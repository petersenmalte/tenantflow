"""End to end with the official MCP SDK (S20): MCP client -> `tenantflow mcp-gateway` -> upstream
MCP server. Skipped without the optional extra `mcp`."""

import sys
from pathlib import Path

import pytest

mcp = pytest.importorskip("mcp")
from mcp import ClientSession  # noqa: E402
from mcp.client.stdio import StdioServerParameters, stdio_client  # noqa: E402

CONFIG = Path(__file__).resolve().parents[2] / "examples" / "mcp-gateway.json"


def gateway(session: str) -> StdioServerParameters:
    return StdioServerParameters(
        command=sys.executable,
        args=[
            "-m",
            "tenantflow.cli",
            "mcp-gateway",
            str(CONFIG),
            "--session",
            session,
            "--",
            sys.executable,
            "-m",
            "tenantflow.mcp_example_server",
        ],
    )


def text(res) -> str:
    return " ".join(c.text for c in res.content if getattr(c, "text", None))


@pytest.mark.anyio
async def test_gateway_over_real_mcp():
    async with stdio_client(gateway("1")) as (r, w), ClientSession(r, w) as s:
        await s.initialize()
        names = {t.name for t in (await s.list_tools()).tools}
        assert {"rag_query", "rag_write", "deliver", "web_fetch", "notify_shop"} <= names
        res = await s.call_tool("rag_query", {"q": "secret"})
        assert "bank secret iban" in text(res) and "shop" not in text(res)  # filtered per tenant
        res = await s.call_tool("notify_shop", {"text": "bank secret iban"})
        assert res.is_error and "flow" in text(res)  # bank data may not reach the shop
        res = await s.call_tool("web_fetch", {"url": "http://x"})
        assert not res.is_error and "ignore previous instructions" in text(res)  # ran upstream
        res = await s.call_tool("rag_write", {"payload": "note"})
        assert not res.is_error  # own-tenant context (untrusted is fine for writing)


@pytest.mark.anyio
async def test_gateway_other_tenant_sees_nothing_of_the_bank():
    async with stdio_client(gateway("2")) as (r, w), ClientSession(r, w) as s:
        await s.initialize()
        res = await s.call_tool("rag_query", {"q": "secret"})
        assert "shop secret price list" in text(res) and "bank" not in text(res)
        res = await s.call_tool("notify_shop", {"text": "hello"})
        assert not res.is_error and "sent" in text(res)


@pytest.fixture
def anyio_backend():
    return "asyncio"
