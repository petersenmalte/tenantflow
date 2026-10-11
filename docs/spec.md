# TenantFlow – Formal specification

Status: **v0.3** (v0.2: task F0, adversarial review by `claude-fable-5-1` of the v0.1 draft by `claude-opus-5-5`;
v0.3: task F6 adds theorem (e) transparency, §7.8).
Theorem statements in this file are owned by FABLE tasks (see `CLAUDE.md` §3.3); changes require a changelog
entry (§10). Review findings and the reasons for every v0.2 change: `docs/spec-review.md`.

Notation: `⊑` label order, `⊔` join, `⊥` bottom label. `t(s)` is the tenant of session `s`.
"Agent" always means an arbitrary, possibly adversarial program; nothing is assumed about its behaviour.

---

## 1. Scope and claim in one paragraph

Several tenants share one agent platform and one RAG index. A per-call authorizer (Cedar) decides each tool call
in isolation. TenantFlow adds a **trusted adapter** that attaches labels from trusted metadata only (the
authenticated session and a tool registry) and a **flow monitor** that tracks a floating context label per agent
instance and checks it at every point where data leaves the agent. We prove, in Lean 4, that for **every**
authorizer and **every** agent behaviour:
(a) nothing that may depend on data another tenant owns is ever delivered to a tenant's principals or tools,
(b) every label dominates the join of the registry labels of everything it may depend on; payload content never
    enters a label (no forgery, no laundering),
(c) what tenant B's principals and tools observe is a function of the data B may read alone (noninterference),
(d) the executable monitor used by the oracle and the tests implements the abstract model.

**Isolation comes from the flow monitor, not from Cedar.** Cedar is an opaque, universally quantified function
`authorize : Request → Decision`. No theorem about Cedar itself is claimed, and no theorem assumes anything about
the policies (in particular not "forbid overrides permit" or "default deny": with the monitor doing the isolation,
such a hypothesis would be unused and the statement would be misleading). Cedar's role is least privilege per call;
the benchmark measures what it adds, the proofs do not rely on it.

Honest summary of what carries the weight (details in `docs/spec-review.md`): (c) is the semantic guarantee.
(a) and (b) are label-soundness invariants whose proofs are straightforward inductions; their value is that they
are stated in terms of provenance and of the registry, which is what the deck and the game cite. (d) connects the
proofs to the code that runs.

---

## 2. Threat model

### 2.1 Attacker

- **The agent is the attacker.** Every agent instance (root agent or sub-agent) may choose any action with any
  payload at any step. This covers a prompt-injected LLM, a malicious tool-calling loop and a buggy orchestrator.
  In (a), (b), (d) this is modelled by universal quantification over action sequences; in (c) by universal
  quantification over agent *strategies* (§7.4).
- **Payloads are attacker-controlled.** Any payload (document text, tool result, tool arguments, ticket body,
  query string) may contain fields that look like labels (`security_label`, `owners`, `integrity: trusted`, …).
  This is the FIDES label-forgery class (APIsec Labs, see `docs/related-work.md`).
- **Cedar policies may be wrong.** Policies may be overly permissive (up to "permit everything"). The guarantees
  must hold for every authorizer.
- **Data of other tenants is adversarial.** Tenant A's documents and tool results may be crafted to influence
  tenant B's agents.

### 2.2 Trusted computing base

| Component | Trusted for | Covered by |
|---|---|---|
| Session authentication | `principal(s)` is the real, authenticated principal of session `s` | assumption A1 |
| Tool registry | observers, result labels and integrity requirements of tools are correct | assumption A2 |
| Adapter + monitor | implement the step function of §5 | theorem (d) for the Lean executable; differential testing (S3) for Python |
| Index server | filters by label **before** ranking / top-k | part of the model (§5, rule `query`); (d), S3 |
| Orchestrator | schedules agents independently of data (§7.4) | assumption A5 |
| Lean kernel, Lean compiler for the oracle | as usual | – |

### 2.3 Out of scope (non-goals)

- Side channels: timing, latency, resource usage, error rates, index size, rate limits, logs, scheduling order.
- Prompt injection that stays within the permissions of the affected tenant (e.g. tenant A's data tricks tenant
  A's agent into sending tenant A's data to a tool tenant A is allowed to use). That is an integrity/utility
  problem inside one tenant; TenantFlow only adds the integrity bit (§3) so that registries *can* require trusted
  inputs for certain tools. No integrity noninterference theorem is claimed (it would be the dual of (c)).
- **Isolation is at tenant granularity.** Users of the same tenant are not isolated from each other by the
  monitor; least privilege inside a tenant is Cedar's job and is not proven.
- Correctness of data classification (whether the registry labels a tool correctly).
- Bugs in the trusted adapter itself (only differential testing, no proof).
- Declassification / endorsement. There is no operation that lowers a label. (APPA's recoverable IFC is related
  work, not a feature.) Consequence: a tool observed by every tenant (e.g. a public web search that sees the
  query) can never be called by a runtime agent; the registry owner decides whether to register such a tool with
  `observers = ∅` (a trust decision under A2) or to leave it unusable.
- Several shared components (cache, shared agent memory, shared conversation history) in version 1.
- Messages from a parent to a child after delegation (would be `tell c v`, symmetric to `receive`); v1 has
  parent → child only at creation and child → parent via `report`/`receive`.
- Tools with memory and data that re-enters through another tool: assumption A4.

---

## 3. Labels

- `Tenant`: a type with decidable equality.
- `Integrity ::= trusted | untrusted`, ordered `trusted ≤ untrusted` ("untrusted wins").
- `Label := { owners : Set Tenant, integ : Integrity }`.
  - `owners` = the tenants whose data (may have) contributed. Confidentiality: more owners = more restrictive.
  - `ℓ₁ ⊑ ℓ₂ :⇔ ℓ₁.owners ⊆ ℓ₂.owners ∧ ℓ₁.integ ≤ ℓ₂.integ`
  - `ℓ₁ ⊔ ℓ₂ := (ℓ₁.owners ∪ ℓ₂.owners, max ℓ₁.integ ℓ₂.integ)`, `⊥ := (∅, trusted)`.
  - `(Label, ⊑, ⊔, ⊥)` is a join-semilattice with bottom (lemma).
- **Readable by tenant `u`:** `readable u ℓ :⇔ ℓ.owners ⊆ {u}`. Data with `owners = ∅` (public) is readable by all;
  data with two or more owners (joint data) is readable by nobody. `readable u` is downward closed under `⊑`.

Representation (decided in F1a): in `Model/` sets are predicates `Tenant → Prop`; in `Exec/` they are sorted,
duplicate-free lists so that `decide` and the oracle work without Mathlib.

---

## 4. System model

### 4.1 Static configuration (trusted, identical in all compared runs)

| Symbol | Meaning |
|---|---|
| `Principal = (tenant : Tenant, user : UserId)` | |
| `sessions : SessionId → Option Principal` | authenticated principal per session (A1) |
| `ToolId ::= deliver \| ext (k : ExtId)` | `deliver` = "response to the acting session's principal"; `ext k` = registered external tool |
| `ToolInfo = (observers : Set Tenant, needsTrusted : Bool, result : Option Label)` | who sees the **arguments** of a call; whether the arguments must be trusted; label of the **result** (`none`: the result is discarded, the agent only sees `ok`) |
| `extReg : ExtId → Option ToolInfo` | tool registry (A2) |
| `toolInfo t : ToolId → Option ToolInfo` | `deliver ↦ some (observers = {t}, needsTrusted = false, result = none)`; `ext k ↦ extReg k` |
| `CedarPrincipal` | entity on whose behalf Cedar is asked; root agents use `principal(s)`, sub-agents a role |
| `mkRequest : CedarPrincipal → Action → Request` | builds the Cedar request from the acting principal and the action only (A7); **may** include the payload (cedar-for-agents puts tool arguments into the context) |
| `authorize : Request → Decision` | **opaque, universally quantified**, `Decision ::= allow \| deny` |
| `rank : Query → List Doc → List Doc` | retrieval; universally quantified, subject to `rank_mem : ∀ q L d, d ∈ rank q L → d ∈ L` (a ranking selects, it does not fabricate) |

A tool is simultaneously a **sink** (its arguments reach `observers`) and a **source** (its result carries
`result`). A pure data source has `observers = ∅`; a pure sink has `result = none`. The old `read`/`send` pair
of v0.1 is the special case `observers = ∅` / `result = none`. Example: tenant B's CRM is
`(observers = {B}, needsTrusted = false, result = some ({B}, untrusted))`; a calculator is
`(observers = ∅, needsTrusted = false, result = some ⊥)`.

### 4.2 Data (what may differ between the runs compared in (c))

| Symbol | Meaning | Label |
|---|---|---|
| `tool : ExtId → Payload → Payload` | result of each external tool as a function of its arguments | `(extReg k).result` |
| `index₀ : List Doc`, `Doc = (label, payload)` | initial content of the shared index | stored per doc, set by adapter/config |
| `prompt : SessionId → Payload` | the user's request that starts the session | `({t(s)}, trusted)` |

`Payload` is an arbitrary type (in `Exec`: a JSON value). Nothing in the monitor inspects it except `rank`,
`mkRequest` and `tool`, which are parameters (§6, design rule D8).

### 4.3 Runtime state

- `index : List Doc` — **append-only**. There is no update or delete (an overwrite by tenant A of a tenant-B doc
  would be a write-up flow; deletion is out of scope for v1).
- `agents : AgentId → Option AgentState`, with `AgentId = (SessionId, List Nat)` (root = `(s, [])`, the `n`-th
  child of `a` is `a ++ [n]`; identifiers are allocated **locally**, so no global counter can carry information).
- `AgentState = { session : SessionId, cedarP : CedarPrincipal, ctx : Label, nextChild : Nat,
  outbox : List Payload, parent : Option AgentId }`.
- `events : List Event`, `Event = (tenant : Tenant, tool : ToolId, args : Payload, label : Label)`, one per
  **successful** `call`; `tenant` is the acting session's tenant. `observers e := {e.tenant}` if
  `e.tool = deliver`, else `(extReg k).observers`. Denials are returned to the acting agent, never to a principal.

Initial state `init cfg D`: one root agent per session `s` with `sessions s = some p`, `ctx = ({p.tenant}, trusted)`,
`cedarP = p`, `nextChild = 0`, `outbox = []`, `parent = none`; its first observation is `prompt s`;
`index = index₀`; `events = []`.

Ghost state (provenance) is **not** part of the state; it is a separate instrumentation layer, §7.1.

### 4.4 Agent actions

```
Action ::= call     (k : ToolId) (args : Payload)   -- tool call: args leave to observers, result comes back
         | query    (q : Query)                     -- shared index, filtered server-side
         | write    (v : Payload)                   -- append to shared index
         | delegate (role : CedarPrincipal) (task : Payload)
         | report   (v : Payload)                   -- sub-agent → its parent's view of it
         | receive  (c : Nat)                       -- parent collects from child a ++ [c]
```

Every action is mediated (A3, complete mediation). The response an agent receives is one of
`payload v`, `payloads vs`, `child n`, `ok`, `denied`. `Exec` may attach a reason to `denied` for diagnostics;
the model collapses all reasons to `denied` (§7.5). An agent that "stops" keeps choosing an action that is
denied (e.g. `receive` of a non-existent child); every denied action is a no-op on the state.

---

## 5. Monitor rules

For agent `a` with state `σa`, session `s = σa.session`, tenant `t = t(s)`, context label `ℓ = σa.ctx`:

`allowed(a, act) :⇔ authorize (mkRequest σa.cedarP act) = allow ∧ flowOK(a, act)` for `call`, `query`, `write`,
`delegate`. `report` and `receive` are internal to an already-authorized delegation and skip Cedar (decision D9).

| Action | `flowOK` | Effect if allowed | Response |
|---|---|---|---|
| `call k v` | `toolInfo t k = some i` (unregistered ⇒ deny, **never** a default); `∀ u ∈ i.observers, readable u ℓ`; `i.needsTrusted → ℓ.integ = trusted` | append event `(t, k, v, ℓ)`; if `i.result = some ℓr` then `ctx := ℓ ⊔ ℓr` | `payload (tool k v)` if `i.result = some _` (`k = ext k`), else `ok` |
| `query q` | – | `R := rank q (filter (readable t ∘ label) index)`; `ctx := ℓ ⊔ ⨆ label(R)` | `payloads (map payload R)` |
| `write v` | `ℓ.owners ⊆ {t}` | append `(ℓ, v)` to `index` | `ok` |
| `delegate ρ v` | – | create `a ++ [σa.nextChild]` with `session = s`, `cedarP = ρ`, `ctx = ℓ`, `parent = some a`, first observation `v`; `σa.nextChild += 1` | `child σa.nextChild` |
| `report v` | `σa.parent ≠ none` | append `v` to `σa.outbox` | `ok` |
| `receive c` | child `a ++ [c]` exists | `ctx := ℓ ⊔ ctx(child)`; `child.outbox := []` | `payloads child.outbox` |

If not allowed: state unchanged, the agent receives `denied`.

### Design decisions (reviewed in F0; D1–D7 confirmed, D8–D10 new)

1. **D1 Floating label, checked at the exits (taint, not block-at-read).** A call that only *reads* (observers = ∅)
   is never blocked by the flow monitor, only by Cedar. This matches the narrative "every call is Cedar-allowed,
   TenantFlow blocks the write" (game level 2) and the FIDES comparison. It relies on A3: the agent context is only
   observable through mediated actions. Alternative (LIO-style clearance `ctx.owners ⊆ {t}` checked at every
   label join): one extra conjunct in `flowOK`; strictly safer if A3 is doubted; not chosen for v1.
2. **D2 Filter before rank.** `rank` sees only readable docs and (by `rank_mem`) returns a selection of them.
   Top-k before filtering would let tenant-A documents displace tenant-B documents and leak through which B docs
   are returned.
3. **D3 Query filter uses the session tenant `t`, not `ctx`.** Docs with `owners = ∅` are returned to everyone.
4. **D4 Writes by a tainted agent are denied** (not stored under a label nobody can read). Every stored doc written
   at runtime therefore has `owners = {t}`; no runtime write can create a public or a joint document.
5. **D5 `ctx` always contains `t(s)`** (initial value; inherited by children; monotone). Consequently no runtime
   agent can call a tool whose observers include another tenant; see §2.3 for the public-tool consequence.
6. **D6 `receive` joins the child's *current* context**, also when the outbox is empty, so an empty answer cannot
   leak whether a tainted child chose to report.
7. **D7 Sub-agents inherit the session;** a delegated role may have **more Cedar rights** but never a lower label
   and never another tenant (game level 4). The role is attacker-chosen; nothing depends on Cedar restricting it.
8. **D8 Payloads are opaque by construction.** `Model` and `Exec` are polymorphic in the payload type `Pay`; the
   only components that consume a `Pay` are the parameters `rank`, `mkRequest` and `tool`. The monitor therefore
   *cannot* read a label out of a payload; §7.3 states the corresponding lemma.
9. **D9 Tool arguments are an output.** A tool call sends its arguments to the tool's observers; the registry says
   who they are. v0.1's argument-less `read` hid this channel (a tainted agent could have passed tenant-A data
   as the argument of a tenant-B tool).
10. **D10 `deliver` addresses the acting session's principal only.** The agent cannot pick the recipient.

---

## 6. Executable monitor (`Exec/`)

- `Exec.step : Config → ExecState → AgentId → Action → Response × ExecState`, total and computable, over concrete
  structures (payload = JSON in the oracle, labels = sorted lists, index = list, agents = association list).
  `Exec.step` is polymorphic in `Pay` (D8); `authorize` is a field of `Exec.Config` so that the oracle can be
  driven with "allow everything" or a policy table supplied in the trace.
- `rank` instantiated with a deterministic toy embedding and top-k; F1a proves `rank_mem` for it. Same algorithm
  as Python, documented in `docs/oracle-format.md` by S1.
- Labels are stored **next to** payloads, never inside them. Nothing in `Exec` parses a payload for label fields.
- The oracle (`lake exe oracle`, S1) runs `Exec.step` over a JSON trace. Python (`tenantflow.monitor`, S2) is a
  port; S3 compares them.

---

## 7. Theorems

All theorems quantify over: every tenant type, every configuration (including every `authorize`, `mkRequest`,
`rank` with `rank_mem`), every data `D`, and every agent behaviour. "Reachable" = reachable from `init cfg D` by
any finite sequence of `(AgentId, Action)` pairs under the step relation (denied actions included; they are
no-ops). `Model.Step cfg : State → AgentId → Action → Response → State → Prop` is **total and functional**
(lemma `Step.det`: for every state, agent and action there is exactly one `(resp, state')`), because `authorize`
and `rank` are functions; nondeterminism lives entirely in the agent.

### 7.1 Ghost provenance (instrumentation layer, used by (a) and (b))

`Origin ::= toolO ExtId | docO Nat | promptO SessionId`, `label₀ : Origin → Label` is the trusted label of an
origin (`(extReg k).result`, the initial doc label, `({t(s)}, trusted)`).

`GState := State × Ghost` where `Ghost` assigns `deps : Set Origin` to every agent, index doc, outbox entry and
event. `GStep` is `Step` plus the ghost update:
- initial: root agent `deps = {promptO s}`; initial doc `i` has `deps = {docO i}`;
- `call (ext k) v` with `result = some _`: agent `deps ∪= {toolO k}`; `query`: `∪=` deps of every returned doc;
  `receive`: `∪=` deps of child;
- the event of a `call`, the doc of a `write`, the outbox entry of a `report`, the child of a `delegate`: the
  produced object gets the agent's current `deps`.

Lemma `ghost_proj`: `GStep g a act r g' → Step g.1 a act r g'.1`, and every `Step` lifts to a `GStep` (the ghost
update is total). Hence (a) and (b2) below, proven on `GState`, hold for every `Step`-reachable state with the
ghost computed along any trace reaching it.

`deps` is defined **without looking at labels**; it over-approximates "may depend on" for an arbitrary agent,
because an arbitrary agent may put anything it has seen into any later payload. Its semantic justification is
(c), not (a): (a) says the labels are sound for `deps`; (c) says the observations really are independent of
unreadable data.

### 7.2 (a) Isolation

> **Theorem (a).** For every reachable ghost state and every event `e ∈ events`, every observer tenant
> `u ∈ observers e` and every origin `o ∈ deps(e)`: `readable u (label₀ o)`.
> In words: nothing that may depend on data another tenant owns ever reaches a principal or tool of tenant `u`.
>
> **(a-int)** For every reachable ghost state and every event `e` at a tool with `needsTrusted = true`: every
> `o ∈ deps(e)` has `(label₀ o).integ = trusted`.

Why not just "the event label is readable": that is the monitor's own check and would be true by definition.
(a) relates the check to provenance through the shared index and through delegation. Proof: (b2) for the acting
agent's `ctx`, the `call` check, and downward closure of `readable`. Expected difficulty: easy.

### 7.3 (b) No forgery, no laundering

> **Theorem (b) = (b2) No laundering.** For every reachable ghost state and every object `x` (agent context,
> index doc, outbox entry, event): `⨆ { label₀ o | o ∈ deps x } ⊑ label x`, where an outbox entry's label is
> the child's `ctx` at the time of the `report`.
> Additionally `ctx` is monotone along every trace for every agent, and a child's `ctx` at creation equals its
> parent's.

Reading: the only inputs to any label are registry labels (`label₀`) and other labels; no payload occurs in the
statement or in the rules. The lower bound holds for every payload, so a payload claiming `security_label:
trusted` cannot lower anything. (In the current rules equality holds; only `⊑` is claimed, so that conservative
tainting remains allowed. The converse "labels are no higher than provenance" is a utility property and not
claimed.)

> **Lemma (b1) Label–payload independence (`Exec`).** Let `skel` erase every payload in an `Exec` state, action
> and response (keeping labels, ids, registry, structure). If `skel s₁ = skel s₂`, `skel act₁ = skel act₂`, both
> actions get the same Cedar decision, and (for `query`) `rank` selects the same positions of the filtered index,
> then `skel (step s₁ a act₁) = skel (step s₂ a act₂)`.

(b1) is a lemma, not a headline theorem: in `Model` it is definitional, and in `Exec` the primary guarantee is
structural (D8: `Exec.step` is parametric in `Pay`, so a label field inside a JSON payload is unreachable by
the code). The lemma documents this for the Python port, whose test suite (S3, forgery suite in S5) is the
corresponding evidence. Proof in Lean: `cases act <;> simp [step]`; if it costs more than ~1 USD, drop it and
keep D8 plus the sanity examples 4 and 6 (§7.7). *Status (F1b): dropped; D8 and sanity examples 4 and 6 are the evidence.*

**(b1-default)** `toolInfo t k = none → call k v` is denied, for every `v` (no default label, in particular never a
default `trusted` – the second FIDES issue). Immediate from the rules; stated as sanity example 6.

### 7.4 (c) Noninterference

Agents are modelled as **strategies**: `Strategy := List Response → Action`, one per agent id
(`strat : AgentId → Strategy`), where the list is the agent's own observations so far (first entry: its prompt
or delegation task). A strategy is an arbitrary Lean function. A **schedule** `sched : List AgentId` fixes which
agent moves next; scheduling a non-existent agent is a no-op. `run cfg strat sched D : List Event` is the event
list after the whole schedule, starting from `init cfg D`.

Low equivalence for an observer tenant `B`: `D₁ ≈_B D₂` iff
- `tool₁ k = tool₂ k` (as functions) for every `k` with `(extReg k).result = some ℓ` and `readable B ℓ`,
- `filter (readable B ∘ label) index₀₁ = filter (readable B ∘ label) index₀₂` (order preserved; non-readable docs
  may differ arbitrarily in content, number and position),
- `prompt₁ s = prompt₂ s` for every session `s` with `t(s) = B`.

Observation: `obs_B evs := filter (fun e => B ∈ observers e) evs` (tool, arguments and label of every call that
tenant B's principals or tools receive).

> **Theorem (c).** For all `cfg, strat, sched, B, D₁, D₂`:
> `D₁ ≈_B D₂ → obs_B (run cfg strat sched D₁) = obs_B (run cfg strat sched D₂)`.

Remarks:
- This is stronger than "differ only in tenant-A data": everything B may not read may differ, including other
  tenants' data, joint data and the *existence* of documents.
- **Well-formedness for a nondeterministic agent.** An LLM sampler is a deterministic function of (seed,
  context); the seed is drawn independently of the data. Fixing the seed inside the strategy and quantifying
  over all strategies therefore covers every sampler; equal observations for every seed give equal observation
  distributions. Compared with LLMbda's termination-insensitive probabilistic noninterference (TIPNI): here
  strategies are total and schedules finite, so no run diverges and the termination-sensitive and -insensitive
  readings coincide. Whether a *real* agent stops early is a timing channel (A5). Whether an agent becomes tainted
  depends only on labels and Cedar decisions on its own (low) history, never on unreadable content, so "no
  response because the agent got tainted" is itself low.
- **Schedule.** The schedule is fixed in advance, i.e. independent of the data (A5). A data-dependent scheduler
  is a channel: an orchestrator that wakes the parent *because* a tainted child reported lets the parent act a
  different number of times in the two runs. Round-robin and any schedule computed before the run satisfy A5.
  Generalising to schedulers that are functions of the low history is possible later; not v1.
- **Expected proof shape** (lockstep simulation over the schedule). Relation between the two runs:
  (i) `filter (readable B ∘ label)` of the two indexes is equal;
  (ii) `obs_B` of the two event lists is equal;
  (iii) for every agent id `a`: either `a` exists in both runs, is *clean* (`ctx.owners ⊆ {B}`) and has identical
  state and observation history in both, or in each run `a` is *absent or tainted* (`ctx.owners ⊄ {B}`).
  The third clause matters: a tainted parent's `delegate` may be Cedar-denied in one run and allowed in the
  other, so a child may exist in one run only. D2, D4, D6, D9, D10 and `rank_mem` are what make the relation
  preserved; `Step.det` is what makes clean agents move identically.
  *Proven shape (F2):* the relation additionally has (iv) "children of a clean agent exist in one run iff in the
  other", and (iii) compares clean agents up to the outbox (outboxes equal for a clean child of a clean parent);
  see the changelog entry "F2 details" and `lean/TenantFlow/Proofs/Noninterference.lean`.
- Non-vacuity: a monitor that denies everything satisfies (a)–(c). Ruled out by §7.7.

### 7.5 (d) Refinement

> **Theorem (d).** There is an abstraction `α : ExecState → Model.State` and a response projection
> `⌊·⌋ : Exec.Response → Model.Response` (identity except that every `denied reason` maps to `denied`) such that,
> with `Model.rank` instantiated with `Exec`'s top-k function:
> - **(d1)** for every `s`, `a`, `act`: `Exec.step cfg s a act = (r, s') → Model.Step (α cfg) (α s) a act ⌊r⌋ (α s')`;
> - **(d2)** `α (Exec.init cfg D) = Model.init (α cfg) D`;
> - and (lemma, Model side) `Step.det` as in §7.
> Corollaries: if `Exec` answers `denied` then `s' = s` and no allowed model step exists (from (d1) + `Step.det`);
> (a), (b2) and (c) hold for `Exec` traces (lift along `α`; for (c), `obs_B` commutes with `α` and
> `Exec.run` maps to `Model.run`).

Expected difficulty: medium; hard cap per `TASKS.md`.

### 7.6 What the theorems do not say

- Nothing about Cedar: a permissive policy loses least privilege inside a tenant, not isolation.
- Nothing about users inside a tenant, side channels, tools with memory (A4), or the Python port beyond S3.
- About utility only (e) (§7.8): the flow checks are transparent on single-tenant trusted contexts. (a)–(c) alone
  hold for the monitor that denies everything; §7.7 is the evidence that the intended flows are allowed, the
  benchmark (S5) measures utility. (e) says nothing about Cedar's share of the denials and nothing once an agent
  has read untrusted or foreign data (then a denial *is* the intended behaviour).

### 7.7 Sanity (non-vacuity) examples

Required alongside (a)–(c), proven by evaluation on `Exec` (`decide` / `rfl`), with `authorize = fun _ => allow`:
1. A bank agent calls a bank source (`observers = ∅`, `result = some ({bank}, trusted)`), writes to the index; a
   second bank session queries and `call deliver`s it — all allowed, and the delivered payload equals the written
   one.
2. The same with an insurer session as the reader: the query returns nothing of the bank document.
3. Game level 2: an insurer agent calls a bank source (Cedar-allowed), then `write` is **denied**.
4. Game level 3: a source with `result = some ({A}, untrusted)` whose payload contains `"security_label":
   {"owners": [], "integrity": "trusted"}`: after the call, `ctx = ({t, A}, untrusted)`.
5. Game level 4: a delegated child with a more powerful role inherits the tainted label; its `call deliver` is
   denied; `receive` taints the parent.
6. `call (ext k) v` with `extReg k = none` is denied, for a payload `v` that claims to be trusted.
7. D9: a tainted insurer agent calls an insurer tool with `observers = {insurer}` passing bank data as the
   argument: denied. A clean insurer agent calling the same tool: allowed, and the event is in `obs_insurer`.

### 7.8 (e) Transparency (utility)

Definitions (`lean/TenantFlow/Proofs/Transparency.lean`):
- `Single t ℓ :⇔ ℓ ⊑ rootCtx t ∧ t ∈ ℓ.owners`, i.e. `ℓ = ({t}, trusted)` up to extensionality: the agent depends
  on nothing but its own tenant's trusted data.
- `LabelFree cfg s a act`: the preconditions of the §5 rows **without the flow checks** (`hobs`/`hint` on `call`,
  `hown` on `write`): the agent exists with an authenticated session; Cedar allows (`call`, `query`, `write`,
  `delegate`); for `call` the tool is registered **and private to the tenant** (`observers ⊆ {t}`); `report` has
  a parent; `receive c` names an existing child.

> **Theorem (e).** Let `s.agents a = some σ`, `cfg.sessions σ.session = some p` and `Single p.tenant σ.ctx`.
> Then for every action `act`:
> - **(e1)** `(∃ r s', Allowed cfg D s a act r s') ↔ LabelFree cfg s a act` (`Model.transparency`), and on the
>   step relation `Step cfg D s a act r s' → (r = denied ↔ ¬ LabelFree cfg s a act)` (`Model.transparency_step`).
>   So the flow monitor never denies such an agent for a flow reason: only Cedar, an unregistered or non-private
>   tool, a `report` without parent or a `receive` of a non-existent child can deny.
> - **(e2) preservation** (`Model.Single.step`): after a step of `a` the context is still `Single p.tenant`,
>   provided the step mixes in only labels `⊑ rootCtx p.tenant`: the result label of a called tool, the labels of
>   the docs a `query` returns (their owners are `⊆ {t}` by the server-side filter, so only trustedness is
>   assumed), and the child's `ctx` on `receive`. `write`, `delegate`, `report` and denials preserve it
>   unconditionally. Root agents start `Single` (`Model.Single.of_init`).
> - **(e-Exec)** via (d): `Exec.step cfg D s a act = (denied msg, s')` on an agent whose abstraction is `Single`
>   implies `¬ LabelFree (α cfg) (α s) a act` (`Exec.transparency_denied`).

Reading: a tenant whose workflow touches only its own trusted documents, tenant-private tools with trusted results,
and its own children is governed by Cedar alone; TenantFlow adds no denial. The moment untrusted or foreign data
enters the context, `Single` fails and (a)–(c) take over – that is the intended trade-off, not a utility loss.

Not stated: a trace-level "always `Single`" invariant (it would need the hypotheses of (e2) for every step, which is
a property of the data and the agent's choices, not of the monitor); nothing about Cedar's own denials.

Expected difficulty: low; proven in F6 (no change to `Model/`).

---

## 8. Lean signature sketch (binding for the shape, not for names; F1a decides details)

```lean
namespace TenantFlow.Model

inductive Integrity | trusted | untrusted
structure Label (T : Type) where
  owners : T → Prop
  integ  : Integrity

variable {T U Ext Role Req Pay Qry Sid : Type} [DecidableEq T]

structure Principal (T U) where tenant : T; user : U
inductive ToolId (Ext) | deliver | ext (k : Ext)
structure ToolInfo (T) where observers : T → Prop; needsTrusted : Bool; result : Option (Label T)
inductive Action (Ext Role Pay Qry)
  | call (k : ToolId Ext) (args : Pay) | query (q : Qry) | write (v : Pay)
  | delegate (ρ : Role) (v : Pay) | report (v : Pay) | receive (c : Nat)
inductive Response (Pay) | payload (v : Pay) | payloads (vs : List Pay) | child (n : Nat) | ok | denied

structure Config where
  sessions  : Sid → Option (Principal T U)
  extReg    : Ext → Option (ToolInfo T)
  mkRequest : Role → Action Ext Role Pay Qry → Req      -- A7: principal and action only
  authorize : Req → Bool                                -- opaque
  rank      : Qry → List (Doc T Pay) → List (Doc T Pay)
  rank_mem  : ∀ q L d, d ∈ rank q L → d ∈ L

structure Data where
  tool   : Ext → Pay → Pay
  index₀ : List (Doc T Pay)
  prompt : Sid → Pay

structure State where
  index  : List (Doc T Pay)
  agents : AgentId Sid → Option (AgentState T Role Pay Sid)
  events : List (Event T Ext Pay)

inductive Step (cfg : Config) : State → AgentId Sid → Action … → Response Pay → State → Prop
  -- one constructor per row of §5, plus `denied` (state unchanged)
theorem Step.det : Step cfg s a act r₁ s₁ → Step cfg s a act r₂ s₂ → r₁ = r₂ ∧ s₁ = s₂
theorem Step.total : ∃ r s', Step cfg s a act r s'

def Reachable (cfg : Config) (s₀ : State) : State → Prop := …   -- reflexive-transitive closure

-- ghost layer
structure GState where base : State; ghost : Ghost …
inductive GStep (cfg : Config) : GState → … → GState → Prop
theorem ghost_proj : GStep cfg g a act r g' → Step cfg g.base a act r g'.base
theorem ghost_lift : Step cfg s a act r s' → ∀ gh, ∃ gh', GStep cfg ⟨s, gh⟩ a act r ⟨s', gh'⟩

theorem isolation   (h : GReachable cfg (ginit cfg D) g) : ∀ e ∈ g.base.events, ∀ u, observers e u →
    ∀ o ∈ g.ghost.depsEvent e, readable u (label₀ cfg D o)                                   -- (a)
theorem no_launder  (h : GReachable cfg (ginit cfg D) g) : ∀ x, joinDeps x ⊑ labelOf x       -- (b2)

def Strategy (Pay) := List (Response Pay) → Action …
def run (cfg) (strat : AgentId Sid → Strategy Pay) (sched : List (AgentId Sid)) (D : Data) : List (Event …)
theorem noninterference (B : T) (h : lowEq B D₁ D₂) :
    obs B (run cfg strat sched D₁) = obs B (run cfg strat sched D₂)                           -- (c)
end TenantFlow.Model

namespace TenantFlow.Exec
def step (cfg : Config) : State → AgentId → Action → Response × State := …   -- polymorphic in Pay (D8)
theorem label_payload_indep : skel s₁ = skel s₂ → … → skel (step cfg s₁ a act₁) = skel (step cfg s₂ a act₂) -- (b1)
theorem refines : step cfg s a act = (r, s') → Model.Step (α cfg) (α s) a act ⌊r⌋ (α s')                 -- (d1)
theorem refines_init : α (init cfg D) = Model.init (α cfg) D                                            -- (d2)
end TenantFlow.Exec
```

---

## 9. Assumptions (stated with every guarantee)

- **A1 Trusted session.** `sessions s` is the authenticated principal; agents cannot change their session.
- **A2 Trusted registry.** Tool observers, result labels and integrity flags are configured correctly. In
  particular, every party that can see a tool's arguments (operators, logs of a third-party API) is in
  `observers`.
- **A3 Complete mediation.** Every interaction of an agent with data, the index, principals, tools and other
  agents goes through the monitor. The agent's internal context (LLM context window, scratchpad, logs) is not
  observable by any principal except through mediated actions.
- **A4 Stateless tools, closed world.** The result of a tool call is a function of its arguments (`tool k args`).
  A tool with memory, or data that leaves through one tool and re-enters through another, must be registered so
  that every tenant able to read the re-entering data is among the `observers` of the tool it entered through;
  then the write is subject to the same check as any other exit.
- **A5 No side channels, data-independent scheduling.** Timing, resource usage, error frequencies, index size
  and the order in which the orchestrator schedules agents are not observed and do not depend on data.
- **A6 Trusted adapter implementation.** The Lean `Exec` monitor is covered by (d); the Python adapter/gateway only
  by differential testing (S3).
- **A7 Cedar sees principal and action only.** `mkRequest` is a function of the acting Cedar principal and the
  action (including its payload). A deployment whose Cedar entities are derived from the index or from tool
  results adds a channel outside the model.
- **A8 Agents do not observe denial reasons.** The model collapses every denial to `denied` (§4.4, §7.5) and the
  strategies in (c) see `⌊r⌋` only. A deployment that returns the reason string of `Exec.step`/the Python monitor
  to the agent adds an observation the theorems do not cover (it is meant for the operator's log); whether a
  reason can carry non-`B`-readable information is not proven.

---

## 10. Changelog

| Date | Version | Author/model | Change |
|---|---|---|---|
| 2026-10-10 | 0.1 | claude-opus-5-5 (O1) | First draft from `docs/project-brief.md`. Open questions for F0: taint vs. clearance at read (§5.1), keep (b1) as theorem or Exec lemma (§7.3), Cedar on `report`/`receive`, schedule generality in (c), cost of the `receive` return channel (drop under G1 fallback). |
| 2026-10-10 | 0.2 | claude-fable-5-1 (F0) | Adversarial review, see `docs/spec-review.md`. `read`/`send` unified into `call k args` with a tool registry `(observers, needsTrusted, result)` (D9); `deliver` without recipient (D10); `rank_mem` side condition; ghost provenance moved to a separate `GState` layer so that `α` in (d) is definable; (d) restated as forward simulation (d1) + `Step.det`; (b) := (b2), (b1) demoted to an `Exec` lemma, D8 added; (c): simulation relation gets the "absent or tainted" clause, nondeterminism/termination remarks made precise; A4 (stateless tools), A5 (scheduling), A7 (Cedar inputs) added; tenant granularity, public tools, integrity NI listed as non-goals; sanity examples 6–7 added; D1 (taint) and no-Cedar-on-`report`/`receive` (D9) confirmed. |
| 2026-10-10 | 0.2 (F1a details) | claude-fable-5-1 (F1a) | No statement changed. Details decided per §8: `Step cfg D` takes `Data` (for `tool`); `Config.principalRole` embeds root principals into the Cedar principal type; `Step` = `Allowed` (one constructor per §5 row) + `denied`; `GStep` = `Step` + ghost-update function; ghost `deps` keyed by agent id, doc value and event value (equal objects share deps, an over-approximation); `Exec` owner sets are duplicate-free lists with set equality; `Exec.rank` = stable sort by score + top-k. |
| 2026-10-10 | 0.2 (F1b details) | claude-fable-5-1 (F1b) | No statement changed. (b2) `no_launder` states the join of the origin set pointwise (`∀ o ∈ deps x, label₀ o ⊑ label x`, equivalent to `⨆ … ⊑ label x`). `ctx` monotonicity (`ctx_mono`) is proven on `Reachable` from `init` via the auxiliary invariant `Fresh` (children numbered `≥ nextChild` do not exist, an agent exists only if its parent does), which guarantees that `delegate` never overwrites an existing agent; `ctx_mono_ghost` lifts it to `GReachable`. `child_ctx_eq` is stated per allowed `delegate` step. (b1) dropped per the §7.3 cost rule. |
| 2026-10-10 | 0.2 (F2 details) | claude-fable-5-1 (F2) | No statement changed; (c) proven as `Model.noninterference` (`lean/TenantFlow/Proofs/Noninterference.lean`; `Strategy`, `run`, `LowEq`, `obs` defined there because `run` needs `Step.total`). `run` uses the step *function* `stepFn` chosen from `Step.total`; `Step.det` shows it is the unique step. A root agent's first observation is `payload (prompt s)`, a child's is `payload task`. The simulation relation needed two strengthenings of the §7.4 sketch: (iv) children of a clean agent exist in one run iff in the other (otherwise `receive c` could be denied in one run and allowed in the other for a clean parent); and clause (iii) compares clean agents only *up to the outbox*, with outboxes required equal only for a clean child of a clean parent (a tainted parent may `receive`, i.e. clear the outbox of, a clean child in one run only; the child's own behaviour does not depend on its outbox). "Clean" additionally records that the session tenant is `B` (D5 as part of the relation instead of a separate invariant). `Fresh` (F1b) is part of the relation. |
| 2026-10-10 | 0.2 (F3 details) | claude-fable-5-1 (F3) | No statement changed; (d) proven in `lean/TenantFlow/Proofs/Refinement.lean`. Details decided per §8: `α` is `Exec.Config.abs` / `Exec.Data.abs` / `Exec.State.abs` (owner lists become membership predicates, association lists become lookup functions; `Data` is abstracted as well because `index₀` carries labels), `⌊·⌋` is `Exec.Response.abs`; `Model.rank` is instantiated as `(sortByScore (score q ·.payload) ·).take topK` over abstract docs (`sortByScore` made generic in the element type, `rank_mem` is `mem_sortByScore`); `Exec` now uses the model's `AgentId`/`childId`. (d1) `Exec.refines`, (d2) `Exec.refines_init`. Corollaries proven: `Exec.refines_denied` (a denial leaves the `Exec` state unchanged and no allowed model step exists), `Exec.refines_trace` / `Exec.refines_ghost` (the abstraction of every `runTrace` state is `Model.Reachable` / `GReachable` from the initial state, so (a), (b2) and `ctx_mono` apply to `Exec` traces). Not done: the (c) corollary for `Exec` (`Exec.run` does not exist yet; `obs` commuting with `α` is straightforward once it does) – optional task F4. |
| 2026-10-11 | 0.2 (F4 details) | claude-fable-5-1 (F4) | No statement changed; the (c) corollary of §7.5 is proven in `lean/TenantFlow/Proofs/NoninterferenceExec.lean`. `Exec.run` is `Model.run` with `Exec.step` in place of `stepFn` (same `Strategy`/schedule; `histUpdate` is applied to `⌊r⌋`, so strategies are reason-blind exactly as in the model, which collapses all denial reasons). `Exec.run_abs`: `α (Exec.run cfg strat sched D) = Model.run (α cfg) strat sched (α D)` (lockstep via (d1) + `Step.eq_stepFn` and (d2)); `Exec.obs_abs`: `α (obs_B evs) = Model.obs_B (α evs)`; `Exec.noninterference`: `LowEq (α cfg) B (α D₁) (α D₂) → α (obs_B (Exec.run … D₁)) = α (obs_B (Exec.run … D₂))`, i.e. the `B`-observable `Exec` events agree in tenant, tool, arguments and label-as-set (`α` on events only changes the label representation). Low equivalence is stated on the abstractions; no separate `Exec.LowEq` was introduced. |
| 2026-10-11 | 0.3 | claude-fable-5-1 (F6) | **New theorem (e) transparency (§7.8)**, the utility counterpart of (a)–(d); §7.6 updated accordingly. Statement shape decided in F6: the hypothesis "every origin the agent may depend on is owned by its tenant and trusted" is stated directly on the context (`Single t ctx`, i.e. `ctx = rootCtx t` up to extensionality) rather than through ghost `deps`, because `Inv` only gives the lower bound `label₀ o ⊑ ctx` (soundness), not the upper bound `ctx ⊑ ⨆ label₀ (deps a)` that the origin phrasing would need (a new invariant, out of budget and not needed: by (b) `ctx` dominates the origins, so `Single ctx` *implies* the origin condition). (e1) is an equivalence, so it also lists exactly the remaining denial reasons. The private-tool condition `observers ⊆ {t}` is part of `LabelFree`, not of the flow checks: a tool observed by another tenant is a cross-tenant channel, and denying it on a `Single` context is correct (`hobs` with `t ∈ owners` forces every observer to be `t`). (e2) is a one-step preservation lemma with explicit data hypotheses; no trace-level invariant (see §7.8). Proven in `lean/TenantFlow/Proofs/Transparency.lean`, `Model/` unchanged; no sorry. |
| 2026-10-11 | 0.3 (F7 review) | claude-fable-5-1 (F7) | No statement changed. Claim review of README, deck and game against the Lean statements: `docs/claim-review.md`; text fixes are task S23. §9: **A8** added (agents do not observe denial reasons) – it was implicit in §4.4/§7.5 and in `Exec.run` (`⌊·⌋` before `histUpdate`) but missing from every assumption list. |
