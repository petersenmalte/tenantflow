# TenantFlow

[![ci](https://github.com/petersenmalte/tenantflow/actions/workflows/ci.yml/badge.svg)](https://github.com/petersenmalte/tenantflow/actions/workflows/ci.yml)

**Tenant isolation for AI agents on shared infrastructure, with machine-checked proofs.**

A bank and an insurer run their AI agents on one platform and search one shared RAG index. A per-call policy
(Cedar) checks each tool call on its own, so three individually allowed calls can still move the bank's data to the
insurer: read it, write it to the shared index, let the insurer search for it. TenantFlow adds an information-flow
monitor with tenant labels that follow the data and cannot be forged by the data. The core is a Lean 4 model with
proofs; a Python gateway (MCP), a benchmark, a slide deck and a browser game build on it.

## Five-minute tour

| Minutes | Do | You see |
|---|---|---|
| 2 | Open `web/game/index.html` in a browser (no server, no install) | Play a hijacked agent; switch protection between Off, Cedar, FIDES and TenantFlow and watch the same attack leak or bounce back |
| 1 | `cd web/deck && quarto render && open _site/index.html` | Ten slides; slides 1–3 and 5 run the real monitor live |
| 1 | `cd python && uv run tenantflow check ../examples/shared-rag.json` | A concrete call sequence that leaks although Cedar allows every call; add `--enforce tenantflow`: no leak in the model |
| 1 | `cd lean && lake build && ../scripts/check-lean.sh` | The proofs check; every theorem uses only the standard axioms |

## What is proven

Lean 4, no `sorry`, axioms per theorem in `docs/proof-status.md`, statements in `docs/spec.md` §7.

| | Guarantee | Lean |
|---|---|---|
| (a) | Nothing that may depend on another tenant's data reaches a tenant's principals or tools | `Model.isolation`, `Model.isolation_int` |
| (b) | Every label dominates the labels of all its sources, integrity included: data cannot lower or launder a label | `Model.no_launder`, `Model.ctx_mono`, `Model.child_ctx_eq` |
| (c) | What tenant B observes depends only on data B may read (for a fixed schedule) | `Model.noninterference`, `Exec.noninterference` |
| (d) | The executable monitor implements the model | `Exec.refines`, `Exec.refines_init` |
| (e) | An agent that depends only on its own tenant's trusted data and calls only tenant-private tools is never denied by the flow checks; only Cedar, an unregistered tool, or a missing session, parent or child can deny it | `Model.transparency`, `Exec.transparency_denied` |

These hold **for every agent behaviour and every Cedar policy**, under the assumptions of `docs/spec.md` §9:
trusted session (A1), correct tool registry (A2), complete mediation (A3), stateless tools (A4), no side channels and a
data-independent schedule (A5), the Python adapter is tested, not proven (A6), Cedar sees only principal and action
(A7), agents see `denied` but not the denial reason (A8). **Nothing is claimed about Cedar itself.**

## What is tested and measured

- **Not proven, tested:** the Python monitor and the game's JavaScript monitor are compared with the Lean oracle
  (`lake exe oracle` = `Exec.step`) on random scenarios: Python with Hypothesis on every CI run, JavaScript on a fixed
  corpus of 2 400 scenarios. That the monitor never reads a label out of a payload holds by construction (the monitor
  is generic in the payload type) and is tested; it is not a theorem.
- **Benchmark** (`bench/`; seed 1, revision `8caa375`, numbers from `bench/results/results.json`; read `bench/README.md` before quoting):

  | | cross-tenant leaks | label forgery | utility | random attacker, any violation |
  |---|---|---|---|---|
  | Cedar only | 5/5 | 5/5 | 8/8 | 99.8 % of 2000 runs |
  | FIDES logic (re-implemented, 1.5.0) | 5/5 | 2/5 | 7/8 | 99.7 % |
  | Cedar + TenantFlow | 0/5 | 0/5 | 8/8 | 0 % |

  TenantFlow's zeros are what theorems (a) and (b) predict (the ground truth uses the same labels), not independent
  evidence; utility is the measured counterpart of (e). The monitor itself takes p50 0.5 µs / p99 6 µs per decision;
  with the Cedar call (cedarpy) a decision takes about 100 µs.

## Limitations

- Isolation is between tenants, not between users of one tenant (that is Cedar's job, not proven).
- No declassification: a workflow that legitimately mixes two tenants' data is denied by design.
- Side channels (timing, sizes, error rates), tools with memory and data-dependent schedulers are outside the model.
- The registry must label tools correctly; a tool that hands bank-labelled data to an insurer principal is not caught.
- The FIDES baseline is a re-implementation of the label logic of `agent-framework-core` 1.5.0, not the middleware;
  the forgery succeeds only under the conditions of the APIsec proof of concept (`bench/README.md`).
- `tenantflow check` and the game's attacker are bounded or random searches, not proofs.

## Related work

Cedar and its Lean formalisation ([cedar-spec](https://github.com/cedar-policy/cedar-spec)),
[cedar-for-agents](https://github.com/cedar-policy/cedar-for-agents), AWS Bedrock AgentCore Policy,
[LLMbda](https://arxiv.org/abs/2602.20064) (Lean noninterference for agents),
[FIDES](https://arxiv.org/abs/2505.23643) and the APIsec Labs analysis of
[label forgery in FIDES](https://labs.apisec.ai/research/articles/trust-me-bro-forging-security-labels-fides),
[APPA](https://arxiv.org/abs/2607.24625), [SPA](https://arxiv.org/abs/2608.27234),
[AgentFlow](https://arxiv.org/abs/2608.22868), [CaMeL](https://arxiv.org/abs/2503.18813).
How TenantFlow relates to each: `docs/related-work.md`.

## Repository

| Path | Content |
|---|---|
| `docs/spec.md` | threat model, monitor rules, theorem statements, assumptions (§9), changelog |
| `docs/claim-review.md` | every guarantee in README, deck and game checked against the Lean statements |
| `lean/` | model, executable monitor, proofs, oracle (`lake exe oracle`, format in `docs/oracle-format.md`) |
| `python/` | adapter, monitor, Cedar check, MCP gateway, `tenantflow check` CLI (`python/README.md`) |
| `bench/` | baselines, suites, fuzzing agent, results and plots |
| `web/game/`, `web/deck/` | browser game "Leak the Vault", Quarto slide deck |

All data is synthetic. MIT license.
