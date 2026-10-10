# TenantFlow – Formal specification

Status: **draft v0.1** (task O1, written by `claude-opus-5-5`). To be attacked and finalised in task F0.
Theorem statements in this file are owned by FABLE tasks (see `CLAUDE.md` §3.3); after F0, changes require a
changelog entry (§10).

Notation: `⊑` label order, `⊔` join, `⊥` bottom label. `t(s)` is the tenant of session `s`.
"Agent" always means an arbitrary, possibly adversarial program; nothing is assumed about its behaviour.

---

## 1. Scope and claim in one paragraph

Several tenants share one agent platform and one RAG index. A per-call authorizer (Cedar) decides each tool call
in isolation. TenantFlow adds a **trusted adapter** that attaches labels from trusted metadata only (the
authenticated session and a source/sink registry) and a **flow monitor** that tracks a floating context label per
agent instance and checks it at every point where data leaves the agent. We prove, in Lean 4, that for **every**
authorizer and **every** agent behaviour:
(a) no data originating from another tenant is ever delivered to a tenant's principals or sinks,
(b) labels cannot be forged by payload content and are never lowered,
(c) tenant-B observations are independent of all data B may not see (noninterference),
(d) the executable monitor used by the oracle and the tests implements the abstract model.

**Isolation comes from the flow monitor, not from Cedar.** Cedar is an opaque, universally quantified function
`authorize : Request → Decision`. No theorem about Cedar itself is claimed, and no theorem assumes anything about
the policies (in particular not "forbid overrides permit" or "default deny": with the monitor doing the isolation,
such a hypothesis would be unused and the statement would be misleading). Cedar's role is least privilege per call;
the benchmark measures what it adds, the proofs do not rely on it.

---

## 2. Threat model

### 2.1 Attacker

- **The agent is the attacker.** Every agent instance (root agent or sub-agent) may choose any action with any
  payload at any step. This covers a prompt-injected LLM, a malicious tool-calling loop and a buggy orchestrator.
  In (a), (b), (d) this is modelled by universal quantification over action sequences; in (c) by universal
  quantification over agent *strategies* (§7.3).
- **Payloads are attacker-controlled.** Any payload (document text, tool result, ticket body, query string) may
  contain fields that look like labels (`security_label`, `owners`, `integrity: trusted`, …). This is the FIDES
  label-forgery class (APIsec Labs, see `docs/related-work.md`).
- **Cedar policies may be wrong.** Policies may be overly permissive (up to "permit everything"). The guarantees
  must hold for every authorizer.
- **Data of other tenants is adversarial.** Tenant A's documents may be crafted to influence tenant B's agents.

### 2.2 Trusted computing base

| Component | Trusted for | Covered by |
|---|---|---|
| Session authentication | `principal(s)` is the real, authenticated principal of session `s` | assumption A1 |
| Registry config | labels of sources, observers and integrity requirements of sinks are correct | assumption A2 |
| Adapter + monitor | implement the step function of §5 | theorem (d) for the Lean executable; differential testing (S3) for Python |
| Index server | filters by label **before** ranking / top-k | part of the model (§5, rule `query`); (d), S3 |
| Lean kernel, Lean compiler for the oracle | as usual | – |

### 2.3 Out of scope (non-goals)

- Side channels: timing, latency, resource usage, error rates, index size, rate limits, logs.
- Prompt injection that stays within the permissions of the affected tenant (e.g. tenant A's data tricks tenant
  A's agent into sending tenant A's data to a sink tenant A is allowed to use). That is an integrity/utility
  problem inside one tenant; TenantFlow only adds the integrity bit (§3) so that policies *can* require trusted
  inputs for certain sinks.
- Correctness of data classification (whether the registry labels a source correctly).
- Bugs in the trusted adapter itself (only differential testing, no proof).
- Declassification / endorsement. There is no operation that lowers a label. (APPA's recoverable IFC is related
  work, not a feature.)
- Several shared components (cache, shared agent memory, shared conversation history) in version 1.
- Data that leaves the platform to an external system and comes back through another source (e.g. a public paste
  site). External sinks are modelled as observation points only; see A4.

---

## 3. Labels

- `Tenant`: a type with decidable equality; finitely many tenants in any concrete configuration.
- `Integrity ::= trusted | untrusted`, ordered `trusted ≤ untrusted` ("untrusted wins").
- `Label := { owners : Set Tenant, integ : Integrity }`.
  - `owners` = the tenants whose data (may have) contributed. Confidentiality: more owners = more restrictive.
  - `ℓ₁ ⊑ ℓ₂ :⇔ ℓ₁.owners ⊆ ℓ₂.owners ∧ ℓ₁.integ ≤ ℓ₂.integ`
  - `ℓ₁ ⊔ ℓ₂ := (ℓ₁.owners ∪ ℓ₂.owners, max ℓ₁.integ ℓ₂.integ)`, `⊥ := (∅, trusted)`.
  - `(Label, ⊑, ⊔, ⊥)` is a join-semilattice with bottom (to be proven as a lemma, not a theorem).
- **Readable by tenant `u`:** `readable u ℓ :⇔ ℓ.owners ⊆ {u}`. Data with `owners = ∅` (public) is readable by all.

Representation (decided in F1a): in `Model/` sets may be predicates or a finite-set type; in `Exec/` they are
sorted, duplicate-free lists so that `decide` and the oracle work without Mathlib.

---

## 4. System model

### 4.1 Static configuration (trusted, identical in all compared runs)

| Symbol | Meaning |
|---|---|
| `Principal = (tenant : Tenant, user : UserId)` | |
| `sessions : SessionId → Option Principal` | authenticated principal per session (A1) |
| `srcReg : SourceId → Option Label` | label of each registered source (tool / data store) (A2) |
| `sinkReg : SinkId → Option SinkInfo`, `SinkInfo = (observers : Set Tenant, needsTrusted : Bool)` | external sinks (A2) |
| `deliver p` | built-in sink "response to principal `p`" with `observers = {p.tenant}`, `needsTrusted = false` |
| `CedarPrincipal` | entity on whose behalf Cedar is asked; root agents use `principal(s)`, sub-agents a role |
| `mkRequest : CedarPrincipal → Action → Request` | builds the Cedar request; **may** include the payload (cedar-for-agents puts tool arguments into the context) |
| `authorize : Request → Decision` | **opaque, universally quantified**, `Decision ::= allow | deny` |
| `rank : Query → List Doc → List Doc` | retrieval function; universally quantified in the model, toy embedding top-k in `Exec`/Python |

### 4.2 Data (what may differ between the runs compared in (c))

| Symbol | Meaning | Label |
|---|---|---|
| `src : SourceId → Payload` | current content of each source | `srcReg id` |
| `index₀ : List Doc`, `Doc = (label, payload)` | initial content of the shared index | stored per doc, set by adapter/config |
| `prompt : SessionId → Payload` | the user's request that starts the session | `({t(s)}, trusted)` |

`Payload` is arbitrary (in `Exec`: a JSON value). Nothing in the monitor inspects it except `rank` and `mkRequest`.

### 4.3 Runtime state

- `index : List Doc` — **append-only**. There is no update or delete (an overwrite by tenant A of a tenant-B doc
  would be a write-up flow; deletion is out of scope for v1).
- `agents : AgentId → Option AgentState`, with `AgentId = (SessionId, List Nat)` (root = `(s, [])`, the `n`-th
  child of `a` is `a ++ [n]`; identifiers are allocated **locally**, so no global counter can carry information).
- `AgentState = { session : SessionId, cedarP : CedarPrincipal, ctx : Label, nextChild : Nat,
  outbox : List Payload, parent : Option AgentId }`.
- `events : List Event`, `Event = (sink : SinkRef, payload, label)` where `SinkRef = deliver Principal | ext SinkId`.
  Only **successful** sink actions are events. Denials are returned to the acting agent, never to a principal.
- Ghost state for the proofs (not in `Exec`, not observable): `deps` on every payload-carrying object, a set of
  origins `Origin ::= srcO SourceId | docO Nat | promptO SessionId` (§7.1).

Initial state: one root agent per session `s` with `ctx = ({t(s)}, trusted)`, `cedarP = principal(s)`; its first
observation is `prompt s`; `index = index₀`; `events = []`.

### 4.4 Agent actions

```
Action ::= read   (k : SourceId)
         | query  (q : Query)
         | write  (v : Payload)                       -- append to shared index
         | send   (r : SinkRef) (v : Payload)          -- deliver to principal or external sink
         | delegate (role : CedarPrincipal) (task : Payload)
         | report (v : Payload)                        -- sub-agent → its parent's view of it
         | receive (c : Nat)                           -- parent collects from child a ++ [c]
```

Every action is mediated (A3, complete mediation). The response an agent receives is either a payload / list of
payloads, a child id, `ok`, or `denied`.

---

## 5. Monitor rules

For agent `a` with state `σa`, session `s = σa.session`, tenant `t = t(s)`, context label `ℓ = σa.ctx`:

`allowed(a, act) :⇔ authorize (mkRequest σa.cedarP act) = allow ∧ flowOK(a, act)`
(`receive` and `report` are internal and skip Cedar; F0 may decide otherwise.)

| Action | `flowOK` (beyond registry lookup succeeding) | Effect if allowed |
|---|---|---|
| `read k` | `srcReg k = some ℓk` (unregistered ⇒ deny, **never** a default label) | `ctx := ℓ ⊔ ℓk`; respond `src k` |
| `query q` | – | `R := rank q (filter (readable t ∘ label) index)`; `ctx := ℓ ⊔ ⨆ label(R)`; respond payloads of `R` |
| `write v` | `ℓ.owners ⊆ {t}` | append `(ℓ, v)` to `index`; respond `ok` |
| `send r v` | `observers(r) = O`: `∀ u ∈ O, readable u ℓ`; and `needsTrusted(r) → ℓ.integ = trusted` | append event `(r, v, ℓ)`; respond `ok` |
| `delegate ρ v` | – | create `a ++ [n]` with `session = s`, `cedarP = ρ`, `ctx = ℓ`, first observation `v`; `nextChild += 1` |
| `report v` | `σa.parent ≠ none` | append `v` to `σa.outbox` |
| `receive c` | child `a ++ [c]` exists | `ctx := ℓ ⊔ ctx(child)`; respond and clear `child.outbox` |

If not allowed: state unchanged, the agent receives `denied`.

Design decisions (explicitly up for review in F0):

1. **Floating label, checked at the exits (taint, not block-at-read).** A read is never blocked by the flow monitor,
   only by Cedar. This matches the narrative "every call is Cedar-allowed, TenantFlow blocks the write" (game
   level 2) and the FIDES comparison. It relies on A3: the agent context is only observable through mediated
   actions. Alternative (LIO-style clearance `ctx.owners ⊆ {t}` checked at read): strictly safer, makes (a)
   simpler, but makes the owner sets of agent contexts degenerate.
2. **Filter before rank.** `rank` sees only readable docs. Top-k before filtering would let tenant-A documents
   displace tenant-B documents and leak through which B docs are returned.
3. **Query filter uses the session tenant `t`, not `ctx`.** Docs with `owners = ∅` are returned to everyone.
4. **Writes by a tainted agent are denied** (not stored under a label nobody can read). Every stored doc written
   at runtime therefore has `owners = {t}`.
5. **`ctx` always contains `t(s)`** (initial value; inherited by children; monotone). Consequently no runtime
   agent can send to a public sink (`observers` = all tenants); public sinks only make sense for `⊥` data, which
   no agent holds. Accepted for v1 (no declassification).
6. **`receive` joins the child's *current* context**, also when the outbox is empty, so an empty answer cannot
   leak whether a tainted child chose to report.
7. Sub-agents inherit the session; a delegated role may have **more Cedar rights** but never a lower label and
   never another tenant (game level 4).

---

## 6. Executable monitor (`Exec/`)

- `Exec.step : Config → Authorizer → ExecState → AgentId → Action → Response × ExecState`, total and computable,
  over concrete structures (payload = JSON, labels = sorted lists, index = array/list, agents = association list
  or `HashMap`).
- `rank` instantiated with a deterministic toy embedding and top-k (same algorithm as Python, documented in
  `docs/oracle-format.md` by S1).
- Labels are stored **next to** payloads, never inside them. Nothing in `Exec` parses a payload for label fields.
- The oracle (`lake exe oracle`, S1) runs `Exec.step` over a JSON trace. Python (`tenantflow.monitor`, S2) is a
  port; S3 compares them.

---

## 7. Theorems

All theorems quantify over: every configuration, every `authorize`, every `mkRequest`, every `rank`, and every
agent behaviour. "Reachable" = reachable from an initial state by any finite sequence of `(AgentId, Action)` pairs
under the step relation (denied actions included; they are no-ops).

### 7.1 Ghost provenance (definition, used by (a) and (b))

Extend the model state with `deps : Set Origin` for each agent context, index doc, outbox entry and event:
- initial: root agent `deps = {promptO s}`; initial doc `i` has `deps = {docO i}`;
- `read k`: agent `deps ∪= {srcO k}`; `query`: `∪=` deps of every returned doc; `receive`: `∪=` deps of child;
- `write`, `send`, `report`, `delegate`: the produced object gets the agent's current `deps`.

`label₀ : Origin → Label` is the trusted label of an origin (`srcReg`, the initial doc label, `({t(s)}, trusted)`).
`deps` is defined **without looking at labels**; it over-approximates "may depend on" for an arbitrary agent,
because an arbitrary agent may put anything it has seen into any later payload (this captures implicit flows
through the agent's choices).

### 7.2 (a) Isolation

> **Theorem (a).** For every reachable state and every event `(r, v, ℓ)` in `events`, every observer tenant
> `u ∈ observers(r)` and every origin `o ∈ deps(event)`: `readable u (label₀ o)`.
> In words: nothing that may depend on data another tenant owns ever reaches a principal or sink of tenant `u`.
>
> **(a-int)** For every reachable state and every event at a sink with `needsTrusted = true`: every
> `o ∈ deps(event)` has `(label₀ o).integ = trusted`.

Why not just "the event label is readable": that is the monitor's own check and would be true by definition
(vacuous). (a) relates the check to provenance, through the shared index and through delegation, and therefore
needs the invariant (b2). Expected difficulty: easy–medium.

### 7.3 (b) No forgery, no laundering

> **(b1) Payload independence of labels.** Let `skel` erase every payload in a state and in an action (keeping
> labels, ids, registry, structure). If `skel s₁ = skel s₂`, `skel act₁ = skel act₂`, both actions get the same
> Cedar decision, and (for `query`) `rank` selects the same documents, then
> `skel (step s₁ a act₁) = skel (step s₂ a act₂)`.
> Corollary: a payload containing `security_label`, `owners`, `integrity` or any other field cannot change any
> label. Stated and proven for `Exec` (JSON payloads), transferred to `Model` via (d) or proven in both.
>
> **(b1-default)** If `srcReg k = none` then `read k` is denied; if `sinkReg k = none` then `send (ext k) v` is
> denied. (No default label, in particular never a default `trusted` – the second FIDES issue.)
>
> **(b2) No laundering.** For every reachable state and every object `x` (agent context, index doc, outbox entry,
> event): `⨆ { label₀ o | o ∈ deps x } ⊑ label x`, where an outbox entry's label is the child's `ctx`.
> Additionally `ctx` is monotone along every trace for every agent, and a child's `ctx` at creation equals its
> parent's.

Known weakness for F0: in the abstract model (b1) holds almost by construction because labels and payloads are
separate fields. Its value lies in `Exec` (concrete JSON) and as the specification the Python adapter is tested
against. F0 decides whether to keep it as a theorem or demote it to a lemma about `Exec`.

### 7.4 (c) Noninterference

Agents are modelled as **strategies**: `Strategy := List Response → Action`, one per agent id
(`strat : AgentId → Strategy`), where the list is the agent's own observations so far (first entry: its prompt
or delegation task). A strategy is an arbitrary Lean function; randomness (an LLM sampling) is modelled by fixing
a seed inside the strategy, i.e. by quantifying over all strategies. A **schedule** `sched : List AgentId` fixes
which agent moves next; scheduling a non-existent agent is a no-op. `run cfg auth strat sched D` is the resulting
event list from data `D`.

Low equivalence for an observer tenant `B`: `D₁ ≈_B D₂` iff
- `src₁ k = src₂ k` for every `k` with `readable B (srcReg k)`,
- `filter (readable B ∘ label) index₀₁ = filter (readable B ∘ label) index₀₂` (order preserved; non-readable docs
  may differ arbitrarily in content, number and position),
- `prompt₁ s = prompt₂ s` for every session `s` with `t(s) = B`.

Observation: `obs_B evs := filter (fun e => B ∈ observers e.sink) evs` (payloads and labels).

> **Theorem (c).** For all `cfg, authorize, mkRequest, rank, strat, sched, B, D₁, D₂`:
> `D₁ ≈_B D₂ → obs_B (run … D₁) = obs_B (run … D₂)`.

Remarks for F0:
- This is stronger than "differ only in tenant-A data": everything B may not read may differ, including other
  tenants' data, joint data and the *existence* of documents.
- Well-formedness for a nondeterministic agent: nondeterminism is moved into the universally quantified strategy;
  a probabilistic agent is a distribution over strategies independent of the data, so equal observations for
  every strategy give equal observation distributions. Compare LLMbda's termination-insensitive probabilistic
  noninterference. Because strategies are total and schedules finite, divergence does not arise in this
  formulation; if F0 introduces partial strategies or an unbounded scheduler, the statement must become
  termination-insensitive explicitly.
- The schedule is fixed in advance, i.e. independent of the data. A data-dependent scheduler is a timing channel
  (non-goal). F0 may generalise to schedulers that see only `obs_B`.
- Expected proof shape: a lockstep simulation with the relation "each agent is either *clean* (`ctx.owners ⊆ {B}`)
  and identical in both runs, or *tainted* (`ctx.owners ⊄ {B}`) in both runs", plus equality of the B-readable
  projection of the index. Design decisions 2, 4 and 6 in §5 are what make this relation preserved.
- Non-vacuity: a monitor that denies everything satisfies (c) and (a). This is ruled out by §7.6.

### 7.5 (d) Refinement

> **Theorem (d).** There is an abstraction `α : ExecState → Model.State` such that for every `s`, agent `a` and
> action `act`, with `(resp, s') := Exec.step cfg auth s a act`:
> - if `resp ≠ denied` then `Model.Step (α s) a act resp (α s')`;
> - if `resp = denied` then `s' = s` and there is no `t, resp'` with `resp' ≠ denied ∧ Model.Step (α s) a act resp' t`;
> - `α` maps `Exec.init` to `Model.init`.
> Corollary: (a), (b2) and (c) hold for `Exec` traces (lift along `α`; for (c), `obs_B` commutes with `α`).

Here `Model.rank` is instantiated with `Exec`'s top-k function. Expected difficulty: medium–hard; hard cap per
`TASKS.md`.

### 7.6 Sanity (non-vacuity) examples

Required alongside (a)–(c), proven by evaluation on `Exec` (`decide` / `rfl`), with `authorize = fun _ => allow`:
1. A bank agent reads a bank source, writes to the index; a second bank session queries and delivers it to a bank
   principal — all allowed, and the delivered payload equals the written one.
2. The same with an insurer session as the reader: the query returns nothing of the bank document.
3. Game level 2: an insurer agent reads a bank source (Cedar-allowed), then `write` is **denied**.
4. Game level 3: a source labelled `({A}, untrusted)` whose payload contains `"security_label": {"owners": [],
   "integrity": "trusted"}`: after reading it, `ctx = ({t, A}, untrusted)`.
5. Game level 4: a delegated child with a more powerful role inherits the tainted label; its `send` to a B principal
   is denied.

---

## 8. Lean signature sketch (illustrative, not binding; F0/F1a decide)

```lean
namespace TenantFlow.Model

inductive Integrity | trusted | untrusted
structure Label (T : Type) where
  owners : T → Prop          -- or a finite-set type; decided in F1a
  integ  : Integrity

variable {T U Src Snk Role Req Pay Qry : Type} [DecidableEq T]

structure Principal (T U) where tenant : T; user : U
inductive SinkRef (T U Snk) | deliver (p : Principal T U) | ext (k : Snk)
inductive Action (Src Snk Role Pay Qry T U)
  | read (k : Src) | query (q : Qry) | write (v : Pay)
  | send (r : SinkRef T U Snk) (v : Pay) | delegate (ρ : Role) (v : Pay)
  | report (v : Pay) | receive (c : Nat)

structure Config where
  sessions  : SessionId → Option (Principal T U)
  srcReg    : Src → Option (Label T)
  sinkReg   : Snk → Option SinkInfo
  mkRequest : CedarP → Action … → Req
  authorize : Req → Decision          -- opaque
  rank      : Qry → List (Doc T Pay) → List (Doc T Pay)

inductive Step (cfg : Config) : State → AgentId → Action … → Response … → State → Prop
  | read  : … → Step cfg s a (.read k) (.payload (s.src k)) { s with … }
  -- one constructor per row of the table in §5, plus `denied` (state unchanged)

def Reachable (cfg : Config) (s₀ : State) : State → Prop := …

theorem isolation   (cfg) (h : Reachable cfg (init cfg D) s) : ∀ e ∈ s.events, … -- (a)
theorem no_launder  (cfg) (h : Reachable cfg (init cfg D) s) : ∀ x, joinDeps x ⊑ labelOf x -- (b2)
theorem noninterference (cfg) (strat) (sched) (B) (h : lowEq B D₁ D₂) :
    obsB B (run cfg strat sched D₁) = obsB B (run cfg strat sched D₂)            -- (c)
end TenantFlow.Model

namespace TenantFlow.Exec
def step (cfg : Config) : State → AgentId → Action → Response × State := …
theorem payload_independent : skel s₁ = skel s₂ → … → skel (step cfg s₁ a act₁).2 = …    -- (b1)
theorem refines : let (r, s') := step cfg s a act; … Model.Step cfg (α s) a act r (α s') -- (d)
end TenantFlow.Exec
```

---

## 9. Assumptions (stated with every guarantee)

- **A1 Trusted session.** `sessions s` is the authenticated principal; agents cannot change their session.
- **A2 Trusted registry.** Source labels and sink observers/integrity flags are configured correctly.
- **A3 Complete mediation.** Every interaction of an agent with data, the index, principals, sinks and other agents
  goes through the monitor. The agent's internal context (LLM context window, scratchpad, logs) is not observable
  by any principal except through mediated actions.
- **A4 Closed world.** External sinks are observation points; data sent there does not re-enter through a source
  (otherwise the registry must label that source with the sink's observers).
- **A5 No side channels.** Timing, resource usage, error frequencies and index size are not observed.
- **A6 Trusted adapter implementation.** The Lean `Exec` monitor is covered by (d); the Python adapter/gateway only
  by differential testing (S3).

---

## 10. Changelog

| Date | Version | Author/model | Change |
|---|---|---|---|
| 2026-10-10 | 0.1 | claude-opus-5-5 (O1) | First draft from `docs/project-brief.md`. Open questions for F0: taint vs. clearance at read (§5.1), keep (b1) as theorem or Exec lemma (§7.3), Cedar on `report`/`receive`, schedule generality in (c), cost of the `receive` return channel (drop under G1 fallback). |
