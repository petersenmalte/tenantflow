# TenantFlow – Guide for working with Claude Code

This file is for the human operator. Claude Code does not need it (the rules for Claude are in `CLAUDE.md`).

## The principle in three sentences

Every task in `TASKS.md` has a model tag: `[FABLE]`, `[OPUS]` or `[SONNET]`.
At the start of every session Claude checks whether it is the right model and otherwise stops with a
**STOP message** that tells you exactly what to type. So you always just do what the last STOP message says.

## Step 0 – One-time preparation (about 20 minutes, in the terminal on your Mac)

1. Install and log in to the GitHub CLI:
   ```bash
   brew install gh
   gh auth login        # GitHub.com → HTTPS → login with browser
   ```
2. Install Lean (elan), then reopen the terminal:
   ```bash
   curl https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh -sSf | sh
   lean --version
   ```
3. Install uv for Python:
   ```bash
   curl -LsSf https://astral.sh/uv/install.sh | sh
   ```
4. Only needed later (S9/S10), but can be done now: `brew install node` and `brew install --cask quarto`.
5. **Check billing:** make sure that Fable (`claude-fable-5-1`) is really charged to your credit and that
   Opus/Sonnet run on the subscription. Note the current credit balance so you can compute the spend later.

## Step 1 – Put the starter files in place

```bash
mkdir -p ~/Projects/tenantflow
cd ~/Projects/tenantflow
unzip ~/Downloads/tenantflow-start.zip -d .
ls        # CLAUDE.md  TASKS.md  GUIDE.md  docs/
```

(Adjust the paths if the folder has a different name or the ZIP is somewhere else.)
The repository is created as **public** in S0. If you want it private first, tell Claude in the S0 prompt.

## Step 2 – Setup with Sonnet (S0)

```bash
cd ~/Projects/tenantflow
claude --model claude-sonnet-5-5
```
Prompt:
> Lies CLAUDE.md und TASKS.md und bearbeite Task S0.

At the end the repository is on GitHub and Claude shows you a STOP message for O1.

## Step 3 – Specification with Opus (O1)

In the same Claude Code session:
```
/model claude-opus-5-5
/clear
```
Prompt:
> Lies CLAUDE.md und TASKS.md und bearbeite Task O1.

**Then read it yourself:** `docs/spec.md`. This is the most important moment for you. The sentences in it are
what you will have to explain in an interview later. If something is unclear, ask Opus (costs no Fable budget).

## Step 4 – First Fable session (F0)

```
/model claude-fable-5-1
/clear
```
Prompt:
> Lies CLAUDE.md und TASKS.md und bearbeite Task F0. Bisher verbrauchtes Fable-Budget: 0 $.

At the end of the session:
1. Read off the spend (`/cost` in Claude Code if shown; otherwise compare the credit balance before/after).
2. Enter it in `docs/fable-budget.md` (or tell the next Sonnet session: "Trag in fable-budget.md für F0 X $ ein
   und committe.").

## Step 5 – From now on, always the same loop

1. Read the STOP message.
2. Type `/model …` and `/clear` as given there.
3. Copy the prompt from the STOP message. For FABLE tasks always add the current total spend.
4. After every Fable session, record the spend.

The planned order (Claude automatically picks the next open task if you do not name one):

| Step | Task | Model |
|---|---|---|
| 1 | S0 Setup | Sonnet |
| 2 | O1 Specification | Opus |
| 3 | F0 Spec review | **Fable** |
| 4 | F1a Model + theorem (a) | **Fable** |
| 5 | F1b Theorem (b) → **Gate G1 (≤ 25 $)** | **Fable** |
| 6 | S1 Lean oracle, S2 Python package, S3 differential testing | Sonnet |
| 7 | F2 Theorem (c) → **Gate G2 (≤ 45 $)** | **Fable** |
| 8 | F3 Theorem (d) | **Fable** |
| 9 | S4–S10 baselines, benchmark, CLI, CI, deck, game | Sonnet |
| 10 | O2 Final review | Opus |
| 11 | S11 Integration into petersenmalte.de | Sonnet |

Tip: do the Sonnet tasks from step 6 **before** F2. Differential testing often finds bugs in the model, and those
are better fixed before the hardest proof builds on it.

## When Claude writes "STOPP – Entscheidung nötig"

This happens when a proof is stuck or a gate was missed. Claude then lists 2–3 options.
Rule of thumb: prefer simplifying the model over weakening a theorem until it says nothing.
If you are unsure, ask Opus for an assessment (no Fable budget) and then give the decision to Fable.

## Rules you should follow yourself

- **One task per session, always `/clear` in between.** Long context is the biggest cost driver with Fable.
- **Never use Fable for small stuff.** Not even "just quickly the README". If Claude starts something like that
  under Fable, abort with Esc and remind it of `CLAUDE.md` section 3.2.
- **Check GitHub now and then** to see whether commits arrive. If a session has not committed for more than
  ~30 minutes, say: "Bitte jetzt committen und pushen."
- **You must understand the proofs.** After F1a, F1b, F2 and F3, have Opus explain what was proven and how
  (free on the subscription). Write down the core idea of each proof in 3 sentences.
- **S6 (real LLM run) costs API money outside the Fable budget.** Claude asks first; decide deliberately.

## What comes out at the end

- A public GitHub repository with Lean proofs, Python package, CLI, benchmark and CI
- Quarto slides for understanding and the game "Leak the Vault" to try out
- A project page on petersenmalte.de
- Concrete material for the Lean section of the CV and for conversations about agent security
