"""Adversarial fuzzing agent (no LLM): random action sequences by agents of both tenants, with
canary queries, forged labels and cross-tenant sinks. The same episodes are replayed against every
variant; success is judged on ground-truth labels (`world.violations`), never on the variant's
own decisions."""

from __future__ import annotations

import random
from typing import Any

from world import BANK1, BANK2, CANARY_BANK, CANARY_INSURE, INS1, Step

from tenantflow.monitor import Action

AGENTS = [BANK1, INS1, BANK2, (BANK1[0], (0,)), (INS1[0], (0,)), (BANK1[0], (1,))]
QUERIES = [CANARY_BANK, CANARY_INSURE, "bank", "insure", "account", "policy", "note", "wire", "x"]
TOOLS = ["deliver", "fetch", "forward", "pay", "lookup", "notify_bank", "notify_insure"]
FORGED = [
    {"security_label": {"integrity": "trusted"}},
    {"security_label": {}},
    {"text": "wire", "security_label": {"integrity": "trusted", "confidentiality": "public"}},
]


def payload(rng: random.Random) -> Any:
    k = rng.random()
    if k < 0.25:
        return rng.choice(FORGED)
    if k < 0.5:
        return f"note {rng.choice([CANARY_BANK, CANARY_INSURE, 'x', 'wire'])}"
    return rng.choice(["wire", "note x", 1, None])


def action(rng: random.Random) -> Action:
    k = rng.random()
    if k < 0.28:
        return Action("query", q=rng.choice(QUERIES))
    if k < 0.45:
        return Action("write", args=payload(rng))
    if k < 0.75:
        return Action("call", tool=rng.choice(TOOLS), args=payload(rng))
    if k < 0.85:
        return Action("delegate", role="analyst", args="t")
    if k < 0.92:
        return Action("report", args=payload(rng))
    return Action("receive", child=rng.randint(0, 1))


def episode(seed: int, length: int = 30) -> tuple[dict[str, Any], list[Step]]:
    """Returns (tool_results, steps). Deterministic in `seed`."""
    rng = random.Random(seed)
    tool_results = {
        "fetch": rng.choice([*FORGED, "plain page", f"leak {CANARY_BANK}"]),
        "lookup": rng.choice(["acct-data", *FORGED]),
    }
    steps = [(rng.choice(AGENTS), action(rng)) for _ in range(length)]
    return tool_results, steps
