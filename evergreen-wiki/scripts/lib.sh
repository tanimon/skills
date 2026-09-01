#!/usr/bin/env bash
# evergreen-wiki/scripts/lib.sh — frontmatter 抽出の共通関数(正準形式前提)
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
