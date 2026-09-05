# レビュープロファイル：SQL Weekly（dbt プロジェクト）

`sql/_weekly/task_w_{NN}/` のレビューで、手法ファイル（`review_1_correctness` / `review_2_quality`）と**併せて読む。**

## 実行の可否

**実行しない。** `dbt run` / `dbt test` / `run_sql.py` / Snowflake への接続はすべて禁止（クレジットを消費する）。

机上トレースで導き、**実行していないことをレビュー冒頭に明記する。**

## 読む対象 — 提出物は入れ子になっている

**Daily と違い、提出物はタスクフォルダ直下に無い。** dbt プロジェクトとして入れ子になっている。

```
sql/_weekly/task_w_01/
  README.md                    ← 課題文
  setup.sql                    ← DDL とサンプルデータ
  {プロジェクト名}/              ← ここから下が提出物
    dbt_project.yml
    packages.yml
    models/staging/*.sql
    models/staging/_*__sources.yml     ← ソース定義
    models/staging/_stg_*__models.yml  ← テスト定義
    models/mart/*.sql
    models/mart/_*__models.yml
    macros/*.sql
    tests/*.sql                        ← singular test
```

**`ls -R` でプロジェクト全体を確認してから読む。** そして以下をすべて読む。

| ファイル | 目的 |
|---|---|
| `README.md` | 課題文。要求と制約 |
| `setup.sql` | DDL とサンプルデータ。机上トレースに必須 |
| `models/**/*.sql` | **提出版のモデル。レビューの主対象** |
| `models/**/*.yml` | **ソース定義とテスト定義。`.sql` だけ読んでレビューを書かない** |
| `dbt_project.yml` | materialization の既定値、`vars`、モデルパス設定 |
| `macros/*.sql`, `tests/*.sql` | あれば。マクロと singular test |
| `packages.yml` | 依存パッケージ |

**`.yml` を読み飛ばすとレビューが成立しない。** dbt ではソース定義とテスト定義が全部 yml にあるため。

## dbt 固有の正確性の観点

- **`ref()` / `source()` を使っているか** — テーブル名を文字列でハードコードしていないか。ハードコードすると DAG が繋がらず、環境をまたいだ実行が壊れる
- **層の分離** — `staging` は1ソース1モデルで、リネーム・型変換・軽いクレンジングのみか。**ビジネスロジックが staging に漏れていないか**。集計や結合は `intermediate` / `mart` の責務
- **materialization の選択** — `view` / `table` / `incremental` が妥当か。`dbt_project.yml` の既定と個別 `config()` の整合。巨大な中間結果が `view` のままメモリを圧迫していないか
- **incremental の場合** — `unique_key` の指定、`{% if is_incremental() %}` の絞り込み条件、遅延データ（Late-Arriving Data）が来たときに二重集計・取りこぼしを起こさないか。`insert_overwrite` と `merge` の選択理由
- **Jinja** — `{{ var() }}` で対象期間を外から渡せるか。同じロジックの重複がマクロ化されているか

## テスト定義（必ず見る）

**`_*__models.yml` の `data_tests:` を必ず確認する。** ここが「検証の設計」の弱点に直結する。

| 見るもの | 判定 |
|---|---|
| `not_null` / `unique` | 主キーに付いているか。付けただけで満足していないか |
| **`relationships`** | 参照整合性。**過去のタスクでは一度も使われていない** |
| **`accepted_values`** | 区分値の網羅。**同じく未使用** |
| **singular test（`tests/*.sql`）** | **過去のタスクでは全件ゼロ。** schema test では捕まえられない異常（粒度の崩れ、集計値の急変、0件の区間）を書けているか |

**各テストについて「そのテストが失敗する入力を1つ挙げられるか」を判定する。** 挙げられないテストは機能していない。`not_null` と `unique` だけで「テストを書いた」ことにはならない。

## イディオム・パフォーマンス

- **窓関数の前に絞り込めているか。** `WHERE` を CTE の外に置くと全件に `ROW_NUMBER` が走る
- **Sargable か** — カラムに関数を適用するとプルーニングが効かない
- 集約前の `ORDER BY`、`LATERAL FLATTEN` を絞り込み前に実行していないか
- 不要な `SELECT *`（列を絞らないと Spillage リスクが上がる）
- **`SET` 文に依存していないか** — dbt モデルは単一 SELECT がテーブル/ビューに展開されるため、`SET` 文は本文に置けない。`{{ var() }}` に置き換える

## 命名

- **`stg_<source>__<entity>`** の規約に従っているか（ソース名とエンティティ名を二重アンダースコアで区切る）
- `fct_` / `dim_` / `int_` の使い分け
- **層を示す接頭辞の誤用** — 処理ステップ名の CTE に `raw_` を付けていないか
- yml のファイル名規約（`_<source>__sources.yml` / `_stg_<source>__models.yml`）

## 本番運用の必須トレース（dbt 版に読み替える）

| 観点 | dbt では何を見るか |
|---|---|
| **0件入力** | ソースが空のとき、モデルが落ちるか・空テーブルを作るか。下流のモデルとテストが壊れないか |
| **冪等性** | **`dbt run` を2回叩いて同じ結果か。** incremental は特に（2回目で重複が積まれないか） |
| **バックフィル** | `--full-refresh` で作り直せるか。`--vars '{target_date: ...}'` のように対象期間を外から渡せるか。**渡せるなら問題なしと書いてよい** |

そのほか：`dbt test` が失敗したときにパイプラインが止まる設計になっているか（`severity: warn` で通してしまっていないか）。

## 修正版の出力 — 複数ファイルなのでツリーで置く

**1ファイルでは表現できない。** `FB_from_AI_{NN}/corrected/` 配下に、**元のプロジェクトと同じ相対パス**で置く。

```
FB_from_AI_01/
  README.md
  corrected/
    models/staging/stg_apexpay__raw_transactions.sql
    models/staging/_stg_apexpay__models.yml
    models/mart/fct_monthly_merchant_financial_summary.sql
    tests/assert_no_duplicate_grain.sql
```

- **変更したファイルだけ置く。** 無変更のファイルはコピーしない
- したがって **`corrected/` は dbt プロジェクトとして実行できない**（`dbt_project.yml` や `packages.yml` を含まないため）。`corrected/README.md` の冒頭に「これは差分の置き場で、実行可能なプロジェクトではない。元のプロジェクトの同じ相対パスに上書きして使う」と明記する
- `corrected/README.md` に**どのファイルをなぜ変えたかの一覧**を書く（各ファイル冒頭のコメントではなく、1箇所にまとめる。dbt の `.sql` はコメントが Jinja と混ざって読みにくいため）
- 指摘した全項目と課題文の全制約を**同時に満たす**こと
- **実行していないことを明記する**
- **テストの不足を指摘したなら、テストも書く。** 指摘だけして `tests/*.sql` を置かないのは修正版として不完全
