# TASKS

Status values: `open`, `in progress`, `done`, `blocked`.
Rules for working on tasks: see `CLAUDE.md`, section 3. One task per session.

## Budget gates (Fable only, total budget 60 USD)

| Gate | Condition | Fallback if missed |
|---|---|---|
| G1 | F1a + F1b done with ≤ 25 USD spent | Simplify the model: exactly two tenants, no delegation, (b) only for adapter writes. Then retry F1b once. |
| G2 | F2 done with ≤ 45 USD spent | Weaken (c) to noninterference of RAG query results only (single query step, not whole traces), or drop (c) and go to F3. |
| Hard stop | No new FABLE task above 55 USD spent | Remaining budget is reserve for fixes found by differential testing. |

## Tasks

| ID | Tag | Depends on | Status | Title |
|---|---|---|---|---|
| S0 | [SONNET] | – | open | Repository setup |
| O1 | [OPUS] | S0 | open | Draft the formal spec |
| F0 | [FABLE] | O1 | open | Adversarial spec review, final theorem statements |
| F1a | [FABLE] | F0 | open | Lean model + executable monitor + theorem (a) isolation |
| F1b | [FABLE] | F1a | open | Theorem (b) no label forgery / no laundering |
| S1 | [SONNET] | F1a | open | Lean oracle executable |
| S2 | [SONNET] | F1a | open | Python package: adapter, monitor, Cedar per-call check |
| S3 | [SONNET] | S1, S2 | open | Differential testing Python ↔ Lean oracle |
| F2 | [FABLE] | F1b | open | Theorem (c) noninterference for the shared RAG index |
| F3 | [FABLE] | F2 (or G2 fallback) | open | Theorem (d) refinement: executable monitor implements the model |
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

### F1a [FABLE] Lean model + executable monitor + theorem (a)
- `Model/`: abstract relational semantics (inductive step relation, agent chooses any action).
- `Exec/`: computable monitor (`step : State → Action → Decision × State`) over concrete data structures,
  designed so that F3 can prove refinement and S1 can call it from `main`.
- Prove (a) isolation. DoD per `CLAUDE.md` section 5. Budget target: 8–12 USD.

### F1b [FABLE] Theorem (b) no label forgery / no laundering
- Labels depend only on trusted metadata (session principal, source registry) and input labels, never on payload
  content (including payload fields that look like labels); output labels are at least as restrictive as the join
  of the input labels. Budget target: 7–10 USD. **Check G1 afterwards.**

### S1 [SONNET] Lean oracle executable
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
- Two initial states that differ only in tenant-A data: everything delivered to tenant-B principals is identical
  (termination-insensitive; side channels excluded). Budget target: 15–20 USD. **Check G2 afterwards.**

### F3 [FABLE] Theorem (d) refinement
- Abstraction function from `Exec` state to `Model` state; every accepted exec step corresponds to an abstract
  step, every rejected one has none. Budget target: 8–10 USD, hard cap.

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
