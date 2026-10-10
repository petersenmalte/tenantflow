"""Minimal MCP gateway: JSON-RPC proxy that puts Cedar + the flow monitor in front of an upstream.

Only ``tools/list`` and ``tools/call`` are handled. Every call goes through ``Monitor.step``
(Cedar per-call check first, then the information-flow check); only allowed calls reach the
upstream. The agent identity comes from ``params._meta.agent``
(``{"session": sid, "path": [...]}``), set by the trusted session layer, never by model output.
Result labels come from the tool registry.

Built-in tools: ``rag_query`` (``{"q": ...}``), ``rag_write`` (``{"payload": ...}``).
All other tools are registered in the monitor's registry and forwarded to
``upstream(name, arguments)``.
"""

from __future__ import annotations

import json
import sys
from collections.abc import Callable
from typing import Any, TextIO

from .monitor import Action, Monitor, parse_agent

Upstream = Callable[[str, Any], Any]

BUILTIN = {"rag_query": "query", "rag_write": "write"}


class Gateway:
    def __init__(self, monitor: Monitor, upstream: Upstream) -> None:
        self.monitor = monitor
        self.upstream = upstream

    def _tool_list(self) -> list[dict[str, Any]]:
        names = [*BUILTIN, "deliver", *self.monitor.tools]
        return [{"name": n, "inputSchema": {"type": "object"}} for n in names]

    def _action(self, name: str, args: dict[str, Any]) -> Action:
        if name == "rag_query":
            return Action("query", q=str(args.get("q", "")))
        if name == "rag_write":
            return Action("write", args=args.get("payload"))
        return Action("call", tool=name, args=args)

    def call(self, agent_json: dict[str, Any], name: str, args: dict[str, Any]) -> dict[str, Any]:
        agent = parse_agent(agent_json)
        resp = self.monitor.step(agent, self._action(name, args))
        if resp.denied:
            return {"isError": True, "content": [{"type": "text", "text": f"denied: {resp.value}"}]}
        if resp.kind == "payloads":
            value: Any = resp.value
        elif resp.kind == "payload":  # ext tool with a labelled result: run it upstream
            value = self.upstream(name, args)
        else:
            if name not in BUILTIN and name != "deliver":
                self.upstream(name, args)  # effect-only ext tool
            elif name == "deliver":
                self.upstream(name, args)
            value = None
        return {"isError": False, "content": [{"type": "text", "text": json.dumps(value)}]}

    def handle(self, req: dict[str, Any]) -> dict[str, Any] | None:
        rid = req.get("id")
        method = req.get("method")
        if rid is None:  # notification
            return None
        if method == "tools/list":
            result: Any = {"tools": self._tool_list()}
        elif method == "tools/call":
            p = req.get("params") or {}
            agent = (p.get("_meta") or {}).get("agent")
            if agent is None:
                return {
                    "jsonrpc": "2.0",
                    "id": rid,
                    "error": {"code": -32602, "message": "missing _meta.agent"},
                }
            result = self.call(agent, p.get("name", ""), p.get("arguments") or {})
        else:
            return {
                "jsonrpc": "2.0",
                "id": rid,
                "error": {"code": -32601, "message": f"unknown method {method}"},
            }
        return {"jsonrpc": "2.0", "id": rid, "result": result}

    def serve(self, inp: TextIO = sys.stdin, out: TextIO = sys.stdout) -> None:
        """Line-delimited JSON-RPC over stdio."""
        for line in inp:
            if not line.strip():
                continue
            resp = self.handle(json.loads(line))
            if resp is not None:
                out.write(json.dumps(resp) + "\n")
                out.flush()
