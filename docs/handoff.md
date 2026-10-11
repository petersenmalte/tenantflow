# Handoff

Overwritten at the end of every session. Keep it short; the next session reads only this, CLAUDE.md and TASKS.md.

- **Last session:** Opus inventory and rework (claude-opus-5-5, user-authorised to work on SONNET tasks).
  Done: S12, S13, S14, S16, S17, S18, S19. CI green on all four jobs (lean, python, game, deck).
- **Open `sorry`s:** none (F4 by Fable: `Exec.noninterference` in `lean/TenantFlow/Proofs/NoninterferenceExec.lean`).
- **Next:**
  1. **F6 [FABLE]** transparency theorem (user wants the remaining ~14 USD used for F6 + F7).
  2. **F7 [FABLE]** claim review of deck, game, README (after F6).
  3. S15 (user reads the APIsec article), S20 (decide on the S2 gaps), S21 (which file the `.gitignore` comment means).
  4. O2 [OPUS] final review, then S11 (website; ask for the repo location). S6 only after asking (API costs).
- **Know before editing:**
  - Game (`web/game`): logic `src/play.js`, view `src/board.js` (also used by the deck), monitor `src/monitor.js`.
    After changing levels or `lean/`, regenerate fixtures and `src/theorems.js` (commands in `web/game/README.md`).
  - Deck (`web/deck`): render the project (`quarto render` in `web/deck`), not the single file; `_variables.yml` and
    `_isolation.lean` are committed and checked by `python/tests/test_deck.py`.
  - Benchmark results are from clean commit `5275c58` (`meta.dirty = false`).
- **Deviations and limits** (details in the READMEs of `web/game`, `web/deck`, `bench`):
  - Game and deck checked in headless Chrome (desktop, 390 px phone, dark mode, real mouse drag); no screen-reader or
    real-touch test, deck not tried on a projector.
  - Level 2 under TenantFlow: the write is allowed, the search filters (brief said "blocks step 2").
  - Sandbox has no vault tool (registry error, assumption A2). Fuzzer = bounded search, not a proof.
  - FIDES = re-implementation of agent-framework-core 1.5.0 label logic; APIsec article still unread (S15).
  - CI: FIDES cross-check test skipped (extra not installed); cause of the missing CI runs before `e5f6ec8` unknown.
