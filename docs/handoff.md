# Handoff

Overwritten at the end of every session. Keep it short; the next session reads only this, CLAUDE.md and TASKS.md.

- **Last task:** F0 – Adversarial spec review, final theorem statements (done)
- **Model:** claude-fable-5-1
- **State:** `docs/spec.md` is v0.2 (final theorem statements, binding Lean shape in §8). Findings and decisions
  in `docs/spec-review.md`. No Lean code written: `lake`/`elan` are not installed in the cloud session, so a
  compiled signature sketch was not cheap; new task S0b sets up the toolchain.
- **Main changes vs v0.1:** `read`/`send` → `call k args` with registry `(observers, needsTrusted, result)`;
  `deliver` without recipient; `rank_mem`; ghost provenance as separate `GState` layer; (d) = forward simulation
  + `Step.det`; (b) = (b2), (b1) is an `Exec` lemma; (c) simulation relation has an "absent-or-tainted" clause;
  assumptions A4, A5, A7 added.
- **For F1a, read first:** `docs/spec-review.md` §C, then spec §4–§5, §7.1, §7.7, §8.
- **Open `sorry`s (file:line, lemma):** none
- **What was tried (if stuck):** –
- **Next task:** S0b [SONNET] – Lean toolchain for cloud sessions (then F1a [FABLE])
