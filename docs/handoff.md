# Handoff

Overwritten at the end of every session. Keep it short; the next session reads only this, CLAUDE.md and TASKS.md.

- **Last task:** F2 – Theorem (c) noninterference (done)
- **Model:** claude-fable-5-1
- **State:** new file `lean/TenantFlow/Proofs/Noninterference.lean` (imported from `TenantFlow.lean`):
  §7.4 definitions (`Strategy`, `RunState`, `stepFn`, `histUpdate`, `runStep`, `runAll`, `initRun`, `run`, `LowEq`,
  `obs`), relation `Sim` (`Clean`/`Tainted` per agent id, `EqUpToOutbox`), generic preservation lemmas `Sim.left`
  (absent-or-tainted agent moves in one run) and `Sim.lock` (clean agent moves in both runs), per-action case analyses
  `Step.leftOK`/`Step.lockOK`, `Allowed.transport`, `Sim.of_lowEq_init`, and `noninterference`.
  `lake build` clean, zero warnings, no sorry. Axioms recorded in `docs/proof-status.md`.
- **Design decisions F2:** see `docs/spec.md` changelog "F2 details" (clause (iv) child existence, outbox exception in
  (iii), session tenant `B` inside `Clean`, `Fresh` in the relation, `run` via `stepFn := Classical.choose (Step.total …)`).
- **For F3 (theorem (d)):** `Step.eq_stepFn` (`Step.det` packaged as an equation on `stepFn`) may be handy for (d1);
  `Allowed.transport` shows which hypotheses of each `Allowed` row depend on the agent state only.
- **Open `sorry`s (file:line, lemma):** none
- **What was tried (if stuck):** –
- **Next task:** F3 [FABLE] – Theorem (d) refinement (budget target 8–10 USD, hard cap; no new FABLE task above 55 USD).
  S1 and S2 [SONNET] are unblocked and can run in parallel on other models.
