# TASKS

Status values: `open`, `in progress`, `done`, `blocked`.
Rules for working on tasks: see `CLAUDE.md`, section 3. One task per session.

## Budget gates (Fable only, total budget 60 USD)

| Gate | Condition | Fallback if missed |
|---|---|---|
| G1 | F1a + F1b done with ≤ 25 USD spent | Simplify the model: exactly two tenants, drop delegation (`delegate`/`report`/`receive`), restrict (b2) to index docs and events. Then retry F1b once. |
| G2 | F2 done with ≤ 45 USD spent | Weaken (c) to noninterference of RAG query results only (single query step, not whole traces), or drop (c) and go to F3. |
| Hard stop | No new FABLE task above 55 USD spent | Remaining budget is reserve for fixes found by differential testing. |

## Tasks

| ID | Tag | Depends on | Status | Title |
|---|---|---|---|---|
| S0 | [SONNET] | – | done | Repository setup |
| O1 | [OPUS] | S0 | done | Draft the formal spec |
| F0 | [FABLE] | O1 | done | Adversarial spec review, final theorem statements |
| S0b | [SONNET] | S0 | done | Lean toolchain for cloud sessions (SessionStart hook / setup script) |
| F1a | [FABLE] | F0, S0b | done | Lean model + executable monitor + theorem (a) isolation |
| F1b | [FABLE] | F1a | done | Theorem (b) no label forgery / no laundering |
| S1 | [SONNET] | F1a | done | Lean oracle executable |
| S2 | [SONNET] | F1a | done | Python package: adapter, monitor, Cedar per-call check |
| S3 | [SONNET] | S1, S2 | done | Differential testing Python ↔ Lean oracle |
| F2 | [FABLE] | F1b | done | Theorem (c) noninterference for the shared RAG index |
| F3 | [FABLE] | F2 (or G2 fallback) | done | Theorem (d) refinement: executable monitor implements the model |
| F4 | [FABLE] | F3, S1 | done | Lift (c) to `Exec` traces: `Exec.run`, `obs` commutes with `α` (`Exec.noninterference`) |
| S4 | [SONNET] | S2 | done | Baselines: none, Cedar-only, FIDES middleware |
| S5 | [SONNET] | S3, S4 | done | Benchmark suites, adversarial fuzzing agent, latency, plots |
| S6 | [SONNET] | S5 | open | OPTIONAL – small real-LLM utility run (ask user first, costs API money) |
| S7 | [SONNET] | S3 | done | CLI `tenantflow check` (CI mode with counterexamples) |
| S8 | [SONNET] | S1, S3 | done | GitHub Actions CI |
| S9 | [SONNET] | S5 | done | Quarto slide deck |
| S10 | [SONNET] | S3, S5 | done | Browser game "Leak the Vault" |
| O2 | [OPUS] | all above | open | Final review: claims vs. proofs, README, limitations |
| S11 | [SONNET] | O2 | open | Integrate deck and game into petersenmalte.de |
| S12 | [SONNET] | F4 | open | Cite `Exec.noninterference` in deck, README and game; drop "F4 open" from the limitations slide |
| S13 | [SONNET] | S8 | done | CI never ran on GitHub: find the cause, add `workflow_dispatch`, get a first green run |
| S14 | [SONNET] | – | done | Root README states "nothing proven yet": replace with the current state (polish stays in O2) |
| S15 | [SONNET] | – | open | APIsec article never read (403): user reads it, verify our forgery cases and citations against it |
| S16 | [SONNET] | S10 | done | Randomised differential test JS game monitor ↔ Lean oracle (as S3 for Python) |
| S17 | [SONNET] | S9 | open | Deck: navigation bug (only slide 1 reachable), redesign: interactive, staged, intuitive |
| S18 | [SONNET] | S10, S16 | done | Game: redesign: intuitive, guided, animated; verify in a real browser |
| S19 | [SONNET] | S5 | open | Benchmark: rerun on a clean commit; report monitor-only latency separately from Cedar |
| S20 | [SONNET] | S2 | open | Decide/close S2 gaps: Cedar schema via cedar-for-agents generator, gateway as real MCP |
| S21 | [SONNET] | – | open | `.gitignore`: dangling comment "Personal German user guide" without a pattern |
| F5 | [FABLE] | F3 | deferred (user: budget goes to F6 + F7) | (b1) on `Exec`: decisions and labels are independent of payload content (forgery claim at code level) |
| F6 | [FABLE] | F3 | open | Transparency (utility) theorem: single-tenant trusted workflows are never denied by the flow monitor |
| F7 | [FABLE] | S17, S18, F6 | open | Claim review: every statement in deck, game and README is covered exactly by a theorem (≈ 2–3 USD) |

---

### S0 [SONNET] Repository setup
- Create the layout from `CLAUDE.md` section 6.
- `lean/`: Lake project named `TenantFlow` **without Mathlib** (add it later only if a FABLE task asks for it).
  Empty modules `TenantFlow/Model.lean`, `TenantFlow/Exec.lean`, `TenantFlow/Proofs.lean` so that `lake build` passes.
- `python/`: uv project, package `tenantflow`, pytest, ruff, one trivial test.
- `.gitignore` (Lean `.lake/`, Python, Node, `.env`), MIT license, short README stub ("work in progress").
- Empty `docs/spec.md`, `docs/handoff.md`, `docs/proof-status.md`, `docs/discrepancies.md` (keep `docs/project-brief.md` and `docs/fable-budget.md` as they are).
- `git init`, first commit, `gh repo create tenantflow --public --source=. --remote=origin --push`.
- DoD: repo on GitHub, `lake build` and `uv run pytest -q` pass.

### O1 [OPUS] Draft the formal spec
- Write `docs/spec.md` from `docs/project-brief.md`: threat model, system model (principals, labels, sessions,
  trusted adapter, shared RAG index, agent actions, delegation), monitor rules, theorem statements (a)–(d) in
  precise mathematical prose plus a Lean signature sketch, assumptions, non-goals, changelog section.
- State explicitly: isolation comes from the flow monitor; Cedar is an opaque per-call authorizer;
  no theorem about Cedar itself is claimed.
- Write `docs/related-work.md` (one paragraph per item in the brief, with links).
- Do not write Lean code. DoD: both files committed.

### F0 [FABLE] Adversarial spec review
- Attack every theorem statement in `docs/spec.md`: Is it vacuous? Does it follow directly from a definition?
  Does an assumption do the real work? Is the agent really modelled as arbitrary/adversarial?
  Is the noninterference statement well-formed for a nondeterministic agent (see LLMbda's TIPNI as reference)?
- Rewrite the statements so that each says something non-trivial; record changes in the spec changelog.
- Write `docs/spec-review.md` (findings, decisions). Optional: Lean signatures with `sorry`, only if cheap.
- Budget target: 3–5 USD.

### S0b [SONNET] Lean toolchain for cloud sessions
- In the F0 cloud session `lake`/`elan` were not installed, so `lake build` cannot run. Add a SessionStart hook
  (skill `session-start-hook`) or setup script that installs elan and the toolchain pinned in `lean/lean-toolchain`
  (v4.34.1) and runs `lake build` once so the cache is warm. Verify `cd lean && lake build` passes in a fresh session.
- Do not touch `Model/`, `Exec/`, `Proofs/`.

### F1a [FABLE] Lean model + executable monitor + theorem (a)
- Follow `docs/spec.md` v0.2 exactly: six actions (`call, query, write, delegate, report, receive`), tool registry
  `(observers, needsTrusted, result)`, `rank_mem`, `GState` ghost layer with `ghost_proj`/`ghost_lift`,
  lemmas `Step.det`/`Step.total`, sanity examples §7.7 (1–7). Read `docs/spec-review.md` §C first.
- `Model/`: abstract relational semantics (inductive step relation, agent chooses any action).
- `Exec/`: computable monitor (`step : State → Action → Decision × State`) over concrete data structures,
  designed so that F3 can prove refinement and S1 can call it from `main`.
- Prove (a) isolation. DoD per `CLAUDE.md` section 5. Budget target: 8–12 USD.

### F1b [FABLE] Theorem (b) no label forgery / no laundering
- (b) = (b2) of `docs/spec.md` §7.3 on `GState`: every object's label dominates the join of the registry labels of
  its origins, `ctx` monotone, child `ctx` = parent `ctx` at creation. (b1) only as an `Exec` lemma and only if it
  costs ≤ 1 USD (design rule D8 is the primary guarantee). Budget target: 7–10 USD. **Check G1 afterwards.**
- Done: `no_launder`, `ctx_mono`, `ctx_mono_ghost`, `child_ctx_eq`, helper invariant `Fresh` (`lean/TenantFlow/Proofs.lean`);
  (b1) dropped per spec §7.3 cost rule. Axioms in `docs/proof-status.md`.

### S1 [SONNET] Lean oracle executable
- Use `TenantFlow.Exec.step`/`Exec.runTrace` (polymorphic in `Pay`; instantiate `Pay := Lean.Json`, `Qry := String`,
  `Req` as a small request record). `Exec.Config` holds `sessions`/`extReg` as association lists, `score : Qry → Pay → Nat`
  and `topK`. Owner lists are unsorted sets: sort them when serialising. `Exec.Response.denied` carries a reason string.
  Sanity examples in `lean/TenantFlow/Proofs.lean` (namespace `Exec.Sanity`) show how to build a config and a trace.
- Since F3, `Exec` uses the model's `AgentId`/`childId` (`TenantFlow.Model.childId`), and `sortByScore` is generic in the
  element type; `Exec.step`/`runTrace` are unchanged. The oracle must implement exactly `Exec.step` (theorem (d) covers it).
- Actions and registry format follow `docs/spec.md` v0.2 §4.1/§4.4 (`call k args` with `observers`, `needsTrusted`,
  `result`; no separate read/send).
- `lean/Oracle/Main.lean`, `lake exe oracle`: reads a JSON trace (list of actions + initial state) from stdin,
  runs `Exec.step`, prints decisions and resulting labels as JSON. JSON format documented in `docs/oracle-format.md`.
- Do not touch `Model/`, `Exec/`, `Proofs/`. Tests with 5 hand-written traces.

### S2 [SONNET] Python package
- `tenantflow.adapter`: in-memory RAG index with a deterministic toy embedding; labels set from the session at write,
  server-side filtering at query.
- `tenantflow.monitor`: Python port of `Exec.step` (same JSON format as the oracle).
- `tenantflow.cedar`: per-call authorization with Cedar Python bindings (e.g. `cedarpy`); schema generated with the
  generator from `cedar-policy/cedar-for-agents` where possible. Document what was used.
- `tenantflow.gateway`: MCP proxy that combines Cedar check + monitor (minimal, one example MCP server).
- Unit tests.

### S3 [SONNET] Differential testing
- Hypothesis generates random and adversarial traces, runs Python monitor and `lake exe oracle`, compares.
- Counterexamples are minimized and stored in `docs/discrepancies.md` (see `CLAUDE.md` 3.3).

### F2 [FABLE] Theorem (c) noninterference
- Statement and low-equivalence as in `docs/spec.md` §7.4; use the simulation relation sketched there, including
  clause (iii) "clean-and-identical or absent-or-tainted". Budget target: 15–20 USD. **Check G2 afterwards.**
- Done: `Model.noninterference` in `lean/TenantFlow/Proofs/Noninterference.lean` (strategies, schedule, `run`, `LowEq`,
  `obs`, relation `Sim` with the strengthened clauses (iii)/(iv), see spec changelog "F2 details"); no sorry; axioms in
  `docs/proof-status.md`. G2: user fills in the spend after this session in `docs/fable-budget.md`.

### F3 [FABLE] Theorem (d) refinement
- (d1) forward simulation with denial reasons collapsed by `⌊·⌋`, (d2) initial states agree (`docs/spec.md` §7.5);
  "rejected ⇒ no abstract step" is a corollary of `Step.det`. Budget target: 8–10 USD, hard cap.
- Done: `lean/TenantFlow/Proofs/Refinement.lean` (`Exec.refines`, `Exec.refines_init`, `Exec.refines_denied`,
  `Exec.refines_trace`, `Exec.refines_ghost`). See `docs/spec.md` changelog "F3 details".

### F4 [FABLE] (optional) Noninterference for `Exec` traces
- Define `Exec.run` (the executable counterpart of `Model.run` in `Proofs/Noninterference.lean`, driven by the same
  `Strategy`/schedule), show `Exec.obs` commutes with `α` and `α (Exec.run …) = Model.run …`; then (c) transfers.
- Only if the Fable budget allows after S-tasks are green; the deck can cite (d) + (c) on the model without it.
- Done (2026-10-11): `lean/TenantFlow/Proofs/NoninterferenceExec.lean` – `Exec.run`, `run_abs`, `obs_abs`,
  `Exec.noninterference` (observable events agree up to `α`; strategies are reason-blind as in the model; low
  equivalence stated on the abstractions). Details in the `docs/spec.md` changelog and `docs/proof-status.md`.

### S12 [SONNET] Cite theorem (c) for `Exec` traces (after F4)
- F4 proved `Exec.noninterference` in `lean/TenantFlow/Proofs/NoninterferenceExec.lean`: for data low-equivalent after
  abstraction, the `B`-observable events of `Exec.run` agree up to `α` (tenant, tool, arguments, label-as-set).
  Strategies are reason-blind (histories hold `⌊r⌋`), exactly as in the model.
- `web/deck/index.qmd`: line "(c) noninterference for the shared index (on the model)" → also for `Exec` traces via
  `Exec.noninterference`; remove "(c) for `Exec` traces (optional task F4, open)" from the "Not covered" slide and
  state the remaining assumption instead (strategies do not see denial reasons). Check README and the game's "Why?"
  panel (`web/game/rules.js`) for the same wording. Statement and axioms: `docs/spec.md` changelog (F4 row),
  `docs/proof-status.md`. No numbers change; do not touch `lean/`.
- Should be done before O2 so the final review sees the final wording.

### Rework found in the Opus inventory (2026-10-11)
Sonnet ran S0–S10 at medium effort; the inventory found gaps that are tracked here. The user authorised Opus to work
on these SONNET tasks in this session. F4 ran in parallel; none of these tasks touch `lean/`.

### S13 [SONNET] CI never ran
- `gh api repos/petersenmalte/tenantflow/actions/runs` → `total_count: 0` after ≥ 6 pushes since S8, workflow `ci` is
  `active`, Actions enabled. Every "CI checks X" statement is unbacked until a run is green.
- Find the cause (repo/account settings, billing, workflow syntax), add `workflow_dispatch`, fix failing jobs.
- Done (Opus): runs exist from `e5f6ec8` on and are green (jobs lean, python, game, deck; 44 theorem names checked
  by `#print axioms`; 5 oracle traces; differential test with 100 examples). Cause of the missing earlier runs not
  found (no settings change by Claude). `workflow_dispatch` added. Remaining skip in CI: the FIDES cross-check
  (`agent-framework-core` extra not installed in CI), documented here.

### S14 [SONNET] Root README is wrong
- `README.md` still says "Work in progress … Nothing in this repository is claimed to be proven yet." Replace it with
  a short, correct state (theorems with names, assumptions, links to game/deck/bench). Full polish in O2.

### S15 [SONNET] APIsec analysis not read
- The article returned HTTP 403 in S4; it is still cited in `docs/related-work.md`, `bench/README.md`, the deck.
  The user reads it in a browser; check that suite 2 (forgery) and the FIDES re-implementation match what it
  describes, and fix or qualify the citations. CLAUDE.md §8.

### S16 [SONNET] Differential test JS ↔ oracle
- S10 tested the JS monitor on only 9 traces (5 hand-written, 4 level scripts). Add a randomised corpus: generate
  ≥ 300 scenarios (reuse the Hypothesis strategies of `python/tests/test_differential.py`), store oracle outputs as
  fixtures (or run the oracle in CI), compare the JS monitor on all of them; also the 3 baselines vs Python.
- Done (Opus): `web/game/scripts/gen_corpus.py` → `tests/fixtures/corpus.json.gz` (2900 scenarios, 18 746 steps,
  derandomised); `tests/corpus.test.js` compares all four JS modes (TenantFlow vs oracle, baselines vs Python), all
  agree. Finding: the S3 generator sends ~60 % of steps to unknown agents, so flow denials were rare; added
  `scenarios_valid` (existing agents, mostly allow_all) and `test_python_matches_oracle_valid_agents` to
  `python/tests/test_differential.py`. Flow denials "tainted write" and "requires trusted" are still rare (≈ 10 each).

### S17 [SONNET] Deck rework
- Bug: `####` headings inside `.zone` divs become nested sections (22 `<section>`s instead of 11), so only the first
  slide is reachable.
- Redesign (user feedback): far too static and not intuitive. Follow the style reference (one concept per slide,
  concrete example before abstraction, staged builds), chips that visibly move, the join drawn as two chips,
  Lean statement marked as abridged or extracted, use the benchmark plots. Inspect every slide in a browser.

### Target picture for S17/S18 (user decisions, 2026-10-11)
- Game: **drag & drop**. Data chips (bank blue, insurer gold, untrusted red dashed) are dragged between agents, the
  shared index and tools; every move is checked immediately by the real JS monitor and animated (passes / bounces
  back), with the reason at the chip. Must also work without a mouse (keyboard / tap).
- Audience: **both, layered**: simple surface that a recruiter understands in two minutes, precise details
  (theorem names, assumptions, denial reasons) on demand.
- Deck: Quarto/reveal.js stays, but slides 3–5 embed **live widgets** running the real JS monitor (click a step,
  the chip moves; switch the protection mode on the slide).
- Fable budget (~14 USD): F6 transparency theorem, then F7 claim review after S17/S18. F5 deferred.

### S18 [SONNET] Game rework
- User feedback: far from the target picture; must be much more intuitive, guided and interactive, less static.
  Visible chips that move between agents/index/tools, one clear goal per level, immediate feedback, the "Warum?"
  panel as in the brief. Lean links with file + line anchors (`noninterference` lives in another file).
  Check in a real browser (layout, dark mode, phone width, keyboard).
- Done (Opus): rebuilt as a drag & drop board (`src/play.js` logic, `src/board.js` view, `src/game.js` shell), result
  card comparing all four modes, two-layer explanations, Lean line links (`src/theorems.js`), sandbox replays the
  fuzzer's counterexample on the board. 67 JS tests. Checked in headless Chrome via CDP (1280 px, 390 px, dark mode,
  real mouse drag). Limits in `web/game/README.md` (no screen-reader / real-touch test).

### S19 [SONNET] Benchmark provenance and latency
- `results.json` has `meta.git = 4775e8a` (S4) but was produced by uncommitted S5 code; S7 moved `violations`
  afterwards. Rerun on a clean commit and regenerate the deck variables.
- Latency mean (99 µs) < median (169 µs): ~40 % of decisions exit before Cedar. Report the monitor alone (without
  Cedar) separately, so "the monitor adds no measurable cost" is measured, not inferred.

### S20 [SONNET] S2 gaps
- Cedar schema is hand-written (task asked for the cedar-for-agents generator where possible); the gateway is a
  JSON-RPC proxy without the MCP SDK. Either close the gaps or state the decision and reason in `python/README.md`.

### F7 [FABLE] Claim review of deck, game and README
- After S17/S18 (and F6): check every sentence that states a guarantee against the Lean statements and the spec
  assumptions; flag vacuous, overstated or uncovered claims; fix wording in the spec changelog if needed and list the
  required text changes as a `[SONNET]` task. Budget ≈ 2–3 USD.

### S21 [SONNET] `.gitignore`
- Comment "Personal German user guide, not part of the public repository" has no pattern. Ask the user which file
  is meant (`GUIDE.md` is tracked on purpose as the English operator guide).

### F5 [FABLE] (b1) payload independence on `Exec`
- Dropped in F1b by the cost rule. Statement: two `Exec` states/actions that differ only in payloads give the same
  decision (⌊r⌋) and the same labels. Backs "labels in data are ignored" at code level (deck slide 5, game level 3).
  Budget target ≤ 5 USD.

### F6 [FABLE] Transparency (utility) theorem
- The spec claims only safety; utility is measured (suite 3). State and prove: if every origin an agent may depend
  on is owned by its own tenant and trusted, the monitor never denies an action for a flow reason (only Cedar, unknown
  agent/tool, report/receive preconditions can). Gives the deck a proven counterpart to "TenantFlow keeps utility".
  Spec changelog entry required. Budget target ≤ 8 USD.

### S4 [SONNET] Baselines
- `none` (no protection), `cedar-only`, `fides`: the label middleware of Microsoft Agent Framework (pin a version in
  which the published label-forgery behaviour reproduces); if not installable, a faithful re-implementation, clearly
  labelled as such, with the reason in `bench/README.md`.

### S5 [SONNET] Benchmark
- Suites: (1) cross-tenant leaks through call sequences over the shared RAG index, each call Cedar-allowed;
  (2) label forgery; (3) legitimate workflows (utility).
- Adversarial fuzzing agent (no LLM). Metrics: attack success rate, utility, latency per decision.
- Results as JSON in `bench/results/`, plots generated from them. No hand-made numbers.

### S6 [SONNET] OPTIONAL real-LLM utility run
- Ask the user before spending any API money. Small run with Haiku or Sonnet on suite (3).

### S7 [SONNET] CLI `tenantflow check`
- Input: Cedar policies + tool list + adapter config. Searches for an allowed call sequence that leaks across tenants;
  prints the counterexample or "no leak in the model". Example GitHub Action in the README.

### S8 [SONNET] CI
- GitHub Actions: `lake build`, check that `Proofs/` contains no `sorry`, pytest, differential tests (small sample),
  JS tests of the game monitor.
- The `sorry` check must cover `lean/TenantFlow/Proofs.lean` **and** `lean/TenantFlow/Proofs/**` (F2 added
  `Proofs/Noninterference.lean`). Also run `#print axioms` for the theorems listed in `docs/proof-status.md` and fail on
  anything but `propext`, `Classical.choice`, `Quot.sound`.

### S9 [SONNET] Quarto slide deck
- Style reference: https://ai.katestange.net/ai/course/llm-course/slides/from-tokens-to-transformers/
- Outline and colour convention: `docs/project-brief.md`, section "Presentation". Numbers only from `bench/results/`.

### S10 [SONNET] Browser game "Leak the Vault"
- Levels 1–5 from the brief, protection switch (off / Cedar / FIDES / TenantFlow), "Warum?" panel linking to deck
  slide and Lean theorem. Monitor ported to JS and tested against oracle outputs. Static, no server.

### S9 – done (notes)
- `web/deck/`: `index.qmd` (10 slides + title), `custom.scss`, `scripts/gen_variables.py` (numbers from `bench/results/results.json`
  into `_variables.yml`), `python/tests/test_deck.py`, CI job `deck`. Deviations and limits: `web/deck/README.md`.
- Render fixed by `_quarto.yml` (without it `_variables.yml` is ignored and output goes next to the .qmd); no warnings. Layout and builds still not inspected visually (see README). The game's "Why?" links now use
  `../deck/index.html#/N` (N = content slide).

### S10 – done (notes)
- `web/game/` (static, open `index.html`): `src/monitor.js` (JS port of the monitor + the three baselines), `src/levels.js`,
  `src/rules.js` (goals, seeded fuzzer with shrinking, "Why?" texts), `src/game.js` (UI), `npm test` (41 tests).
- Tests: 5 Lean oracle traces exact; level attacks in all 4 modes vs. `tests/fixtures/expected.json` (generated by
  `scripts/gen_expected.py`, TenantFlow column = `lake exe oracle`). Deck links in "Why?" point to `../deck/index.html#/N`
  following the slide order of the brief; adjust in `rules.js` (`slide(...)`) once S9 exists.
- Level 2 deviates from the brief's wording: the write is allowed, the leak is stopped at the query (label + filter).

### O2 [OPUS] Final review
- Every claim in README, deck and game maps to a proven theorem or a measured result. Limitations and related work
  are visible. README polished for recruiters (5-minute quick start first).

### S11 [SONNET] Website integration
- Add a project page to petersenmalte.de (separate repository; ask the user for its location).

### S2 – done (notes)
- `python/src/tenantflow/{monitor,adapter,cedar,gateway,example_server}.py`, tests in `python/tests/test_monitor.py`.
- `monitor.run_scenario` reads/writes the oracle JSON; matches all 5 hand traces in `lean/Oracle/tests/` (kind/denied/ctx/final).
- Cedar via `cedarpy`; hand-written schema (cedar-for-agents generator not used, documented in `cedar.py`).
- Gateway is a minimal JSON-RPC (`tools/list`, `tools/call`) proxy, no MCP SDK dependency.

### S3 – done (notes)
- `python/tests/test_differential.py`: Hypothesis scenarios (2–3 tenants, ext tools, Cedar allow-lists, delegation trees,
  unknown agents/tools) → Python `run_scenario` vs. `lake exe oracle`; skipped if the oracle binary is not built
  (`TF_ORACLE` overrides the path, `TF_EXAMPLES` the number of examples, default 300).
- One finding, D1 (duplicate session ids), is an input precondition: see `docs/discrepancies.md`. No `[FABLE]` task.

### S4 – done (notes)
- `python/src/tenantflow/baselines.py` (`Baseline.from_monitor(mode, monitor)`, modes `none|cedar-only|fides`), tests in
  `python/tests/test_baselines.py`, rationale and limits in `bench/README.md`.
- FIDES is a re-implementation of the label logic of `agent-framework-core==1.5.0` (optional extra `fides`), because the
  middleware needs a full agent runtime and 1.21.0 is hardened. The APIsec article was not fetchable (403).

### S5 – done (notes)
- `bench/{world,suites,fuzz,run,plot}.py`, results + plots in `bench/results/`, method and caveats in `bench/README.md`,
  harness tests `python/tests/test_bench.py`. Matplotlib is in the dependency group `bench`.
- Headline (seed 1, 2000 episodes): none / Cedar-only / FIDES-1.5.0-logic violate in ~100 % of fuzz episodes and 5/5
  leak scenarios; FIDES blocks only the unlabelled control in suite 2 (3/4 forgery succeed); TenantFlow 0 violations,
  8/8 utility. Latency ~170 µs per decision, all Cedar (cedarpy).

### S7 – done (notes)
- `python/src/tenantflow/{check,cli}.py` (`tenantflow check`, entry point in `pyproject.toml`), `examples/shared-rag.json`,
  tests `python/tests/test_cli.py`, README section with a GitHub Action example. `violations` moved to `tenantflow.check`
  (bench imports it from there).

### S8 – done (notes)
- `.github/workflows/ci.yml`: jobs `lean` (lake build, oracle build, `scripts/check-lean.sh`, oracle traces; uploads the oracle),
  `python` (ruff, pytest incl. differential test with 100 examples via `TF_ORACLE`, small benchmark run), `game` (runs
  `npm ci && npm test` in `web/game` once it has a `package.json`; S10 must provide an `npm test`).
- `scripts/check-lean.sh`: no `sorry`/`admit`/`axiom` in `lean/TenantFlow`, `TenantFlow.lean`, `lean/Oracle`; `#print axioms` for every
  `Model.*`/`Exec.*` name in the "proven"/"defined" rows of `docs/proof-status.md` (unknown names fail, so the doc cannot drift).
