import TenantFlow.Proofs
/-!
# Theorem (d): refinement (`docs/spec.md` §7.5)

The executable monitor `Exec` implements the abstract `Model`.

* `Config.abs`, `Data.abs`, `State.abs` are the abstraction `α` of §7.5 (owner lists become
  membership predicates, association lists become lookup functions, the model's `rank` is
  `Exec`'s top-k over abstract docs).  `Response.abs` is `⌊·⌋`: the identity except that every
  `denied reason` maps to `denied`.
* (d1) `refines`: `step cfg D s a act = (r, s') → Model.Step (α cfg) (α D) (α s) a act ⌊r⌋ (α s')`.
* (d2) `refines_init`: `α (init cfg D) = Model.init (α cfg) (α D)`.
* Corollaries: `refines_denied` (a denial leaves the `Exec` state unchanged and no allowed model
  step exists, by `Step.det`-style reasoning on the model side), `refines_trace` (the abstraction
  of every state `runTrace` reaches from `init` is `Model.Reachable` from `Model.init`).
-/

namespace TenantFlow.Model

section
variable {T U Ext Role Req Qry Pay Sid : Type} [DecidableEq Sid]
variable {cfg : Config T U Ext Role Req Qry Pay Sid} {D : Data T Ext Pay Sid}

omit [DecidableEq Sid] in
theorem Label.ext {l₁ l₂ : Label T} (h₁ : ∀ t, l₁.owners t ↔ l₂.owners t)
    (h₂ : l₁.integ = l₂.integ) : l₁ = l₂ := by
  obtain ⟨o₁, i₁⟩ := l₁
  obtain ⟨o₂, i₂⟩ := l₂
  cases h₂
  have ho : o₁ = o₂ := funext fun t => propext (h₁ t)
  cases ho
  rfl

omit [DecidableEq Sid] in
theorem State.ext {s₁ s₂ : State T Ext Role Pay Sid} (h₁ : s₁.index = s₂.index)
    (h₂ : s₁.agents = s₂.agents) (h₃ : s₁.events = s₂.events) : s₁ = s₂ := by
  cases s₁; cases s₂; cases h₁; cases h₂; cases h₃; rfl

theorem Step.cast {s s' s'' : State T Ext Role Pay Sid} {a act r r'}
    (h : Step cfg D s a act r s') (hr : r = r') (hs : s' = s'') : Step cfg D s a act r' s'' := by
  rw [← hr, ← hs]; exact h

theorem Allowed.ne_denied {s s' : State T Ext Role Pay Sid} {a act r}
    (h : Allowed cfg D s a act r s') : r ≠ .denied := by
  cases h
  · exact callResp_ne_denied _ _ _
  all_goals (intro h; cases h)

/-- Every reachable base state carries some ghost state (lift along `ghost_lift`), so (a) and
(b2) apply to it. -/
theorem Reachable.ghost {s : State T Ext Role Pay Sid} (h : Reachable cfg D (init cfg D) s) :
    ∃ gh, GReachable cfg D (ginit cfg D) ⟨s, gh⟩ := by
  induction h with
  | refl => exact ⟨(ginit cfg D).ghost, .refl⟩
  | step _ hs ih =>
    obtain ⟨gh, hg⟩ := ih
    obtain ⟨gh', hg'⟩ := ghost_lift hs gh
    exact ⟨gh', hg.step hg'⟩

/-- If the model answers `denied`, no allowed row applies (the `denied` rule is the only source
of `denied`). -/
theorem Step.not_allowed_of_denied {s s' : State T Ext Role Pay Sid} {a act}
    (h : Step cfg D s a act .denied s') : ∀ r t, ¬ Allowed cfg D s a act r t := by
  cases h with
  | allowed h => exact absurd rfl h.ne_denied
  | denied h => exact h

end

end TenantFlow.Model

namespace TenantFlow.Exec

open TenantFlow.Model (Integrity Principal ToolId Action AgentId childId)

/-! ## Ranking is stable under relabelling -/

theorem map_insertByScore {X Y : Type} {sc : X → Nat} {sc' : Y → Nat} {f : X → Y}
    (hf : ∀ x, sc' (f x) = sc x) (d : X) :
    ∀ l : List X, (insertByScore sc d l).map f = insertByScore sc' (f d) (l.map f)
  | [] => rfl
  | e :: es => by
    by_cases h : sc e ≤ sc d <;> simp [insertByScore, h, hf, map_insertByScore hf d es]

theorem map_sortByScore {X Y : Type} {sc : X → Nat} {sc' : Y → Nat} {f : X → Y}
    (hf : ∀ x, sc' (f x) = sc x) :
    ∀ l : List X, (sortByScore sc l).map f = sortByScore sc' (l.map f)
  | [] => rfl
  | d :: ds => by
    simp only [sortByScore, List.map_cons, map_sortByScore hf ds, map_insertByScore hf]

/-! ## Boolean helpers -/

theorem of_bnot {b : Bool} (h : (!b) = true) : b = false := by cases b <;> simp_all
theorem of_not_bnot {b : Bool} (h : ¬ (!b) = true) : b = true := by cases b <;> simp_all
theorem of_not_band_not {a : Bool} {p : Prop} [Decidable p] (h : ¬ (a && !decide p) = true) :
    a = true → p := by
  cases a <;> by_cases hp : p <;> simp_all
theorem band_not_elim {a : Bool} {p : Prop} [Decidable p] (h : (a && !decide p) = true)
    (h' : a = true → p) : False := by
  cases a <;> by_cases hp : p <;> simp_all

section
variable {T U Ext Role Req Qry Pay Sid : Type} [DecidableEq T] [DecidableEq Ext] [DecidableEq Sid]

/-! ## The abstraction `α` and the projection `⌊·⌋` (§7.5) -/

def Label.abs (l : Label T) : Model.Label T := ⟨fun t => t ∈ l.owners, l.integ⟩

def ToolInfo.abs (i : ToolInfo T) : Model.ToolInfo T :=
  ⟨fun u => u ∈ i.observers, i.needsTrusted, i.result.map Label.abs⟩

def Doc.abs (d : Doc T Pay) : Model.Doc T Pay := ⟨Label.abs d.label, d.payload⟩

def AgentState.abs (σ : AgentState T Role Pay Sid) : Model.AgentState T Role Pay Sid :=
  ⟨σ.session, σ.cedarP, Label.abs σ.ctx, σ.nextChild, σ.outbox, σ.parent⟩

def Event.abs (e : Event T Ext Pay) : Model.Event T Ext Pay :=
  ⟨e.tenant, e.tool, e.args, Label.abs e.label⟩

/-- `⌊·⌋`: the identity except that every `denied reason` maps to `denied`. -/
def Response.abs : Response Pay → Model.Response Pay
  | .payload v => .payload v
  | .payloads vs => .payloads vs
  | .child n => .child n
  | .ok => .ok
  | .denied _ => .denied

/-- `α` on configurations.  The model's `rank` is `Exec`'s top-k (`sortByScore` + `take`) over
abstract docs; `rank_mem` is `mem_sortByScore`. -/
def Config.abs (cfg : Config T U Ext Role Req Qry Pay Sid) :
    Model.Config T U Ext Role Req Qry Pay Sid where
  sessions := fun sid => assocFind sid cfg.sessions
  extReg := fun k => (assocFind k cfg.extReg).map ToolInfo.abs
  principalRole := cfg.principalRole
  mkRequest := cfg.mkRequest
  authorize := cfg.authorize
  rank := fun q L => (sortByScore (fun d => cfg.score q d.payload) L).take cfg.topK
  rank_mem := fun _ _ _ h => mem_sortByScore (List.mem_of_mem_take h)

/-- `α` on data: only the labels of the initial index change representation. -/
def Data.abs (D : Data T Ext Pay Sid) : Model.Data T Ext Pay Sid :=
  ⟨D.tool, D.index₀.map Doc.abs, D.prompt⟩

/-- `α` on runtime states. -/
def State.abs (s : State T Ext Role Pay Sid) : Model.State T Ext Role Pay Sid where
  index := s.index.map Doc.abs
  agents := fun a => (assocFind a s.agents).map AgentState.abs
  events := s.events.map Event.abs

omit [DecidableEq T] [DecidableEq Ext] in
@[simp] theorem State.abs_index (s : State T Ext Role Pay Sid) :
    (State.abs s).index = s.index.map Doc.abs := rfl
omit [DecidableEq T] [DecidableEq Ext] in
@[simp] theorem State.abs_events (s : State T Ext Role Pay Sid) :
    (State.abs s).events = s.events.map Event.abs := rfl
omit [DecidableEq T] [DecidableEq Ext] in
@[simp] theorem State.abs_agents (s : State T Ext Role Pay Sid) (a : AgentId Sid) :
    (State.abs s).agents a = (assocFind a s.agents).map AgentState.abs := rfl

/-! ### Labels -/

theorem Label.abs_join (l₁ l₂ : Label T) :
    Label.abs (l₁.join l₂) = (Label.abs l₁).join (Label.abs l₂) :=
  Model.Label.ext
    (fun t => by by_cases h : t ∈ l₁.owners <;> simp [Label.abs, Label.join, Model.Label.join, h])
    rfl

omit [DecidableEq T] in
theorem Label.abs_bot : Label.abs (Label.bot : Label T) = Model.Label.bot :=
  Model.Label.ext (fun t => by simp [Label.abs, Label.bot, Model.Label.bot]) rfl

theorem Label.abs_joinAll :
    ∀ ls : List (Label T), Label.abs (Label.joinAll ls) = Model.Label.joinAll (ls.map Label.abs)
  | [] => Label.abs_bot
  | l :: ls => by
    simp only [Label.joinAll, Model.Label.joinAll, List.map_cons, Label.abs_join,
      Label.abs_joinAll ls]

omit [DecidableEq T] in
theorem Label.abs_single (t : T) (i : Integrity) :
    Label.abs ⟨[t], i⟩ = (⟨fun u => u = t, i⟩ : Model.Label T) :=
  Model.Label.ext (fun u => by simp [Label.abs]) rfl

theorem readable_abs (u : T) (l : Label T) :
    readable u l = true ↔ Model.readable u (Label.abs l) := by
  simp [readable, Model.readable, Label.abs, List.all_eq_true]

theorem readable_abs_decide (u : T) (l : Label T) [Decidable (Model.readable u (Label.abs l))] :
    readable u l = decide (Model.readable u (Label.abs l)) := by
  by_cases h : Model.readable u (Label.abs l)
  · rw [decide_eq_true h]; exact (readable_abs u l).mpr h
  · rw [decide_eq_false h]
    cases hb : readable u l
    · rfl
    · exact absurd ((readable_abs u l).mp hb) h

/-! ### Registry, agents, index, ranking -/

omit [DecidableEq T] in
theorem toolInfo_abs (cfg : Config T U Ext Role Req Qry Pay Sid) (t : T) (k : ToolId Ext) :
    (Config.abs cfg).toolInfo t k = (toolInfo cfg t k).map ToolInfo.abs := by
  cases k with
  | deliver =>
    show some (Model.ToolInfo.mk _ _ _) = some (Model.ToolInfo.mk _ _ _)
    congr 2
    funext u
    exact propext List.mem_singleton.symm
  | ext k => rfl

theorem assocFind_filter_ne {β : Type} (a a' : AgentId Sid) (l : List (AgentId Sid × β)) :
    assocFind a (l.filter fun q => decide (q.1 ≠ a')) = if a = a' then none else assocFind a l := by
  induction l with
  | nil => simp [assocFind]
  | cons q rest ih =>
    obtain ⟨k, v⟩ := q
    by_cases hk : k = a'
    · subst hk
      by_cases ha : a = k
      · subst ha; simp_all
      · simp_all [assocFind]
    · by_cases ha : a = k
      · subst ha; simp [assocFind, hk]
      · simp_all [assocFind]

omit [DecidableEq T] [DecidableEq Ext] in
theorem assocFind_setAgent (s : State T Ext Role Pay Sid) (a a' : AgentId Sid)
    (σ : AgentState T Role Pay Sid) :
    assocFind a' (s.setAgent a σ).agents = if a' = a then some σ else assocFind a' s.agents := by
  simp only [State.setAgent, assocFind, assocFind_filter_ne]
  by_cases h : a' = a <;> simp [h]

omit [DecidableEq T] [DecidableEq Ext] in
theorem State.abs_setAgent (s : State T Ext Role Pay Sid) (a : AgentId Sid)
    (σ : AgentState T Role Pay Sid) :
    State.abs (s.setAgent a σ) = (State.abs s).setAgent a (AgentState.abs σ) := by
  refine Model.State.ext rfl ?_ rfl
  funext a'
  simp only [State.abs_agents, Model.State.setAgent_agents, assocFind_setAgent]
  by_cases h : a' = a <;> simp [h]

open Classical in
theorem readableDocs_abs (t : T) (L : List (Doc T Pay)) :
    (L.filter fun d => readable t d.label).map Doc.abs = Model.readableDocs t (L.map Doc.abs) := by
  unfold Model.readableDocs
  rw [List.filter_map]
  congr 2
  funext d
  exact readable_abs_decide t d.label

omit [DecidableEq T] in
theorem rank_abs (cfg : Config T U Ext Role Req Qry Pay Sid) (q : Qry) (L : List (Doc T Pay)) :
    (rank cfg q L).map Doc.abs = (Config.abs cfg).rank q (L.map Doc.abs) := by
  show ((sortByScore _ L).take cfg.topK).map Doc.abs = (sortByScore _ (L.map Doc.abs)).take cfg.topK
  rw [List.map_take,
    map_sortByScore (sc := fun d : Doc T Pay => cfg.score q d.payload)
      (sc' := fun d : Model.Doc T Pay => cfg.score q d.payload) (f := Doc.abs) (fun _ => rfl)]

/-! ### Initial state -/

omit [DecidableEq T] [DecidableEq Ext] in
theorem assocFind_init_root (cfg : Config T U Ext Role Req Qry Pay Sid) (D : Data T Ext Pay Sid)
    (sid : Sid) :
    assocFind (sid, []) (init cfg D).agents =
      (assocFind sid cfg.sessions).map fun p =>
        (⟨sid, cfg.principalRole p, ⟨[p.tenant], .trusted⟩, 0, [], none⟩ :
          AgentState T Role Pay Sid) := by
  unfold init
  dsimp only
  generalize cfg.sessions = ss
  induction ss with
  | nil => rfl
  | cons sp rest ih =>
    obtain ⟨s, p⟩ := sp
    by_cases h : sid = s
    · subst h; simp [assocFind]
    · simp [assocFind, h, ih]

omit [DecidableEq T] [DecidableEq Ext] in
theorem assocFind_init_child (cfg : Config T U Ext Role Req Qry Pay Sid) (D : Data T Ext Pay Sid)
    (sid : Sid) (n : Nat) (path : List Nat) :
    assocFind (sid, n :: path) (init cfg D).agents = none := by
  unfold init
  dsimp only
  generalize cfg.sessions = ss
  induction ss with
  | nil => rfl
  | cons sp rest ih =>
    obtain ⟨s, p⟩ := sp
    simp [assocFind, ih]

omit [DecidableEq T] in
/-- **(d2)** The initial states agree. -/
theorem refines_init (cfg : Config T U Ext Role Req Qry Pay Sid) (D : Data T Ext Pay Sid) :
    State.abs (init cfg D) = Model.init (Config.abs cfg) (Data.abs D) := by
  refine Model.State.ext rfl ?_ rfl
  funext a
  obtain ⟨sid, path⟩ := a
  cases path with
  | nil =>
    simp only [State.abs_agents, assocFind_init_root, Model.init, Config.abs]
    cases assocFind sid cfg.sessions with
    | none => rfl
    | some p => simp [AgentState.abs, Label.abs_single, Model.rootCtx]
  | cons n path => simp [assocFind_init_child, Model.init]

/-! ## (d1) Forward simulation -/

/-- Every `Exec.step` is a `Model.Step` of the abstracted states, and a denial leaves the
executable state unchanged. -/
theorem refines_aux (cfg : Config T U Ext Role Req Qry Pay Sid) (D : Data T Ext Pay Sid)
    (s : State T Ext Role Pay Sid) (a : AgentId Sid) (act : Action Ext Role Pay Qry)
    (r : Response Pay) (s' : State T Ext Role Pay Sid) (h : step cfg D s a act = (r, s')) :
    Model.Step (Config.abs cfg) (Data.abs D) (State.abs s) a act (Response.abs r) (State.abs s') ∧
      (r.isDenied = true → s' = s) := by
  unfold step at h
  split at h
  · -- unknown agent
    rename_i hσ
    rw [Prod.mk.injEq] at h; obtain ⟨rfl, rfl⟩ := h
    refine ⟨.denied fun r t hA => ?_, fun _ => rfl⟩
    cases hA <;> simp_all
  rename_i σ hσ
  split at h
  · -- unknown session
    rename_i hp
    rw [Prod.mk.injEq] at h; obtain ⟨rfl, rfl⟩ := h
    refine ⟨.denied fun r t hA => ?_, fun _ => rfl⟩
    cases hA <;> simp only [State.abs_agents, hσ, Option.map_some, Option.some.injEq] at * <;>
      subst_vars <;> simp_all [Config.abs, AgentState.abs]
  rename_i p hp
  have hσ' : (State.abs s).agents a = some (AgentState.abs σ) := by
    rw [State.abs_agents, hσ]; rfl
  have hp' : (Config.abs cfg).sessions (AgentState.abs σ).session = some p := hp
  dsimp only at h
  cases act with
  | call k v =>
    dsimp only at h
    split at h
    · -- unregistered tool
      rename_i hi
      rw [Prod.mk.injEq] at h; obtain ⟨rfl, rfl⟩ := h
      refine ⟨.denied fun r t hA => ?_, fun _ => rfl⟩
      cases hA with
      | call hσ₂ hp₂ _ hi₂ _ _ =>
        rw [hσ'] at hσ₂; cases hσ₂
        rw [hp'] at hp₂; cases hp₂
        rw [toolInfo_abs, hi] at hi₂; cases hi₂
    rename_i i hi
    have hi' : (Config.abs cfg).toolInfo p.tenant k = some (ToolInfo.abs i) := by
      rw [toolInfo_abs, hi]; rfl
    split at h
    · -- cedar
      rename_i hc
      rw [Prod.mk.injEq] at h; obtain ⟨rfl, rfl⟩ := h
      refine ⟨.denied fun r t hA => ?_, fun _ => rfl⟩
      cases hA with
      | call hσ₂ hp₂ hauth₂ _ _ _ =>
        rw [hσ'] at hσ₂; cases hσ₂
        have := of_bnot hc
        exact absurd hauth₂ (by simp [this, Config.abs, AgentState.abs])
    rename_i hc
    have hauth' : (Config.abs cfg).authorize
        ((Config.abs cfg).mkRequest (AgentState.abs σ).cedarP (.call k v)) = true :=
      of_not_bnot hc
    split at h
    · -- flow: observers
      rename_i hob
      rw [Prod.mk.injEq] at h; obtain ⟨rfl, rfl⟩ := h
      refine ⟨.denied fun r t hA => ?_, fun _ => rfl⟩
      cases hA with
      | call hσ₂ hp₂ _ hi₂ hobs₂ _ =>
        rw [hσ'] at hσ₂; cases hσ₂
        rw [hp'] at hp₂; cases hp₂
        rw [hi'] at hi₂; cases hi₂
        have hall : (i.observers.all fun u => readable u σ.ctx) = true :=
          List.all_eq_true.mpr fun u hu => (readable_abs u σ.ctx).mpr (hobs₂ u hu)
        rw [of_bnot hob] at hall; cases hall
    rename_i hob
    have hobs' : ∀ u, (ToolInfo.abs i).observers u → Model.readable u (AgentState.abs σ).ctx :=
      fun u hu => (readable_abs u σ.ctx).mp (List.all_eq_true.mp (of_not_bnot hob) u hu)
    split at h
    · -- flow: integrity
      rename_i hint
      rw [Prod.mk.injEq] at h; obtain ⟨rfl, rfl⟩ := h
      refine ⟨.denied fun r t hA => ?_, fun _ => rfl⟩
      cases hA with
      | call hσ₂ hp₂ _ hi₂ _ hint₂ =>
        rw [hσ'] at hσ₂; cases hσ₂
        rw [hp'] at hp₂; cases hp₂
        rw [hi'] at hi₂; cases hi₂
        exact band_not_elim hint hint₂
    rename_i hint
    have hint' : (ToolInfo.abs i).needsTrusted = true →
        (AgentState.abs σ).ctx.integ = .trusted :=
      of_not_band_not hint
    -- allowed
    rw [Prod.mk.injEq] at h; obtain ⟨rfl, rfl⟩ := h
    have hA := Model.Step.allowed (Model.Allowed.call (D := Data.abs D) hσ' hp' hauth' hi' hobs' hint')
    cases hres : i.result with
    | none =>
      refine ⟨hA.cast ?_ ?_, fun hd => ?_⟩
      · cases k <;> simp [Model.callResp, Response.abs, ToolInfo.abs, hres]
      · refine Model.State.ext rfl ?_ ?_
        · funext a'
          simp only [Model.State.setAgent_agents, State.abs_agents, assocFind_setAgent]
          by_cases ha : a' = a <;> simp [ha, AgentState.abs, Model.ToolInfo.joinResult, ToolInfo.abs, hres]
        · simp [Event.abs, AgentState.abs]
      · cases k <;> simp [Response.isDenied] at hd
    | some ℓr =>
      refine ⟨hA.cast ?_ ?_, fun hd => ?_⟩
      · cases k <;> simp [Model.callResp, Response.abs, ToolInfo.abs, Data.abs, hres]
      · refine Model.State.ext rfl ?_ ?_
        · funext a'
          simp only [Model.State.setAgent_agents, State.abs_agents, assocFind_setAgent]
          by_cases ha : a' = a <;>
            simp [ha, AgentState.abs, Model.ToolInfo.joinResult, ToolInfo.abs, hres, Label.abs_join]
        · simp [Event.abs, AgentState.abs]
      · cases k <;> simp [Response.isDenied] at hd
  | query q =>
    dsimp only at h
    split at h
    · -- cedar
      rename_i hc
      rw [Prod.mk.injEq] at h; obtain ⟨rfl, rfl⟩ := h
      refine ⟨.denied fun r t hA => ?_, fun _ => rfl⟩
      cases hA with
      | query hσ₂ hp₂ hauth₂ =>
        rw [hσ'] at hσ₂; cases hσ₂
        have := of_bnot hc
        exact absurd hauth₂ (by simp [this, Config.abs, AgentState.abs])
    rename_i hc
    have hauth' : (Config.abs cfg).authorize
        ((Config.abs cfg).mkRequest (AgentState.abs σ).cedarP (.query q)) = true :=
      of_not_bnot hc
    rw [Prod.mk.injEq] at h; obtain ⟨rfl, rfl⟩ := h
    have hA := Model.Step.allowed (Model.Allowed.query (D := Data.abs D) hσ' hp' hauth')
    refine ⟨hA.cast ?_ ?_, fun hd => by simp [Response.isDenied] at hd⟩
    · simp only [State.abs_index, ← readableDocs_abs, ← rank_abs, List.map_map, Response.abs]
      rfl
    · rw [State.abs_setAgent]
      simp only [State.abs_index, ← readableDocs_abs, ← rank_abs, List.map_map, AgentState.abs,
        Label.abs_join, Label.abs_joinAll]
      rfl
  | write v =>
    dsimp only at h
    split at h
    · -- cedar
      rename_i hc
      rw [Prod.mk.injEq] at h; obtain ⟨rfl, rfl⟩ := h
      refine ⟨.denied fun r t hA => ?_, fun _ => rfl⟩
      cases hA with
      | write hσ₂ hp₂ hauth₂ _ =>
        rw [hσ'] at hσ₂; cases hσ₂
        have := of_bnot hc
        exact absurd hauth₂ (by simp [this, Config.abs, AgentState.abs])
    rename_i hc
    have hauth' : (Config.abs cfg).authorize
        ((Config.abs cfg).mkRequest (AgentState.abs σ).cedarP (.write v)) = true :=
      of_not_bnot hc
    split at h
    · -- flow: tainted agent may not write
      rename_i hown
      rw [Prod.mk.injEq] at h; obtain ⟨rfl, rfl⟩ := h
      refine ⟨.denied fun r t hA => ?_, fun _ => rfl⟩
      cases hA with
      | write hσ₂ hp₂ _ hown₂ =>
        rw [hσ'] at hσ₂; cases hσ₂
        rw [hp'] at hp₂; cases hp₂
        have := (readable_abs _ _).mpr hown₂
        rw [of_bnot hown] at this; cases this
    rename_i hown
    have hown' : Model.readable p.tenant (AgentState.abs σ).ctx :=
      (readable_abs _ _).mp (of_not_bnot hown)
    rw [Prod.mk.injEq] at h; obtain ⟨rfl, rfl⟩ := h
    have hA := Model.Step.allowed (Model.Allowed.write (D := Data.abs D) hσ' hp' hauth' hown')
    refine ⟨hA.cast rfl ?_, fun hd => by simp [Response.isDenied] at hd⟩
    refine Model.State.ext ?_ rfl rfl
    simp [Doc.abs, AgentState.abs]
  | delegate ρ task =>
    dsimp only at h
    split at h
    · -- cedar
      rename_i hc
      rw [Prod.mk.injEq] at h; obtain ⟨rfl, rfl⟩ := h
      refine ⟨.denied fun r t hA => ?_, fun _ => rfl⟩
      cases hA with
      | delegate hσ₂ hp₂ hauth₂ =>
        rw [hσ'] at hσ₂; cases hσ₂
        have := of_bnot hc
        exact absurd hauth₂ (by simp [this, Config.abs, AgentState.abs])
    rename_i hc
    have hauth' : (Config.abs cfg).authorize
        ((Config.abs cfg).mkRequest (AgentState.abs σ).cedarP (.delegate ρ task)) = true :=
      of_not_bnot hc
    rw [Prod.mk.injEq] at h; obtain ⟨rfl, rfl⟩ := h
    have hA := Model.Step.allowed (Model.Allowed.delegate (D := Data.abs D) hσ' hp' hauth')
    refine ⟨hA.cast rfl ?_, fun hd => by simp [Response.isDenied] at hd⟩
    rw [State.abs_setAgent, State.abs_setAgent]
    rfl
  | report v =>
    dsimp only at h
    split at h
    · -- no parent
      rename_i hpar
      rw [Prod.mk.injEq] at h; obtain ⟨rfl, rfl⟩ := h
      refine ⟨.denied fun r t hA => ?_, fun _ => rfl⟩
      cases hA with
      | report hσ₂ hp₂ hpar₂ =>
        rw [hσ'] at hσ₂; cases hσ₂
        exact hpar₂ (Option.isNone_iff_eq_none.mp hpar)
    rename_i hpar
    have hpar' : (AgentState.abs σ).parent ≠ none :=
      fun h => hpar (Option.isNone_iff_eq_none.mpr h)
    rw [Prod.mk.injEq] at h; obtain ⟨rfl, rfl⟩ := h
    have hA := Model.Step.allowed (Model.Allowed.report (D := Data.abs D) (v := v) hσ' hp' hpar')
    refine ⟨hA.cast rfl ?_, fun hd => by simp [Response.isDenied] at hd⟩
    rw [State.abs_setAgent]
    rfl
  | receive c =>
    dsimp only at h
    split at h
    · -- no such child
      rename_i hc
      rw [Prod.mk.injEq] at h; obtain ⟨rfl, rfl⟩ := h
      refine ⟨.denied fun r t hA => ?_, fun _ => rfl⟩
      cases hA with
      | receive hσ₂ hp₂ hc₂ =>
        rw [State.abs_agents, hc] at hc₂; cases hc₂
    rename_i σc hc
    have hc' : (State.abs s).agents (childId a c) = some (AgentState.abs σc) := by
      rw [State.abs_agents, hc]; rfl
    rw [Prod.mk.injEq] at h; obtain ⟨rfl, rfl⟩ := h
    have hA := Model.Step.allowed (Model.Allowed.receive (D := Data.abs D) hσ' hp' hc')
    refine ⟨hA.cast rfl ?_, fun hd => by simp [Response.isDenied] at hd⟩
    rw [State.abs_setAgent, State.abs_setAgent]
    simp [AgentState.abs, Label.abs_join]

/-- **(d1)** Forward simulation: every step of the executable monitor is a step of the model
on the abstracted states, with denial reasons collapsed by `Response.abs`. -/
theorem refines (cfg : Config T U Ext Role Req Qry Pay Sid) (D : Data T Ext Pay Sid)
    (s : State T Ext Role Pay Sid) (a : AgentId Sid) (act : Action Ext Role Pay Qry)
    {r : Response Pay} {s' : State T Ext Role Pay Sid} (h : step cfg D s a act = (r, s')) :
    Model.Step (Config.abs cfg) (Data.abs D) (State.abs s) a act (Response.abs r) (State.abs s') :=
  (refines_aux cfg D s a act r s' h).1

/-- Corollary: if `Exec` answers `denied`, the state is unchanged and no allowed model step
exists. -/
theorem refines_denied (cfg : Config T U Ext Role Req Qry Pay Sid) (D : Data T Ext Pay Sid)
    (s : State T Ext Role Pay Sid) (a : AgentId Sid) (act : Action Ext Role Pay Qry)
    {msg : String} {s' : State T Ext Role Pay Sid} (h : step cfg D s a act = (.denied msg, s')) :
    s' = s ∧ ∀ r t, ¬ Model.Allowed (Config.abs cfg) (Data.abs D) (State.abs s) a act r t :=
  ⟨(refines_aux cfg D s a act _ s' h).2 rfl, (refines cfg D s a act h).not_allowed_of_denied⟩

/-- Traces: the abstraction of the state after any trace is reachable from the abstraction of
the start state. -/
theorem refines_runTrace (cfg : Config T U Ext Role Req Qry Pay Sid) (D : Data T Ext Pay Sid) :
    ∀ (tr : List (AgentId Sid × Action Ext Role Pay Qry)) (s : State T Ext Role Pay Sid)
      (s₀ : Model.State T Ext Role Pay Sid),
      Model.Reachable (Config.abs cfg) (Data.abs D) s₀ (State.abs s) →
      Model.Reachable (Config.abs cfg) (Data.abs D) s₀ (State.abs (runTrace cfg D s tr).2)
  | [], _, _, hR => hR
  | (a, act) :: rest, s, s₀, hR => by
    rcases hst : step cfg D s a act with ⟨r, s'⟩
    have ih := refines_runTrace cfg D rest s' s₀ (hR.step (refines cfg D s a act hst))
    rcases hrt : runTrace cfg D s' rest with ⟨rs, s''⟩
    rw [hrt] at ih
    simpa [runTrace, hst, hrt] using ih

/-- Corollary: every state the executable monitor reaches from `init` abstracts to a model
state reachable from `Model.init`; (a) and (b2) therefore apply to `Exec` traces. -/
theorem refines_trace (cfg : Config T U Ext Role Req Qry Pay Sid) (D : Data T Ext Pay Sid)
    (tr : List (AgentId Sid × Action Ext Role Pay Qry)) :
    Model.Reachable (Config.abs cfg) (Data.abs D) (Model.init (Config.abs cfg) (Data.abs D))
      (State.abs (runTrace cfg D (init cfg D) tr).2) :=
  refines_runTrace cfg D tr _ _ (by rw [refines_init]; exact .refl)

/-- Corollary: the same with ghost provenance, in the form `Model.isolation`, `Model.no_launder`
and `Model.ctx_mono_ghost` expect. -/
theorem refines_ghost (cfg : Config T U Ext Role Req Qry Pay Sid) (D : Data T Ext Pay Sid)
    (tr : List (AgentId Sid × Action Ext Role Pay Qry)) :
    ∃ gh, Model.GReachable (Config.abs cfg) (Data.abs D) (Model.ginit (Config.abs cfg) (Data.abs D))
      ⟨State.abs (runTrace cfg D (init cfg D) tr).2, gh⟩ :=
  (refines_trace cfg D tr).ghost

end

end TenantFlow.Exec
