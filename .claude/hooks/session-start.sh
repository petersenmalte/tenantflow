#!/bin/bash
# SessionStart hook for Claude Code cloud sessions: installs elan + the Lean toolchain pinned in
# lean/lean-toolchain, warms `lake build`, and syncs the Python dev environment.
# Notes:
#  - release.lean-lang.org is blocked by the cloud network policy; elan only needs it to resolve
#    channels such as "stable". A pinned version (vX.Y.Z) is fetched from GitHub releases, which works.
#  - Idempotent: every step is skipped or cheap when already done.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
export ELAN_HOME="${ELAN_HOME:-$HOME/.elan}"
export PATH="$ELAN_HOME/bin:$PATH"

# --- Lean: elan -------------------------------------------------------------------------------
if ! command -v elan >/dev/null 2>&1; then
  echo "[session-start] installing elan"
  curl -sSfL https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh -o /tmp/elan-init.sh
  sh /tmp/elan-init.sh -y --no-modify-path --default-toolchain none
  rm -f /tmp/elan-init.sh
fi

# Make elan/lake/lean available in the session's later Bash calls.
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export ELAN_HOME=\"$ELAN_HOME\"" >> "$CLAUDE_ENV_FILE"
  echo "export PATH=\"$ELAN_HOME/bin:\$PATH\"" >> "$CLAUDE_ENV_FILE"
fi

# --- Lean: pinned toolchain + warm build cache --------------------------------------------------
cd "$ROOT/lean"
TOOLCHAIN="$(tr -d '[:space:]' < lean-toolchain)"      # e.g. leanprover/lean4:v4.34.1
VERSION="${TOOLCHAIN##*:}"                              # v4.34.1
TC_DIR="$ELAN_HOME/toolchains/$(echo "$TOOLCHAIN" | sed 's|/|--|; s|:|---|')"
echo "[session-start] toolchain: $TOOLCHAIN"

if [ ! -x "$TC_DIR/bin/lean" ]; then
  # Normal path (works where release.lean-lang.org is reachable) ...
  if ! elan toolchain install "$TOOLCHAIN" >/dev/null 2>&1; then
    # ... fallback: the cloud network policy blocks release.lean-lang.org but allows GitHub releases.
    echo "[session-start] elan download failed, fetching toolchain from GitHub releases"
    if ! command -v zstd >/dev/null 2>&1; then
      apt-get update -qq >/dev/null 2>&1 || true
      apt-get install -y -qq zstd >/dev/null
    fi
    TMP="$(mktemp -d)"
    curl -sSfL -o "$TMP/lean.tar.zst" \
      "https://github.com/leanprover/lean4/releases/download/$VERSION/lean-${VERSION#v}-linux.tar.zst"
    mkdir "$TMP/x"
    tar --zstd -xf "$TMP/lean.tar.zst" -C "$TMP/x"
    rm -rf "$TC_DIR"
    mkdir -p "$(dirname "$TC_DIR")"
    mv "$TMP"/x/* "$TC_DIR"
    rm -rf "$TMP"
  fi
fi
elan default "$TOOLCHAIN"
lean --version
lake build 2>&1 | tail -n 10

# --- Python dev environment (pytest, ruff) ------------------------------------------------------
if [ -f "$ROOT/python/pyproject.toml" ] && command -v uv >/dev/null 2>&1; then
  cd "$ROOT/python"
  uv sync --quiet
fi

echo "[session-start] done"
