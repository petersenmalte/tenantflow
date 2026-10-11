"""Shared synthetic world for all suites: two tenants on one RAG index (synthetic data only)."""

from __future__ import annotations

from typing import Any

from tenantflow.baselines import Baseline, FidesConfig
from tenantflow.cedar import CedarAuthorizer
from tenantflow.check import Violations, violations  # noqa: F401 (re-exported)
from tenantflow.monitor import (
    TRUSTED,
    UNTRUSTED,
    Action,
    AgentId,
    Doc,
    Label,
    Monitor,
    Response,
    ToolInfo,
)

VARIANTS = ["none", "cedar-only", "fides", "tenantflow"]
CANARY_BANK = "CANARY-BANK"
CANARY_INSURE = "CANARY-INSURE"
BANK1: AgentId = ("1", ())
INS1: AgentId = ("2", ())
BANK2: AgentId = ("3", ())

ACTIONS = [
    "call:deliver",
    "call:fetch",
    "call:forward",
    "call:pay",
    "call:lookup",
    "call:notify_bank",
    "call:notify_insure",
    "query",
    "write",
    "delegate",
    "report",
    "receive",
]
# Cedar permits every action of the world for the role: each call is individually allowed.
CEDAR = CedarAuthorizer.from_allow_list([("analyst", a) for a in ACTIONS])


def tools() -> dict[str, ToolInfo]:
    return {
        # external, attacker-influenced content: result is untrusted
        "fetch": ToolInfo(frozenset(), False, Label(frozenset(), UNTRUSTED)),
        # relays its argument to an external ticket system and returns the reply: untrusted result.
        # In the FIDES deployment it declares no source_integrity (a "transformation" tool).
        "forward": ToolInfo(frozenset(), False, Label(frozenset(), UNTRUSTED)),
        # sensitive action that must only run on trusted context
        "pay": ToolInfo(frozenset(), True, None),
        # internal, trusted data source
        "lookup": ToolInfo(frozenset(), False, Label(frozenset(), TRUSTED)),
        # sinks observed by one tenant (cross-tenant exfiltration channel when called by the other)
        "notify_bank": ToolInfo(frozenset({"bank"}), False, None),
        "notify_insure": ToolInfo(frozenset({"insure"}), False, None),
    }


# FIDES deployment of the world: `forward` declares no source_integrity, shipped defaults otherwise.
FIDES_DEFAULT = FidesConfig(frozenset({"forward"}), auto_hide=True)
# The conditions of the APIsec proof of concept: additionally auto_hide_untrusted=False.
FIDES_POC = FidesConfig(frozenset({"forward"}), auto_hide=False)


def make(
    variant: str,
    tool_results: dict[str, Any] | None = None,
    extra_docs: list[Doc] | None = None,
    fides: FidesConfig | None = None,
) -> Monitor:
    mon = Monitor(
        sessions={
            "1": ("bank", "u1", "analyst"),
            "2": ("insure", "u2", "analyst"),
            "3": ("bank", "u3", "analyst"),
        },
        tools=tools(),
        tool_results=tool_results or {},
        authorize=lambda r, a: True if variant == "none" else CEDAR(r, a),
        top_k=3,
        index=[
            Doc(Label(frozenset({"bank"})), f"bank account {CANARY_BANK} iban"),
            Doc(Label(frozenset({"insure"})), f"insure policy {CANARY_INSURE} claim"),
            *(extra_docs or []),
        ],
    )
    if variant == "tenantflow":
        return mon
    return Baseline.from_monitor(variant, mon, fides or FIDES_DEFAULT)


Step = tuple[AgentId, Action]
Log = list[tuple[AgentId, Action, Response]]


def run(mon: Monitor, steps: list[Step]) -> Log:
    return [(a, act, mon.step(a, act)) for a, act in steps]


def call(a: AgentId, tool: str, args: Any = None) -> Step:
    return a, Action("call", tool=tool, args=args)


def query(a: AgentId, q: str) -> Step:
    return a, Action("query", q=q)


def write(a: AgentId, payload: Any) -> Step:
    return a, Action("write", args=payload)


# ---- ground truth (computed from the labels every variant records, enforced or not) -------------
