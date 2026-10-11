# Handoff

Overwritten at the end of every session. Keep it short; the next session reads only this, CLAUDE.md and TASKS.md.

- **Last session:** F7 (claude-fable-5-1). Claim review of README, deck and game against the Lean statements:
  `docs/claim-review.md` (7 findings: 1 overstated, 5 incomplete hypotheses/assumptions, 1 loose citation; the rest
  is covered exactly). No theorem statement changed, `lean/` untouched. Spec §9 gained **A8** (agents do not observe
  denial reasons; implicit in `Exec.run`'s `⌊·⌋`), changelog row added. Fable spend before F7: 50 USD (user enters
  the spend after F7 in `docs/fable-budget.md`).
- **Open `sorry`s:** none.
- **Next:**
  1. **S23 [SONNET]** apply the F7 fixes (exact locations and wording in `docs/claim-review.md` §1 / `TASKS.md` S23),
     including the gateway change: agent sees `denied` only, reason goes to the log.
  2. O2 [OPUS] final review (after S23), then S11 (website; ask for the repo location). S6 only after asking.
  3. F5 stays deferred (budget). Remaining Fable budget after F7 is reserve for fixes found by differential testing.
- **Know before editing:**
  - Do not overclaim (e): hypotheses `Single t ctx` **and** tenant-private tool; a `Single` agent can still be denied
    by Cedar, an unregistered tool, a missing session/parent/child. "Never denied by the flow checks" is the correct
    phrase, "never blocked by the monitor" is not.
  - (b) at model level = `Model.no_launder` (pointwise ⊑ incl. integrity, so untrusted origins force untrusted
    objects; holds on `Exec` traces via `Exec.refines_ghost`). Payload independence of the executable monitor ((b1),
    "labels in data are ignored") is by construction + tested, not a theorem.
  - Assumption lists must name A1–A8 (A4 stateless tools, A7 Cedar inputs and A8 were missing everywhere).
  - Game (`web/game`): logic `src/play.js`, view `src/board.js` (also used by the deck), monitor `src/monitor.js`.
    After changing levels or `lean/`, regenerate fixtures and `src/theorems.js` (commands in `web/game/README.md`).
  - Deck (`web/deck`): render the project (`quarto render` in `web/deck`), not the single file.
