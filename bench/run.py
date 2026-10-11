"""Run all suites and the fuzzer against every variant; write bench/results/results.json.

Usage (repo root):  cd python && uv run python ../bench/run.py [--episodes N] [--seed S]
"""

from __future__ import annotations

import argparse
import json
import math
import platform
import statistics
import subprocess
import sys
import time
from datetime import UTC, datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import fuzz  # noqa: E402
import suites  # noqa: E402
from world import VARIANTS, make, run, violations  # noqa: E402

RESULTS = Path(__file__).resolve().parent / "results"


def wilson(k: int, n: int, z: float = 1.96) -> list[float]:
    if n == 0:
        return [0.0, 0.0]
    p = k / n
    d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return [round(max(0.0, c - h), 4), round(min(1.0, c + h), 4)]


def scripted(scenarios: list[suites.Scenario]) -> dict:
    out = {}
    for v in VARIANTS:
        per = {}
        for sc in scenarios:
            mon = make(v, sc.tool_results, sc.extra_docs)
            log = run(mon, sc.steps)
            per[sc.id] = bool(sc.check(mon, log))
        k = sum(per.values())
        out[v] = {
            "n": len(per),
            "k": k,
            "rate": k / len(per),
            "ci95": wilson(k, len(per)),
            "per_scenario": per,
        }
    return out


def fuzzing(episodes: int, seed: int) -> dict:
    eps = [fuzz.episode(seed * 1_000_003 + i) for i in range(episodes)]
    out = {}
    for v in VARIANTS:
        conf = integ = anyv = 0
        for tr, steps in eps:
            mon = make(v, tr)
            run(mon, steps)
            vio = violations(mon)
            conf += vio.confidentiality
            integ += vio.integrity
            anyv += vio.any
        out[v] = {
            "episodes": episodes,
            "confidentiality": {"k": conf, "rate": conf / episodes, "ci95": wilson(conf, episodes)},
            "integrity": {"k": integ, "rate": integ / episodes, "ci95": wilson(integ, episodes)},
            "any": {"k": anyv, "rate": anyv / episodes, "ci95": wilson(anyv, episodes)},
        }
    return out


def latency(episodes: int, seed: int) -> dict:
    """Wall-clock per decision (`step`, includes the Cedar check via cedarpy), same episodes."""
    eps = [fuzz.episode(seed * 1_000_003 + i) for i in range(min(episodes, 200))]
    out = {}
    for v in VARIANTS:
        ts: list[int] = []
        for tr, steps in eps:
            mon = make(v, tr)
            for a, act in steps:
                t0 = time.perf_counter_ns()
                mon.step(a, act)
                ts.append(time.perf_counter_ns() - t0)
        us = sorted(t / 1000 for t in ts)

        def q(p: float, us: list[float] = us) -> float:
            return us[min(len(us) - 1, int(p * len(us)))]

        out[v] = {
            "n": len(us),
            "mean_us": round(statistics.fmean(us), 2),
            "p50_us": round(q(0.5), 2),
            "p95_us": round(q(0.95), 2),
            "p99_us": round(q(0.99), 2),
        }
    return out


def latency_monitor_only(episodes: int, seed: int) -> dict:
    """TenantFlow's monitor without the Cedar call (authorize stubbed to allow), same episodes as `latency`.

    Separates the monitor's own cost from Cedar's (S19); all decisions run the full flow checks."""
    eps = [fuzz.episode(seed * 1_000_003 + i) for i in range(min(episodes, 200))]
    ts: list[int] = []
    for tr, steps in eps:
        mon = make("tenantflow", tr)
        mon.authorize = lambda role, action: True
        for a, act in steps:
            t0 = time.perf_counter_ns()
            mon.step(a, act)
            ts.append(time.perf_counter_ns() - t0)
    us = sorted(t / 1000 for t in ts)
    return {
        "n": len(us),
        "mean_us": round(statistics.fmean(us), 2),
        "p50_us": round(us[len(us) // 2], 2),
        "p95_us": round(us[min(len(us) - 1, int(0.95 * len(us)))], 2),
        "p99_us": round(us[min(len(us) - 1, int(0.99 * len(us)))], 2),
    }


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--episodes", type=int, default=2000)
    ap.add_argument("--seed", type=int, default=1)
    args = ap.parse_args()
    rev = subprocess.run(
        ["git", "rev-parse", "--short", "HEAD"], capture_output=True, text=True, check=False
    ).stdout.strip()
    dirty = bool(
        subprocess.run(
            ["git", "status", "--porcelain", "--", "bench", "python/src"],
            capture_output=True,
            text=True,
            check=False,
        ).stdout.strip()
    )
    res = {
        "meta": {
            "dirty": dirty,
            "date": datetime.now(UTC).isoformat(timespec="seconds"),
            "git": rev,
            "python": platform.python_version(),
            "machine": platform.machine(),
            "episodes": args.episodes,
            "seed": args.seed,
            "episode_length": 30,
            "variants": VARIANTS,
        },
        "leak": scripted(suites.SUITE1),
        "forgery": scripted(suites.SUITE2),
        "utility": scripted(suites.SUITE3),
        "fuzz": fuzzing(args.episodes, args.seed),
        "latency": latency(args.episodes, args.seed),
        "latency_monitor_only": latency_monitor_only(args.episodes, args.seed),
    }
    RESULTS.mkdir(exist_ok=True)
    (RESULTS / "results.json").write_text(json.dumps(res, indent=1, sort_keys=True) + "\n")
    for k in ("leak", "forgery", "utility"):
        print(k, {v: f"{res[k][v]['k']}/{res[k][v]['n']}" for v in VARIANTS})
    print("fuzz any", {v: res["fuzz"][v]["any"]["rate"] for v in VARIANTS})
    print("p50 us", {v: res["latency"][v]["p50_us"] for v in VARIANTS})
    print("monitor only p50/p99 us", res["latency_monitor_only"]["p50_us"], res["latency_monitor_only"]["p99_us"])
    if dirty:
        print("WARNING: bench/ or python/src has uncommitted changes; meta.git does not identify the code")


if __name__ == "__main__":
    main()
