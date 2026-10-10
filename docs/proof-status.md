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
| (c) `noninterference` | §7.4 | open (F2) | – |
| (d1) `refines`, (d2) `refines_init` | §7.5 | open (F3) | – |

Checked on 2026-10-10 with `#print axioms` after `lake build` (no `sorry`, no `admit`, no new `axiom` in `lean/`).
