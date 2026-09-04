# Python Daily task_d_04

今回選んだテーマ: 6. dtype の理解（および決定論的なソート）

## シナリオ

ユーザーの購買履歴データの前処理を行います。
購買金額（`purchase_amount`）には欠損が含まれており、標準の整数型（int）で定義しようとすると自動的に浮動小数点型（float）に昇格してしまいます。また、会員ランク（`member_rank`）は `category` 型で定義されていますが、一部に欠損（未登録）があります。
これらを適切な型と値へクレンジングし、後続の処理で扱いやすい状態に整えてください。

## 制約条件

1. **副作用の排除:** 入力データの DataFrame を直接変更せず、新しい DataFrame を作って返すこと（必要な `.copy()` を使うこと）。
2. **category型の補完:** `member_rank` の型は `category` を維持したまま、欠損値を `'Bronze'` で埋めること。
3. **nullable整数型:** `purchase_amount` の欠損値を `0` で埋め、pandas標準の nullable整数型 (`Int64`) に変換すること。
4. **決定論的ソート:** `purchase_amount` の降順でソートすること。同額のユーザーがいる場合は `user_id` の昇順でソートして、実行ごとに結果が変わらないようにすること（決定論性の担保）。最後にインデックスは元の値を捨てて `0` からの連番にリセットすること。

## 準備するもの

以下をコピーしてスクリプトのベースにしてください。

```python
import pandas as pd
import numpy as np

# User purchase data with missing values
df_users = pd.DataFrame({
    'user_id': [1, 2, 3, 4, 5],
    'purchase_amount': [1500, np.nan, 3000, 400, np.nan],
    'member_rank': pd.Series(['Gold', 'Silver', 'Gold', np.nan, 'Silver'], dtype='category')
})
```

## 期待するスクリプトの条件

上記の制約条件をすべて満たす前処理関数を実装し、処理後の DataFrame を print 等で出力して確認できるようにしてください。

---

解答のコードを書いてみてください。

**最低10分は何も見ずに書き切ってから提出してください。**
