# Benchmark baselines

Implemented in `python/src/tenantflow/baselines.py` (task S4); the suites and fuzzer come in S5.

| Variant | Cedar per call | Tenant filter on the shared index | Flow labels |
|---|---|---|---|
| `none` | no | no | none |
| `cedar-only` | yes | no | none |
| `fides` | yes | no | integrity + confidentiality, **no tenant**; tools without `source_integrity` take labels from their arguments |
| `tenantflow` | yes | yes | tenant owners + integrity, labels only from the trusted adapter/registry |

All baselines have the same `step` API as `tenantflow.monitor.Monitor` and record the ground-truth tenant label
in the agent context and the events without enforcing it, so leaks can be measured independently of the variant.

## FIDES baseline: re-implementation, and why

FIDES ships as an experimental middleware in `agent-framework-core` (`agent_framework.security`,
`LabelTrackingFunctionMiddleware`). The real middleware needs a running agent (chat client, function invocation
pipeline), which is out of proportion for a deterministic benchmark, so `fides` is a **re-implementation of its label
logic**, pinned to the source of **1.5.0** (`uv sync --extra fides`). Corrected in task S15 after reading the APIsec Labs
analysis and the 1.5.0 source; the S4 version had modelled the forgery in the wrong place (see below).

How the result label of a tool call is computed (`LabelTrackingFunctionMiddleware.process`, 1.5.0):

* **Tier 2:** the tool declares `source_integrity` → that integrity, argument labels are ignored.
* **Tier 3:** no declaration → the join of the labels found in the **call arguments** (`_get_input_labels`: any dict
  with a `security_label` key, parsed by `ContentLabel.from_dict`, whose missing fields default to `trusted`; the legacy
  key `label`; variable references carry the label of the hidden result); no labels → `default_integrity` (untrusted).
* **Tier 1** (per-item labels in a result item's `additional_properties`) is framework metadata; a dict returned by a
  tool is serialised to text, so data cannot set it. Not modelled.
* **auto_hide_untrusted** (default on): an untrusted result is replaced by a variable reference (`{"var": "var_n"}`
  here) and does not taint the context integrity. The context label only ever joins (monotone).

This tier-3 argument scan is the forgery described by APIsec Labs (*Trust Me, Bro*, MSRC case 126767, confirmed in
1.11.0–1.15.0; the same code is in 1.5.0): a `security_label` that the attacker writes into a tool argument becomes the
result label. MSRC confirmed the forgery primitive and closed the case as defense-in-depth (no CVE). It becomes a policy
bypass only under the conditions of their proof of concept: a tool without `source_integrity`, `auto_hide_untrusted`
switched off, and a context that is not yet untrusted.

`tests/test_baselines.py` checks `ContentLabel.from_dict`, `combine_labels` and the argument scan against the real
package (`test_argument_scan_matches_real_package_if_installed`) when the `fides` extra is installed; the tier logic,
hiding and monotonicity are transcribed from the 1.5.0 source and tested on the cases of the article. Simplifications:
confidentiality has only `public`/`private`; documents written to the shared index get the writer's FIDES context
integrity (FIDES has no index concept); index queries are not hidden.

Ground truth stays TenantFlow's label, with one adjustment for fairness: a result that FIDES hides never reaches the
agent, so it does not enter the agent's ground-truth context; it does enter the label of a tool call that receives the
variable reference.

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
  delegation relay, reverse direction. **Suite 2, forgery (n=5):** after the APIsec analysis: (2a) forged trusted
  label in the arguments of a tool without `source_integrity` under the PoC conditions, (2b) the same with
  `security_label: {}`, (2c) the shipped default (the forged ticket arrives as untrusted content and is hidden),
  (2d) the context is already untrusted (monotonicity), (2e) control without a label. Success = `pay` ran on a context
  that depends on untrusted data (ground truth). **Suite 3, utility (n=8):** same-tenant workflows
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
  For FIDES, the forgery succeeds exactly in the two cases with the PoC conditions (2a, 2b) and fails under the
  shipped default, on an already untrusted context and for the control, matching the article and MSRC's assessment.
  With `auto_hide_untrusted` the agent cannot read fetched content, so utility case 3b fails for FIDES (7/8): a real
  cost of hiding, which the APIsec article also mentions. FIDES has no tenant in its labels, so suite 1 and the
  fuzzer's confidentiality violations are unaffected by these settings.
* TenantFlow's 0 % is **not independent evidence**: the ground truth uses the same label definitions as the monitor,
  so 0 % is what theorems (a) and (b) predict. The benchmark's job is to show that the harness detects violations in
  the other variants and that TenantFlow keeps utility; the guarantee itself comes from the proofs and their
  assumptions (trusted adapter, trusted session, no side channels; `docs/spec.md`).
* Scripted suites are small (n=5..8) and hand-designed; the fuzzer is random, not learned. Wilson 95 % intervals are in
  `results.json`. Utility is measured on workflows that fit the tenant model, so a 100 % utility does not cover
  workflows that legitimately mix tenants (these are denied by design).
* `fides` characterises the label logic of `agent-framework-core` 1.5.0 as re-implemented here, not the middleware of
  the current release; the deployment choices (which tools declare `source_integrity`, `auto_hide_untrusted`) are
  part of each scenario (`world.FIDES_DEFAULT`, `world.FIDES_POC`). The fuzzer uses the shipped default.
