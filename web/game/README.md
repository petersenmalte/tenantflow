# Leak the Vault

Static browser game (no server, no dependencies): open `index.html`. A bank (blue) and an insurer (gold) share one AI
platform; untrusted data is red and dashed. You play a hijacked agent and try to get the bank's data to the insurer.

**How to play:** drag a tile or a coloured data chip onto a highlighted place (mouse or touch), or click/tap it and then
click the place; with the keyboard, Tab to it, Enter to pick up, Tab to a highlighted place, Enter to drop, Escape to
cancel. Every move runs the real monitor. The chip lands or bounces back with a one-sentence reason; "Why? (details)"
shows the monitor rule, the Lean theorem (with line link) and the slide. Switch the protection between
**Off / Cedar / FIDES / TenantFlow**; after each level a card compares the same attack against all four.

| Level | Move | Lesson |
|---|---|---|
| 1 | vault → insurer agent | Cedar already blocks a direct read |
| 2 | vault → bank agent → index → insurer agent | every step is allowed; TenantFlow keeps the label and filters the search |
| 3 | own ticket (label says "trusted") → Ticket system → Payments | FIDES takes the label from the call's arguments (APIsec PoC conditions); TenantFlow only from the registry |
| 4 | vault → bank agent → helper (role ops) → Insurer inbox | the helper inherits the bank's label |
| 5 | edit the Cedar policy, let a random attacker search | a found leak is replayed step by step on the board |

URL parameters: `?level=1..5&mode=none|cedar-only|fides|tenantflow`.

## Code
`src/monitor.js` (JS port of `Exec.step` + the three baselines), `src/levels.js`, `src/rules.js` (goals, fuzzer,
explanations), `src/play.js` (game logic without DOM: drag moves → monitor actions), `src/board.js` (view: drag & drop,
animation; also used by the deck's live widgets), `src/game.js` (shell), `src/theorems.js` (generated Lean links).

## Tests (`npm test`, Node ≥ 20)
1. The 5 hand-written Lean oracle traces, exact equality.
2. Randomised corpus (`tests/fixtures/corpus.json.gz`, 2400 scenarios from the Hypothesis strategies, with varying FIDES deployments, of
   `python/tests/test_differential.py`): JS TenantFlow vs Lean oracle, JS baselines vs Python baselines.
3. Level scripts in all four modes vs reference outputs; expected win/lose per level and mode.
4. The drag moves of each level (`tests/play.test.js`), the fuzzer, and that every cited theorem exists in `lean/`.

Regenerate after editing levels or `lean/` (needs `cd lean && lake build oracle`):
```
node scripts/dump-scenarios.js && (cd ../../python && uv run python ../web/game/scripts/gen_expected.py)
(cd ../../python && uv run python ../web/game/scripts/gen_corpus.py)
node scripts/gen_theorems.js     # Lean line links; the test only warns when they drift
```

## Deviations and limits
* Modes `none`, `cedar-only`, `fides` are the benchmark baselines; `fides` is a re-implementation of the label logic of
  agent-framework-core 1.5.0, not the Microsoft middleware (see `bench/README.md`). Level 3 runs FIDES under the
  conditions of the APIsec proof of concept (`auto_hide_untrusted` off, the ticket's tool without `source_integrity`);
  with the shipped default the outside reply would be hidden from the agent. The sandbox uses the default.
* Level 2 under TenantFlow: the write is allowed (the entry keeps the bank's label); the leak is stopped at the search.
* Level 5 has no vault tool: a tool that hands bank-labelled data to an insurer principal is a registry error
  (assumption A2), which the monitor does not claim to catch. Bank data lives in the index there.
* The fuzzer is a bounded random search; "nothing found" is not a proof. The guarantee is the Lean theorem, under the
  spec's assumptions (trusted session, adapter and tool registry, complete mediation, stateless tools, Cedar sees only principal and action, agents do not see denial reasons, no side channels incl. data-independent scheduling (A1–A8 in docs/spec.md §9)). That the monitor never reads a label out of a payload is by construction and tested (spec §7.3 (b1), D8), not a theorem.
* The JS monitor is tested, not proven, against the oracle; the oracle is `Exec.step`, which theorem (d) relates to the model.
* Checked in headless Chrome (desktop 1280 px, phone 390 px, dark mode, real mouse drag, click-to-place); not yet checked
  with a screen reader or on a real touch device. The "Why?" panel is called "Why?" (repository language is English).
