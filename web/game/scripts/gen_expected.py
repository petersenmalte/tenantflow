"""Writes tests/fixtures/expected.json: reference outputs for the game's scripted attacks.

For each scenario in tests/fixtures/scenarios.json, runs the Python reference (Monitor for
TenantFlow, Baseline for none/cedar-only/fides). The TenantFlow output is also checked against
the Lean oracle (`lake exe oracle`, or $TF_ORACLE) when it is built, and the oracle's output is
stored then.

Usage (from the repository root): ``cd python && uv run python ../web/game/scripts/gen_expected.py``
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

from tenantflow.baselines import Baseline
from tenantflow.monitor import Action, monitor_from_scenario, parse_agent, run_scenario

HERE = Path(__file__).resolve().parent
FIX = HERE.parent / "tests" / "fixtures"
ORACLE = Path(os.environ.get("TF_ORACLE", HERE.parents[2] / "lean/.lake/build/bin/oracle"))


def run_mode(sc: dict, mode: str) -> dict:
    if mode == "tenantflow":
        return run_scenario(sc)
    mon = Baseline.from_monitor(mode, monitor_from_scenario(sc))
    decisions = []
    for step in sc["trace"]:
        a = parse_agent(step["agent"])
        resp = mon.step(a, Action.from_json(step["action"]))
        st = mon.agents.get(a)
        decisions.append(
            {
                "agent": step["agent"],
                "response": resp.to_json(),
                "denied": resp.denied,
                "ctx": None if st is None else st.ctx.to_json(),
            }
        )
    return {"decisions": decisions, "final": mon.state_json()}


def main() -> int:
    scenarios = json.loads((FIX / "scenarios.json").read_text())
    expected = {}
    for item in scenarios:
        sc = item["scenario"]
        modes = {m: run_mode(sc, m) for m in ("none", "cedar-only", "fides", "tenantflow")}
        if ORACLE.exists():
            res = subprocess.run(
                [str(ORACLE)], input=json.dumps(sc), text=True, capture_output=True, check=True
            )
            oracle = json.loads(res.stdout)
            if oracle != json.loads(json.dumps(modes["tenantflow"])):
                print(f"MISMATCH python vs oracle in {item['id']}", file=sys.stderr)
                return 1
            modes["tenantflow"] = oracle
        else:
            print("oracle not built; storing the Python output for tenantflow", file=sys.stderr)
        expected[item["id"]] = json.loads(json.dumps(modes))
    (FIX / "expected.json").write_text(json.dumps(expected, indent=1, sort_keys=True) + "\n")
    print("wrote", len(expected), "scenarios")
    return 0


if __name__ == "__main__":
    sys.exit(main())
