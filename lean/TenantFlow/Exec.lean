import TenantFlow.Model
/-!
# Executable monitor (`docs/spec.md` §6)

Computable counterpart of `TenantFlow.Model`, used by the oracle (S1) and ported to Python (S2).

* Owner sets are duplicate-free lists; label equality is set equality (`Label.equiv`).
  The oracle sorts owners when it serialises (S1).
* `rank` is a stable sort by a configurable score followed by top-k (`rank_mem` in `Proofs`).
* Polymorphic in `Pay` (D8): nothing here can inspect a payload; only the configuration
  parameters `score`, `mkRequest` and the data parameter `tool` consume one.
* `Response.denied` carries a reason string; the model collapses all reasons (§7.5).
-/


namespace TenantFlow.Exec

open TenantFlow.Model (Integrity Principal ToolId Action AgentId childId)

structure Label (T : Type) where
  owners : List T
  integ : Integrity
  deriving DecidableEq, Repr

namespace Label
variable {T : Type} [DecidableEq T]

def bot : Label T := ⟨[], .trusted⟩

def join (l₁ l₂ : Label T) : Label T :=
  ⟨l₁.owners ++ l₂.owners.filter (fun t => decide (t ∉ l₁.owners)),
   Integrity.max l₁.integ l₂.integ⟩

def joinAll : List (Label T) → Label T
  | [] => bot
  | l :: ls => join l (joinAll ls)

def le (l₁ l₂ : Label T) : Bool :=
  l₁.owners.all (fun t => decide (t ∈ l₂.owners)) && decide (l₁.integ ≤ l₂.integ)

/-- Set equality of labels. -/
def equiv (l₁ l₂ : Label T) : Bool := le l₁ l₂ && le l₂ l₁

end Label

def readable {T : Type} [DecidableEq T] (u : T) (l : Label T) : Bool :=
  l.owners.all fun t => decide (t = u)

structure ToolInfo (T : Type) where
  observers : List T
  needsTrusted : Bool
  result : Option (Label T)
  deriving DecidableEq, Repr

structure Doc (T Pay : Type) where
  label : Label T
  payload : Pay
  deriving DecidableEq, Repr

structure AgentState (T Role Pay Sid : Type) where
  session : Sid
  cedarP : Role
  ctx : Label T
  nextChild : Nat
  outbox : List Pay
  parent : Option (AgentId Sid)
  deriving Repr

structure Event (T Ext Pay : Type) where
  tenant : T
  tool : ToolId Ext
  args : Pay
  label : Label T
  deriving DecidableEq, Repr

inductive Response (Pay : Type)
  | payload (v : Pay)
  | payloads (vs : List Pay)
  | child (n : Nat)
  | ok
  | denied (reason : String)
  deriving DecidableEq, Repr

def Response.isDenied {Pay : Type} : Response Pay → Bool
  | .denied _ => true
  | _ => false

structure Config (T U Ext Role Req Qry Pay Sid : Type) where
  sessions : List (Sid × Principal T U)
  extReg : List (Ext × ToolInfo T)
  principalRole : Principal T U → Role
  mkRequest : Role → Action Ext Role Pay Qry → Req
  authorize : Req → Bool
  /-- Toy embedding: relevance of a payload for a query. -/
  score : Qry → Pay → Nat
  topK : Nat

structure Data (T Ext Pay Sid : Type) where
  tool : Ext → Pay → Pay
  index₀ : List (Doc T Pay)
  prompt : Sid → Pay

structure State (T Ext Role Pay Sid : Type) where
  index : List (Doc T Pay)
  agents : List (AgentId Sid × AgentState T Role Pay Sid)
  events : List (Event T Ext Pay)
  deriving Repr

def assocFind {α β : Type} [DecidableEq α] (k : α) : List (α × β) → Option β
  | [] => none
  | (k', v) :: rest => if k = k' then some v else assocFind k rest

section
variable {T U Ext Role Req Qry Pay Sid : Type} [DecidableEq T] [DecidableEq Ext] [DecidableEq Sid]

/-! ### Ranking: stable sort by score (descending), then top-k -/

/-- Generic in the element type so that the model's `rank` can be instantiated with it (§7.5). -/
def insertByScore {X : Type} (sc : X → Nat) (d : X) : List X → List X
  | [] => [d]
  | e :: es => if sc e ≤ sc d then d :: e :: es else e :: insertByScore sc d es

def sortByScore {X : Type} (sc : X → Nat) : List X → List X
  | [] => []
  | d :: ds => insertByScore sc d (sortByScore sc ds)

def rank (cfg : Config T U Ext Role Req Qry Pay Sid) (q : Qry) (L : List (Doc T Pay)) :
    List (Doc T Pay) :=
  (sortByScore (fun d => cfg.score q d.payload) L).take cfg.topK

/-! ### Registry and state helpers -/

def toolInfo (cfg : Config T U Ext Role Req Qry Pay Sid) (t : T) : ToolId Ext → Option (ToolInfo T)
  | .deliver => some ⟨[t], false, none⟩
  | .ext k => assocFind k cfg.extReg

def observersOf (cfg : Config T U Ext Role Req Qry Pay Sid) (e : Event T Ext Pay) : List T :=
  match toolInfo cfg e.tenant e.tool with
  | some i => i.observers
  | none => []

/-- `obs_B`: the events whose arguments tenant `B`'s principals or tools receive. -/
def obs (cfg : Config T U Ext Role Req Qry Pay Sid) (B : T) (evs : List (Event T Ext Pay)) :
    List (Event T Ext Pay) :=
  evs.filter fun e => decide (B ∈ observersOf cfg e)

def State.setAgent (s : State T Ext Role Pay Sid) (a : AgentId Sid) (σ : AgentState T Role Pay Sid) :
    State T Ext Role Pay Sid :=
  { s with agents := (a, σ) :: s.agents.filter fun q => decide (q.1 ≠ a) }

def init (cfg : Config T U Ext Role Req Qry Pay Sid) (D : Data T Ext Pay Sid) :
    State T Ext Role Pay Sid where
  index := D.index₀
  agents := cfg.sessions.map fun (sid, p) =>
    ((sid, []), ⟨sid, cfg.principalRole p, ⟨[p.tenant], .trusted⟩, 0, [], none⟩)
  events := []

/-! ### The monitor (§5, one branch per row) -/

def step (cfg : Config T U Ext Role Req Qry Pay Sid) (D : Data T Ext Pay Sid)
    (s : State T Ext Role Pay Sid) (a : AgentId Sid) (act : Action Ext Role Pay Qry) :
    Response Pay × State T Ext Role Pay Sid :=
  match assocFind a s.agents with
  | none => (.denied "unknown agent", s)
  | some σ =>
    match assocFind σ.session cfg.sessions with
    | none => (.denied "unknown session", s)
    | some p =>
      let t := p.tenant
      let cedar := cfg.authorize (cfg.mkRequest σ.cedarP act)
      match act with
      | .call k v =>
        match toolInfo cfg t k with
        | none => (.denied "unregistered tool", s)
        | some i =>
          if !cedar then (.denied "cedar", s)
          else if !(i.observers.all fun u => readable u σ.ctx) then
            (.denied "flow: context not readable by every observer of the tool", s)
          else if i.needsTrusted && !decide (σ.ctx.integ = .trusted) then
            (.denied "flow: tool requires trusted input", s)
          else
            let resp : Response Pay :=
              match k, i.result with
              | .ext k', some _ => .payload (D.tool k' v)
              | _, _ => .ok
            let ctx' := match i.result with
              | some ℓr => σ.ctx.join ℓr
              | none => σ.ctx
            (resp, { s.setAgent a { σ with ctx := ctx' } with
                      events := s.events ++ [⟨t, k, v, σ.ctx⟩] })
      | .query q =>
        if !cedar then (.denied "cedar", s)
        else
          let R := rank cfg q (s.index.filter fun d => readable t d.label)
          (.payloads (R.map (·.payload)),
           s.setAgent a { σ with ctx := σ.ctx.join (Label.joinAll (R.map (·.label))) })
      | .write v =>
        if !cedar then (.denied "cedar", s)
        else if !readable t σ.ctx then (.denied "flow: tainted agent may not write", s)
        else (.ok, { s with index := s.index ++ [⟨σ.ctx, v⟩] })
      | .delegate ρ _ =>
        if !cedar then (.denied "cedar", s)
        else
          (.child σ.nextChild,
           (s.setAgent a { σ with nextChild := σ.nextChild + 1 }).setAgent
             (childId a σ.nextChild) ⟨σ.session, ρ, σ.ctx, 0, [], some a⟩)
      | .report v =>
        if σ.parent.isNone then (.denied "report: agent has no parent", s)
        else (.ok, s.setAgent a { σ with outbox := σ.outbox ++ [v] })
      | .receive c =>
        match assocFind (childId a c) s.agents with
        | none => (.denied "receive: no such child", s)
        | some σc =>
          (.payloads σc.outbox,
           (s.setAgent a { σ with ctx := σ.ctx.join σc.ctx }).setAgent
             (childId a c) { σc with outbox := [] })

/-- Run a trace; returns the responses in order and the final state. -/
def runTrace (cfg : Config T U Ext Role Req Qry Pay Sid) (D : Data T Ext Pay Sid) :
    State T Ext Role Pay Sid → List (AgentId Sid × Action Ext Role Pay Qry) →
    List (Response Pay) × State T Ext Role Pay Sid
  | s, [] => ([], s)
  | s, (a, act) :: rest =>
    let (r, s') := step cfg D s a act
    let (rs, s'') := runTrace cfg D s' rest
    (r :: rs, s'')

end

end TenantFlow.Exec
