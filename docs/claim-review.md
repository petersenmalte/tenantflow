# Claim review (F7): deck, game, README against the Lean theorems

Reviewed on 2026-10-11 (claude-fable-5-1, task F7) at revision `7a9e2c7`. Every sentence in `README.md`,
`web/deck/index.qmd` and `web/game/` (`src/levels.js`, `src/rules.js`, `src/game.js`, `index.html`, `README.md`)
that states a guarantee was compared with the Lean statements (`lean/TenantFlow/Proofs*/`) and the assumptions of
`docs/spec.md` §9. Required text changes are task **S23** in `TASKS.md`. Theorem statements are unchanged.

**Status (O2, claude-opus-5-5, 2026-10-11): all findings 1–7 fixed in S23.** 1, 2: deck slides 8/10 wording;
3: README row (e); 4: README row (b), deck slide 8 "tested, not proven" line, game `rules.js` cites `Model.no_launder`
next to `Model.isolation_int` and states that payload independence is by construction and tested, game README;
5: README, deck slide 8, game (`game.js` result card, `levels.js` level 5, `index.html`, README) list A1–A8;
6: the Python gateway and the MCP gateway return only `denied` to the agent and log the reason
(`tests/test_monitor.py::test_gateway_hides_denial_reason`, `tests/test_mcp_gateway.py`); the game keeps showing
reasons in its operator view ("Why?"); 7: write denial cites `Model.no_launder`.

Severity: **A** = overstated (says more than the theorem), **B** = incomplete hypothesis or assumption,
**C** = loose citation (true, but the cited theorem is not the one that says it).

## 1. Findings

| # | Sev. | Location | Claim | What Lean says | Fix (S23) |
|---|---|---|---|---|---|
| 1 | A | deck slide 7, `index.qmd:184` | (e) "… is **never blocked by the monitor**" | `Model.transparency_step`: `r = denied ↔ ¬ LabelFree`. `LabelFree` *contains* Cedar's permit, a registered private tool, an existing parent (`report`) / child (`receive`). So the agent **can** be blocked – by Cedar or a missing precondition, not by a flow check. | "… is never denied by the **flow checks** (Cedar and missing preconditions can still deny)". |
| 2 | B | deck slide 9, `index.qmd:239` | "(e) … for agents that read only their own tenant's trusted data" | Hypotheses are `Single t ctx` **and**, for `call`, `observers ⊆ {t}` (`LabelFree.call`, `hpriv`). | Add "and call only tenant-private tools". |
| 3 | B | `README.md` row (e) | "(only Cedar or a missing agent, tool or child can deny)" | `LabelFree` also needs an authenticated session (`hp`), a registered tool (`hi`) and a parent for `report` (`hpar`). | "(only Cedar, an unregistered tool, or a missing session, parent or child can deny)". |
| 4 | B | deck slide 7 (b), `index.qmd:181`; `README.md` row (b); game `rules.js:100` ("a label written inside the data is ignored") | "no forgery, no laundering – `Model.no_launder`"; "data cannot forge or launder" | `Model.no_launder` is (b2): `label₀ o ⊑ label x` pointwise, **including integrity** (`trusted` is the bottom), so an untrusted origin forces an untrusted object – that *is* the model-level anti-forgery statement, and via `Exec.refines_ghost` it holds for `Exec` traces. What is **not** a theorem: payload independence of the executable monitor ((b1), dropped in F1b; spec §7.3 D8 "parametric in `Pay`", sanity examples 4 and 6, differential tests). "Ignored" describes (b1). | Keep the citations; add once per artefact: "that the monitor never reads a label out of a payload is by construction and tested (spec §7.3 (b1), D8), not a theorem". In `rules.js:100` cite `Model.no_launder` (integrity part) next to `Model.isolation_int`. |
| 5 | B | `README.md` assumptions line; deck slide 7 right column; game `game.js:94`, `levels.js:114`, `web/game/README.md:50` | "trusted session, trusted adapter and tool registry, complete mediation, no side channels" | Spec §9 has **A4** (stateless tools, closed world: a tool with memory shared across tenants is a channel the theorems do not see) and **A7** (Cedar decides from principal and action only; entities derived from the index are a channel). A5 also contains *data-independent scheduling*. None of the three lists mentions A4 or A7. | Extend all five lists: "…, stateless tools, Cedar sees only principal and action, no side channels (incl. data-independent scheduling)" – or cite "A1–A8 in `docs/spec.md` §9". |
| 6 | B | implicit everywhere (c) is cited: `README.md` row (c), deck slide 7, game `rules.js:111/125` | (c) for the deployed monitor | `Exec.run` applies `⌊·⌋` before `histUpdate`: strategies see `denied`, **not the reason string**. `python/src/tenantflow/monitor.py:108` returns `{"kind": "denied", "reason": …}` to the caller. Whether a reason string can carry non-`B`-readable information is **not proven** (plausibly not: reasons are functions of the agent's own label, the registry and Cedar). | Preferred: the gateway returns only `denied` to the agent and logs the reason (one-line change + test); then no text change. Otherwise add to the assumption lists: "the agent does not see denial reasons (A8)". A8 is now stated in spec §9. |
| 7 | C | game `rules.js:102` (write denied, "flow: tainted") | cites `Model.isolation` | The write check `hown : readable t ctx` is a §5 rule, not what `Model.isolation` states; (a) holds with or without it. The theorem that speaks about the written doc's label is `Model.no_launder` (doc label = writer's `ctx` ⊒ origins). | Cite `Model.no_launder` and link slide 4. |

## 2. Checked and covered exactly (no change)

- **(a)** README row (a); deck slide 6 formula "∀ reachable state, ∀ event `e`, ∀ observer `u`, ∀ origin `o`:
  `readable u (label₀ o)`" = `Model.isolation` verbatim; "whatever the agent does, whatever Cedar says": agent =
  arbitrary `Action` in `Step`, `cfg.authorize` arbitrary. "Principals or tools": principals are modelled as
  observers of tools (A3), same wording as spec §1.
- **(b) rules on slide 4**: "join of everything it read" (`ctx := ctx ⊔ …` in `Allowed.call/query/receive`); "data
  may go to `u` only if every owner is `u`" = `readable`; "a document keeps its writer's label" (`index ++ [⟨σ.ctx, v⟩]`);
  "a helper starts with its parent's label" = `Model.child_ctx_eq`; "labels only grow" = `Model.ctx_mono`.
  "A reply from outside stays untrusted": holds when the registry labels the tool's result untrusted (A2) –
  stated as such on slide 5 ("labels come only from the tool registry").
- **(c)** "what tenant B observes depends only on data B may read": `obs` = events at tools `B` observes;
  `LowEq` = `B`-readable initial docs, `B`'s prompts, and the functions of tools whose result label is `B`-readable.
  Same strategy and schedule in both runs (A5). `Exec.noninterference` cited correctly for the executable monitor.
- **(d)** `Exec.refines`, `Exec.refines_init`; "JavaScript port of the Lean-verified `Exec.step`" (`index.html:37`)
  is justified by (d).
- **(e)** README row (e) hypotheses ("depends only on its own tenant's trusted data, calling tools private to its
  tenant") match `Single` + `hpriv`; game `play.js:75` cites `Model.transparency` as "also".
- Level texts: "the bank's entry never comes back" (server-side `readableDocs` filter); "labels never shrink"
  (`ctx_mono`); level 3 cites `Model.isolation_int`, `Model.no_launder` (model level, see finding 4).
- Hedges present and correct: "tested, not proven" (Python/JS monitors), "nothing is claimed about Cedar", "a
  bounded search, not a proof" (fuzzer, `tenantflow check`), "TenantFlow's 0 is what the theorems predict, not
  independent evidence", footer "guarantees hold in the Lean model under the stated assumptions".
- No vacuity: sanity examples 1–7 (`Exec.Sanity`, by `decide`) show that the intended flows are allowed; (e) rules
  out the all-denying monitor on single-tenant contexts (spec §7.6).

## 3. Not claimed anywhere, and must stay unclaimed

- Isolation between users of one tenant; integrity noninterference; side channels; tools with memory (A4);
  correctness of the registry's classification (A2); the Python adapter beyond differential testing (A6);
  a trace-level "always `Single`" invariant for (e).
