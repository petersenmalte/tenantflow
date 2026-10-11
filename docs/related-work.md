# Related work

TenantFlow applies established ideas – information-flow control (IFC) for agents, per-call authorization,
mechanised noninterference – to one concrete problem: tenant isolation over a shared RAG index. This file says what
each piece of related work does and how TenantFlow relates to it. Summaries are based on the public abstracts and
documentation linked below (checked 2026-10-10); where a detail could not be verified, that is stated.

## Cedar and its Lean formalisation

Cedar is AWS's open-source authorization policy language. Its semantics, validator and analysis are formalised in
Lean, and the production Rust implementation is checked against the Lean model by differential randomized testing
("verification-guided development"). <https://github.com/cedar-policy/cedar-spec>

*Relation:* TenantFlow uses Cedar as an opaque per-call authorizer and claims nothing about it; every theorem
quantifies over all authorizers. TenantFlow copies Cedar's methodology: a Lean model, an executable Lean oracle,
and differential testing of the production (here: Python) implementation against it.

## cedar-for-agents

A collection of Rust crates, JavaScript packages and bindings that connect Cedar to agent workflows: an MCP tool
description parser, a generator that derives a Cedar schema from MCP tool descriptions (also available as WASM on
npm and as a Python wrapper on PyPI), and an MCP server exposing Cedar's analysis tools.
<https://github.com/cedar-policy/cedar-for-agents>

*Relation:* used in task S2 to generate the Cedar schema for the example MCP server. It authorizes single calls;
it does not track flows across calls.

## AWS Bedrock AgentCore Policy

A policy engine attached to the AgentCore Gateway that evaluates every agent-to-tool request against Cedar
policies before it is forwarded; rules can be authored in natural language and are compiled to Cedar, and a
log-only mode exists. Generally available since 3 March 2026.
<https://aws.amazon.com/about-aws/whats-new/2026/03/policy-amazon-bedrock-agentcore-generally-available/>

*Relation:* the industrial instance of per-call authorization. TenantFlow's motivating example is a sequence of
calls that each pass such a check but jointly move data across tenants.

## LLMbda calculus

Garby, Gordon, Sands: *The LLMbda Calculus: AI Agents, Conversations, and Information Flow*. An untyped
call-by-value lambda calculus with forkable and clearable conversations, code generation and dynamic labels
propagated by every reduction. The authors prove termination-insensitive probabilistic noninterference (plus an
"insulated" variant where the attacker chooses all untrusted inputs); harness and proofs are in Lean, and the
verified interpreter is the agent harness. On the AgentDojo banking suite it matches CaMeL's utility.
<https://arxiv.org/abs/2602.20064>

*Relation:* the closest formal work. LLMbda gives a general calculus for agent programs; TenantFlow is a fixed
monitor for one architecture (sessions, shared index, delegation) with multi-tenant confidentiality labels, and
models the agent as an arbitrary strategy rather than as a program in a calculus. Our noninterference statement (c)
is checked against LLMbda's notion in task F0.

## FIDES and the Microsoft Agent Framework

Costa, Köpf, Kolluri, Paverd, Russinovich, Salem, Tople, Wutschitz, Zanella-Béguelin: *Securing AI Agents with
Information-Flow Control*. A formal model for the security and expressiveness of agent planners, an analysis of
which properties dynamic taint tracking can enforce, and FIDES, a planner that tracks confidentiality and integrity
labels and enforces policies deterministically, evaluated on AgentDojo. <https://arxiv.org/abs/2505.23643>
FIDES ships as experimental middleware in Microsoft Agent Framework (Python); its security documentation models
principals with `tenant_id` / `user_id`. <https://learn.microsoft.com/agent-framework/agents/security>

*Relation:* TenantFlow uses the same label structure (confidentiality + integrity, floating context label) and
compares against the FIDES middleware as a baseline (S4). The difference is where labels come from: TenantFlow
attaches them only from trusted metadata (theorem (b)).

## APIsec Labs: label forgery in FIDES

B. Kaur, *Trust Me, Bro: Forging Security Labels in Microsoft's FIDES Middleware*, APIsec Research Labs, 2026-09-01.
<https://labs.apisec.ai/research/articles/trust-me-bro-forging-security-labels-fides>
For a tool without a `source_integrity` declaration, the FIDES label-tracking middleware derives the result label from
`security_label` dicts found in the tool's call arguments, and `ContentLabel.from_dict` defaults missing fields to
`trusted`, so attacker-written data can mint a trusted label. MSRC (case 126767) confirmed the forgery primitive and
closed it as defense-in-depth without a CVE; a policy bypass requires `auto_hide_untrusted=False` and a context that is
not yet untrusted (the context label is join-only). Confirmed against agent-framework-core 1.11.0–1.15.0; the same
argument scan is in 1.5.0, which our baseline re-implements (`bench/README.md`). Read by the user and checked against the
1.5.0 source in task S15.

*Relation:* the attack class that TenantFlow's (b) `Model.no_launder` rules out: labels are computed from registry labels
only, payloads never enter a label. Reproduced only locally against our own re-implementation (`CLAUDE.md` §8):
benchmark suite 2 and game level 3.

## APPA – recoverable IFC

Kravchenko, Liventsev, Konstantinov, Iskhakov, Kukuy: *APPA: Recoverable Information-Flow Control for Real-World
LLM Agents*. Addresses the utility cost of monotone taint tracking: tool calls are checked before and after
execution at dispatch and protocol gateways, unannotated tools get gradual security types, and disposable child
branches inspect untrusted data without contaminating the main context. Reports 64.2–91 % utility and zero observed
attacks in 1,320 guarded episodes. <https://arxiv.org/abs/2607.24625>

*Relation:* TenantFlow's labels are monotone with no declassification (a non-goal); APPA shows how to recover
utility. APPA also reports 0 % undefended attack success for the frontier models it tested on AgentDojo, which is
why AgentDojo is not TenantFlow's main benchmark.

## SPA – persistent agents across queries

Girrens, Wang: *SPA: Securing Persistent LLM Agents Across Queries with Plan-First Information-Flow Control*.
The planner emits a complete declarative plan per query; dual-lattice IFC tracks confidentiality and integrity;
results are stored as labelled artifacts so later queries see only metadata. Evaluated on AgentDojo and a
multi-query extension (AgentDojo-MQ). <https://arxiv.org/abs/2608.27234>

*Relation:* SPA treats persistent state across queries of one agent; TenantFlow treats state shared across
tenants (the RAG index). Shared agent memory is a TenantFlow non-goal for v1.

## AgentFlow – flow-centric policy language

Ammanaghatta Shivakumar, Priya, Gao: *AgentFlow: A Flow-Centric Policy Language and Framework for Securing LLM
Agent Systems*. A policy language for where data may flow, a reference monitor mediating agent actions (including
delegation), and a bounded SMT-based verifier; preliminary results on AgentDojo and AgentDyn.
<https://arxiv.org/abs/2608.22868>

*Relation:* closest in spirit to `tenantflow check` (S7). AgentFlow verifies policies with bounded SMT;
TenantFlow fixes one flow policy (tenant isolation) and proves it for unbounded traces in Lean.

## CaMeL

Debenedetti et al. (Google DeepMind), *Defeating Prompt Injections by Design*, 2025. A privileged LLM writes a
program from the trusted user query; a quarantined LLM processes untrusted data; a custom interpreter tracks
capabilities (provenance) of values and enforces policies at tool calls. <https://arxiv.org/abs/2503.18813>

*Relation:* CaMeL addresses prompt injection within one user's task through control/data separation. TenantFlow
does not constrain the agent's control flow at all (the agent is arbitrary) and addresses cross-tenant
confidentiality only.
