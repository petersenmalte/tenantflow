import TenantFlow.Proofs
import TenantFlow.Proofs.Refinement

/-!
# Theorem (e): transparency (`docs/spec.md` §7.8)

Utility counterpart of the safety theorems (a)–(d).  An agent whose context is its own tenant's
trusted root label (`Single t ctx`: owners exactly `{t}`, integrity `trusted`) is never denied for
a *flow* reason: on such an agent the monitor's decision coincides with the label-free part of §5
(`LabelFree`: Cedar allows, the tool is registered and private to the tenant, `report` has a
parent, `receive` names an existing child).

* `transparency`: `(∃ r s', Allowed … act r s') ↔ LabelFree … act` under `Single`.
* `transparency_step`: on the step relation, `r = denied ↔ ¬ LabelFree`.
* `Single.step`: the context stays `Single` as long as the step mixes in only data owned by the
  tenant and trusted (result label of a called tool, docs returned by `query`, the child's context
  on `receive`); it is trivially preserved by `write`, `delegate`, `report` and by denials.
* `Single.of_init`: root agents start `Single`.
* `Exec.transparency_denied`: via (d), a denial by `Exec.step` on a `Single` agent means a
  label-free precondition failed.
-/

namespace TenantFlow.Model

section
variable {T U Ext Role Req Qry Pay Sid : Type} [DecidableEq Sid]
variable {cfg : Config T U Ext Role Req Qry Pay Sid} {D : Data T Ext Pay Sid}

omit [DecidableEq Sid] in
theorem Label.joinAll_le {ℓ : Label T} :
    ∀ {ls : List (Label T)}, (∀ l ∈ ls, l ≤ ℓ) → Label.joinAll ls ≤ ℓ
  | [], _ => Label.bot_le _
  | l :: _, h =>
    Label.join_le (h l (.head _)) (Label.joinAll_le fun l' hl' => h l' (.tail _ hl'))

omit [DecidableEq Sid] in
open Classical in
theorem readable_of_mem_readableDocs {t : T} {L : List (Doc T Pay)} {d : Doc T Pay}
    (h : d ∈ readableDocs t L) : readable t d.label := by
  unfold readableDocs at h
  exact of_decide_eq_true (List.mem_filter.1 h).2

/-- `ℓ` is the single-tenant trusted label of `t`: `ℓ ⊑ rootCtx t` (owners ⊆ {t}, trusted) and
`t` is an owner – i.e. `ℓ = rootCtx t` up to extensionality.  "The agent depends on nothing but
its own tenant's trusted data." -/
def Single (t : T) (ℓ : Label T) : Prop := ℓ ≤ rootCtx t ∧ ℓ.owners t

omit [DecidableEq Sid] in
theorem Single.of_root (t : T) : Single t (rootCtx t) := ⟨Label.le_refl _, rfl⟩

omit [DecidableEq Sid] in
theorem Single.readable {t : T} {ℓ : Label T} (h : Single t ℓ) : readable t ℓ :=
  fun u hu => h.1.1 u hu

omit [DecidableEq Sid] in
theorem Single.integ {t : T} {ℓ : Label T} (h : Single t ℓ) : ℓ.integ = .trusted :=
  Integrity.le_trusted h.1.2

omit [DecidableEq Sid] in
theorem Single.join {t : T} {ℓ ℓ' : Label T} (h : Single t ℓ) (h' : ℓ' ≤ rootCtx t) :
    Single t (ℓ.join ℓ') :=
  ⟨Label.join_le h.1 h', Or.inl h.2⟩

/-- The label-free preconditions of §5: the rows of `Allowed` without the flow checks
(`hobs`/`hint` on `call`, `hown` on `write`).  For `call` the tool must be registered and
*private to the tenant* (observers ⊆ {tenant}): a tool observed by another tenant is a
cross-tenant channel and not part of a single-tenant workflow. -/
inductive LabelFree (cfg : Config T U Ext Role Req Qry Pay Sid) :
    State T Ext Role Pay Sid → AgentId Sid → Action Ext Role Pay Qry → Prop
  | call {s a σ p k v i}
      (hσ : s.agents a = some σ) (hp : cfg.sessions σ.session = some p)
      (hauth : cfg.authorize (cfg.mkRequest σ.cedarP (.call k v)) = true)
      (hi : cfg.toolInfo p.tenant k = some i)
      (hpriv : ∀ u, i.observers u → u = p.tenant) :
      LabelFree cfg s a (.call k v)
  | query {s a σ p q}
      (hσ : s.agents a = some σ) (hp : cfg.sessions σ.session = some p)
      (hauth : cfg.authorize (cfg.mkRequest σ.cedarP (.query q)) = true) :
      LabelFree cfg s a (.query q)
  | write {s a σ p v}
      (hσ : s.agents a = some σ) (hp : cfg.sessions σ.session = some p)
      (hauth : cfg.authorize (cfg.mkRequest σ.cedarP (.write v)) = true) :
      LabelFree cfg s a (.write v)
  | delegate {s a σ p ρ v}
      (hσ : s.agents a = some σ) (hp : cfg.sessions σ.session = some p)
      (hauth : cfg.authorize (cfg.mkRequest σ.cedarP (.delegate ρ v)) = true) :
      LabelFree cfg s a (.delegate ρ v)
  | report {s a σ p v}
      (hσ : s.agents a = some σ) (hp : cfg.sessions σ.session = some p)
      (hpar : σ.parent ≠ none) :
      LabelFree cfg s a (.report v)
  | receive {s a σ p c σc}
      (hσ : s.agents a = some σ) (hp : cfg.sessions σ.session = some p)
      (hc : s.agents (childId a c) = some σc) :
      LabelFree cfg s a (.receive c)

/-- Every allowed step satisfies the label-free preconditions (on a `Single` agent the private-tool
condition follows from `hobs`). -/
theorem Allowed.labelFree {s s' : State T Ext Role Pay Sid} {a act r} {σ p}
    (hσ : s.agents a = some σ) (hp : cfg.sessions σ.session = some p)
    (hS : Single p.tenant σ.ctx) (h : Allowed cfg D s a act r s') : LabelFree cfg s a act := by
  cases h with
  | call hσ' hp' hauth hi hobs _ =>
    obtain rfl := Option.some.inj (hσ.symm.trans hσ')
    obtain rfl := Option.some.inj (hp.symm.trans hp')
    exact .call hσ' hp' hauth hi fun u hu => (hobs u hu _ hS.2).symm
  | query hσ' hp' hauth => exact .query hσ' hp' hauth
  | write hσ' hp' hauth _ => exact .write hσ' hp' hauth
  | delegate hσ' hp' hauth => exact .delegate hσ' hp' hauth
  | report hσ' hp' hpar => exact .report hσ' hp' hpar
  | receive hσ' hp' hc => exact .receive hσ' hp' hc

/-- On a `Single` agent the label-free preconditions suffice: the flow checks hold automatically. -/
theorem LabelFree.allowed {s : State T Ext Role Pay Sid} {a act} {σ p}
    (hσ : s.agents a = some σ) (hp : cfg.sessions σ.session = some p)
    (hS : Single p.tenant σ.ctx) (h : LabelFree cfg s a act) :
    ∃ r s', Allowed cfg D s a act r s' := by
  cases h with
  | call hσ' hp' hauth hi hpriv =>
    obtain rfl := Option.some.inj (hσ.symm.trans hσ')
    obtain rfl := Option.some.inj (hp.symm.trans hp')
    exact ⟨_, _, .call hσ' hp' hauth hi
      (fun u hu => by rw [hpriv u hu]; exact hS.readable) (fun _ => hS.integ)⟩
  | query hσ' hp' hauth => exact ⟨_, _, .query hσ' hp' hauth⟩
  | write hσ' hp' hauth =>
    obtain rfl := Option.some.inj (hσ.symm.trans hσ')
    obtain rfl := Option.some.inj (hp.symm.trans hp')
    exact ⟨_, _, .write hσ' hp' hauth hS.readable⟩
  | delegate hσ' hp' hauth => exact ⟨_, _, .delegate hσ' hp' hauth⟩
  | report hσ' hp' hpar => exact ⟨_, _, .report hσ' hp' hpar⟩
  | receive hσ' hp' hc => exact ⟨_, _, .receive hσ' hp' hc⟩

/-- **Theorem (e) transparency.**  For an agent `a` of tenant `t` whose context is `Single t`,
an action is allowed iff its label-free preconditions hold: the flow monitor never denies for a
flow reason.  Only Cedar, an unregistered or non-private tool, a `report` without parent or a
`receive` of a non-existent child can deny. -/
theorem transparency {s : State T Ext Role Pay Sid} {a act} {σ p}
    (hσ : s.agents a = some σ) (hp : cfg.sessions σ.session = some p)
    (hS : Single p.tenant σ.ctx) :
    (∃ r s', Allowed cfg D s a act r s') ↔ LabelFree cfg s a act :=
  ⟨fun ⟨_, _, h⟩ => h.labelFree hσ hp hS, fun h => h.allowed hσ hp hS⟩

/-- Theorem (e) on the step relation: the step of a `Single` agent is `denied` iff a label-free
precondition fails. -/
theorem transparency_step {s s' : State T Ext Role Pay Sid} {a act r} {σ p}
    (hσ : s.agents a = some σ) (hp : cfg.sessions σ.session = some p)
    (hS : Single p.tenant σ.ctx) (h : Step cfg D s a act r s') :
    r = .denied ↔ ¬ LabelFree cfg s a act := by
  cases h with
  | allowed hal =>
    exact ⟨fun hr => absurd hr hal.ne_denied, fun hn => absurd (hal.labelFree hσ hp hS) hn⟩
  | denied hn =>
    refine ⟨fun _ hL => ?_, fun _ => rfl⟩
    obtain ⟨r, s', hal⟩ := hL.allowed (D := D) hσ hp hS
    exact hn r s' hal

omit [DecidableEq Sid] in
/-- Root agents start `Single`. -/
theorem Single.of_init {sid : Sid} {p : Principal T U} (hp : cfg.sessions sid = some p) :
    (init cfg D).agents (sid, []) =
      some ⟨sid, cfg.principalRole p, rootCtx p.tenant, 0, [], none⟩ ∧
    Single p.tenant (rootCtx p.tenant) :=
  ⟨by simp [init, hp], Single.of_root _⟩

/-- **`Single` is preserved** by a step of the agent itself as long as the step mixes in only
labels `⊑ rootCtx t`: the result label of a called tool (`hcall`), the labels of the docs a
`query` returns (`hquery`; their owners are ⊆ {t} by the server-side filter, so only trustedness
is assumed), and the child's context on `receive` (`hrecv`).  `write`, `delegate`, `report` and
denials leave the context unchanged. -/
theorem Single.step {s s' : State T Ext Role Pay Sid} {a act r} {σ p}
    (hσ : s.agents a = some σ) (hp : cfg.sessions σ.session = some p)
    (hS : Single p.tenant σ.ctx)
    (hcall : ∀ k v i ℓ, act = .call k v → cfg.toolInfo p.tenant k = some i →
      i.result = some ℓ → ℓ ≤ rootCtx p.tenant)
    (hquery : ∀ q d, act = .query q → d ∈ cfg.rank q (readableDocs p.tenant s.index) →
      d.label.integ = .trusted)
    (hrecv : ∀ c σc, act = .receive c → s.agents (childId a c) = some σc →
      σc.ctx ≤ rootCtx p.tenant)
    (h : Step cfg D s a act r s') :
    ∃ σ', s'.agents a = some σ' ∧ Single p.tenant σ'.ctx := by
  cases h with
  | denied _ => exact ⟨σ, hσ, hS⟩
  | allowed hal =>
    cases hal with
    | @call _ _ k v i hσ' hp' _ hi _ _ =>
      obtain rfl := Option.some.inj (hσ.symm.trans hσ')
      obtain rfl := Option.some.inj (hp.symm.trans hp')
      refine ⟨{ σ with ctx := i.joinResult σ.ctx }, by simp, ?_⟩
      cases hres : i.result with
      | some ℓ =>
        simp only [ToolInfo.joinResult, hres]
        exact hS.join (hcall k v i ℓ rfl hi hres)
      | none => simpa only [ToolInfo.joinResult, hres] using hS
    | @query _ _ q hσ' hp' _ =>
      obtain rfl := Option.some.inj (hσ.symm.trans hσ')
      obtain rfl := Option.some.inj (hp.symm.trans hp')
      refine ⟨{ σ with ctx := σ.ctx.join (Label.joinAll
                ((cfg.rank q (readableDocs p.tenant s.index)).map (·.label))) }, by simp,
        hS.join (Label.joinAll_le ?_)⟩
      intro l hl
      obtain ⟨d, hd, rfl⟩ := List.mem_map.1 hl
      exact ⟨readable_of_mem_readableDocs (cfg.rank_mem _ _ _ hd),
        by rw [hquery q d rfl hd]; exact Integrity.trusted_le _⟩
    | write hσ' hp' _ _ => exact ⟨σ, hσ, hS⟩
    | @delegate _ _ _ _ hσ' hp' _ =>
      obtain rfl := Option.some.inj (hσ.symm.trans hσ')
      exact ⟨{ σ with nextChild := σ.nextChild + 1 }, by simp [ne_childId], hS⟩
    | @report _ _ v hσ' hp' _ =>
      obtain rfl := Option.some.inj (hσ.symm.trans hσ')
      exact ⟨{ σ with outbox := σ.outbox ++ [v] }, by simp, hS⟩
    | @receive _ _ c σc hσ' hp' hc =>
      obtain rfl := Option.some.inj (hσ.symm.trans hσ')
      obtain rfl := Option.some.inj (hp.symm.trans hp')
      exact ⟨{ σ with ctx := σ.ctx.join σc.ctx }, by simp [ne_childId],
        hS.join (hrecv c σc rfl hc)⟩

end

end TenantFlow.Model

namespace TenantFlow.Exec

open TenantFlow.Model (Single LabelFree Action AgentId)

variable {T U Ext Role Req Qry Pay Sid : Type} [DecidableEq T] [DecidableEq Ext] [DecidableEq Sid]

/-- Theorem (e) for the executable monitor, via (d): if `Exec.step` denies an action of an agent
whose abstract context is `Single`, a label-free precondition fails on the abstraction. -/
theorem transparency_denied (cfg : Config T U Ext Role Req Qry Pay Sid) (D : Data T Ext Pay Sid)
    (s : State T Ext Role Pay Sid) (a : AgentId Sid) (act : Action Ext Role Pay Qry)
    {msg : String} {s' : State T Ext Role Pay Sid} (h : step cfg D s a act = (.denied msg, s'))
    {σ p} (hσ : (State.abs s).agents a = some σ)
    (hp : (Config.abs cfg).sessions σ.session = some p) (hS : Single p.tenant σ.ctx) :
    ¬ LabelFree (Config.abs cfg) (State.abs s) a act := fun hL => by
  obtain ⟨r, t, hal⟩ := hL.allowed (D := Data.abs D) hσ hp hS
  exact (refines_denied cfg D s a act h).2 r t hal

end TenantFlow.Exec
