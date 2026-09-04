# python/daily/task02 レビュー（pandas merge：重複・欠損パターンへの対応）

対象：`python/daily/task02/main.py`（提出版）、`python/daily/task02/FB/main.py`（FB反映版）、PR #3 `feat(pipeline) claense data and merge dfs`

> 注記：この環境では `uv` / スクリプト実行が使えなかったため、**実行はせず机上トレースと静的読解**で評価しています。

---

## 良かったところ

### 1. `validate="m:1"` の短縮エイリアスを使っている — 今回いちばん強い「理解の証拠」

```python
merged_df = pd.merge(tmp_sales, tmp_products, on='product_id', how='left', validate="m:1")
```

これを最初に指摘したいです。**`FB/README.md` の模範解答は `validate="many_to_one"` と書いています。** つまりあなたが提出時点で書いた `"m:1"` は、模範解答から写せる文字列ではありません。`pandas.merge` の docstring を自分で読んで、そこに併記されているエイリアスを選んだということです。

これは SKILL のレビュー観点で言う「模範解答をなぞらず自分の言葉で書いた箇所」の、最も明確な実例です。しかも `m:1` という表記は**ER図・dbt の relationships テストと同じ語彙**で、Snowflake/dbt をやるなら日常語になる記法。「認識できるが再生できない」という自己評価に対して、ここは完全に再生できています。遠慮せずに自信を持ってよい箇所です。

### 2. `.copy()` の位置が正確 — 副作用を先読みできている

```python
tmp_products = df_products.copy()
tmp_products['idx'] = tmp_products.index   # ← copy がなければ呼び出し元の df_products を壊す
...
tmp_sales = df_sales.copy()
```

これは**理屈が分かっていないと置けない**行です。この関数は引数で受け取った DataFrame に**新しい列 `idx` を追加している**ので、`copy()` がなければ関数を呼んだだけで呼び出し元の `df_products` に `idx` 列が生えます。関数が引数を書き換える（副作用を持つ）のは、パイプラインで最も追跡しにくいバグの原因です。

`FB/README.md` も冒頭で「`.copy()` の適切な配置」を評価していますが、**なぜ必要かの説明がない**ので補強しておきます。ここは「pandas のお作法として `.copy()` と書く」レベルではなく、「**自分がこれから列を足すから、その前に複製する**」という因果で置けている。だから正しいのです。

### 3. groupby + max + inner join での重複排除は「SQL脳」の正解であり、暗記ではなく組み立て

既存FBはこの部分を「過度な複雑さ」と評価していますが、**私は評価の重心を変えます。**

```python
tmp_products['idx'] = tmp_products.index
max_idx = max_idx.groupby('product_id')['idx'].max().reset_index()
tmp_products = pd.merge(tmp_products, max_idx, on=['product_id', 'idx'], how='inner').drop('idx', axis=1)
```

これは pandas としては冗長です（後述の通り指摘もします）。しかし、**この発想は SQL では完全に定石**です。

```sql
-- あなたが書いた pandas は、SQL ではこれと同じ構造
select p.* from products p
inner join (select product_id, max(idx) as idx from products group by product_id) m
  on p.product_id = m.product_id and p.idx = m.idx
```

つまりあなたは「`drop_duplicates` という便利メソッドを知らなかった」のではなく、**知っている道具（グループ化・集約・結合）だけで問題を解き切った**のです。これは丸暗記では絶対にできません。プリミティブから組み立てる力があるという意味で、認識と再生のギャップは、少なくともこのテーマでは埋まりつつあります。

そして Snowflake/dbt を扱う上では、**この筋肉こそ本命です。** Snowflake なら同じ処理はこう書きます。

```sql
select * from products qualify row_number() over (partition by product_id order by idx desc) = 1
```

`drop_duplicates(keep='last')` を覚えるより、この `QUALIFY ROW_NUMBER()` の型を身体に入れる方が、実務では直接効きます。

### 4. assert のメッセージに実際の値を入れている

```python
assert len(merged_df) == len(df_sales), f"Error : ... merged_row : {len(merged_df)} \n df_sales_row : {len(df_sales)}."
```

「失敗したときに、原因調査に必要な数字がメッセージに入っているか」は、実務のアサーションの品質を決める要素です。`assert len(a) == len(b)` だけで終わらせず、両方の値を出している。**深夜に叩き起こされる自分を助けるコード**で、経験がないと書けない配慮です（このアサーション自体には別の論点があるので後述します）。

### 5. PR #3 の Note に「詰まった箇所」を具体的に書いている — この習慣が最大の資産

```
# group集計の書き方が何度もやり直した、他のパターン出されると厳しいかも
# axisが行列を示すことはわかるが、axisオプションが必要な理由がわからない
```

これは技術ではなく**学習法**への評価です。「答えを見れば理解できるが白紙では書けない」というギャップを潰す唯一の方法は、**どこで詰まったかを言語化して記録すること**です。それをPRに書いている。しかも「何度もやり直した」「記憶にはできるはずだったんだが」と、**自分の理解の解像度まで自己申告している**。

この Note があるおかげで、レビュアーは「動いているコード」を褒めるだけで終わらず、あなたが本当に欲しい説明を返せます。この習慣は続けてください。実務でも、自分の不確実性を正確に申告できるエンジニアが一番信頼されます。

---

## 技術的な評価

ここからは実務レベルの厳しさで書きます。既存FBの3つの指摘（`drop_duplicates` / `\"Unknown\"` のエスケープ / 二重ブラケット）は正しいので繰り返さず、**そこで指摘されていない問題**を中心に挙げます。

### 正確性

#### ① 【未指摘・実バグ】`tmp_products.index` はユニークとは限らない → 重複排除が黙って失敗する

これが提出コードの中で**唯一の本当のバグ**です。

```python
tmp_products['idx'] = tmp_products.index
```

このコードは「index がユニークな連番（RangeIndex）である」ことを暗黙に仮定しています。今回のサンプルは `pd.DataFrame({...})` で直接作っているので 0,1,2,3 になり、たまたま成立します。しかし実務でマスタが来る経路を考えると、この仮定はすぐ壊れます。

```python
# 例：分割されたCSVを結合してマスタを作る、というごく普通の前処理
df_products = pd.concat([
    pd.DataFrame({"product_id": [101, 102], "category": ["Electronics", "Furniture"]}),
    pd.DataFrame({"product_id": [103, 101], "category": ["Apparel", "Electronics_New"]}),
])
# → index は 0, 1, 0, 1 になる（pd.concat は既定で index を振り直さない）
```

この状態であなたのコードを通すと何が起きるか：

- `idx` 列は `0, 1, 0, 1`
- `groupby('product_id')['idx'].max()` → `product_id=101` の max は `1`
- `pd.merge(..., on=['product_id','idx'], how='inner')` → `(101, 1)` が**マスタ側に2行ある**か、あるいは意図しない行が残る
- 結果、`product_id=101` が重複したまま通過し、次の `validate="m:1"` が `MergeError` を投げる

**症状が「重複排除の失敗」ではなく「merge のバリデーションエラー」として出る**のが厄介です。エラーメッセージは merge 行を指すので、真の原因（index の非ユニーク性）まで辿るのに時間がかかります。

**次にどうするか：** index を値として使うなら、必ず直前に振り直す。

```python
tmp_products = df_products.reset_index(drop=True)   # ← これだけで仮定が保証される
tmp_products['idx'] = tmp_products.index
```

持ち帰る原則は「**`df.index` をデータとして扱う前に `reset_index(drop=True)` する**」。pandas の index は「行の名前」であって「行番号」ではありません。ここが SQL と最も違う点で、SQL には index に相当する暗黙の行識別子がないため、SQL 側から入ると踏みやすい罠です。既存FBが勧める `drop_duplicates()` や `idxmax()` を使えば、この問題自体が発生しません（それが「便利メソッドを使う」ことの本当の価値です）。

#### ② 【未指摘】「max(index) を残す」は「最新レコードを残す」ではない — 仕様の弱さ

課題文が「最後のレコード `Electronics_New` を残すように制御してください」と書いているので**課題としては満点**ですが、実務の観点では踏み込んで指摘します。

あなたのコードも、既存FBの `drop_duplicates(keep="last")` も、やっているのは「**ファイル・データフレーム上で物理的に後ろにある行を残す**」です。これは「新しい行が後ろに来る」という並び順への依存です。

- マスタがソート順を保証しないAPI/テーブルから来たら？
- 並列で読み込んで `pd.concat` の順序が変わったら？
- 上流が「更新行を先頭に差し込む」実装に変わったら？

いずれの場合も、**エラーは出ないまま、間違ったカテゴリが黙って選ばれます。** 行数も変わらず assert も通るので、気づく手段がありません。データ品質事故として最悪のクラスです。

**次にどうするか：** 本番の重複排除は、必ず**業務的な順序キー**で行う。

```python
deduped = (df_products
           .sort_values(["product_id", "updated_at"])
           .drop_duplicates(subset=["product_id"], keep="last"))
```

`FB/README.md` の「次回追加制約案」（`updated_at` と `is_active` を追加した最新レコード特定）は、まさにこの穴を埋める課題です。**あの課題は「難易度を上げるため」ではなく「今回のコードに残っている実務上の欠陥を塞ぐため」のもの**だと理解して取り組むと、学習効率が変わります。ぜひ次回やってください。

#### ③ 【未指摘】このアサーションは、実は何も検証していない

```python
merged_df = pd.merge(..., how='left', validate="m:1")
...
assert len(merged_df) == len(df_sales), "..."
```

課題文の要求（条件4）なので書いたのは正しいです。ただし技術的には、**`how="left"` かつ `validate="m:1"` が通った時点で、行数が変わることは数学的にあり得ません。** 右側のキーがユニークであることを `validate` が保証し、left join は左の各行に対して最大1行しかマッチしないからです。

つまりこの assert は**決して失敗しない=何も守っていない**（トートロジー）。もし `validate` を外したなら、このアサーションは意味を持ちます。**「どの防御が、どの故障モードを捕まえるのか」を対応付けて考える**のが、防御的プログラミングの本質です。防御を2つ並べても、同じ故障しか見ていなければ冗長なだけです。

では、この処理で**本当に監視すべき**ものは何か。**マッチ率**です。

```python
unmatched = merged_df["category"].isna().sum()
unmatched_rate = unmatched / len(merged_df)
logging.info("Unmatched product_id rows: %d (%.1f%%)", unmatched, unmatched_rate * 100)
if unmatched_rate > 0.05:
    raise ValueError(f"Master coverage degraded: {unmatched_rate:.1%} of sales rows have no product master.")
```

行数は変わりません。**変わるのは「意味のあるデータの割合」です。** 今日 `product_id=999` が1件（20%）なら許容範囲かもしれませんが、上流のマスタ連携が壊れて明日80%が `Unknown` になったとき、行数チェックは沈黙し、`fillna("Unknown")` は健気に全部埋め、下流のダッシュボードには「Unknown カテゴリの売上が急増」と表示されます。**`fillna` は欠損を隠す道具でもある**ので、埋める前に必ず数を記録する。これが dbt で言えば `not_null` テストや `relationships` テストに相当する発想です。

#### ④ 【未指摘】`fillna` は Categorical dtype では失敗する

```python
merged_df[['category']] = merged_df[['category']].fillna('"Unknown"')
```

今回 `category` 列は `object` dtype なので動きます。ただしメモリ削減のためマスタを `astype("category")` で読むのは実務でよくある最適化で、その場合 **`"Unknown"` がカテゴリ一覧に存在しないため `TypeError`（新しい pandas では `Cannot setitem on a Categorical with a new category`）になります。** 対処は `.cat.add_categories("Unknown")` を先に呼ぶこと。

「列名が `category` で dtype も category」という混乱しやすい状況なので、**変数名・列名と dtype は別物**という意識を持っておいてください。

#### ⑤ 【未指摘】`assert` は本番で消える

```python
assert len(merged_df) == len(df_sales), "..."
```

Python を `-O`（最適化）フラグ付きで起動する、または `PYTHONOPTIMIZE=1` が設定された環境では、**`assert` 文はバイトコードから完全に削除されます。** Docker イメージや一部のCI/実行環境でこれが有効になっていることがあります。

つまり `assert` は「開発中に自分の思い込みを検証する道具」であって、**データ品質ゲートに使うものではありません。** データが期待通りかを本番でも必ず検証したいなら、明示的に例外を投げる。

```python
if len(merged_df) != len(df_sales):
    raise ValueError(f"Row count changed: {len(df_sales)} -> {len(merged_df)}")
```

使い分けの基準：**「プログラマのバグ」を捕まえるなら `assert`、「データの異常」を捕まえるなら `raise`。** 今回は後者なので `raise` が適切です。

### イディオム・パフォーマンス

#### ⑥ 【未指摘】捨てられる `.copy()` が1つある

```python
max_idx = tmp_products.copy()                                  # ← DataFrame 全体を複製
max_idx = max_idx.groupby('product_id')['idx'].max().reset_index()  # ← 直後に上書きして破棄
```

1行目の複製結果は、2行目で即座に別のオブジェクトに置き換えられて捨てられます。**マスタが1000万行あれば、1000万行のフルコピーを1回作って即破棄する**ことになります（メモリのピークが2倍になり、最悪 OOM）。`groupby` は元のデータを変更しないので、そもそも `copy()` は不要です。

```python
max_idx = tmp_products.groupby('product_id')['idx'].max().reset_index()
```

指摘②で褒めた `.copy()` と、ここで削るべき `.copy()` の違いは明快です。**「これから書き換えるか」だけ。** 書き換えるなら必要、読むだけなら不要。この基準で判断できるようになると、`.copy()` を「おまじない」で書かなくなります。

#### ⑦ 削除すべき無意味な行

```python
tmp_products['product_id'] = tmp_products['product_id']   # 自分自身を代入していて何も起きない
```

既存FBも見落としていますが、この行は**完全な no-op（何もしない）**です。試行錯誤の残骸だと思います。

レビュアー視点で言うと、この種の行は**単なる無駄より厄介**です。読んだ人が「dtype を変えたいのか？ 列順を変えたいのか？ 何か意図があるはずだ」と考え込んで時間を使い、結論として何もないと分かる。**コードは「書いた意図」を伝える媒体なので、意図のない行は読み手にコストを課します。** コミット前の差分通読で拾ってください。

#### ⑧ `drop('idx', axis=1)` → `drop(columns='idx')`：PRの疑問への実務的な回答

PR #3 の Note で `axis` について質問されていた点です。既存FBは `.shape` が `(行数, 列数)` を返すという暗記法を提示していて、それは正しいのですが、**実務ではもっと確実な回避策があります。**

```python
.drop('idx', axis=1)        # axis を覚える必要がある
.drop(columns='idx')        # ✓ 読めばわかる。axis を思い出す必要がない
```

`drop` / `rename` / `reindex` は `columns=` / `index=` のキーワードを受け付けます。**これを使う限り `axis` を覚える必要はありません。** 「暗記に頼る場面をコードの書き方で消す」のは、記憶力に頼らない有効な戦略です。

その上で、`axis` の意味そのものについて。既存FBの `.shape` 暗記法だけでは、実は次の混乱が残ります。

```python
df.drop('x', axis=1)   # 「列を」削除する
df.sum(axis=1)         # 「行ごとに、横方向に」合計する ← 結果は列ではなく行単位で出る
```

どちらも `axis=1` なのに、片方は「列に対する操作」、もう片方は「列を潰す操作」に見える。ここで多くの人が躓きます。統一した理解はこうです。

> **`axis=1` は常に「列という次元を指す」。ただし操作の種類で意味が変わる。**
> - **選択・削除系**（`drop`, `rename`, `reindex`）＝「その次元の**ラベルを指定して**選ぶ」→ `axis=1` は「列ラベルを指定」
> - **集約系**（`sum`, `mean`, `max`）＝「その次元を**潰して消す**」→ `axis=1` は「列という次元を消す」＝各行に1つの値が残る＝横方向の合計

覚え方は「**集約は指定した axis が消える**」。`df.sum(axis=1)` は `(5,3)` → `(5,)` になり、消えたのは1番目の次元（列）です。この「消える」を軸にすると、`drop` と `sum` の見かけの矛盾が解けます。

#### ⑨ 計算量：merge による重複排除は、大規模データでは選ばない

指摘3で発想としては評価しましたが、コストの話は分けて書きます。あなたの実装は、マスタに対して **①フルコピー ②groupby集約 ③merge（ハッシュ結合）④列drop** の4パスかかります。対して `drop_duplicates` はハッシュ1パスです。

Snowflake/dbt を目指すあなたに刺さる言い方をすると、**②③はメモリ上での shuffle と join を発生させるので、Snowflake でいう spillage（メモリ溢れによるディスク退避）と同じ構図**です。5行なら差はゼロですが、1000万行のマスタでは体感で変わります。

なので結論はこうなります：**発想は正しい。使う道具を1段上げるだけ。** これは「複雑な書き方をしたのが悪い」という話ではなく、「同じ意図を1パスで表現できる語彙を追加で持とう」という話です。

### 可読性・命名

#### ⑩ 関数名が責務を過小申告している

```python
def cleanse_raw_data(df_products, df_sales) -> pd.DataFrame:
```

この関数は実際には **①マスタの重複排除 ②結合 ③欠損補完 ④検証** の4つをやっていますが、名前は「クレンジング」しか言っていません。`cleanse_raw_data` という名前を見た人は、返り値が「きれいになったマスタ」だと思うはずで、実際に返るのは「売上に商品カテゴリが付いたテーブル」です。

**dbt の文脈に言い換えます。** これは dbt のモデル分割とまったく同じ問題です。

```python
def dedupe_product_master(df_products: pd.DataFrame) -> pd.DataFrame:   # stg_products 相当
def join_sales_with_category(df_sales, df_products) -> pd.DataFrame:    # fct_sales 相当
```

dbt で `stg_` と `fct_` を分ける理由が「1モデル1責務でテストとデバッグを容易にするため」であるのと、Python の関数を分ける理由は完全に同一です。**今この癖をつけておくと、dbt に入ったときにモデル設計で悩みません。** 分割すると、`dedupe_product_master` だけを単体テストできるという実利もあります（今の形では、重複排除だけをテストする手段がありません）。

#### ⑪ 引数の順序が呼び出し側で読みにくい

```python
def cleanse_raw_data(df_products, df_sales)   # マスタが先
merged_df = cleanse_raw_data(df_products, df_sales)
```

この処理の主役は `df_sales`（行数を保つ側＝left table）で、PR本文も課題文も売上を先に説明しています。**関数のシグネチャは「主役を先に」置くのが読みやすい**（`merge(left, right)` も、`join(base, lookup)` もそうなっています）。加えて両引数が同じ型 `pd.DataFrame` なので、**順序を間違えても型エラーにならず、静かに逆結合される**リスクがあります。順序を意味に合わせておくのが唯一の防御です。

#### ⑫ `tmp_` という接頭辞は情報量がゼロ

`tmp_products` / `tmp_sales` / `max_idx` のうち、`tmp_` は「一時変数である」ことしか言っていません（関数ローカルなら全部一時変数です）。`deduped_products` なら**中身が何かを言っている**ので、後で読んだときに `print` して確認する手間が省けます。

#### ⑬ docstring と PR 本文の記述が、実際のコードと食い違っている

```python
"""
[MERGE] LEFT JOIN df_sales and df_products
key = [product_id, index]      # ← 実際の結合キーは product_id のみ
"""
```

最終的な merge は `on='product_id'` です。`['product_id', 'idx']` を使ったのは**重複排除の内部処理**であって、売上との結合キーではありません。そして**同じ誤りが PR #3 の本文にもそのまま書かれています**（`### 2.[MERGE] ... key = [product_id, index]`）。

レビュアーはこれを読んで「売上とマスタを2キーで結合している」と誤解し、コードを見て混乱します。**間違ったドキュメントは、ドキュメントがない状態より有害**です。docstring は書いた後、コードと突き合わせて1回読み直す。

また docstring の各行末に半角スペース2つ（Markdown の改行記法）が付いていますが、docstring は Markdown としてレンダリングされないので効果がなく、`ruff` の W291（trailing whitespace）で警告されます。

### 本番運用の視点

#### ⑭ テストデータがモジュールトップレベルにある

`df_sales` / `df_products` がモジュール直下で定義されているため、`import` した瞬間に DataFrame が構築されます。関数自体は引数を受け取る良い設計になっているので、**フィクスチャを `main()` の中に移すだけ**で、この関数は純粋に再利用可能になります。将来 `pytest` を書くときにも、そのまま `conftest.py` のフィクスチャに移せます。

#### ⑮ `pandas` が `pyproject.toml` に宣言されていない（task01 と共通）

`dependencies` には `polars` があるのに `pandas` がありません。今動いているのは `seaborn` の間接依存として `pandas` が入っているからです（`uv.lock` で確認）。**`seaborn` を外した瞬間に両タスクが `ImportError` で壊れます。** `uv add pandas` を実行してください。原則は「**import するものは宣言する**」。

### 英語のスキル（PR #3）

既存FBは `Implements process for...` の1点だけ指摘しています。他にも学習価値の高い点があるので挙げます。

#### 最優先：`claense` という綴り間違いが git 履歴に永久に残っている

```
✗ feat(pipeline) claense data and merge dfs     ← PR タイトル & コミットメッセージ
✗ [CLENSE] df_products                          ← docstring・PR本文（こちらは別の綴り違い）
✓ cleanse
```

**同じ単語を2種類の異なる綴りで間違えています**（`claense` と `CLENSE`）。しかもコミットメッセージに入ったものは、マージ済みなので**もう直せません**（`git log` に残り続けます）。

これは英語力の問題というより実務上のコストです。半年後に「クレンジング処理を入れたコミットはどれだ」と `git log --grep=cleanse` を叩いたとき、**このコミットは絶対にヒットしません。** 検索性は将来の自分への投資なので、コミットメッセージ内のキーワードだけはエディタのスペルチェックを通す価値があります（VSCode なら Code Spell Checker 拡張が git コミット欄でも効きます）。

なお `cleanse`（動詞・クレンジングする）と `clean`（動詞・掃除する）は別語で、データ文脈では `cleanse` / `cleansing` が正しい選択です。そこは合っています。

#### 文法：`be remained` — 自動詞は受動態にできない

```
✗ only product_id with max number of id will be remained
✓ only the row with the highest index will be kept
✓ only the last occurrence will remain
```

3つの問題があります。

1. **`remain` は自動詞**なので受動態 `be remained` にできません。「残される」と言いたいなら他動詞 `keep` を使って `be kept`、「残る」なら能動で `will remain`。**日本語の「〜される」を機械的に受動態にすると、自動詞で事故ります**（同じ罠：`be occurred` ✗ / `occur` ✓、`be happened` ✗）。これは日本語話者の英文で頻出のパターンなので、「受動態を書いたら、その動詞は他動詞か？」を確認するチェックポイントにしてください。
2. **`max number of id` が意味不明。** 「id の最大の数」と読めますが、実際に言いたいのは「index が最大の行」です。`the highest index` / `the largest index value`。
3. **`only product_id` は主語がずれている。** 残るのは `product_id`（列の値）ではなく**行**なので `only the row`。

#### 語彙：`expectedly` は副詞として使えない

```
✗ Check if merge worked expectedly
✓ Assert that the join is many-to-one
✓ Verify that the merge behaves as expected
```

`expectedly` は（`unexpectedly` と違って）単独ではほぼ使われません。`as expected` が定型表現です。さらに言えば、ここは `Check if`（〜かどうか確認する）より **`Assert that`** の方が正確です。コードは条件分岐で確認しているのではなく、**満たされなければ落とす**という強い制約を課しているので。動詞の強さをコードの挙動に一致させると、PR の説明が正確になります。

#### 語彙：`row number` ≠ 行数

```
✗ df_sales's row number should not be changed
✓ The row count of df_sales must not change
```

`row number` は「行の番号（何行目か）」の意味です（SQL の `ROW_NUMBER()` がまさにそれ）。**「行数」は `row count` または `the number of rows`。** `number of X` と `X number` で意味が変わるので、ここは意識して使い分けたいところ。また `should not`（〜すべきでない、推奨）より `must not`（〜してはならない、必須）が、アサーションの強度に合っています。

#### 表記：所有格のアポストロフィをコード識別子に付けない

`df_sales's row count` は、**識別子 `df_sales` に `'s` がくっついて読みにくい**（`grep` でも引っかかりにくい）。`the row count of df_sales` と前置詞で書く、あるいは `` `df_sales` `` をバックティックで囲んで境界を明示するのが実務の作法です。

#### タイトル：Conventional Commits にはコロンが必要

```
✗ feat(pipeline) claense data and merge dfs
✓ feat(pipeline): cleanse product master and join sales with category
```

コロンが必須です（ないとツールがパースできません）。また `dfs` のような内部的な略語より、**何が出来上がったか**を書く方がレビュアーに親切です。

#### 添削版PR本文

```markdown
# Purpose
Join daily sales transactions with the product master safely, so that neither
duplicate master records nor unmatched keys can silently corrupt the output.

## Changes
1. **Deduplicate the product master** — for duplicated `product_id`s, keep only
   the last occurrence (highest index).
2. **Left join sales with the master on `product_id`**, with `validate="m:1"`
   so that an unexpected many-to-many relationship fails loudly instead of
   inflating the row count.
3. **Backfill unmatched keys** — rows whose `product_id` is absent from the
   master (e.g. `999`) get `category = "Unknown"`.
4. **Assert the row count is preserved**, guaranteeing that enriching the
   transactions never adds or drops a sale.

## Note (open questions for the reviewer)
A few things I am still not confident about, and would appreciate a second
opinion on:

- **`groupby` aggregation.** I rewrote this several times before it worked. I can
  follow the pattern I ended up with, but I am not sure I could adapt it to a
  different shape of aggregation.
- **The `axis` argument.** I understand that `axis` selects rows or columns, but
  I cannot explain *why* `axis=1` means "columns", or how to reliably remember it.
- **`numpy.where`.** I initially tried to replace `product_id == 999` with
  `"Unknown"` using `np.where`, but I could not work out the argument order
  (`cond` / `x` / `y`). I dropped it since it was out of scope, but I would like
  to understand it.
```

**Note を英語にしたことが、この添削のいちばんの狙いです。** 実務で最も難しく、最も価値のある英語は「自分が分かっていないことを、正確に、卑下せずに伝える」表現です。日本語の「厳しいかも」「よく分からなかった」を直訳すると、英語では過度に自信がない印象になります。使える型を挙げておきます。

- `I am not confident about X` — 素直に不確実性を示す標準表現
- `I could not work out ...` — 「解決できなかった」を前向きに（`I didn't understand` より能動的）
- `I would appreciate a second opinion on ...` — レビュアーへの依頼を丁寧かつ簡潔に
- `I dropped it since it was out of scope` — **やらなかった判断の正当化**。これが書けると「実装できなかった」ではなく「スコープ判断した」と読まれます

この4つは、英語のPRレビューで一生使えます。

---

## 一言だけ聞きたいこと（丸暗記か理解かの確認）

FB反映版は模範解答と完全一致なので、そこは理解の判定材料になりません。**提出版で自力で書いた部分**について3問だけ。

1. **`validate="m:1"` が通っているとき、その次の行の `assert len(merged_df) == len(df_sales)` は失敗しうると思いますか？**
   （指摘③の核心です。`m:1` が何を保証しているのかを自分の言葉で説明できれば、答えは自然に出ます。「防御を並べる」のと「故障モードを塞ぐ」の違いを掴んでいるかの確認）

2. **`df_products` を `pd.concat` で2つのDataFrameから作った場合、あなたの重複排除ロジックはどう壊れますか？**
   （指摘①。`tmp_products['idx'] = tmp_products.index` という1行が、どんな前提に乗っているか）

3. **`df.drop('x', axis=1)` と `df.sum(axis=1)` は、どちらも `axis=1` なのに操作の向きが逆に感じられます。この2つを1つの原則で説明できますか？**
   （PR Note のご質問への逆質問です。`.shape` の暗記法だけではこれが説明できません。指摘⑧に答えを書いてあるので、まず自分で言葉にしてみてから読み合わせてください）

---

## まとめ

**再生できている部分：** `validate="m:1"` の自力発見、`.copy()` の因果に基づいた配置、プリミティブ（groupby + join）だけで重複排除を組み立てる力、詰まった箇所を言語化してPRに残す習慣。この4つは丸暗記では出てきません。**「白紙では書けない」という自己評価は、このタスクに関しては実態より厳しすぎます。**

**穴（3段階に分けると）：**
1. **語彙**（`drop_duplicates`, `idxmax`, `drop(columns=)`）— 一番浅い層。既存FBが指摘済みで、調べれば埋まる。優先度は低い。
2. **pandas 特有のモデル**（index は行番号ではない ⇒ 指摘①）— SQL から入ると必ず踏む罠。ここは概念の理解が必要なので、1回きちんと潰す価値がある。
3. **データ品質の設計思想**（何を検証すれば故障を捕まえられるか ⇒ 指摘②③）— 一番深く、一番価値がある層。コードが動くかどうかを見ていても永久に気づけないので、意識的に取りに行く必要があります。**dbt のテスト設計はまさにこの筋肉**なので、投資効率が最も高い領域です。

既存の `FB/README.md` は良い教材ですが、**index の非ユニーク問題（①）、`assert` の冗長性（③）、`assert` が `-O` で消える件（⑤）、捨てられる `.copy()`（⑥）、no-op 行（⑦）は見落としています。** 模範解答を「正解」ではなく「もう一つのレビュー対象」として読めるようになると、伸びが加速します。実際あなたは PR #3 の Note で自分のコードを自分でレビューしているので、その目を模範解答にも向けるだけです。

`FB/README.md` の次回課題案（`updated_at` + `is_active` での最新レコード特定）は、指摘②の穴をちょうど塞ぐ内容です。**次はそれをやり、さらに Snowflake 側で `QUALIFY ROW_NUMBER() OVER (PARTITION BY product_id ORDER BY updated_at DESC) = 1` と書いて、同じ問題を2つの言語で解いてみてください。** pandas と SQL で同じ思考を往復させるのが、定着には一番効きます。
