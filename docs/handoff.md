# Handoff

Overwritten at the end of every session. Keep it short; the next session reads only this, CLAUDE.md and TASKS.md.

- **Last task:** S1 – Lean oracle executable (done)
- **Model:** claude-sonnet-5-5
- **State:** `lean/Oracle/Main.lean` (+ `lean_exe oracle` in `lean/lakefile.toml`), format in `docs/oracle-format.md`,
  5 hand-written traces with expected outputs in `lean/Oracle/tests/` (`run.sh`). `Model/`, `Exec/`, `Proofs/` untouched.
- **Notes for S2/S3:** the Python monitor must port the toy `score` exactly (whitespace tokens, see format doc) and
  the Cedar stand-in (allow-list of `(role, action name)`). Compare `kind`/`denied`/`ctx`/`final`, not `reason`.
  Ext tools may not be called `deliver`.
- **Open `sorry`s:** none
- **Next task:** S2 [SONNET] – Python package (S3 after S2).
