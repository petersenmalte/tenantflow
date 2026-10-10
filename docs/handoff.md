# Handoff

Overwritten at the end of every session. Keep it short; the next session reads only this, CLAUDE.md and TASKS.md.

- **Last task:** O1 – Draft the formal spec (done)
- **Model:** claude-opus-5-5
- **State:** `docs/spec.md` v0.1 (threat model, system model, monitor rules §5, theorems (a)–(d) + sanity
  examples §7.6, Lean sketch §8, assumptions A1–A6, changelog) and `docs/related-work.md` written. No Lean code.
- **For F0, read first:** spec §5 "Design decisions" and the "Remarks for F0" in §7.3/§7.4; open questions are
  listed in the changelog row of v0.1. Main ones: taint vs. clearance at read; (b1) is near-definitional in the
  model; (c) uses fixed data-independent schedules and deterministic strategies; the `receive` return channel.
- **Unverified source:** APIsec Labs article returned HTTP 403; its details (version, fix status) must be checked
  in S4 (noted in `docs/related-work.md`).
- **Open `sorry`s (file:line, lemma):** none
- **What was tried (if stuck):** –
- **Next task:** F0 [FABLE] – Adversarial spec review, final theorem statements
