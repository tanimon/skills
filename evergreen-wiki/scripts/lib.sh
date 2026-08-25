#!/usr/bin/env bash
# evergreen-wiki/scripts/lib.sh — frontmatter 抽出の共通関数(正準形式前提)
# fm_block <file>: 最初の --- ペアに挟まれた frontmatter 本体を出力
fm_block() { awk '/^---$/{n++; next} n==1{print} n>=2{exit}' "$1"; }
# fm_get <file> <key>: トップレベルのスカラー値を出力(なければ空)
fm_get() { fm_block "$1" | awk -v k="$2" 'index($0, k":")==1 {sub(/^[^:]*:[ ]*/, ""); print; exit}'; }
