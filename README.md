# TenantFlow

**Work in progress.**

TenantFlow enforces tenant isolation for AI agents that share infrastructure (for example one shared RAG index).
Cedar decides each tool call individually; TenantFlow adds an information-flow monitor with tenant labels that
cannot be forged by data. The core is a Lean 4 model with machine-checked theorems.

Nothing in this repository is claimed to be proven yet. See `docs/project-brief.md` for the plan.
