#!/usr/bin/env bash
# Render the deck (which contains a copy of the game) and copy it into a checkout of
# petersenmalte-homepage under projects/tenantflow/. Commit and push in that repository yourself.
#
#   web/publish-homepage.sh ../petersenmalte-homepage
#
# Served at https://petersenmalte.de/projects/tenantflow/ (deck) and .../game/ (game).
# The project page itself (tenantflow.html) lives in the homepage repository.
set -euo pipefail

if [ $# -ne 1 ] || [ ! -f "$1/CNAME" ]; then
  echo "usage: $0 <path to petersenmalte-homepage checkout>" >&2
  exit 2
fi
root="$(cd "$(dirname "$0")/.." && pwd)"
dest="$(cd "$1" && pwd)/projects/tenantflow"

if [ -n "$(git -C "$root" status --porcelain)" ]; then
  echo "warning: tenantflow working tree is dirty; REVISION will not match a commit" >&2
fi
rev="$(git -C "$root" rev-parse --short HEAD)"

(cd "$root/web/deck" && quarto render)

mkdir -p "$dest"
# Source maps only help debugging reveal.js and double the download.
rsync -a --delete --exclude '*.map' --exclude REVISION "$root/web/deck/_site/" "$dest/"
echo "$rev" > "$dest/REVISION"
echo "published tenantflow@$rev to $dest"
