"""Sanity tests for the benchmark harness itself (small sample; the full run is bench/run.py)."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "bench"))

import fuzz  # noqa: E402
import suites  # noqa: E402
from world import VARIANTS, make, run, violations  # noqa: E402


def test_scripted_attacks_and_utility():
    for sc in [*suites.SUITE1, *suites.SUITE2]:
        mon = make("tenantflow", sc.tool_results, sc.extra_docs)
        assert not sc.check(mon, run(mon, sc.steps)), sc.id
        assert not violations(mon).any, sc.id
    for sc in suites.SUITE3:
        for v in VARIANTS:
            mon = make(v, sc.tool_results, sc.extra_docs)
            assert sc.check(mon, run(mon, sc.steps)), (v, sc.id)


def test_harness_detects_attacks_on_baselines():
    for v in ("none", "cedar-only"):
        hits = [
            sc.check(*(lambda m: (m, run(m, sc.steps)))(make(v, sc.tool_results)))
            for sc in suites.SUITE1
        ]
        assert all(hits), v


def test_fuzz_tenantflow_never_violates_baselines_do():
    eps = [fuzz.episode(i) for i in range(60)]
    counts = {}
    for v in VARIANTS:
        counts[v] = 0
        for tr, steps in eps:
            mon = make(v, tr)
            run(mon, steps)
            counts[v] += violations(mon).any
    assert counts["tenantflow"] == 0
    assert all(counts[v] > 0 for v in ("none", "cedar-only", "fides"))


def test_fuzz_is_deterministic():
    assert fuzz.episode(7) == fuzz.episode(7)
