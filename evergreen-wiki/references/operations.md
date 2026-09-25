# evergreen-wiki 操作手順(operations)

本書は evergreen-wiki skill が提供する4操作(Init / Ingest / Query / Lint)の実行手順を定める。書式・分類・マージ・相互リンクの規約は `references/conventions.md` を参照し、本書では重複して記載しない。

以下のコマンド例における `scripts/*.sh` は、この skill のディレクトリ(`evergreen-wiki/`)からの相対パスで示す。実行時のカレントディレクトリはユーザーのプロジェクトであり skill ディレクトリとは限らないため、実際に実行する際は skill ディレクトリの絶対パス(本ファイルが置かれている `evergreen-wiki/` の実パス)起点に読み替える。

## 1. Init(bundle 作成)

1. **scope を確認する**。user scope(個人の汎用知識)か project scope(現在のプロジェクト固有知識)かを、依頼内容や文脈から判断する。判断できない場合は AskUserQuestion ツールでユーザーに確認する。
2. **既存 bundle の発見を先に行う**。`scripts/bundle-locate.sh --scope all` を実行し、対象 scope の bundle が既に存在するか確認する。見つかった場合は新規作成せず、発見した bundle のパスを報告して終了する。

   場所を先にユーザーへ確認してしまうと、実際には別の場所に既存 bundle がある場合に二重 bundle が生まれ、Query がその両方を対等に読み込んでしまう。そのため「発見が先、場所の確認は見つからない場合のみ」という順序を必ず守る。

3. **見つからない場合のみ、場所を決定する**。
   - user scope: `~/knowledge/` に固定する(環境変数 `EVERGREEN_USER_BUNDLE` で上書きされている場合はその値)。場所の確認は不要。
   - project scope: `git rev-parse --show-toplevel`(git 管理外の場合は CWD)配下の候補(`docs/knowledge/` 等)を提示し、AskUserQuestion ツールでユーザーに確認して決定する。`bundle-locate.sh` は `index.md` をプロジェクトルートから深さ4まで(`find -maxdepth 4`)しか探索しない。つまり発見できるのは bundle ディレクトリ自体が深さ3以内(例: `docs/knowledge/` は深さ2、`a/b/c/` は深さ3)のものだけで、これより深い場所を候補として選ぶと、以後の Query/Lint/Ingest がこの bundle を発見できなくなる。候補提示時は bundle ディレクトリが深さ3以内の場所に限定する。
4. **scaffold を作成する**。bundle root に以下の3点を作成する。

   `index.md`:

   ```markdown
   ---
   okf_version: "0.2"
   ---

   # concept

   # entity

   # note
   ```

   `log.md`(見出しの日付は Init を実行した当日の日付を `YYYY-MM-DD` 形式で記入する):

   ```markdown
   # Update Log

   ## 2026-08-25

   - bundle 作成
   ```

   `notes/`: 空のディレクトリを作成する(以降の Ingest で `notes/<slug>.md` を追加していく)。

5. **git 管理を推奨として案内する**。user bundle は独立した git リポジトリとして管理することを提案する(可搬性と履歴保持のため)。project bundle は既存のプロジェクトリポジトリにそのままコミットしてよい。いずれも強制はしない。

## 2. Ingest(取り込み)

1. **候補の選別**。取り込む前に次の基準で足切りする: 一般化できるか / 非自明か / 繰り返し起こりうるか / まだ bundle に無いか。作業ログ・そのタスク限定の一過性の状態・コードを読めば自明な内容は取り込まない。
2. **scope 振分**。プロジェクト固有の知識は project bundle へ、汎用的な教訓は user bundle へ振り分ける。

   ```bash
   scripts/bundle-locate.sh --scope all
   ```

   で両 scope の bundle を確認し、振分に迷う場合のみ AskUserQuestion ツールでユーザーに確認する。project bundle が存在しない場合は user bundle へ入れる(振分のために勝手に Init を実行しない)。

3. **既存照合**。新規ページを作る前に、対象 bundle の `index.md` を読み、さらに `wiki-query.sh` で同趣旨のページが無いか機械的に探す。

   ```bash
   scripts/wiki-query.sh --bundle <bundle-path> --keyword "<キーワード>"
   scripts/wiki-query.sh --bundle <bundle-path> --tag <tag> --type note
   ```

   出力は `<bundle>\t<slug>\t<type>\t<status>\t<description>` の形式(1行1ページ)。同趣旨のページが見つかった場合はマージ(本文統合 + `sources` 追記 + `generated` 更新。判定基準は conventions.md §8)、見つからない場合は正準形式(conventions.md §3)で新規作成する。

   マージ時、既存の `verified` は削除せず保持する。「現在有効な検証」かどうかは `verified.at >= generated.at` で機械的に判定される(conventions.md §9)ため、マージで `generated.at` を更新しても過去の検証イベント自体は失わない。

4. **相互リンク**。関連する既存ページとの間に双方向リンク(`[label](/notes/<slug>.md)`、conventions.md §6)を張る。関連する `concept` / `entity` ページへも接続する。関連する `entity` がまだ無い場合はスタブとして新設してよい。
5. **カタログ更新**。`index.md` の該当 type セクションへ1行追加し、`log.md` の当日見出しの下に追記する(見出しが無ければ新設。conventions.md §7)。
6. **報告は書き込み完了後に行う**。`index.md` / `log.md` / `notes/<slug>.md` への書き込みがすべて完了してから、取り込み内容をユーザーへ報告する。同一 bundle への Ingest は逐次実行する(複数の Ingest を並列に走らせて同一 bundle へ同時書き込みしない)。

## 3. Query(参照)

1. **bundle 発見**。`scripts/bundle-locate.sh --scope all` で存在する全 bundle(user + project)を洗い出す。
2. **該当ページの特定**。各 bundle の `index.md` を読みつつ、`wiki-query.sh` で機械的に絞り込む。

   ```bash
   scripts/wiki-query.sh --type concept
   scripts/wiki-query.sh --tag <tag>
   scripts/wiki-query.sh --keyword "<キーワード>"
   scripts/wiki-query.sh --slug <slug>
   ```

   `--bundle` を省略すると `bundle-locate.sh` が発見した全 bundle を横断検索する。出力の `<bundle>\t<slug>` から対象ファイル(`<bundle>/notes/<slug>.md`)を特定する。
3. 該当ページの本文を読み、`## 関連` の相互リンクをたどって関連知識を辿る。
4. どの bundle のどのページを根拠にしたかを出典として明示して回答する。`status: deprecated` のページや `stale_after` を超過したページを回答に使う場合は、その旨を明示する。
5. **回答の還元**。複数ページを突き合わせたことで既存のどのページにも無い新しい統合や洞察が生まれた場合(例: 複数の note を貫く関係に気づいた、既存ページの欠落に気づいた)、その内容を Ingest 手順(本書 §2)に渡してナレッジとして bundle へ還元する。一過性の検索結果を列挙しただけの回答は還元しない。

## 4. Lint(健全化)

1. **機械チェック**。対象 bundle を指定して(または全 bundle に対して)実行する。

   ```bash
   scripts/wiki-lint.sh --bundle <bundle-path>
   scripts/wiki-lint.sh --bundle <bundle-path> --json
   ```

   `--bundle` を省略すると `bundle-locate.sh` が発見した全 bundle を対象にする。出力は `<severity>\t<check>\t<bundle>\t<file>\t<detail>`(`--json` 指定時は同内容を1行1 JSON オブジェクトで出力)。`ERROR` が1件でもあれば exit code は `1`、`SUGGEST` のみ、または検出なしの場合は `0` になる。

   check id とその意味・対処方法は次のとおり(実装 `scripts/wiki-lint.sh` に完全準拠)。

   **ERROR(機械的事実。存在すれば必ず修正する)**

   | check id | 検出内容 | 対処方法 |
   |---|---|---|
   | `conformance-structure` | bundle 直下に予約ファイル(`index.md` または `log.md`)が存在しない | 該当ファイルを conventions.md §7 の正準形式で作成する。存在しない間、その bundle では当該ファイルに依存する横断検査(`index-miss` / `index-format` / `log-format`)がスキップされる |
   | `conformance-frontmatter` | frontmatter が存在しないか、閉じる `---` が無い | conventions.md §3 の正準形で frontmatter を追加する |
   | `conformance-type` | `type` フィールドが欠落または空 | `type` に `note` / `concept` / `entity` 等を設定する |
   | `actor-format` | `generated` / `verified` の `by:` が actor 記法(`^(human:.+\|process:.+\|[^/ ]+/[^/ ]+)$`)に違反 | conventions.md §3 の actor 記法(`human:<id>` / `process:<id>` / `<producer>/<version>`)に沿って書き直す |
   | `slug-format` | `notes/` 配下のファイル名が slug 規則(`^[a-z0-9][a-z0-9-]*$`、conventions.md §5)に違反 | ファイル名を slug 規則に沿って変更する。違反ページは正規リンク記法で参照できないため、相互リンク検査(`broken-link` / `one-way-link` / `orphan` / `index-miss`)の対象外になる |
   | `source-id-dup` | `sources[].id` が同一ページ内で重複している(脚注の結合キーが曖昧になり、無音の出典取り違えを招く) | 重複する要素の `id` を付け直す(本文の脚注ラベルも追随させる。conventions.md §3・§8) |
   | `footnote-ref` | 本文の脚注ラベル `[^<id>]` が同ページの `sources[].id` のいずれとも一致しない(fenced code block・インラインコード内は検査対象外) | `sources` に該当 id を持つ要素を追加するか、脚注ラベルを既存の id に合わせる(conventions.md §4・§6) |
   | `link-format` | 本文中の `](/notes/...)` リンクが正規形式 `[label](/notes/<slug>.md)` でない(空 slug・規則外 slug 等。fenced code block・インデントコード・インラインコード内の記法の例示は検査対象外。`broken-link` / `one-way-link` / `orphan` も同様) | conventions.md §6 のリンク記法に修正する |
   | `broken-link` | 本文中の `[label](/notes/<slug>.md)` のリンク先が bundle 内に存在しない | リンク先ページを作成するか、リンクを削除・修正する |
   | `index-miss` | `notes/` 配下のページが `index.md` に記載されていない | `index.md` の該当 type セクションへ1行追加する |
   | `index-dangling` | `index.md` のエントリが存在しないページ(`/notes/<slug>.md`)を記載している(ページ統合・削除の取り残し) | エントリを削除するか、後継ページのエントリに差し替える |
   | `one-way-link` | A→B のリンクがあるのに B→A のリンクが無い(片方向リンク) | B 側のページに A への逆リンクを追加し双方向にする |
   | `orphan` | `type: note` のページが他のどのページからもリンクされていない(孤立ページ) | 関連する既存ページからリンクするか、`## 関連` に関連ページを追加する |
   | `index-format` | `index.md` の frontmatter に `okf_version` 以外のキーがある、`okf_version` が無い(frontmatter ごと無い場合を含む。bundle マーカー喪失で `bundle-locate.sh` から発見されなくなる)、またはエントリ行(`* ` / `- ` 始まりの行)が `* [title](/notes/slug.md) - description` 形式でない(`- ` 箇条書きも違反として検出する) | conventions.md §7 の正準形式に修正する |
   | `log-format` | `log.md` の日付見出しが `## YYYY-MM-DD` 形式でない、または新しい日付が上に来る降順で並んでいない | conventions.md §7 の正準形式に修正する |

   **SUGGEST(判断材料。exit code には影響しない)**

   | check id | 検出内容 | 対処方法 |
   |---|---|---|
   | `canonical-form` | frontmatter のキー順序が正準順(conventions.md §3)でない、または `verified` / `sources` が単一マッピングで書かれている(1要素でもリスト形式でない) | conventions.md §3 の正準形に正規化する。外部プロデューサー由来の非正準 YAML はエラーではなく正規化の提案として扱う(conventions.md §3「OKF 許容原則」) |
   | `source-id-format` | `sources[].id` が slug 規則(`^[a-z0-9][a-z0-9-]*$`)に違反(OKF 的には妥当な id もありうるため、正規化の提案として扱う。なお規則外の id は脚注結合検査 `footnote-ref` の対象にならない) | conventions.md §3 の id 規則に沿って付け直す(本文の脚注ラベルも追随させる) |
   | `stale` | `stale_after` の期限を超過している | 内容を見直し、`stale_after` の更新、または `status: deprecated` への変更を検討する(conventions.md §9) |
   | `verify-stale` | 最新の `verified.at` が `generated.at` より古い(検証失効。マージで内容が変わったのに再検証されていない) | 内容を再確認し、`verified` に新しい検証イベントを追記する(既存の `verified` は削除しない) |
   | `concept-candidate` | 同一タグを `concept` 以外のページが5件以上共有しているが、そのタグを持つ `concept` ページが無い | 該当ページ群を束ねる `concept` ページの新設を検討する(conventions.md §5) |

2. **LLM 意味チェック**。機械チェックでは検出できない、内容面の矛盾・重複・陳腐化・欠落している `concept` を洗い出す。複数ページを読み比べ、同趣旨なのに別ページになっているもの、矛盾する記述、実質的に古い情報を検出する。
3. **変更の適用**。加算的な変更(リンクの追加、`index.md` の記載漏れ補完など)は検出次第そのまま実行してよい。破壊的な変更(ページの統合、`status: deprecated` への変更)はまとめてユーザーに提示し、一括で承認を得てから適用する。
4. 適用した変更を `log.md` の当日見出しの下に記録する。
