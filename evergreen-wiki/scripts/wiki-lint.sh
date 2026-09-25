#!/usr/bin/env bash
# evergreen-wiki/scripts/wiki-lint.sh — bundle の健全性検査
# 出力: <severity>\t<check>\t<bundle>\t<file>\t<detail>。ERROR ありなら exit 1
# bundle が1件も見つからなければ何も出力せず exit 0
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
SLUG_RE='^[a-z0-9][a-z0-9-]*$'
TS_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
CANON_ORDER="type title description tags sources generated verified status stale_after"
# links_file: "from>to" の行集合(bundle ごとに truncate して使い回す)。中断時も EXIT trap で掃除する
LINKS_FILE=$(mktemp)
trap 'rm -f "$LINKS_FILE"' EXIT

# JSON 文字列エスケープ。detail にはファイル由来の値(actor・時刻等)が入り、タブ等の制御文字も
# 混入しうるため、\ と " に加えてタブ・CR・LF をエスケープし、残りの制御文字は除去する
# (JSON は文字列内の生の制御文字を許さない)
json_esc() {
  local s=${1//\\/\\\\}; s=${s//\"/\\\"}
  s=${s//$'\t'/\\t}; s=${s//$'\r'/\\r}; s=${s//$'\n'/\\n}
  case "$s" in *[[:cntrl:]]*) s=$(printf '%s' "$s" | tr -d '\000-\037') ;; esac
  printf '%s' "$s"
}
# TSV フィールドの区切り文字除去(タブ・CR・LF を空白へ。混入すると列がずれる)
tsv_clean() { local s=${1//$'\t'/ }; s=${s//$'\r'/ }; s=${s//$'\n'/ }; printf '%s' "$s"; }

report() { # severity check bundle file detail
  [ "$1" = ERROR ] && ERRORS=$((ERRORS+1))
  if [ "$JSON" = 1 ]; then
    printf '{"severity":"%s","check":"%s","bundle":"%s","file":"%s","detail":"%s"}\n' \
      "$(json_esc "$1")" "$(json_esc "$2")" "$(json_esc "$3")" "$(json_esc "$4")" "$(json_esc "$5")"
  else
    printf '%s\t%s\t%s\t%s\t%s\n' "$(tsv_clean "$1")" "$(tsv_clean "$2")" "$(tsv_clean "$3")" "$(tsv_clean "$4")" "$(tsv_clean "$5")"
  fi
}

# frontmatter の存在(--- で開始し --- で閉じる)。行末 CR は剥がして判定する(lib.sh の改行方針)
has_frontmatter() {
  awk '{ sub(/\r$/, "") } NR==1 && $0!="---"{bad=1; exit} /^---$/{n++} END{exit (bad || n<2)}' "$1"
}
# has_cr <file>: CR を含む(CRLF 改行)なら真。grep -q がファイルを直接読むのでパイプの SIGPIPE は起きない
has_cr() { grep -q $'\r' "$1"; }

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

# fm_next_line <file> <key>: frontmatter 内でトップレベルキー行(<key>:)の直後の1行を出力。
# fm_block | grep -q のパイプは grep の早期 exit → SIGPIPE → pipefail で条件が反転しうるため、
# 単一 awk で捕捉してから呼び出し側が判定する
fm_next_line() {
  awk -v k="$2" '{ sub(/\r$/, "") } /^---$/{n++; next} n>=2{exit} n!=1{next} p{print; exit} $0==k":"{p=1}' "$1"
}

check_note_file() { # bundle file
  local b="$1" f="$2" rel
  rel="notes/$(basename "$2")"
  has_cr "$f" && report SUGGEST line-ending "$b" "$rel" "改行が CRLF(正準形は LF。解釈は LF と同じに行う)"
  if ! has_frontmatter "$f"; then
    report ERROR conformance-frontmatter "$b" "$rel" "frontmatter がないか閉じていない"
    return
  fi
  local t; t=$(fm_get "$f" type)
  [ -n "$t" ] || report ERROR conformance-type "$b" "$rel" "type が欠落または空"
  # actor 記法: generated/verified ブロック配下の by: 行をすべて検査
  # process substitution を使い、report の ERRORS 加算がサブシェルで消えないようにする
  # 値は scalar()(lib.sh)で引用符・インラインコメントを剥がしてから照合する
  # (引用符付き・コメント付きの OKF 妥当な actor を ERROR にしない)
  while IFS= read -r actor; do
    [[ $actor =~ $ACTOR_RE ]] || report ERROR actor-format "$b" "$rel" "actor 記法違反: ${actor}"
  done < <(awk "$AWK_SCALAR"'{ sub(/\r$/, "") } /^---$/{n++; next} n>=2{exit} n!=1{next}
                /^(generated|verified):/{on=1; next} /^[a-zA-Z_]+:/{on=0}
                on && /^[ -]*by:/{sub(/^[ -]*by:[ ]*/, ""); print scalar($0)}' "$f")
  # 正準形: キー順序
  canonical_order_ok "$f" || report SUGGEST canonical-form "$b" "$rel" "frontmatter キーが正準順でない"
  # 正準形: verified / sources が単一マッピング(キー行の直後がブロックリストの "  - " でなく "  key:" ならリストでない)
  local vnext snext
  vnext=$(fm_next_line "$f" verified)
  case "$vnext" in "  by:"*)
    report SUGGEST canonical-form "$b" "$rel" "verified が単一マッピング(1要素リストに正規化を推奨)" ;;
  esac
  snext=$(fm_next_line "$f" sources)
  case "$snext" in "  resource:"*|"  id:"*|"  title:"*)
    report SUGGEST canonical-form "$b" "$rel" "sources が単一マッピング(1要素リストに正規化を推奨)" ;;
  esac
  # Provenance: sources[].id の形式・一意性と、本文の脚注ラベルとの結合
  # (SPEC §5.1: 脚注ラベルは sources[].id への join key。不一致は無音の出典取り違えになる)
  local sids sid dup label hit
  sids=$(fm_block "$f" | awk "$AWK_SCALAR"'/^sources:$/{on=1; next} /^[a-zA-Z_]+:/{on=0}
                              on && /^[ -]*id:/{sub(/^[ -]*id:[ ]*/, ""); print scalar($0)}')
  while read -r sid; do
    [ -n "$sid" ] || continue
    # 文字種違反は「OKF 的には妥当・正準形違反」なので SUGGEST(§3 OKF 許容原則。ERROR にすると
    # SPEC 準拠の外部 bundle を exit 1 で拒絶してしまう)
    echo "$sid" | grep -Eq "$SLUG_RE" ||
      report SUGGEST source-id-format "$b" "$rel" "sources の id が slug 規則(^[a-z0-9][a-z0-9-]*\$)に違反: $sid"
  done <<< "$sids"
  # 重複は結合キーの曖昧化(無音の出典取り違え)なので ERROR。SPEC §5.1 は id を
  # 「個別の主張を属性付けする安定キー」と定めており、重複キーはその役目を果たせない(SPEC の含意)
  dup=$(printf '%s\n' "$sids" | grep -v '^$' | sort | uniq -d)
  while read -r sid; do
    [ -n "$sid" ] || continue
    report ERROR source-id-dup "$b" "$rel" "sources の id がページ内で重複: $sid"
  done <<< "$dup"
  # 本文の脚注ラベル(参照 [^id] と定義 [^id]: の双方)を全数捕捉してから照合する。
  # コード領域は body_prose(lib.sh)で除外する(正規表現の文字クラス [^...] を脚注と誤認しないため)。
  # ラベルの抽出は id と同じ slug 規則(先頭 [a-z0-9]、以降 [a-z0-9-])に限定する。
  # [^-abc] のような先頭ハイフンの文字クラスを拾わないための制約でもある。代償が2つ:
  # 非 slug な id を使う外部 bundle では footnote-ref が効かない(既知の偽陰性)、および
  # slug 文字種のみの文字クラス([^a-z] 等)を code で囲まず本文に書くと偽陽性 ERROR になる
  # (本文中の正規表現・コード断片はインラインコード必須。conventions.md §4)
  while read -r label; do
    [ -n "$label" ] || continue
    hit=$(printf '%s\n' "$sids" | grep -Fx -- "$label" || true)
    [ -n "$hit" ] ||
      report ERROR footnote-ref "$b" "$rel" "脚注ラベル [^${label}] に対応する sources の id がない"
  done < <(body_prose "$f" | grep -o '\[\^[a-z0-9][a-z0-9-]*\]' | sed 's/^\[\^//; s/\]$//' | sort -u)
  # Lifecycle: stale_after 超過(ISO 8601 UTC は文字列比較で成立。fm_get が引用符を剥がすので
  # 引用符付き timestamp でも誤判定しない)。形式外の値(never・UTC 以外のオフセット等)は
  # 文字列比較が無意味なので timestamp-format で報告し、stale 判定には使わない
  local sa; sa=$(fm_get "$f" stale_after)
  if [ -n "$sa" ] && ! [[ $sa =~ $TS_RE ]]; then
    report SUGGEST timestamp-format "$b" "$rel" "stale_after が ISO 8601 UTC(YYYY-MM-DDTHH:MM:SSZ)形式でない: ${sa}"
  elif [ -n "$sa" ] && [ "$sa" \< "$NOW" ]; then
    report SUGGEST stale "$b" "$rel" "stale_after 超過: ${sa}"
  fi
  # Trust: 最新 verified.at < generated.at なら検証失効(値は scalar() で引用符・コメントを剥がして比較する)。
  # 形式外の at は timestamp-format で報告し、比較対象から外す
  local gat vat at
  gat=$(awk "$AWK_SCALAR"'{ sub(/\r$/, "") } /^---$/{n++; next} n>=2{exit} n!=1{next}
             /^generated:$/{on=1; next} /^[a-zA-Z_]+:/{on=0}
             on && /^  at:/{sub(/^  at:[ ]*/, ""); print scalar($0); exit}' "$f")
  if [ -n "$gat" ] && ! [[ $gat =~ $TS_RE ]]; then
    report SUGGEST timestamp-format "$b" "$rel" "generated.at が ISO 8601 UTC(YYYY-MM-DDTHH:MM:SSZ)形式でない: ${gat}"
    gat=""
  fi
  # at: は行頭アンカーで抽出する(/at:/ だと by: 行の値に "at:" を含む actor を拾い、
  # sort 汚染で verify-stale の偽陰性になる)
  vat=""
  while IFS= read -r at; do
    [ -n "$at" ] || continue
    if ! [[ $at =~ $TS_RE ]]; then
      report SUGGEST timestamp-format "$b" "$rel" "verified.at が ISO 8601 UTC(YYYY-MM-DDTHH:MM:SSZ)形式でない: ${at}"
    elif [ -z "$vat" ] || [ "$vat" \< "$at" ]; then
      vat=$at
    fi
  done < <(awk "$AWK_SCALAR"'{ sub(/\r$/, "") } /^---$/{n++; next} n>=2{exit} n!=1{next}
             /^verified:$/{on=1; next} /^[a-zA-Z_]+:/{on=0}
             on && /^[ -]*at:/{sub(/^[ -]*at:[ ]*/, ""); print scalar($0)}' "$f")
  if [ -n "$gat" ] && [ -n "$vat" ] && [ "$vat" \< "$gat" ]; then
    report SUGGEST verify-stale "$b" "$rel" "最新の検証(${vat})が generated(${gat})より古い(再検証候補)"
  fi
}

check_bundle_cross() { # bundle
  local b="$1" f slug to t bad_link tag_hit prose
  # 予約ファイル構造検査: index.md / log.md が無ければ ERROR を出し、
  # 以降の当該ファイルに依存する横断検査(index-miss/index-format/log-format)はスキップする
  local has_index=1 has_log=1
  [ -f "$b/index.md" ] || { report ERROR conformance-structure "$b" "index.md" "予約ファイルが存在しない"; has_index=0; }
  [ -f "$b/log.md" ]   || { report ERROR conformance-structure "$b" "log.md" "予約ファイルが存在しない"; has_log=0; }
  [ "$has_index" = 1 ] && has_cr "$b/index.md" && report SUGGEST line-ending "$b" "index.md" "改行が CRLF(正準形は LF。解釈は LF と同じに行う)"
  [ "$has_log" = 1 ] && has_cr "$b/log.md" && report SUGGEST line-ending "$b" "log.md" "改行が CRLF(正準形は LF。解釈は LF と同じに行う)"
  : > "$LINKS_FILE"
  for f in "$b"/notes/*.md; do
    [ -e "$f" ] || continue
    slug=$(basename "$f" .md)
    # slug-format: 命名規則違反のファイルは正規リンク記法で参照できないため、
    # 真因をこの1件で報告し、以降の相互リンク検査(誤検出の連鎖源)からは除外する
    if ! echo "$slug" | grep -Eq "$SLUG_RE"; then
      report ERROR slug-format "$b" "notes/$slug.md" "ファイル名が slug 規則(^[a-z0-9][a-z0-9-]*\$)に違反"
      continue
    fi
    # リンク抽出はコード領域を除いた地の文から行う(記法を説明するページのコード内の例示を
    # 実リンクと誤認し、link-format / broken-link / one-way-link を誤検出しないため)
    prose=$(body_prose "$f")
    # link-format: /notes/ へのリンクのうち正規形式(空 slug・規則外 slug 等)でないもの
    bad_link=$(grep -o '](/notes/[^)]*)' <<< "$prose" | grep -Ev '^\]\(/notes/[a-z0-9][a-z0-9-]*\.md\)$' || true)
    [ -n "$bad_link" ] &&
      report ERROR link-format "$b" "notes/$slug.md" "リンクが正規形式([label](/notes/<slug>.md))でない"
    # shellcheck disable=SC2013 # 行ではなく個々のリンク先(単語)を反復する意図的な word-split。slug は [a-z0-9-] のみで空白を含まない
    # sort -u: 同じリンク先への重複リンクで broken-link / one-way-link を重複報告しない
    for to in $(grep -o '](/notes/[a-z0-9][a-z0-9-]*\.md)' <<< "$prose" | sed 's|](/notes/||; s|\.md)||' | sort -u); do
      [ "$to" = "$slug" ] && continue   # 自己リンクは相互リンク網(orphan/one-way-link)に数えない
      printf '%s>%s\n' "$slug" "$to" >> "$LINKS_FILE"
      [ -f "$b/notes/$to.md" ] || report ERROR broken-link "$b" "notes/$slug.md" "リンク先が存在しない: /notes/${to}.md"
    done
    if [ "$has_index" = 1 ]; then
      grep -qF "(/notes/$slug.md)" "$b/index.md" || report ERROR index-miss "$b" "notes/$slug.md" "index.md に未記載"
    fi
  done
  # one-way-link / orphan(存在するページ間のみ対象。slug は [a-z0-9-] のみなので正規表現エスケープ不要)
  for f in "$b"/notes/*.md; do
    [ -e "$f" ] || continue
    slug=$(basename "$f" .md)
    echo "$slug" | grep -Eq "$SLUG_RE" || continue   # slug-format 違反は報告済み
    while read -r to; do
      [ -n "$to" ] || continue
      [ -f "$b/notes/$to.md" ] || continue
      grep -qx "$to>$slug" "$LINKS_FILE" ||
        report ERROR one-way-link "$b" "notes/$slug.md" "→ ${to} への片方向リンク(${to} 側に逆リンクなし)"
    done < <(grep "^$slug>" "$LINKS_FILE" 2>/dev/null | sed "s/^$slug>//")
    t=$(fm_get "$f" type)
    if [ "$t" = "note" ]; then
      grep -q ">$slug\$" "$LINKS_FILE" ||
        report ERROR orphan "$b" "notes/$slug.md" "他のどのページからも被リンクなし"
    fi
  done
  if [ "$has_index" = 1 ]; then
    # index-format: frontmatter は okf_version のみ / エントリ行の書式
    # pipefail 下で「パイプ全体の終了ステータス」を条件に使うと、上流 grep が SIGPIPE で
    # 非0終了した場合に grep -q . が成功していても && が発火しないことがある(データ依存の不具合)。
    # そのため必ずコマンド置換で結果を変数へ捕捉してから空文字判定する。
    local bad_fm bad_entry
    bad_fm=$(fm_block "$b/index.md" | grep -Ev '^okf_version:')
    [ -n "$bad_fm" ] &&
      report ERROR index-format "$b" "index.md" "frontmatter に okf_version 以外のキーがある"
    # okf_version は bundle マーカーそのもの。欠落すると bundle-locate.sh が発見できなくなるのに
    # lint は clean と報告する偽陰性になるため、必ず検査する(frontmatter ごと無い場合も検出)
    # キーの有無と値の空を分けて判定する(bundle-locate.sh はキーの存在だけで bundle とみなすため、
    # 値が空でも発見はされる。「発見できない」はキー自体が無い場合に限る)
    local okf_key
    okf_key=$(awk '{ sub(/\r$/, "") } /^---$/{n++; next} n>=2{exit} n==1 && /^okf_version:/{print "found"; exit}' "$b/index.md")
    if [ -z "$okf_key" ]; then
      report ERROR index-format "$b" "index.md" "frontmatter に okf_version がない(bundle マーカー喪失: bundle-locate が発見できない)"
    elif [ -z "$(fm_get "$b/index.md" okf_version)" ]; then
      report ERROR index-format "$b" "index.md" "okf_version の値が空(bundle としては発見されるが OKF バージョンを判別できない)"
    fi
    # 候補は - 箇条書きも含めて拾う(- で書かれた index を無検査で素通りさせない)
    bad_entry=$(tr -d '\r' < "$b/index.md" | grep -E '^[*-] ' | grep -Ev '^\* \[[^]]+\]\(/notes/[a-z0-9][a-z0-9-]*\.md\) - .+')
    [ -n "$bad_entry" ] &&
      report ERROR index-format "$b" "index.md" "エントリ行が「* [title](/notes/slug.md) - description」形式でない(箇条書き記号は * のみ)"
    # index-dangling: 存在しないページを記載したエントリ(ページ統合・削除の取り残し)。
    # broken-link は notes/ 内のリンクのみ、index-miss は note→index の一方向のみを見るため、
    # index→note 方向の実在確認はここで行う
    local entry_to
    while read -r entry_to; do
      [ -n "$entry_to" ] || continue
      [ -f "$b/notes/$entry_to.md" ] ||
        report ERROR index-dangling "$b" "index.md" "存在しないページを記載: /notes/${entry_to}.md"
    done < <(grep -o '](/notes/[a-z0-9][a-z0-9-]*\.md)' "$b/index.md" | sed 's|](/notes/||; s|\.md)||' | sort -u)
  fi
  if [ "$has_log" = 1 ]; then
    # log-format: 日付見出しの形式と降順(同様にコマンド置換で捕捉してから判定)
    local bad_date
    # 行末 CR は剥がしてから照合する($ アンカーが CRLF 行に一致しないため)
    bad_date=$(tr -d '\r' < "$b/log.md" | grep -E '^## ' | grep -Ev '^## [0-9]{4}-[0-9]{2}-[0-9]{2}$')
    [ -n "$bad_date" ] &&
      report ERROR log-format "$b" "log.md" "日付見出しが ## YYYY-MM-DD 形式でない"
    local dates sorted
    dates=$(tr -d '\r' < "$b/log.md" | grep -E '^## [0-9]{4}-[0-9]{2}-[0-9]{2}$' | sed 's/^## //')
    sorted=$(echo "$dates" | sort -r)
    [ "$dates" = "$sorted" ] ||
      report ERROR log-format "$b" "log.md" "日付見出しが新しい順(降順)でない"
  fi
  # concept-candidate: 同一タグ5件以上を非 concept ページが共有 + そのタグを持つ concept ページがない
  local tag has_concept
  for tag in $(for f in "$b"/notes/*.md; do
      [ -e "$f" ] || continue
      [ "$(fm_get "$f" type)" = "concept" ] && continue
      fm_tags "$f"
    done | grep -v '^$' | sort | uniq -c | awk '$1>=5{print $2}'); do
    has_concept=0
    for f in "$b"/notes/*.md; do
      [ -e "$f" ] || continue
      [ "$(fm_get "$f" type)" = "concept" ] || continue
      # grep -q の早期 exit による SIGPIPE + pipefail の偽陰性を避けるため全量捕捉してから判定
      tag_hit=$(fm_tags "$f" | grep -Fx -- "$tag" || true)
      [ -n "$tag_hit" ] && { has_concept=1; break; }
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
