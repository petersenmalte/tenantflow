# Handoff

Overwritten at the end of every session. Keep it short; the next session reads only this, CLAUDE.md and TASKS.md.

- **Last task:** F4 – theorem (c) for `Exec` traces (done).
- **Model:** claude-fable-5-1
- **State:** `lean/TenantFlow/Proofs/NoninterferenceExec.lean` (new, imported from `lean/TenantFlow.lean`):
  `Exec.RunState`/`initRun`/`runStep`/`runAll`/`run` (computable counterpart of `Model.run`; histories hold
  `Response.abs r`, so strategies are reason-blind as in the model), `RunState.abs`, `initRun_abs`, `stepFn_abs`,
  `runStep_abs`, `runAll_abs`, `run_abs`, `observersOf_abs`, `obs_abs`, `Exec.noninterference`
  (`Model.LowEq (α cfg) B (α D₁) (α D₂) → α (obs … (Exec.run … D₁)) = α (obs … (Exec.run … D₂))`).
  `lake build` green, no warnings; `#print axioms` recorded in `docs/proof-status.md`; `uv run pytest -q` green
  (27 passed, 3 skipped). Spec changelog row added (no statement changed).
- **Open `sorry`s:** none
- **Design choice to know:** low equivalence for `Exec` is stated on the abstractions (`Model.LowEq (Config.abs cfg) B
  (Data.abs D₁) (Data.abs D₂)`); no separate executable `Exec.LowEq`. Observable events agree *up to `α`*
  (same tenant, tool, args; labels equal as sets), not as raw `Exec` events.
- **Next task:** S12 [SONNET] (cite `Exec.noninterference` in deck/README/game, drop "F4 open"), then O2 [OPUS]
  final review, then S11 (ask the user for the website repo). S6 only after asking (API costs).
- **Earlier notes still relevant for O2:**
  - S9: Quarto not installed locally, deck and CI job `deck` unobserved; slide 6 quotes the Lean statement by hand;
    results slide repeats the caveats of `bench/README.md`.
  - S10: level 2 stops the leak at the query, not at the write; sandbox has no `vault` tool (registry error A2 is not
    caught by the monitor); fuzzer is bounded search; FIDES mode is a re-implementation; UI only smoke-tested with a
    fake DOM, not in a real browser.
  - S5: read the caveats in `bench/README.md` before quoting numbers (TenantFlow's 0 % is predicted by the theorems).
  - S3: only finding is D1 in `docs/discrepancies.md`.
