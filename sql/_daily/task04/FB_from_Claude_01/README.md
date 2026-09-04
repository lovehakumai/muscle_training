# sql/task04 レビュー（ISO週境界の決定論的な逆算）

対象：`sql/_daily/task04/my_answer.sql`（提出版）、`sql/_daily/task04/FB/ai_answer.sql`（模範解答）、`sql/_daily/task04/FB/README.md`（既存FB）、`sql/envs/init_sql/task04.sql`（DDL）、PR #5 `feat(pipeline) weekly summary and its baseline is monday`

> 注記：**コードは実行していません。** Snowflake への接続を伴うため、机上トレースと静的読解のみで評価しています。以下に出てくる集計値・境界値は、DDL のサンプルデータに対してコードを追って導いたもので、実測値ではありません。

---

## 良かったところ

このタスクは既存FBが後から模範解答を提示する形式なので、**提出版に書かれているものはすべて自力の産物**です。その前提で、模範解答と「一致した箇所」＝独力で正解に到達した箇所を中心に挙げます。

### 1. 週境界の核心式を、模範解答と完全に同一の形で導いている

```sql
dateadd(day, -(DAYOFWEEKISO($SESSION_DATE) - 1) - 7, $SESSION_DATE) as baseline
```

模範解答の該当箇所と**式が完全に一致しています**（模範解答は外側に `date_trunc` が付くだけ）。これは後から写せるものではなく、提出時点で自力で組み立てたものです。

この式が正しい理由を分解すると、3つの判断が同時に正しく行われています。

1. **`DAYOFWEEKISO` を選んだ** — ここが最大の分岐点です。`DAYOFWEEK` は Snowflake の `WEEK_START` パラメータの影響を受け、環境設定次第で日曜始まりになります。`DAYOFWEEKISO` は**常に月曜=1で固定**され、パラメータに影響されません。制約3「Snowflakeのパラメータによる曜日設定の揺れに依存せず」を、関数選択ひとつで満たしています
2. **`-(DAYOFWEEKISO - 1)` で今週の月曜に着地させた** — 火曜(2)なら -1、月曜(1)なら 0。制約にあった「月曜実行か火曜実行か」に依存しない構造がここで担保されています
3. **さらに `- 7` で先週の月曜へ** — 2段階に分けたことで式の意図が読めます

### 2. 「年をまたぐ罠」を、特別扱いゼロで無力化している

課題文が「毎年必ずどこかでバグを発生させる**死の罠**」と呼んでいたのは、カレンダー年とISO年の不整合です。`2025-12-29`（月）は ISO では **2026年の第1週**に属します。

ここで多くの人が `WEEKISO()` や `YEAROFWEEKISO()` で週番号を出してから範囲を組み立てようとして落ちます。年境界で `YEAR()` と `YEAROFWEEKISO()` が食い違うためです。

**あなたのアプローチは、そもそも週番号を一度も materialise していません。** 基準日から日数を引くだけなので、年境界に特別な分岐が要りません。机上で追うと：

`SET SESSION_DATE = '2026-01-06'`（火）のとき
`DAYOFWEEKISO = 2` → `-(2-1) - 7 = -8` → `2026-01-06 - 8日 = 2025-12-29`（月）✓

年が変わっても、うるう年でも、ISO年が1つズレていても、この式は影響を受けません。**課題が主題として設定していた罠に対して、構造的に免疫のある解を選べている**——これが今回いちばん評価すべき点です。既存FBは冒頭で「決定論的な設計」と抽象的に褒めていますが、なぜ免疫があるのかまでは書いていないので補強しておきます。

### 3. 模範解答があなたの命名と構造を採用している

模範解答の2段目のCTE名は `raw_extract_targets` です。**これはあなたが提出版で使った名前そのものです。** 模範解答を書いた側が、あなたの構造をそのまま踏襲したということです。

「先に境界を作る → 次に集計する」という2段構成の骨格も同じです。つまり**設計レベルでは既に正解の形に到達していて、以下で指摘するのは全て「その骨格の中の実装ディテール」**です。ここは自信を持ってよい部分です。

### 4. PR で、聞かれていない将来のリスクまで踏み込んでいる

```
This logic always read all rows in `raw_weekly_sales` table...
1. For Extract data -> Add CLUSTERING KEY
2. For updating table -> Add incremental model with dbt
```

課題は「クエリを書け」でしたが、**全件スキャンになるという性質と、その2つの対策（クラスタリングキー／dbtのincrementalモデル）まで自発的に書いています。** 実装報告で終わらせず、運用コスト（クレジット）の観点を持ち込むのは、指示されて書けるものではありません。

さらに `I can support both actions, please feel free to tell me.` と**引き取る意思まで示している**のは、レビュー依頼として完成度が高いです。英文の粗さは後述しますが、**何を書くべきかの判断は既にシニアの水準**です。

---

## 技術的な評価

既存FBの2点（`BETWEEN 0 AND 7` の8日間バグ／計算列でのフィルタによるプルーニング崩壊）は正しいので繰り返しません。**そこで指摘されていない問題**を挙げます。

### 正確性

#### ① 【既存FB未指摘・最重要】`DATE_TRUNC` が無いため、既存FBの修正指示に素直に従うと**データ欠損バグに変わる**

これが今回いちばん重要な指摘です。既存FBは対策として

> * `sale_timestamp >= baseline`
> * `sale_timestamp < DATEADD(day, 7, baseline)`

と書いています。**この指示だけを覚えて再実装すると、本番で売上が消えます。**

理由：あなたの `baseline` には `DATE_TRUNC` が付いていません。

```sql
-- 提出版
dateadd(day, ... , $SESSION_DATE) as baseline          -- 時刻成分がそのまま残る

-- 模範解答
date_trunc('day', dateadd(day, ... , $SESSION_DATE))   -- ← この date_trunc の説明が既存FBに無い
```

今回は `SET SESSION_DATE = '2026-09-01 00:00:00.000'` と**ちょうど深夜0時**を渡しているので、`baseline` も `2026-08-24 00:00:00` になり問題が出ません。しかし**本番のバッチは実行時刻を渡します。**

`SET SESSION_DATE = '2026-09-01 03:15:00'` の場合（火曜 3:15 起動のバッチ）：

| | 値 |
|---|---|
| `baseline` | `2026-08-24 03:15:00` ← 深夜0時ではない |
| 既存FBの修正後の条件 | `sale_timestamp >= 2026-08-24 03:15:00` |
| `S_002`（`2026-08-24 01:10:00`、月曜未明の売上） | `01:10 < 03:15` → **除外される** |

**先週月曜の 00:00〜03:15 の売上が、毎週黙って消えます。** 行数も変わらず、エラーも出ず、合計金額だけが少しずつ小さくなる——検知が最も難しいクラスの事故です。

なぜ今の提出版ではこれが起きないかというと、`DATEDIFF('day', ...)` が**時刻成分を切り捨てて日付単位で数える**ため、`baseline` の時刻の汚れを結果的に吸収しているからです。**2つの雑さが打ち消し合っているだけ**で、設計として成立してはいません。

**次にどうするか：** 境界の計算に `DATE_TRUNC('day', ...)` を必ず入れる。

```sql
date_trunc('day', dateadd(day, -(DAYOFWEEKISO($SESSION_DATE) - 1) - 7, $SESSION_DATE)) as week_start
```

持ち帰る原則は「**基準日（境界）は正規化する。データ側のカラムは加工しない。**」制約2が禁じているのは *`sale_timestamp` カラムを* 加工することで、**境界側を `DATE_TRUNC` するのは推奨されるべき正反対の行為**です。この2つを混同しないでください。

#### ② 【既存FB未指摘】売上が1件も無い週に、`(NULL, NULL)` の行を1行返す

```sql
select
    MIN(baseline) as week
    , SUM(amount) as amount_sum
from raw_get_baseline
where target_flg
```

`GROUP BY` の無い集計クエリは、**入力が0行でも必ず1行返します。** 該当週の売上がゼロだった場合（連休・障害でデータ未着・上流の連携停止など）、この行の中身は：

- `MIN(baseline)` → 入力が0行なので **NULL**
- `SUM(amount)` → 同じく **NULL**

つまりレポートに `week = NULL, amount_sum = NULL` が1行出ます。「売上0円の週」ではなく「壊れたレコード」に見えます。下流でこの `week` を主キーやパーティションキーに使っていれば、そこで落ちます。

なお模範解答は `week` をスカラサブクエリで取っているので日付は残りますが、`sum(amount)` は同じく NULL です。**両方とも対処されていません。**

**次にどうするか：** 週ラベルは集計関数から取らず、金額はゼロ埋めする。

```sql
select
    $WEEK_START as week                      -- 定数なので集計に依存しない
    , coalesce(sum(amount), 0) as amount_sum -- 0件の週は 0 と報告する
```

`MIN(baseline)` が動く理由も確認しておいてください。`baseline` は行ごとに同じ定数なので `MIN` を取れば同じ値になる——**動きますが、「定数を集計している」という無駄な表現**になっています。読んだ人は「なぜ MIN なのか、行ごとに違う値があるのか」と考え込みます。

#### ③ 制約4「CTEは2段階まで」を満たしていない（CTEが3つある）

```sql
with base as (...)               -- 1
, raw_get_baseline as (...)      -- 2
, raw_extract_targets as (...)   -- 3
```

PR にはこう書かれています。

> And this query includes only 2 ctes aside from base cte,

**`base` を除外して数えれば2つ、という数え方をしています。** 自覚的だったことは分かりますが、制約は「CTEは2段階まで」であって除外規定はありません。これは**制約違反**です。

制約付きの課題で制約を外すと、その課題の学習価値が失われます。今回の制約4は「境界計算と集計を、中間テーブルを挟まず2段で書け」という設計上の縛りであり、そこを守る工夫こそが練習対象でした。

**次にどうするか：** `base` は削除できます（次項の通り、削るべき理由が別にもあります）。削れば CTE は2つになり、制約を満たします。

なお、**制約を外す判断をした場合の作法**も覚えておいてください。PR で「制約を満たしている」と読める書き方をせず、`The query uses three CTEs; the constraint allowed two. I kept the extra one because ...` と**逸脱として明示し理由を書く**のが正解です。レビュアーが見落とすリスクを消せます。

### イディオム・パフォーマンス

#### ④ 【既存FB未指摘】`base` CTE の `ORDER BY` は、無意味なうえに**このクエリで最もスピレージを起こしやすい操作**

```sql
with base as (
    select * from raw_weekly_sales order by sale_timestamp
)
```

2つの問題があります。

**(a) 効果がない。** SQL では、サブクエリ/CTE 内の `ORDER BY` は外側のクエリの出力順を保証しません。順序が保証されるのは最外側の `ORDER BY` だけです。しかも今回は最終的に1行に集約するので、順序に意味がありません。

**(b) コストが最悪。** ソートは全行をメモリに載せて並べる操作で、**メモリに収まらなければ local/remote のディスクに退避します。これがまさに Spillage です。**

ここが今回のいちばん皮肉な点です。**PR であなた自身が Spillage を懸念してクラスタリングキーを提案しているのに、クエリ本体には全件ソートが入っています。**

```
PR: data spilage will makes credit higher.  → 対策としてクラスタリングキーを提案
実装: select * from raw_weekly_sales order by sale_timestamp  → 全件ソート
```

5行のサンプルでは差が出ませんが、1000万行では**このクエリで最初に溢れるのはこの `ORDER BY`** です。クラスタリングキーを追加してもソートは消えません。

**次にどうするか：** `base` CTE を丸ごと削除する。制約違反（指摘③）も同時に解消します。持ち帰る原則は「**集約するクエリの途中に `ORDER BY` を書かない。順序が要るのは最終出力だけ。**」

#### ⑤ 【既存FB未指摘】`case when <条件> then true else false end` は、条件式そのものと同じ

```sql
, case
    when datediff('day', baseline, sale_timestamp) between 0 and 7 then true
    else false end as target_flg
```

`between` は既にブール値を返すので、`CASE` で `true`/`false` に包み直す意味がありません。

```sql
, datediff('day', baseline, sale_timestamp) between 0 and 7 as target_flg  -- 同じ意味
```

指摘としては軽微ですが、**「ブール値をブール値に変換している」という構造に気づけるかは、型を意識して書けているかの指標**になります。なお最終形ではこの列自体が不要になります（`WHERE` に直接書く＝既存FBの指摘②）。

#### ⑥ 既存FBの「スカラサブクエリなら100%プルーニングが効く」は、言い過ぎ

既存FBは模範解答についてこう書いています。

> クエリ実行の超初期段階で値が確定するため、スキャンする前に「どのパーティションを読むべきか」を完全に決定できます

方向性は正しいのですが、**`(select last_week_start from date_boundaries)` は「コンパイル時に確定したリテラル」ではありません。** オプティマイザがこのパターンを定数畳み込みできるかに依存します（Snowflake は動的プルーニングも行いますが、「100%」と断言できる形ではありません）。

今回の課題は**すでに `SET` でセッション変数を使う構成**なので、もっと確実な形があります。**境界もセッション変数にしてしまう**ことです。

```sql
SET SESSION_DATE = '2026-09-01 03:15:00.000'::timestamp_ntz;
SET WEEK_START = date_trunc('day', dateadd(day, -(DAYOFWEEKISO($SESSION_DATE) - 1) - 7, $SESSION_DATE));
SET WEEK_END   = dateadd(day, 7, $WEEK_START);

select ...
from raw_weekly_sales
where sale_timestamp >= $WEEK_START
  and sale_timestamp < $WEEK_END
```

こうすると述語の両辺が**クエリに渡る前に確定した値**になるので、オプティマイザの賢さに依存しません。副産物として**CTEが0個になり、制約4も余裕でクリア**します。

原則は「**プルーニングを効かせたいなら、境界をクエリの外に出す。** オプティマイザに推論させる余地を減らすほど確実になる」。

> 実行して `EXPLAIN` / Query Profile を確認していないので、実際のプルーニング挙動は未検証です。上は「オプティマイザへの依存度を下げる」という設計上の議論として読んでください。

### 可読性・命名

#### ⑦ `baseline` という名前が、何の基準なのかを言っていない

`baseline` は「基準」ですが、**何の基準か**が読み取れません。実体は「先週の月曜 00:00:00」＝集計期間の開始境界です。

```sql
baseline      →  last_week_start / week_start
```

境界は必ず**開始と終了のペア**で扱うので、`week_start` / `week_end` と対称に命名すると、`>=` と `<` のどちらを当てるかも自明になります。「半開区間 `[week_start, week_end)`」という定型に乗せられるのが、名前を揃える実利です。

#### ⑧ `week` 列が日付なのか週番号なのか分からない

出力の列名 `week` に入っているのは**日付**（先週の月曜）です。`week` という名前だと週番号（`2026-W36` 等）を期待されます。`week_start_date` のように**粒度と型を名前に入れる**と、下流で誤解されません。

#### ⑨ `USE SCHEMA` のハードコード

```sql
USE SCHEMA MUSCLE_DB_TASK04.RAW;
```

ドリルとしては問題ありませんが、dbt に載せる際は**モデル内に `USE SCHEMA` を書かない**（`profiles.yml` と `generate_schema_name` の責務）ことを意識しておいてください。task01 で `generate_schema_name` マクロを扱っているので、その知識と接続する箇所です。

### 本番運用の視点

#### ⑩ 「先週」の定義が、実行が遅れた場合に破綻する

要件は「毎週火曜日に先週分を集計」で、実装は「実行日の週の月曜から7日前」です。つまり**「先週」を実行日基準の相対値として定義**しています。

火曜のバッチが失敗して**水曜に手動再実行**した場合：水曜 `DAYOFWEEKISO = 3` → `-(3-1)-7 = -9` → 同じ月曜に着地します。ここは正しく動きます（曜日非依存の設計が効いている）。

ところが**翌週の火曜まで復旧しなかった場合**、基準日が1週間ずれるので、集計されるのは「その週から見た先週」＝**落ちた週の分は永久に集計されません**。

**次にどうするか：** 本番のバッチは、実行日ではなく**対象期間そのものをパラメータで受ける**のが定石です（dbt なら `var('week_start')`、Airflow なら論理実行日 `data_interval_start`）。

```sql
SET WEEK_START = '2026-08-24'::timestamp_ntz;  -- 対象週を外から与える
```

「実行日から逆算」は**今回の課題の制約1が要求したもの**なので提出版は正解です。そのうえで、実務では逆算のさらに外側に「対象期間を明示的に渡せる口」を用意する、という段階があることを覚えておいてください。冪等な再実行（バックフィル）ができるかどうかが分かれます。

#### ⑪ 結果の検証手段がない

このクエリは合計値を1つ返すだけで、**その値が正しいかを確認する手段が同梱されていません。** 実務では、境界のオフバイワンは今回のように必ず起きるので、境界そのものをテストします。

```sql
-- 境界の妥当性を目視できるようにする（開発時）
select $WEEK_START as week_start, $WEEK_END as week_end,
       dayname($WEEK_START) as start_dow,   -- 'Mon' であること
       datediff('day', $WEEK_START, $WEEK_END) as span_days;  -- 7 であること
```

`span_days = 7` と `start_dow = 'Mon'` を確認するだけで、今回の8日間バグは提出前に発見できました。dbt なら singular test に落とせます。**「境界を計算したら、境界自体をアサートする」**を癖にすると、この種のバグは構造的に防げます。

### 英語のスキル（PR #5）

既存FBは `data spilage will makes credit higher` と `easy enough to catche up` の2箇所を添削しています。それ以外を挙げます。

#### 最優先：PRの仕様記述そのものが間違っている（バグと同じ間違いをしている）

```
This sql extract the 7 days from that monday, (between `2026-08-24` ~ `2026-08-31`) .
```

**`2026-08-31` は実行週の月曜で、集計対象外です。** つまり PR の説明文が、コードの8日間バグと**同じ誤りを記述しています。**

これは英語の問題ではなく**レビュー可能性の問題**です。レビュアーがこの説明を読んでコードを見ても、「説明と実装が一致している」ので**バグに気づけません。** 説明が正しければ、実装との食い違いから発見できました。

さらに `the 7 days` と言いながら範囲が8日分書かれているという**内部矛盾**もあります。

**次にどうするか：** 期間は必ず**半開区間の記法**で書く。

```
Aggregates the seven days starting from that Monday: [2026-08-24 00:00, 2026-08-31 00:00)
```

`[` と `)` を使うだけで「開始は含む、終了は含まない」が一目で伝わり、**書いた本人が矛盾に気づけます。** 期間を扱う仕様は口語で書かず、この記法に統一してください。

#### 文法：主語と動詞の一致（3箇所）

```
✗ This sql extract the 7 days ...        → extracts
✗ This logic always read all rows ...    → reads
✗ this model update table efficiently and decrease credit  → updates / decreases
```

三単現の `-s` が3箇所落ちています。**技術文書は主語が三人称単数（`This query`, `The model`, `This logic`）になりがちなので、動詞に `-s` が付いているかを機械的に見る**チェックポイントにしてください。

#### 文法：`recommend` の語法

```
✗ For avoiding this I recommend you to 2 actions
✓ To avoid this, I recommend two actions:
```

3点あります。

1. **`For avoiding` → `To avoid`。** 目的を表すのは `to` 不定詞です。`for + -ing` は用途（`a tool for cutting`）に使います
2. **`recommend you to <名詞>` は成立しません。** `recommend` は `recommend + 名詞` / `recommend that S (should) V` / `recommend -ing` を取り、`recommend someone to do` は非標準です。ここは目的語が名詞なので `I recommend two actions` で足ります
3. **数字は文中では綴る**（`2` → `two`）のが技術文書の慣習です。箇条書きの番号はそのままで構いません

#### 文法：`makes` の目的語欠落

```
✗ this simple architecture makes easy enough to catche up for other engineers.
✓ this simple structure makes it easy enough for other engineers to follow.
```

`make` は `make + 目的語 + 補語` を取るので、**形式目的語 `it` が必要**です（`makes it easy`）。また `catch up` は「遅れを取り戻す」で、ここで言いたい「理解する・追える」は `follow` / `follow along`。`architecture` はクエリ1本には大きすぎるので `structure` が適切です。

#### 語彙・スペル

```
✗ Additionaly   → Additionally
✗ spilage       → spillage
✗ catche        → catch
✗ this sql      → this SQL / the query
✗ ctes          → CTEs
✗ monday        → Monday（曜日は常に大文字始まり）
```

`Additionaly` / `spilage` / `catche` は3件ともスペルミスです。**そして `monday` の小文字は PR タイトルとコミットメッセージにも入っています。**

前回の task02 で `claense` が git 履歴に残った件と同じ構図です。マージ済みのコミットメッセージは修正できないので、**コミット欄でもスペルチェックが効く設定**（VSCode なら Code Spell Checker）を入れる価値があります。

#### 語彙：`credit` は不可算の集合名詞として扱う

```
✗ data spilage will makes credit higher / decrease credit
✓ increase / reduce warehouse credit consumption
```

Snowflake の課金単位としての `credit` は、`credit consumption`（消費量）や `credit usage` と書くのが正確です。`credit` 単体だと「信用」「貸方」とも読めます。既存FBの添削もこの方向でした。

#### 表現：ぼかしすぎている箇所

```
✗ I'd love to share the problem in future about this logic.
✓ I would also like to flag a potential issue with this logic.
```

3点。**語順**（`in future about this logic` → 修飾の位置が離れすぎ）、**`in future` → `in the future`**（英では冠詞なしも使われますが、技術文書では `the` 付きが無難）、そして**`the problem` → `a potential issue`**。定冠詞 `the problem` は「既知の、その問題」を指すので、初出の懸念には `a` を使います。

`I'd love to` は「〜したくてたまらない」で、リスク報告のトーンには強すぎます。`I would like to flag ...` が定型です。

#### 表現：カンマスプライス

```
✗ I can support both actions, please feel free to tell me.
✓ I can take on either of these — let me know if you would like me to.
```

独立した2文をカンマだけで繋ぐのは誤りです（カンマスプライス）。ピリオド、セミコロン、ダッシュ、接続詞のいずれかが必要です。

また `both actions` は「2つとも実施する」と読めます。「どちらでも対応できる」なら `either of these`。

#### タイトルとコミットメッセージ

```
✗ feat(pipeline) weekly summary and its baseline is monday
✓ feat(pipeline): add weekly sales summary anchored to last Monday

✗ feat(pipeline) add fb from ai
✓ docs(task04): add AI feedback and model answer
```

- **コロンが必須**です（Conventional Commits のパーサが認識できません）。前回も同じ指摘をしています
- タイトルに `and its baseline is monday` という**節を繋げない**。要約は名詞句で「何を追加したか」を書く（`anchored to last Monday` のように分詞で修飾する）
- 2つ目のコミットはフィードバック文書の追加なので、**`feat` ではなく `docs`**。type を正しく選ぶと `git log --grep` や自動 CHANGELOG が機能します
- `fb` / `ai` は略語のまま小文字にしない（`FB` / `AI`）

#### 添削版PR本文

```markdown
# Purpose
Build the weekly sales report that aggregates the previous ISO week
(Monday 00:00 through Sunday 23:59) from a given reference date.

The query never calls `CURRENT_DATE()` or `CURRENT_TIMESTAMP()`, so the result
depends only on the reference date it is given -- not on who runs it, where, or
on which weekday. Re-running it for the same reference date always produces the
same row.

# How
`DAYOFWEEKISO` returns 1 on Monday regardless of the `WEEK_START` parameter, so
subtracting `(DAYOFWEEKISO - 1)` lands on the current week's Monday and a further
7 days lands on the previous week's Monday. Because no week number is ever
materialised, the year-crossing case needs no special handling:

    reference 2026-09-01 (Tue) -> [2026-08-24 00:00, 2026-08-31 00:00)
    reference 2026-01-06 (Tue) -> [2025-12-29 00:00, 2026-01-05 00:00)

The second range spans the calendar-year boundary; `2025-12-29` belongs to ISO
week 1 of 2026.

The boundaries are computed once into session variables and compared against the
raw `sale_timestamp` column, so the predicate stays sargable and no function is
applied to the partitioning column.

# Known limitation
The query scans the full table today, which will increase warehouse credit
consumption as the table grows. Two options, either of which I can take on:

1. **For reads** -- add a clustering key on `sale_timestamp` so the engine can
   prune micro-partitions instead of scanning all of them.
2. **For writes** -- convert this into a dbt incremental model so each run
   processes only the new week.

Let me know which you would prefer.
```

変えたところの意図を3点だけ。**期間を半開区間 `[start, end)` で書いた**（自分でオフバイワンに気づける）。**年をまたぐケースを実例で示した**（この課題の主題なので、対応済みであることが伝わる）。**`Known limitation` という見出しで懸念を切り出した**（実装報告と将来課題が混ざらず、レビュアーが読み分けられる）。

---

## 一言だけ聞きたいこと（丸暗記か理解かの確認）

模範解答と一致していた箇所は理解の判定材料になるので除き、**あなた独自の実装だった箇所**について3問だけ。

1. **`SET SESSION_DATE = '2026-09-01 03:15:00'` に変えたうえで、既存FBの指示どおり `>=` と `<` に書き換えたとします。`S_002`（`2026-08-24 01:10:00`）は集計に入りますか？**
   （指摘①の核心です。模範解答に `date_trunc` が付いている理由を自分の言葉で説明できれば答えは出ます。「境界を正規化する」と「カラムを加工しない」が別の話だと分かっているかの確認）

2. **制約4は「CTEは2段階まで」でした。`base` CTE を残した判断を、いま自分の言葉で説明できますか？ また `base` を削ると、制約以外に何が改善されますか？**
   （指摘③④。PR に「`aside from base cte`」と書いた時点で違反は自覚されていたはずなので、なぜ残したのかを言語化してみてください。削って改善するものが2つあります）

3. **先週の売上が1件も無い週にこのクエリを実行すると、結果は何行返り、その中身はどうなりますか？**
   （指摘②。`GROUP BY` の無い集計クエリの挙動と、`MIN(baseline)` が定数に対する集計であることが繋がれば答えられます）

---

## まとめ

**再生できている部分：** 週境界の核心式（`DAYOFWEEKISO` の選択、`-(dow-1)-7` の2段階の逆算）を模範解答と同一の形で自力導出、年をまたぐ罠に構造的に免疫のある方針の選択、2段構成の骨格と命名（模範解答がそれを踏襲している）、PR での自発的なコスト分析と改善提案。**課題の主題は完全に攻略できています。**

**穴を3段階に分けると：**

1. **語彙・作法**（`case when ... then true` の冗長、CTE内の `ORDER BY`、命名）— 一番浅い層。指摘を読めば済みます
2. **境界値の設計**（`DATE_TRUNC` の役割、半開区間、0件時の挙動 ⇒ 指摘①②）— **ここが今回の本命**。「動いた」と「正しい」の差が最も出る領域で、しかも `SESSION_DATE` を深夜0時に設定していたため**テストで露見しませんでした**。境界は必ず「時刻成分あり」「0件」「年境界」の3条件で確認する癖をつけると潰せます
3. **制約の扱い**（制約4を除外規定で回避した ⇒ 指摘③）— 技術ではなく姿勢の層。制約付きの課題は制約を守ることが練習の本体なので、外すなら逸脱として明示する

**既存FBが見落としていた点：** `DATE_TRUNC` 欠落による潜在的なデータ欠損（①、しかも既存FBの修正指示に従うと顕在化する）、0件週の `(NULL, NULL)`（②）、制約4違反（③）、`ORDER BY` によるスピレージリスク（④）、冗長な `CASE`（⑤）。加えて既存FBの「スカラサブクエリで100%プルーニングが効く」は言い過ぎです（⑥）。

**PR の英語は、文法（三単現・`recommend` の語法・形式目的語 `it`）とスペル（4件）に集中しています。** ただし最も重いのは英語ではなく、**仕様記述がコードのバグと同じ間違いをしていた**点（レビュアーがバグを検出できなくなる）。期間は半開区間の記法で書く習慣をつけてください。

同じフォルダに修正版 `revised_answer.sql` を置きました（**実行はしていません**）。差分の理由は冒頭コメントに列挙してあります。

**次にやるなら：** 既存FBの提案（Late-Arriving Data の増分マージ）の前に、**今回のクエリを dbt モデル化して境界のテストを書く**のが効果的です。指摘⑪の `span_days = 7` / `start_dow = 'Mon'` を singular test に落とすだけで、今回のオフバイワンは提出前に自動検出できました。「境界を計算したらアサートする」が身につくと、この種のバグと縁が切れます。
