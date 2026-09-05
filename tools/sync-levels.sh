#!/usr/bin/env bash
# sync-levels.sh — bring the browser build's authored levels into this
# project, from the DEPLOYED tree, never by hand. Q-032.
#
# CONTENT IS AUTHORED ONCE AND FLOWS. The levels are written upstream
# (mbace1/Suds-Jack, toko-drop/levels/*.json, format 1 from js/level.js) and
# this build reads the very same files: no exporter, no allow-list, nothing
# that can drop a field. They land in `levels/`, which is git-ignored —
# hand-editing a file there is how a lineage forks, so don't.
#
#   tools/sync-levels.sh                 # from origin/gh-pages of the sibling clone
#   tools/sync-levels.sh --ref <ref>     # any ref, e.g. a feature branch before it ships
#   UPSTREAM=/path/to/Suds-Jack tools/sync-levels.sh
#
# Reads the ref's tree with `git show`, so the sibling clone's checkout is
# irrelevant — the same rule as CLAUDE.md's "audit the DEPLOYED tree".
# Writes levels/LEVELS_SOURCE.txt with the exact commit, so a trace or a
# capture can say which upstream tree it played.
set -euo pipefail
cd "$(dirname "$0")/.."

UPSTREAM="${UPSTREAM:-$HOME/src/Suds-Jack}"
REF="origin/gh-pages"
if [ "${1:-}" = "--ref" ]; then REF="$2"; fi

if [ ! -d "$UPSTREAM/.git" ]; then
  echo "sync-levels: no clone at $UPSTREAM (set UPSTREAM=)" >&2; exit 1
fi
SHA=$(git -C "$UPSTREAM" rev-parse --verify "$REF^{commit}")
FILES=$(git -C "$UPSTREAM" ls-tree -r --name-only "$REF" -- toko-drop/levels | grep '\.json$' || true)
if [ -z "$FILES" ]; then
  echo "sync-levels: $REF ($SHA) has no toko-drop/levels/*.json" >&2; exit 1
fi

mkdir -p levels
rm -f levels/*.json
n=0
for f in $FILES; do
  git -C "$UPSTREAM" show "$REF:$f" > "levels/$(basename "$f")"
  n=$((n + 1))
done
{
  echo "upstream: $UPSTREAM"
  echo "ref: $REF"
  echo "commit: $SHA"
  echo "synced: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "files: $n"
} > levels/LEVELS_SOURCE.txt
echo "✔ synced $n level(s) from $REF ($SHA) into levels/"
