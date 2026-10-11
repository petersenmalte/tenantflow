# Handoff

- **Last task:** S10 – browser game (done): see `web/game/README.md`; `npm test` green, CI `game` job has a lockfile.
Overwritten at the end of every session. Keep it short; the next session reads only this, CLAUDE.md and TASKS.md.

- **Model:** claude-sonnet-5-5
- **State:** `python/src/tenantflow/` has `monitor` (port of `Exec.step`, `run_scenario` = oracle format),
  `adapter` (RAG index), `cedar` (cedarpy authorizer), `gateway` (JSON-RPC proxy), `example_server`.
  `uv run pytest -q` and `ruff check` green; the 5 oracle traces agree with the Python monitor.
- **Notes for S3:** use `tenantflow.monitor.run_scenario(sc)`; compare `kind`/`denied`/`ctx`/`final`, not `reason`.
  Payload number formatting (floats) in `payload_text` may differ from Lean's `compress`; avoid floats in generators.
- **Open `sorry`s:** none
- **S3:** `tests/test_differential.py` (needs `cd lean && lake build oracle`); only finding is D1 in `docs/discrepancies.md`.
- **S4:** `tenantflow.baselines.Baseline` (same `step` API as `Monitor`, ground-truth labels recorded but not enforced); FIDES = re-implementation of 1.5.0 label logic, see `bench/README.md`.
- **S5:** results in `bench/results/results.json`, plots `summary-{light,dark}.png`; read the caveats in `bench/README.md` before quoting numbers (TenantFlow's 0 % is predicted by the theorems, not independent evidence).
- **S8:** CI not yet observed on GitHub (first run happens on push); check the Actions tab / `gh run list`.

- **Next task:** S9 [SONNET] Quarto deck (the game's "Why?" links expect slide order of the brief, see TASKS.md S10 notes); then O2. S6 only after asking the user.
