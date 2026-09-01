# evergreen-wiki — OKF 完全準拠ナレッジベース skill 設計書

- 日付: 2026-08-25
- 対象: 本リポジトリに新規作成する skill `evergreen-wiki/`
- 参照する一次資料:
  - [Evergreen notes](https://notes.andymatuschak.org/z5E5QawiXCMbtNtupvxeoEX)(Andy Matuschak)
  - [LLM Wiki](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f)(Andrej Karpathy)
  - [OKF SPEC.md v0.2](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md)(Open Knowledge Format)

## 1. 目的と位置づけ

相互リンクされた Markdown 群として知識を蓄積・育成するナレッジベースの構築・管理操作を提供する skill を作る。ナレッジベースの実体は OKF v0.2 に完全準拠した bundle であり、user scope / project scope で選択的に作成できる。

設計原則は3つの一次資料に基づく:

- **Evergreen notes**: ページは atomic(1ページ1知識)・concept-oriented・densely linked。分類は階層ディレクトリではなく tags と相互リンクで表現する
- **LLM Wiki**: 時系列追記ではなく既存知識へのマージ・重複排除・相互リンク。整理・相互参照・重複排除の bookkeeping は LLM が担い、人間は内容の妥当性判断に集中する
- **OKF v0.2**: Conformance Requirements の充足に加え、推奨フィールド(title/description/tags)と Provenance(sources)・Trust(generated/verified)・Lifecycle(status/stale_after)の任意族を全ページで運用する。Attested Computation はナレッジベース用途では不要のため対象外。「`cat` と `git clone` で十分」の思想に従い、スキーマ登録や専用ツールに依存しない

**発動はユーザーの明示指示のみ**(「ナレッジベースに取り込んで」「knowledge を検索して」「bundle を初期化して」「lint して」等)。自律トリガーは持たない。

**操作は4つ**: Init(bundle 作成)/ Ingest(取り込み)/ Query(参照)/ Lint(健全化)。

## 2. 三層モデル

1. **Raw source** = 真実の出典(PR・コード・ドキュメント・調査セッション等)。bundle には保存せず、各ページの `sources[].resource` で参照する。URI を持たない出典(会話・ターミナル出力等)は OKF が許容するスコープ記述子(例: `"2026-08-25 デバッグセッション: CI失敗の原因調査"`)として記録する。コピー・改変はしない
2. **Bundle** = LLM が所有・維持する OKF bundle。人間は読む
3. **Schema** = この skill の SKILL.md と `references/conventions.md`。書式・分類・マージ・相互リンクの規約

raw source の実体を bundle 内に保存する設計(`sources/` ディレクトリ等)は、bundle の肥大化・可搬性低下を招き、OKF の provenance 参照モデルからも外れるため採らない。

## 3. Bundle 構造と scope 解決

各 bundle は完全に独立した OKF bundle であり、リンクは bundle 内で閉じる(bundle をまたぐ相互リンクは張らない。OKF bundle の可搬性を保つため):

```
<bundle-root>/
├── index.md          # okf_version: "0.2" を frontmatter に持つ唯一のファイル。全ページのカタログ
├── log.md            # OKF 予約構造: ## YYYY-MM-DD 見出し(新しい順)+ 箇条書き
└── notes/<slug>.md   # 1知識 = 1ファイル(atomic)。フラット配置、分類は tags と相互リンク
```

### scope 解決

| scope | 場所 | 発見方法 |
|---|---|---|
| user | `~/knowledge/`(固定) | 固定パス |
| project | Init 時にユーザーへ確認して決定(候補として `docs/knowledge/` を提示) | プロジェクトルート配下から `okf_version` frontmatter を持つ `index.md` を glob 検索 |

- **プロジェクトルートの定義**: `git rev-parse --show-toplevel`(git 管理外の場合は CWD)。モノレポでは git リポジトリ単位で1 bundle とする(パッケージごとの bundle 分割は採らない)
- レジストリ・設定ファイルは持たない。bundle 自身(`okf_version` を持つ `index.md`)がマーカーとなるため、発見は決定論的でどの環境でも再現する

### scope 間の振る舞い

- **Ingest の振分**: プロジェクト固有の知識 → project bundle、汎用的な教訓 → user bundle。迷う場合のみユーザーに確認する
- **Query**: 存在する全 bundle を横断検索し、どの bundle のどのページかを出典として明示して統合回答する

## 4. ページ書式

### notes/<slug>.md の frontmatter

```yaml
---
type: note                        # 必須(OKF Conformance)。open set
title: シェルのパイプは exit code を隠す   # 推奨。本文 H1 と一致させる
description: パイプ末尾のコマンドの exit code だけが返るため中間の失敗が見えない  # 推奨。1文要約
tags: [shell, error-handling]     # 推奨。kebab-case
sources:                          # Provenance 族
  - resource: "https://github.com/owner/repo/pull/123"
  - resource: "2026-08-25 デバッグセッション: CI失敗の原因調査"
generated:                        # Trust 族: 内容を実質的に書いた actor と時刻
  by: claude-code/claude-fable-5
  at: 2026-08-25T04:10:00Z
verified:                         # Trust 族: 検証イベントの蓄積(任意)
  - by: human:<id>
    at: 2026-08-25T05:00:00Z
status: stable                    # Lifecycle 族: draft|stable|deprecated(省略時 stable)
stale_after: 2027-08-25T00:00:00Z # Lifecycle 族: 時限性のある知識のみに付与
---
```

### 正準シリアライズ形式(canonical form)

`conventions.md` は frontmatter の意味論だけでなく**シリアライズ形式そのものを規範化する**: キーの順序固定、2スペースインデント固定、`sources`/`verified` は要素1件でも必ずリスト形式、`- resource:`/`- by:` は1行1キー。理由は2つ:

1. この skill が唯一のプロデューサーである限り、常に正準形で書き出せる
2. lint を bash + 標準ツールで実装するため。grep/awk は YAML を解析できず、既知の正準形への行アンカーのパターンマッチしかできない。正準形の規範化により「(a) 正準形に一致するかの検証 → (b) 正準形を前提とした意味チェック」の二段構えが成立する

外部プロデューサーが書いた正準形でない(しかし OKF 的には妥当な)YAML — 例: 単一マッピングの `verified`(OKF はコンシューマーに1要素リスト扱いを要求)— は、**エラーではなく「正準形違反(提案枠)」として正規化を提案する**。OKF の「コンシューマーは理解できないものを許容する」原則に従い、lint が外部 bundle を誤って拒絶しないようにする。

### Trust / Lifecycle の運用規約

- **actor 記法**(OKF §7 準拠): LLM は `<producer>/<version>` 形式(例 `claude-code/claude-fable-5`)、人間は `human:<id>`、自動プロセスは `process:<id>`
- **`generated`**: ページ新規作成時と実質的な内容変更(マージ含む)のたびに更新する。書式調整のみでは更新しない
- **`verified`**: 内容の検証イベントを追記する(上書きせず蓄積)。主な運用はユーザーによる内容確認(`human:<id>`)だが、自動チェックによる検証(非 `human:` actor)も許容する。OKF の trust tier(`verified` なし = unverified → 非 `human:` actor のみ = machine-confirmed → `human:` actor を含む = human-reviewed)がこのフィールドから導出される
- **検証の失効**: `verified` イベントは履歴として保持するが、「現在有効な検証」は `at >= generated.at` を満たすもののみ。マージで内容が変わると過去の人間検証は実質失効し、Lint が「再検証候補」として検出する
- **`status`**: 既定 `stable`。確信度の低い暫定知識は `draft`。陳腐化した知識は削除せず `deprecated` にして後継ページへリンクする(知識の履歴を保つ)
- **`stale_after`**: バージョン依存・期限つきの知識のみに付与する(絶対 ISO 8601 時刻。相対 TTL ではない)。Lint が期限超過を検出する

### type 体系(open set、skill が定義するコアは3つ)

| type | 役割 |
|---|---|
| `note` | atomic な知見・教訓。1ページ1知識(Evergreen の atomic 原則) |
| `concept` | 複数の note を貫く横断的洞察の結節点ページ。note が接続されるたびに育つ |
| `entity` | 固有名詞(プロジェクト・ツール・仕組み)の参照ハブ。スタブで生まれ、バックリンクの蓄積で意味が定義される |

これ以外の type も許容する(OKF は未知 type を容認。将来の用途が自由に追加できる)。

### リンク記法

bundle-relative の絶対形式 `[label](/notes/<slug>.md)` を使う(OKF 推奨の Absolute 形式)。関連ページ同士は双方向にリンクする。

### index.md / log.md(OKF 予約ファイル)

- **index.md**: bundle root のみ frontmatter `okf_version: "0.2"` を持つ。本文は `# セクション見出し` + `* [title](/notes/<slug>.md) - description` の列挙。セクションは type 別(concept → entity → note)
- **log.md**: `# Update Log` の下に `## YYYY-MM-DD` 見出しで日付グルーピング(新しい順)、同日内は箇条書き

## 5. 4操作の詳細

### Init(bundle 作成)

1. scope を確認(user / project)
2. **先に既存 bundle の発見を実行する**(`bundle-locate.sh`)。既存 bundle があれば作成せず報告して終了する(場所を先に聞くと、別の場所に既存 bundle があった場合に二重 bundle ができ、Query が両方を対等に読んでしまう)
3. 見つからない場合のみ場所を決める。user は `~/knowledge/` 固定、project は候補(`docs/knowledge/` 等)を提示しつつユーザーに確認する
4. scaffold: `index.md`(`okf_version: "0.2"` + 空のセクション構造)、`log.md`(初期エントリ)、`notes/`
5. git 管理を推奨として案内する(user bundle は独立リポジトリ化を提案。強制はしない)

### Ingest(取り込み)

1. **候補の選別**: 一般化できるか / 非自明か / 繰り返しうるか / まだ bundle にないか。作業ログ・一過性の状態・コードを読めば自明な内容は入れない
2. **scope 振分**: プロジェクト固有 → project bundle、汎用 → user bundle。迷う場合のみユーザーに確認。project bundle が無い場合は user bundle へ入れる(勝手に Init しない)
3. **既存照合**: 必ず先に index.md + `wiki-query.sh` で同趣旨ページを探す → あればマージ(sources 追記 + `generated` 更新)、なければ新規作成
4. **相互リンク**: 双方向 `[label](/notes/<slug>.md)`。関連する concept / entity へ接続する(entity は初出の言及からスタブ新設可)
5. **カタログ更新**: index.md 更新 → log.md 追記(当日見出しの下)
6. **報告は書き込み完了後**に出す。同一 bundle への Ingest は逐次実行(並列書き込み禁止)

### Query(参照)

1. bundle 発見(`bundle-locate.sh`: user 固定パス + project glob 検索)→ 存在する全 bundle を横断する
2. index.md + `wiki-query.sh`(type/tag/keyword/slug)で該当ページを特定 → 本文と関連リンクをたどる
3. どの bundle のどのページかを出典として明示して回答する
4. `deprecated` / `stale_after` 超過のページを回答に使う場合はその旨を明示する
5. **回答の還元**: Query の過程で既存ページに無い有用な統合・洞察が生まれた場合(複数ページを突き合わせて初めて見えた関係、既存ページの欠落を補う知見など)、その回答を Ingest 手順に渡してナレッジとして還元する(新規ページまたは既存ページへのマージ)。一過性の検索結果の単なる列挙は還元しない

### Lint(健全化)

対象 bundle を指定して実行する(または全 bundle を順に):

1. **機械チェック**(`wiki-lint.sh`)。まず正準形(§4)への一致を検証し、正準形を前提に意味チェックを行う:
   - エラー(機械的事実): OKF conformance 違反(frontmatter パース不可・`type` 空・予約ファイル構造違反)/ リンク切れ / 孤立ページ / 片方向リンク / index 記載漏れ / actor 記法違反
   - 提案(判断材料): 正準形違反(外部プロデューサー由来等。正規化を提案)/ `stale_after` 期限超過 / 検証失効(`verified` の最新 `at` < `generated.at`)/ concept 候補(タグクラスタ)
2. **LLM 意味チェック**: 矛盾・重複・陳腐化・欠落 concept の検出と統合
3. **変更の適用**: 加算的変更(リンク追加・index 補完)は即実行、破壊的変更(ページ統合・deprecated 化)は一括でユーザー承認を得る
4. log.md に記録する

## 6. skill ディレクトリ構成

```
evergreen-wiki/
├── SKILL.md                 # 要点のみ: 発動条件(明示呼び出し)・哲学の要約・4操作の概要・references への誘導
├── references/
│   ├── conventions.md       # 書式規約: frontmatter スキーマ / type 体系 / slug・tag 命名 /
│   │                        #   リンク記法 / index.md・log.md 書式 / マージ判定基準 / Trust・Lifecycle 運用
│   └── operations.md        # Init / Ingest / Query / Lint の詳細手順
└── scripts/
    ├── bundle-locate.sh     # bundle 発見(user 固定パス + project glob 検索)
    ├── wiki-query.sh        # --bundle / --type / --tag / --keyword / --slug でページを機械的に絞り込み
    ├── wiki-lint.sh         # 機械チェック一式(OKF conformance 検証を含む)。--json 対応
    └── selftest.sh          # fixture bundle を一時ディレクトリに生成し、lint/query の挙動をアサートする回帰テスト
```

### スクリプトの設計方針

- bash + 標準ツールのみ(grep/awk/sed)。外部依存なし — OKF の「`cat` と `git clone` で十分」の思想に合わせる
- どの CWD からでも動く(bundle root は `bundle-locate.sh` が解決、または `--bundle <path>` で明示指定)
- project bundle の glob 検索は `node_modules`・`.git`・`vendor` 等を除外し、深さ制限をかけて高速に保つ
- `wiki-lint.sh` の出力は「エラー」と「提案」を区別する

### テスト

- `selftest.sh` が正常系 fixture と異常系 fixture(frontmatter 欠落・`type` 空・リンク切れ・検証失効など)を生成し、lint の検出結果と query の出力を検証する
- スクリプト実装は TDD(selftest のアサーションを先に書く)で進める

### 配置・運用

- 本リポジトリに `evergreen-wiki/` として作成し、利用時は `~/.claude/skills/evergreen-wiki` への symlink を張る
- ドキュメント類(SKILL.md / references / 本設計書)はすべて日本語で記載する

#### 未決事項: 既存 `llm-wiki` skill との併存(symlink 配備前に要決定)

`~/.claude/skills/` には別リポジトリ由来の `llm-wiki` skill が既にインストールされており、本 skill と次の点で競合する。

- 同じファイルレイアウト(index.md + log.md + notes/&lt;slug&gt;.md)・同じ type 語彙(concept / entity)を持つ
- トリガー語が重複する(「ナレッジを検索して」「lint して」等)
- 発動ポリシーが正反対(llm-wiki は自律発動あり / 本 skill は明示呼び出しのみ)
- bundle モデルが異なる(llm-wiki は単一統合 wiki / 本 skill は user + project の複数 bundle)

この状態で symlink を張ると skill 選択が非決定的になるため、配備前に次のいずれかを決定する: (a) llm-wiki を置換(supersede)する、(b) トリガー語を棲み分けて併存させる、(c) 本 skill は symlink せずプロジェクトローカルで使う。

## 7. スコープ外(将来の拡張ポイント)

- Attested Computation type(OKF §10): ナレッジベース用途では不要
- bundle をまたぐリンク・bundle 間の知識移動: 必要になった時点で設計する
- 自律トリガー(作業中の気づきの自動 Ingest): 本 skill は明示呼び出しのみ
