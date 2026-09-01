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

相互リンクされた Markdown 群として知識を蓄積・育成するナレッジベースの構築・管理操作を提供する skill。ナレッジベースの実体は OKF v0.2 に完全準拠した bundle であり、user scope(個人の汎用知識)と project scope(プロジェクト固有知識)で選択的に作成する。発動はユーザーの明示指示のみで、自律トリガーは持たない。

## 設計原則

3つの一次資料に基づく。

- **Evergreen notes**(Andy Matuschak): ページは atomic(1ページ1知識)・concept-oriented・densely linked。分類は階層ディレクトリではなく tags と相互リンクで表現する。
- **LLM Wiki**(Andrej Karpathy): 時系列追記ではなく既存知識へのマージ・重複排除・相互リンク。整理・相互参照・重複排除の bookkeeping は LLM が担い、人間は内容の妥当性判断に集中する。
- **OKF v0.2**(Open Knowledge Format): Conformance Requirements の充足に加え、推奨フィールド(title/description/tags)と Provenance(sources)・Trust(generated/verified)・Lifecycle(status/stale_after)の任意族を全ページで運用する。「`cat` と `git clone` で十分」の思想に従い、スキーマ登録や専用ツールに依存しない。

## 三層モデル

1. **Raw source(生の出典)**: PR・コード・ドキュメント・調査セッション等、真実の出典。bundle には保存せず、各ページの frontmatter `sources[].resource` で参照するのみ。コピー・改変はしない。
2. **Bundle**: この skill が所有・維持する OKF bundle そのもの。人間は読む側。
3. **Schema**: この SKILL.md と `references/conventions.md`。書式・分類・マージ・相互リンクの規約を定める層。

## Bundle 構造と scope 解決

各 bundle は完全に独立した OKF bundle であり、リンクは bundle 内で閉じる(bundle をまたぐ相互リンクは張らない)。

```
<bundle-root>/
├── index.md          # okf_version: "0.2" を frontmatter に持つ唯一のファイル。全ページのカタログ
├── log.md            # OKF 予約構造: ## YYYY-MM-DD 見出し(新しい順)+ 箇条書き
└── notes/<slug>.md   # 1知識 = 1ファイル(atomic)。フラット配置、分類は tags と相互リンク
```

| scope | 場所 | 発見方法 |
|---|---|---|
| user | `~/knowledge/`(固定。`EVERGREEN_USER_BUNDLE` で上書き可) | 固定パス |
| project | Init 時にユーザーへ確認して決定(候補: `docs/knowledge/` 等) | プロジェクトルート(`git rev-parse --show-toplevel`、git 管理外は CWD)配下から `okf_version` frontmatter を持つ `index.md` を glob 検索 |

レジストリ・設定ファイルは持たない。bundle 自身(`okf_version` を持つ `index.md`)がマーカーとなるため、発見はどの環境でも決定論的に再現する。

## 4操作

### Init(bundle 作成)

scope(user / project)を確認する。
`bundle-locate.sh --scope all` で既存 bundle の発見を**先に**行い、見つかればそのパスを報告して終了する。
見つからない場合のみ場所を決定する(user は `~/knowledge/` 固定、project はユーザーに確認)。
`index.md` / `log.md` / `notes/` を scaffold し、git 管理を推奨として案内する。
詳細手順は `references/operations.md` §1 を参照。

### Ingest(取り込み・マージ)

一般化できるか・非自明か・繰り返しうるかで取り込み候補を選別する。
プロジェクト固有の知識は project bundle、汎用的な教訓は user bundle へ振り分ける。
`wiki-query.sh` で既存ページと照合し、同趣旨があればマージ、なければ正準形式で新規作成して双方向相互リンクを張る。
`index.md` / `log.md` を更新し、書き込み完了後に報告する(同一 bundle への並列書き込みは禁止)。
マージ判定基準・正準形式は `references/conventions.md` §3・§8、詳細手順は `references/operations.md` §2 を参照。

### Query(参照)

`bundle-locate.sh --scope all` で存在する全 bundle(user + project)を発見し横断する。
`wiki-query.sh` で該当ページを機械的に絞り込み、`## 関連` をたどって関連知識を辿る。
どの bundle のどのページを根拠にしたか出典を明示して回答する(`deprecated` / `stale_after` 超過ページ使用時はその旨も明示)。
複数ページを突き合わせて生まれた新しい統合・洞察は Ingest 手順へ渡して bundle へ還元する(一過性の列挙は還元しない)。
詳細手順は `references/operations.md` §3 を参照。

### Lint(健全化)

`wiki-lint.sh` で機械チェックを行う(正準形一致の検証 → 正準形を前提とした意味チェックの二段構え。ERROR 12種 + SUGGEST 4種)。
機械チェックでは検出できない矛盾・重複・陳腐化・欠落 concept を LLM が意味チェックする。
加算的な変更(リンク追加・index 補完等)は即実行し、破壊的な変更(ページ統合・deprecated 化)は一括でユーザー承認を得てから適用する。
適用した変更は `log.md` に記録する。
check id 一覧と詳細手順は `references/operations.md` §4 を参照。

## スクリプト

いずれも bash + 標準ツールのみで実装され、外部依存を持たない。CWD に依存せず、bundle root は `bundle-locate.sh` が解決するか `--bundle <path>` で明示指定する。

| スクリプト | 役割 | 実行例 |
|---|---|---|
| `scripts/bundle-locate.sh` | bundle 発見(user 固定パス + project glob 検索)。出力: `<scope>\t<bundle絶対パス>`(1行1 bundle) | `scripts/bundle-locate.sh --scope all` |
| `scripts/wiki-query.sh` | `--bundle`/`--type`/`--tag`/`--keyword`/`--slug` でページを機械的に絞り込み。出力: `<bundle>\t<slug>\t<type>\t<status>\t<description>` | `scripts/wiki-query.sh --tag shell --type note` |
| `scripts/wiki-lint.sh` | 機械チェック一式(OKF conformance 検証を含む)。`--json` 対応。出力: `<severity>\t<check>\t<bundle>\t<file>\t<detail>`。ERROR が1件でもあれば exit 1、SUGGEST のみ・検出なしなら exit 0 | `scripts/wiki-lint.sh --bundle ~/knowledge` |
| `scripts/selftest.sh` | fixture bundle を一時ディレクトリに生成し、lint/query の挙動をアサートする回帰テスト。`PASS=N FAIL=0` を出力し FAIL=0 で exit 0 | `bash scripts/selftest.sh` |

上記コマンド例は `evergreen-wiki/` からの相対パスで示す。実行時のカレントディレクトリは skill ディレクトリとは限らないため、実際には skill の絶対パス(例: `~/.claude/skills/evergreen-wiki/scripts/...`)に読み替える。

## 参照ファイル

- `references/conventions.md` — 書式規約: frontmatter スキーマ・正準シリアライズ形式・type 体系・slug/tag 命名・リンク記法・index.md/log.md 書式・マージ判定基準・Trust/Lifecycle 運用。**ページを作る/更新する前に必ず読む。**
- `references/operations.md` — Init / Ingest / Query / Lint の実行手順の詳細と、`wiki-lint.sh` の check id(ERROR 12種 + SUGGEST 4種)一覧。
