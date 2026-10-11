# tenantflow (Python)

Python package for TenantFlow: trusted adapter, monitor (port of the Lean `Exec.step`), Cedar per-call check,
MCP-style gateway, baselines and the `tenantflow` CLI. Guarantees come from the Lean proofs (`lean/`, `docs/spec.md`)
and hold only under their assumptions (trusted adapter, trusted session, no side channels). The Python code is
tested against the Lean oracle (`tests/test_differential.py`), not proven.

```
uv sync            # add --extra fides to cross-check the FIDES baseline against agent-framework-core 1.5.0
uv run pytest -q
```

## `tenantflow check`

Bounded search for an action sequence that crosses tenants (or runs a trusted-only tool on untrusted context)
although every call is allowed by your Cedar policy.

```
uv run tenantflow check ../examples/shared-rag.json                       # system under test: Cedar only
uv run tenantflow check ../examples/shared-rag.json --enforce tenantflow  # Cedar + flow monitor
```

Config = oracle scenario without `trace` (`docs/oracle-format.md`): `sessions`, `tools`, `index`, and either
`cedar` (allow-list) or `cedarPolicies` (Cedar text, or a path to a `.cedar` file relative to the config).
Output: the counterexample (steps and violated condition) with exit code 1, or `no leak in the model` with exit
code 0. `--depth` (default 4) and `--max-nodes` bound the search; "no leak" means none within the bounds, in the
model. It is not a proof. Note the model counts it as a violation when an agent that holds its tenant's data
calls a tool observed by another tenant.

### GitHub Action

```yaml
name: tenantflow-check
on: [pull_request]
jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: astral-sh/setup-uv@v5
      - run: uv run --project python tenantflow check path/to/config.json --enforce tenantflow
```

Use the default `--enforce cedar` to see whether your policies alone already allow a leak (exit code 1 = yes);
`--enforce tenantflow` is the regression check for the monitored deployment.

## MCP gateway (`tenantflow mcp-gateway`)

An MCP server built on the official MCP Python SDK that puts Cedar and the flow monitor in front of an upstream MCP
server. One gateway process serves one authenticated session; a client can address child agents of that session via
`_meta["tenantflow/path"]` but cannot leave the session. Labels come from the registry in the config, never from the
upstream's output.

```
uv sync --extra mcp
uv run --extra mcp tenantflow mcp-gateway ../examples/mcp-gateway.json --session 1 -- \
    python -m tenantflow.mcp_example_server
```

Tools offered: `rag_query`, `rag_write`, `deliver`, and every registry tool the upstream also offers. Tested end to end
with the SDK's client (`tests/test_mcp_gateway.py`: per-tenant filtering, a flow denial, an allowed upstream call).
The older JSON-RPC proxy (`gateway.py`, no SDK) stays for the tests that run without the extra.

## Decisions and limits (S2, S20)

* **Cedar schema:** hand-written (`cedar.py`), not generated with the `cedar-for-agents` schema generator. The demo has
  a handful of tools with one role and a fixed action naming (`call:<tool>`, `query`, ...); the generator pays off for
  many real MCP tools with typed inputs. Nothing in the guarantees depends on Cedar (it is an opaque per-call
  authorizer in the proofs).
* **Session identity** is whatever started the gateway (`--session`): assumption A1 (trusted session). Child paths
  from `_meta` stay inside that session; impersonating one's own child does not cross tenants but is not authenticated.
* The gateway forwards the upstream's real output; the monitor's labels come from the registry. A wrong registry entry
  (assumption A2) is not detected.
* Only `tools/list` and `tools/call` are mediated; resources and prompts of the upstream are not exposed.
