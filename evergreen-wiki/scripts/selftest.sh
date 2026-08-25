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
# Concepts

# Entities

# Notes
* [パイプは exit code を隠す](/notes/pipe-exit-code.md) - パイプ末尾の exit code だけが返る
* [set -o pipefail の使いどころ](/notes/pipefail-usage.md) - パイプ中間の失敗を検出する
EOF
  cat > "$d/log.md" <<'EOF'
# Update Log

## 2026-08-25
* 新規: pipe-exit-code, pipefail-usage
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
* [set -o pipefail の使いどころ](/notes/pipefail-usage.md)
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
* [パイプは exit code を隠す](/notes/pipe-exit-code.md)
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
* [パイプは exit code を隠す](/notes/pipe-exit-code.md)
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

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
