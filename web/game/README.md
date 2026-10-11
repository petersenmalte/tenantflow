# Leak the Vault

Static browser game (no server, no dependencies): open `index.html`. You play a compromised agent on a platform
that shares one RAG index between a bank (blue) and an insurer (gold); untrusted data is red and dashed.
Protection switch: **Off / Cedar / FIDES / TenantFlow**. The "Why?" panel explains each decision in one sentence and
links the Lean theorem and the deck slide (deck links are placeholders until the deck, task S9, exists).

| Level | Attempt | Lesson |
|---|---|---|
| 1 | read the bank's vault directly | Cedar already blocks this |
| 2 | vault → write to the shared index → query as insurer | every call is Cedar-allowed; TenantFlow labels the document and filters at query |
| 3 | forged `security_label` in fetched data, then `pay` | FIDES accepts the label; TenantFlow takes labels only from the registry |
| 4 | delegate to a sub-agent with role `ops` | the child inherits the parent's label |
| 5 | sandbox: edit a Cedar allow-list, run a seeded random attacker | a leak is shown as a shrunk call sequence |

## Honesty notes
* Modes `none`, `cedar-only`, `fides` are the benchmark baselines (`python/src/tenantflow/baselines.py`); `fides` is a
  re-implementation of the label logic, not the Microsoft middleware (see `bench/README.md`).
* The fuzzer is a bounded random search. "No violation found" is not a proof; for TenantFlow the guarantee is
  `Model.isolation` / `Model.isolation_int` under the assumptions in `docs/spec.md` (trusted session, adapter and
  registry; no side channels). The sandbox has no `vault` tool on purpose: a tool that returns bank-labelled data to an
  insurer principal is a registry error (assumption A2) that the monitor does not claim to catch.
* In level 2 the write step is *allowed* under TenantFlow; the leak is stopped at the query, because the document keeps
  the bank's label.

* Not yet checked in a real browser (layout, dark mode, keyboard use): the UI was smoke-tested with a fake DOM in Node only.

## Tests
`npm test` (Node ≥ 20) checks the JS monitor against
1. the five hand-written Lean oracle traces (`lean/Oracle/tests`), exact equality;
2. the scripted attacks of the levels in all four modes, against `tests/fixtures/expected.json`
   (TenantFlow = output of `lake exe oracle`, the others = Python baselines);
3. the expected outcome of each level, and the fuzzer (finds leaks without TenantFlow, none with it).

Regenerate fixtures after editing `src/levels.js` (needs the built oracle: `cd lean && lake build oracle`):
```
node scripts/dump-scenarios.js && (cd ../../python && uv run python ../web/game/scripts/gen_expected.py)
```
