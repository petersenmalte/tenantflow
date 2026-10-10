# TenantFlow – Project Brief

Working title. Status: planning (October 2026). Author: Malte Petersen.

## 1. Problem

Several tenants (example: a bank and an insurer) use the same AI agent platform and share technical components,
here a shared RAG index. Per-call authorization (Cedar, AWS Bedrock AgentCore Policy) decides each tool call in
isolation. A sequence of individually allowed calls can still move tenant-A data to tenant B, e.g.:
read a bank document → write a summary into the shared index → a session of the insurer retrieves it.

A second problem: label-based information-flow control can be broken when labels are taken from the data itself.
The published analysis of APIsec Labs shows that the FIDES middleware of Microsoft Agent Framework accepts a
`security_label` field inside attacker-controlled payloads, and that missing fields default to `trusted`.

## 2. Goal

A small, well-scoped system with machine-checked guarantees:

1. Tenant labels are attached by a **trusted adapter** from the **authenticated session**, never from data.
2. An information-flow monitor in front of the shared RAG index and the agent's tools blocks flows across tenants.
3. Cedar is used (not re-implemented) for per-call least privilege.
4. Lean 4 proofs for the properties below; differential testing connects the proofs to the Python code.
5. Directly usable: a CI check (`tenantflow check`), offline trace analysis, optionally a blocking MCP gateway.

The contribution is an application of established ideas (IFC for agents) to a concrete, demonstrable problem –
not a claim of a new research direction.

## 3. Model sketch (to be made precise in `docs/spec.md`)

- `Tenant`, `Principal = (tenant, user)`. A session carries one authenticated principal from trusted config.
- `Label = (owners : set of tenants, integrity : trusted | untrusted)`; join = union of owners, untrusted wins.
- Payloads are arbitrary attacker-controllable values; they may contain fields that look like labels.
- Shared RAG index: documents with labels set by the adapter at write time; queries are filtered server-side.
- Agent context label: join of everything the agent has read in this session.
- Agent actions (chosen arbitrarily / adversarially): read from a tool, write to the index, query the index,
  send to a sink (response to a principal, external tool), delegate to a sub-agent (label is inherited).
- Monitor: allow iff the Cedar decision is `allow` **and** the flow check passes.
- Cedar is an opaque function `authorize : Request → Decision` in Lean. Isolation must follow from the monitor,
  for every authorizer. No theorem about Cedar itself is claimed.

## 4. Theorems

| ID | Informal statement | Expected difficulty |
|---|---|---|
| (a) Isolation | In every reachable state, nothing delivered to a principal of tenant B carries an owner other than B. | easy–medium (invariant, induction) |
| (b) No forgery / no laundering | Labels depend only on trusted metadata and input labels, never on payload content; an output label is at least as restrictive as the join of its inputs. | medium |
| (c) Noninterference | Two initial states that differ only in tenant-A data produce identical observations for tenant-B principals (termination-insensitive; side channels excluded). | hard |
| (d) Refinement | The executable monitor (used by the oracle, the test vectors and optionally the gateway) implements the abstract model. | medium–hard |

Lessons from the planning phase: a theorem that holds "for every authorizer satisfying forbid-overrides-permit and
default-deny" is vacuous if the monitor does the isolation – do not state it. Invariants over arbitrarily long traces
are not automatically hard. The adversarial spec review (task F0) exists to catch such statements early.

## 5. Non-goals

Side channels (timing, resource usage), prompt injection that stays within allowed permissions, implicit flows
beyond the modelled ones, correctness of data classification, bugs in the trusted adapter itself (covered only by
differential testing, not by proof), multiple shared components (cache, agent memory) in version 1.

## 6. Benchmark

- Variants: no protection, Cedar only, FIDES middleware, Cedar + TenantFlow.
- Suites: cross-tenant leaks via call sequences (each call Cedar-allowed), label forgery, legitimate workflows.
- Drivers: adversarial fuzzing agent without LLM (worst case, free); optional small real-LLM run for utility.
- Metrics: attack success rate, utility (legitimate tasks completed), latency per decision.
- AgentDojo is not the main benchmark: APPA reports 0 % undefended attack success for the frontier models it tested,
  so it says little about this setting. The AgentDojo banking suite can be added for comparability with LLMbda.

## 7. Presentation

### Slide deck (Quarto / reveal.js)
Style reference: https://ai.katestange.net/ai/course/llm-course/slides/from-tokens-to-transformers/
(one concept per slide, concrete example before abstraction, staged builds, fixed colour convention).
Colours: tenant A (bank) blue, tenant B (insurer) gold, untrusted data red dashed. Data shown as coloured chips.

1. Two companies, one agent platform
2. What Cedar checks per call (staged)
3. Three allowed calls, one leak (chips move from blue to gold)
4. Labels: where they come from, how they combine
5. The forgery attack: data assigns itself a label
6. The invariant as a formula, next to the Lean statement
7. What the proof covers and what it does not
8. Architecture: session, adapter, Cedar, monitor
9. Benchmark results (measured data only)
10. How to use it: CI check in five minutes

### Browser game "Leak the Vault"
The visitor plays a compromised agent and tries to move bank data to the insurer.
Protection switch: off / Cedar / FIDES / TenantFlow.

| Level | Attempt | Lesson |
|---|---|---|
| 1 | Read the other tenant's data directly | Cedar already blocks this |
| 2 | Read bank data, write it to the shared index, query as insurer | Every call is Cedar-allowed; TenantFlow blocks step 2 |
| 3 | Smuggle data with a forged `security_label` in a ticket | FIDES accepts it; TenantFlow ignores labels from data |
| 4 | Delegate to a sub-agent with more rights | Labels travel with the delegation |
| 5 | Sandbox: write policies, run the fuzzer | A found leak is shown as a concrete call sequence |

Chips move visibly at each step; a "Warum?" panel explains the decision in one sentence and links the deck slide and
the Lean theorem. Runs fully in the browser; the JS monitor is tested against the Lean oracle.

## 8. Related work (to be summarised in `docs/related-work.md`)

- Cedar and its Lean formalisation with differential randomized testing: https://github.com/cedar-policy/cedar-spec
- cedar-for-agents (MCP schema generator, Python/WASM bindings): https://github.com/cedar-policy/cedar-for-agents
- AWS Bedrock AgentCore Policy (Cedar for agent tool calls, GA March 2026)
- LLMbda calculus – Lean 4 mechanised noninterference for agents: https://www.alphaxiv.org/abs/2602.20064
- FIDES – IFC for agents: https://arxiv.org/abs/2505.23643 ; Microsoft Agent Framework security docs (principals with
  `tenant_id`/`user_id`): https://learn.microsoft.com/agent-framework/agents/security
- APIsec Labs, label forgery in FIDES: https://labs.apisec.ai/research/articles/trust-me-bro-forging-security-labels-fides
- APPA – recoverable IFC: https://arxiv.org/abs/2607.24625
- SPA – persistent agents across queries: https://arxiv.org/abs/2608.27234
- AgentFlow – flow-centric policy language: https://arxiv.org/abs/2608.22868
- CaMeL – capability-based defence against prompt injection (Google DeepMind, 2025)

## 9. Budget

Fable (`claude-fable-5-1`): 60 USD in total, only for tasks tagged `[FABLE]`. Gates in `TASKS.md`.
All other tasks run on Opus/Sonnet via subscription.
