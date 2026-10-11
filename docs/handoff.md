# Handoff

Overwritten at the end of every session. Keep it short; the next session reads only this, CLAUDE.md and TASKS.md.

- **Last session:** S11 website integration (claude-opus-5-5, user's explicit choice). Homepage PR
  petersenmalte/petersenmalte-homepage#16 (merged) adds `tenantflow.html`, an index icon and the deck/game build; live and checked on 2026-10-11.
  All tasks except S6 (optional real-LLM run) are done. CI green; `lake build`, pytest (41, extras `mcp` + `fides`),
  game tests (68) and `quarto render` pass.
- **Open `sorry`s:** none.
- **Next:** S6 only after the user approves API costs. After changing deck or game: `web/publish-homepage.sh
  ../petersenmalte-homepage`, run its `npm test`, commit there (details in `web/deck/README.md`).
- **Know before editing:**
  - Claims: every guarantee sentence in README, deck and game is checked in `docs/claim-review.md`; changing wording
    means re-checking against `docs/spec.md` §7 and the assumptions A1–A8 (§9).
  - Game (`web/game`): logic `src/play.js`, view `src/board.js` (also used by the deck), monitor `src/monitor.js`.
    After changing levels or `lean/`, regenerate fixtures and `src/theorems.js` (commands in `web/game/README.md`).
  - Deck (`web/deck`): render the project (`quarto render` in `web/deck`); `_variables.yml` and `_isolation.lean` are
    committed and checked by `python/tests/test_deck.py`. The game links slides as `../deck/index.html#/N`.
  - Benchmark: run only on a pushed commit (`git pull --rebase && git push` first); results now from `8caa375`.
  - Gateways return only `denied` to agents (A8); reasons go to the log.
- **Deviations and limits** (details in the READMEs of `web/game`, `web/deck`, `bench`, `python`):
  - Game and deck checked in headless Chrome (desktop, 390 px phone, dark mode, real mouse drag); no screen-reader or
    real-touch test, deck not tried on a projector.
  - Level 2 under TenantFlow: the write is allowed, the search filters (brief said "blocks step 2").
  - FIDES = re-implementation of the agent-framework-core 1.5.0 label logic; forgery only under the APIsec PoC
    conditions (2/5), utility 7/8 because hiding blocks reading fetched content.
  - Cedar schema hand-written (generator not used, reasons in `python/README.md`).
  - Cause of the missing CI runs before `e5f6ec8` unknown.
