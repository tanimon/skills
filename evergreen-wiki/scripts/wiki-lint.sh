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

check_bundle_cross() { # bundle
  local b="$1" f slug to t
  local links_file; links_file=$(mktemp)
  # links_file: "from>to" の行集合(存在しないリンク先も含む。broken-link 判定と併用)
  for f in "$b"/notes/*.md; do
    [ -e "$f" ] || continue
    slug=$(basename "$f" .md)
    for to in $(grep -o '](/notes/[a-z0-9-]*\.md)' "$f" | sed 's|](/notes/||; s|\.md)||'); do
      printf '%s>%s\n' "$slug" "$to" >> "$links_file"
      [ -f "$b/notes/$to.md" ] || report ERROR broken-link "$b" "notes/$slug.md" "リンク先が存在しない: /notes/${to}.md"
    done
    grep -qF "(/notes/$slug.md)" "$b/index.md" || report ERROR index-miss "$b" "notes/$slug.md" "index.md に未記載"
  done
  # one-way-link / orphan(存在するページ間のみ対象。slug は [a-z0-9-] のみなので正規表現エスケープ不要)
  for f in "$b"/notes/*.md; do
    [ -e "$f" ] || continue
    slug=$(basename "$f" .md)
    while read -r to; do
      [ -n "$to" ] || continue
      [ -f "$b/notes/$to.md" ] || continue
      grep -qx "$to>$slug" "$links_file" ||
        report ERROR one-way-link "$b" "notes/$slug.md" "→ ${to} への片方向リンク(${to} 側に逆リンクなし)"
    done < <(grep "^$slug>" "$links_file" 2>/dev/null | sed "s/^$slug>//")
    t=$(fm_get "$f" type)
    if [ "$t" = "note" ]; then
      grep -q ">$slug\$" "$links_file" ||
        report ERROR orphan "$b" "notes/$slug.md" "他の note からの被リンクなし"
    fi
  done
  rm -f "$links_file"
  # index-format: frontmatter は okf_version のみ / エントリ行の書式
  fm_block "$b/index.md" | grep -Ev '^okf_version:' | grep -q . &&
    report ERROR index-format "$b" "index.md" "frontmatter に okf_version 以外のキーがある"
  grep -E '^\* ' "$b/index.md" | grep -Ev '^\* \[[^]]+\]\(/notes/[a-z0-9-]+\.md\) - .+' | head -n1 | grep -q . &&
    report ERROR index-format "$b" "index.md" "エントリ行が「* [title](/notes/slug.md) - description」形式でない"
  # log-format: 日付見出しの形式と降順
  grep -E '^## ' "$b/log.md" | grep -Ev '^## [0-9]{4}-[0-9]{2}-[0-9]{2}$' | head -n1 | grep -q . &&
    report ERROR log-format "$b" "log.md" "日付見出しが ## YYYY-MM-DD 形式でない"
  local dates sorted
  dates=$(grep -E '^## [0-9]{4}-[0-9]{2}-[0-9]{2}$' "$b/log.md" | sed 's/^## //')
  sorted=$(echo "$dates" | sort -r)
  [ "$dates" = "$sorted" ] ||
    report ERROR log-format "$b" "log.md" "日付見出しが新しい順(降順)でない"
  # concept-candidate: 同一タグ5件以上を非 concept ページが共有 + そのタグを持つ concept ページがない
  local tag has_concept
  for tag in $(for f in "$b"/notes/*.md; do
      [ -e "$f" ] || continue
      [ "$(fm_get "$f" type)" = "concept" ] && continue
      fm_get "$f" tags | tr -d '[]' | tr ',' '\n' | sed 's/^ *//; s/ *$//'
    done | grep -v '^$' | sort | uniq -c | awk '$1>=5{print $2}'); do
    has_concept=0
    for f in "$b"/notes/*.md; do
      [ -e "$f" ] || continue
      [ "$(fm_get "$f" type)" = "concept" ] || continue
      fm_get "$f" tags | tr -d '[]' | tr ',' '\n' | sed 's/^ *//; s/ *$//' | grep -qx "$tag" && { has_concept=1; break; }
    done
    [ "$has_concept" = 0 ] && report SUGGEST concept-candidate "$b" "-" "タグ ${tag} を5件以上が共有(concept ページ候補)"
  done
}

for b in "${BUNDLES[@]}"; do
  for f in "$b"/notes/*.md; do
    [ -e "$f" ] || continue
    check_note_file "$b" "$f"
  done
  check_bundle_cross "$b"
done
[ "$ERRORS" -gt 0 ] && exit 1
exit 0
