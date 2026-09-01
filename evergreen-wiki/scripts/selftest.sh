#!/usr/bin/env bash
# evergreen-wiki/scripts/selftest.sh — fixture bundle を生成して各スクリプトの挙動を検証する回帰テスト
set -uo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0

ok()   { PASS=$((PASS+1)); }
ng()   { FAIL=$((FAIL+1)); echo "FAIL: $1" >&2; }
assert_contains()     { echo "$1" | grep -q -- "$2" && ok || ng "expect contains [$2] in: $1"; }
assert_not_contains() { echo "$1" | grep -q -- "$2" && ng "expect NOT contains [$2] in: $1" || ok; }
assert_exit()         { [ "$1" -eq "$2" ] && ok || ng "expect exit $2, got $1 ($3)"; }

# 正常系 fixture bundle を生成する(正準形式。conventions.md 第3・7章に一致)
make_bundle() {
  local d="$1"; mkdir -p "$d/notes"
  cat > "$d/index.md" <<'EOF'
---
okf_version: "0.2"
---
# concept

# entity

# note
* [パイプは exit code を隠す](/notes/pipe-exit-code.md) - パイプ末尾の exit code だけが返る
* [set -o pipefail の使いどころ](/notes/pipefail-usage.md) - パイプ中間の失敗を検出する
EOF
  cat > "$d/log.md" <<'EOF'
# Update Log

## 2026-08-25

- 新規: pipe-exit-code, pipefail-usage
EOF
  cat > "$d/notes/pipe-exit-code.md" <<'EOF'
---
type: note
title: パイプは exit code を隠す
description: パイプ末尾の exit code だけが返る
tags: [shell, error-handling]
sources:
  - resource: "https://example.com/pr/1"
generated:
  by: claude-code/claude-fable-5
  at: 2026-08-25T00:00:00Z
---
# パイプは exit code を隠す

本文。

## 関連

- [set -o pipefail の使いどころ](/notes/pipefail-usage.md)
EOF
  cat > "$d/notes/pipefail-usage.md" <<'EOF'
---
type: note
title: set -o pipefail の使いどころ
description: パイプ中間の失敗を検出する
tags: [shell]
sources:
  - resource: "2026-08-25 デバッグセッション"
generated:
  by: claude-code/claude-fable-5
  at: 2026-08-25T00:00:00Z
verified:
  - by: human:reviewer
    at: 2026-08-25T01:00:00Z
---
# set -o pipefail の使いどころ

本文。

## 関連

- [パイプは exit code を隠す](/notes/pipe-exit-code.md)
EOF
}

echo "=== bundle-locate ==="
# user bundle のみ存在
make_bundle "$WORK/userkb"
mkdir -p "$WORK/proj/sub"
out=$(EVERGREEN_USER_BUNDLE="$WORK/userkb" "$SCRIPT_DIR/bundle-locate.sh" --root "$WORK/proj")
assert_contains "$out" "user	$WORK/userkb"
assert_not_contains "$out" "project"
# project bundle を追加(root 配下の docs/knowledge)
make_bundle "$WORK/proj/docs/knowledge"
out=$(EVERGREEN_USER_BUNDLE="$WORK/userkb" "$SCRIPT_DIR/bundle-locate.sh" --root "$WORK/proj")
assert_contains "$out" "project	$WORK/proj/docs/knowledge"
# --scope フィルタ
out=$(EVERGREEN_USER_BUNDLE="$WORK/userkb" "$SCRIPT_DIR/bundle-locate.sh" --root "$WORK/proj" --scope user)
assert_not_contains "$out" "project"
# okf_version を持たない index.md は bundle ではない
mkdir -p "$WORK/proj2/docs"; echo "# just a doc" > "$WORK/proj2/docs/index.md"
out=$(EVERGREEN_USER_BUNDLE="$WORK/nonexistent" "$SCRIPT_DIR/bundle-locate.sh" --root "$WORK/proj2"); rc=$?
assert_exit "$rc" 0 "bundle なしでも exit 0"
assert_not_contains "$out" "proj2"
# 除外ディレクトリ(node_modules)配下は発見しない
make_bundle "$WORK/proj3/node_modules/pkg/knowledge"
out=$(EVERGREEN_USER_BUNDLE="$WORK/nonexistent" "$SCRIPT_DIR/bundle-locate.sh" --root "$WORK/proj3")
assert_not_contains "$out" "node_modules"
# --root に存在しないディレクトリを渡しても exit 0(git toplevel も abspath も失敗するケース)
out=$(EVERGREEN_USER_BUNDLE="$WORK/nonexistent" "$SCRIPT_DIR/bundle-locate.sh" --root "$WORK/no-such-dir"); rc=$?
assert_exit "$rc" 0 "存在しない --root でも exit 0"

echo "=== wiki-query ==="
Q="$SCRIPT_DIR/wiki-query.sh"
B="$WORK/userkb"
# --type で絞り込み
out=$("$Q" --bundle "$B" --type note)
assert_contains "$out" "pipe-exit-code"
assert_contains "$out" "pipefail-usage"
# --tag で絞り込み(error-handling を持つのは1件)
out=$("$Q" --bundle "$B" --tag error-handling)
assert_contains "$out" "pipe-exit-code"
assert_not_contains "$out" "pipefail-usage"
# --slug 完全一致
out=$("$Q" --bundle "$B" --slug pipefail-usage)
assert_contains "$out" "pipefail-usage	note	stable	パイプ中間の失敗を検出する"
assert_not_contains "$out" "pipe-exit-code"
# --keyword は本文も対象
out=$("$Q" --bundle "$B" --keyword "pipefail")
assert_contains "$out" "pipefail-usage"
# 複数 bundle 横断(--bundle 2回指定)
make_bundle "$WORK/kb2"
out=$("$Q" --bundle "$B" --bundle "$WORK/kb2" --tag shell)
assert_contains "$out" "$B	pipe-exit-code"
assert_contains "$out" "$WORK/kb2	pipe-exit-code"
# bundle が1件もない場合も exit 0(空出力)
out=$(cd "$WORK/proj2" && EVERGREEN_USER_BUNDLE="$WORK/nonexistent" "$Q" --keyword anything); rc=$?
assert_exit "$rc" 0 "bundle なしの query は exit 0"
assert_not_contains "$out" "pipe-exit-code"
# SIGPIPE 回帰(M1): 巨大かつ閉じていない frontmatter の note が混在しても query は
# rc=141・出力ゼロで黙って死なず、同 bundle の正常な note も出力する
BIGKB="$WORK/bigkb"; make_bundle "$BIGKB"
{ printf -- '---\ntype: note\ntitle: big unclosed\n'
  i=0; while [ "$i" -lt 4000 ]; do printf 'x%04d: filler-value-line-for-sigpipe-regression\n' "$i"; i=$((i+1)); done
} > "$BIGKB/notes/unclosed-fm.md"
out=$("$Q" --bundle "$BIGKB" --type note); rc=$?
assert_exit "$rc" 0 "巨大・未閉鎖 frontmatter が混在しても query は exit 0"
assert_contains "$out" "pipe-exit-code"
# SIGPIPE 回帰(M1 派生): tags が巨大でも --tag は先頭タグを取りこぼさない
{ printf -- '---\ntype: note\ntitle: many tags\ndescription: tags 大量\ntags: ['
  i=0; while [ "$i" -lt 8000 ]; do printf 'tag-%04d, ' "$i"; i=$((i+1)); done
  printf 'tag-last]\n---\n# many tags\n'
} > "$BIGKB/notes/many-tags.md"
out=$("$Q" --bundle "$BIGKB" --tag tag-0000); rc=$?
assert_exit "$rc" 0 "巨大 tags でも --tag は exit 0"
assert_contains "$out" "many-tags"

echo "=== wiki-lint (single-file checks) ==="
L="$SCRIPT_DIR/wiki-lint.sh"
# 異常系 fixture bundle
BAD="$WORK/badkb"; make_bundle "$BAD"
# frontmatter なし
printf '# no frontmatter\n' > "$BAD/notes/no-fm.md"
# type 空
cat > "$BAD/notes/empty-type.md" <<'EOF'
---
type:
title: type が空
---
# type が空
EOF
# actor 記法違反 + verified が単一マッピング(正準形違反) + 検証失効 + 期限切れ
cat > "$BAD/notes/bad-actor.md" <<'EOF'
---
type: note
title: 不正 actor
description: actor 記法と正準形の違反サンプル
tags: [shell]
generated:
  by: just a name
  at: 2026-08-25T02:00:00Z
verified:
  by: human:reviewer
  at: 2026-08-25T01:00:00Z
status: stable
stale_after: 2020-01-01T00:00:00Z
---
# 不正 actor

## 関連

- [パイプは exit code を隠す](/notes/pipe-exit-code.md)
EOF
out=$("$L" --bundle "$BAD"); rc=$?
assert_exit "$rc" 1 "ERROR があれば exit 1"
assert_contains "$out" "ERROR	conformance-frontmatter"
assert_contains "$out" "ERROR	conformance-type"
assert_contains "$out" "ERROR	actor-format"
assert_contains "$out" "SUGGEST	canonical-form"
assert_contains "$out" "SUGGEST	stale"
assert_contains "$out" "SUGGEST	verify-stale"
# 正常系 bundle では単一ファイル検査の ERROR/SUGGEST が出ない
out=$("$L" --bundle "$WORK/userkb"); rc=$?
assert_exit "$rc" 0 "正常系は exit 0"
assert_not_contains "$out" "conformance-"
assert_not_contains "$out" "actor-format"
assert_not_contains "$out" "canonical-form"

echo "=== wiki-lint (cross-file checks) ==="
XB="$WORK/xkb"; make_bundle "$XB"
# broken-link + orphan + index-miss: 存在しないページへリンクし、誰からもリンクされず、index 未記載
cat > "$XB/notes/orphan-note.md" <<'EOF'
---
type: note
title: 孤立ノート
description: 誰からもリンクされない
tags: [misc]
generated:
  by: claude-code/claude-fable-5
  at: 2026-08-25T00:00:00Z
---
# 孤立ノート

## 関連

- [存在しないページ](/notes/no-such-page.md)
- [パイプは exit code を隠す](/notes/pipe-exit-code.md)
EOF
# log.md を不正な形式に(日付見出しが昇順)
cat > "$XB/log.md" <<'EOF'
# Update Log

## 2026-08-24

- 古いエントリ

## 2026-08-25

- 新しいエントリ
EOF
out=$("$L" --bundle "$XB"); rc=$?
assert_exit "$rc" 1 "横断検査の ERROR で exit 1"
assert_contains "$out" "ERROR	broken-link"
assert_contains "$out" "ERROR	orphan	$XB	notes/orphan-note.md"
assert_contains "$out" "ERROR	index-miss"
assert_contains "$out" "ERROR	log-format"
# orphan-note → pipe-exit-code は片方向(pipe-exit-code 側に逆リンクなし)
assert_contains "$out" "ERROR	one-way-link"
# 正常系 bundle は横断検査も無違反
out=$("$L" --bundle "$WORK/userkb"); rc=$?
assert_exit "$rc" 0 "正常系は exit 0"
assert_not_contains "$out" "broken-link"
assert_not_contains "$out" "orphan"
assert_not_contains "$out" "one-way-link"
# concept-candidate: 同一タグ5件・concept なし
CC="$WORK/cckb"; make_bundle "$CC"
for i in 1 2 3 4 5; do
cat > "$CC/notes/tagged-$i.md" <<EOF
---
type: note
title: tagged $i
description: 同一タグのサンプル $i
tags: [hot-topic]
generated:
  by: claude-code/claude-fable-5
  at: 2026-08-25T00:00:00Z
---
# tagged $i

## 関連
EOF
done
out=$("$L" --bundle "$CC" 2>/dev/null) || true
assert_contains "$out" "SUGGEST	concept-candidate"
assert_contains "$out" "hot-topic"
# --json は JSONL を出す
out=$("$L" --bundle "$XB" --json 2>/dev/null) || true
assert_contains "$out" '"severity":"ERROR"'
assert_contains "$out" '"check":"broken-link"'
# index-format / log-format: frontmatter に余分なキー・エントリ行崩れ・日付見出しの形式違反
IF="$WORK/ifkb"; make_bundle "$IF"
cat > "$IF/index.md" <<'EOF'
---
okf_version: "0.2"
title: bad
---
# Notes
* [壊れた行](/notes/pipe-exit-code.md)
EOF
cat > "$IF/log.md" <<'EOF'
# Update Log

## 2026/08/25
* 形式違反
EOF
out=$("$L" --bundle "$IF"); rc=$?
assert_exit "$rc" 1 "index-format/log-format で exit 1"
assert_contains "$out" "ERROR	index-format"
assert_contains "$out" "ERROR	log-format"
# conformance-structure: index.md も log.md も無い bundle は ERROR + exit 1(偽陰性の回帰防止)
NOFILE="$WORK/nofilekb"; mkdir -p "$NOFILE/notes"
out=$("$L" --bundle "$NOFILE"); rc=$?
assert_exit "$rc" 1 "予約ファイル不存在で exit 1"
assert_contains "$out" "ERROR	conformance-structure"

echo "=== wiki-lint (review regressions) ==="
# M2: 引用符付き stale_after(未来)は stale と報告しない(引用符は全数字より小さく、
# 剥がさないと文字列比較で永久に stale になる)
QK="$WORK/quotedkb"; make_bundle "$QK"
cat > "$QK/notes/quoted-stale.md" <<'EOF'
---
type: note
title: quoted stale
description: 引用符付き stale_after
tags: [misc]
status: stable
stale_after: "2099-01-01T00:00:00Z"
---
# quoted stale
EOF
out=$("$L" --bundle "$QK" 2>/dev/null) || true
assert_not_contains "$out" "SUGGEST	stale"
# M3: slug 規則外のファイルは slug-format ERROR 1件で報告し、相互リンク検査の誤検出連鎖
# (orphan / one-way-link)を起こさない
SK="$WORK/slugkb"; make_bundle "$SK"
cat > "$SK/notes/Foo_Bar.md" <<'EOF'
---
type: note
title: bad slug
description: slug 規則外
tags: [misc]
---
# bad slug

## 関連

- [パイプは exit code を隠す](/notes/pipe-exit-code.md)
EOF
# link-format: 空 slug へのリンクは正規形式違反として検出する
cat > "$SK/notes/bad-link-note.md" <<'EOF'
---
type: note
title: bad link
description: 空 slug リンク
tags: [misc]
---
# bad link

## 関連

- [x](/notes/.md)
EOF
out=$("$L" --bundle "$SK" 2>/dev/null) || true
assert_contains "$out" "ERROR	slug-format	$SK	notes/Foo_Bar.md"
assert_not_contains "$out" "one-way-link	$SK	notes/Foo_Bar.md"
assert_not_contains "$out" "orphan	$SK	notes/Foo_Bar.md"
assert_contains "$out" "ERROR	link-format	$SK	notes/bad-link-note.md"
# M4: --json は detail 内の " と \ をエスケープし、壊れた JSON を出さない
JK="$WORK/jsonkb"; make_bundle "$JK"
cat > "$JK/notes/json-escape.md" <<'EOF'
---
type: note
title: json escape
description: actor に引用符とバックスラッシュ
tags: [misc]
generated:
  by: bad "quoted\actor
  at: 2026-08-25T00:00:00Z
---
# json escape
EOF
out=$("$L" --bundle "$JK" --json 2>/dev/null) || true
# 期待する生出力: ...bad \"quoted\\actor...(BRE では \\ = リテラル \)
assert_contains "$out" 'bad \\"quoted\\\\actor'
# M5: - 箇条書きの index.md も index-format 検査の対象になる(素通りしない)
IF2="$WORK/if2kb"; make_bundle "$IF2"
cat > "$IF2/index.md" <<'EOF'
---
okf_version: "0.2"
---
# note
- [パイプは exit code を隠す](/notes/pipe-exit-code.md) - パイプ末尾の exit code だけが返る
EOF
out=$("$L" --bundle "$IF2" 2>/dev/null) || true
assert_contains "$out" "ERROR	index-format"
# L1: 自己リンクだけの note は orphan をすり抜けない
SL="$WORK/selfkb"; make_bundle "$SL"
cat > "$SL/notes/self-link.md" <<'EOF'
---
type: note
title: self link
description: 自己リンクのみ
tags: [misc]
---
# self link

## 関連

- [self](/notes/self-link.md)
EOF
out=$("$L" --bundle "$SL" 2>/dev/null) || true
assert_contains "$out" "ERROR	orphan	$SL	notes/self-link.md"
# L3: sources の単一マッピングも canonical-form で検出する
CS="$WORK/srckb"; make_bundle "$CS"
cat > "$CS/notes/single-sources.md" <<'EOF'
---
type: note
title: single sources
description: sources が単一マッピング
tags: [misc]
sources:
  resource: "https://example.com/x"
---
# single sources
EOF
out=$("$L" --bundle "$CS" 2>/dev/null) || true
assert_contains "$out" "SUGGEST	canonical-form	$CS	notes/single-sources.md	sources が単一マッピング"

echo "=== review round 3 regressions ==="
# R1: 読み取り不可のサブディレクトリがあっても bundle-locate は exit 1 で死なず、
# 発見済み bundle を無音で取りこぼさない(find の permission-denied 非0終了 + pipefail 起因)
PD="$WORK/permdenied"; make_bundle "$PD/docs/knowledge"
mkdir -p "$PD/secret"; chmod 000 "$PD/secret"
out=$(EVERGREEN_USER_BUNDLE="$WORK/nonexistent" "$SCRIPT_DIR/bundle-locate.sh" --root "$PD"); rc=$?
chmod 755 "$PD/secret"
assert_exit "$rc" 0 "読み取り不可ディレクトリがあっても exit 0"
assert_contains "$out" "project	$PD/docs/knowledge"
# R2: okf_version を持たない index.md は index-format ERROR(bundle マーカー喪失の検出)
NV="$WORK/noverkb"; make_bundle "$NV"
printf -- '---\ntitle: not a marker\n---\n# note\n' > "$NV/index.md"
out=$("$L" --bundle "$NV" 2>/dev/null); rc=$?
assert_exit "$rc" 1 "okf_version 欠落で exit 1"
assert_contains "$out" "frontmatter に okf_version がない"
# R2 派生: frontmatter ごと無い index.md も同様に検出する
printf '# just markdown\n' > "$NV/index.md"
out=$("$L" --bundle "$NV" 2>/dev/null); rc=$?
assert_exit "$rc" 1 "frontmatter なし index.md で exit 1"
assert_contains "$out" "frontmatter に okf_version がない"
# R3: index.md の宙ぶらりんエントリ(存在しないページへの参照)は index-dangling ERROR
DG="$WORK/danglingkb"; make_bundle "$DG"
printf '* [削除済みページ](/notes/deleted-note.md) - もう存在しない\n' >> "$DG/index.md"
out=$("$L" --bundle "$DG"); rc=$?
assert_exit "$rc" 1 "宙ぶらりん index エントリで exit 1"
assert_contains "$out" "ERROR	index-dangling	$DG	index.md"
assert_contains "$out" "/notes/deleted-note.md"
# R4: --keyword は固定文字列として検索する(正規表現メタ文字で grep が黙って失敗しない)
FK="$WORK/fixedkb"; make_bundle "$FK"
cat > "$FK/notes/regex-chars.md" <<'EOF'
---
type: note
title: regex chars
description: 本文に a[b を含む
tags: [misc]
---
# regex chars

本文に a[b を含む。
EOF
out=$("$Q" --bundle "$FK" --keyword 'a[b' 2>&1); rc=$?
assert_exit "$rc" 0 "正規表現メタ文字を含む keyword でも exit 0"
assert_contains "$out" "regex-chars"
# R5: verified の at: 抽出は by: 行の値に "at:" を含む actor を拾わない
# (拾うと sort 汚染で verify-stale の偽陰性になる)
VA="$WORK/atkb"; make_bundle "$VA"
cat > "$VA/notes/at-actor.md" <<'EOF'
---
type: note
title: at actor
description: by の値に at: を含む actor
tags: [misc]
generated:
  by: claude-code/claude-fable-5
  at: 2026-08-25T02:00:00Z
verified:
  - by: process:legacy-at: zzz
    at: 2026-08-25T01:00:00Z
---
# at actor
EOF
out=$("$L" --bundle "$VA" 2>/dev/null) || true
assert_contains "$out" "SUGGEST	verify-stale"

echo "=== sources id / footnote ==="
# S1: id/title 付き正準 sources + 一致する脚注はエラーなし。
# code block・インラインコード内の文字クラス [^...] は脚注とみなさない
FN="$WORK/fnkb"; make_bundle "$FN"
cat > "$FN/notes/with-footnote.md" <<'EOF'
---
type: note
title: with footnote
description: id 付き sources と脚注
tags: [misc]
sources:
  - id: pr-1
    resource: "https://example.com/pr/1"
    title: "Example PR 1"
generated:
  by: claude-code/claude-fable-5
  at: 2026-08-25T00:00:00Z
---
# with footnote

主張には出典が付く。[^pr-1]

`grep -o '[^a-z]'` のような文字クラスは脚注とみなさない。

```
regex sample: [^0-9]+
```

~~~
tilde fence sample: [^x-z]+
~~~

    indented code sample: [^a-f]+

[^pr-1]: Example PR 1

## 関連
EOF
out=$("$L" --bundle "$FN" 2>/dev/null) || true
assert_not_contains "$out" "footnote-ref"
assert_not_contains "$out" "source-id"
assert_not_contains "$out" "canonical-form"
# S2: id 始まりの単一マッピングも canonical-form で検出する
cat > "$FN/notes/single-id.md" <<'EOF'
---
type: note
title: single id
description: id 始まりの単一マッピング
tags: [misc]
sources:
  id: x-1
  resource: "https://example.com/x"
---
# single id
EOF
out=$("$L" --bundle "$FN" 2>/dev/null) || true
assert_contains "$out" "SUGGEST	canonical-form	$FN	notes/single-id.md	sources が単一マッピング"
# S3: 対応する sources[].id のない脚注ラベルは footnote-ref ERROR
cat > "$FN/notes/dangling-footnote.md" <<'EOF'
---
type: note
title: dangling footnote
description: sources に無い脚注ラベル
tags: [misc]
sources:
  - resource: "https://example.com/y"
---
# dangling footnote

出典不明の主張。[^no-such-id]
EOF
out=$("$L" --bundle "$FN" 2>/dev/null); rc=$?
assert_exit "$rc" 1 "footnote-ref で exit 1"
assert_contains "$out" "ERROR	footnote-ref	$FN	notes/dangling-footnote.md"
assert_contains "$out" "no-such-id"
# S4: id の slug 規則違反は SUGGEST(OKF 許容原則)、ページ内重複は ERROR(結合キーの曖昧化)
cat > "$FN/notes/bad-ids.md" <<'EOF'
---
type: note
title: bad ids
description: id の規則違反と重複
tags: [misc]
sources:
  - id: Bad_ID
    resource: "https://example.com/a"
  - id: dup-key
    resource: "https://example.com/b"
  - id: dup-key
    resource: "https://example.com/c"
---
# bad ids
EOF
out=$("$L" --bundle "$FN" 2>/dev/null) || true
assert_contains "$out" "SUGGEST	source-id-format	$FN	notes/bad-ids.md	sources の id が slug 規則"
assert_contains "$out" "に違反: Bad_ID"
assert_contains "$out" "ERROR	source-id-dup	$FN	notes/bad-ids.md	sources の id がページ内で重複: dup-key"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
