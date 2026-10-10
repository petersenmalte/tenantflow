"""Baselines for the benchmark (S5): ``none``, ``cedar-only``, ``fides`` (and ``tenantflow``).

All baselines share the :class:`~tenantflow.monitor.Monitor` data structures and API
(``step(agent, action) -> Response``, ``state_json()``) so the benchmark can swap them.
They keep the *ground-truth* tenant label (the one TenantFlow computes) in ``AgentState.ctx``
and in the events, but do **not** enforce it. The benchmark can thus measure leaks without
trusting the baseline.

* ``none``       - no checks; the shared index is not filtered per tenant.
* ``cedar-only`` - per-call Cedar check only; index not filtered, no flow tracking.
* ``fides``      - Cedar + a re-implementation of the label logic of the FIDES middleware of
  Microsoft Agent Framework (``agent-framework-core`` 1.5.0): integrity (trusted/untrusted) and
  confidentiality (public/private) labels, joined to the most restrictive. Labels embedded in
  data (``{"security_label": {...}}``) are *accepted* (tier 1) and absent fields default to
  ``trusted`` (``ContentLabel.from_dict``). There is no tenant in the labels.

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
    """Tier 1: a label embedded in the data itself (the forgeable part)."""
    if isinstance(payload, dict) and isinstance(payload.get("security_label"), dict):
        try:
            return FidesLabel.from_dict(payload["security_label"])
        except ValueError:
            return None
    return None


class Baseline(Monitor):
    """Monitor-compatible baseline; ``mode`` is ``none``, ``cedar-only`` or ``fides``."""

    def __init__(self, mode: str, *args: Any, **kwargs: Any) -> None:
        if mode not in ("none", "cedar-only", "fides"):
            raise ValueError(f"unknown baseline '{mode}'")
        self.mode = mode
        self.fides_ctx: dict[AgentId, FidesLabel] = {}
        self.fides_docs: dict[int, FidesLabel] = {}  # id(Doc) -> label as FIDES sees it
        super().__init__(*args, **kwargs)
        for a in self.agents:
            self.fides_ctx[a] = FidesLabel(TRUSTED, PUBLIC)
        for d in self.index:
            self.fides_docs[id(d)] = FidesLabel(TRUSTED, PRIVATE)

    @classmethod
    def from_monitor(cls, mode: str, mon: Monitor) -> Baseline:
        return cls(
            mode,
            sessions=mon.sessions,
            tools=mon.tools,
            tool_results=mon.tool_results,
            authorize=mon.authorize,
            top_k=mon.top_k,
            index=copy.deepcopy(mon.index),
        )

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
            resp = Response("ok")
            result_fl: FidesLabel | None = None
            if act.tool != DELIVER and info.result is not None:
                value = copy.deepcopy(self.tool_results.get(act.tool))
                resp = Response("payload", value)
                # tier 1 (embedded, forgeable) > tier 2 (tool's declared source integrity)
                result_fl = embedded_label(value) or FidesLabel(info.result.integ, PRIVATE)
            self.events.append(Event(t, act.tool, act.args, st.ctx))  # ground truth label
            if info.result is not None:
                st.ctx = st.ctx.join(info.result)
            if fides and result_fl is not None:
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
                self.fides_docs[id(doc)] = embedded_label(act.args) or FidesLabel(
                    fctx.integrity, PRIVATE
                )
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
