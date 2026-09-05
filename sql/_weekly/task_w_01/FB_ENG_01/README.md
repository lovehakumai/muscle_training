# 英語コミュニケーションの添削 (PR #12 / コミットメッセージ)

PR 本文およびコミットメッセージを取得してレビューしています。

## オリジナルの文章
（PR タイトル：`add answer script on sql task_w_01` / コミット：`feat(pipeline) add answer project on sql task_w_01`）

**本文**
- **feat(pipeline) add answer project on sql task_w_01**
[PURPOSE]
Cleanse the transaction date and aggregate it to summarise the daily report.
... (省略) ...
[CONCLUSION] From Client :
- Making `transaction_id` unique only includes latest `transaction_timestamp`.
- This is becaus\tuue, if there's dupulicated `transaction_id` with different `user_id` and `purchase_amount` means the problems in upstream, we shouldn't fix it here.
... (省略) ...
`consective_date` test will validate it.
(SINGULAR TEST:)
Sinbular test detects this kind of data below.
... (省略) ...
[COMMENT]
I'm not confident with these topics here
unit_tests, maybe I could implemet it here to check my pipeline works well and help it to separate the category of the problems between this pipeline or upstream system.
comments in model, I wrote a lot of comments on model `int_transactions_cleanse` but it should be written in description in model. 
dbt_util test, if we need to accurately have check the PK of `int_transactions_cleanse`, we should use hash key and dbt_util must have that library but I forgot what it is.

## AIによるレビューと添削

- **Conventional Commits のコロン抜け:** タイトルおよびコミットメッセージが `feat(pipeline) add answer project...` となっていますが、正しくは `feat(pipeline): add answer project...` のように `)` の後にコロンとスペースが必要です。（この指摘は過去に何度も発生しており「繰り返し出ている弱点」の7番です。手癖にする必要があります）
- **スペルミス・タイポ:**
  - `becaus\tuue` -> 打ち間違いです。`because`
  - `dupulicated` -> `duplicated`
  - `consective` -> `consecutive`
  - `Sinbular` -> `Singular`
  - `implemet` -> `implement`
  スペルミスは git の履歴に残ると後から検索できなくなるため、コミット前に見直す癖をつけましょう。
- **文法・語彙:**
  - `Cleanse the transaction date` -> データを指す場合は `data` または `transaction records` のほうが自然です。
  - `only includes latest` -> `only involves taking the latest` などとします。
  - `if there's dupulicated... means the problems` -> if 節の中で動詞が重複しています。`if there are duplicated records... it implies a problem` のように整理します。
  - `minus` : 値が負であることは `negative value` と表現するのが一般的です。
- **不確実性の表現（Note セクション等）:**
  「〜というライブラリがあるはずだが忘れた」という部分は、以下のように自然なエンジニアリングの提案として書けます。
  `To accurately check the composite PK of int_transactions_cleanse, we should generate a surrogate key. The dbt_utils package has a macro for this (dbt_utils.generate_surrogate_key).`

## 添削版（提案）

```markdown
feat(pipeline): add answer project for sql task_w_01

[PURPOSE]
Cleanse the transaction data and aggregate it to summarize the daily report.

[PROBLEMS]
- `transaction_id` contains duplicated values due to upstream retries.
- `purchase_amount` includes negative values, which are valid (e.g., refunds).
- `points_earned` includes NULL values, which are valid.
- `points_earned` includes abnormally large values due to a bug.
- `transaction_timestamp` has gaps (non-consecutive dates) due to system errors.

[HOW]
- Ensure `transaction_id` is unique and not null by grouping and using a window function.
  - [ESCALATION]
    Needed to check how to define the uniqueness of `transaction_id`. Should we partition by `transaction_id` and pick the one with:
    - the highest `user_id`?
    - the latest `transaction_timestamp`?
    - the highest `purchase_amount`?
    - `points_earned` is not null with a positive `purchase_amount`?
  - [CONCLUSION] From Client:
    - Making `transaction_id` unique only involves taking the latest `transaction_timestamp`.
    - This is because if there are duplicated `transaction_id`s with different `user_id`s and `purchase_amount`s, it implies a problem in the upstream system, and we shouldn't fix it here.

[ADDITIONAL INFO] From Client:
- `points_earned` might include negative values when the transaction is a repayment.
- However, if there are negative points with a positive `purchase_amount`, it is invalid.
- If there are gaps in `transaction_timestamp` dates, it must be detected in the test because this is caused by the upstream system.

[ABOUT TESTS]
`int_transactions_cleanse`:
- The unique test is only applied to `transaction_id`, not `user_id`.
- `purchase_amount` and `points_earned` must have valid combinations.
  - They are not allowed to be a mix of positive and negative values (e.g., (100, -100) or (-100, 100)).
  - They are not allowed to be a mix of null and not null (e.g., (null, 100) or (100, null)).
- This is validated by a singular test (`num_combination`) because a generic test cannot cover this cross-column logic.

`fct_user_daily_points`:
- `user_id` and `transaction_timestamp` are not allowed to be null.
- This table must have consecutive dates, which is validated by the `consecutive_date` singular test.

[SINGULAR TESTS]
The singular tests detect the following problematic data:
`num_combination`:
Allowed - (`purchase_amount`, `points_earned`) = (100, 50), (null, null), (-100, -50)
Not Allowed - (`purchase_amount`, `points_earned`) = (-100, 50), (50, null), (null, 50), (100, -50)

`consecutive_date`:
Allowed -
(user_id, transaction_date) =
(1, '2000-01-01')
(1, '2000-01-02')
(1, '2000-01-03')

Not Allowed -
(user_id, transaction_date) =
(1, '2000-01-01')
(1, '2000-01-03')
(1, '2000-01-05')

---
[COMMENT]
Notes and future improvements:
- **Unit tests:** I could perhaps implement them here to verify my pipeline logic and help separate the problems between this pipeline and the upstream system.
- **Model comments:** I wrote many comments in the `int_transactions_cleanse` model file itself, but they should ideally be placed in the model's description in the YAML file.
- **dbt_utils tests:** To accurately check the composite PK of `int_transactions_cleanse`, we should generate a surrogate key. The `dbt_utils` package has a macro for this (`dbt_utils.generate_surrogate_key`).
```
