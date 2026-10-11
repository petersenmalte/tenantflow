# Benchmark baselines

Implemented in `python/src/tenantflow/baselines.py` (task S4); the suites and fuzzer come in S5.

| Variant | Cedar per call | Tenant filter on the shared index | Flow labels |
|---|---|---|---|
| `none` | no | no | none |
| `cedar-only` | yes | no | none |
| `fides` | yes | no | integrity + confidentiality, **no tenant**, labels may come from data |
| `tenantflow` | yes | yes | tenant owners + integrity, labels only from the trusted adapter/registry |

All baselines have the same `step` API as `tenantflow.monitor.Monitor` and record the ground-truth tenant label
in the agent context and the events without enforcing it, so leaks can be measured independently of the variant.

## FIDES baseline: re-implementation, and why

FIDES ships as an experimental middleware in `agent-framework-core` (`agent_framework.security`,
`LabelTrackingFunctionMiddleware`). I checked the released versions on PyPI (checked 2026-10-11):

* **1.5.0** (2026-05-20, first release with the middleware): a result item with
  `additional_properties["security_label"]` is used directly as its label (tier 1), and
  `ContentLabel.from_dict` defaults a missing `integrity` to `trusted`. Both behaviours of the published
  label-forgery class are present in the source.
* **1.21.0** (current at the time): the tiers were hardened (`default_integrity=UNTRUSTED`, embedded labels "may
  only restrict", complete labels only from framework-stamped producers). The forgery described by APIsec Labs
  does not apply to it as-is. I did not reproduce the exact article: it returned HTTP 403, so the baseline is
  derived from the source of 1.5.0, not from the article.

The real middleware needs a running agent (chat client, function invocation pipeline), which is out of proportion
for a deterministic benchmark. Hence `fides` is a **faithful re-implementation of its label logic**, not the
middleware itself:

* `FidesLabel.from_dict` / `FidesLabel.join` mirror `ContentLabel.from_dict` / `combine_labels`;
  `tests/test_baselines.py::test_matches_real_package_if_installed` compares them with the real package when
  `uv sync --extra fides` (pins `agent-framework-core==1.5.0`) is installed.
* Tier 1 (embedded label) > tier 2 (tool's declared source integrity = registry `result` integrity).
  Tools with `needsTrusted` stand for tools with `accepts_untrusted=False` in `PolicyEnforcementFunctionMiddleware`.
* Simplifications: confidentiality has only `public`/`private` (no `user_identity`); documents written to the index
  are `private` unless the data embeds a label; no variable hiding (`auto_hide_untrusted`).
* The numbers for `fides` therefore characterise "the label design of 1.5.0", not the current release; the deck
  must say so.

Only local, synthetic data (`CLAUDE.md` §8); nothing is run against third-party systems.

## Benchmark (task S5)

Run: `cd python && uv run python ../bench/run.py [--episodes 2000 --seed 1]`, then
`uv run --group bench python ../bench/plot.py`. Output: `bench/results/results.json` (all numbers, with date, git
revision, seed) and `bench/results/plots/summary-{light,dark}.png`. Nothing is typed in by hand.

Code: `world.py` (two tenants, shared index, tool registry, Cedar policy), `suites.py` (scripted suites),
`fuzz.py` (adversarial agent without LLM), `run.py`, `plot.py`; harness tests in `python/tests/test_bench.py`.

* **Cedar** permits every action of the world for the agents' role, so every call is individually allowed
  (the guarantees hold for every authorizer; a stricter policy can only block more).
* **Suite 1, leaks (n=5):** direct query, summary laundering through the shared index, cross-tenant sink,
  delegation relay, reverse direction. **Suite 2, forgery (n=4):** forged `security_label` in a tool result, in a
  document, missing-field default, plus an unlabelled control. **Suite 3, utility (n=8):** same-tenant workflows
  (write/retrieve/deliver, fetch+deliver, delegation, trusted-only tools, two users of one tenant).
* **Fuzzer:** 2000 random 30-step episodes over 6 agents (both tenants, children), canary queries, forged labels,
  cross-tenant sinks; identical episodes for every variant.
* **Success is judged on ground truth, not on the variant's decisions:** every variant records the tenant/integrity
  label of the context it would have under TenantFlow (`world.violations`): an agent whose context contains foreign
  tenant data, an event whose label is not readable by an observer of the tool, a trusted-only tool run on an
  untrusted context. Scripted attacks use concrete goals (canary string seen by / sent to the other tenant, `pay` ran).
* **Latency:** wall clock of `step` per decision (200 episodes x 30 steps per variant, Apple/CPython, single thread).
  It is dominated by the Cedar call through `cedarpy` (about 100–170 microseconds depending on the machine load).
  `latency_monitor_only` measures TenantFlow's monitor with Cedar stubbed to "allow" on the same episodes (S19):
  p50/p99 in the single-digit microseconds. Both include decisions that end early (unknown agent or tool), which
  is why the mean is below the median in `latency`.
* **Provenance:** `meta.git` is the commit the run used; `meta.dirty` is true if `bench/` or `python/src` had
  uncommitted changes (then `meta.git` does not identify the code). Results before S19 were produced with
  uncommitted S5 code under revision `4775e8a`.

### Reading the results honestly

* The baselines are saturated: with a shared index, a permissive Cedar policy and no tenant in any label, leaks are
  trivial to produce, so "100 %" says the attacks are well-formed, not that the baselines are weak by design.
  FIDES resists only the control (unlabelled untrusted content), not forgery.
* TenantFlow's 0 % is **not independent evidence**: the ground truth uses the same label definitions as the monitor,
  so 0 % is what theorems (a) and (b) predict. The benchmark's job is to show that the harness detects violations in
  the other variants and that TenantFlow keeps utility; the guarantee itself comes from the proofs and their
  assumptions (trusted adapter, trusted session, no side channels; `docs/spec.md`).
* Scripted suites are small (n=4..8) and hand-designed; the fuzzer is random, not learned. Wilson 95 % intervals are in
  `results.json`. Utility is measured on workflows that fit the tenant model, so a 100 % utility does not cover
  workflows that legitimately mix tenants (these are denied by design).
* `fides` characterises the label design of `agent-framework-core` 1.5.0 as re-implemented here, not the middleware
  of the current release and not the APIsec article's exact setup (see above).
