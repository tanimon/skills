#!/usr/bin/env bash
# evergreen-wiki/scripts/lib.sh — frontmatter・本文抽出の共通関数(正準形式前提)
# 改行: CRLF のファイルも LF と同じに解釈する。各 awk の先頭規則 { sub(/\r$/, "") } で行末の CR を
# 剥がす(YAML・Markdown とも CRLF は妥当。剥がさないと /^---$/ 等が一致せず、query が黙って
# ページを取りこぼす)。tr -d '\r' | awk のパイプにはしない(下流 awk の早期 exit で SIGPIPE になる)
# fm_block <file>: 最初の --- ペアに挟まれた frontmatter 本体を出力
fm_block() { awk '{ sub(/\r$/, "") } /^---$/{n++; next} n==1{print} n>=2{exit}' "$1"; }
# AWK_SCALAR: YAML スカラー値の正規化関数 scalar(v) の awk 定義。awk プログラムの先頭に連結して使う。
# - 値全体を対で囲む引用符("/')は剥がす(片側だけの引用符は値の一部とみなし剥がさない)
# - インラインコメント(空白 + # 以降)を除去する。引用符で始まる値では閉じ引用符より後ろのみ対象
#   (YAML ではコメントの # の直前に空白が必要なので、"C#" や C#の話 の # は値の一部として残る)
# shellcheck disable=SC2016 # awk プログラムのリテラル。シェル展開の意図はない
AWK_SCALAR='
function scalar(v,    q, last, i) {
  q = substr(v, 1, 1)
  if (q == "\"" || q == "\047") {
    last = 0
    for (i = length(v); i > 1; i--) if (substr(v, i, 1) == q) { last = i; break }
    if (last > 1 && substr(v, last + 1) ~ /^[ \t]*(#.*)?$/) return substr(v, 2, last - 2)
    return v
  }
  sub(/[ \t]+#.*$/, "", v); sub(/[ \t]+$/, "", v)
  return v
}'
# fm_get <file> <key>: トップレベルのスカラー値を scalar() で正規化して出力(なければ空)。
# パイプを使わず単一 awk でファイルを直接読む。fm_block | awk のパイプ構成だと、下流 awk の
# 早期 exit 後に上流が書き込むと SIGPIPE(141)になり、pipefail 下で呼び出し側が黙って死ぬため。
fm_get() {
  awk -v k="$2" "$AWK_SCALAR"'
    { sub(/\r$/, "") }
    /^---$/{n++; next} n>=2{exit}
    n==1 && index($0, k":")==1 {
      sub(/^[^:]*:[ ]*/, "")
      print scalar($0); exit
    }' "$1"
}
# unquote <value>: 値全体を対で囲む引用符("/')を剥がす(fm_get と同じ規則。片側だけなら剥がさない)
unquote() {
  local v=$1
  case "$v" in \"*\"|\'*\') [ ${#v} -ge 2 ] && v=${v:1:${#v}-2} ;; esac
  printf '%s\n' "$v"
}
# body_prose <file>: frontmatter 以降の本文(frontmatter が無ければファイル全体)から、コード領域を除いた地の文だけを出力する。
# 除外対象は fenced code block(``` / ~~~。フェンスは同種の記号でのみ閉じる: ``` 内の ~~~ 行は
# 内容として除外を継続する)・4スペース/タブのインデントコード行・インラインコード。
# 脚注・リンクの抽出で、コード内の記法の例示を実体と誤認しないために使う
# (インデント除外の代償として4スペース以上インデントされたネストリスト内の参照は拾えないが、
# ERROR の偽陽性より安い。フェンス長・info string の CommonMark 細則までは判定しない近似である)
# フェンスは CommonMark と同じく行頭0〜3スペースのインデントを許す(リスト項目内の "  ```" を
# 取りこぼすと中身の文字クラス [^a-z] 等が脚注と誤認され footnote-ref の偽陽性 ERROR になる)。
# インラインコードは ``...``(内部に単一バッククォートを含みうる)を先に除去してから `...` を除去する
# (逆順だと `` の組が空スパンとして先に消費され、中身が地の文に露出する)
# shellcheck disable=SC2016 # sed のバッククォートはインラインコード除去のリテラル。展開意図はない
body_prose() {
  awk '{ sub(/\r$/, "") } NR==1 && $0!="---"{n=2} /^---$/ && n<2{n++; next} n>=2' "$1" \
    | awk '/^ ? ? ?(```|~~~)/ { s = $0; sub(/^ +/, "", s); t = substr(s, 1, 1)
                                if (fence == "") fence = t
                                else if (fence == t) fence = ""
                                next }
           fence == "" && !/^(    |\t)/' \
    | sed -E 's/``([^`]|`[^`])*``//g; s/`[^`]*`//g'
}
# fm_tags <file>: frontmatter tags(インラインフロー形式)の各要素を1行1タグで出力する。
# 要素を囲む引用符("/')は剥がす(["a", "b"] も OKF 的に妥当なため。剥がさないと
# --tag や concept-candidate の照合が無音で外れる)
fm_tags() {
  fm_get "$1" tags | tr -d '[]' | tr ',' '\n' | sed 's/^ *//; s/ *$//' | while IFS= read -r tag; do unquote "$tag"; done
}
