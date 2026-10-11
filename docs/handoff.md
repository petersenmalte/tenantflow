# Handoff

Overwritten at the end of every session. Keep it short; the next session reads only this, CLAUDE.md and TASKS.md.

- **Last session:** F6 (claude-fable-5-1). Theorem (e) transparency proven: `docs/spec.md` §7.8 (new) and §7.6
  (updated), changelog 0.3; `lean/TenantFlow/Proofs/Transparency.lean` (new, registered in `lean/TenantFlow.lean`);
  `docs/proof-status.md` rows added; `Model/` unchanged. Fable spend before F6: 44 USD (user enters the spend after
  F6 in `docs/fable-budget.md`).
- **Open `sorry`s:** none.
- **Next:**
  1. **S22 [SONNET]** cite theorem (e) in deck, game, README (statement and hypotheses in `TASKS.md` S22 / spec §7.8).
  2. **F7 [FABLE]** claim review of deck, game, README (≈ 2–3 USD; hard stop 55 USD). Best after S22 so that (e) is
     already cited and F7 only checks.
  3. S15 (user reads the APIsec article), S20 (decide on the S2 gaps).
  4. O2 [OPUS] final review, then S11 (website; ask for the repo location). S6 only after asking (API costs).
- **Know before editing:**
  - Theorem (e) hypotheses (do not overclaim): agent context `Single t` (= `rootCtx t` up to extensionality), tool
    tenant-private (`observers ⊆ {t}`); then denial ⇔ a label-free precondition fails (Cedar, unregistered or
    non-private tool, `report` without parent, `receive` of a missing child). Preservation (`Single.step`) is per
    step with data hypotheses; there is **no** trace-level "always `Single`" invariant.
  - Game (`web/game`): logic `src/play.js`, view `src/board.js` (also used by the deck), monitor `src/monitor.js`.
    After changing levels or `lean/`, regenerate fixtures and `src/theorems.js` (commands in `web/game/README.md`).
  - Deck (`web/deck`): render the project (`quarto render` in `web/deck`), not the single file; `_variables.yml` and
    `_isolation.lean` are committed and checked by `python/tests/test_deck.py`.
  - CI picks the `#print axioms` names from the `proven`/`defined` rows of `docs/proof-status.md`
    (`scripts/check-lean.sh`); every `Model.*`/`Exec.*` name in those rows must resolve.
  - Benchmark results are from clean commit `5275c58` (`meta.dirty = false`).
- **Deviations and limits** (details in the READMEs of `web/game`, `web/deck`, `bench`):
  - Game and deck checked in headless Chrome (desktop, 390 px phone, dark mode, real mouse drag); no screen-reader or
    real-touch test, deck not tried on a projector.
  - Level 2 under TenantFlow: the write is allowed, the search filters (brief said "blocks step 2").
  - Sandbox has no vault tool (registry error, assumption A2). Fuzzer = bounded search, not a proof.
  - FIDES = re-implementation of agent-framework-core 1.5.0 label logic; APIsec article still unread (S15).
  - CI: FIDES cross-check test skipped (extra not installed); cause of the missing CI runs before `e5f6ec8` unknown.
