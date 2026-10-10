"""Python port of ``TenantFlow.Exec.step`` (``lean/TenantFlow/Exec.lean``).

Same scenario/output JSON as the Lean oracle (``docs/oracle-format.md``). The decision logic is a
line-by-line port; the only injected parts are ``authorize`` (Cedar per-call check, an opaque
``(role, action name) -> bool``), the registry and the toy ``score``.
"""

from __future__ import annotations

import copy
import json
from collections.abc import Callable
from dataclasses import dataclass, field
from typing import Any

TRUSTED = "trusted"
UNTRUSTED = "untrusted"
DELIVER = "deliver"  # reserved built-in tool

AgentId = tuple[str, tuple[int, ...]]
Authorizer = Callable[[str, str], bool]  # (role, action name) -> allowed


@dataclass(frozen=True)
class Label:
    owners: frozenset[str]
    integ: str = TRUSTED

    def join(self, other: Label) -> Label:
        integ = UNTRUSTED if UNTRUSTED in (self.integ, other.integ) else TRUSTED
        return Label(self.owners | other.owners, integ)

    def readable_by(self, tenant: str) -> bool:
        return all(t == tenant for t in self.owners)

    def to_json(self) -> dict[str, Any]:
        return {"owners": sorted(self.owners), "integrity": self.integ}

    @staticmethod
    def from_json(j: dict[str, Any]) -> Label:
        integ = j["integrity"]
        if integ not in (TRUSTED, UNTRUSTED):
            raise ValueError(f"bad integrity '{integ}'")
        return Label(frozenset(j["owners"]), integ)


BOT = Label(frozenset(), TRUSTED)


def join_all(labels: list[Label]) -> Label:
    out = BOT
    for label in labels:
        out = out.join(label)
    return out


@dataclass(frozen=True)
class ToolInfo:
    observers: frozenset[str]
    needs_trusted: bool = False
    result: Label | None = None


@dataclass
class Doc:
    label: Label
    payload: Any


@dataclass
class AgentState:
    session: str
    role: str
    ctx: Label
    next_child: int = 0
    outbox: list[Any] = field(default_factory=list)
    parent: AgentId | None = None


@dataclass
class Event:
    tenant: str
    tool: str
    args: Any
    label: Label


@dataclass
class Response:
    kind: str  # payload | payloads | child | ok | denied
    value: Any = None  # payload: value, payloads: list, child: n, denied: reason

    @property
    def denied(self) -> bool:
        return self.kind == "denied"

    def to_json(self) -> dict[str, Any]:
        match self.kind:
            case "payload":
                return {"kind": "payload", "value": self.value}
            case "payloads":
                return {"kind": "payloads", "values": self.value}
            case "child":
                return {"kind": "child", "n": self.value}
            case "ok":
                return {"kind": "ok"}
            case _:
                return {"kind": "denied", "reason": self.value}


def denied(reason: str) -> Response:
    return Response("denied", reason)


# ---- actions -------------------------------------------------------------------------------------


@dataclass(frozen=True)
class Action:
    op: str  # call | query | write | delegate | report | receive
    tool: str = ""  # call
    args: Any = None  # call args / write+report payload / delegate task
    q: str = ""  # query
    role: str = ""  # delegate
    child: int = 0  # receive

    @property
    def name(self) -> str:
        return f"call:{self.tool}" if self.op == "call" else self.op

    @staticmethod
    def from_json(j: dict[str, Any]) -> Action:
        op = j["op"]
        match op:
            case "call":
                return Action("call", tool=j["tool"], args=j.get("args"))
            case "query":
                return Action("query", q=j["q"])
            case "write" | "report":
                return Action(op, args=j.get("payload"))
            case "delegate":
                return Action("delegate", role=j["role"], args=j.get("task"))
            case "receive":
                n = j["child"]
                if not isinstance(n, int) or isinstance(n, bool) or n < 0:
                    raise ValueError("bad child index")
                return Action("receive", child=n)
            case _:
                raise ValueError(f"bad op '{op}'")


# ---- toy embedding -------------------------------------------------------------------------------


def payload_text(p: Any) -> str:
    # Lean's Json.compress: no whitespace, object keys sorted.
    if isinstance(p, str):
        return p
    return json.dumps(p, separators=(",", ":"), sort_keys=True, ensure_ascii=False)


def score(q: str, p: Any) -> int:
    pt = payload_text(p).split()
    return sum(1 for t in q.split() if t in pt)


# ---- monitor -------------------------------------------------------------------------------------


def child_id(a: AgentId, n: int) -> AgentId:
    return (a[0], (*a[1], n))


@dataclass
class Monitor:
    sessions: dict[str, tuple[str, str, str]]  # sid -> (tenant, user, role)
    tools: dict[str, ToolInfo] = field(default_factory=dict)
    tool_results: dict[str, Any] = field(default_factory=dict)
    authorize: Authorizer = lambda role, action: True  # noqa: E731
    top_k: int = 3
    index: list[Doc] = field(default_factory=list)
    agents: dict[AgentId, AgentState] = field(default_factory=dict)
    events: list[Event] = field(default_factory=list)

    def __post_init__(self) -> None:
        if not self.agents:
            for sid, (tenant, _user, role) in self.sessions.items():
                self.agents[(sid, ())] = AgentState(sid, role, Label(frozenset({tenant})))

    def tool_info(self, tenant: str, tool: str) -> ToolInfo | None:
        if tool == DELIVER:
            return ToolInfo(frozenset({tenant}), False, None)
        return self.tools.get(tool)

    def rank(self, q: str, docs: list[Doc]) -> list[Doc]:
        # sorted() is stable; descending score keeps input order among ties (= insertByScore).
        return sorted(docs, key=lambda d: -score(q, d.payload))[: self.top_k]

    def step(self, a: AgentId, act: Action) -> Response:
        st = self.agents.get(a)
        if st is None:
            return denied("unknown agent")
        sess = self.sessions.get(st.session)
        if sess is None:
            return denied("unknown session")
        t = sess[0]
        cedar = self.authorize(st.role, act.name)

        if act.op == "call":
            info = self.tool_info(t, act.tool)
            if info is None:
                return denied("unregistered tool")
            if not cedar:
                return denied("cedar")
            if not all(st.ctx.readable_by(u) for u in info.observers):
                return denied("flow: context not readable by every observer of the tool")
            if info.needs_trusted and st.ctx.integ != TRUSTED:
                return denied("flow: tool requires trusted input")
            if act.tool != DELIVER and info.result is not None:
                resp = Response("payload", copy.deepcopy(self.tool_results.get(act.tool)))
            else:
                resp = Response("ok")
            self.events.append(Event(t, act.tool, act.args, st.ctx))
            if info.result is not None:
                st.ctx = st.ctx.join(info.result)
            return resp
        if act.op == "query":
            if not cedar:
                return denied("cedar")
            readable = [d for d in self.index if d.label.readable_by(t)]
            ranked = self.rank(act.q, readable)
            st.ctx = st.ctx.join(join_all([d.label for d in ranked]))
            return Response("payloads", [d.payload for d in ranked])
        if act.op == "write":
            if not cedar:
                return denied("cedar")
            if not st.ctx.readable_by(t):
                return denied("flow: tainted agent may not write")
            self.index.append(Doc(st.ctx, act.args))
            return Response("ok")
        if act.op == "delegate":
            if not cedar:
                return denied("cedar")
            n = st.next_child
            st.next_child += 1
            self.agents[child_id(a, n)] = AgentState(st.session, act.role, st.ctx, 0, [], a)
            return Response("child", n)
        if act.op == "report":
            if st.parent is None:
                return denied("report: agent has no parent")
            st.outbox.append(act.args)
            return Response("ok")
        if act.op == "receive":
            child = self.agents.get(child_id(a, act.child))
            if child is None:
                return denied("receive: no such child")
            out = child.outbox
            child.outbox = []
            st.ctx = st.ctx.join(child.ctx)
            return Response("payloads", out)
        raise ValueError(f"bad op '{act.op}'")

    # ---- serialisation, same shape as the oracle's `final` ----

    def state_json(self) -> dict[str, Any]:
        agents = [
            {
                "agent": agent_json(a),
                "ctx": s.ctx.to_json(),
                "role": s.role,
                "nextChild": s.next_child,
                "outbox": s.outbox,
                "parent": None if s.parent is None else agent_json(s.parent),
            }
            for a, s in sorted(self.agents.items())
        ]
        return {
            "agents": agents,
            "index": [{"label": d.label.to_json(), "payload": d.payload} for d in self.index],
            "events": [
                {"tenant": e.tenant, "tool": e.tool, "args": e.args, "label": e.label.to_json()}
                for e in self.events
            ],
        }


def agent_json(a: AgentId) -> dict[str, Any]:
    return {"session": a[0], "path": list(a[1])}


def parse_agent(j: dict[str, Any]) -> AgentId:
    return (j["session"], tuple(j.get("path") or ()))


# ---- scenario runner (oracle-compatible) ---------------------------------------------------------


def monitor_from_scenario(sc: dict[str, Any], authorize: Authorizer | None = None) -> Monitor:
    sessions: dict[str, tuple[str, str, str]] = {}
    for s in sc["sessions"]:
        # Lean `assocFind` takes the first entry for a duplicate session id.
        sessions.setdefault(s["sid"], (s["tenant"], s["user"], s.get("role") or "default"))
    tools: dict[str, ToolInfo] = {}
    for k, v in (sc.get("tools") or {}).items():
        res = v.get("result")
        tools[k] = ToolInfo(
            frozenset(v["observers"]),
            bool(v.get("needsTrusted", False)),
            None if res is None else Label.from_json(res),
        )
    if authorize is None:
        cedar = sc.get("cedar", "allow_all")
        if cedar is None or cedar == "allow_all":
            authorize = allow_all
        else:
            allowed = {(r["role"], r["action"]) for r in cedar["allow"]}
            authorize = lambda role, action: (role, action) in allowed  # noqa: E731
    mon = Monitor(
        sessions=sessions,
        tools=tools,
        tool_results=dict(sc.get("toolResults") or {}),
        authorize=authorize,
        top_k=sc.get("topK", 3),
        index=[Doc(Label.from_json(d["label"]), d.get("payload")) for d in sc.get("index") or []],
    )
    return mon


def allow_all(role: str, action: str) -> bool:
    return True


def run_scenario(sc: dict[str, Any], authorize: Authorizer | None = None) -> dict[str, Any]:
    """Run an oracle scenario; returns the oracle's output object."""
    mon = monitor_from_scenario(sc, authorize)
    decisions = []
    for step in sc["trace"]:
        a = parse_agent(step["agent"])
        resp = mon.step(a, Action.from_json(step["action"]))
        st = mon.agents.get(a)
        decisions.append(
            {
                "agent": agent_json(a),
                "response": resp.to_json(),
                "denied": resp.denied,
                "ctx": None if st is None else st.ctx.to_json(),
            }
        )
    return {"decisions": decisions, "final": mon.state_json()}
