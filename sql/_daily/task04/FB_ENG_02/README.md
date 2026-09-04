# 英語コミュニケーションの添削 (PR #5)

## オリジナルの文章
```text
# Create Summary report

According to business constraints, this sql will summarize the total amount of sales in last week, starting with last monday.  
This sql doesn't use `current_date()` or `current_timestamp()` to avoid unstable result caused by users execution   environment, this query's result is always based on what date you execute in not who or where you execute.   

` ` `
e.g.  
If you execute this query on '2026-09-01', this is the Tuesday so that last monday is `2026-08-24`.  
This sql extract the 7 days from that monday, (between `2026-08-24` ~ `2026-08-31`) .
` ` `

And this query includes only 2 ctes aside from base cte,   
this simple architecture makes easy enough to catche up for other engineers.

---
Additionaly, I'd love to share the problem in future about this logic.
This logic always read all rows in `raw_weekly_sales` table, and it means data spilage will makes credit higher.
For avoiding this I recommend you to 2 actions 
1. For Extract data -> Add CLUSTERING KEY, this helps query engine to search for target rows using specified column names
2. For updating table -> Add incremental model with dbt, this model update table efficiently and decrease credit.

---
 I can support both actions, please feel free to tell me.
```

## AIによるレビューと添削

Masa、今回のPRメッセージは、実装報告にとどまらず、将来のパフォーマンスリスク（全件スキャンによるクレジット消費増大）への言及と、具体的な技術的解決策まで提案できていて本当に素晴らしいです！

技術文書としてよりプロフェッショナルにするためのポイントをまとめました。

**最優先：仕様記述がコードのバグと同じ誤りをしている**
- `between 2026-08-24 ~ 2026-08-31` と書かれていますが、これだと**8日間**になります（31日は翌週の月曜です）。
- 期間は必ず**半開区間の記法（`[2026-08-24 00:00, 2026-08-31 00:00)`）** で書くようにしてください。これだけで書いた本人がオフバイワンバグに気づけ、レビュアーも実装とのズレを正しく検知できます。

**文法・語彙**
- **三単現の `-s`**: 技術文書は主語が三人称単数（This query, This logic）になりがちです。`This sql extract` → `extracts`、`This logic always read` → `reads`。
- **`recommend` の語法**: `recommend you to 2 actions` ✗ → `recommend two actions:`。また、数字は文中では綴る（`2` → `two`）のが慣習です。
- **形式目的語の欠落**: `makes easy enough` ✗ → `makes it easy enough`。
- **助動詞の後は原形**: `will makes` ✗ → `will make`。
- **冠詞と表現**: `the problem in future` → `a potential issue in the future`（初出の懸念には `the` ではなく `a`）。`I'd love to share` はトーンが強すぎるため `I would like to flag` を使います。
- **スペルミス**: `Additionaly` → `Additionally`、`spilage` → `spillage`、`catche` → `catch`、`monday` → `Monday`（曜日は大文字始まり）。コミットメッセージにも `monday` の小文字化が見られました。スペルミスは git 履歴に残り検索性を損なうため注意しましょう。

**構成**
- `I can support both actions, please feel free to tell me.` はカンマスプライス（独立した2文をカンマで繋いでいる）です。`I can take on either of these — let me know if you would like me to.` が自然です。
- コミットメッセージのコロン欠落: `feat(pipeline) weekly...` ✗ → `feat(pipeline): add weekly...`。

## 添削版（提案）
```markdown
# Purpose
According to business constraints, this query summarizes the total amount of sales for the previous ISO week.

It avoids dynamic functions like `CURRENT_DATE()` or `CURRENT_TIMESTAMP()`, meaning the result depends entirely on the reference date passed into it, regardless of the execution environment or timing. Re-running it for the same reference date always produces the exact same result.

```text
e.g.  
If executed on '2026-09-01' (Tuesday), the reference Monday is '2026-08-24'.  
The query extracts the 7 days starting from that Monday: [2026-08-24 00:00, 2026-08-31 00:00).
```

The logic relies on only two CTEs, making it simple and easy enough for other engineers to follow.

---
### Known Limitations & Next Steps
I would like to flag a potential issue with this approach. Currently, it reads all rows in the `raw_weekly_sales` table. As data grows, full table scans will increase warehouse credit consumption.

To avoid this, I recommend two actions:
1. **For reads**: Add a CLUSTERING KEY on `DATE(sale_timestamp)` to help the query engine prune micro-partitions.
2. **For writes**: Convert this into a dbt incremental model so it efficiently updates the table with only new records.

I can take on either of these — let me know if you would like me to proceed.
```
