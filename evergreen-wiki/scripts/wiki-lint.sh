#!/usr/bin/env bash
# evergreen-wiki/scripts/wiki-lint.sh — bundle の健全性検査
# 出力: <severity>\t<check>\t<bundle>\t<file>\t<detail>。ERROR ありなら exit 1
set -uo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/lib.sh"
BUNDLES=(); JSON=0
while [ $# -gt 0 ]; do case "$1" in
  --bundle) BUNDLES+=("$2"); shift 2 ;;
  --json)   JSON=1; shift ;;
  *) echo "unknown arg: $1" >&2; exit 2 ;;
esac; done
if [ ${#BUNDLES[@]} -eq 0 ]; then
  while IFS=$'\t' read -r _ path; do BUNDLES+=("$path"); done < <("$SCRIPT_DIR/bundle-locate.sh")
fi
if [ ${#BUNDLES[@]} -eq 0 ]; then exit 0; fi
ERRORS=0
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
ACTOR_RE='^(human:.+|process:.+|[^/ ]+/[^/ ]+)$'
CANON_ORDER="type title description tags sources generated verified status stale_after"

report() { # severity check bundle file detail
  [ "$1" = ERROR ] && ERRORS=$((ERRORS+1))
  if [ "$JSON" = 1 ]; then
    # detail に二重引用符・バックスラッシュは含めない前提(自前生成の文字列のみ)
    printf '{"severity":"%s","check":"%s","bundle":"%s","file":"%s","detail":"%s"}\n' "$1" "$2" "$3" "$4" "$5"
  else
    printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5"
  fi
}

# frontmatter の存在(--- で開始し --- で閉じる)
has_frontmatter() { [ "$(head -n1 "$1")" = "---" ] && [ "$(awk '/^---$/{n++} END{print n}' "$1")" -ge 2 ]; }

# トップレベルキー列が CANON_ORDER の部分列かどうか
canonical_order_ok() {
  local keys; keys=$(fm_block "$1" | grep -E '^[a-zA-Z_]+:' | cut -d: -f1)
  local pos=0 k c i
  for k in $keys; do
    i=0; local found=-1
    for c in $CANON_ORDER; do
      i=$((i+1)); [ "$c" = "$k" ] && { found=$i; break; }
    done
    [ "$found" -lt 0 ] && continue           # 未知キーは OKF 許容(順序検査の対象外)
    [ "$found" -lt "$pos" ] && return 1
    pos=$found
  done
  return 0
}

check_note_file() { # bundle file
  local b="$1" f="$2" rel="notes/$(basename "$2")"
  if ! has_frontmatter "$f"; then
    report ERROR conformance-frontmatter "$b" "$rel" "frontmatter がないか閉じていない"
    return
  fi
  local t; t=$(fm_get "$f" type)
  [ -n "$t" ] || report ERROR conformance-type "$b" "$rel" "type が欠落または空"
  # actor 記法: generated/verified ブロック配下の by: 行をすべて検査
  # process substitution を使い、report の ERRORS 加算がサブシェルで消えないようにする
  while read -r actor; do
    echo "$actor" | grep -Eq "$ACTOR_RE" || report ERROR actor-format "$b" "$rel" "actor 記法違反: $actor"
  done < <(fm_block "$f" | awk '/^(generated|verified):/{on=1; next} /^[a-zA-Z_]+:/{on=0} on && /^[ -]*by:/' | sed 's/^[ -]*by:[ ]*//')
  # 正準形: キー順序
  canonical_order_ok "$f" || report SUGGEST canonical-form "$b" "$rel" "frontmatter キーが正準順でない"
  # 正準形: verified が単一マッピング(直後の行が "  by:" ならリストでない)
  if fm_block "$f" | grep -q '^verified:$'; then
    fm_block "$f" | awk '/^verified:$/{getline; print; exit}' | grep -q '^  by:' &&
      report SUGGEST canonical-form "$b" "$rel" "verified が単一マッピング(1要素リストに正規化を推奨)"
  fi
  # Lifecycle: stale_after 超過(ISO 8601 UTC は文字列比較で成立)
  local sa; sa=$(fm_get "$f" stale_after)
  if [ -n "$sa" ] && [ "$sa" \< "$NOW" ]; then
    report SUGGEST stale "$b" "$rel" "stale_after 超過: $sa"
  fi
  # Trust: 最新 verified.at < generated.at なら検証失効
  local gat vat
  gat=$(fm_block "$f" | awk '/^generated:$/{on=1; next} /^[a-zA-Z_]+:/{on=0} on && /^  at:/{sub(/^  at:[ ]*/, ""); print}' | head -n1)
  vat=$(fm_block "$f" | awk '/^verified:$/{on=1; next} /^[a-zA-Z_]+:/{on=0} on && /at:/{sub(/^.*at:[ ]*/, ""); print}' | sort | tail -n1)
  if [ -n "$gat" ] && [ -n "$vat" ] && [ "$vat" \< "$gat" ]; then
    report SUGGEST verify-stale "$b" "$rel" "最新の検証($vat)が generated($gat)より古い(再検証候補)"
  fi
}

for b in "${BUNDLES[@]}"; do
  for f in "$b"/notes/*.md; do
    [ -e "$f" ] || continue
    check_note_file "$b" "$f"
  done
done
[ "$ERRORS" -gt 0 ] && exit 1
exit 0
