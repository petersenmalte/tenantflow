"""Command line: ``tenantflow check config.json``."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from .check import load_config, search


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="tenantflow")
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("check", help="search for a tenant-crossing call sequence")
    c.add_argument("config", help="JSON: sessions, tools, index, cedar / cedarPolicies (no trace)")
    c.add_argument("--depth", type=int, default=4, help="max number of actions (default 4)")
    c.add_argument("--max-nodes", type=int, default=20000)
    c.add_argument(
        "--enforce",
        choices=["cedar", "tenantflow"],
        default="cedar",
        help="system under test: Cedar only (default) or Cedar + flow monitor",
    )
    c.add_argument("--json", action="store_true", help="machine-readable output")
    args = ap.parse_args(argv)

    path = Path(args.config)
    cfg, authorize = load_config(json.loads(path.read_text()), str(path.parent))
    res = search(cfg, authorize, args.enforce, args.depth, args.max_nodes)
    if args.json:
        print(json.dumps(res, indent=1))
    elif res["leak"]:
        print(f"LEAK found against {args.enforce} ({res['explored']} actions explored):")
        for i, s in enumerate(res["trace"], 1):
            print(f"  {i}. {s}")
        for d in res["violations"]:
            print(f"  => {d}")
    else:
        bound = "" if res["complete"] else " (search truncated at --max-nodes)"
        print(
            f"no leak in the model within depth {args.depth} against {args.enforce}{bound} "
            f"({res['explored']} actions explored). Bounded search, not a proof."
        )
    return 1 if res["leak"] else 0


if __name__ == "__main__":
    sys.exit(main())
