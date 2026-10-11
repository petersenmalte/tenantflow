#!/usr/bin/env bash
# CI check for the Lean proofs (CLAUDE.md section 5). Run from anywhere; needs a built `lean/` project.
#  1. no sorry / admit / axiom in lean/TenantFlow and lean/Oracle
#  2. #print axioms for every Model.* / Exec.* name in the 'proven'/'defined' rows of docs/proof-status.md: only
#     propext, Classical.choice, Quot.sound allowed; unknown names fail (the doc must not drift)
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root/lean"

echo "== sorry / admit / axiom"
if grep -rnE '(^|[^A-Za-z_.])(sorry|admit)([^A-Za-z_]|$)|^\s*(private |protected )?axiom ' TenantFlow TenantFlow.lean Oracle \
     --include='*.lean' | grep -vE '^\S+:[0-9]+:\s*--' ; then
  echo "FAIL: sorry/admit/axiom found (comment-only lines are ignored)"; exit 1
fi
echo "ok"

echo "== #print axioms"
names=$(grep -E '\| (proven|defined)' ../docs/proof-status.md | grep -oE '`(Model|Exec)\.[A-Za-z_0-9.]+`' | tr -d '`' | sort -u \
        | grep -v '^Exec\.Sanity' || true)
[ -n "$names" ] || { echo "FAIL: no theorem names found in docs/proof-status.md"; exit 1; }
tmp="CiAxioms_tmp.lean"
trap 'rm -f "$tmp"' EXIT
{ echo "import TenantFlow"; for n in $names; do echo "#print axioms TenantFlow.$n"; done; } > "$tmp"
out=$(lake env lean "$tmp" 2>&1) || true
echo "$out" | grep -E "error|unknown" && { echo "FAIL: unresolved name or error above"; exit 1; }
bad=$(echo "$out" | grep "depends on axioms" \
      | sed -E 's/.*\[(.*)\]/\1/' | tr ',' '\n' | tr -d ' ' \
      | grep -vE '^(propext|Classical\.choice|Quot\.sound)$' || true)
if [ -n "$bad" ]; then echo "FAIL: forbidden axioms: $bad"; echo "$out"; exit 1; fi
echo "checked $(echo "$names" | wc -l | tr -d ' ') names, only propext/Classical.choice/Quot.sound"
