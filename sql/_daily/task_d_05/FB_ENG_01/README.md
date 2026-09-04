# 英語コミュニケーションの添削 (PR #8)

## オリジナルの文章
```text
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

### 語彙・文法
- `in specifice target date` ✗ → `for a specific target date` (綴りミスと前置詞の誤用)
- `duplicated values in columns [store_id , received_at]` ✗ → 重複しているのは `store_id` と `sales_date` の組み合わせであり、`received_at` はむしろ差異を見分けるための列です。
- `it had an sync error` ✗ → `due to a sync error` または `because of a sync error`
- `latest received_at value in each store_id` ✗ → `the latest received_at value for each store_id`
- `Additionaly` ✗ → `Additionally` (綴りミス)
- `cte is only allowed once` ✗ → `Only one CTE is allowed`
- `the 3rd problems` ✗ → `the 3rd problem` (単数形)
- `impleted` ✗ → `implemented` (綴りミス。スペルミスは git 履歴に残り検索性を損なうため注意です)
- `doesn't look work` ✗ → `didn't work as I expected`
- `My apologies to left 3rd constraints here` ✗ → `I apologize for leaving the 3rd constraint unresolved`
- `It's thankful for me if you would give me any advices on it.` ✗ → `I would appreciate your advice on it.` または `I would appreciate a second opinion on it.`

### 構成・内容
- **課題文の仕様の解釈**：課題は「(NULL, NULL)ではなく0行を返す」でしたが、PR本文では「(0, 0)を返す」と誤って書かれています。仕様記述が間違っていると、レビュアーが誤解したまま実装を見てしまうため注意が必要です。
- **不確実性の表現**：末尾で「できなかった」と謝るよりも、「自分はこのように理解して実装したが、期待通りにならなかった。アドバイスがほしい」と事実ベースで伝えるとプロフェッショナルな印象になります（`I would appreciate a second opinion on...` や `What I had actually got wrong was...` など）。

## 添削版（提案）
```markdown
# Purpose
Summarize the transaction data for a specific target date.

# Problem
This data has duplicate records for the same `store_id` and `sales_date` due to a system sync error.
We need to extract the record with the latest `received_at` timestamp for each `store_id`.
Additionally, the following constraints are defined:
1. Do not use `GROUP BY` or subqueries for deduplication.
2. Only one CTE is allowed.
3. If there are no rows for a specific date, the query must return 0 rows, not a row with `(NULL, NULL)`.

# How
I solved the 1st and 2nd constraints. For the 1st constraint, I used the `QUALIFY` clause to extract the rows with the latest `received_at`.

Regarding the 3rd constraint, I misunderstood the requirement as "returning (0, 0)" and attempted to use `NVL` to replace `NULL` values. It didn't work as I expected because the `GROUP BY` clause correctly caused the query to return 0 rows when the input was empty, which was actually the intended behavior.

---

I would appreciate a second opinion on my approach, especially regarding the 3rd constraint. Thank you.
```
