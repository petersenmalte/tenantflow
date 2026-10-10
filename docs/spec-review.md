# Adversarial spec review (task F0)

Reviewer: `claude-fable-5-1`, 2026-10-10. Object: `docs/spec.md` v0.1 (O1). Result: `docs/spec.md` v0.2.
Method: for every theorem ask (1) is it vacuous or definitional, (2) does an assumption do the real work,
(3) is the agent really arbitrary, (4) is the statement well-formed for a nondeterministic agent, (5) can the
proof be done cheaply in Lean 4 without Mathlib. Each finding has a verdict and the decision taken.

## A. Findings that changed a theorem statement

### A1. `rank` could fabricate documents
`rank : Query → List Doc → List Doc` was universally quantified with no side condition. A constant `rank` returning
a tenant-A document from nowhere is a valid instance. Labels still get joined, so (a) and (b2) survive, but the
ghost `deps` of a fabricated doc is undefined and `query` stops meaning "retrieve".
**Decision:** `Config` carries `rank_mem : ∀ q L d, d ∈ rank q L → d ∈ L`. `Exec`'s top-k satisfies it (F1a proves
`topk_mem`). A relational `Select` would have made (c) possibilistic; a function with `rank_mem` keeps (c) exact.

### A2. Ghost state made (d) unprovable as stated
v0.1 put `deps` into `Model.State` and asked for `α : ExecState → Model.State`. `Exec` has no provenance, so no
`α` can produce it; (d) was unsatisfiable.
**Decision:** provenance is an instrumentation layer `GState = State × Ghost` with `GStep`, `ghost_proj`
(`GStep → Step`) and `ghost_lift` (every `Step` lifts). (a), (b2) are proven on `GState`; (c), (d) on `State`.
Alternative considered: compute `deps` in `Exec` too (cheap, and the oracle could print provenance). Rejected for
v1 to keep `Exec` minimal and the Python port small; can be added without touching any theorem.

### A3. Tool arguments are an output channel; `read` had no arguments
v0.1's `read k` returned `src k` with no arguments. Real tools take arguments, and the arguments reach the tool's
operator. With the v0.1 rules a tainted insurer agent (holding bank data) could call an insurer-observed tool
and pass bank data as the argument: a leak that no v0.1 theorem would have caught, because sources were not
observation points. The same gap covers tools with memory (write via arguments, read back later).
**Decision (D9):** `read`/`send` unified into `call k args` over a registry `ToolInfo = (observers, needsTrusted,
result : Option Label)`. Arguments are checked against `observers` exactly like a sink; the result (if any) is
joined into `ctx` exactly like a source. `deliver` is the built-in tool with `observers = {t(s)}`. Every
successful call is an event, so `obs_B` sees the arguments B's tools receive. Tool memory and re-entry become
assumption A4 with a concrete registry obligation. Six action constructors instead of seven; one fewer case in
every proof.

### A4. `deliver (p : Principal)` let the agent choose the recipient
Harmless for the theorems (observers were `{p.tenant}`), but an attacker-controlled field that no deployment
offers, and it made `SinkRef` carry a `Principal`.
**Decision (D10):** `deliver` addresses the acting session's principal. Cross-tenant delivery is inexpressible;
notifying another user of the same tenant is an `ext` tool with `observers = {t}`.

### A5. (d) was stated as forward simulation plus a separate "no allowed step" clause
`Model.Step` is functional (authorize and rank are functions). **Decision:** state `Step.det` and `Step.total` as
lemmas; (d) = (d1) every `Exec` step is a `Model` step (with denial reasons collapsed by `⌊·⌋`) + (d2) initial
states agree. "Denied ⇒ no allowed model step" is then a corollary, not an extra proof obligation.

### A6. (b1) is definitional in `Model`; in `Exec` the real guarantee is structural
Labels and payloads are separate fields, so "same skeleton ⇒ same skeleton" is `rfl`-shaped. What actually
prevents forgery is that the monitor is polymorphic in `Pay` and only `rank`, `mkRequest`, `tool` consume
payloads: a label inside a JSON payload is unreachable by construction.
**Decision:** design rule D8 (parametricity) is primary; (b1) demoted to an `Exec` lemma with a ~1 USD cap,
(b1-default) becomes sanity example 6. Headline (b) := (b2), reworded so that its content is visible: the label
lower bound is built only from registry labels and holds for every payload.

### A7. (c)'s simulation relation needed an "absent or tainted" clause
A tainted parent's `delegate` goes through Cedar with a payload that may differ between the two runs, so a
child may exist in run 1 and not in run 2. "Each agent is clean-and-identical or tainted-in-both" is not
preserved. **Decision:** relation (iii) in §7.4: clean-and-identical, or in each run absent-or-tainted. Children
of clean parents exist in both runs (parent identical), so clean agents never hit the second case.

## B. Findings answered without changing a statement

### B1. Is (a) vacuous? Partly definitional, kept.
`deps` mirrors the label rules exactly (in fact `label x = ⨆ label₀ (deps x)` holds), so (a) is (b2) + the exit
check + downward closure of `readable`. It is an easy induction, not a vacuous one, and it is the statement the
deck and game cite ("nothing with foreign provenance reaches you"). The semantic claim that `deps` is the right
over-approximation is (c). Written into §1 and §7.1 so that nobody oversells (a). Only `⊑` is claimed in (b2):
equality would break under any conservative extra tainting and the converse direction is a utility property.

### B2. Is the agent really arbitrary? Yes, with one subtlety.
Strategies `List Response → Action` see their own observation history including `denied`; actions carry
attacker-chosen payloads, roles and recipients (now only via `ext` tools). The subtlety: `denied` for a clean agent
is a function of its own history (Cedar on its own request, flow check on its own label), hence low. For a
tainted agent nothing it observes matters. Exec may return denial *reasons*; same argument, so (d) collapses
them.

### B3. Well-formedness for a nondeterministic agent (TIPNI reference)
An LLM sampler is `f(seed, context)`; the seed is independent of the data. Quantifying over all strategies
quantifies over all seeds; pointwise equality of observations for every seed gives equality in distribution.
Strategies total + finite schedule ⇒ no divergence ⇒ termination-insensitive and -sensitive coincide; early
stopping of a real agent is a timing channel under A5. The model has a universal no-op (any denied action), so
"the agent stops" is expressible. Whether an agent gets tainted depends on labels and its own low history, so the
visible effect "no response" is low. Recorded as remarks in §7.4.

### B4. Scheduling
A data-dependent scheduler is a channel (parent woken because a tainted child reported ⇒ parent acts a
different number of times). Fixed schedule + A5. Generalisation to schedulers that are functions of the low
history is sound and mechanical but adds proof surface; deferred.

### B5. Cedar inputs
Real Cedar policies can reference entity attributes derived from data. The model's `mkRequest` sees principal
and action only. Made explicit as A7 rather than silently assumed.

### B6. Taint vs clearance (D1)
Taint-at-read is what the narrative needs (game level 2 blocks the *write*). Under A3 both variants give the
same theorems; clearance is one extra conjunct (`ctx.owners ⊆ {t}` after every join) if A3 is ever doubted.
Confirmed taint.

### B7. Cedar on `report`/`receive`
Internal return path of an already-authorized delegation; Cedar has no sensible request to see. Confirmed: no
Cedar. All theorems hold for every `authorize` anyway.

### B8. Decision D6 (`receive` joins the child's current `ctx`)
Alternative (join only the labels of reported entries) leaks one bit through an empty outbox. Join-current is
the canonical choice (by monotonicity it equals join of entry labels ⊔ current). Confirmed. Cost: a parent that
collects late from a child that got tainted after reporting is tainted too (utility only).

### B9. Granularity and dead data
Isolation is per tenant; users within a tenant are not isolated (non-goal, now explicit). Joint documents
(`owners ⊇ {A, B}`) are readable by nobody and can never be created at runtime (D4); public documents can only
exist in `index₀` (D5). Tools with `observers = ∅` are black holes w.r.t. (a); fine under A4.

### B10. Public tools
Because `ctx ∋ t(s)` always and there is no declassification, a tool observed by every tenant is uncallable.
Documented as a consequence of "no declassification"; the registry owner may register such a tool with
`observers = ∅` as an explicit trust decision (A2).

### B11. Integrity
(a-int) is kept. Integrity noninterference (trusted-tool observations independent of untrusted data) is the dual
of (c) with `readable` replaced by `integ = trusted`; not claimed, listed as non-goal, cheap to add after G2 if
budget remains.

## C. Consequences for other tasks (recorded in `TASKS.md`)

- F1a: six actions (`call, query, write, delegate, report, receive`), `GState` layer, `Step.det`/`Step.total`,
  `rank_mem` for top-k, sanity examples 1–7.
- F1b: (b) = (b2) on `GState`; (b1) only if ≤ 1 USD.
- F2: simulation relation of §7.4 incl. clause (iii).
- F3: (d1) + (d2) with `⌊·⌋`.
- S1/S2: JSON actions follow §4.4; registry format follows §4.1 (`observers`, `needsTrusted`, `result`).
- G1 fallback updated: drop delegation (`delegate`/`report`/`receive`) and restrict (b2) to index docs and events.
- New SONNET task S0b: Lean toolchain is not installed in cloud sessions (`lake` missing); a SessionStart hook or
  setup script is needed before F1a can build.
