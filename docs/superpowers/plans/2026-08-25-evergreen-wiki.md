# evergreen-wiki Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** OKF v0.2 完全準拠のナレッジベース(bundle)を user/project scope で構築・管理する skill `evergreen-wiki/` を本リポジトリに実装する。

**Architecture:** skill は SKILL.md(要点)+ references(規約・手順)+ bash スクリプト群(bundle 発見・query・lint)で構成。bundle は `index.md`/`log.md`/`notes/<slug>.md` の OKF 構造。スクリプトは正準シリアライズ形式(conventions.md で規範化)を前提に行アンカーのパターンマッチで動く。

**Tech Stack:** bash + 標準ツール(grep/awk/sed/find)のみ。外部依存なし。テストは自前の `selftest.sh`(fixture 生成 + アサーション)。

**Spec:** `docs/superpowers/specs/2026-08-25-evergreen-wiki-design.md`

## Global Constraints

- ドキュメント(SKILL.md / references)はすべて日本語。plan doc・skill ファイル群中には実在する個人を特定する情報を書かない(alice / bob 等のダミー名は可)。運用時の bundle 内 actor `human:<id>` の `<id>` には GitHub username 等の識別子を用いてよい
- スクリプトは bash + 標準ツールのみ。python/jq/yq 等に依存しない
- スクリプトはどの CWD からでも動く(`SCRIPT_DIR` 基準で相互参照、bundle は引数か `bundle-locate.sh` で解決)
- リンク記法は bundle-relative 絶対形式 `[label](/notes/<slug>.md)` のみ
- user bundle の既定パスは `~/knowledge/`。テスト容易性のため env `EVERGREEN_USER_BUNDLE` で上書き可(既定 `$HOME/knowledge`)
- slug は `^[a-z0-9][a-z0-9-]*$`。tags は kebab-case
- ISO 8601 UTC(`YYYY-MM-DDTHH:MM:SSZ`)の時刻比較は文字列比較で行う(date パース不要)
- 各タスクの最後に必ず `bash evergreen-wiki/scripts/selftest.sh` を実行し(存在するタスク以降)、PASS を確認してからコミットする

---

## 正準シリアライズ形式(全タスク共通の前提)

conventions.md(Task 1)で規範化し、lint(Task 4-5)が検証し、operations.md(Task 6)の手順が書き出す形式。frontmatter のキーは以下の順(存在するものだけ、この順序で):

```yaml
---
type: note
title: <表示名>
description: <1文要約>
tags: [tag-a, tag-b]
sources:
  - resource: "<URI または記述子>"
generated:
  by: <actor>
  at: <ISO 8601 UTC>
verified:
  - by: <actor>
    at: <ISO 8601 UTC>
status: stable
stale_after: <ISO 8601 UTC>
---
```

- `tags` はインラインフロー形式 `[a, b]` の1行
- `sources` / `verified` は要素1件でも必ずブロックリスト(`  - key: value`)
- `sources` の要素は `resource` 必須に加え、任意で `id`(本文脚注 `[^<id>]` からの参照キー)と `title` を `id` → `resource` → `title` の順で持てる(OKF SPEC §5.1。後続レビューで追加)
- `generated` はネストマッピング(`  by:` / `  at:` の2行)
- actor 記法: `human:<id>` / `process:<id>` / `<producer>/<version>`(正規表現 `^(human:.+|process:.+|[^/ ]+/[^/ ]+)$`)
- `status` は `draft|stable|deprecated`(省略時 stable)

index.md(bundle root): frontmatter は `okf_version: "0.2"` のみ。本文は `# セクション見出し` + `* [title](/notes/<slug>.md) - <description>` の列挙。
log.md: `# Update Log` の下に `## YYYY-MM-DD`(新しい順)+ 箇条書き。

---

### Task 1: references/conventions.md(書式規約)

**Files:**
- Create: `evergreen-wiki/references/conventions.md`

**Interfaces:**
- Produces: 正準シリアライズ形式・type 体系・命名・リンク・index/log 書式・マージ判定・Trust/Lifecycle 運用の規範。Task 4-6 はこの文書の規則を実装・参照する

- [x] **Step 1: conventions.md を書く**

以下の章立てで、設計書 §2〜§4 の内容を規範として日本語で記述する(各章は設計書の対応箇所を過不足なく落とし込む。「後で決める」等の未確定記述を残さない):

```markdown
# evergreen-wiki 書式規約(conventions)

## 1. bundle 構造
(index.md / log.md / notes/<slug>.md。フラット配置。リンクは bundle 内で閉じる)

## 2. 三層モデル
(Raw source = sources[].resource で参照・保存しない / Bundle / Schema)

## 3. frontmatter スキーマと正準シリアライズ形式
(本計画冒頭の「正準シリアライズ形式」を規範として全文記載。
 各フィールドの意味・必須/推奨/任意の区分・actor 記法・正規表現を含む。
 外部プロデューサー由来の非正準 YAML はエラーではなく正規化提案の対象、
 という OKF 許容原則も明記)

## 4. type 体系
(note / concept / entity の3コア + open set。各 type の役割と本文テンプレート:
 H1 = title、本文、`## 関連` セクションに双方向リンクを列挙)

## 5. slug・tag 命名
(slug: ^[a-z0-9][a-z0-9-]*$ で英語 kebab-case、bundle 内一意。
 tags: kebab-case。分類は階層でなく tags と相互リンク)

## 6. リンク記法
([label](/notes/<slug>.md) のみ。相対リンク・bundle 外リンクは張らない。
 関連ページは双方向にリンクする)

## 7. index.md / log.md 書式
(正準形式の実例つき。okf_version: "0.2"。セクションは concept → entity → note 順)

## 8. マージ判定基準
(同趣旨 = 同じ状況で同じ判断を導く知見。マージ時: 本文統合 + sources 追記 +
 generated 更新。書式調整のみでは generated を更新しない)

## 9. Trust / Lifecycle 運用
(verified は蓄積・有効条件 at >= generated.at・trust tier 導出。
 status の使い分け。deprecated は削除せず後継リンク。stale_after は時限知識のみ)
```

- [x] **Step 2: 規範の自己整合を検証する**

Run: `grep -c '^## ' evergreen-wiki/references/conventions.md`
Expected: 9(全9章が存在)

Run: `grep -n 'okf_version\|human:<id>\|/notes/<slug>.md' evergreen-wiki/references/conventions.md | head`
Expected: 3種すべてヒット(規範のキー要素が記載されている)

- [x] **Step 3: Commit**

```bash
git add evergreen-wiki/references/conventions.md
git commit -m "feat: evergreen-wiki の書式規約(conventions.md)を追加"
```

---

### Task 2: scripts/lib.sh + selftest 基盤 + bundle-locate.sh

**Files:**
- Create: `evergreen-wiki/scripts/lib.sh`
- Create: `evergreen-wiki/scripts/bundle-locate.sh`
- Create: `evergreen-wiki/scripts/selftest.sh`

**Interfaces:**
- Produces:
  - `lib.sh`: `fm_block <file>`(frontmatter 本体を出力)/ `fm_get <file> <key>`(トップレベルスカラー値を出力)
  - `bundle-locate.sh [--scope user|project|all] [--root <dir>]`: 発見した bundle を `<scope>\t<絶対パス>` で1行ずつ出力。見つからなくても exit 0
  - `selftest.sh`: fixture 生成ヘルパー `make_bundle <dir>`(正常系 bundle を作る)と `assert_contains / assert_not_contains / assert_exit` を持ち、失敗があれば exit 1

- [x] **Step 1: selftest.sh の骨格と bundle-locate 用アサーションを書く(失敗するテスト)**

```bash
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

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
```

- [x] **Step 2: 失敗を確認する**

Run: `bash evergreen-wiki/scripts/selftest.sh`
Expected: FAIL(bundle-locate.sh が存在しないため)

- [x] **Step 3: lib.sh と bundle-locate.sh を実装する**

```bash
#!/usr/bin/env bash
# evergreen-wiki/scripts/lib.sh — frontmatter 抽出の共通関数(正準形式前提)
# fm_block <file>: 最初の --- ペアに挟まれた frontmatter 本体を出力
fm_block() { awk '/^---$/{n++; next} n==1{print} n>=2{exit}' "$1"; }
# fm_get <file> <key>: トップレベルのスカラー値を出力(なければ空)
fm_get() { fm_block "$1" | awk -v k="$2" 'index($0, k":")==1 {sub(/^[^:]*:[ ]*/, ""); print; exit}'; }
```

```bash
#!/usr/bin/env bash
# evergreen-wiki/scripts/bundle-locate.sh — OKF bundle の発見
# 出力: <scope>\t<bundle絶対パス>(1行1 bundle)。見つからなくても exit 0
set -euo pipefail
SCOPE=all; ROOT="$PWD"
while [ $# -gt 0 ]; do case "$1" in
  --scope) SCOPE=$2; shift 2 ;;
  --root)  ROOT=$2;  shift 2 ;;
  *) echo "unknown arg: $1" >&2; exit 2 ;;
esac; done
USER_BUNDLE="${EVERGREEN_USER_BUNDLE:-$HOME/knowledge}"

# okf_version frontmatter を持つ index.md があるディレクトリだけが bundle
is_bundle() {
  [ -f "$1/index.md" ] || return 1
  awk '/^---$/{n++; next} n==1{print} n>=2{exit}' "$1/index.md" | grep -q '^okf_version:'
}
abspath() { (cd "$1" 2>/dev/null && pwd); }

emit_user() {
  if is_bundle "$USER_BUNDLE"; then printf 'user\t%s\n' "$(abspath "$USER_BUNDLE")"; fi
}
emit_project() {
  local top
  top=$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null || abspath "$ROOT")
  [ -n "$top" ] || return 0
  local user_abs; user_abs=$(abspath "$USER_BUNDLE" || true)
  find "$top" -maxdepth 4 \
    \( -name node_modules -o -name .git -o -name vendor -o -name dist -o -name build \) -prune \
    -o -name index.md -print 2>/dev/null |
  while read -r f; do
    d=$(dirname "$f")
    [ "$(abspath "$d")" = "${user_abs:-}" ] && continue
    if is_bundle "$d"; then printf 'project\t%s\n' "$(abspath "$d")"; fi
  done
}
case "$SCOPE" in
  user) emit_user ;;
  project) emit_project ;;
  all) emit_user; emit_project ;;
  *) echo "invalid --scope: $SCOPE" >&2; exit 2 ;;
esac
exit 0
```

Run: `chmod +x evergreen-wiki/scripts/*.sh`

- [x] **Step 4: テストが通ることを確認する**

Run: `bash evergreen-wiki/scripts/selftest.sh`
Expected: `PASS=7 FAIL=0` で exit 0

- [x] **Step 5: Commit**

```bash
git add evergreen-wiki/scripts/
git commit -m "feat: bundle-locate.sh と selftest 基盤を追加"
```

---

### Task 3: wiki-query.sh

**Files:**
- Create: `evergreen-wiki/scripts/wiki-query.sh`
- Modify: `evergreen-wiki/scripts/selftest.sh`(query セクション追記)

**Interfaces:**
- Consumes: `lib.sh` の `fm_get`、`bundle-locate.sh` の出力形式
- Produces: `wiki-query.sh [--bundle <path>]... [--type t] [--tag t] [--keyword k] [--slug s]`。マッチしたページを `<bundle>\t<slug>\t<type>\t<status>\t<description>` で出力。`--bundle` 省略時は `bundle-locate.sh` の全 bundle を対象

- [x] **Step 1: selftest.sh に query のアサーションを追記する(失敗するテスト)**

`echo "PASS=$PASS FAIL=$FAIL"` の直前に挿入:

```bash
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
```

- [x] **Step 2: 失敗を確認する**

Run: `bash evergreen-wiki/scripts/selftest.sh`
Expected: query セクションで FAIL(wiki-query.sh が存在しない)

- [x] **Step 3: wiki-query.sh を実装する**

```bash
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
```

Run: `chmod +x evergreen-wiki/scripts/wiki-query.sh`

- [x] **Step 4: テストが通ることを確認する**

Run: `bash evergreen-wiki/scripts/selftest.sh`
Expected: `FAIL=0` で exit 0

- [x] **Step 5: Commit**

```bash
git add evergreen-wiki/scripts/
git commit -m "feat: wiki-query.sh を追加"
```

---

### Task 4: wiki-lint.sh — 単一ファイル検査(conformance / 正準形 / actor / Trust / Lifecycle)

**Files:**
- Create: `evergreen-wiki/scripts/wiki-lint.sh`
- Modify: `evergreen-wiki/scripts/selftest.sh`(lint 単一ファイル検査セクション追記)

**Interfaces:**
- Consumes: `lib.sh`、`bundle-locate.sh`
- Produces: `wiki-lint.sh [--bundle <path>]... [--json]`。検出結果を `<severity>\t<check>\t<bundle>\t<file>\t<detail>`(severity は `ERROR`|`SUGGEST`)で出力。ERROR が1件以上なら exit 1、それ以外 exit 0。本タスクで実装する check id:
  - ERROR: `conformance-frontmatter`(frontmatter がない/閉じていない)、`conformance-type`(type 欠落・空)、`actor-format`(generated.by / verified[].by が actor 正規表現に不一致)
  - SUGGEST: `canonical-form`(トップレベルキーが正準順でない、または `verified:` が単一マッピング)、`stale`(stale_after < 現在時刻)、`verify-stale`(最新 verified.at < generated.at)

- [x] **Step 1: selftest.sh に lint 用の異常系 fixture とアサーションを追記する(失敗するテスト)**

`echo "PASS=$PASS FAIL=$FAIL"` の直前に挿入:

```bash
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
```

- [x] **Step 2: 失敗を確認する**

Run: `bash evergreen-wiki/scripts/selftest.sh`
Expected: lint セクションで FAIL(wiki-lint.sh が存在しない)

- [x] **Step 3: wiki-lint.sh を実装する(単一ファイル検査)**

```bash
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
  fm_block "$f" | awk '/^(generated|verified):/{on=1; next} /^[a-zA-Z_]+:/{on=0} on && /^[ -]*by:/' |
  sed 's/^[ -]*by:[ ]*//' | while read -r actor; do
    echo "$actor" | grep -Eq "$ACTOR_RE" || report ERROR actor-format "$b" "$rel" "actor 記法違反: $actor"
  done
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
```

Run: `chmod +x evergreen-wiki/scripts/wiki-lint.sh`

**実装上の注意:** `check_note_file` 内の actor 検査は `while read` がサブシェルになると `ERRORS` が加算されない。実装時は process substitution(`while read ... done < <(...)`)を使うこと。上記コードのこの箇所は実装時に必ず直すこと(selftest の exit code アサーションが検出する)。

- [x] **Step 4: テストが通ることを確認する**

Run: `bash evergreen-wiki/scripts/selftest.sh`
Expected: `FAIL=0` で exit 0(exit code アサーション含む)

- [x] **Step 5: Commit**

```bash
git add evergreen-wiki/scripts/
git commit -m "feat: wiki-lint.sh の単一ファイル検査を追加"
```

---

### Task 5: wiki-lint.sh — bundle 横断検査(リンク / index / log / concept 候補)

**Files:**
- Modify: `evergreen-wiki/scripts/wiki-lint.sh`
- Modify: `evergreen-wiki/scripts/selftest.sh`

**Interfaces:**
- Consumes: Task 4 の `report` / `fm_get` / bundle ループ構造
- Produces: 追加 check id:
  - ERROR: `broken-link`(リンク先の notes ファイルが存在しない)、`index-miss`(note が index.md に未記載)、`index-format`(index.md の frontmatter が okf_version 以外を含む/エントリ行が書式不一致)、`log-format`(log.md の日付見出しが `## YYYY-MM-DD` 形式でない、または降順でない)、`one-way-link`(A→B のリンクに B→A がない)、`orphan`(他の note からの被リンクが1本もない note。concept/entity は対象外)
  - SUGGEST: `concept-candidate`(同一タグを5件以上の非 concept ページが持ち、そのタグを持つ concept ページが存在しない)

- [x] **Step 1: selftest.sh に横断検査のアサーションを追記する(失敗するテスト)**

`echo "PASS=$PASS FAIL=$FAIL"` の直前に挿入:

```bash
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
* [存在しないページ](/notes/no-such-page.md)
EOF
# log.md を不正な形式に(日付見出しが昇順)
cat > "$XB/log.md" <<'EOF'
# Update Log

## 2026-08-24
* 古いエントリ

## 2026-08-25
* 新しいエントリ
EOF
out=$("$L" --bundle "$XB"); rc=$?
assert_exit "$rc" 1 "横断検査の ERROR で exit 1"
assert_contains "$out" "ERROR	broken-link"
assert_contains "$out" "ERROR	orphan	$XB	notes/orphan-note.md"
assert_contains "$out" "ERROR	index-miss"
assert_contains "$out" "ERROR	log-format"
assert_contains "$out" "ERROR	one-way-link"   # orphan-note → pipe... はないが、broken 先とは別に相互リンク検査
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
```

**注意:** `one-way-link` のアサーションが fixture で成立するよう、`orphan-note.md` の `## 関連` に `* [パイプは exit code を隠す](/notes/pipe-exit-code.md)` を1行追加すること(pipe-exit-code 側は orphan-note にリンクしていない → 片方向)。上の heredoc に追記して使う。

- [x] **Step 2: 失敗を確認する**

Run: `bash evergreen-wiki/scripts/selftest.sh`
Expected: cross-file セクションで FAIL

- [x] **Step 3: wiki-lint.sh に横断検査を追加実装する**

`check_note_file` ループの後、`[ "$ERRORS" -gt 0 ]` の前に bundle ごとの横断検査を追加:

```bash
check_bundle_cross() { # bundle
  local b="$1" f slug
  local slugs=""; local links=""   # links: "from>to" の行集合
  for f in "$b"/notes/*.md; do
    [ -e "$f" ] || continue
    slugs="$slugs $(basename "$f" .md)"
  done
  for f in "$b"/notes/*.md; do
    [ -e "$f" ] || continue
    slug=$(basename "$f" .md)
    for to in $(grep -o '](/notes/[a-z0-9-]*\.md)' "$f" | sed 's|](/notes/||; s|\.md)||'); do
      links="$links
$slug>$to"
      # broken-link
      [ -f "$b/notes/$to.md" ] || report ERROR broken-link "$b" "notes/$slug.md" "リンク先が存在しない: /notes/$to.md"
    done
    # index-miss
    grep -qF "(/notes/$slug.md)" "$b/index.md" || report ERROR index-miss "$b" "notes/$slug.md" "index.md に未記載"
  done
  # one-way-link / orphan(存在するページ間のみ対象)
  for f in "$b"/notes/*.md; do
    [ -e "$f" ] || continue
    slug=$(basename "$f" .md)
    # one-way: slug→to があり to→slug がない(to が実在する場合のみ)
    echo "$links" | grep -x "$slug>.*" | sed "s/^$slug>//" | while read -r to; do
      [ -n "$to" ] && [ -f "$b/notes/$to.md" ] || continue
      echo "$links" | grep -qx "$to>$slug" ||
        report ERROR one-way-link "$b" "notes/$slug.md" "→ $to への片方向リンク($to 側に逆リンクなし)"
    done
    # orphan: 被リンク0(note のみ。concept/entity はハブなので対象外)
    local t; t=$(fm_get "$f" type)
    if [ "$t" = "note" ]; then
      echo "$links" | grep -q ">$slug\$" ||
        report ERROR orphan "$b" "notes/$slug.md" "他の note からの被リンクなし"
    fi
  done
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
  # concept-candidate: 同一タグ5件以上 + そのタグを持つ concept なし
  for tag in $(for f in "$b"/notes/*.md; do [ -e "$f" ] || continue
      [ "$(fm_get "$f" type)" = "concept" ] && continue
      fm_get "$f" tags | tr -d '[]' | tr ',' '\n' | sed 's/^ *//; s/ *$//'
    done | grep -v '^$' | sort | uniq -c | awk '$1>=5{print $2}'); do
    local has_concept=0
    for f in "$b"/notes/*.md; do
      [ -e "$f" ] || continue
      [ "$(fm_get "$f" type)" = "concept" ] || continue
      fm_get "$f" tags | tr -d '[]' | tr ',' '\n' | sed 's/^ *//; s/ *$//' | grep -qx "$tag" && { has_concept=1; break; }
    done
    [ "$has_concept" = 0 ] && report SUGGEST concept-candidate "$b" "-" "タグ $tag を5件以上が共有(concept ページ候補)"
  done
}
```

bundle ループを次の形にする:

```bash
for b in "${BUNDLES[@]}"; do
  for f in "$b"/notes/*.md; do
    [ -e "$f" ] || continue
    check_note_file "$b" "$f"
  done
  check_bundle_cross "$b"
done
```

**実装上の注意(Task 4 と同じ罠):** `while read` のサブシェル内で `report ERROR` しても `ERRORS` が親に伝わらない。横断検査ではパイプではなく一時ファイルまたは process substitution でループすること。selftest の `assert_exit rc 1` が検出する。

- [x] **Step 4: テストが通ることを確認する**

Run: `bash evergreen-wiki/scripts/selftest.sh`
Expected: `FAIL=0` で exit 0

- [x] **Step 5: shellcheck(あれば)を通す**

Run: `command -v shellcheck >/dev/null && shellcheck evergreen-wiki/scripts/*.sh || echo "shellcheck なし: スキップ"`
Expected: エラーなし(warning は SC2086 等、意図的なものは directive で抑制)

- [x] **Step 6: Commit**

```bash
git add evergreen-wiki/scripts/
git commit -m "feat: wiki-lint.sh の bundle 横断検査を追加"
```

---

### Task 6: references/operations.md(操作手順)

**Files:**
- Create: `evergreen-wiki/references/operations.md`

**Interfaces:**
- Consumes: conventions.md の規約、Task 2-5 のスクリプト CLI
- Produces: Init / Ingest / Query / Lint の実行手順書。SKILL.md(Task 7)から参照される

- [x] **Step 1: operations.md を書く**

以下の章立てで日本語で記述する(設計書 §5 を過不足なく落とし込む。スクリプト名・CLI・出力形式は Task 2-5 の実装と一致させる):

```markdown
# evergreen-wiki 操作手順(operations)

## 1. Init(bundle 作成)
1. scope を確認(user / project)
2. 先に `scripts/bundle-locate.sh` で既存 bundle を発見。あれば作成せず報告して終了
   (場所を先に聞くと二重 bundle ができ、Query が両方を対等に読んでしまうため)
3. 見つからない場合のみ場所を決める。user: ~/knowledge/ 固定。
   project: git toplevel 配下の候補(docs/knowledge/ 等)を提示して AskUserQuestion で確認
4. scaffold を作成(以下のテンプレートを全文記載):
   - index.md: okf_version frontmatter + 「# concept / # entity / # note」の空セクション
   - log.md: 「# Update Log」+ 当日見出し + 「bundle 作成」エントリ
   - notes/ ディレクトリ
5. git 管理を推奨として案内(user bundle は独立リポジトリ化を提案。強制しない)

## 2. Ingest(取り込み)
(設計書 §5 の6手順を、具体的なコマンド例つきで記述:
 1. 候補の選別基準(一般化・非自明・繰り返し・未収載)
 2. scope 振分(プロジェクト固有→project、汎用→user。迷ったら AskUserQuestion。
    project bundle がなければ user へ。勝手に Init しない)
 3. 既存照合: index.md を読み、wiki-query.sh --keyword/--tag で同趣旨を探す
    → マージ(本文統合 + sources 追記 + generated 更新)or 新規(正準形式で作成)
 4. 相互リンク: 双方向リンク + concept/entity への接続(entity はスタブ新設可)
 5. index.md 更新(type 別セクションへ1行追加)+ log.md 追記(当日見出しの下)
 6. 報告は書き込み完了後。同一 bundle への Ingest は逐次実行(並列書き込み禁止)
 マージ時の Trust: verified は消さず保持。有効性は at >= generated.at で判定される)

## 3. Query(参照)
(1. bundle-locate.sh で全 bundle 発見 → 2. index.md + wiki-query.sh で該当ページ特定 →
 3. 本文と関連リンクをたどる → 4. bundle とページを出典明示して回答。
 deprecated / stale_after 超過は明示 →
 5. 回答の還元: 複数ページの突き合わせで生まれた統合・洞察は Ingest 手順に渡して
 還元する。一過性の検索結果の列挙は還元しない)

## 4. Lint(健全化)
(1. wiki-lint.sh 実行(対象 bundle 指定 or 全 bundle)→ ERROR / SUGGEST の意味と
 check id 一覧表(Task 4-5 の全 check id と対処方法)→
 2. LLM 意味チェック(矛盾・重複・陳腐化・欠落 concept)→
 3. 加算的変更は即実行、破壊的変更(ページ統合・deprecated 化)は一括承認 →
 4. log.md に記録)
```

- [x] **Step 2: 記載内容とスクリプト実装の一致を確認する**

Run: `grep -o 'bundle-locate.sh\|wiki-query.sh\|wiki-lint.sh' evergreen-wiki/references/operations.md | sort -u`
Expected: 3スクリプトすべてが登場

Run: `grep -c 'conformance-frontmatter\|broken-link\|concept-candidate' evergreen-wiki/references/operations.md`
Expected: 1以上(check id 一覧が記載されている)

- [x] **Step 3: Commit**

```bash
git add evergreen-wiki/references/operations.md
git commit -m "feat: evergreen-wiki の操作手順(operations.md)を追加"
```

---

### Task 7: SKILL.md + 統合検証

**Files:**
- Create: `evergreen-wiki/SKILL.md`

**Interfaces:**
- Consumes: references/ の2文書、scripts/ の3スクリプト + selftest

- [x] **Step 1: SKILL.md を書く**

frontmatter(name / description)+ 本文。description は明示呼び出しのトリガー条件を具体的な発話例で列挙する(自律トリガーは持たない旨を含める):

```markdown
---
name: evergreen-wiki
description: >-
  Evergreen notes(atomic・concept-oriented・densely linked)と karpathy の LLM Wiki
  (時系列追記ではなく既存知識へマージ・重複排除・相互リンク)の哲学に基づき、
  OKF (Open Knowledge Format) v0.2 に完全準拠したナレッジベース(bundle)を構築・管理するスキル。
  bundle は user scope(~/knowledge/)と project scope(プロジェクト内)で選択的に作成できる。
  操作は4つ: Init(bundle 初期化)/ Ingest(知見の取り込み・マージ)/
  Query(横断参照。有用な統合が生まれたら還元)/ Lint(OKF conformance 検証を含む健全化)。
  ユーザーが「ナレッジベースを初期化して/作って」「knowledge に取り込んで/統合して」
  「ナレッジ(knowledge)を検索して/参照して」「bundle を lint して/整理して」など
  明示的に指示したときに使う。自律的には発動しない。
---

# evergreen-wiki — OKF 準拠ナレッジベース skill

(本文: 目的1段落 → 設計原則3资料の要約 → 三層モデル → bundle 構造と scope 解決の表 →
 4操作の要約(各3-5行。詳細は references/operations.md へ誘導)→
 スクリプト表(bundle-locate / wiki-query / wiki-lint / selftest の役割と実行例)→
 参照ファイル一覧(conventions.md は「ページを作る/更新する前に必ず読む」と明記))
```

- [x] **Step 2: 統合検証 — selftest 全体を実行する**

Run: `bash evergreen-wiki/scripts/selftest.sh`
Expected: `FAIL=0` で exit 0

- [x] **Step 3: 統合検証 — 実際の Init 相当の scaffold を一時ディレクトリで作り、lint が無違反であることを確認する**

Run:
```bash
T=$(mktemp -d)
mkdir -p "$T/kb/notes"
printf -- '---\nokf_version: "0.2"\n---\n# concept\n\n# entity\n\n# note\n' > "$T/kb/index.md"
printf -- '# Update Log\n\n## %s\n* bundle 作成\n' "$(date -u +%Y-%m-%d)" > "$T/kb/log.md"
bash evergreen-wiki/scripts/wiki-lint.sh --bundle "$T/kb"; echo "exit=$?"
rm -rf "$T"
```
Expected: 出力なし・`exit=0`(空 bundle は無違反)

- [x] **Step 4: Commit**

```bash
git add evergreen-wiki/SKILL.md
git commit -m "feat: evergreen-wiki の SKILL.md を追加"
```
