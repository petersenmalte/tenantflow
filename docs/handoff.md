# Handoff

Overwritten at the end of every session. Keep it short; the next session reads only this, CLAUDE.md and TASKS.md.

- **Last task:** F3 – Theorem (d) refinement (done)
- **Model:** claude-fable-5-1
- **State:** new file `lean/TenantFlow/Proofs/Refinement.lean` (imported from `TenantFlow.lean`):
  abstraction `α` (`Exec.Config.abs`, `Exec.Data.abs`, `Exec.State.abs`, plus `Label.abs`, `ToolInfo.abs`, `Doc.abs`,
  `AgentState.abs`, `Event.abs`), projection `Exec.Response.abs` (`⌊·⌋`), commutation lemmas (`Label.abs_join`,
  `Label.abs_joinAll`, `readable_abs`, `toolInfo_abs`, `assocFind_setAgent`, `State.abs_setAgent`, `readableDocs_abs`,
  `rank_abs`, `assocFind_init_root/child`), (d1) `Exec.refines` via `Exec.refines_aux` (one `split` per branch of
  `Exec.step`), (d2) `Exec.refines_init`, corollaries `Exec.refines_denied`, `Exec.refines_trace`, `Exec.refines_ghost`,
  `Model.Reachable.ghost`, `Model.Step.not_allowed_of_denied`. `lake build` clean, zero warnings, no sorry.
  Axioms recorded in `docs/proof-status.md`.
- **Changes outside the new file (F3):** `Exec.insertByScore`/`sortByScore` generic in the element type;
  `Exec.AgentId`/`Exec.childId` removed in favour of the model's (opened in `Exec` and `Exec.Sanity`);
  `mem_insertByScore`/`mem_sortByScore` restated generically. `Exec.step`, `runTrace`, `init` unchanged.
- **Design decisions F3:** see `docs/spec.md` changelog "F3 details" (`Data` abstracted too, model `rank` := Exec top-k).
- **Not done (optional F4):** (c) for `Exec` traces; needs `Exec.run`, which does not exist.
- **Open `sorry`s (file:line, lemma):** none
- **What was tried (if stuck):** –
- **Next task:** S1 [SONNET] – Lean oracle executable (F1a done; S1 and S2 are unblocked). The remaining FABLE work is
  optional (F4); no FABLE task should start above 55 USD.
