# Handoff

Overwritten at the end of every session. Keep it short; the next session reads only this, CLAUDE.md and TASKS.md.

- **Last task:** S9 – Quarto deck (done, **not rendered**: see `web/deck/README.md`; run `quarto render` and look at every slide).
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

- **S10 deviations and limits:** (1) Level 2: under TenantFlow the write is allowed and the leak is stopped at the query
  (label + filter), unlike the brief's "blocks step 2". (2) Sandbox has no `vault` tool: a bank-labelled tool callable by an
  insurer principal is a registry error (A2), not caught by the monitor. (3) Fuzzer = bounded search, not a proof.
  (4) FIDES mode is a re-implementation. (5) "Why?" deck links are placeholders until S9 (`rules.js`, `slide(...)`).
  (6) The UI was only smoke-tested with a fake DOM in Node, **not in a real browser** (Chrome extension was not connected): open
  `web/game/index.html` and check layout, dark mode, level 5 before publishing (S11).

- **Next task:** O2 [OPUS] final review (claims vs. proofs), then S11 (ask the user for the website repo). S6 only after asking (API costs).
- **S9 deviations and limits:** Quarto not installed locally, so the deck and the CI job `deck` are unobserved; slide 3 shows the chip in three boxes instead of moving it; slide 6 quotes the Lean statement by hand; results slide repeats the caveats of `bench/README.md`.
