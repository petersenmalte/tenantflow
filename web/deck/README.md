# TenantFlow slide deck (Quarto / reveal.js)

`index.qmd`, ten content slides in the order of `docs/project-brief.md` §7 (plus Quarto's title slide, which is `#/0`).
Colours: tenant A (bank) blue, tenant B (insurer) gold, untrusted data red dashed (`custom.scss`).

```
python3 scripts/gen_variables.py     # bench/results/results.json -> _variables.yml (run after every benchmark run)
quarto render index.qmd              # needs Quarto >= 1.4; output: _site/ (git-ignored)
```

Every number on the results slide is a `{{< var ... >}}` from `_variables.yml`, which is generated from
`bench/results/results.json`; `python/tests/test_deck.py` fails if the file is stale or a slide uses an unknown variable.
Claims on slides cite theorem names from `docs/proof-status.md`.

## Deviations and limits
* **Not rendered yet.** Quarto was not installed in the session that wrote the deck, so `quarto render` has never been run:
  layout, the staged builds (fragments) on slides 3 and 5, and the KaTeX formula on slide 6 are unchecked. The CI job `deck`
  renders it on GitHub (also unobserved so far). Render it locally and look at every slide before publishing (S11).
* The browser game links to slides as `../deck/index.html#/N` (`web/game/src/rules.js`); the layout of the website
  integration (S11) may change these paths.
* The staged build on slide 3 shows the chip in three boxes (bank, index, insurer) instead of animating a move.
* The results slide shows the benchmark caveats from `bench/README.md` (TenantFlow's 0 % is predicted by the theorems and not
  independent evidence; `FIDES logic` is a re-implementation of agent-framework-core 1.5.0; small suites).
* Slide 6 quotes the Lean statement of `isolation` from `lean/TenantFlow/Proofs.lean` by hand; it is not extracted automatically.
