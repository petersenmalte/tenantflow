# TenantFlow – Instructions for Claude Code

Read this file completely at the start of every session. It overrides your defaults.

## 1. Project in one paragraph

TenantFlow enforces tenant isolation for AI agents that share infrastructure (here: one shared RAG index).
Cedar decides each tool call individually; TenantFlow adds an information-flow monitor with tenant labels
that cannot be forged by data (the FIDES label-forgery class). The core is a Lean 4 model with machine-checked
theorems; a Python adapter/gateway, a benchmark, a Quarto slide deck and a browser game build on it.
Full context: `docs/project-brief.md`. Formal spec: `docs/spec.md` (created in task O1).

## 2. Language

- Talk to the user in **German**.
- Everything in the repository (code, comments, commit messages, docs) is **English**.

## 3. Model routing – the most important rule

Three models are used. Each task in `TASKS.md` carries exactly one tag.

| Tag | Model ID | Billing | Use for |
|---|---|---|---|
| `[FABLE]` | `claude-fable-5-1` | **limited budget: 60 USD total** | model design, theorem statements, Lean proofs, spec review |
| `[OPUS]` | `claude-opus-5-5` | subscription | spec drafting, research, final review |
| `[SONNET]` | `claude-sonnet-5-5` | subscription | everything else: setup, Python, JS, tests, CI, benchmark, deck, game, docs |

### 3.1 At the start of every session

1. Determine which model you are from your system information. If you cannot determine it with certainty,
   ask the user and wait. Do nothing else first.
2. Read `TASKS.md`. Take the task the user named. If none was named, take the first task with status `open`
   whose dependencies are `done`.
3. Compare the task tag with your model.
   - **Match** → work on the task.
   - **Mismatch** → do **not** edit files, do **not** run builds or tests. Reply only with the STOP message (3.4).
   - Exception: OPUS may work on a SONNET task if the user explicitly says so in this session.
     FABLE never works on a non-FABLE task, even if asked casually – remind the user of the budget and ask
     for an explicit "ja, trotzdem mit Fable".

### 3.2 While working on a FABLE task

- Do only what needs deep reasoning: designing the model, stating theorems, proving them, restructuring
  definitions so that proofs go through, reviewing the spec for vacuous or trivial statements.
- Everything else (Python, JS, test harnesses, CI, README prose, formatting, renaming, boilerplate) you **do not do**.
  Add it to `TASKS.md` as a new `[SONNET]` task with enough context, then continue with the hard part.
  Allowed exception: minimal glue (≈ 20 lines) that is required for `lake build` to pass.
- As soon as the hard part of the task is done: commit, update `TASKS.md`, write `docs/handoff.md`,
  then STOP (3.4). Do not "also quickly" continue with the next task.
- **Stuck rule:** if three substantially different approaches to the same lemma fail, or you keep looping on
  build errors without progress, stop. Commit the work in progress (`wip:` prefix, remaining `sorry`s listed in
  `docs/handoff.md`), describe what you tried and offer 2–3 options (helper lemma, simpler model, weaker but
  still meaningful statement). Wait for the user's decision.
- **Budget:** at session start read `docs/fable-budget.md`. If the user has not told you the current total
  Fable spend in this session's first message, ask for it and wait. Then check the gates in `TASKS.md`:
  - G1: tasks F1a + F1b done before 25 USD are spent.
  - G2: task F2 done before 45 USD are spent.
  - Hard stop: never start a FABLE task when more than 55 USD are spent; the rest is reserve for fixes.
  If a gate is missed, stop and present the fallback options listed in `TASKS.md`.
- **Keep context small** (every turn resends the context and Fable is expensive):
  read only the files you need; never print full build logs, use `lake build 2>&1 | tail -n 40` or grep
  for `error`; do not reread files you just wrote.

### 3.3 While working on an OPUS or SONNET task

- **Protected files:** never change `lean/TenantFlow/Model/**`, `lean/TenantFlow/Proofs/**` or the theorem
  statements in `docs/spec.md`. They belong to FABLE tasks. If a change seems necessary, stop and add a
  `[FABLE]` task with the reason.
- If the task turns out to need a proof, a change of semantics, or a non-obvious modelling decision,
  stop and add a `[FABLE]` task.
- Never weaken a test to make it pass. If the Python monitor and the Lean oracle disagree:
  first check whether Python is wrong and fix it. If you are not sure, record the counterexample in
  `docs/discrepancies.md` and add a `[FABLE]` task.

### 3.4 STOP message (always exactly this format, in German)

```
STOPP – Modellwechsel nötig.
Nächster Task: <ID> – <Titel> [<TAG>]
1. /model <model-id>
2. /clear
3. Prompt: „Lies CLAUDE.md und TASKS.md und bearbeite Task <ID>.“
   (Bei FABLE-Tasks zusätzlich: „Bisher verbrauchtes Fable-Budget: <X> $.“)
```

If you stopped because of the stuck rule or a missed gate, write `STOPP – Entscheidung nötig.` instead and list the options.

## 4. Git and GitHub

- Remote: GitHub repository `tenantflow`, branch `main`.
- **Commit often:** after every green step – each proven lemma, each passing group of tests, each working
  feature – and at least every ~30 minutes of work. Small commits are preferred.
- Before committing: `lake build` passes (in `lean/`) and `uv run pytest -q` passes (in `python/`, once it exists).
  A commit with `sorry` is only allowed with the `wip:` prefix, and every `sorry` must be listed in `docs/handoff.md`.
- Conventional prefixes: `lean:`, `feat:`, `fix:`, `test:`, `bench:`, `docs:`, `ci:`, `chore:`, `wip:`.
- Run `git push` after every commit.
- Never force-push, never rewrite history, never commit secrets (`.env` is git-ignored), no large binaries.
- At the end of every task: update the status in `TASKS.md` and commit that too.

## 5. Definition of done for a Lean theorem

- No `sorry`, `admit` or new `axiom` in the files involved.
- `#print axioms <theorem>` lists only `propext`, `Classical.choice`, `Quot.sound` (or nothing).
  Record the output in `docs/proof-status.md`.
- The statement matches `docs/spec.md`. If it had to change, the change and its reason are recorded in the
  changelog section of `docs/spec.md` (FABLE only).

## 6. Repository layout

```
lean/                 Lake project
  TenantFlow/Model/   abstract model: labels, principals, store, actions, step relation   (FABLE)
  TenantFlow/Exec/    executable monitor used by the oracle                                 (FABLE)
  TenantFlow/Proofs/  theorems (a)–(d)                                                      (FABLE)
  Oracle/Main.lean    `lake exe oracle`: JSON trace on stdin → decisions on stdout          (SONNET)
python/               package `tenantflow`: adapter, monitor, gateway, cli, baselines
bench/                benchmark suites, fuzzing agent, results, plots
web/deck/             Quarto slide deck
web/game/             static browser game
docs/                 brief, spec, handoff, budget, proof status, discrepancies
```

## 7. Honesty

- Never claim more than is proven. README, deck and game cite theorem names for every guarantee.
- Every guarantee is stated together with its assumptions (trusted adapter, trusted session, no side channels).
- Related work (Cedar, AWS AgentCore Policy, LLMbda, FIDES, APPA, SPA, CaMeL) is cited, not hidden.

## 8. Security and ethics

- The FIDES label-forgery case is reproduced only locally against our own test setup, citing the published
  APIsec Labs analysis. No tests against third-party systems.
- No real customer data; all data in benchmarks and demos is synthetic.
