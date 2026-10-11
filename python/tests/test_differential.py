"""Differential testing: Python monitor vs. the Lean oracle (`lake exe oracle`).

Skipped if the oracle binary is not built (`cd lean && lake build oracle`). On a mismatch the
assertion message contains the (Hypothesis-minimized) scenario; record it in
`docs/discrepancies.md`.
Compared: decision `kind`/`denied`/`ctx` and the whole `final` state; denial `reason` is ignored.
"""

from __future__ import annotations

import copy
import json
import os
import subprocess
from pathlib import Path

import pytest
from hypothesis import HealthCheck, given, settings
from hypothesis import strategies as st

from tenantflow.monitor import run_scenario

ROOT = Path(__file__).resolve().parents[2]
ORACLE = Path(os.environ.get("TF_ORACLE", ROOT / "lean/.lake/build/bin/oracle"))

pytestmark = pytest.mark.skipif(not ORACLE.exists(), reason="oracle not built (lake build oracle)")

TENANTS = ["a", "b", "c"]
ROLES = ["r1", "r2"]
EXT = ["fetch", "lookup", "notify"]
WORDS = ["x", "y", "z", "secret"]
ACTIONS = [
    "call:deliver",
    *(f"call:{t}" for t in EXT),
    "query",
    "write",
    "delegate",
    "report",
    "receive",
]


def oracle(sc: dict) -> dict:
    p = subprocess.run(
        [str(ORACLE)], input=json.dumps(sc), capture_output=True, text=True, timeout=30, check=False
    )
    return json.loads(p.stdout)


def normalise(out: dict) -> dict:
    out = copy.deepcopy(out)
    for d in out["decisions"]:
        d["response"].pop("reason", None)
    return out


labels = st.builds(
    lambda o, i: {"owners": sorted(set(o)), "integrity": i},
    st.lists(st.sampled_from(TENANTS), max_size=2),
    st.sampled_from(["trusted", "untrusted"]),
)
payloads = st.one_of(
    st.lists(st.sampled_from(WORDS), max_size=3).map(" ".join),
    st.integers(-3, 3),
    st.none(),
    st.dictionaries(st.sampled_from(WORDS), st.sampled_from(WORDS), max_size=2),
    st.lists(st.sampled_from(WORDS), max_size=2),
)
queries = st.lists(st.sampled_from(WORDS), max_size=3).map(" ".join)

agents = st.builds(
    lambda s, p: {"session": s, "path": p},
    st.sampled_from(["1", "2", "3", "9"]),  # "9" is unknown
    st.lists(st.integers(0, 2), max_size=2),
)
actions = st.one_of(
    st.builds(
        lambda t, a: {"op": "call", "tool": t, "args": a},
        st.sampled_from(["deliver", *EXT, "ghost"]),
        payloads,
    ),
    st.builds(lambda q: {"op": "query", "q": q}, queries),
    st.builds(lambda p: {"op": "write", "payload": p}, payloads),
    st.builds(
        lambda r, t: {"op": "delegate", "role": r, "task": t}, st.sampled_from(ROLES), payloads
    ),
    st.builds(lambda p: {"op": "report", "payload": p}, payloads),
    st.builds(lambda c: {"op": "receive", "child": c}, st.integers(0, 2)),
)
tools = st.fixed_dictionaries(
    {},
    optional={
        t: st.fixed_dictionaries(
            {
                "observers": st.lists(st.sampled_from(TENANTS), max_size=2),
                "needsTrusted": st.booleans(),
                "result": st.one_of(st.none(), labels),
            }
        )
        for t in EXT
    },
)
cedar = st.one_of(
    st.just("allow_all"),
    st.builds(
        lambda al: {"allow": [{"role": r, "action": a} for r, a in al]},
        st.lists(
            st.tuples(st.sampled_from([*ROLES, "default"]), st.sampled_from(ACTIONS)), max_size=12
        ),
    ),
)
scenarios = st.builds(
    lambda sess, tl, res, c, k, idx, tr: {
        "sessions": sess,
        "tools": tl,
        "toolResults": res,
        "cedar": c,
        "topK": k,
        "index": idx,
        "trace": tr,
    },
    st.lists(
        st.tuples(st.sampled_from(TENANTS), st.sampled_from([*ROLES, "default"])),
        min_size=1,
        max_size=3,
    ).map(
        lambda rows: [
            {"sid": str(i + 1), "tenant": t, "user": f"u{i + 1}", "role": r}
            for i, (t, r) in enumerate(rows)
        ]
    ),
    tools,
    st.fixed_dictionaries({}, optional={t: payloads for t in EXT}),
    cedar,
    st.integers(0, 4),
    st.lists(st.builds(lambda lb, p: {"label": lb, "payload": p}, labels, payloads), max_size=5),
    st.lists(st.builds(lambda a, ac: {"agent": a, "action": ac}, agents, actions), max_size=25),
)


# The generator above sends most steps to unknown agents ("9", random paths), so most decisions are
# "unknown agent" denials. This variant uses existing roots and their first children only and mostly
# allow_all, so that the flow checks themselves are exercised (S16 finding).
valid_agents = st.builds(
    lambda s, p: {"session": s, "path": p},
    st.sampled_from(["1", "2", "3"]),
    st.sampled_from([[], [], [], [], [0]]),
)
valid_actions = st.one_of(
    actions,
    st.builds(lambda t, a: {"op": "call", "tool": t, "args": a}, st.sampled_from(EXT), payloads),
    st.builds(lambda q: {"op": "query", "q": q}, queries),
)
scenarios_valid = st.builds(
    lambda sc, c, tr: {**sc, "cedar": c, "trace": tr},
    scenarios,
    st.one_of(st.just("allow_all"), st.just("allow_all"), cedar),
    st.lists(
        st.builds(lambda a, ac: {"agent": a, "action": ac}, valid_agents, valid_actions),
        min_size=3,
        max_size=25,
    ),
)


@settings(
    max_examples=int(os.environ.get("TF_EXAMPLES", 300)),
    deadline=None,
    suppress_health_check=[HealthCheck.too_slow, HealthCheck.data_too_large],
)
@given(scenarios_valid)
def test_python_matches_oracle_valid_agents(sc):
    exp = oracle(sc)
    assert "error" not in exp, exp
    got = run_scenario(sc)
    assert normalise(got) == normalise(exp), json.dumps(sc)


@settings(
    max_examples=int(os.environ.get("TF_EXAMPLES", 300)),
    deadline=None,
    suppress_health_check=[HealthCheck.too_slow, HealthCheck.data_too_large],
)
@given(scenarios)
def test_python_matches_oracle(sc):
    exp = oracle(sc)
    assert "error" not in exp, exp
    got = run_scenario(sc)
    assert normalise(got) == normalise(exp), json.dumps(sc)


def test_hand_traces_match_oracle():
    for f in sorted((ROOT / "lean/Oracle/tests").glob("t*.json")):
        sc = json.loads(f.read_text())
        assert normalise(run_scenario(sc)) == normalise(oracle(sc)), f.name
