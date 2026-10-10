# Handoff

Overwritten at the end of every session. Keep it short; the next session reads only this, CLAUDE.md and TASKS.md.

- **Last task:** F1b – Theorem (b) no forgery / no laundering (done)
- **Model:** claude-fable-5-1
- **State:** `lean/TenantFlow/Proofs.lean` now also has `no_launder` ((b2), pointwise form of the join),
  `Fresh` (child ids fresh; `Fresh.init`, `Fresh.setAgent`, `Fresh.delegate`, `Fresh.step`, `Reachable.fresh`),
  `Step.ctx_mono`, `Reachable.ctx_mono`, `ctx_mono`, `GReachable.base`, `ctx_mono_ghost`, `child_ctx_eq`.
  `lake build` clean, zero warnings, no sorry. Axioms recorded in `docs/proof-status.md`.
- **Design decisions F1b:** (b2) is stated pointwise over origins (equivalent to the set join). `ctx_mono` is on
  `Reachable cfg D (init cfg D) s` + `Reachable cfg D s s'` (base states; ghost version via `GReachable.base`).
  (b1) dropped per spec §7.3 cost rule (D8 + sanity examples 4 and 6 remain the evidence).
- **For F2 (theorem (c)):** `Fresh` and `GReachable.base` are reusable. `Inv.reachable` gives label soundness.
  Note the spec's "absent or tainted" clause in the simulation relation (§7.4) and the `rank_mem` side condition.
- **Open `sorry`s (file:line, lemma):** none
- **What was tried (if stuck):** –
- **Next task:** F2 [FABLE] – Theorem (c). Session must start with the current Fable spend (gate G2 ≤ 45 USD).
  S1 and S2 [SONNET] are unblocked and can run in parallel on other models.
