"""Writes tests/fixtures/corpus.json.gz: random scenarios for the JS monitor (task S16).

Scenarios are drawn (derandomised, so the corpus is reproducible) from the Hypothesis strategies of
python/tests/test_differential.py (S3 and its valid-agent variant), the ones used for Python vs. the oracle. Stored per scenario:
the oracle output (TenantFlow) and the Python baseline outputs (none, cedar-only, fides).

Usage: cd python && uv run python ../web/game/scripts/gen_corpus.py [N valid-agent scenarios, default 2000]   (needs `lake build oracle`)
"""
# ruff: noqa: E501

from __future__ import annotations

import gzip
import json
import subprocess
import sys
from pathlib import Path

from hypothesis import HealthCheck, given, settings

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "python" / "tests"))
sys.path.insert(0, str(HERE))

from gen_expected import ORACLE, run_mode  # noqa: E402

from test_differential import scenarios, scenarios_valid  # noqa: E402


def main() -> int:
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 2000
    if not ORACLE.exists():
        print(f"oracle not found at {ORACLE}; run `cd lean && lake build oracle`", file=sys.stderr)
        return 1
    drawn: list[dict] = []
    # 400 from the S3 generator (mostly error paths), n from the valid-agent variant (flow checks)
    for strategy, count in ((scenarios, 400), (scenarios_valid, n)):

        @settings(
            max_examples=count,
            derandomize=True,
            database=None,
            deadline=None,
            suppress_health_check=list(HealthCheck),
        )
        @given(strategy)
        def collect(sc: dict) -> None:
            drawn.append(sc)

        collect()
    # FIDES deployment per scenario (ignored by the oracle and by TenantFlow): undeclared tools and
    # auto_hide_untrusted vary deterministically, so that tiers 2/3 and hiding are all exercised.
    ext = ["fetch", "lookup", "notify"]
    for i, sc in enumerate(drawn):
        sc["fides"] = {
            "undeclared": [t for k, t in enumerate(ext) if (i >> k) & 1],
            "autoHide": i % 3 != 0,
        }
    corpus = []
    for sc in drawn:
        res = subprocess.run(
            [str(ORACLE)], input=json.dumps(sc), text=True, capture_output=True, check=True
        )
        out = {"tenantflow": json.loads(res.stdout)}
        for m in ("none", "cedar-only", "fides"):
            out[m] = json.loads(json.dumps(run_mode(sc, m)))
        corpus.append({"scenario": sc, "expected": out})
    data = json.dumps(corpus, separators=(",", ":"), sort_keys=True).encode()
    with gzip.GzipFile(HERE.parent / "tests/fixtures/corpus.json.gz", "wb", mtime=0) as f:
        f.write(data)
    print(
        f"wrote {len(corpus)} scenarios ({sum(len(c['scenario']['trace']) for c in corpus)} steps)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
