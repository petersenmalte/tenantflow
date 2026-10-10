# Handoff

Overwritten at the end of every session. Keep it short; the next session reads only this, CLAUDE.md and TASKS.md.

- **Last task:** S0b – Lean toolchain for cloud sessions (done)
- **Model:** claude-sonnet-5-5
- **State:** `.claude/hooks/session-start.sh` (registered in `.claude/settings.json`, remote sessions only, synchronous)
  installs elan, the toolchain from `lean/lean-toolchain` (v4.34.1), runs `lake build` once and `uv sync` in `python/`.
  Verified from a clean state: hook exits 0, second run is idempotent (<1 s), `lake build`, `ruff check`, `pytest` pass.
- **Cloud network caveat:** `release.lean-lang.org` is blocked by the egress policy, so `elan toolchain install`
  fails there. The hook falls back to the Lean tarball from GitHub releases (needs `zstd`, installed via apt if missing)
  and unpacks it into `~/.elan/toolchains/`. Only pinned versions (`vX.Y.Z`) work, not `stable`/`nightly`.
  Mathlib (if a FABLE task ever adds it) would need `lake exe cache get`, which may also be blocked – check first.
- **Hook takes effect** in sessions started from the default branch only after this branch is merged; in the current
  branch's sessions run `bash .claude/hooks/session-start.sh` manually (with `CLAUDE_CODE_REMOTE=true`) then
  `export PATH=$HOME/.elan/bin:$PATH`.
- **Open `sorry`s (file:line, lemma):** none
- **What was tried (if stuck):** –
- **Next task:** F1a [FABLE] – Lean model + executable monitor + theorem (a). Read first: `docs/spec-review.md` §C,
  then `docs/spec.md` §4–§5, §7.1, §7.7, §8. Ask the user for the current Fable spend (`docs/fable-budget.md`, gate G1).
