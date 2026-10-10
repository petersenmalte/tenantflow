import Lean.Data.Json
import TenantFlow.Exec

/-!
# Oracle (task S1)

`lake exe oracle`: reads a JSON scenario (initial state + trace) on stdin, runs
`TenantFlow.Exec.step` and prints the decisions and resulting labels as JSON.
Format: `docs/oracle-format.md`. This file only parses and serialises; all decisions are made by
`Exec.step` (theorem (d) in `Proofs/Refinement.lean` covers it).
-/

open Lean (Json)
open TenantFlow.Model (Integrity Principal ToolId Action AgentId)
open TenantFlow.Exec

namespace Oracle

/-- Cedar request abstraction: the agent's role and a flat action name (`call:<tool>`, `query`, ...). -/
structure Req where
  role : String
  action : String
  deriving DecidableEq, Repr

abbrev Act := Action String String Json String
abbrev Cfg := Config String String String String Req String Json String
abbrev Dat := Data String String Json String
abbrev St := State String String String Json String
abbrev Lbl := Label String

/-! ### Parsing -/

abbrev P := Except String

def field (j : Json) (k : String) : P Json := j.getObjVal? k
def optField (j : Json) (k : String) : Option Json :=
  match j.getObjVal? k with
  | .ok v => if v.isNull then none else some v
  | .error _ => none
def str (j : Json) : P String := j.getStr?
def list (j : Json) : P (List Json) := (·.toList) <$> j.getArr?
def strList (j : Json) : P (List String) := do (← list j).mapM str

def parseInteg (j : Json) : P Integrity := do
  match ← str j with
  | "trusted" => pure .trusted
  | "untrusted" => pure .untrusted
  | s => throw s!"bad integrity '{s}'"

def parseLabel (j : Json) : P Lbl := do
  let owners ← strList (← field j "owners")
  let integ ← parseInteg (← field j "integrity")
  -- owner sets are duplicate-free lists
  pure ⟨owners.eraseDups, integ⟩

def toolId (s : String) : ToolId String := if s == "deliver" then .deliver else .ext s

def toolName : ToolId String → String
  | .deliver => "deliver"
  | .ext k => k

def parseAction (j : Json) : P Act := do
  match ← str (← field j "op") with
  | "call" => pure (.call (toolId (← str (← field j "tool"))) ((optField j "args").getD .null))
  | "query" => pure (.query (← str (← field j "q")))
  | "write" => pure (.write ((optField j "payload").getD .null))
  | "delegate" => pure (.delegate (← str (← field j "role")) ((optField j "task").getD .null))
  | "report" => pure (.report ((optField j "payload").getD .null))
  | "receive" => pure (.receive (← (← field j "child").getNat?))
  | op => throw s!"bad op '{op}'"

def parseAgent (j : Json) : P (AgentId String) := do
  let sid ← str (← field j "session")
  let path ← match optField j "path" with
    | none => pure []
    | some p => do (← list p).mapM (·.getNat?)
  pure (sid, path)

def actionName : Act → String
  | .call k _ => "call:" ++ toolName k
  | .query _ => "query"
  | .write _ => "write"
  | .delegate _ _ => "delegate"
  | .report _ => "report"
  | .receive _ => "receive"

/-- Toy relevance: number of whitespace-separated tokens of the query that also occur as tokens of
the payload text (a string payload itself, otherwise its compact JSON). -/
def tokens (s : String) : List String :=
  (s.split Char.isWhitespace).toList.map (·.toString) |>.filter (· ≠ "")

def payloadText : Json → String
  | .str s => s
  | j => j.compress

def score (q : String) (p : Json) : Nat :=
  let pt := tokens (payloadText p)
  (tokens q).foldl (fun n t => if t ∈ pt then n + 1 else n) 0

structure Scenario where
  cfg : Cfg
  D : Dat
  trace : List (AgentId String × Act)

def parseScenario (j : Json) : P Scenario := do
  let sessJ ← list (← field j "sessions")
  let sess ← sessJ.mapM fun s => do
    let sid ← str (← field s "sid")
    let tenant ← str (← field s "tenant")
    let user ← str (← field s "user")
    let role := (optField s "role").bind (·.getStr?.toOption) |>.getD "default"
    pure ((sid, (⟨tenant, user⟩ : Principal String String)), ((tenant, user), role))
  let tools ← match optField j "tools" with
    | none => pure []
    | some (.obj o) => o.toList.mapM fun (k, v) => do
        let obs ← strList (← field v "observers")
        let nt := ((optField v "needsTrusted").bind (·.getBool?.toOption)).getD false
        let res ← match optField v "result" with
          | none => pure none
          | some l => some <$> parseLabel l
        pure (k, (⟨obs.eraseDups, nt, res⟩ : ToolInfo String))
    | some _ => throw "tools: object expected"
  let results : List (String × Json) := match optField j "toolResults" with
    | some (.obj o) => o.toList
    | _ => []
  -- "cedar": "allow_all" (default) or {"allow": [{"role": r, "action": a}, ...]}
  let allowed : Option (List (String × String)) ← match optField j "cedar" with
    | none => pure none
    | some (.str "allow_all") => pure none
    | some c => do
        let rs ← list (← field c "allow")
        some <$> rs.mapM fun r => do pure (← str (← field r "role"), ← str (← field r "action"))
  let index ← match optField j "index" with
    | none => pure []
    | some a => do (← list a).mapM fun d => do
        pure (⟨← parseLabel (← field d "label"), (optField d "payload").getD .null⟩ :
          Doc String Json)
  let topK := ((optField j "topK").bind (·.getNat?.toOption)).getD 3
  let trace ← do (← list (← field j "trace")).mapM fun st => do
    pure (← parseAgent (← field st "agent"), ← parseAction (← field st "action"))
  let userRole : List ((String × String) × String) := sess.map (·.2)
  let cfg : Cfg :=
    { sessions := sess.map (·.1)
      extReg := tools
      principalRole := fun p => (userRole.lookup (p.tenant, p.user)).getD "default"
      mkRequest := fun r a => ⟨r, actionName a⟩
      authorize := fun r => match allowed with
        | none => true
        | some l => decide ((r.role, r.action) ∈ l)
      score := score
      topK := topK }
  let D : Dat :=
    { tool := fun k _ => (results.lookup k).getD .null
      index₀ := index
      prompt := fun _ => .null }
  pure ⟨cfg, D, trace⟩

/-! ### Serialisation -/

def jstrs (l : List String) : Json := Json.arr (l.toArray.map Json.str)

def labelJson (l : Lbl) : Json :=
  Json.mkObj [("owners", jstrs (l.owners.toArray.qsort (· < ·)).toList),
              ("integrity", Json.str (match l.integ with | .trusted => "trusted" | .untrusted => "untrusted"))]

def agentJson (a : AgentId String) : Json :=
  Json.mkObj [("session", Json.str a.1), ("path", Json.arr (a.2.toArray.map Lean.toJson))]

def respJson : Response Json → Json
  | .payload v => Json.mkObj [("kind", "payload"), ("value", v)]
  | .payloads vs => Json.mkObj [("kind", "payloads"), ("values", Json.arr vs.toArray)]
  | .child n => Json.mkObj [("kind", "child"), ("n", Lean.toJson n)]
  | .ok => Json.mkObj [("kind", "ok")]
  | .denied r => Json.mkObj [("kind", "denied"), ("reason", Json.str r)]

def stateJson (s : St) : Json :=
  let agents := s.agents.toArray.qsort (fun a b => a.1.1 < b.1.1 || (a.1.1 == b.1.1 && a.1.2 < b.1.2))
  Json.mkObj
    [("agents", Json.arr (agents.map fun (a, σ) => Json.mkObj
        [("agent", agentJson a), ("ctx", labelJson σ.ctx), ("role", Json.str σ.cedarP),
         ("nextChild", Lean.toJson σ.nextChild), ("outbox", Json.arr σ.outbox.toArray),
         ("parent", match σ.parent with | none => Json.null | some p => agentJson p)])),
     ("index", Json.arr (s.index.toArray.map fun d =>
        Json.mkObj [("label", labelJson d.label), ("payload", d.payload)])),
     ("events", Json.arr (s.events.toArray.map fun e =>
        Json.mkObj [("tenant", Json.str e.tenant), ("tool", Json.str (toolName e.tool)),
                    ("args", e.args), ("label", labelJson e.label)]))]

def run (sc : Scenario) : Json := Id.run do
  let mut s := init sc.cfg sc.D
  let mut out : Array Json := #[]
  for (a, act) in sc.trace do
    let (r, s') := step sc.cfg sc.D s a act
    s := s'
    let ctx := match assocFind a s.agents with
      | some σ => labelJson σ.ctx
      | none => Json.null
    out := out.push (Json.mkObj
      [("agent", agentJson a), ("response", respJson r), ("denied", Json.bool r.isDenied),
       ("ctx", ctx)])
  return Json.mkObj [("decisions", Json.arr out), ("final", stateJson s)]

end Oracle

def main : IO UInt32 := do
  let input ← (← IO.getStdin).readToEnd
  match Json.parse input >>= Oracle.parseScenario with
  | .ok sc =>
    IO.println (Oracle.run sc).compress
    pure 0
  | .error e =>
    IO.println (Json.mkObj [("error", Json.str e)]).compress
    pure 1
