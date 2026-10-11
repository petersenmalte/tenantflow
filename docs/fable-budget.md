# Fable budget log

Total budget: **60 USD** (model `claude-fable-5-1`, only for `[FABLE]` tasks).
Gates: G1 ≤ 25 USD after F1a + F1b · G2 ≤ 45 USD after F2 · no new FABLE task above 55 USD.

The user fills in "spent after" at the end of every Fable session (cost shown by Claude Code / usage page).

| Date | Task | Spent before (USD) | Spent after (USD) | Result / note |
|---|---|---|---|---|
| 2026-10-10 | F0 | 0.00 | 6.00 | spec v0.2 + `docs/spec-review.md`; no Lean (toolchain missing in cloud session → S0b) |
| 2026-10-10 | F1a | 6.00 | 14.00 | model, exec monitor, Step.det/total, ghost layer, (a) + (a-int), rank_mem, sanity 1–7; no sorry |
| 2026-10-10 | F1b | 14.00 | 22.00 | (b2) `no_launder`, `ctx_mono`, `child_ctx_eq`, invariant `Fresh`; (b1) dropped; no sorry |
| 2026-10-10 | F2 | 22.00 | 30.00 | (c) `noninterference` with `run`/`LowEq`/`obs` and relation `Sim`; no sorry. G2 passed (30 ≤ 45) |
| 2026-10-10 | F3 | 30.00 | 38.00 | (d) refinement: (d1) forward simulation, (d2) initial states agree; target 8–10 USD, hard cap |
| 2026-10-11 | F4 | 38.00 | 44.00 | (c) for `Exec` traces: `Exec.run`, `run_abs`, `obs_abs`, `Exec.noninterference`; no sorry; target ≤ 8 USD |
| 2026-10-11 | F6 | 44.00 | 50.00 | (e) transparency: `Single`, `LabelFree`, `transparency`, `transparency_step`, `Single.step`, `Exec.transparency_denied`; no sorry; target ≤ 8 USD. Remaining for F7: ≈ 2–3 USD (hard stop 55) |
| 2026-10-11 | F7 | 50.00 | _(user fills in)_ | claim review `docs/claim-review.md` (7 findings, no statement changed), spec A8 + changelog, task S23; target ≤ 3 USD (hard stop 55) |
