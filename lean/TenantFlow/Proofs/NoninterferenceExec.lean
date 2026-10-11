import TenantFlow.Proofs.Noninterference
import TenantFlow.Proofs.Refinement

/-!
# Theorem (c) for `Exec` traces (`docs/spec.md` §7.5, corollary)

`Exec.run` is the executable counterpart of `Model.run`: the same strategies and the same schedule
drive the executable monitor `Exec.step` instead of the model's `stepFn`.  Histories hold model
responses (denial reasons collapsed by `Response.abs`), so a strategy is reason-blind, exactly as
in the model (§7.5: the model collapses all reasons).

* `run_abs`: `α (Exec.run cfg strat sched D) = Model.run (α cfg) strat sched (α D)`
  (lockstep: `runStep_abs` via (d1) `refines` and `Step.eq_stepFn`, `initRun_abs` via (d2)).
* `obs_abs`: `α (Exec.obs cfg B evs) = Model.obs (α cfg) B (α evs)`.
* `Exec.noninterference`: for `α`-low-equivalent data the `B`-observable events of `Exec.run` agree
  up to `α` (same tenant, tool and arguments, labels equal as sets).
-/

namespace TenantFlow.Exec

open TenantFlow.Model (AgentId Action Strategy)

section
variable {T U Ext Role Req Qry Pay Sid : Type} [DecidableEq T] [DecidableEq Ext] [DecidableEq Sid]

/-! ## `Exec.run` -/

/-- Run state: monitor state plus the observation history of every agent id (model responses). -/
structure RunState (T Ext Role Pay Sid : Type) where
  state : State T Ext Role Pay Sid
  hist : AgentId Sid → List (Model.Response Pay)

/-- Initial run state: `init cfg D`; every root agent has observed its prompt. -/
def initRun (cfg : Config T U Ext Role Req Qry Pay Sid) (D : Data T Ext Pay Sid) :
    RunState T Ext Role Pay Sid where
  state := init cfg D
  hist := fun a => match a.2 with
    | [] => [.payload (D.prompt a.1)]
    | _ => []

/-- One scheduled move: a no-op if the agent does not exist, else the strategy's action is stepped. -/
def runStep (cfg : Config T U Ext Role Req Qry Pay Sid) (D : Data T Ext Pay Sid)
    (strat : AgentId Sid → Strategy Ext Role Pay Qry) (rs : RunState T Ext Role Pay Sid)
    (a : AgentId Sid) : RunState T Ext Role Pay Sid :=
  match assocFind a rs.state.agents with
  | none => rs
  | some _ =>
    let act := strat a (rs.hist a)
    let rs' := step cfg D rs.state a act
    ⟨rs'.2, Model.histUpdate rs.hist a act (Response.abs rs'.1)⟩

def runAll (cfg : Config T U Ext Role Req Qry Pay Sid) (D : Data T Ext Pay Sid)
    (strat : AgentId Sid → Strategy Ext Role Pay Qry) :
    List (AgentId Sid) → RunState T Ext Role Pay Sid → RunState T Ext Role Pay Sid
  | [], rs => rs
  | a :: sched, rs => runAll cfg D strat sched (runStep cfg D strat rs a)

/-- `Exec.run cfg strat sched D`: the event list after the whole schedule. -/
def run (cfg : Config T U Ext Role Req Qry Pay Sid)
    (strat : AgentId Sid → Strategy Ext Role Pay Qry) (sched : List (AgentId Sid))
    (D : Data T Ext Pay Sid) : List (Event T Ext Pay) :=
  (runAll cfg D strat sched (initRun cfg D)).state.events

/-! ## `α` on run states and its commutation with the run -/

def RunState.abs (rs : RunState T Ext Role Pay Sid) : Model.RunState T Ext Role Pay Sid :=
  ⟨State.abs rs.state, rs.hist⟩

omit [DecidableEq T] [DecidableEq Ext] in
@[simp] theorem RunState.abs_state (rs : RunState T Ext Role Pay Sid) :
    (RunState.abs rs).state = State.abs rs.state := rfl
omit [DecidableEq T] [DecidableEq Ext] in
@[simp] theorem RunState.abs_hist (rs : RunState T Ext Role Pay Sid) :
    (RunState.abs rs).hist = rs.hist := rfl

omit [DecidableEq T] in
theorem initRun_abs (cfg : Config T U Ext Role Req Qry Pay Sid) (D : Data T Ext Pay Sid) :
    RunState.abs (initRun cfg D) = Model.initRun (Config.abs cfg) (Data.abs D) := by
  show (⟨State.abs (init cfg D), _⟩ : Model.RunState T Ext Role Pay Sid) = ⟨Model.init _ _, _⟩
  rw [refines_init]
  rfl

/-- (d1) in the form the run function needs. -/
theorem stepFn_abs (cfg : Config T U Ext Role Req Qry Pay Sid) (D : Data T Ext Pay Sid)
    (s : State T Ext Role Pay Sid) (a : AgentId Sid) (act : Action Ext Role Pay Qry) :
    Model.stepFn (Config.abs cfg) (Data.abs D) (State.abs s) a act =
      (Response.abs (step cfg D s a act).1, State.abs (step cfg D s a act).2) :=
  Model.Step.eq_stepFn (refines cfg D s a act rfl)

theorem runStep_abs (cfg : Config T U Ext Role Req Qry Pay Sid) (D : Data T Ext Pay Sid)
    (strat : AgentId Sid → Strategy Ext Role Pay Qry) (rs : RunState T Ext Role Pay Sid)
    (a : AgentId Sid) :
    RunState.abs (runStep cfg D strat rs a) =
      Model.runStep (Config.abs cfg) (Data.abs D) strat (RunState.abs rs) a := by
  unfold runStep Model.runStep
  cases h : assocFind a rs.state.agents with
  | none => simp [h]
  | some σ => simp [h, RunState.abs, stepFn_abs]

theorem runAll_abs (cfg : Config T U Ext Role Req Qry Pay Sid) (D : Data T Ext Pay Sid)
    (strat : AgentId Sid → Strategy Ext Role Pay Qry) :
    ∀ (sched : List (AgentId Sid)) (rs : RunState T Ext Role Pay Sid),
      RunState.abs (runAll cfg D strat sched rs) =
        Model.runAll (Config.abs cfg) (Data.abs D) strat sched (RunState.abs rs)
  | [], _ => rfl
  | a :: sched, rs => by
    rw [runAll, Model.runAll, runAll_abs cfg D strat sched, runStep_abs]

/-- `α (Exec.run …) = Model.run …`. -/
theorem run_abs (cfg : Config T U Ext Role Req Qry Pay Sid)
    (strat : AgentId Sid → Strategy Ext Role Pay Qry) (sched : List (AgentId Sid))
    (D : Data T Ext Pay Sid) :
    (run cfg strat sched D).map Event.abs = Model.run (Config.abs cfg) strat sched (Data.abs D) := by
  unfold run Model.run
  rw [← State.abs_events, ← RunState.abs_state, runAll_abs, initRun_abs]

/-! ## `obs` commutes with `α` -/

omit [DecidableEq T] in
theorem observersOf_abs (cfg : Config T U Ext Role Req Qry Pay Sid) (e : Event T Ext Pay) (B : T) :
    B ∈ observersOf cfg e ↔ (Config.abs cfg).observersOf (Event.abs e) B := by
  unfold observersOf Model.Config.observersOf
  rw [show (Event.abs e).tenant = e.tenant from rfl, show (Event.abs e).tool = e.tool from rfl,
    toolInfo_abs]
  cases toolInfo cfg e.tenant e.tool with
  | none => simp
  | some i => simp [ToolInfo.abs]

theorem obs_abs (cfg : Config T U Ext Role Req Qry Pay Sid) (B : T) (evs : List (Event T Ext Pay)) :
    (obs cfg B evs).map Event.abs = Model.obs (Config.abs cfg) B (evs.map Event.abs) := by
  unfold obs Model.obs
  rw [List.filter_map]
  congr 1
  apply List.filter_congr
  intro e _
  exact decide_eq_decide.mpr (observersOf_abs cfg e B)

/-! ## Theorem (c) for `Exec` traces -/

/-- **Theorem (c) for the executable monitor** (`docs/spec.md` §7.5, corollary): for every
configuration, every family of (reason-blind) strategies, every schedule and every observer tenant
`B`, data sets that are low-equivalent after abstraction produce `B`-observable events that agree
up to `α` (same tenant, tool and arguments; labels equal as sets). -/
theorem noninterference (cfg : Config T U Ext Role Req Qry Pay Sid)
    (strat : AgentId Sid → Strategy Ext Role Pay Qry) (sched : List (AgentId Sid)) (B : T)
    {D₁ D₂ : Data T Ext Pay Sid} (hL : Model.LowEq (Config.abs cfg) B (Data.abs D₁) (Data.abs D₂)) :
    (obs cfg B (run cfg strat sched D₁)).map Event.abs =
      (obs cfg B (run cfg strat sched D₂)).map Event.abs := by
  rw [obs_abs, obs_abs, run_abs, run_abs]
  exact Model.noninterference strat sched B hL

end

end TenantFlow.Exec
