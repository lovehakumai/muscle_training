# task04 レビュー（日付操作のエッジケースとISO週番号・年をまたぐ集計の罠）

対象：`task04/my_answer.sql`、PR（環境起因で取得できなかったため、既存FBの引用からコミットメッセージを推測してレビューしています）

> 注記：コードは実行せず、机上トレースと静的読解で評価しています。

## 課題の主題と、その攻略
**主題：** 日付操作のエッジケース（年末年始など）においても、決定論的に先週の月曜〜日曜を正しく切り出せるか。
**攻略：** 見事に攻略できています。`DAYOFWEEKISO` を使って曜日を数値化し、そこから月曜までの差分を逆算する `-(DAYOFWEEKISO($SESSION_DATE) - 1) - 7` というロジックは、年をまたいでも絶対に破綻しない本質的な解法です。

## 良かったところ
### 1. 模範解答に依存しない逆算ロジックの構築 — 自力で計算式を組み上げた証拠
```sql
dateadd(day, -(DAYOFWEEKISO($SESSION_DATE) - 1) - 7, $SESSION_DATE) as baseline
```
既存の模範解答と結果は一致しますが、提出版は `date_trunc` に頼ることなく、純粋な日付の加減算だけで月曜を導き出しています。これは丸暗記ではなく、日付関数の挙動を頭の中でシミュレーションしながら自力で組み立てた証拠です。非常に素晴らしいです。

## 制約の充足
* 制約1: 実行環境に依存する動的関数の禁止 → **満たしている**（`$SESSION_DATE`から逆算）
* 制約2: Sargable（パーティション刈り込み可能）な範囲指定 → **違反**（`datediff` に `sale_timestamp` カラムを渡しており、非Sargableになっています。既存FB指摘済）
* 制約3: ISO週基準での正確な週境界の算出 → **満たしている**（`DAYOFWEEKISO` を適切に使用）
* 制約4: CTEは2段階まで → **違反**（`base`、`raw_get_baseline`、`raw_extract_targets` の3段階になっています）

## 技術的な評価
### 正確性
#### ① 【既存FB未指摘】GROUP BY抜けによる、0件入力時のサイレント障害
```sql
    select
        MIN(baseline) as week
        , SUM(amount) as amount_sum
    from raw_get_baseline
    where target_flg
```
**壊れる条件：** もし対象週の売上が1件もなかった場合（テーブル自体が空、または `where target_flg` を通過する行が0件の場合）。
`GROUP BY` のない集計クエリは、0行入力でも必ず1行を返します。この場合 `(NULL, NULL)` というレコードが出力され、後続処理で NOT NULL 制約のあるカラムに挿入しようとすると落ちます。
**次にどうするか：** 集計を行う際は必ず `GROUP BY` を指定し、0件入力時には正しく「0行」が返るようにします。

#### ② 【既存FB未指摘】無意味な ORDER BY による制約違反
```sql
with base as (
    select * from raw_weekly_sales order by sale_timestamp 
)
```
**壊れる条件：** RDB において、CTE 内での `ORDER BY` は最終的な結果の順序を一切保証しません（オプティマイザに無視されます）。これによって意味もなくCTEが1段消費され、「2段階まで」の制約に違反してしまっています。
**次にどうするか：** `base` CTEを削除し、直接テーブルから読み込みます。

#### ③ 【既存FB未指摘】時刻成分が含まれていた場合の境界のズレ
現状の `baseline` は `$SESSION_DATE` の時刻成分をそのまま引き継ぎます。
**壊れる条件：** もし `$SESSION_DATE` が `2026-09-01 15:30:00` だった場合、`baseline` も `15:30:00` になります。これと `sale_timestamp` を比較する際、厳密な 00:00:00 の境界にならず、意図しないオフバイワンを引き起こすリスクがあります。
**次にどうするか：** 既存FBの模範解答のように、日付の起点を算出する時点で `DATE_TRUNC('DAY', ...)` を使い、時刻成分を 00:00:00 に正規化します。

### イディオム・パフォーマンス
既存FBが「スカラサブクエリなのでプルーニングが100%効く」と断定していますが、**これは過剰な断定（幻覚）です。**
オプティマイザの定数畳み込みに依存する話であり、必ず保証されるものではありません。確実にプルーニングを効かせたい場合は、1行だけ返すCTEを `CROSS JOIN` でメインテーブルに結合し、そのカラムを使って `>=` および `<` で比較する（Sargableな指定）のが安全なイディオムです。

### 可読性・命名
**層を示す接頭辞の誤用**
`raw_get_baseline` や `raw_extract_targets` のように、処理ステップ名の CTE に `raw_` を付けています。dbt などにおいて `raw_` は「生データ層」を示す厳格な規約として扱われるため、中間処理にこの名前をつけると他のエンジニアが誤読します。
**次にどうするか：** `get_baseline` や `date_boundaries` など、処理の実態に合わせた接頭辞のない名前にします。

### 本番運用の視点
0件入力・再実行・バックフィルの3点をトレースした結果、以下1件が該当します。
* **0件入力**: 上記の通り、`GROUP BY` がないため `(NULL, NULL)` が返る欠陥があります。
* **再実行・バックフィル**: `$SESSION_DATE` を外部から注入可能な設計のため、冪等性が担保されており、任意の過去日での再集計も可能です。問題ありません。

### 英語のスキル
（今回は環境起因でPR全体を取得できなかったため、既存FBが引用している文章からコミットメッセージをレビューします）
* `data spilage will makes credit higher.`
  * **助動詞の後は原形**: `will makes` → `will make`
  * **スペルミス**: `spilage` → `spillage`。スペルミスは git 履歴に残り、後から検索する際にヒットしなくなるため注意が必要です。
* `easy enough to catche up for other engineers.`
  * **スペルミス**: `catche up` → `catch up`
  * よりプロフェッショナルな表現として、既存FBの `ensuring high readability` の提案は非常に優れています。

**添削版PR本文（参考）**
```markdown
feat(pipeline): implement deterministic weekly sales aggregation

This query extracts the total amount of sales from Monday to Sunday of the previous week.
By calculating `week_start_date` via `DAYOFWEEKISO` and cross-joining it as a boundary, it ensures idempotency regardless of the execution day.

Note:
I avoided calculated columns in the `WHERE` clause. This ensures Sargable filtering, preventing partition-scanning inefficiencies and an increase in warehouse credit consumption, while keeping high readability for other team members.
```

## 一言だけ聞きたいこと（丸暗記か理解かの確認）
1. `base` CTE で `ORDER BY sale_timestamp` を行っていますが、このソートは最終結果の何に影響を与えることを意図していましたか？
2. もし `raw_weekly_sales` に対象週のデータが1件もなかった場合、提出いただいたクエリ（`GROUP BY` なし）は何行・どんな値を返すでしょうか？机上でトレースしてみてください。（既存FBの模範解答も同じ挙動になります）

## まとめ
**再生できている部分：** `DAYOFWEEKISO` を用いた週境界の算出ロジックは、丸暗記では決して出てこない、自力での見事な到達点です。
**穴：**
* **浅い層**: `raw_` 接頭辞の誤用、文法上のスペルミス（`spilage`、`catche`）
* **中間**: CTE内での無意味な `ORDER BY`
* **深い層**: `GROUP BY` なしの集計における0件入力時の挙動（サイレント障害への発展）

**既存FBが見落としていた点・過剰な断定の一覧：**
* `GROUP BY` 抜けによる0件入力時のバグを見落とし（既存FBの模範解答も同じバグを抱えています）
* CTEが3段階になっている制約違反を見落とし
* CTE内の無意味な `ORDER BY` を見落とし
* 「スカラサブクエリなら100%プルーニングが効く」という過剰な断定（オプティマイザ依存であり保証はない）

次は実務の増分更新（Incremental model）を想定した遅延データ（Late-Arriving Data）のハンドリングに挑戦してみましょう！
