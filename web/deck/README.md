# TenantFlow slide deck (Quarto / reveal.js)

`index.qmd`: ten content slides in the order of `docs/project-brief.md` §7 (plus the title slide, `#/0`). One concept
per slide, concrete example first, staged builds. Slides 1, 2, 3 and 5 embed **live widgets**: the game's board
(`web/game/src/board.js`) running the real JavaScript monitor. "Next step" plays the attack one step at a time, the
protection buttons switch between Cedar, FIDES and TenantFlow, and the audience can drag chips directly.

```
quarto render                # in web/deck; Quarto ≥ 1.4; runs scripts/prepare.py first; output: _site/
open _site/index.html
```

`scripts/prepare.py` (pre-render, stdlib only) generates `_variables.yml` from `bench/results/results.json`, extracts the
statement of `isolation` from `lean/TenantFlow/Proofs.lean` into `_isolation.lean`, and copies the game into `game/`
and the benchmark plot into `img/` (git-ignored). `_variables.yml` and `_isolation.lean` are committed, because Quarto
resolves includes before the pre-render step; render the project (`quarto render`), not the single file. `python/tests/test_deck.py` fails if the
variables or the Lean statement are stale or a slide uses an unknown variable. Colour convention: bank blue, insurer gold, untrusted red dashed.

## Deviations and limits
* Checked in headless Chrome at 1280×760 (all slides with all fragments, widget steps in Cedar and TenantFlow mode);
  not yet presented on a projector or checked on a phone.
* The deck's numbers come from `bench/results/results.json` at revision `4775e8a`; the benchmark rerun on a clean commit
  is task S19.
* "FIDES" is our re-implementation of the label logic of agent-framework-core 1.5.0. The APIsec article is cited but
  was not readable (HTTP 403, task S15).
* The game links to slides by number (`../deck/index.html#/N`; inside the deck's copy `../index.html#/N`). Online, only
  `_site/` is published (deck with its game copy), so the inner link is the one used; see "Publishing" below.

## Publishing on petersenmalte.de (S11)

`web/publish-homepage.sh <homepage checkout>` renders this project and copies `_site/` (without source maps) to
`projects/tenantflow/` in the `petersenmalte-homepage` repository and writes the tenantflow commit to `REVISION` there.
The project page `tenantflow.html` and the link tests (`tests/tenantflow.spec.js`) live in that repository; commit,
test and push there. Online: <https://petersenmalte.de/tenantflow> (slides under `/projects/tenantflow/`, game under
`/projects/tenantflow/game/`). The build is a copy: after changing deck or game, publish again.
