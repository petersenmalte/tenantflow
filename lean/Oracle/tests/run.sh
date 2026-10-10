#!/bin/sh
# Usage: Oracle/tests/run.sh [--update]   (from lean/)
# Compares `lake exe oracle` output on Oracle/tests/*.json with *.expected.out.
cd "$(dirname "$0")/../.." || exit 1
fail=0
for f in Oracle/tests/t*.json; do
  exp="${f%.json}.expected.out"
  got=$(lake exe oracle < "$f")
  if [ "$1" = "--update" ]; then echo "$got" > "$exp"; continue; fi
  if [ "$got" = "$(cat "$exp")" ]; then echo "ok   $f"; else echo "FAIL $f"; fail=1; fi
done
exit $fail
