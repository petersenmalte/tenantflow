"""Baselines for the benchmark (S5): ``none``, ``cedar-only``, ``fides`` (and ``tenantflow``).

All baselines share the :class:`~tenantflow.monitor.Monitor` data structures and API
(``step(agent, action) -> Response``, ``state_json()``) so the benchmark can swap them.
They keep the *ground-truth* tenant label (the one TenantFlow computes) in ``AgentState.ctx``
and in the events, but do **not** enforce it. The benchmark can thus measure leaks without
trusting the baseline.

* ``none``       - no checks; the shared index is not filtered per tenant.
* ``cedar-only`` - per-call Cedar check only; index not filtered, no flow tracking.
* ``fides``      - Cedar + a re-implementation of the label logic of the FIDES middleware of
  Microsoft Agent Framework (``agent-framework-core`` 1.5.0, ``LabelTrackingFunctionMiddleware``),
  following its source (S15): integrity (trusted/untrusted) and confidentiality (public/private)
  labels, the context label only ever joins. The label of a tool result is the tool's declared
  ``source_integrity`` (tier 2); for a tool *without* a declaration it is the join of the labels
  found in the call arguments (tier 3: any dict with a ``security_label`` key, parsed by
  ``ContentLabel.from_dict``, missing fields default to ``trusted``; variable references carry the
  label of the hidden result), else ``untrusted``. This argument scan is the forgery path
  described by APIsec Labs. With ``auto_hide_untrusted`` (default on) an untrusted result is
  replaced by a variable reference and does not taint the context. Tier 1 (labels in a result
  item's ``additional_properties``) is framework metadata, not attacker data, and is not modelled.
  There is no tenant in the labels.

The FIDES baseline is a **re-implementation**, not the middleware itself (see ``bench/README.md``).
``tests/test_baselines.py`` cross-checks its label functions against the real package when the
optional extra ``fides`` (``agent-framework-core==1.5.0``) is installed.
"""

from __future__ import annotations

import copy
from dataclasses import dataclass
from typing import Any

from .monitor import (
    DELIVER,
    TRUSTED,
    UNTRUSTED,
    Action,
    AgentId,
    AgentState,
    Doc,
    Event,
    Monitor,
    Response,
    child_id,
    denied,
    join_all,
)

# ---- FIDES label logic (mirrors agent_framework.security 1.5.0) ----------------------------------

PUBLIC, PRIVATE = "public", "private"  # confidentiality; the real enum also has user_identity
_CONF_RANK = {PUBLIC: 0, PRIVATE: 1}


@dataclass(frozen=True)
class FidesLabel:
    integrity: str = TRUSTED
    confidentiality: str = PUBLIC

    @staticmethod
    def from_dict(d: dict[str, Any]) -> FidesLabel:
        """``ContentLabel.from_dict``: missing ``integrity`` defaults to ``trusted``."""
        integ = d.get("integrity", TRUSTED)
        conf = d.get("confidentiality", PUBLIC)
        if integ not in (TRUSTED, UNTRUSTED) or conf not in _CONF_RANK:
            raise ValueError("bad label")
        return FidesLabel(integ, conf)

    def join(self, o: FidesLabel) -> FidesLabel:
        """``combine_labels``: untrusted if either is, most restrictive confidentiality."""
        integ = UNTRUSTED if UNTRUSTED in (self.integrity, o.integrity) else TRUSTED
        conf = max(self.confidentiality, o.confidentiality, key=_CONF_RANK.__getitem__)
        return FidesLabel(integ, conf)


def embedded_label(payload: Any) -> FidesLabel | None:
    """``ContentLabel.from_dict`` of a dict's ``security_label`` field, or None."""
    if isinstance(payload, dict) and isinstance(payload.get("security_label"), dict):
        try:
            return FidesLabel.from_dict(payload["security_label"])
        except ValueError:
            return None
    return None


@dataclass(frozen=True)
class FidesConfig:
    """Deployment choices of the FIDES middleware that the attack depends on."""

    undeclared: frozenset[str] = frozenset()  # tools without a source_integrity declaration
    auto_hide: bool = True  # auto_hide_untrusted (the shipped default)

    @staticmethod
    def from_json(j: dict[str, Any] | None) -> FidesConfig:
        j = j or {}
        return FidesConfig(frozenset(j.get("undeclared", [])), bool(j.get("autoHide", True)))


def is_var(v: Any) -> bool:
    return isinstance(v, dict) and set(v) == {"var"} and isinstance(v["var"], str)


def join_fides(labels: list[FidesLabel]) -> FidesLabel:
    out = FidesLabel()
    for lab in labels:
        out = out.join(lab)
    return out


def fides_conf_join(a: FidesLabel, b: FidesLabel) -> str:
    return a.join(b).confidentiality


class Baseline(Monitor):
    """Monitor-compatible baseline; ``mode`` is ``none``, ``cedar-only`` or ``fides``."""

    def __init__(
        self, mode: str, *args: Any, fides: FidesConfig | None = None, **kwargs: Any
    ) -> None:
        if mode not in ("none", "cedar-only", "fides"):
            raise ValueError(f"unknown baseline '{mode}'")
        self.mode = mode
        self.fides_cfg = fides or FidesConfig()
        self.fides_ctx: dict[AgentId, FidesLabel] = {}
        self.fides_docs: dict[int, FidesLabel] = {}  # id(Doc) -> label as FIDES sees it
        # hidden results: variable id -> (FIDES label, ground-truth label of the hidden data)
        self.fides_vars: dict[str, tuple[FidesLabel, Any]] = {}
        super().__init__(*args, **kwargs)
        for a in self.agents:
            self.fides_ctx[a] = FidesLabel(TRUSTED, PUBLIC)
        for d in self.index:
            self.fides_docs[id(d)] = FidesLabel(TRUSTED, PRIVATE)

    @classmethod
    def from_monitor(cls, mode: str, mon: Monitor, fides: FidesConfig | None = None) -> Baseline:
        return cls(
            mode,
            fides=fides,
            sessions=mon.sessions,
            tools=mon.tools,
            tool_results=mon.tool_results,
            authorize=mon.authorize,
            top_k=mon.top_k,
            index=copy.deepcopy(mon.index),
        )

    def _arg_labels(self, value: Any) -> tuple[list[FidesLabel], list[Any]]:
        """``_get_input_labels``: labels in the call arguments, plus ground-truth labels of the
        hidden results that the arguments reference."""
        fl: list[FidesLabel] = []
        gt: list[Any] = []

        def walk(v: Any) -> None:
            if is_var(v) and v["var"] in self.fides_vars:
                f, g = self.fides_vars[v["var"]]
                fl.append(f)
                gt.append(g)
            elif isinstance(v, dict):
                lab = embedded_label(v)
                if lab is None and "security_label" not in v and isinstance(v.get("label"), dict):
                    lab = embedded_label({"security_label": v["label"]})  # legacy key
                if lab is not None:
                    fl.append(lab)
                for x in v.values():
                    walk(x)
            elif isinstance(v, list | tuple):
                for x in v:
                    walk(x)

        walk(value)
        return fl, gt

    def _cedar_ok(self, role: str, act: Action) -> bool:
        return self.mode == "none" or self.authorize(role, act.name)

    def step(self, a: AgentId, act: Action) -> Response:  # noqa: C901
        st = self.agents.get(a)
        if st is None:
            return denied("unknown agent")
        sess = self.sessions.get(st.session)
        if sess is None:
            return denied("unknown session")
        t = sess[0]
        fides = self.mode == "fides"
        fctx = self.fides_ctx.get(a, FidesLabel())
        cedar = self._cedar_ok(st.role, act)

        if act.op == "call":
            info = self.tool_info(t, act.tool)
            if info is None:
                return denied("unregistered tool")
            if not cedar:
                return denied("cedar")
            if fides and info.needs_trusted and fctx.integrity != TRUSTED:
                return denied("fides: untrusted context")
            arg_fl, arg_gt = self._arg_labels(act.args) if fides else ([], [])
            event_label = st.ctx
            for g in arg_gt:  # dereferenced hidden data flows into the tool
                event_label = event_label.join(g)
            resp = Response("ok")
            if act.tool != DELIVER and info.result is not None:
                resp = Response("payload", copy.deepcopy(self.tool_results.get(act.tool)))
            self.events.append(Event(t, act.tool, act.args, event_label))  # ground truth label
            if info.result is None:  # nothing comes back to the agent
                return resp
            gt_result = event_label.join(info.result)
            if not fides:
                st.ctx = gt_result
                return resp
            # tier 2: declared source_integrity; tier 3: join of argument labels, else untrusted
            if act.tool not in self.fides_cfg.undeclared:
                result_fl = FidesLabel(info.result.integ, PRIVATE)
            elif arg_fl:
                result_fl = FidesLabel(join_fides(arg_fl).integrity, PRIVATE)
            else:
                result_fl = FidesLabel(UNTRUSTED, PRIVATE)
            if (
                self.fides_cfg.auto_hide
                and result_fl.integrity == UNTRUSTED
                and resp.kind == "payload"
            ):
                vid = f"var_{len(self.fides_vars) + 1}"
                self.fides_vars[vid] = (result_fl, gt_result)
                resp = Response("payload", {"var": vid})  # the agent only sees a reference
                # hidden: the data did not reach the agent, its context is unchanged
                self.fides_ctx[a] = FidesLabel(fctx.integrity, fides_conf_join(fctx, result_fl))
                return resp
            st.ctx = gt_result
            self.fides_ctx[a] = fctx.join(result_fl)
            return resp
        if act.op == "query":
            if not cedar:
                return denied("cedar")
            ranked = self.rank(act.q, list(self.index))  # no tenant filtering
            st.ctx = st.ctx.join(join_all([d.label for d in ranked]))
            if fides:
                for d in ranked:
                    fctx = fctx.join(self.fides_docs.get(id(d), FidesLabel(TRUSTED, PRIVATE)))
                self.fides_ctx[a] = fctx
            return Response("payloads", [d.payload for d in ranked])
        if act.op == "write":
            if not cedar:
                return denied("cedar")
            doc = Doc(st.ctx, act.args)  # ground-truth label, not enforced
            self.index.append(doc)
            if fides:
                self.fides_docs[id(doc)] = FidesLabel(fctx.integrity, PRIVATE)
            return Response("ok")
        if act.op == "delegate":
            if not cedar:
                return denied("cedar")
            n = st.next_child
            st.next_child += 1
            cid = child_id(a, n)
            self.agents[cid] = AgentState(st.session, act.role, st.ctx, 0, [], a)
            self.fides_ctx[cid] = fctx
            return Response("child", n)
        if act.op == "report":
            if st.parent is None:
                return denied("report: agent has no parent")
            st.outbox.append(act.args)
            return Response("ok")
        if act.op == "receive":
            cid = child_id(a, act.child)
            child = self.agents.get(cid)
            if child is None:
                return denied("receive: no such child")
            out, child.outbox = child.outbox, []
            st.ctx = st.ctx.join(child.ctx)
            if fides:
                self.fides_ctx[a] = fctx.join(self.fides_ctx.get(cid, FidesLabel()))
            return Response("payloads", out)
        raise ValueError(f"bad op '{act.op}'")
