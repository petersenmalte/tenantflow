# Oracle JSON format (`lake exe oracle`)

`cd lean && lake exe oracle < scenario.json` runs `TenantFlow.Exec.step` on a trace and prints one line of JSON.
Instantiation: tenants, users, sessions, roles, tools, queries are strings; payloads are arbitrary JSON (never inspected,
except by the toy `score`). Exit code 0 on success; on a parse error the output is `{"error": "..."}` and the exit code 1.

## Input

```json
{
  "sessions": [{"sid": "1", "tenant": "bank", "user": "u1", "role": "r"}],
  "tools": {"<ext tool>": {"observers": ["bank"], "needsTrusted": false,
                           "result": {"owners": ["bank"], "integrity": "trusted"}}},
  "toolResults": {"<ext tool>": <json>},
  "cedar": "allow_all" | {"allow": [{"role": "r", "action": "call:deliver"}]},
  "topK": 3,
  "index": [{"label": {"owners": ["bank"], "integrity": "trusted"}, "payload": <json>}],
  "trace": [{"agent": {"session": "1", "path": []}, "action": <action>}]
}
```

* `role` (default `"default"`) is the Cedar role of the principal `(tenant, user)`.
* `tools`: registry of external tools. `result` is `null`/absent for "result discarded". The built-in tool `deliver`
  (observers = the caller's tenant, no result) is reserved; ext tools must not be named `deliver`.
* `toolResults`: constant payload returned by an ext tool (default `null`); the argument is ignored.
* `cedar`: stand-in for the opaque per-call authorizer. `allow_all` (default), or an allow-list of
  `(role, action name)`; everything else is denied. Action names: `call:<tool>`, `query`, `write`, `delegate`,
  `report`, `receive`.
* `topK` (default 3), `index` (initial docs, default empty).
* Agent: `{"session": sid, "path": [n, ...]}`; root agent has `path: []`, the n-th child of `a` is `a.path ++ [n]`.
* Actions (`op`):
  `{"op":"call","tool":"deliver"|<ext>,"args":<json>}`, `{"op":"query","q":"<text>"}`, `{"op":"write","payload":<json>}`,
  `{"op":"delegate","role":"<role>","task":<json>}`, `{"op":"report","payload":<json>}`, `{"op":"receive","child":n}`.
* Toy embedding `score q p` (must be ported exactly): number of whitespace-separated tokens of `q` that occur among the
  whitespace-separated tokens of the payload text (payload if it is a JSON string, else its compact serialisation).
  `rank` = stable sort by score descending, then `take topK` (all docs readable by the tenant are ranked, score 0 included).

## Output

```json
{"decisions": [{"agent": {...}, "response": {"kind": "payload", "value": <json>}, "denied": false,
                "ctx": {"owners": ["bank"], "integrity": "trusted"}}],
 "final": {"agents": [...], "index": [...], "events": [...]}}
```

* `response.kind` ∈ `payload` (`value`), `payloads` (`values`), `child` (`n`), `ok`, `denied` (`reason`).
  Compare `kind` and `denied`; `reason` is informational (model collapses reasons, spec §7.5).
* `ctx`: context label of the acting agent after the step (`null` for an unknown agent).
* Labels: `owners` sorted ascending (sets), `integrity` ∈ `trusted|untrusted`.
* `final.agents` sorted by `(session, path)`: `agent`, `ctx`, `role`, `nextChild`, `outbox`, `parent`.
  `final.index`: docs in order. `final.events`: `tenant`, `tool`, `args`, `label` in order.

Tests: `lean/Oracle/tests/t*.json` with `*.expected.out`; run `lean/Oracle/tests/run.sh` (`--update` to regenerate).
