# Proof status

`#print axioms` output per theorem (CLAUDE.md section 5). Lean 4.34.1, no Mathlib.
Allowed: `propext`, `Classical.choice`, `Quot.sound`.

| Theorem (Lean name) | Spec | Status | Axioms |
|---|---|---|---|
| `Model.Step.det` | §7 lemma | proven (F1a) | propext, Classical.choice, Quot.sound |
| `Model.Step.total` | §7 lemma | proven (F1a) | propext, Classical.choice, Quot.sound |
| `Model.ghost_proj`, `Model.ghost_lift` | §7.1 | proven (F1a) | propext, Classical.choice, Quot.sound |
| `Model.Inv.reachable` (label soundness invariant, incl. the (b2) inequality for agents, docs, events, outbox entries) | §7.2/§7.3 | proven (F1a) | propext, Classical.choice, Quot.sound |
| `Model.isolation` | (a) §7.2 | proven (F1a) | propext, Classical.choice, Quot.sound |
| `Model.isolation_int` | (a-int) §7.2 | proven (F1a) | propext, Classical.choice, Quot.sound |
| `Exec.rank_mem` | §6 `rank_mem` for the executable top-k | proven (F1a) | propext |
| Sanity examples 1–7 | §7.7 | proven by `decide` on `Exec` (F1a), `lean/TenantFlow/Proofs.lean`, namespace `Exec.Sanity` | – |
| `Model.no_launder` (b2: pointwise `label₀ o ≤ label x` for agents, docs, events, outbox entries) | (b) §7.3 | proven (F1b) | propext, Classical.choice, Quot.sound |
| `Model.ctx_mono`, `Model.ctx_mono_ghost` (`ctx` monotone along every trace, agents never removed) | (b) §7.3 | proven (F1b) | propext, Classical.choice, Quot.sound |
| `Model.child_ctx_eq` (child `ctx` = parent `ctx` at creation) | (b) §7.3 | proven (F1b) | propext, Classical.choice, Quot.sound |
| `Model.Fresh.init`, `Model.Reachable.fresh` (child ids fresh, needed for `ctx_mono`) | §7.3 helper | proven (F1b) | propext / propext, Classical.choice, Quot.sound |
| (b1) `Exec` label–payload independence | §7.3 lemma | dropped per §7.3 cost rule (D8 + sanity examples 4, 6 are the evidence) | – |
| `Model.noninterference` (c: `LowEq cfg B D₁ D₂ → obs cfg B (run cfg strat sched D₁) = obs cfg B (run cfg strat sched D₂)`) | (c) §7.4 | proven (F2), `lean/TenantFlow/Proofs/Noninterference.lean` | propext, Classical.choice, Quot.sound |
| `Model.Sim.left`, `Model.Sim.lock`, `Model.Step.leftOK`, `Model.Step.lockOK`, `Model.Sim.of_lowEq_init` (simulation relation `Sim`, its preservation, initial states) | §7.4 proof shape | proven (F2) | propext, Classical.choice, Quot.sound |
| `Model.stepFn`, `Model.run` (step function via `Step.total`/`Classical.choose`; `Step.eq_stepFn` by `Step.det`) | §7.4 definitions | defined (F2), noncomputable | – |
| `Exec.refines` (d1: `step cfg D s a act = (r, s') → Model.Step (α cfg) (α D) (α s) a act ⌊r⌋ (α s')`) | (d) §7.5 | proven (F3), `lean/TenantFlow/Proofs/Refinement.lean` | propext, Classical.choice, Quot.sound |
| `Exec.refines_init` (d2: `α (init cfg D) = Model.init (α cfg) (α D)`) | (d) §7.5 | proven (F3) | propext, Quot.sound |
| `Exec.refines_denied` (denied ⇒ `Exec` state unchanged ∧ no allowed model step), `Exec.refines_trace`, `Exec.refines_ghost` (`runTrace` states abstract to `Reachable`/`GReachable` model states), `Model.Reachable.ghost`, `Model.Step.not_allowed_of_denied` | §7.5 corollaries | proven (F3) | propext, Classical.choice, Quot.sound |
| `Exec.rank_abs`, `Exec.readableDocs_abs`, `Exec.Label.abs_join`/`abs_joinAll`, `Exec.State.abs_setAgent`, `Exec.toolInfo_abs` (`α` commutes with ranking, the readable filter, label joins, agent updates, the registry) | §7.5 proof shape | proven (F3) | propext / propext, Classical.choice, Quot.sound |
| `Exec.run` (executable counterpart of `Model.run`: same `Strategy`/schedule, `Exec.step` instead of `stepFn`, histories hold `⌊r⌋`, so strategies are reason-blind as in the model) | §7.5 definition | defined (F4), computable, `lean/TenantFlow/Proofs/NoninterferenceExec.lean` | – |
| `Exec.noninterference` (c for `Exec` traces: `Model.LowEq (α cfg) B (α D₁) (α D₂) → α (obs cfg B (Exec.run cfg strat sched D₁)) = α (obs cfg B (Exec.run cfg strat sched D₂))`, i.e. the `B`-observable events agree in tenant, tool, arguments and label-as-set), `Exec.run_abs` (`α (Exec.run cfg strat sched D) = Model.run (α cfg) strat sched (α D)`), `Exec.obs_abs` (`obs` commutes with `α`) | §7.5 corollary | proven (F4) | propext, Classical.choice, Quot.sound |
| `Exec.initRun_abs`, `Exec.observersOf_abs` / `Exec.stepFn_abs`, `Exec.runStep_abs`, `Exec.runAll_abs` (lockstep lemmas behind `run_abs` and `obs_abs`) | §7.5 proof shape | proven (F4) | propext, Quot.sound / propext, Classical.choice, Quot.sound |

Checked on 2026-10-11 with `#print axioms` after `lake build` (no `sorry`, no `admit`, no new `axiom` in `lean/`).
