"""Sanity tests for the benchmark harness itself (small sample; the full run is bench/run.py)."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "bench"))

import fuzz  # noqa: E402
import suites  # noqa: E402
from world import VARIANTS, make, run, violations  # noqa: E402


def test_scripted_attacks_and_utility():
    for sc in [*suites.SUITE1, *suites.SUITE2]:
        mon = make("tenantflow", sc.tool_results, sc.extra_docs, sc.fides)
        assert not sc.check(mon, run(mon, sc.steps)), sc.id
        assert not violations(mon).any, sc.id
    # FIDES with auto_hide_untrusted (default) hides fetched content from the agent, so a workflow
    # that reads a web page cannot complete: a real utility cost of that design, not a harness bug.
    expected_fail = {("fides", "3b-fetch-then-deliver")}
    for sc in suites.SUITE3:
        for v in VARIANTS:
            mon = make(v, sc.tool_results, sc.extra_docs, sc.fides)
            assert sc.check(mon, run(mon, sc.steps)) != ((v, sc.id) in expected_fail), (v, sc.id)


def test_fides_forgery_only_under_poc_conditions():
    """Suite 2 against FIDES: the bypass needs the APIsec PoC conditions (2a, 2b)."""
    got = {}
    for sc in suites.SUITE2:
        mon = make("fides", sc.tool_results, sc.extra_docs, sc.fides)
        got[sc.id] = sc.check(mon, run(mon, sc.steps))
    assert got == {
        "2a-argument-label-poc": True,
        "2b-missing-field-default": True,
        "2c-default-hiding": False,
        "2d-monotone-context": False,
        "2e-unlabelled-control": False,
    }
    for v in ("none", "cedar-only"):
        for sc in suites.SUITE2:
            mon = make(v, sc.tool_results, sc.extra_docs, sc.fides)
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
