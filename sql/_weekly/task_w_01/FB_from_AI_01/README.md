# SQL Weekly task_w_01 レビュー（dbt のテスト設計）

対象：`models/`, `tests/` 配下のSQLおよびYAMLファイル

> 注記：コードは実行せず、机上トレースと静的読解で評価しています。
> 進捗：Pass 1・Pass 2 完了。

## 課題の主題と、その攻略
今回の主題は「dbtのテスト設計において、SQLで記述する singular test を用いて本番のデータ異常を水際で防ぐこと」でした。
指定した2つの異常（金額とポイントの符号不一致、日付のスキップ）に対するテストを自力で実装できており、方向性としては十分攻略できています。

## 良かったところ
### 1. 相談内容を doc ブロックに残していること
`int_transactions_cleanse.sql` の冒頭に `[ESCALATION]` と `[CONCLUSION]` として、ユニーク制約をどのように定義すべきかの業務判断プロセスを書き残している点が素晴らしいです。このようにコードの背景にある「なぜそう決めたのか（Why）」のコンテキストを dbt のソースコード側に残すのは、保守性を劇的に高めるベストプラクティスです。

### 2. QUALIFY 句を使ったスマートな重複排除
事前の相談通り、`QUALIFY ROW_NUMBER() OVER (PARTITION BY transaction_id ORDER BY transaction_timestamp DESC) = 1` を使って最新のトランザクションを抽出できています。CTEを無駄に深くせず、シンプルかつ堅牢に書けています。

## 制約の充足
- `models/` 配下に、`fct_user_daily_points` (user_id, date, total_points_earned, transaction_count) の集計モデルを作成すること → **違反（要修正）**。作成自体はできていますが、列名が要件（`date`, `total_points_earned`）と異なっており、また `transaction_count` カラムが含まれていません。
- モデルに対し、`not_null`, `unique` などの generic tests を設定すること → **不十分（要修正）**。`int_transactions_cleanse` 側は完璧ですが、`fct_user_daily_points` は `(user_id, transaction_timestamp)` の組み合わせで一意になるテーブルにもかかわらず、その一意性を保証するテストがありません（`dbt_utils.unique_combination_of_columns` などを使用するか、サロゲートキーを生成してテストする必要があります）。
- singular tests を少なくとも2つ作成すること → **満たしている**（`num_combination.sql`, `consective_date.sql`）。

## 正確性
### ① `consective_date.sql` における誤検知（正常なデータでテストが落ちるバグ）
**現象と壊れる条件：**
`fct_user_daily_points` に複数のユーザーが同じ日に購入したレコードがあった場合、このテストは必ず失敗（誤検知）します。
例えば、出力テーブルに以下の行があるとき：
1. (user_id=1, transaction_timestamp='2026-09-01')
2. (user_id=2, transaction_timestamp='2026-09-01')

`order by transaction_timestamp` で `LAG` を取ると、2行目（user_id=2）の前回日付（`pre_transaction_timestamp`）は 1行目の '2026-09-01' になります。
このとき `datediff` は `0` となり、`!= 1` の条件に合致してしまうため、完全に正常な「連続した日のデータ」であってもテストがエラーとして検知してしまいます。

**次にどうするか：**
システム全体の「日付のスキップ（0件区間）」を検知したい場合は、ユーザー単位のテーブルを直接調べるのではなく、まず `DISTINCT` で「存在する日付」の一覧を作り、その一覧に対して `LAG` をかける必要があります。また、同日の重複を弾くか1日以上空いたときだけを検知するため、条件は `> 1` を使うのが安全です（修正版の `corrected_consective_date.sql` を参照してください）。

### ② 異常値（Outlier）に対するテストの欠如
**現象と壊れる条件：**
シナリオに記載した「異常に巨大なポイント」の罠について、用意した `raw_transactions` には `('TXN-006', 5, '2026-09-05 10:00:00', 99999999, 999999)` のような異常値が含まれていました。
しかし現在のテスト網ではこれを検知できず、そのまま集計されて下流に流れてしまいます。`num_combination.sql` は符号と NULL をチェックしていますが、金額の上限や桁数の異常はチェックしていません。

**次にどうするか：**
（※制約の「少なくとも2つ」は満たしているので課題としてはクリアですが、本番運用の観点からの補足です）
`purchase_amount` や `points_earned` に対して、「絶対にありえない閾値（例: 10万ポイント以上など）」を超えたら失敗する generic test（dbt-expectationsパッケージの活用など）か singular test を追加することで防御できます。

## 本番運用の視点
0件入力・再実行（決定論性）・バックフィルの3点をトレースした結果、すべて問題なし（クリア）です。

- **0件入力:** `fct_user_daily_points` は `GROUP BY` を持つため、入力が0件の場合は空のテーブルを返し、エラーになりません。
- **再実行（決定論性）:** `QUALIFY ROW_NUMBER() OVER (ORDER BY transaction_timestamp DESC)` により、最新のタイムスタンプが確定的に選ばれるため、冪等性が担保されています。
- **バックフィル:** 全件洗い替えの `table` / `view` 想定のため、期間依存のロジックはありません。

## イディオム・パフォーマンス
- **テストクエリの `SELECT *`**: `consective_date.sql` で `SELECT 1` を返していますが、dbt の singular test では `SELECT *` で失敗したレコードそのものを返すのがベストプラクティスです。そうすることで、コンパイルされたビューを叩いたときに「どの行が原因でテストが落ちたのか」を直接確認（インスペクト）できます。
- **YAML の分割と配置**: `stg_ecommerce__transaction.sql` に対するテストや説明が `_ecommerce__properties.yml` に書かれていますが、慣例としては `_stg_ecommerce__models.yml` などのように層とエンティティを名前に入れることが多いです。また、層ごとに `_properties.yml` とするという名前も悪くはないですが、プロジェクトが拡大した際にどのエンティティの定義なのかファイル名から分かりにくくなります。

## 可読性・命名
- **日付への切り捨てによる命名のズレ**: `fct_user_daily_points` で `date_trunc('day', transaction_timestamp)` として日付に丸めた後も、カラム名を `transaction_timestamp` のままにしています。「タイムスタンプ（時刻を含む）」という名前のまま中身が「日付（00:00:00）」になっていると、後続の利用者が「時刻情報も入っている」と誤認しやすくなります。`transaction_date` や単に `date` とリネームするのが安全です（要件としても `date` でした）。
- **スペルミス**: `consective_date` -> `consecutive_date` (u が抜けています)。また PR 内の `Sinbular` -> `Singular`。スペルミスはファイル名に入ると後から直すのが大変なので注意が必要です。
- **doc ブロックの活用への気づき**: PR のコメントにある通り、`int_transactions_cleanse.sql` の冒頭に書いた長大な業務コンテキストは、dbt の `docs` ブロックとして定義し、YAML の `description: '{{ doc("cleanse_logic") }}'` のように参照させるのが dbt のベストプラクティスです。この気づきは非常に素晴らしいです。

## Pass 1 への補足
- **修正版スクリプトの出力形式**: Pass 1 は修正版のファイルを `FB_from_AI_01/` 直下にフラットに置いてしまいましたが、dbt のルール（`sql_weekly` プロファイル）では `corrected/models/mart/...` のようにツリー構造で出力する必要があります。（本Pass 2 の指摘はスクリプトそのものを大きく変更するものではないため、既存の修正版スクリプトはそのままにしています）。

## 一言だけ聞きたいこと（丸暗記か理解かの確認）
1. `dbt_project.yml` で `task_w_01` 全体のデフォルトを `+materialized: "view"` とし、`mart` フォルダだけ `table` に上書きしています。もし `int_transactions_cleanse` の処理結果が数億行になり、後続の複数のデータマートから頻繁に参照されるようになった場合、`intermediate` 層の materialization はどう変更するのが適切でしょうか？またその理由は何ですか？
2. `fct_user_daily_points.sql` の `GROUP BY` で `date_trunc('day', transaction_timestamp)` を使っています。もし、元データが UTC で記録されており、これを「日本時間（JST）での日次集計」に直す要件が追加されたら、この SQL のどの部分をどう変えますか？

## まとめ
**再生できている部分：**
- `QUALIFY` 句を使ったシンプルで堅牢な最新レコードの抽出
- プロジェクトの `materialized` の階層的なデフォルト設定（`view` と `table` の使い分け）
- なぜその主キーを選んだかという業務的背景（Escalation と Conclusion）の言語化

**穴：**
- [深い] テスト設計：複数ユーザーが混在するテーブルでの `LAG` の誤検知（Partition や Distinct の不足による、正常データのテスト失敗）
- [中間] イディオム：dbt の singular test における `SELECT *` の欠如（デバッグ容易性の低下）
- [浅い] 命名・可読性：Truncate した日付を timestamp という名前で維持してしまうミス、およびスペルミス

**今回通用した解法：**
- `QUALIFY ROW_NUMBER() OVER (...) = 1` を用いた重複排除
- 複数条件の組み合わせに対する `OR` を用いた singular test

**次にやるべき課題の提案：**
- **Surrogate Key と複数カラムの Unique テスト**: PR コメントで言及されていた `dbt_utils.generate_surrogate_key` を実際に用いて、複合主キー（`user_id` と `date` など）に対するテストを実装する。
