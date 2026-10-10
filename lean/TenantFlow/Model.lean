/-!
# Abstract model

`docs/spec.md` v0.2, §3 (labels), §4 (system model), §5 (monitor rules), §7.1 (ghost provenance).

Design (task F1a):
* Sets are predicates `T → Prop`; nothing here needs to be computable.
* `Allowed` has one constructor per row of §5; `Step` is `Allowed` plus the single `denied`
  rule (state unchanged, response `denied`).  Hence `Step.det` and `Step.total` (in `Proofs`).
* The ghost layer is `Step` plus a ghost-update *function* (`ghostUpdate`), so `ghost_proj`
  and `ghost_lift` are immediate.  Ghost `deps` are attached to agent ids, to docs and to
  events by value (a function on the object): two equal docs/events share their deps, which
  over-approximates "may depend on" and is sound for (a) and (b2).
* Payloads are a type parameter `Pay` that only `rank`, `mkRequest` and `tool` consume (D8).
-/

namespace TenantFlow.Model

/-! ## §3 Labels -/

inductive Integrity
  | trusted
  | untrusted
  deriving DecidableEq, Repr, Inhabited

namespace Integrity

/-- `trusted ≤ untrusted` ("untrusted wins"). -/
def leB : Integrity → Integrity → Bool
  | untrusted, trusted => false
  | _, _ => true

instance : LE Integrity := ⟨fun a b => leB a b = true⟩
instance : DecidableRel (α := Integrity) (· ≤ ·) :=
  fun a b => inferInstanceAs (Decidable (leB a b = true))

def max (a b : Integrity) : Integrity := if leB a b then b else a

theorem le_refl (a : Integrity) : a ≤ a := by cases a <;> decide
theorem le_trans {a b c : Integrity} : a ≤ b → b ≤ c → a ≤ c := by
  cases a <;> cases b <;> cases c <;> decide
theorem le_max_left (a b : Integrity) : a ≤ max a b := by cases a <;> cases b <;> decide
theorem le_max_right (a b : Integrity) : b ≤ max a b := by cases a <;> cases b <;> decide
theorem max_le {a b c : Integrity} : a ≤ c → b ≤ c → max a b ≤ c := by
  cases a <;> cases b <;> cases c <;> decide
theorem trusted_le (a : Integrity) : trusted ≤ a := by cases a <;> decide
theorem le_trusted {a : Integrity} : a ≤ trusted → a = trusted := by cases a <;> decide

end Integrity

structure Label (T : Type) where
  owners : T → Prop
  integ : Integrity

namespace Label
variable {T : Type}

/-- `ℓ₁ ⊑ ℓ₂ :⇔ owners ⊆ owners ∧ integ ≤ integ`. -/
protected def le (l₁ l₂ : Label T) : Prop :=
  (∀ t, l₁.owners t → l₂.owners t) ∧ l₁.integ ≤ l₂.integ

instance : LE (Label T) := ⟨Label.le⟩

def join (l₁ l₂ : Label T) : Label T :=
  ⟨fun t => l₁.owners t ∨ l₂.owners t, Integrity.max l₁.integ l₂.integ⟩

def bot : Label T := ⟨fun _ => False, .trusted⟩

def joinAll : List (Label T) → Label T
  | [] => bot
  | l :: ls => join l (joinAll ls)

theorem le_refl (l : Label T) : l ≤ l := ⟨fun _ h => h, Integrity.le_refl _⟩
theorem le_trans {l₁ l₂ l₃ : Label T} (h₁ : l₁ ≤ l₂) (h₂ : l₂ ≤ l₃) : l₁ ≤ l₃ :=
  ⟨fun t h => h₂.1 t (h₁.1 t h), Integrity.le_trans h₁.2 h₂.2⟩
theorem le_join_left (l₁ l₂ : Label T) : l₁ ≤ join l₁ l₂ :=
  ⟨fun _ h => Or.inl h, Integrity.le_max_left _ _⟩
theorem le_join_right (l₁ l₂ : Label T) : l₂ ≤ join l₁ l₂ :=
  ⟨fun _ h => Or.inr h, Integrity.le_max_right _ _⟩
theorem join_le {l₁ l₂ l : Label T} (h₁ : l₁ ≤ l) (h₂ : l₂ ≤ l) : join l₁ l₂ ≤ l :=
  ⟨fun t h => h.elim (h₁.1 t) (h₂.1 t), Integrity.max_le h₁.2 h₂.2⟩
theorem bot_le (l : Label T) : bot ≤ l := ⟨fun _ h => h.elim, Integrity.trusted_le _⟩
theorem le_joinAll_of_mem {l : Label T} : ∀ {ls : List (Label T)}, l ∈ ls → l ≤ joinAll ls
  | _ :: _, List.Mem.head _ => le_join_left _ _
  | _ :: _, List.Mem.tail _ h => le_trans (le_joinAll_of_mem h) (le_join_right _ _)

end Label

/-- `readable u ℓ :⇔ ℓ.owners ⊆ {u}`. -/
def readable {T : Type} (u : T) (l : Label T) : Prop := ∀ t, l.owners t → t = u

theorem readable_mono {T : Type} {u : T} {l₁ l₂ : Label T} (h : l₁ ≤ l₂)
    (hr : readable u l₂) : readable u l₁ :=
  fun t ht => hr t (h.1 t ht)

/-! ## §4 System model -/

structure Principal (T U : Type) where
  tenant : T
  user : U
  deriving DecidableEq, Repr

inductive ToolId (Ext : Type)
  | deliver
  | ext (k : Ext)
  deriving DecidableEq, Repr

/-- Who sees the *arguments* of a call, whether they must be trusted, label of the *result*
(`none`: the result is discarded, the agent only sees `ok`). -/
structure ToolInfo (T : Type) where
  observers : T → Prop
  needsTrusted : Bool
  result : Option (Label T)

inductive Action (Ext Role Pay Qry : Type)
  | call (k : ToolId Ext) (args : Pay)
  | query (q : Qry)
  | write (v : Pay)
  | delegate (ρ : Role) (task : Pay)
  | report (v : Pay)
  | receive (c : Nat)

inductive Response (Pay : Type)
  | payload (v : Pay)
  | payloads (vs : List Pay)
  | child (n : Nat)
  | ok
  | denied

structure Doc (T Pay : Type) where
  label : Label T
  payload : Pay

/-- Root agent of session `s` is `(s, [])`; the `n`-th child of `a` is `(a.1, a.2 ++ [n])`. -/
abbrev AgentId (Sid : Type) := Sid × List Nat

def childId {Sid : Type} (a : AgentId Sid) (n : Nat) : AgentId Sid := (a.1, a.2 ++ [n])

structure AgentState (T Role Pay Sid : Type) where
  session : Sid
  cedarP : Role
  ctx : Label T
  nextChild : Nat
  outbox : List Pay
  parent : Option (AgentId Sid)

/-- One event per successful `call`; `tenant` is the acting session's tenant. -/
structure Event (T Ext Pay : Type) where
  tenant : T
  tool : ToolId Ext
  args : Pay
  label : Label T

/-- §4.1 static configuration.  `authorize` is opaque; `rank` is opaque up to `rank_mem`.
`principalRole` embeds the authenticated principal of a root agent into the Cedar principal type. -/
structure Config (T U Ext Role Req Qry Pay Sid : Type) where
  sessions : Sid → Option (Principal T U)
  extReg : Ext → Option (ToolInfo T)
  principalRole : Principal T U → Role
  mkRequest : Role → Action Ext Role Pay Qry → Req
  authorize : Req → Bool
  rank : Qry → List (Doc T Pay) → List (Doc T Pay)
  rank_mem : ∀ q L d, d ∈ rank q L → d ∈ L

/-- §4.2 data (what may differ between the runs compared in (c)). -/
structure Data (T Ext Pay Sid : Type) where
  tool : Ext → Pay → Pay
  index₀ : List (Doc T Pay)
  prompt : Sid → Pay

/-- §4.3 runtime state. -/
structure State (T Ext Role Pay Sid : Type) where
  index : List (Doc T Pay)
  agents : AgentId Sid → Option (AgentState T Role Pay Sid)
  events : List (Event T Ext Pay)

section
variable {T U Ext Role Req Qry Pay Sid : Type} [DecidableEq Sid]

def rootCtx (t : T) : Label T := ⟨fun u => u = t, .trusted⟩

def Config.toolInfo (cfg : Config T U Ext Role Req Qry Pay Sid) (t : T) :
    ToolId Ext → Option (ToolInfo T)
  | .deliver => some ⟨fun u => u = t, false, none⟩
  | .ext k => cfg.extReg k

/-- `observers e` of §4.3: `{e.tenant}` for `deliver`, the registry observers for `ext k`. -/
def Config.observersOf (cfg : Config T U Ext Role Req Qry Pay Sid) (e : Event T Ext Pay) (u : T) :
    Prop :=
  ∃ i, cfg.toolInfo e.tenant e.tool = some i ∧ i.observers u

def Config.needsTrustedOf (cfg : Config T U Ext Role Req Qry Pay Sid) (e : Event T Ext Pay) :
    Prop :=
  ∃ i, cfg.toolInfo e.tenant e.tool = some i ∧ i.needsTrusted = true

/-- `ctx := ℓ ⊔ ℓr` if the tool has a result label, else `ℓ`. -/
def ToolInfo.joinResult (i : ToolInfo T) (ℓ : Label T) : Label T :=
  match i.result with
  | some ℓr => ℓ.join ℓr
  | none => ℓ

/-- Response of an allowed `call`: the tool result if the tool has one, else `ok`. -/
def callResp (D : Data T Ext Pay Sid) (k : ToolId Ext) (i : ToolInfo T) (v : Pay) : Response Pay :=
  match k, i.result with
  | .ext k', some _ => .payload (D.tool k' v)
  | _, _ => .ok

open Classical in
/-- Server-side filter: the docs tenant `t` may read, in index order (D2, D3). -/
noncomputable def readableDocs (t : T) (L : List (Doc T Pay)) : List (Doc T Pay) :=
  L.filter fun d => decide (readable t d.label)

def State.setAgent (s : State T Ext Role Pay Sid) (a : AgentId Sid)
    (σ : AgentState T Role Pay Sid) : State T Ext Role Pay Sid :=
  { s with agents := fun a' => if a' = a then some σ else s.agents a' }

@[simp] theorem State.setAgent_index (s : State T Ext Role Pay Sid) (a σ) :
    (s.setAgent a σ).index = s.index := rfl
@[simp] theorem State.setAgent_events (s : State T Ext Role Pay Sid) (a σ) :
    (s.setAgent a σ).events = s.events := rfl
@[simp] theorem State.setAgent_agents (s : State T Ext Role Pay Sid) (a σ a') :
    (s.setAgent a σ).agents a' = if a' = a then some σ else s.agents a' := rfl

/-! ## §5 Monitor rules -/

/-- The allowed rows of §5.  Hypotheses: acting agent `σ` with authenticated principal `p`
(`t = p.tenant`), the Cedar decision where §5 asks for it, and `flowOK`. -/
inductive Allowed (cfg : Config T U Ext Role Req Qry Pay Sid) (D : Data T Ext Pay Sid) :
    State T Ext Role Pay Sid → AgentId Sid → Action Ext Role Pay Qry → Response Pay →
    State T Ext Role Pay Sid → Prop
  | call {s a σ p k v i}
      (hσ : s.agents a = some σ) (hp : cfg.sessions σ.session = some p)
      (hauth : cfg.authorize (cfg.mkRequest σ.cedarP (.call k v)) = true)
      (hi : cfg.toolInfo p.tenant k = some i)
      (hobs : ∀ u, i.observers u → readable u σ.ctx)
      (hint : i.needsTrusted = true → σ.ctx.integ = .trusted) :
      Allowed cfg D s a (.call k v) (callResp D k i v)
        { s.setAgent a { σ with ctx := i.joinResult σ.ctx } with
            events := s.events ++ [⟨p.tenant, k, v, σ.ctx⟩] }
  | query {s a σ p q}
      (hσ : s.agents a = some σ) (hp : cfg.sessions σ.session = some p)
      (hauth : cfg.authorize (cfg.mkRequest σ.cedarP (.query q)) = true) :
      Allowed cfg D s a (.query q)
        (.payloads ((cfg.rank q (readableDocs p.tenant s.index)).map (·.payload)))
        (s.setAgent a { σ with
          ctx := σ.ctx.join (Label.joinAll ((cfg.rank q (readableDocs p.tenant s.index)).map (·.label))) })
  | write {s a σ p v}
      (hσ : s.agents a = some σ) (hp : cfg.sessions σ.session = some p)
      (hauth : cfg.authorize (cfg.mkRequest σ.cedarP (.write v)) = true)
      (hown : readable p.tenant σ.ctx) :
      Allowed cfg D s a (.write v) .ok { s with index := s.index ++ [⟨σ.ctx, v⟩] }
  | delegate {s a σ p ρ v}
      (hσ : s.agents a = some σ) (hp : cfg.sessions σ.session = some p)
      (hauth : cfg.authorize (cfg.mkRequest σ.cedarP (.delegate ρ v)) = true) :
      Allowed cfg D s a (.delegate ρ v) (.child σ.nextChild)
        ((s.setAgent a { σ with nextChild := σ.nextChild + 1 }).setAgent
          (childId a σ.nextChild) ⟨σ.session, ρ, σ.ctx, 0, [], some a⟩)
  | report {s a σ p v}
      (hσ : s.agents a = some σ) (hp : cfg.sessions σ.session = some p)
      (hpar : σ.parent ≠ none) :
      Allowed cfg D s a (.report v) .ok (s.setAgent a { σ with outbox := σ.outbox ++ [v] })
  | receive {s a σ p c σc}
      (hσ : s.agents a = some σ) (hp : cfg.sessions σ.session = some p)
      (hc : s.agents (childId a c) = some σc) :
      Allowed cfg D s a (.receive c) (.payloads σc.outbox)
        ((s.setAgent a { σ with ctx := σ.ctx.join σc.ctx }).setAgent
          (childId a c) { σc with outbox := [] })

/-- The step relation: an allowed row, or `denied` with the state unchanged. -/
inductive Step (cfg : Config T U Ext Role Req Qry Pay Sid) (D : Data T Ext Pay Sid) :
    State T Ext Role Pay Sid → AgentId Sid → Action Ext Role Pay Qry → Response Pay →
    State T Ext Role Pay Sid → Prop
  | allowed {s a act r s'} (h : Allowed cfg D s a act r s') : Step cfg D s a act r s'
  | denied {s a act} (h : ∀ r s', ¬ Allowed cfg D s a act r s') : Step cfg D s a act .denied s

/-- Initial state: one root agent per authenticated session. -/
def init (cfg : Config T U Ext Role Req Qry Pay Sid) (D : Data T Ext Pay Sid) :
    State T Ext Role Pay Sid where
  index := D.index₀
  agents := fun a =>
    match a.2 with
    | [] => (cfg.sessions a.1).map fun p =>
        ⟨a.1, cfg.principalRole p, rootCtx p.tenant, 0, [], none⟩
    | _ => none
  events := []

inductive Reachable (cfg : Config T U Ext Role Req Qry Pay Sid) (D : Data T Ext Pay Sid)
    (s₀ : State T Ext Role Pay Sid) : State T Ext Role Pay Sid → Prop
  | refl : Reachable cfg D s₀ s₀
  | step {s a act r s'} : Reachable cfg D s₀ s → Step cfg D s a act r s' → Reachable cfg D s₀ s'

/-! ## §7.1 Ghost provenance -/

end

inductive Origin (Ext Sid : Type)
  | toolO (k : Ext)
  | docO (i : Nat)
  | promptO (s : Sid)

abbrev Deps (Ext Sid : Type) := Origin Ext Sid → Prop

/-- `deps` of every agent, doc, event and outbox entry (the latter with the child's `ctx`
at the time of the `report`, which is the entry's label in (b2)). -/
structure Ghost (T Ext Pay Sid : Type) where
  agent : AgentId Sid → Deps Ext Sid
  doc : Doc T Pay → Deps Ext Sid
  event : Event T Ext Pay → Deps Ext Sid
  outbox : AgentId Sid → List (Deps Ext Sid × Label T)

structure GState (T Ext Role Pay Sid : Type) where
  base : State T Ext Role Pay Sid
  ghost : Ghost T Ext Pay Sid

section
variable {T U Ext Role Req Qry Pay Sid : Type} [DecidableEq Sid]

/-- Trusted label of an origin (registry result label, initial doc label, session tenant). -/
def label₀ (cfg : Config T U Ext Role Req Qry Pay Sid) (D : Data T Ext Pay Sid) :
    Origin Ext Sid → Label T
  | .toolO k => match cfg.extReg k with
    | some i => i.result.getD Label.bot
    | none => Label.bot
  | .docO i => match D.index₀[i]? with
    | some d => d.label
    | none => Label.bot
  | .promptO s => match cfg.sessions s with
    | some p => rootCtx p.tenant
    | none => Label.bot

def ginit (cfg : Config T U Ext Role Req Qry Pay Sid) (D : Data T Ext Pay Sid) :
    GState T Ext Role Pay Sid where
  base := init cfg D
  ghost :=
    { agent := fun a o => a.2 = [] ∧ o = .promptO a.1
      doc := fun d o => ∃ i, D.index₀[i]? = some d ∧ o = .docO i
      event := fun _ _ => False
      outbox := fun _ => [] }

/-- Ghost update of an *allowed* step (§7.1), computed from the pre-state and the action. -/
def ghostUpdateAllowed (cfg : Config T U Ext Role Req Qry Pay Sid)
    (s : State T Ext Role Pay Sid) (gh : Ghost T Ext Pay Sid) (a : AgentId Sid) :
    Action Ext Role Pay Qry → Ghost T Ext Pay Sid
  | act =>
    match s.agents a with
    | none => gh
    | some σ =>
      match cfg.sessions σ.session with
      | none => gh
      | some p =>
        match act with
        | .call k v =>
          let fromTool : Deps Ext Sid :=
            match k with
            | .ext k' =>
              match cfg.extReg k' with
              | some i => (match i.result with
                | some _ => fun o => o = .toolO k'
                | none => fun _ => False)
              | none => fun _ => False
            | .deliver => fun _ => False
          { gh with
            agent := fun a' o => gh.agent a' o ∨ (a' = a ∧ fromTool o)
            event := fun e o => gh.event e o ∨ (e = ⟨p.tenant, k, v, σ.ctx⟩ ∧ gh.agent a o) }
        | .query q =>
          { gh with
            agent := fun a' o => gh.agent a' o ∨
              (a' = a ∧ ∃ d ∈ cfg.rank q (readableDocs p.tenant s.index), gh.doc d o) }
        | .write v =>
          { gh with doc := fun d o => gh.doc d o ∨ (d = ⟨σ.ctx, v⟩ ∧ gh.agent a o) }
        | .delegate _ _ =>
          { gh with
            agent := fun a' => if a' = childId a σ.nextChild then gh.agent a else gh.agent a' }
        | .report _ =>
          { gh with
            outbox := fun a' => if a' = a then gh.outbox a ++ [(gh.agent a, σ.ctx)] else gh.outbox a' }
        | .receive c =>
          { gh with
            agent := fun a' o => gh.agent a' o ∨ (a' = a ∧ gh.agent (childId a c) o)
            outbox := fun a' => if a' = childId a c then [] else gh.outbox a' }

/-- Ghost update along a step: unchanged on `denied`. -/
def ghostUpdate (cfg : Config T U Ext Role Req Qry Pay Sid)
    (s : State T Ext Role Pay Sid) (gh : Ghost T Ext Pay Sid) (a : AgentId Sid)
    (act : Action Ext Role Pay Qry) : Response Pay → Ghost T Ext Pay Sid
  | .denied => gh
  | _ => ghostUpdateAllowed cfg s gh a act

inductive GStep (cfg : Config T U Ext Role Req Qry Pay Sid) (D : Data T Ext Pay Sid) :
    GState T Ext Role Pay Sid → AgentId Sid → Action Ext Role Pay Qry → Response Pay →
    GState T Ext Role Pay Sid → Prop
  | mk {g a act r s'} (h : Step cfg D g.base a act r s') :
      GStep cfg D g a act r ⟨s', ghostUpdate cfg g.base g.ghost a act r⟩

inductive GReachable (cfg : Config T U Ext Role Req Qry Pay Sid) (D : Data T Ext Pay Sid)
    (g₀ : GState T Ext Role Pay Sid) : GState T Ext Role Pay Sid → Prop
  | refl : GReachable cfg D g₀ g₀
  | step {g a act r g'} : GReachable cfg D g₀ g → GStep cfg D g a act r g' → GReachable cfg D g₀ g'

theorem ghost_proj {cfg : Config T U Ext Role Req Qry Pay Sid} {D : Data T Ext Pay Sid}
    {g g' : GState T Ext Role Pay Sid} {a act r} (h : GStep cfg D g a act r g') :
    Step cfg D g.base a act r g'.base := by
  cases h; assumption

theorem ghost_lift {cfg : Config T U Ext Role Req Qry Pay Sid} {D : Data T Ext Pay Sid}
    {s s' : State T Ext Role Pay Sid} {a act r} (h : Step cfg D s a act r s') :
    ∀ gh, ∃ gh', GStep cfg D ⟨s, gh⟩ a act r ⟨s', gh'⟩ :=
  fun gh => ⟨_, GStep.mk (g := ⟨s, gh⟩) h⟩

end

end TenantFlow.Model
