# 英語コミュニケーションの添削 (PR #8 / コミットメッセージ)

PR本文とコミットメッセージを対象にしています。

## オリジナルの文章
タイトル: `feat(pipeline) create answer on task_d_05`

```markdown
# Purpose
Summarize the transaction data in specifice target date.

# Problem
This data has duplicated values in columns [store_id , received_at]  because it had an sync error in systems.  
We need to extract the data which has latest `received_at` value in each store_id.  
Additionaly, clients defined these constraints below :   
1. Do not use group by or subquery to solve duplication
2. cte is only allowed once
3. if there's no rows in specific date, we need to get the result not (NULL, NULL) but (0, 0).

# How
As a result, I couldn't work out with solving the 3rd problems.
But I solved 1,2 constraints in my query, Especially 1) : I used qualify to extract the rows with latest received_at.  

Speaking of 3rd constraints, I impleted `NVL` on each column to avoid showing the `NULL` , but it doesn't look work as I thought. 

---

My apologies to left 3rd constraints here, It's thankful for me if you would give me any advices on it.
Thank you.
```

## AIによるレビューと添削

- **Conventional Commits のコロン抜け**: タイトルが `feat(pipeline) create` となっています。正しくは `feat(pipeline): create` です。（繰り返し見落とされやすい項目です）
- **仕様記述が課題文の要求とずれている**: 課題文は「0行が返るように」でしたが、PRには「`(0, 0)` を取得する必要がある（`get the result not (NULL, NULL) but (0, 0)`）」と書かれています。このずれにより、意図と異なる `NVL` が実装されていました。添削版では課題文に合わせて修正しています。
- **技術的な誤りが英語の記述から見つかる**: `duplicated values in columns [store_id, received_at]` とありますが、重複の粒度は `(store_id, sales_date)` です。`received_at` は最新を特定するための列です。
- **不可算名詞に複数形を付けていないか**: `any advices` → `any advice`（不可算名詞のため `s` は不要です）
- **句動詞に余分な前置詞を付けていないか**: `work out with solving` → `work out how to solve`
- **スペルミス**:
  - `specifice` → `specific`
  - `Additionaly` → `Additionally`
  - `impleted` → `implemented`
  （スペルミスは git 履歴に残り検索性を損なうため注意が必要です）
- **文法・語法**:
  - `an sync` → `a sync`
  - `doesn't look work` → `doesn't look like it works` または `does not work as expected`
  - `cte` は頭字語なので大文字で `CTE` とします。

## 添削版（提案）

```markdown
# Purpose
Summarize the transaction data on a specific target date.

# Problem
This data has duplicated values for the same `(store_id, sales_date)` due to a sync error in the systems.  
We need to extract the data which has the latest `received_at` value for each `store_id` and `sales_date`.  
Additionally, clients defined the constraints below:   
1. Do not use `GROUP BY` or subqueries to solve duplication.
2. A CTE is only allowed once.
3. If there are no rows on a specific date, we need to ensure the query returns 0 rows, rather than `(NULL, NULL)`.

# How
I solved the 1st and 2nd constraints in my query. For the 1st constraint, I used `QUALIFY` to extract the rows with the latest `received_at`.  

Regarding the 3rd constraint, I tried to implement `NVL` on each column to avoid showing `NULL`, but I could not work out how to solve it properly as it does not work as expected. 

---

My apologies for leaving the 3rd constraint incomplete. I would appreciate any advice on this.
Thank you.
```
