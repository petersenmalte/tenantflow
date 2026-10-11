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
