#!/usr/bin/env bash
# evergreen-wiki/scripts/lib.sh — frontmatter・本文抽出の共通関数(正準形式前提)
# fm_block <file>: 最初の --- ペアに挟まれた frontmatter 本体を出力
fm_block() { awk '/^---$/{n++; next} n==1{print} n>=2{exit}' "$1"; }
# fm_get <file> <key>: トップレベルのスカラー値を出力(なければ空)。値を対で囲む引用符("/')は
# 剥がす(片側だけの引用符は値の一部とみなし剥がさない)。
# パイプを使わず単一 awk でファイルを直接読む。fm_block | awk のパイプ構成だと、下流 awk の
# 早期 exit 後に上流が書き込むと SIGPIPE(141)になり、pipefail 下で呼び出し側が黙って死ぬため。
fm_get() {
  awk -v k="$2" '
    /^---$/{n++; next} n>=2{exit}
    n==1 && index($0, k":")==1 {
      sub(/^[^:]*:[ ]*/, "")
      if ($0 ~ /^".*"$/ || $0 ~ /^'\''.*'\''$/) { sub(/^["'\'']/, ""); sub(/["'\'']$/, "") }
      print; exit
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
  awk 'NR==1 && $0!="---"{n=2} /^---$/ && n<2{n++; next} n>=2' "$1" \
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
