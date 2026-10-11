# TenantFlow

TenantFlow enforces tenant isolation for AI agents that share infrastructure (here: one shared RAG index).
Cedar decides each tool call individually; TenantFlow adds an information-flow monitor with tenant labels that
cannot be forged by data. The core is a Lean 4 model with machine-checked theorems; a Python adapter/gateway, a
benchmark, a slide deck and a browser game build on it.

## What is proven (Lean 4, no `sorry`, axioms in `docs/proof-status.md`)

| Guarantee | Lean name |
|---|---|
| (a) Nothing that may depend on another tenant's data reaches a tenant's principals or tools | `Model.isolation`, `Model.isolation_int` |
| (b) Labels come only from the trusted registry; data cannot forge or launder them | `Model.no_launder`, `Model.ctx_mono`, `Model.child_ctx_eq` |
| (c) What tenant B observes depends only on data B may read (noninterference) | `Model.noninterference`, `Exec.noninterference` |
| (d) The executable monitor implements the model | `Exec.refines`, `Exec.refines_init` |

These hold for every agent behaviour and every Cedar policy, **under the assumptions** of `docs/spec.md`:
trusted session, trusted adapter and tool registry, complete mediation, no side channels. Nothing is claimed about
Cedar itself. The Python monitor and the game's JavaScript monitor are tested against the Lean oracle, not proven.

## Where to look

- `docs/spec.md` – threat model, rules, theorem statements, assumptions; `docs/related-work.md`
- `lean/` – model, executable monitor, proofs, oracle (`lake build`, `lake exe oracle`)
- `python/` – adapter, monitor, Cedar check, gateway, `tenantflow check` CLI (see `python/README.md`)
- `bench/` – baselines and benchmark; read the caveats in `bench/README.md` before quoting numbers
- `web/deck/` – slide deck (Quarto), `web/game/` – browser game "Leak the Vault"

Status: deck and game are being reworked (tasks S17, S18 in `TASKS.md`); final review pending (O2).
