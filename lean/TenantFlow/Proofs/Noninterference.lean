import TenantFlow.Proofs

/-!
# Theorem (c) Noninterference (`docs/spec.md` §7.4)

Agents are strategies `List (Response Pay) → Action`; a schedule is a list of agent ids; `run` is the
event list after the schedule.  Low equivalence `LowEq cfg B D₁ D₂` and observation `obs cfg B` are
§7.4 verbatim.  The proof is a lockstep simulation over the schedule with the relation `Sim`:
(i) B-readable index equal, (ii) B-observable events equal, (iii) every agent is *clean in both runs*
(same state up to outbox, same history, session tenant `B`, ctx readable by `B`) or *absent-or-tainted
in each run*, (iv) children of a clean agent exist in one run iff in the other, and a clean child of a
clean parent has the same outbox in both runs.  (iv) is the strengthening of the spec's clause (iii)
needed for `receive`; the outbox exception in (iii) is needed because a tainted parent may `receive`
(and so clear the outbox of) a clean child in one run only.
-/

namespace TenantFlow.Model

section
variable {T U Ext Role Req Qry Pay Sid : Type} {cfg : Config T U Ext Role Req Qry Pay Sid}

/-! ## §7.4 definitions (those not needing decidable equality) -/

/-- A strategy maps the agent's own observation history to its next action. -/
abbrev Strategy (Ext Role Pay Qry : Type) := List (Response Pay) → Action Ext Role Pay Qry

/-- Run state: monitor state plus the observation history of every agent id. -/
structure RunState (T Ext Role Pay Sid : Type) where
  state : State T Ext Role Pay Sid
  hist : AgentId Sid → List (Response Pay)

/-- Initial run state: `init cfg D`; every root agent has observed its prompt. -/
def initRun (cfg : Config T U Ext Role Req Qry Pay Sid) (D : Data T Ext Pay Sid) :
    RunState T Ext Role Pay Sid where
  state := init cfg D
  hist := fun a => match a.2 with
    | [] => [.payload (D.prompt a.1)]
    | _ => []

/-- Low equivalence `D₁ ≈_B D₂` (§7.4). -/
structure LowEq (cfg : Config T U Ext Role Req Qry Pay Sid) (B : T) (D₁ D₂ : Data T Ext Pay Sid) :
    Prop where
  tool : ∀ k i ℓ, cfg.extReg k = some i → i.result = some ℓ → readable B ℓ → D₁.tool k = D₂.tool k
  index₀ : readableDocs B D₁.index₀ = readableDocs B D₂.index₀
  prompt : ∀ s p, cfg.sessions s = some p → p.tenant = B → D₁.prompt s = D₂.prompt s

/-! ## Generic facts about labels, filters and observations -/

open Classical in
/-- `obs_B`: the events whose observers include `B` (§7.4). -/
noncomputable def obs (cfg : Config T U Ext Role Req Qry Pay Sid) (B : T)
    (evs : List (Event T Ext Pay)) : List (Event T Ext Pay) :=
  evs.filter fun e => decide (cfg.observersOf e B)

/-- `a` is absent or tainted (context not readable by `B`). -/
def Tainted (B : T) (o : Option (AgentState T Role Pay Sid)) : Prop :=
  ∀ σ, o = some σ → ¬ readable B σ.ctx

theorem Tainted.none {B : T} : Tainted B (none : Option (AgentState T Role Pay Sid)) :=
  fun _ h => nomatch h

theorem Tainted.of_le {B : T} {σ σ' : AgentState T Role Pay Sid} (h : σ.ctx ≤ σ'.ctx)
    (ht : Tainted B (some σ)) : Tainted B (some σ') :=
  fun τ hτ hr => by cases hτ; exact ht σ rfl (readable_mono h hr)

theorem readable_join {B : T} {l₁ l₂ : Label T} (h₁ : readable B l₁) (h₂ : readable B l₂) :
    readable B (l₁.join l₂) :=
  fun t ht => ht.elim (h₁ t) (h₂ t)

theorem readable_joinAll {B : T} (ls : List (Label T)) (h : ∀ l ∈ ls, readable B l) :
    readable B (Label.joinAll ls) := by
  induction ls with
  | nil => exact fun _ h => h.elim
  | cons l ls ih =>
    exact readable_join (h l (List.Mem.head _)) (ih fun l' hl' => h l' (List.Mem.tail _ hl'))

theorem readable_joinResult {B : T} {i : ToolInfo T} {ℓ : Label T} (hℓ : readable B ℓ)
    (hr : ∀ ℓr, i.result = some ℓr → readable B ℓr) : readable B (i.joinResult ℓ) := by
  unfold ToolInfo.joinResult
  cases h : i.result with
  | none => exact hℓ
  | some ℓr => exact readable_join hℓ (hr ℓr h)

theorem le_joinResult (i : ToolInfo T) (ℓ : Label T) : ℓ ≤ i.joinResult ℓ := by
  unfold ToolInfo.joinResult
  cases i.result
  · exact Label.le_refl _
  · exact Label.le_join_left _ _

theorem readableDocs_append (t : T) (L₁ L₂ : List (Doc T Pay)) :
    readableDocs t (L₁ ++ L₂) = readableDocs t L₁ ++ readableDocs t L₂ := by
  unfold readableDocs; exact List.filter_append ..

theorem readableDocs_singleton_of_readable {t : T} {d : Doc T Pay} (h : readable t d.label) :
    readableDocs t [d] = [d] := by
  unfold readableDocs; simp [h]

theorem readableDocs_singleton_of_not {t : T} {d : Doc T Pay} (h : ¬ readable t d.label) :
    readableDocs t [d] = [] := by
  unfold readableDocs; simp [h]

theorem mem_readableDocs {t : T} {d : Doc T Pay} {L : List (Doc T Pay)} (h : d ∈ readableDocs t L) :
    readable t d.label := by
  unfold readableDocs at h
  have := (List.mem_filter.mp h).2
  simpa using this

theorem obs_append (B : T) (e₁ e₂ : List (Event T Ext Pay)) :
    obs cfg B (e₁ ++ e₂) = obs cfg B e₁ ++ obs cfg B e₂ := by
  unfold obs; exact List.filter_append ..

theorem obs_singleton_of_not {B : T} {e : Event T Ext Pay} (h : ¬ cfg.observersOf e B) :
    obs cfg B [e] = [] := by
  unfold obs; simp [h]


theorem callResp_ne_child (D : Data T Ext Pay Sid) (k : ToolId Ext) (i : ToolInfo T) (v : Pay) (n : Nat) :
    callResp D k i v ≠ .child n := by
  unfold callResp; split <;> simp

theorem Tainted.of_not_readable {B : T} {σ : AgentState T Role Pay Sid} (h : ¬ readable B σ.ctx) :
    Tainted B (some σ) :=
  fun τ hτ => by cases hτ; exact h

theorem Tainted.not_readable {B : T} {σ : AgentState T Role Pay Sid} (h : Tainted B (some σ)) :
    ¬ readable B σ.ctx :=
  h σ rfl

theorem ne_child_denied (n : Nat) : (Response.denied : Response Pay) ≠ .child n := fun h => nomatch h
theorem ne_child_ok (n : Nat) : (Response.ok : Response Pay) ≠ .child n := fun h => nomatch h
theorem ne_child_payloads (vs : List Pay) (n : Nat) : (Response.payloads vs) ≠ .child n :=
  fun h => nomatch h

/-! ## The simulation relation -/

/-- Equal agent states up to the outbox. -/
def EqUpToOutbox (σ₁ σ₂ : AgentState T Role Pay Sid) : Prop :=
  σ₁.session = σ₂.session ∧ σ₁.cedarP = σ₂.cedarP ∧ σ₁.ctx = σ₂.ctx ∧
    σ₁.nextChild = σ₂.nextChild ∧ σ₁.parent = σ₂.parent

theorem EqUpToOutbox.refl (σ : AgentState T Role Pay Sid) : EqUpToOutbox σ σ :=
  ⟨rfl, rfl, rfl, rfl, rfl⟩

theorem EqUpToOutbox.symm {σ₁ σ₂ : AgentState T Role Pay Sid} (h : EqUpToOutbox σ₁ σ₂) :
    EqUpToOutbox σ₂ σ₁ :=
  ⟨h.1.symm, h.2.1.symm, h.2.2.1.symm, h.2.2.2.1.symm, h.2.2.2.2.symm⟩

/-- `a` is clean in both runs: same state up to the outbox, same history, session tenant `B`,
context readable by `B`. -/
def Clean (cfg : Config T U Ext Role Req Qry Pay Sid) (B : T)
    (o₁ o₂ : Option (AgentState T Role Pay Sid)) (h₁ h₂ : List (Response Pay)) : Prop :=
  ∃ σ₁ σ₂, o₁ = some σ₁ ∧ o₂ = some σ₂ ∧ EqUpToOutbox σ₁ σ₂ ∧ readable B σ₁.ctx ∧
    (∃ p, cfg.sessions σ₁.session = some p ∧ p.tenant = B) ∧ h₁ = h₂

theorem Clean.symm {B : T} {o₁ o₂ : Option (AgentState T Role Pay Sid)} {h₁ h₂}
    (h : Clean cfg B o₁ o₂ h₁ h₂) : Clean cfg B o₂ o₁ h₂ h₁ := by
  obtain ⟨σ₁, σ₂, e₁, e₂, he, hr, ⟨p, hp, ht⟩, hh⟩ := h
  exact ⟨σ₂, σ₁, e₂, e₁, he.symm, he.2.2.1 ▸ hr, ⟨p, he.1 ▸ hp, ht⟩, hh.symm⟩

theorem Clean.not_tainted {B : T} {o₁ o₂ : Option (AgentState T Role Pay Sid)} {h₁ h₂}
    (h : Clean cfg B o₁ o₂ h₁ h₂) (ht : Tainted B o₁) : False := by
  obtain ⟨σ₁, σ₂, e₁, e₂, he, hr, hp, hh⟩ := h
  exact ht _ e₁ hr

theorem Clean.not_tainted' {B : T} {o₁ o₂ : Option (AgentState T Role Pay Sid)} {h₁ h₂}
    (h : Clean cfg B o₁ o₂ h₁ h₂) (ht : Tainted B o₂) : False :=
  h.symm.not_tainted ht

theorem Clean.isSome {B : T} {o₁ o₂ : Option (AgentState T Role Pay Sid)} {h₁ h₂}
    (h : Clean cfg B o₁ o₂ h₁ h₂) : o₁ ≠ none ∧ o₂ ≠ none := by
  obtain ⟨σ₁, σ₂, e₁, e₂, -⟩ := h
  exact ⟨by simp [e₁], by simp [e₂]⟩

structure Sim (cfg : Config T U Ext Role Req Qry Pay Sid) (B : T)
    (rs₁ rs₂ : RunState T Ext Role Pay Sid) : Prop where
  fresh₁ : Fresh rs₁.state
  fresh₂ : Fresh rs₂.state
  index : readableDocs B rs₁.state.index = readableDocs B rs₂.state.index
  events : obs cfg B rs₁.state.events = obs cfg B rs₂.state.events
  agents : ∀ a, Clean cfg B (rs₁.state.agents a) (rs₂.state.agents a) (rs₁.hist a) (rs₂.hist a) ∨
    (Tainted B (rs₁.state.agents a) ∧ Tainted B (rs₂.state.agents a))
  childEx : ∀ a, Clean cfg B (rs₁.state.agents a) (rs₂.state.agents a) (rs₁.hist a) (rs₂.hist a) →
    ∀ c, (rs₁.state.agents (childId a c) = none ↔ rs₂.state.agents (childId a c) = none)
  childOutbox : ∀ a, Clean cfg B (rs₁.state.agents a) (rs₂.state.agents a) (rs₁.hist a) (rs₂.hist a) →
    ∀ c, Clean cfg B (rs₁.state.agents (childId a c)) (rs₂.state.agents (childId a c))
      (rs₁.hist (childId a c)) (rs₂.hist (childId a c)) →
    (rs₁.state.agents (childId a c)).map AgentState.outbox =
      (rs₂.state.agents (childId a c)).map AgentState.outbox

theorem Sim.symm {B : T} {rs₁ rs₂ : RunState T Ext Role Pay Sid} (h : Sim cfg B rs₁ rs₂) :
    Sim cfg B rs₂ rs₁ where
  fresh₁ := h.fresh₂
  fresh₂ := h.fresh₁
  index := h.index.symm
  events := h.events.symm
  agents := fun a => (h.agents a).elim (fun hc => Or.inl hc.symm) (fun ht => Or.inr ⟨ht.2, ht.1⟩)
  childEx := fun a hc c => (h.childEx a hc.symm c).symm
  childOutbox := fun a hc c hcc => (h.childOutbox a hc.symm c hcc.symm).symm

/-- A child of a child of `a` is never `a`, and `childId` is injective in the parent. -/
theorem childId_eq_childId_iff {a b : AgentId Sid} {m n : Nat} :
    childId a m = childId b n ↔ a = b ∧ m = n :=
  ⟨childId_inj, fun ⟨h₁, h₂⟩ => h₁ ▸ h₂ ▸ rfl⟩

/-! ### Generic preservation 1: a step of an absent-or-tainted agent in one run only -/

/-- What a step of absent-or-tainted `a` may do to agent `b` of run 1. -/
def LeftOK (B : T) (a : AgentId Sid) (s s' : State T Ext Role Pay Sid)
    (hist hist' : AgentId Sid → List (Response Pay)) (b : AgentId Sid) : Prop :=
  (s'.agents b = s.agents b ∧ hist' b = hist b) ∨
  (Tainted B (s.agents b) ∧ Tainted B (s'.agents b) ∧
    ((s'.agents b = none ↔ s.agents b = none) ∨ ∃ n, b = childId a n)) ∨
  (hist' b = hist b ∧ (∃ n, b = childId a n) ∧
    ∃ σ ob, s.agents b = some σ ∧ s'.agents b = some { σ with outbox := ob })

theorem Sim.left {B : T} {rs₁ rs₂ : RunState T Ext Role Pay Sid} (hS : Sim cfg B rs₁ rs₂)
    {a : AgentId Sid} (hT : Tainted B (rs₁.state.agents a))
    {s₁' : State T Ext Role Pay Sid} {hist₁' : AgentId Sid → List (Response Pay)}
    (hF : Fresh s₁')
    (hI : readableDocs B s₁'.index = readableDocs B rs₁.state.index)
    (hE : obs cfg B s₁'.events = obs cfg B rs₁.state.events)
    (hA : ∀ b, LeftOK B a rs₁.state s₁' rs₁.hist hist₁' b) :
    Sim cfg B ⟨s₁', hist₁'⟩ rs₂ := by
  -- a clean (after) agent was clean before, with the same `agents` value up to outbox
  have cleanBefore : ∀ b, Clean cfg B (s₁'.agents b) (rs₂.state.agents b) (hist₁' b) (rs₂.hist b) →
      Clean cfg B (rs₁.state.agents b) (rs₂.state.agents b) (rs₁.hist b) (rs₂.hist b) ∧ b ≠ a := by
    intro b hc
    have hba : b ≠ a := by
      rintro rfl
      rcases hA b with ⟨e, h⟩ | ⟨ht, ht', _⟩ | ⟨h, ⟨n, hn⟩, σ, ob, e, e'⟩
      · exact (e ▸ h ▸ hc).not_tainted hT
      · exact hc.not_tainted ht'
      · exact hT σ e (by
          obtain ⟨σ₁, σ₂, e₁, e₂, he, hr, hp, hh⟩ := hc
          rw [e'] at e₁; cases e₁; exact hr)
    refine ⟨?_, hba⟩
    rcases hA b with ⟨e, h⟩ | ⟨ht, ht', _⟩ | ⟨h, ⟨n, hn⟩, σ, ob, e, e'⟩
    · exact e ▸ h ▸ hc
    · exact (hc.not_tainted ht').elim
    · obtain ⟨σ₁, σ₂, e₁, e₂, he, hr, hp, hh⟩ := hc
      rw [e'] at e₁; cases e₁
      exact ⟨σ, σ₂, e, e₂, he, hr, hp, h ▸ hh⟩
  refine ⟨hF, hS.fresh₂, hI.trans hS.index, hE.trans hS.events, ?_, ?_, ?_⟩
  · intro b
    rcases hA b with ⟨e, h⟩ | ⟨ht, ht', _⟩ | ⟨h, ⟨n, hn⟩, σ, ob, e, e'⟩
    · simp only [e, h]; exact hS.agents b
    · right
      refine ⟨ht', ?_⟩
      rcases hS.agents b with hc | ⟨_, ht₂⟩
      · exact (hc.not_tainted ht).elim
      · exact ht₂
    · rcases hS.agents b with ⟨σ₁, σ₂, e₁, e₂, he, hr, hp, hh⟩ | ⟨ht₁, ht₂⟩
      · left
        rw [e] at e₁; cases e₁
        exact ⟨_, σ₂, e', e₂, he, hr, hp, by show hist₁' b = _; rw [h]; exact hh⟩
      · right
        refine ⟨fun τ hτ => ?_, ht₂⟩
        rw [e'] at hτ; cases hτ
        exact ht₁ σ e
  · intro b hc c
    obtain ⟨hcb, hba⟩ := cleanBefore b hc
    rcases hA (childId b c) with ⟨e, _⟩ | ⟨_, _, hex | ⟨n, hn⟩⟩ | ⟨_, ⟨n, hn⟩, σ, ob, e, e'⟩
    · rw [e]; exact hS.childEx b hcb c
    · rw [hex]; exact hS.childEx b hcb c
    · exact absurd (childId_inj hn).1 hba
    · exact absurd (childId_inj hn).1 hba
  · intro b hc c hcc
    obtain ⟨hcb, hba⟩ := cleanBefore b hc
    rcases hA (childId b c) with ⟨e, h⟩ | ⟨_, ht', _⟩ | ⟨_, ⟨n, hn⟩, _⟩
    · rw [e]; exact hS.childOutbox b hcb c (cleanBefore _ hcc).1
    · exact (hcc.not_tainted ht').elim
    · exact absurd (childId_inj hn).1 hba

/-! ### Generic preservation 2: lockstep step of a clean agent -/

/-- What a lockstep step of clean `a` may do to agent `b` in both runs. -/
def LockOK (cfg : Config T U Ext Role Req Qry Pay Sid) (B : T)
    (s₁ s₂ s₁' s₂' : State T Ext Role Pay Sid)
    (hist₁ hist₂ hist₁' hist₂' : AgentId Sid → List (Response Pay)) (b : AgentId Sid) : Prop :=
  (s₁'.agents b = s₁.agents b ∧ s₂'.agents b = s₂.agents b ∧
    hist₁' b = hist₁ b ∧ hist₂' b = hist₂ b) ∨
  (Clean cfg B (s₁'.agents b) (s₂'.agents b) (hist₁' b) (hist₂' b) ∧
    (Clean cfg B (s₁.agents b) (s₂.agents b) (hist₁ b) (hist₂ b) ∨
      (s₁.agents b = none ∧ s₂.agents b = none)) ∧
    ((s₁.agents b).map AgentState.outbox = (s₂.agents b).map AgentState.outbox →
      (s₁'.agents b).map AgentState.outbox = (s₂'.agents b).map AgentState.outbox)) ∨
  (Tainted B (s₁'.agents b) ∧ Tainted B (s₂'.agents b) ∧ (s₁'.agents b = none ↔ s₂'.agents b = none))

theorem Sim.lock {B : T} {rs₁ rs₂ : RunState T Ext Role Pay Sid} (hS : Sim cfg B rs₁ rs₂)
    {s₁' s₂' : State T Ext Role Pay Sid} {hist₁' hist₂' : AgentId Sid → List (Response Pay)}
    (hF₁ : Fresh s₁') (hF₂ : Fresh s₂')
    (hI : readableDocs B s₁'.index = readableDocs B s₂'.index)
    (hE : obs cfg B s₁'.events = obs cfg B s₂'.events)
    (hA : ∀ b, LockOK cfg B rs₁.state rs₂.state s₁' s₂' rs₁.hist rs₂.hist hist₁' hist₂' b) :
    Sim cfg B ⟨s₁', hist₁'⟩ ⟨s₂', hist₂'⟩ := by
  -- a clean (after) agent was clean before or absent before in both runs
  have cleanBefore : ∀ b, Clean cfg B (s₁'.agents b) (s₂'.agents b) (hist₁' b) (hist₂' b) →
      Clean cfg B (rs₁.state.agents b) (rs₂.state.agents b) (rs₁.hist b) (rs₂.hist b) ∨
        (rs₁.state.agents b = none ∧ rs₂.state.agents b = none) := by
    intro b hc
    rcases hA b with ⟨e₁, e₂, h₁, h₂⟩ | ⟨_, hb, _⟩ | ⟨ht, _, _⟩
    · left; exact e₁ ▸ e₂ ▸ h₁ ▸ h₂ ▸ hc
    · exact hb
    · exact (hc.not_tainted ht).elim
  -- children of an agent absent in both runs are absent in both runs
  have absentChild : ∀ b c, rs₁.state.agents b = none → rs₂.state.agents b = none →
      rs₁.state.agents (childId b c) = none ∧ rs₂.state.agents (childId b c) = none := by
    intro b c h₁ h₂
    constructor
    · cases h : rs₁.state.agents (childId b c) with
      | none => rfl
      | some σ => obtain ⟨σp, hp⟩ := hS.fresh₁.parent b c σ h; rw [h₁] at hp; exact nomatch hp
    · cases h : rs₂.state.agents (childId b c) with
      | none => rfl
      | some σ => obtain ⟨σp, hp⟩ := hS.fresh₂.parent b c σ h; rw [h₂] at hp; exact nomatch hp
  refine ⟨hF₁, hF₂, hI, hE, ?_, ?_, ?_⟩
  · intro b
    rcases hA b with ⟨e₁, e₂, h₁, h₂⟩ | ⟨hc, _, _⟩ | ⟨ht₁, ht₂, _⟩
    · simp only [e₁, e₂, h₁, h₂]; exact hS.agents b
    · exact Or.inl hc
    · exact Or.inr ⟨ht₁, ht₂⟩
  · intro b hc c
    rcases hA (childId b c) with ⟨e₁, e₂, _, _⟩ | ⟨hcc, _, _⟩ | ⟨_, _, hex⟩
    · rw [e₁, e₂]
      rcases cleanBefore b hc with hcb | ⟨n₁, n₂⟩
      · exact hS.childEx b hcb c
      · obtain ⟨a₁, a₂⟩ := absentChild b c n₁ n₂
        rw [a₁, a₂]
    · obtain ⟨n₁, n₂⟩ := hcc.isSome
      exact ⟨fun h => (n₁ h).elim, fun h => (n₂ h).elim⟩
    · exact hex
  · intro b hc c hcc
    rcases hA (childId b c) with ⟨e₁, e₂, h₁, h₂⟩ | ⟨_, hbefore, himp⟩ | ⟨ht, _, _⟩
    · rw [e₁, e₂]
      rcases cleanBefore b hc with hcb | ⟨n₁, n₂⟩
      · exact hS.childOutbox b hcb c (e₁ ▸ e₂ ▸ h₁ ▸ h₂ ▸ hcc)
      · obtain ⟨a₁, a₂⟩ := absentChild b c n₁ n₂
        rw [a₁, a₂]
    · apply himp
      rcases hbefore with hcc₀ | ⟨n₁, n₂⟩
      · rcases cleanBefore b hc with hcb | ⟨n₁, n₂⟩
        · exact hS.childOutbox b hcb c hcc₀
        · obtain ⟨a₁, a₂⟩ := absentChild b c n₁ n₂
          exact (hcc₀.isSome.1 a₁).elim
      · rw [n₁, n₂]
    · exact (hcc.not_tainted ht).elim

end

section
variable {T U Ext Role Req Qry Pay Sid : Type} [DecidableEq Sid]
variable {cfg : Config T U Ext Role Req Qry Pay Sid}

/-! ## §7.4 definitions: the run function -/

/-- The (unique, by `Step.det`) step as a function; exists by `Step.total`. -/
noncomputable def stepFn (cfg : Config T U Ext Role Req Qry Pay Sid) (D : Data T Ext Pay Sid)
    (s : State T Ext Role Pay Sid) (a : AgentId Sid) (act : Action Ext Role Pay Qry) :
    Response Pay × State T Ext Role Pay Sid :=
  let h := Step.total (cfg := cfg) (D := D) s a act
  (Classical.choose h, Classical.choose (Classical.choose_spec h))

theorem stepFn_spec (D : Data T Ext Pay Sid) (s : State T Ext Role Pay Sid) (a : AgentId Sid)
    (act : Action Ext Role Pay Qry) :
    Step cfg D s a act (stepFn cfg D s a act).1 (stepFn cfg D s a act).2 :=
  Classical.choose_spec (Classical.choose_spec (Step.total (cfg := cfg) (D := D) s a act))

theorem Step.eq_stepFn {D : Data T Ext Pay Sid} {s s' : State T Ext Role Pay Sid} {a act r}
    (h : Step cfg D s a act r s') : stepFn cfg D s a act = (r, s') := by
  obtain ⟨h₁, h₂⟩ := Step.det (stepFn_spec (cfg := cfg) D s a act) h
  exact Prod.ext h₁ h₂

/-- History update: the acting agent sees its response; a new child's first observation is its task. -/
def histUpdate (hist : AgentId Sid → List (Response Pay)) (a : AgentId Sid)
    (act : Action Ext Role Pay Qry) (r : Response Pay) : AgentId Sid → List (Response Pay) :=
  fun a' =>
    match act, r with
    | .delegate _ v, .child n =>
      if a' = childId a n then [.payload v] else if a' = a then hist a ++ [r] else hist a'
    | _, _ => if a' = a then hist a ++ [r] else hist a'

/-- One scheduled move: a no-op if the agent does not exist, else the strategy's action is stepped. -/
noncomputable def runStep (cfg : Config T U Ext Role Req Qry Pay Sid) (D : Data T Ext Pay Sid)
    (strat : AgentId Sid → Strategy Ext Role Pay Qry) (rs : RunState T Ext Role Pay Sid)
    (a : AgentId Sid) : RunState T Ext Role Pay Sid :=
  match rs.state.agents a with
  | none => rs
  | some _ =>
    let act := strat a (rs.hist a)
    let rs' := stepFn cfg D rs.state a act
    ⟨rs'.2, histUpdate rs.hist a act rs'.1⟩

noncomputable def runAll (cfg : Config T U Ext Role Req Qry Pay Sid) (D : Data T Ext Pay Sid)
    (strat : AgentId Sid → Strategy Ext Role Pay Qry) :
    List (AgentId Sid) → RunState T Ext Role Pay Sid → RunState T Ext Role Pay Sid
  | [], rs => rs
  | a :: sched, rs => runAll cfg D strat sched (runStep cfg D strat rs a)

/-- `run cfg strat sched D`: the event list after the whole schedule (§7.4). -/
noncomputable def run (cfg : Config T U Ext Role Req Qry Pay Sid)
    (strat : AgentId Sid → Strategy Ext Role Pay Qry) (sched : List (AgentId Sid))
    (D : Data T Ext Pay Sid) : List (Event T Ext Pay) :=
  (runAll cfg D strat sched (initRun cfg D)).state.events


/-! ## Facts about `histUpdate` and responses -/

theorem histUpdate_of_ne_child {hist : AgentId Sid → List (Response Pay)} {a : AgentId Sid}
    {act : Action Ext Role Pay Qry} {r : Response Pay} (hr : ∀ n, r ≠ .child n) :
    histUpdate hist a act r = fun a' => if a' = a then hist a ++ [r] else hist a' := by
  funext a'
  unfold histUpdate
  cases r <;> cases act <;> first | rfl | exact absurd rfl (hr _)

theorem histUpdate_delegate {hist : AgentId Sid → List (Response Pay)} {a : AgentId Sid}
    {ρ : Role} {v : Pay} {n : Nat} :
    histUpdate (Ext := Ext) (Qry := Qry) hist a (.delegate ρ v) (.child n) = fun a' =>
      if a' = childId a n then [.payload v] else if a' = a then hist a ++ [.child n] else hist a' := rfl

/-! ## A step of an absent-or-tainted agent (run 1 only) -/

theorem Step.leftOK {D : Data T Ext Pay Sid} {B : T} {s s' : State T Ext Role Pay Sid}
    {a : AgentId Sid} {act : Action Ext Role Pay Qry} {r : Response Pay}
    (hT : Tainted B (s.agents a)) (hF : Fresh s) (h : Step cfg D s a act r s')
    (hist : AgentId Sid → List (Response Pay)) :
    readableDocs B s'.index = readableDocs B s.index ∧
    obs cfg B s'.events = obs cfg B s.events ∧
    ∀ b, LeftOK B a s s' hist (histUpdate hist a act r) b := by
  cases h with
  | denied _ =>
    refine ⟨rfl, rfl, fun b => ?_⟩
    rw [histUpdate_of_ne_child ne_child_denied]
    by_cases hb : b = a
    · subst hb; exact Or.inr (Or.inl ⟨hT, hT, Or.inl Iff.rfl⟩)
    · exact Or.inl ⟨rfl, by simp [hb]⟩
  | allowed hal =>
    cases hal with
    | @call σ p k v i hσ hp hauth hi hobs hint =>
      have hTσ : ¬ readable B σ.ctx := hT σ hσ
      refine ⟨rfl, ?_, fun b => ?_⟩
      · show obs cfg B (s.events ++ [_]) = _
        rw [obs_append, obs_singleton_of_not, List.append_nil]
        rintro ⟨i', hi', hB⟩
        simp only at hi'
        rw [hi] at hi'; cases hi'
        exact hTσ (hobs B hB)
      · rw [histUpdate_of_ne_child (callResp_ne_child D k i v)]
        by_cases hb : b = a
        · subst hb
          refine Or.inr (Or.inl ⟨hT, ?_, Or.inl ?_⟩)
          · show Tainted B (if b = b then _ else _)
            simp only [ite_true]
            exact Tainted.of_not_readable fun hr => hTσ (readable_mono (le_joinResult i σ.ctx) hr)
          · simp [hσ]
        · exact Or.inl ⟨by simp [hb], by simp [hb]⟩
    | @query σ p q hσ hp hauth =>
      have hTσ : ¬ readable B σ.ctx := hT σ hσ
      refine ⟨rfl, rfl, fun b => ?_⟩
      rw [histUpdate_of_ne_child (ne_child_payloads _)]
      by_cases hb : b = a
      · subst hb
        refine Or.inr (Or.inl ⟨hT, ?_, Or.inl ?_⟩)
        · show Tainted B (if b = b then _ else _)
          simp only [ite_true]
          exact Tainted.of_not_readable fun hr => hTσ (readable_mono (Label.le_join_left _ _) hr)
        · simp [hσ]
      · exact Or.inl ⟨by simp [hb], by simp [hb]⟩
    | @write σ p v hσ hp hauth hown =>
      have hTσ : ¬ readable B σ.ctx := hT σ hσ
      refine ⟨?_, rfl, fun b => ?_⟩
      · show readableDocs B (s.index ++ [_]) = _
        rw [readableDocs_append, readableDocs_singleton_of_not hTσ, List.append_nil]
      · rw [histUpdate_of_ne_child ne_child_ok]
        by_cases hb : b = a
        · subst hb; exact Or.inr (Or.inl ⟨hT, hT, Or.inl Iff.rfl⟩)
        · exact Or.inl ⟨rfl, by simp [hb]⟩
    | @delegate σ p ρ v hσ hp hauth =>
      have hTσ : ¬ readable B σ.ctx := hT σ hσ
      refine ⟨rfl, rfl, fun b => ?_⟩
      rw [histUpdate_delegate]
      by_cases hbc : b = childId a σ.nextChild
      · subst hbc
        have hnone : s.agents (childId a σ.nextChild) = none := hF.next a σ hσ _ (Nat.le_refl _)
        refine Or.inr (Or.inl ⟨hnone ▸ Tainted.none, ?_, Or.inr ⟨_, rfl⟩⟩)
        simp only [State.setAgent_agents, ite_true]
        exact Tainted.of_not_readable hTσ
      · by_cases hb : b = a
        · subst hb
          refine Or.inr (Or.inl ⟨hT, ?_, Or.inl ?_⟩)
          · simp only [State.setAgent_agents, hbc, ite_false, ite_true]
            exact Tainted.of_not_readable hTσ
          · simp [hbc, hσ]
        · exact Or.inl ⟨by simp [hb, hbc], by simp [hb, hbc]⟩
    | @report σ p v hσ hp hpar =>
      have hTσ : ¬ readable B σ.ctx := hT σ hσ
      refine ⟨rfl, rfl, fun b => ?_⟩
      rw [histUpdate_of_ne_child ne_child_ok]
      by_cases hb : b = a
      · subst hb
        refine Or.inr (Or.inl ⟨hT, ?_, Or.inl ?_⟩)
        · show Tainted B (if b = b then _ else _)
          simp only [ite_true]
          exact Tainted.of_not_readable hTσ
        · simp [hσ]
      · exact Or.inl ⟨by simp [hb], by simp [hb]⟩
    | @receive σ p c σc hσ hp hc =>
      have hTσ : ¬ readable B σ.ctx := hT σ hσ
      refine ⟨rfl, rfl, fun b => ?_⟩
      rw [histUpdate_of_ne_child (ne_child_payloads _)]
      by_cases hbc : b = childId a c
      · subst hbc
        refine Or.inr (Or.inr ⟨by simp [childId_ne], ⟨c, rfl⟩, σc, [], hc, ?_⟩)
        simp
      · by_cases hb : b = a
        · subst hb
          refine Or.inr (Or.inl ⟨hT, ?_, Or.inl ?_⟩)
          · simp only [State.setAgent_agents, hbc, ite_false, ite_true]
            exact Tainted.of_not_readable fun hr => hTσ (readable_mono (Label.le_join_left _ _) hr)
          · simp [hbc, hσ]
        · exact Or.inl ⟨by simp [hb, hbc], by simp [hb]⟩

/-- `runStep` of an absent-or-tainted agent in run 1 preserves `Sim`. -/
theorem Sim.runStep_left {D₁ : Data T Ext Pay Sid} {B : T} {rs₁ rs₂ : RunState T Ext Role Pay Sid}
    (strat : AgentId Sid → Strategy Ext Role Pay Qry) (hS : Sim cfg B rs₁ rs₂) {a : AgentId Sid}
    (hT : Tainted B (rs₁.state.agents a)) :
    Sim cfg B (runStep cfg D₁ strat rs₁ a) rs₂ := by
  unfold runStep
  cases hex : rs₁.state.agents a with
  | none => exact hS
  | some σ =>
    simp only
    have hstep := stepFn_spec (cfg := cfg) D₁ rs₁.state a (strat a (rs₁.hist a))
    obtain ⟨hI, hE, hA⟩ := Step.leftOK (B := B) (hex ▸ hT) hS.fresh₁ hstep rs₁.hist
    exact hS.left (hex ▸ hT) (hS.fresh₁.step hstep) hI hE hA

/-! ## Lockstep step of a clean agent (both runs) -/

omit [DecidableEq Sid] in
theorem callResp_eq_of_lowEq {D₁ D₂ : Data T Ext Pay Sid} {B : T} (hL : LowEq cfg B D₁ D₂)
    {t : T} {k : ToolId Ext} {i : ToolInfo T} (hi : cfg.toolInfo t k = some i)
    (hres : ∀ ℓr, i.result = some ℓr → readable B ℓr) (v : Pay) :
    callResp D₁ k i v = callResp D₂ k i v := by
  unfold callResp
  cases k with
  | deliver => rfl
  | ext k' =>
    cases h : i.result with
    | none => rfl
    | some ℓr =>
      simp only
      rw [hL.tool k' i ℓr (toolInfo_ext hi) h (hres ℓr h)]

omit [DecidableEq Sid] in
theorem readable_rank_label {B : T} (q : Qry) (L : List (Doc T Pay)) :
    ∀ l ∈ (cfg.rank q (readableDocs B L)).map Doc.label, readable B l := by
  intro l hl
  obtain ⟨d, hd, rfl⟩ := List.mem_map.mp hl
  exact mem_readableDocs (cfg.rank_mem _ _ _ hd)

/-- Allowedness of a clean agent's action depends only on its state up to outbox and on the
existence of its children (both equal in the two runs). -/
theorem Allowed.transport {D₁ D₂ : Data T Ext Pay Sid} {s₁ s₂ : State T Ext Role Pay Sid}
    {a : AgentId Sid} {σ₁ σ₂ : AgentState T Role Pay Sid}
    (e₁ : s₁.agents a = some σ₁) (e₂ : s₂.agents a = some σ₂) (he : EqUpToOutbox σ₁ σ₂)
    (hEx : ∀ c, s₁.agents (childId a c) = none ↔ s₂.agents (childId a c) = none)
    {act : Action Ext Role Pay Qry} {r : Response Pay} {s₂' : State T Ext Role Pay Sid}
    (h : Allowed cfg D₂ s₂ a act r s₂') : ∃ r' s₁', Allowed cfg D₁ s₁ a act r' s₁' := by
  obtain ⟨hse, hce, hctx, hnc, hpar⟩ := he
  cases h with
  | @call σ p k v i hσ hp hauth hi hobs hint =>
    rw [e₂] at hσ; cases hσ
    exact ⟨_, _, Allowed.call e₁ (by rw [hse]; exact hp) (by rw [hce]; exact hauth) hi
      (by rw [hctx]; exact hobs) (by rw [hctx]; exact hint)⟩
  | @query σ p q hσ hp hauth =>
    rw [e₂] at hσ; cases hσ
    exact ⟨_, _, Allowed.query e₁ (by rw [hse]; exact hp) (by rw [hce]; exact hauth)⟩
  | @write σ p v hσ hp hauth hown =>
    rw [e₂] at hσ; cases hσ
    exact ⟨_, _, Allowed.write e₁ (by rw [hse]; exact hp) (by rw [hce]; exact hauth)
      (by rw [hctx]; exact hown)⟩
  | @delegate σ p ρ v hσ hp hauth =>
    rw [e₂] at hσ; cases hσ
    exact ⟨_, _, Allowed.delegate e₁ (by rw [hse]; exact hp) (by rw [hce]; exact hauth)⟩
  | @report σ p v hσ hp hpar' =>
    rw [e₂] at hσ; cases hσ
    exact ⟨_, _, Allowed.report e₁ (by rw [hse]; exact hp) (by rw [hpar]; exact hpar')⟩
  | @receive σ p c σc hσ hp hc =>
    rw [e₂] at hσ; cases hσ
    cases hc₁ : s₁.agents (childId a c) with
    | none => exact absurd ((hEx c).mp hc₁) (by simp [hc])
    | some σc₁ => exact ⟨_, _, Allowed.receive e₁ (by rw [hse]; exact hp) hc₁⟩

omit [DecidableEq Sid] in
theorem LockOK.frame {B : T} {s₁ s₂ s₁' s₂' : State T Ext Role Pay Sid}
    {hist₁ hist₂ hist₁' hist₂' : AgentId Sid → List (Response Pay)} {b : AgentId Sid}
    (h₁ : s₁'.agents b = s₁.agents b) (h₂ : s₂'.agents b = s₂.agents b)
    (h₃ : hist₁' b = hist₁ b) (h₄ : hist₂' b = hist₂ b) :
    LockOK cfg B s₁ s₂ s₁' s₂' hist₁ hist₂ hist₁' hist₂' b := Or.inl ⟨h₁, h₂, h₃, h₄⟩

omit [DecidableEq Sid] in
theorem LockOK.clean {B : T} {s₁ s₂ s₁' s₂' : State T Ext Role Pay Sid}
    {hist₁ hist₂ hist₁' hist₂' : AgentId Sid → List (Response Pay)} {b : AgentId Sid}
    (hc : Clean cfg B (s₁'.agents b) (s₂'.agents b) (hist₁' b) (hist₂' b))
    (hb : Clean cfg B (s₁.agents b) (s₂.agents b) (hist₁ b) (hist₂ b) ∨
      (s₁.agents b = none ∧ s₂.agents b = none))
    (himp : (s₁.agents b).map AgentState.outbox = (s₂.agents b).map AgentState.outbox →
      (s₁'.agents b).map AgentState.outbox = (s₂'.agents b).map AgentState.outbox) :
    LockOK cfg B s₁ s₂ s₁' s₂' hist₁ hist₂ hist₁' hist₂' b := Or.inr (Or.inl ⟨hc, hb, himp⟩)

omit [DecidableEq Sid] in
theorem LockOK.tainted {B : T} {s₁ s₂ s₁' s₂' : State T Ext Role Pay Sid}
    {hist₁ hist₂ hist₁' hist₂' : AgentId Sid → List (Response Pay)} {b : AgentId Sid}
    (h₁ : Tainted B (s₁'.agents b)) (h₂ : Tainted B (s₂'.agents b))
    (hex : s₁'.agents b = none ↔ s₂'.agents b = none) :
    LockOK cfg B s₁ s₂ s₁' s₂' hist₁ hist₂ hist₁' hist₂' b := Or.inr (Or.inr ⟨h₁, h₂, hex⟩)

theorem Step.lockOK {D₁ D₂ : Data T Ext Pay Sid} {B : T} (hL : LowEq cfg B D₁ D₂)
    {s₁ s₂ : State T Ext Role Pay Sid} {hist₁ hist₂ : AgentId Sid → List (Response Pay)}
    (hS : Sim cfg B ⟨s₁, hist₁⟩ ⟨s₂, hist₂⟩) {a : AgentId Sid}
    (hC : Clean cfg B (s₁.agents a) (s₂.agents a) (hist₁ a) (hist₂ a))
    {act : Action Ext Role Pay Qry} {r₁ r₂ : Response Pay} {s₁' s₂' : State T Ext Role Pay Sid}
    (h₁ : Step cfg D₁ s₁ a act r₁ s₁') (h₂ : Step cfg D₂ s₂ a act r₂ s₂') :
    readableDocs B s₁'.index = readableDocs B s₂'.index ∧
    obs cfg B s₁'.events = obs cfg B s₂'.events ∧
    ∀ b, LockOK cfg B s₁ s₂ s₁' s₂' hist₁ hist₂ (histUpdate hist₁ a act r₁)
      (histUpdate hist₂ a act r₂) b := by
  have hI : readableDocs B s₁.index = readableDocs B s₂.index := hS.index
  have hE : obs cfg B s₁.events = obs cfg B s₂.events := hS.events
  have hEx : ∀ c, s₁.agents (childId a c) = none ↔ s₂.agents (childId a c) = none :=
    hS.childEx a hC
  obtain ⟨σ₁, σ₂, e₁, e₂, he, hr, ⟨p, hp, hpB⟩, hh⟩ := hC
  have hC : Clean cfg B (s₁.agents a) (s₂.agents a) (hist₁ a) (hist₂ a) :=
    ⟨σ₁, σ₂, e₁, e₂, he, hr, ⟨p, hp, hpB⟩, hh⟩
  obtain ⟨hse, hce, hctx, hnc, hpar⟩ := he
  cases h₁ with
  | denied hd₁ =>
    cases h₂ with
    | allowed hal₂ =>
      obtain ⟨r', s'', h'⟩ := Allowed.transport (D₁ := D₁) e₁ e₂ ⟨hse, hce, hctx, hnc, hpar⟩ hEx hal₂
      exact absurd h' (hd₁ _ _)
    | denied _ =>
      refine ⟨hI, hE, fun b => ?_⟩
      rw [histUpdate_of_ne_child ne_child_denied, histUpdate_of_ne_child ne_child_denied]
      by_cases hb : b = a
      · subst hb
        refine LockOK.clean ⟨σ₁, σ₂, e₁, e₂, ⟨hse, hce, hctx, hnc, hpar⟩, hr, ⟨p, hp, hpB⟩, ?_⟩
          (Or.inl hC) id
        simp [hh]
      · exact LockOK.frame rfl rfl (by simp [hb]) (by simp [hb])
  | allowed hal₁ =>
    cases hal₁ with
    | @call σ p' k v i hσ hp' hauth hi hobs hint =>
      rw [e₁] at hσ; cases hσ
      rw [hp] at hp'; cases hp'
      have hal₂ : Allowed cfg D₂ s₂ a (.call k v) (callResp D₂ k i v)
          { s₂.setAgent a { σ₂ with ctx := i.joinResult σ₂.ctx } with
              events := s₂.events ++ [⟨p.tenant, k, v, σ₂.ctx⟩] } :=
        Allowed.call e₂ (by rw [← hse]; exact hp) (by rw [← hce]; exact hauth) hi
          (by rw [← hctx]; exact hobs) (by rw [← hctx]; exact hint)
      obtain ⟨rfl, rfl⟩ := Step.det h₂ (.allowed hal₂)
      refine ⟨hI, ?_, fun b => ?_⟩
      · show obs cfg B (s₁.events ++ [_]) = obs cfg B (s₂.events ++ [_])
        rw [obs_append, obs_append, hE, hctx]
      · rw [histUpdate_of_ne_child (callResp_ne_child D₁ k i v),
          histUpdate_of_ne_child (callResp_ne_child D₂ k i v)]
        by_cases hb : b = a
        · subst hb
          by_cases hres : ∀ ℓr, i.result = some ℓr → readable B ℓr
          · -- the result is readable by B (or absent): the agent stays clean
            have hresp := callResp_eq_of_lowEq hL hi hres v
            refine LockOK.clean ?_ (Or.inl hC) ?_
            · simp only [State.setAgent_agents, ite_true]
              exact ⟨_, _, rfl, rfl, ⟨hse, hce, by simp [hctx], hnc, hpar⟩,
                readable_joinResult hr hres, ⟨p, hp, hpB⟩, by simp [hh, hresp]⟩
            · simp only [State.setAgent_agents, ite_true]
              intro h; simpa [e₁, e₂] using h
          · -- the result is not readable by B: the agent becomes tainted in both runs
            have hjoin : ∀ ℓ, ¬ readable B (i.joinResult ℓ) := by
              intro ℓ h
              apply hres
              intro ℓr hℓr
              unfold ToolInfo.joinResult at h
              rw [hℓr] at h
              exact readable_mono (Label.le_join_right _ _) h
            refine LockOK.tainted ?_ ?_ ?_ <;> simp only [State.setAgent_agents, ite_true]
            · exact Tainted.of_not_readable (hjoin _)
            · exact Tainted.of_not_readable (hjoin _)
            · simp
        · exact LockOK.frame (by simp [hb]) (by simp [hb]) (by simp [hb]) (by simp [hb])
    | @query σ p' q hσ hp' hauth =>
      rw [e₁] at hσ; cases hσ
      rw [hp] at hp'; cases hp'
      have hal₂ := Allowed.query (cfg := cfg) (D := D₂) (q := q) e₂ (by rw [← hse]; exact hp)
        (by rw [← hce]; exact hauth)
      obtain ⟨rfl, rfl⟩ := Step.det h₂ (.allowed hal₂)
      subst hpB
      refine ⟨hI, hE, fun b => ?_⟩
      rw [histUpdate_of_ne_child (ne_child_payloads _), histUpdate_of_ne_child (ne_child_payloads _)]
      by_cases hb : b = a
      · subst hb
        refine LockOK.clean ?_ (Or.inl hC) ?_
        · simp only [State.setAgent_agents, ite_true]
          exact ⟨_, _, rfl, rfl, ⟨hse, hce, by simp [hctx, hI], hnc, hpar⟩,
            readable_join hr (readable_joinAll _ (readable_rank_label q s₁.index)), ⟨p, hp, rfl⟩,
            by simp [hh, hI]⟩
        · simp only [State.setAgent_agents, ite_true]
          intro h; simpa [e₁, e₂] using h
      · exact LockOK.frame (by simp [hb]) (by simp [hb]) (by simp [hb]) (by simp [hb])
    | @write σ p' v hσ hp' hauth hown =>
      rw [e₁] at hσ; cases hσ
      rw [hp] at hp'; cases hp'
      have hal₂ := Allowed.write (cfg := cfg) (D := D₂) (v := v) e₂ (by rw [← hse]; exact hp)
        (by rw [← hce]; exact hauth) (by rw [← hctx]; exact hown)
      obtain ⟨rfl, rfl⟩ := Step.det h₂ (.allowed hal₂)
      refine ⟨?_, hE, fun b => ?_⟩
      · show readableDocs B (s₁.index ++ [_]) = readableDocs B (s₂.index ++ [_])
        rw [readableDocs_append, readableDocs_append, hI,
          readableDocs_singleton_of_readable hr, readableDocs_singleton_of_readable (hctx ▸ hr), hctx]
      · rw [histUpdate_of_ne_child ne_child_ok, histUpdate_of_ne_child ne_child_ok]
        by_cases hb : b = a
        · subst hb
          refine LockOK.clean ⟨σ₁, σ₂, e₁, e₂, ⟨hse, hce, hctx, hnc, hpar⟩, hr, ⟨p, hp, hpB⟩, ?_⟩
            (Or.inl hC) id
          simp [hh]
        · exact LockOK.frame rfl rfl (by simp [hb]) (by simp [hb])
    | @delegate σ p' ρ v hσ hp' hauth =>
      rw [e₁] at hσ; cases hσ
      rw [hp] at hp'; cases hp'
      have hal₂ := Allowed.delegate (cfg := cfg) (D := D₂) (ρ := ρ) (v := v) e₂
        (by rw [← hse]; exact hp) (by rw [← hce]; exact hauth)
      obtain ⟨rfl, rfl⟩ := Step.det h₂ (.allowed hal₂)
      rw [← hnc]
      refine ⟨hI, hE, fun b => ?_⟩
      rw [histUpdate_delegate, histUpdate_delegate]
      by_cases hbc : b = childId a σ₁.nextChild
      · subst hbc
        refine LockOK.clean ?_ (Or.inr ⟨hS.fresh₁.next a σ₁ e₁ _ (Nat.le_refl _),
            hS.fresh₂.next a σ₂ e₂ _ (Nat.le_of_eq hnc.symm)⟩) ?_
        · simp only [State.setAgent_agents, ite_true]
          exact ⟨_, _, rfl, rfl, ⟨hse, rfl, hctx, rfl, rfl⟩, hr, ⟨p, hp, hpB⟩, rfl⟩
        · simp only [State.setAgent_agents, ite_true]
          intro _; rfl
      · by_cases hb : b = a
        · subst hb
          refine LockOK.clean ?_ (Or.inl hC) ?_
          · simp only [State.setAgent_agents, ne_childId, ite_false, ite_true]
            exact ⟨_, _, rfl, rfl, ⟨hse, hce, hctx, rfl, hpar⟩, hr, ⟨p, hp, hpB⟩, by simp [hh]⟩
          · simp only [State.setAgent_agents, ne_childId, ite_false, ite_true]
            intro h; simpa [e₁, e₂] using h
        · exact LockOK.frame (by simp [hb, hbc]) (by simp [hb, hbc]) (by simp [hb, hbc])
            (by simp [hb, hbc])
    | @report σ p' v hσ hp' hpar' =>
      rw [e₁] at hσ; cases hσ
      rw [hp] at hp'; cases hp'
      have hal₂ := Allowed.report (cfg := cfg) (D := D₂) (v := v) e₂ (by rw [← hse]; exact hp)
        (by rw [← hpar]; exact hpar')
      obtain ⟨rfl, rfl⟩ := Step.det h₂ (.allowed hal₂)
      refine ⟨hI, hE, fun b => ?_⟩
      rw [histUpdate_of_ne_child ne_child_ok, histUpdate_of_ne_child ne_child_ok]
      by_cases hb : b = a
      · subst hb
        refine LockOK.clean ?_ (Or.inl hC) ?_
        · simp only [State.setAgent_agents, ite_true]
          exact ⟨_, _, rfl, rfl, ⟨hse, hce, hctx, hnc, hpar⟩, hr, ⟨p, hp, hpB⟩, by simp [hh]⟩
        · simp only [State.setAgent_agents, ite_true, e₁, e₂, Option.map_some, Option.some.injEq]
          intro h; rw [h]
      · exact LockOK.frame (by simp [hb]) (by simp [hb]) (by simp [hb]) (by simp [hb])
    | @receive σ p' c σc hσ hp' hc =>
      rw [e₁] at hσ; cases hσ
      rw [hp] at hp'; cases hp'
      obtain ⟨σc₂, hc₂⟩ : ∃ σc₂, s₂.agents (childId a c) = some σc₂ := by
        cases h : s₂.agents (childId a c) with
        | none => exact absurd ((hEx c).mpr h) (by simp [hc])
        | some τ => exact ⟨τ, rfl⟩
      have hal₂ := Allowed.receive (cfg := cfg) (D := D₂) e₂ (by rw [← hse]; exact hp) hc₂
      obtain ⟨rfl, rfl⟩ := Step.det h₂ (.allowed hal₂)
      refine ⟨hI, hE, fun b => ?_⟩
      rw [histUpdate_of_ne_child (ne_child_payloads _), histUpdate_of_ne_child (ne_child_payloads _)]
      rcases hS.agents (childId a c) with ⟨τ₁, τ₂, f₁, f₂, hec, hrc, hpc, hhc⟩ | ⟨t₁, t₂⟩
      · -- the child is clean: identical outboxes (clause (iv)), the parent stays clean
        have hob : σc.outbox = σc₂.outbox := by
          have := hS.childOutbox a hC c ⟨τ₁, τ₂, f₁, f₂, hec, hrc, hpc, hhc⟩
          simp only [hc, hc₂, Option.map_some, Option.some.injEq] at this
          exact this
        simp only [hc, Option.some.injEq] at f₁; subst f₁
        simp only [hc₂, Option.some.injEq] at f₂; subst f₂
        by_cases hbc : b = childId a c
        · subst hbc
          refine LockOK.clean ?_ (Or.inl ⟨_, _, hc, hc₂, hec, hrc, hpc, hhc⟩) ?_
          · simp only [State.setAgent_agents, ite_true, childId_ne, ite_false]
            exact ⟨_, _, rfl, rfl, hec, hrc, hpc, hhc⟩
          · simp only [State.setAgent_agents, ite_true]
            intro _; rfl
        · by_cases hb : b = a
          · subst hb
            refine LockOK.clean ?_ (Or.inl hC) ?_
            · simp only [State.setAgent_agents, ne_childId, ite_false, ite_true]
              exact ⟨_, _, rfl, rfl, ⟨hse, hce, by simp [hctx, hec.2.2.1], hnc, hpar⟩,
                readable_join hr hrc, ⟨p, hp, hpB⟩, by simp [hh, hob]⟩
            · simp only [State.setAgent_agents, ne_childId, ite_false, ite_true]
              intro h; simpa [e₁, e₂] using h
          · exact LockOK.frame (by simp [hb, hbc]) (by simp [hb, hbc]) (by simp [hb]) (by simp [hb])
      · -- the child is tainted in both runs: the parent becomes tainted in both runs
        have hnr₁ : ¬ readable B σc.ctx := t₁ σc hc
        have hnr₂ : ¬ readable B σc₂.ctx := t₂ σc₂ hc₂
        by_cases hbc : b = childId a c
        · subst hbc
          refine LockOK.tainted ?_ ?_ ?_ <;> simp only [State.setAgent_agents, ite_true]
          · exact Tainted.of_not_readable hnr₁
          · exact Tainted.of_not_readable hnr₂
          · simp
        · by_cases hb : b = a
          · subst hb
            refine LockOK.tainted ?_ ?_ ?_ <;>
              simp only [State.setAgent_agents, ne_childId, ite_false, ite_true]
            · exact Tainted.of_not_readable fun h => hnr₁ (readable_mono (Label.le_join_right _ _) h)
            · exact Tainted.of_not_readable fun h => hnr₂ (readable_mono (Label.le_join_right _ _) h)
            · simp
          · exact LockOK.frame (by simp [hb, hbc]) (by simp [hb, hbc]) (by simp [hb]) (by simp [hb])

/-! ## Lockstep over the schedule and the initial state -/

/-- One scheduled move of the same agent in both runs preserves `Sim`. -/
theorem Sim.step_both {D₁ D₂ : Data T Ext Pay Sid} {B : T} (hL : LowEq cfg B D₁ D₂)
    (strat : AgentId Sid → Strategy Ext Role Pay Qry) {rs₁ rs₂ : RunState T Ext Role Pay Sid}
    (hS : Sim cfg B rs₁ rs₂) (a : AgentId Sid) :
    Sim cfg B (runStep cfg D₁ strat rs₁ a) (runStep cfg D₂ strat rs₂ a) := by
  rcases hS.agents a with hc | ⟨ht₁, ht₂⟩
  · obtain ⟨s₁, hist₁⟩ := rs₁
    obtain ⟨s₂, hist₂⟩ := rs₂
    obtain ⟨σ₁, σ₂, e₁, e₂, he, hr, hp, hh⟩ := hc
    have hc : Clean cfg B (s₁.agents a) (s₂.agents a) (hist₁ a) (hist₂ a) :=
      ⟨σ₁, σ₂, e₁, e₂, he, hr, hp, hh⟩
    simp only at e₁ e₂ hh
    unfold runStep
    simp only [e₁, e₂, hh]
    have h₁ := stepFn_spec (cfg := cfg) D₁ s₁ a (strat a (hist₂ a))
    have h₂ := stepFn_spec (cfg := cfg) D₂ s₂ a (strat a (hist₂ a))
    obtain ⟨hI, hE, hA⟩ := Step.lockOK hL hS (hh ▸ hc) h₁ h₂
    exact hS.lock (hS.fresh₁.step h₁) (hS.fresh₂.step h₂) hI hE hA
  · exact ((hS.runStep_left strat ht₁).symm.runStep_left strat ht₂).symm

theorem Sim.run_all {D₁ D₂ : Data T Ext Pay Sid} {B : T} (hL : LowEq cfg B D₁ D₂)
    (strat : AgentId Sid → Strategy Ext Role Pay Qry) {rs₁ rs₂ : RunState T Ext Role Pay Sid}
    (hS : Sim cfg B rs₁ rs₂) (sched : List (AgentId Sid)) :
    Sim cfg B (runAll cfg D₁ strat sched rs₁) (runAll cfg D₂ strat sched rs₂) := by
  induction sched generalizing rs₁ rs₂ with
  | nil => exact hS
  | cons a sched ih => exact ih (hS.step_both hL strat a)

omit [DecidableEq Sid] in
theorem init_agents_childId (D : Data T Ext Pay Sid) (a : AgentId Sid) (c : Nat) :
    (init cfg D).agents (childId a c) = none := by
  obtain ⟨sid, l⟩ := a
  cases l <;> rfl

theorem readable_rootCtx (t : T) : readable t (rootCtx t) := fun _ h => h

theorem not_readable_rootCtx {t B : T} (h : t ≠ B) : ¬ readable B (rootCtx t) :=
  fun hr => h (hr t rfl)

omit [DecidableEq Sid] in
/-- The initial run states of two low-equivalent data sets are related. -/
theorem Sim.of_lowEq_init {D₁ D₂ : Data T Ext Pay Sid} {B : T} (hL : LowEq cfg B D₁ D₂) :
    Sim cfg B (initRun cfg D₁) (initRun cfg D₂) where
  fresh₁ := Fresh.init
  fresh₂ := Fresh.init
  index := hL.index₀
  events := rfl
  agents := by
    intro ⟨sid, l⟩
    cases l with
    | cons _ _ => exact Or.inr ⟨Tainted.none, Tainted.none⟩
    | nil =>
      show Clean cfg B ((cfg.sessions sid).map _) ((cfg.sessions sid).map _) _ _ ∨
        (Tainted B ((cfg.sessions sid).map _) ∧ Tainted B ((cfg.sessions sid).map _))
      cases hs : cfg.sessions sid with
      | none => exact Or.inr ⟨Tainted.none, Tainted.none⟩
      | some p =>
        by_cases hpB : p.tenant = B
        · left
          refine ⟨_, _, rfl, rfl, EqUpToOutbox.refl _, hpB ▸ readable_rootCtx _, ⟨p, hs, hpB⟩, ?_⟩
          show [Response.payload (D₁.prompt sid)] = [Response.payload (D₂.prompt sid)]
          rw [hL.prompt sid p hs hpB]
        · right
          exact ⟨Tainted.of_not_readable (not_readable_rootCtx hpB),
            Tainted.of_not_readable (not_readable_rootCtx hpB)⟩
  childEx := by
    intro a _ c
    show (init cfg D₁).agents (childId a c) = none ↔ (init cfg D₂).agents (childId a c) = none
    rw [init_agents_childId, init_agents_childId]
  childOutbox := by
    intro a _ c hcc
    exact absurd (init_agents_childId (cfg := cfg) D₁ a c) hcc.isSome.1

/-! ## Theorem (c) -/

/-- **Theorem (c), noninterference** (`docs/spec.md` §7.4): for every configuration, every family of
strategies, every schedule and every observer tenant `B`, low-equivalent data sets produce the same
`B`-observable events. -/
theorem noninterference (strat : AgentId Sid → Strategy Ext Role Pay Qry) (sched : List (AgentId Sid))
    (B : T) {D₁ D₂ : Data T Ext Pay Sid} (hL : LowEq cfg B D₁ D₂) :
    obs cfg B (run cfg strat sched D₁) = obs cfg B (run cfg strat sched D₂) :=
  (Sim.run_all hL strat (Sim.of_lowEq_init hL) sched).events

end

end TenantFlow.Model
