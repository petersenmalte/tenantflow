# Handoff

Overwritten at the end of every session. Keep it short; the next session reads only this, CLAUDE.md and TASKS.md.

- **Last task:** S3 – Differential testing (done)
- **Model:** claude-sonnet-5-5
- **State:** `python/src/tenantflow/` has `monitor` (port of `Exec.step`, `run_scenario` = oracle format),
  `adapter` (RAG index), `cedar` (cedarpy authorizer), `gateway` (JSON-RPC proxy), `example_server`.
  `uv run pytest -q` and `ruff check` green; the 5 oracle traces agree with the Python monitor.
- **Notes for S3:** use `tenantflow.monitor.run_scenario(sc)`; compare `kind`/`denied`/`ctx`/`final`, not `reason`.
  Payload number formatting (floats) in `payload_text` may differ from Lean's `compress`; avoid floats in generators.
- **Open `sorry`s:** none
- **Next task:** S4 [SONNET] – baselines (S7 CLI and S8 CI are also unblocked).
- **S3:** `tests/test_differential.py` (needs `cd lean && lake build oracle`); only finding is D1 in `docs/discrepancies.md`.
