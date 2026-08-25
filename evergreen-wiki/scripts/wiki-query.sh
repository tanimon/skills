#!/usr/bin/env bash
# evergreen-wiki/scripts/wiki-query.sh — bundle 内ページの機械的な絞り込み
# 出力: <bundle>\t<slug>\t<type>\t<status>\t<description>
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/lib.sh"
BUNDLES=(); TYPE=""; TAG=""; KEYWORD=""; SLUG=""
while [ $# -gt 0 ]; do case "$1" in
  --bundle)  BUNDLES+=("$2"); shift 2 ;;
  --type)    TYPE=$2;    shift 2 ;;
  --tag)     TAG=$2;     shift 2 ;;
  --keyword) KEYWORD=$2; shift 2 ;;
  --slug)    SLUG=$2;    shift 2 ;;
  *) echo "unknown arg: $1" >&2; exit 2 ;;
esac; done
if [ ${#BUNDLES[@]} -eq 0 ]; then
  while IFS=$'\t' read -r _ path; do BUNDLES+=("$path"); done < <("$SCRIPT_DIR/bundle-locate.sh")
fi
for b in "${BUNDLES[@]}"; do
  for f in "$b"/notes/*.md; do
    [ -e "$f" ] || continue
    slug=$(basename "$f" .md)
    [ -n "$SLUG" ] && [ "$slug" != "$SLUG" ] && continue
    t=$(fm_get "$f" type)
    [ -n "$TYPE" ] && [ "$t" != "$TYPE" ] && continue
    if [ -n "$TAG" ]; then
      fm_get "$f" tags | tr -d '[]' | tr ',' '\n' | sed 's/^ *//; s/ *$//' | grep -qx -- "$TAG" || continue
    fi
    if [ -n "$KEYWORD" ]; then grep -qi -- "$KEYWORD" "$f" || continue; fi
    st=$(fm_get "$f" status); [ -n "$st" ] || st=stable
    printf '%s\t%s\t%s\t%s\t%s\n' "$b" "$slug" "$t" "$st" "$(fm_get "$f" description)"
  done
done
