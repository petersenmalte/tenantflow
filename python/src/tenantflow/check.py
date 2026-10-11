"""Bounded search for a tenant-crossing call sequence (``tenantflow check``).

Breadth-first search over action sequences of all agents of a configuration. The system under test
is either ``cedar`` (per-call Cedar check only: what you have today) or ``tenantflow`` (Cedar + flow
monitor). A sequence is a counterexample if it ends in a *ground-truth violation*
(:func:`violations`): an agent whose context holds data of a foreign tenant, an event whose label is
not readable by an observer of the tool, or a trusted-only tool run on an untrusted context.

"No leak found" means: none within the depth/node bounds, in the model (assumptions of
``docs/spec.md``). It is a bounded search, not a proof; the proofs are in ``lean/``.
"""

from __future__ import annotations

import copy
import json
from collections import deque
from dataclasses import dataclass, field
from typing import Any

from .baselines import Baseline
from .cedar import CedarAuthorizer
from .monitor import (
    DELIVER,
    TRUSTED,
    Action,
    AgentId,
    Monitor,
    monitor_from_scenario,
)


@dataclass
class Violations:
    confidentiality: bool = False
    integrity: bool = False
    detail: list[str] = field(default_factory=list)

    @property
    def any(self) -> bool:
        return self.confidentiality or self.integrity


def violations(mon: Monitor) -> Violations:
    """Ground truth from the labels every variant records (enforced or not)."""
    v = Violations()
    for a, st in mon.agents.items():
        tenant = mon.sessions[st.session][0]
        if st.ctx.owners - {tenant}:
            v.confidentiality = True
            v.detail.append(f"agent {a} holds data of {sorted(st.ctx.owners - {tenant})}")
    for e in mon.events:
        info = mon.tool_info(e.tenant, e.tool)
        if info is None:
            continue
        if not all(e.label.readable_by(u) for u in info.observers):
            v.confidentiality = True
            v.detail.append(
                f"tool '{e.tool}' called with data of {sorted(e.label.owners)}, "
                f"observed by {sorted(info.observers)}"
            )
        if info.needs_trusted and e.label.integ != TRUSTED:
            v.integrity = True
            v.detail.append(f"trusted-only tool '{e.tool}' ran on an untrusted context")
    return v


def load_config(
    cfg: dict[str, Any], base_dir: str = "."
) -> tuple[dict[str, Any], CedarAuthorizer | None]:
    """Config = oracle scenario without ``trace``. ``cedarPolicies`` (Cedar text or a file path
    ending in ``.cedar``) overrides the ``cedar`` allow-list."""
    sc = dict(cfg)
    sc.setdefault("trace", [])
    pol = sc.pop("cedarPolicies", None)
    if pol is None:
        return sc, None
    if pol.rstrip().endswith(".cedar") and "\n" not in pol and "permit" not in pol:
        from pathlib import Path

        pol = (Path(base_dir) / pol).read_text()
    return sc, CedarAuthorizer(pol)


def _candidates(mon: Monitor, queries: list[str]) -> list[tuple[AgentId, Action]]:
    out: list[tuple[AgentId, Action]] = []
    tools = [DELIVER, *mon.tools]
    for a, st in sorted(mon.agents.items()):
        out += [(a, Action("query", q=q)) for q in queries]
        out.append((a, Action("write", args="probe")))
        out += [(a, Action("call", tool=t, args="probe")) for t in tools]
        if len(a[1]) < 1 and st.next_child < 1:
            out.append((a, Action("delegate", role=st.role, args="task")))
        if st.parent is not None:
            out.append((a, Action("report", args="probe")))
        if st.next_child:
            out.append((a, Action("receive", child=0)))
    return out


def _key(mon: Monitor) -> str:
    return json.dumps(mon.state_json(), sort_keys=True, default=str)


def describe(a: AgentId, act: Action) -> str:
    who = f"session {a[0]}" + (f" child {list(a[1])}" if a[1] else "")
    detail = {"query": f" q={act.q!r}", "call": f" {act.tool}", "delegate": f" role={act.role}"}
    return f"{who}: {act.op}{detail.get(act.op, '')}"


def search(
    cfg: dict[str, Any],
    authorize: CedarAuthorizer | None = None,
    enforce: str = "cedar",
    depth: int = 4,
    max_nodes: int = 20000,
) -> dict[str, Any]:
    """Result keys: leak, trace, violations, explored, complete (search finished within bounds)."""
    if enforce not in ("cedar", "tenantflow"):
        raise ValueError("enforce must be 'cedar' or 'tenantflow'")
    mon0 = monitor_from_scenario(cfg, authorize)
    if enforce == "cedar":
        mon0 = Baseline.from_monitor("cedar-only", mon0)
    queries = sorted({" ".join(str(d.payload).split()) for d in mon0.index if d.payload})
    seen = {_key(mon0)}
    frontier: deque[tuple[Monitor, list[tuple[AgentId, Action, str]]]] = deque([(mon0, [])])
    explored = 0
    complete = True
    for _ in range(depth):
        nxt: deque = deque()
        while frontier:
            mon, path = frontier.popleft()
            for a, act in _candidates(mon, queries):
                m = copy.deepcopy(mon)
                resp = m.step(a, act)
                explored += 1
                if resp.denied:
                    continue
                step = (a, act, resp.kind)
                v = violations(m)
                if v.any:
                    return {
                        "leak": True,
                        "enforce": enforce,
                        "trace": [describe(x, y) + f" -> {k}" for x, y, k in [*path, step]],
                        "violations": v.detail,
                        "explored": explored,
                        "complete": True,
                    }
                k = _key(m)
                if k in seen:
                    continue
                seen.add(k)
                if explored > max_nodes:
                    complete = False
                    continue
                nxt.append((m, [*path, step]))
        frontier = nxt
    return {
        "leak": False,
        "enforce": enforce,
        "trace": [],
        "violations": [],
        "explored": explored,
        "complete": complete,
    }
