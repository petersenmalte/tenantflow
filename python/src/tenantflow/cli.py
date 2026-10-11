"""Command line: ``tenantflow check``, ``tenantflow mcp-gateway config.json --session S -- CMD``."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from .check import load_config, search


def main(argv: list[str] | None = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    upstream: list[str] = []
    if "--" in argv:  # mcp-gateway: everything after -- is the upstream command
        i = argv.index("--")
        argv, upstream = argv[:i], argv[i + 1 :]
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
    g = sub.add_parser(
        "mcp-gateway", help="MCP server: Cedar + flow monitor in front of an upstream MCP server"
    )
    g.add_argument("config", help="JSON config as for `check` (registry, index, Cedar policy)")
    g.add_argument(
        "--session", required=True, help="authenticated session id (set by the session layer)"
    )
    args = ap.parse_args(argv)

    if args.cmd == "mcp-gateway":
        import anyio

        from .mcp_gateway import serve  # needs the optional extra `mcp`

        if not upstream:
            ap.error("mcp-gateway: give the upstream command after --")
        anyio.run(serve, args.config, args.session, upstream)
        return 0

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
