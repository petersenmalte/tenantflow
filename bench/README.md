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
