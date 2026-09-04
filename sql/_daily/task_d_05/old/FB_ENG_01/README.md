# 英語コミュニケーションの添削 (PR #8)

PR本文とコミットメッセージを対象としています。

## オリジナルの文章
**Title**:
`feat(pipeline) create answer on task_d_05`

**Body**:
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

### 構成・内容（技術的誤りとの連動）
- `duplicated values in columns [store_id , received_at]`
  重複の粒度は `[store_id, sales_date]` であり、`received_at` は重複ではなく最新判定用の列です。英語の仕様記述が実際の重複条件とずれています。
- `not (NULL, NULL) but (0, 0)`
  課題の要求は「0行を返す」ことでしたが、PRでは「(0, 0)を返す」と書かれています。仕様の誤解が記述から見受けられます。

### 表記
- `feat(pipeline) create answer on task_d_05` → `feat(pipeline): create an answer for task_d_05`
  **Conventional Commits のコロン `:` が抜けています（4回連続での見落としです）。必ず `feat(scope): msg` の形式にしてください。**

### 語彙・文法
- `specifice` → `a specific` （スペルミス、単数可算名詞の冠詞欠落）
- `an sync error` → `a sync error` （a/an の使い分け）
- `in systems` → `in the system`
- `Additionaly` → `Additionally` （スペルミス）
- `clients defined these constraints below :` → `the client defined the following constraints:`
- `if there's no rows` → `if there are no rows` （複数形への呼応）
- `in specific date` → `on a specific date` （日付には on）
- `I couldn't work out with solving the 3rd problems.` → `I could not work out how to solve the 3rd problem.` （句動詞 `work out` 後の冗長な with solving の削除、単数形への修正）
- `impleted` → `implemented` （スペルミス。スペルミスは git 履歴に残り検索性を損なうため注意してください）
- `it doesn't look work as I thought.` → `it does not work as I expected.`
- `My apologies to left 3rd constraints here,` → `I apologize for leaving the 3rd constraint unsolved.`
- `It's thankful for me if you would give me any advices on it.` → `I would appreciate any advice on it.`
  **`advice` は不可算名詞のため、複数形の `s` は付けません。**

## 添削版（提案）

**Title**:
`feat(pipeline): create an answer for task_d_05`

**Body**:
```markdown
# Purpose
Summarize the transaction data on a specific target date.

# Problem
This data has duplicated records for the same store_id and sales_date because it had a sync error in the system.
We need to extract the data which has the latest `received_at` value for each store_id.
Additionally, the client defined the following constraints:
1. Do not use group by or a subquery to solve duplication
2. A CTE is only allowed once
3. If there are no rows on a specific date, we need to return 0 rows instead of (NULL, NULL).

# How
As a result, I could not work out how to solve the 3rd problem.
But I solved the 1st and 2nd constraints in my query. For the 1st constraint, I used QUALIFY to extract the rows with the latest received_at.

Speaking of the 3rd constraint, I implemented `NVL` on each column to avoid showing `NULL`, but it does not work as I expected.

---

I apologize for leaving the 3rd constraint unsolved. I would appreciate any advice on it.
Thank you.
```
