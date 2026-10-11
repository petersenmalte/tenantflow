"""MCP gateway on the official MCP Python SDK (optional extra ``mcp``): an MCP server that puts
Cedar + the flow monitor in front of an upstream MCP server (S20).

One gateway process serves one authenticated session (``--session``), set by whoever starts it
(the trusted session layer, assumption A1), never by the model. A client may address a child agent
of that session with ``_meta["tenantflow/path"]`` (a list of child indices); it cannot leave its
session. Every ``tools/call`` goes through ``Monitor.step``; only allowed calls reach the upstream.
Result labels come from the tool registry in the config, not from the upstream's output.

Tools offered: ``rag_query`` ``{"q"}``, ``rag_write`` ``{"payload"}``, ``deliver`` (answer to the
own user), and every registry tool that the upstream also offers (with the upstream's input schema).

The JSON-RPC proxy in ``gateway.py`` (no SDK) is kept for the tests that run without the extra.
"""

from __future__ import annotations

import json
from typing import Any

from mcp import ClientSession, types
from mcp.client.stdio import StdioServerParameters, stdio_client
from mcp.server.lowlevel import Server
from mcp.server.stdio import stdio_server

from .check import load_config
from .monitor import Action, Monitor, monitor_from_scenario

BUILTIN_SCHEMAS = {
    "rag_query": {"type": "object", "properties": {"q": {"type": "string"}}, "required": ["q"]},
    "rag_write": {"type": "object", "properties": {"payload": {}}, "required": ["payload"]},
    "deliver": {"type": "object", "properties": {"text": {"type": "string"}}},
}


def _text(value: Any, error: bool = False) -> types.CallToolResult:
    text = value if isinstance(value, str) else json.dumps(value)
    return types.CallToolResult(content=[types.TextContent(type="text", text=text)], is_error=error)


def _path(meta: Any) -> tuple[int, ...]:
    raw = (
        (meta or {}).get("tenantflow/path")
        if isinstance(meta, dict)
        else getattr(meta, "tenantflow/path", None)
    )
    if not isinstance(raw, list) or not all(isinstance(n, int) and n >= 0 for n in raw):
        return ()
    return tuple(raw)


def action_for(name: str, args: dict[str, Any]) -> Action:
    if name == "rag_query":
        return Action("query", q=str(args.get("q", "")))
    if name == "rag_write":
        return Action("write", args=args.get("payload"))
    return Action("call", tool=name, args=args)


def make_server(
    mon: Monitor, session: str, up: ClientSession, upstream_tools: list[types.Tool]
) -> Server:
    offered = {t.name: t for t in upstream_tools if t.name in mon.tools}

    async def list_tools(ctx: Any, params: Any) -> types.ListToolsResult:
        tools = [types.Tool(name=n, input_schema=s) for n, s in BUILTIN_SCHEMAS.items()]
        tools += [
            types.Tool(name=t.name, description=t.description, input_schema=t.input_schema)
            for t in offered.values()
        ]
        return types.ListToolsResult(tools=tools)

    async def call_tool(ctx: Any, params: types.CallToolRequestParams) -> types.CallToolResult:
        name, args = params.name, dict(params.arguments or {})
        if name not in BUILTIN_SCHEMAS and name not in offered:
            return _text(f"denied: unknown tool {name}", error=True)
        agent = (session, _path(params.meta))
        resp = mon.step(agent, action_for(name, args))
        if resp.denied:
            return _text(f"denied: {resp.value}", error=True)
        if name == "rag_query":
            return _text(resp.value)
        if name == "rag_write":
            return _text("written")
        if name == "deliver":
            return _text(args.get("text", "delivered"))
        result = await up.call_tool(name, args)  # allowed: run it upstream
        return types.CallToolResult(content=result.content, is_error=result.is_error)

    return Server(
        "tenantflow-gateway", version="0.1", on_list_tools=list_tools, on_call_tool=call_tool
    )


async def serve(config_path: str, session: str, upstream: list[str]) -> None:
    from pathlib import Path

    cfg = json.loads(Path(config_path).read_text())
    sc, authorizer = load_config(cfg, str(Path(config_path).parent))
    mon = monitor_from_scenario(sc, authorizer)
    if (session, ()) not in mon.agents:
        raise SystemExit(f"unknown session {session}")
    params = StdioServerParameters(command=upstream[0], args=upstream[1:])
    async with stdio_client(params) as (ur, uw), ClientSession(ur, uw) as up:
        await up.initialize()
        tools = (await up.list_tools()).tools
        server = make_server(mon, session, up, tools)
        async with stdio_server() as (r, w):
            await server.run(r, w, server.create_initialization_options())
