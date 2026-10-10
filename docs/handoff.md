# Handoff

Overwritten at the end of every session. Keep it short; the next session reads only this, CLAUDE.md and TASKS.md.

- **Last task:** F1a – Lean model + executable monitor + theorem (a) (done)
- **Model:** claude-fable-5-1
- **State:** `lean/TenantFlow/Model.lean` (abstract model + ghost layer), `Exec.lean` (computable monitor),
  `Proofs.lean` (`Step.det`, `Step.total`, invariant `Inv`, `isolation`, `isolation_int`, `Exec.rank_mem`,
  sanity examples 1–7). `lake build` clean, zero warnings. Axioms in `docs/proof-status.md`.
- **Design decisions F1a** (spec §8 "F1a decides details"):
  - `Step cfg D` takes the data `D` too (the `tool` function lives in `Data`).
  - `Config.principalRole : Principal → Role` embeds the root principal into the Cedar principal type.
  - `Step` = `Allowed` (one constructor per §5 row, hypotheses = exactly the row's conditions) + `denied`
    (`∀ r s', ¬ Allowed …`). `GStep` = `Step` + the function `ghostUpdate` (unchanged on `denied`).
  - Ghost `deps` are predicates keyed by agent id, by doc *value* and by event *value* (equal docs/events share
    deps: an over-approximation that is sound for (a)/(b2) and avoids positional alignment). Outbox entries in the
    ghost carry `(deps, child ctx at report time)`, so (b2) for them is already in `Inv.outbox`.
  - `Exec`: owner sets are duplicate-free lists, label equality is set equality (`Exec.Label.equiv`); the oracle
    should sort owners on output. `rank` = stable insertion sort by `cfg.score q payload` (desc) then `take cfg.topK`.
    `Response.denied` carries a reason string. `Exec.runTrace` runs a list of `(AgentId, Action)`.
- **For F1b:** `Inv` already contains the (b2) inequality for agents, docs, events and outbox entries; `no_launder`
  is a corollary. Still to prove: `ctx` monotone along traces, child `ctx` = parent `ctx` at creation (both direct
  from `Allowed` cases). (b1) only if ≤ 1 USD.
- **Open `sorry`s (file:line, lemma):** none
- **What was tried (if stuck):** –
- **Next task:** F1b [FABLE] – Theorem (b). Session must start with the current Fable spend (gate G1 ≤ 25 USD).
  S1 and S2 [SONNET] are unblocked and can run in parallel on other models.
