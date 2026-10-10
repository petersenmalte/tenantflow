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
| S3 | [SONNET] | S1, S2 | open | Differential testing Python ↔ Lean oracle |
| F2 | [FABLE] | F1b | done | Theorem (c) noninterference for the shared RAG index |
| F3 | [FABLE] | F2 (or G2 fallback) | done | Theorem (d) refinement: executable monitor implements the model |
| F4 | [FABLE] | F3, S1 | open (optional) | Lift (c) to `Exec` traces: `Exec.run`, `obs` commutes with `α` – only if budget allows, not needed for the deck |
| S4 | [SONNET] | S2 | open | Baselines: none, Cedar-only, FIDES middleware |
| S5 | [SONNET] | S3, S4 | open | Benchmark suites, adversarial fuzzing agent, latency, plots |
| S6 | [SONNET] | S5 | open | OPTIONAL – small real-LLM utility run (ask user first, costs API money) |
| S7 | [SONNET] | S3 | open | CLI `tenantflow check` (CI mode with counterexamples) |
| S8 | [SONNET] | S1, S3 | open | GitHub Actions CI |
| S9 | [SONNET] | S5 | open | Quarto slide deck |
| S10 | [SONNET] | S3, S5 | open | Browser game "Leak the Vault" |
| O2 | [OPUS] | all above | open | Final review: claims vs. proofs, README, limitations |
| S11 | [SONNET] | O2 | open | Integrate deck and game into petersenmalte.de |

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
