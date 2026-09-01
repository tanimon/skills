# evergreen-wiki 書式規約(conventions)

本書は evergreen-wiki skill が管理する OKF v0.2 準拠 bundle の書式・分類・マージ・相互リンクに関する規範である。Init / Ingest / Query / Lint の各操作、および `wiki-lint.sh` 等のスクリプトはすべて本書の規則を実装・参照する。

## 1. bundle 構造

各 bundle は以下の3種類のファイルのみから成る、完全に独立した OKF bundle である。

```
<bundle-root>/
├── index.md          # okf_version: "0.2" を frontmatter に持つ唯一のファイル。全ページのカタログ
├── log.md            # OKF 予約構造: ## YYYY-MM-DD 見出し(新しい順)+ 箇条書き
└── notes/<slug>.md   # 1知識 = 1ファイル(atomic)。フラット配置、分類は tags と相互リンク
```

- `notes/` の配下はフラット配置とする。サブディレクトリによる階層分類は行わない。分類は tags と相互リンクで表現する(§4・§5・§6 参照)。
- リンクは bundle 内で閉じる。bundle をまたぐ相互リンクは張らない。これは OKF bundle の可搬性(`cat` と `git clone` だけで完結する)を保つための制約であり、bundle 間の知識移動は本規約のスコープ外とする。
- bundle root を特定するマーカーは `okf_version` frontmatter を持つ `index.md` の存在そのものである。専用のレジストリ・設定ファイルは持たない。

## 2. 三層モデル

evergreen-wiki が扱う知識は次の3層に分かれる。

1. **Raw source(生の出典)**: PR・コード・ドキュメント・調査セッション等、真実の出典。bundle には保存せず、各ページの frontmatter `sources[].resource` で参照するのみとする。URI を持つ出典(PR URL 等)はその URI をそのまま記録する。URI を持たない出典(会話・ターミナル出力等)は OKF が許容するスコープ記述子(例: `"2026-08-25 デバッグセッション: CI失敗の原因調査"`)として記録する。raw source の内容をコピー・改変して bundle 内に格納することはしない。
2. **Bundle**: evergreen-wiki skill が所有・維持する OKF bundle そのもの。人間はこれを読む側であり、書式の整形やマージ等の bookkeeping は skill が担う。
3. **Schema**: この skill の SKILL.md と本書 `references/conventions.md`。書式・分類・マージ・相互リンクの規約を定める層であり、bundle の内容そのものではない。

raw source の実体を bundle 内に保存する設計(`sources/` ディレクトリを設けて生データを複製する等)は採らない。bundle の肥大化・可搬性低下を招き、OKF の provenance 参照モデル(出典は参照であり複製ではない)からも外れるためである。

## 3. frontmatter スキーマと正準シリアライズ形式

### frontmatter の意味論

`notes/<slug>.md` の frontmatter は以下のフィールドから構成される。

| フィールド | 区分 | 意味 |
|---|---|---|
| `type` | 必須(OKF Conformance) | ページの種別。open set(§4 参照) |
| `title` | 推奨 | 表示名。本文 H1 と一致させる |
| `description` | 推奨 | 1文要約 |
| `tags` | 推奨 | kebab-case のタグ配列(§5 参照) |
| `sources` | 任意(Provenance 族) | raw source への参照。`resource` を持つ要素のリスト |
| `generated` | 任意(Trust 族) | 内容を実質的に書いた actor と時刻(§9 参照) |
| `verified` | 任意(Trust 族) | 検証イベントの蓄積(§9 参照) |
| `status` | 任意(Lifecycle 族) | `draft` \| `stable` \| `deprecated`。省略時 `stable`(§9 参照) |
| `stale_after` | 任意(Lifecycle 族) | 時限性のある知識にのみ付与する失効時刻(§9 参照) |

### 正準シリアライズ形式(canonical form)

本書は frontmatter の意味論だけでなく、**シリアライズ形式そのもの**を規範として定める。evergreen-wiki が新規作成・更新するすべてのページは、次の形式に厳密に従う。

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

正準形の規則は以下のとおりである。

- **キー順序の固定**: `type` `title` `description` `tags` `sources` `generated` `verified` `status` `stale_after` の順に、存在するものだけをこの順で並べる。
- **インデントは2スペース固定**とする。
- `tags` はインラインフロー形式 `[a, b]` の1行で記述する。
- `sources` / `verified` は**要素が1件であっても必ずブロックリスト形式**(`  - key: value`)で記述する。単一マッピングでの省略形は使わない。
- `sources` の各要素は `- resource: "<値>"` の1行1キーとする。
- `generated` はネストマッピング(`  by:` / `  at:` の2行)とする。
- `verified` の各要素は `- by: <actor>` の行に続けて、その1段下のインデント(先頭の `- ` に合わせて4スペース)で `at: <値>` を記述する、2行1要素とする。
- actor 記法(OKF §7 準拠)は次の正規表現に従う: `^(human:.+|process:.+|[^/ ]+/[^/ ]+)$`。すなわち `human:<id>`(人間)、`process:<id>`(自動プロセス)、`<producer>/<version>`(LLM 等のプロデューサー)のいずれかの形式をとる。個人を特定できる実名は書かず、`human:<id>` のようなプレースホルダを用いる。
- `at` の時刻は ISO 8601 UTC(`YYYY-MM-DDTHH:MM:SSZ`)形式とする。前後比較は文字列比較で行える形式であるため、日付パーサへの依存を持たない。
- `status` は `draft|stable|deprecated` のいずれかであり、省略時は `stable` として扱う。

正準形を定める理由は2つある。

1. evergreen-wiki がページの唯一のプロデューサーである限り、常に正準形で書き出すことができる。
2. lint を bash + 標準ツール(grep/awk/sed)のみで実装するためである。これらのツールは YAML を意味的にパースできず、既知の正準形への行アンカーによるパターンマッチしかできない。正準形を規範化することで、「(a) 正準形に一致するかどうかの検証」→「(b) 正準形を前提とした意味チェック」という二段構えの lint が成立する。

### OKF 許容原則(外部プロデューサー由来の非正準 YAML の扱い)

evergreen-wiki 以外のプロデューサーが書いた、正準形ではないが OKF 的には妥当な YAML(例: 単一マッピングの `verified`。OKF はコンシューマー側で1要素リストとして扱うことを求める)は、**エラーとして拒絶しない**。これは「正準形違反」として正規化を提案する対象として扱う。これは OKF の「コンシューマーは自身が理解できないものを許容する」という原則に従うものであり、lint が外部由来の bundle を誤って拒絶することを防ぐための取り扱いである。

## 4. type 体系

`type` は OKF Conformance 上必須のフィールドであり、open set である。evergreen-wiki が定義するコアの3種類は以下のとおりである。

| type | 役割 |
|---|---|
| `note` | atomic な知見・教訓。1ページ1知識(Evergreen notes の atomic 原則に従う) |
| `concept` | 複数の `note` を貫く横断的洞察の結節点ページ。関連する `note` が接続されるたびに育つ |
| `entity` | 固有名詞(プロジェクト・ツール・仕組み)の参照ハブ。スタブとして生まれ、バックリンクの蓄積によって意味が定義されていく |

上記3種類以外の `type` も許容する。OKF は未知の `type` を容認しており、将来の用途に応じて新たな `type` を自由に追加できる。

### 本文テンプレート

`type` によらず、すべてのページは共通して次の構造をとる。

(以下は fenced code block ではなく4スペースインデントで記述している。フェンスにすると実例中の `## 関連` が章見出しの機械検証(`grep '^## '`)に誤って含まれるため)

    # <title>

    <本文。type に応じた内容を記述する>

    ## 関連

    - [label](/notes/<slug>.md)
    - [label](/notes/<slug>.md)

- H1 見出しは frontmatter の `title` と一致させる。
- 本文には知識の内容そのものを記述する。`note` であれば atomic な知見1件、`concept` であれば複数の `note` を貫く洞察、`entity` であればその固有名詞に関する参照情報を記述する。
- `## 関連` セクションに、関連するページへの双方向リンク(§6 参照)を列挙する。他のどのページからもリンクされていない `type: note` のページ(孤立ページ)は Lint がエラーとして検出する(`concept` / `entity` はバックリンク蓄積を待つ性質上、孤立していても検出対象外。operations.md §4 の `orphan` 参照)。

## 5. slug・tag 命名

### slug

- 正規表現 `^[a-z0-9][a-z0-9-]*$` に従う。英語の kebab-case とする。
- bundle 内で一意でなければならない(`notes/<slug>.md` のファイル名が識別子を兼ねるため)。
- slug は内容を簡潔に表す英語表現とし、日本語の音写やタイムスタンプの機械的な付与は避ける。

### tags

- kebab-case で記述する。
- 分類は階層ディレクトリではなく tags と相互リンクによって表現する。これは Evergreen notes の設計原則(atomic・concept-oriented・densely linked であり、階層分類を持たない)に従うものである。
- `concept` 以外のページ(`note` / `entity` 等)が同じ tag を5件以上共有するクラスタは、`concept` ページへ昇華させる候補として Lint が検出する(operations.md 参照)。

## 6. リンク記法

- リンクは bundle-relative の絶対形式 `[label](/notes/<slug>.md)` のみを用いる(OKF が推奨する Absolute 形式)。
- 相対リンク(`[label](../notes/foo.md)` や `[label](foo.md)` 等)は用いない。
- bundle 外へのリンク(他の bundle の `notes/` や任意の外部 URL への `[label](...)` 形式のリンク)は張らない。外部の出典は本文リンクではなく frontmatter の `sources[].resource` で表現する(§2・§3 参照)。
- 関連するページ同士は必ず双方向にリンクする。A のページから B へリンクした場合、B のページからも A へのリンクを追加する。片方向リンクは Lint がエラーとして検出する対象である。

## 7. index.md / log.md 書式

箇条書き記号はファイルごとに固定する: `index.md` のエントリ行は `* `、`log.md` の変更履歴と本文の `## 関連`(§4)は `- ` を用いる。`wiki-lint.sh` の `index-format` はこの規則を前提に検査する(`- ` で書かれた index エントリ行は形式違反として検出される)。

### index.md

bundle root にのみ存在し、`okf_version: "0.2"` を持つ唯一のファイルである。

```markdown
---
okf_version: "0.2"
---

# concept

* [並行書き込みが壊れる理由](/notes/concurrent-write-race.md) - 複数プロセスの同時書き込みが競合状態を生む共通原因
* [キャッシュ無効化の設計原則](/notes/cache-invalidation-principles.md) - キャッシュ更新タイミングに関する横断的な指針

# entity

* [evergreen-wiki](/notes/evergreen-wiki.md) - 本 skill 自身に関する参照ハブ

# note

* [シェルのパイプは exit code を隠す](/notes/shell-pipe-exit-code.md) - パイプ末尾のコマンドの exit code だけが返るため中間の失敗が見えない
```

- 本文は `# セクション見出し` に続けて `* [title](/notes/<slug>.md) - <description>` を列挙する形式とする。
- セクションは `concept` → `entity` → `note` の順に並べる。
- 各行の `<description>` は該当ページの frontmatter `description` と一致させる。

### log.md

(以下は fenced code block ではなく4スペースインデントで記述している。フェンスにすると実例中の `## YYYY-MM-DD` が章見出しの機械検証(`grep '^## '`)に誤って含まれるため)

    # Update Log

    ## 2026-08-25

    - [シェルのパイプは exit code を隠す](/notes/shell-pipe-exit-code.md) を新規作成
    - [キャッシュ無効化の設計原則](/notes/cache-invalidation-principles.md) に sources を追記しマージ

    ## 2026-08-24

    - [evergreen-wiki](/notes/evergreen-wiki.md) を新規作成

- `# Update Log` の下に `## YYYY-MM-DD` 見出しで日付ごとにグルーピングし、新しい日付が上に来る順(降順)で並べる。
- 同日内の変更は箇条書きで列挙する。

## 8. マージ判定基準

Ingest 時に既存ページと新規知見を統合するかどうかは、次の基準で判定する。

- **同趣旨の定義**: 「同じ状況で同じ判断を導く知見」を同趣旨とみなす。表現や具体例が異なっていても、読み手が同じ場面で同じ結論に到達するのであればマージ対象である。逆に、表面上の言葉が似ていても異なる状況・異なる判断を導く知見は別ページとして扱う。
- **マージ時の操作**: 同趣旨のページが既存であった場合、新規ページを作らず既存ページへ次の3点を反映する。
  1. 本文を統合する(新たな知見・具体例・反例を既存の記述に織り込む)。
  2. frontmatter `sources` に新しい出典を追記する(既存の `sources` は削除しない)。
  3. frontmatter `generated` を、この統合作業を行った actor と時刻で更新する。
- **`generated` を更新しない場合**: 誤字修正・インデント修正・リンク記法の正規化など、実質的な内容変更を伴わない書式調整のみを行った場合は `generated` を更新しない。`generated` は「内容を実質的に書いた actor と時刻」を表すフィールドであり、書式上の変更はこれに該当しない(§9 参照)。

## 9. Trust / Lifecycle 運用

### Trust 族(`generated` / `verified`)

- **`generated`**: ページの新規作成時、および実質的な内容変更(マージを含む)のたびに更新する。書式調整のみでは更新しない(§8 参照)。
- **`verified`**: 内容の検証イベントを追記する形で蓄積する。既存の要素を上書きしない。主な運用はユーザーによる内容確認(actor は `human:<id>`)だが、自動チェックによる検証(`human:` 以外の actor)も許容する。
- **trust tier の導出**: `verified` フィールドの状態から、次の3段階の trust tier が導出される。
  - `verified` が存在しない → unverified
  - `verified` が存在するが `human:` actor を含まない → machine-confirmed
  - `verified` に `human:` actor を含む要素がある → human-reviewed
- **検証の失効条件**: `verified` イベントは履歴として保持し続けるが、「現在有効な検証」とみなされるのは `at >= generated.at` を満たす要素のみである。マージによって `generated.at` が更新されると、それより前の `verified` イベント(過去の人間検証を含む)は実質的に失効する。Lint はこの状態を「再検証候補」として検出する。

### Lifecycle 族(`status` / `stale_after`)

- **`status` の使い分け**:
  - `draft`: 確信度の低い暫定知識。
  - `stable`(既定値。省略時はこの値として扱う): 通常運用される知識。
  - `deprecated`: 陳腐化した知識。**削除はせず** `deprecated` にした上で、後継ページへのリンクを本文または `## 関連` に追加する。これは知識の履歴を保つための運用であり、`deprecated` ページを bundle から取り除くことはしない。
- **`stale_after`**: バージョン依存・期限つきの知識にのみ付与する。値は絶対 ISO 8601 時刻とし、相対 TTL(「作成から1年」等)では表現しない。時限性を持たない一般的な知識には付与しない。Lint は `stale_after` の期限超過を機械的に検出する(現在時刻との文字列比較で判定可能な ISO 8601 UTC 形式を用いるため、日付パーサを必要としない)。
