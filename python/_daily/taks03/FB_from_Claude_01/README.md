# python/task03 レビュー（groupby：グループ内最大値のレコード抽出）

対象：`python/daily/taks03/my_answer.py`（提出版）、`python/daily/taks03/FB/README.md`（既存FB）、PR #7 `feat(pipeline) answer task03`

> 注記：**コードは実行していません。** 机上トレースと静的読解のみで評価しています。以下の出力値・挙動はコードを追って導いたもので、実測値ではありません。

---

## 良かったところ

### 1. 提示された2つの解法を両方使わず、第3の解法を自力で見つけている

課題文の制約はこうでした。

> 前回解説した `idxmax()` を用いたエレガントな方法、または `groupby` + `merge` を用いた堅牢な方法のいずれか（あるいは両方のパターン）で実装してください。

**あなたはこのどちらも使っていません。**

```python
tmp_df = tmp_df.sort_values(by = 'impressions', ascending=False).drop_duplicates(subset=['campaign_id'], keep='first')
```

そして既存FBも認めているとおり、この `sort_values` → `drop_duplicates(keep='first')` は **pandas における常套手段のひとつ**です。ヒントとして与えられた2つの道具を使わずに、独立した第3の正解に到達しています。

これが重要な理由は、**課題が誘導していた答えに乗らなかった**という点です。`idxmax()` は前回のFBで解説済みの関数で、思い出せば書けます。そこに寄りかからず「ソートして先頭を残す」という別の筋道を自分で構成したのは、`idxmax` を暗記して再生したのとは質が違います。

机上で確認すると正しく動きます。

| campaign_id | 最大 impressions | 選ばれる行 |
|---|---|---|
| 101 | 3200 | 2026-09-02（clicks 310） |
| 102 | 4500 | 2026-09-01（clicks 400） |
| 103 | 800 | 2026-09-01（clicks 50） |

降順ソート後の並びは `4500, 4100, 3200, 2400, 1500, 800` で、`campaign_id` 単位で先頭を残すと上表の3行になります。要求どおりです。

なお**制約からの逸脱ではある**ので、そこは後述します（PRで解法を明示していた点は前回からの改善です）。

### 2. `assert` ではなく `raise ValueError` を選んでいる — ここは既存FBに従わないでください

```python
if tmp_camp_ncnt_raw != tmp_camp_ncnt_result:
    error_txt = f'Error at unique number of campaign_id: raw {tmp_camp_ncnt_raw} , result: {tmp_camp_ncnt_result}'
    raise ValueError(error_txt)
```

**この判断は、既存FBの模範解答より本番向きです。** 既存FBはこう書いています。

> データパイプラインの事前検証やテストコードにおいては、わざわざ `if` 文で例外を投げるよりも、**`assert` 構文** を使う方がコードが劇的にシンプルになります。

**この助言は、データ品質チェックに関しては逆です。** `assert` 文は Python を `-O` フラグ付きで起動する、あるいは `PYTHONOPTIMIZE=1` が設定された環境では**バイトコードから完全に削除されます**。一部の Docker イメージや CI 環境でこれが有効になっていることがあり、その場合**検証が丸ごと消えたまま本番が動きます。**

使い分けの基準は「**プログラマのバグを捕まえるなら `assert`、データの異常を捕まえるなら `raise`**」。今回は後者なので、あなたの `raise ValueError` が正解です。

これは `python/daily/task02/FB_from_Claude_01/README.md` の指摘⑤と同じ内容で、**そこから今回の実装に反映されている形になっています。** 意識的だったかは分かりませんが、判断としては正しいので、既存FBに合わせて `assert` に書き換えないでください。

課題文の条件2は「アサーション（assert）を記述してください」なので、**ドリルの要求を満たすという意味では既存FBの指摘も正しい**です。両立させるなら `raise` を残したうえで、PRに「要求は assert だったが、`-O` で消える性質があるため明示的に raise した」と書くのが最も強い回答になります。

### 3. エラーメッセージに実測値を両方入れている

```python
f'Error at unique number of campaign_id: raw {tmp_camp_ncnt_raw} , result: {tmp_camp_ncnt_result}'
```

「失敗したときに原因調査に必要な数字が入っているか」は実務のアサーションの品質を決めます。期待値と実際値を両方出す習慣は task02 でも同じでした。**3タスク連続で維持されている**ので、これはもう身についた癖と見ていいです。

### 4. `.size` が「属性」であることを自力で突き止めている

PR の詰まった記録から：

> たまたま記憶の奥底にある関数実行として使わない方法 `.size`を思い出してなんとかなった

`.size()` が `TypeError: 'numpy.int64' object is not callable` で落ちる理由——**`.size` はメソッドではなく属性**——に自力で辿り着いています。これは pandas の中でも紛らわしい部分で、後述するとおり `GroupBy` オブジェクトでは `.size()` が**メソッド**になるという非対称性があります。

「悲しい」と書かれていますが、この1時間で得た区別は正しいものです。ただし**探していた場所が少しずれていた**ので、次の節で整理します。

### 5. 「詰まったこと」を残す習慣が3タスク続いている

task02、task04 に続いて、今回も試したこと（`groupby()['campaign_id'].nunique()`、`.shape`、`.size()`）と所要時間まで記録されています。

**この記録があるから、レビュー側は「動いたコードを褒める」で終わらずに、あなたが本当に詰まった箇所に答えを返せます。** 実際、以下の解説はこの記録がなければ書けませんでした。続けてください。

---

## まず、詰まった箇所への回答（PRの質問）

既存FBは `len()` / `.shape` / `.nunique()` の3つを「3大武器」として列挙していますが、**なぜ試した3つが失敗したのかの説明がない**ので、そこを埋めます。暗記より、区別できる原則を持つほうが再現性があります。

### なぜ試した3つが失敗したのか

| 試したもの | 何が起きたか |
|---|---|
| `groupby()['campaign_id'].nunique()` | **Series が返る**（グループごとに1つずつ、全部 `1`）。スカラが欲しかったのに配列が返るので比較できない |
| `.shape` | **タプル `(行数, 列数)` が返る。** 行数だけ欲しいなら `.shape[0]` が必要 |
| `.size()` | **`.size` は属性なのでカッコを付けると `TypeError`** |

**いちばん重要なのは1行目です。** `groupby` を挟んだことが根本原因でした。

「キャンペーンは何種類あるか」は**データフレーム全体に対する1つの問い**です。`groupby` は「グループごとに答えを出す」道具なので、**全体に対する1つの答えが欲しいときにグループ化してはいけません。**

```python
df_perf.groupby('campaign_id')['campaign_id'].nunique()   # ✗ グループごとに1を返す Series
df_perf['campaign_id'].nunique()                          # ✓ 3（スカラ）
```

`groupby` を外すだけで、最初に試した `nunique()` が正解でした。**1時間の大半は、道具の選択ではなく「問いの粒度」の取り違えに使われていた**ことになります。

判断基準はこれだけです。**答えが1つ欲しいなら `groupby` を使わない。答えがグループごとに欲しいときだけ `groupby` を使う。**

### 属性とメソッドを間違えないための原則

覚えるべきは一覧ではなく、次の区別です。

> **形を尋ねるものは属性。計算するものはメソッド。**

`.shape` `.size` `.ndim` `.empty` `.columns` `.index` `.dtypes` は「このオブジェクトはどういう形か」を保持している値なので、**属性（カッコなし）**。
`.count()` `.nunique()` `.sum()` `.mean()` は中身を走査して**計算する**のでメソッド（カッコあり）。

`df.groupby('campaign_id').size()` が**メソッド**なのは、この原則に照らせば自然です。グループごとの行数は「保持されている形」ではなく、グループ分けの結果から**計算する**ものだからです。同じ `size` という名前でも、DataFrame では属性、GroupBy ではメソッドになる——名前ではなく**役割**で決まります。

### 用途別の対応表

| 欲しいもの | 書き方 | 種類 |
|---|---|---|
| 行数 | `len(df)` または `df.shape[0]` | 組み込み関数 / 属性 |
| 全要素数（行×列） | `df.size` | 属性 |
| ある列のユニーク値の個数 | `df['col'].nunique()` | メソッド |
| グループの数 | `df.groupby('col').ngroups` | 属性 |
| グループごとの行数 | `df.groupby('col').size()` | メソッド |
| 非NULLの件数 | `df['col'].count()` | メソッド |

NaN の扱いだけ注意してください。**`nunique()` と `count()` は NaN を除外**し、**`len()` と `.size` は NaN も数えます。** `campaign_id` に欠損があるデータでは、この差が結果を変えます（後述の指摘⑨で具体例を出します）。

---

## 技術的な評価

既存FBの2点（`.size` が行×列を返すこと／`if raise` と `assert` の対比）は扱いが済んでいるので、**指摘されていない問題**を挙げます。

### 正確性

#### ① 【既存FB未指摘・最重要】この検証は、`.size` を直しても**絶対に失敗しません**（同義反復）

既存FBは `.size` を `len()` に直せば正しくなる、という前提で書かれていますが、**直しても検証としては機能しません。**

```python
tmp_df = df_perf.sort_values(...).drop_duplicates(subset=['campaign_id'], keep='first')
tmp_camp_ncnt_raw = df_perf.drop_duplicates(subset=['campaign_id']).size   # ← len() に直したとして
tmp_camp_ncnt_result = tmp_df.size
```

比較している2つの値は、**どちらも「`df_perf` に対する `drop_duplicates(subset=['campaign_id'])` の行数」**です。左辺はそれをそのまま、右辺はソートを挟んでから同じ操作をしています。

**ソートは「`campaign_id` が何種類あるか」を変えません。** よって両辺は常に `df_perf['campaign_id'].nunique()` と等しく、**この `if` が真になることはありません。**

これがなぜ問題かというと、**検証が「抽出が正しいか」を一切見ていない**からです。具体的に壊してみます。

```python
# ascending=False を True に変えるだけ（最大値ではなく最小値を取る実装ミス）
tmp_df = tmp_df.sort_values(by='impressions', ascending=True).drop_duplicates(subset=['campaign_id'], keep='first')
```

| campaign_id | 出力される impressions | 正しい値 |
|---|---|---|
| 101 | 1500 | 3200 |
| 102 | 4100 | 4500 |
| 103 | 800 | 800 |

**行数は3行のままなので、検証は通ります。** 全キャンペーンで間違った日のデータが出力されているのに、エラーは出ません。「各キャンペーンの最大インプレッション日を取る」というこの関数の唯一の仕事が壊れているのに、検知できない検証です。

**これは task02 と同じ構図です。** `python/daily/task02/FB_from_Claude_01/README.md` の指摘③で、`validate="m:1"` が通った後の行数アサーションが同義反復だと書きました。**2回続いているので、これは偶然ではなく癖です。**

パターンはこうです。**実装で使った操作と同じ操作で期待値を計算してしまっている。** そうすると両辺が必ず一致し、検証は「実装が実装どおりであること」しか確認しません。

**次にどうするか：** 検証は**実装と独立した経路**で期待値を出す。行数ではなく「選ばれた行が本当にグループ最大か」を見ます。

```python
# 実装は sort_values + drop_duplicates、検証は groupby.max()。経路が別なので意味を持つ
expected_peaks = df_perf.groupby('campaign_id')['impressions'].max().sort_index()
actual_peaks = result.set_index('campaign_id')['impressions'].sort_index()
if not actual_peaks.equals(expected_peaks):
    raise ValueError(f'Extracted rows are not the per-campaign maximum.\nexpected:\n{expected_peaks}\nactual:\n{actual_peaks}')
```

この検証なら、上の `ascending=True` の改変を即座に捕まえます。

原則は「**検証は実装と違う道具で書く。** 同じ道具で書いた検証は、実装のコピーであって検証ではない」。行数チェックは残してもいいですが、それは「1キャンペーン1行」という形の確認であって、**中身の正しさは別途見る必要がある**と理解してください。

#### ② 【既存FB未指摘】同点（tie）のとき、どの行が残るか決まっていない

```python
tmp_df.sort_values(by='impressions', ascending=False)
```

`sort_values` の既定は `kind='quicksort'` で、**これは安定ソートではありません。** 同じ `impressions` を持つ行同士の相対順序は保証されません。

具体的に壊れる条件：`campaign_id=101` に最大値と同じ値の行がもう1つある場合。

```python
# 元データに1行足すだけ
{"campaign_id": 101, "date": "2026-09-04", "impressions": 3200, "clicks": 999}
```

`101` には `impressions=3200` の行が2つ（`2026-09-02` clicks=310 と `2026-09-04` clicks=999）できます。降順ソート後にどちらが先に来るかは**未定義**なので、`keep='first'` が拾うのは `clicks=310` の行か `clicks=999` の行か**分かりません。** pandas のバージョンや行数によって変わりえます。

そして**行数は3行のままなので、検証は通ります**（指摘①と同じ穴）。

「同じ入力で同じ結果が返らないパイプライン」は、差分比較・再実行・テストのすべてを壊します。実務では最も嫌われる性質です。

**次にどうするか：** 同点時の順位を仕様として決め、安定ソートを明示する。

```python
tmp_df.sort_values(
    by=['impressions', 'date'],          # 同点なら date で決める
    ascending=[False, True],             # impressions は降順、date は昇順（＝古い日を優先）
    kind='stable',                       # 既定の quicksort は非安定
)
```

ここで**既存FBが提示した `idxmax()` の隠れた利点**が分かります。`idxmax()` は「最大値の**最初の出現**位置を返す」と仕様が定義されているので、同点でも決定論的です。既存FBは `idxmax()` を「意図が明確でパフォーマンスも高い」と説明していますが、**本当の利点は同点時の挙動が定義されていること**です。

持ち帰る原則は「**『最大値を取る』という仕様には、必ず『同点のときどうするか』が抜けている。** 気づいたら自分で決めて明文化する」。

#### ③ 【既存FB未指摘】`date` が文字列なので、ソートできるのは ISO 形式の偶然

```python
"date": ["2026-09-01", "2026-09-02", ...]   # str のまま
```

指摘②で `date` を第2ソートキーにする案を出しましたが、これが正しく動くのは **`YYYY-MM-DD` という ISO 8601 形式が、文字列としての辞書順と時系列順が一致する**からです。

もし上流が `MM/DD/YYYY` 形式で渡してきたら：

```
"09/01/2026", "10/15/2025", "12/31/2025"  → 辞書順では 09/01/2026 が最初
```

2025年のデータより2026年のデータが先に来ます。**エラーは出ず、順序だけが静かに壊れます。**

**次にどうするか：** 日付列は読み込み直後に型変換する。

```python
tmp_df['date'] = pd.to_datetime(tmp_df['date'])
```

`datetime64` にしてしまえば形式に依存せず、期間差の計算や `dt` アクセサも使えます。原則は「**日付は文字列のまま扱わない。** 文字列でソートできるのは ISO 形式のときだけ」。

### イディオム・パフォーマンス

#### ④ 【既存FB未指摘・task02と同じ】`.copy()` が作られた直後に捨てられている

```python
tmp_df = df_perf.copy()                                          # ← DataFrame 全体を複製
tmp_df = tmp_df.sort_values(...).drop_duplicates(...)            # ← 直後に別オブジェクトで上書き
```

1行目の複製は、2行目で即座に置き換えられて破棄されます。100万行なら**100万行のフルコピーを1回作って即捨てる**ことになります。

`python/daily/task02/FB_from_Claude_01/README.md` の指摘⑥とまったく同じパターンです（あちらは `max_idx = tmp_products.copy()` の直後に `max_idx = max_idx.groupby(...)`）。

そして**task02 で示した判断基準に照らすと、ここでは `.copy()` 自体が不要**です。

> **「これから書き換えるか」だけ。** 書き換えるなら必要、読むだけなら不要。

`sort_values` と `drop_duplicates` は**どちらも新しいオブジェクトを返し、元のデータを変更しません。** よってこの関数は引数を書き換えないので、`.copy()` は要りません。

```python
result = df_perf.sort_values(...).drop_duplicates(...)   # copy 不要
```

task02 では `tmp_products['idx'] = ...` と**列を追加していた**ので `.copy()` が必要でした。**同じ基準で、逆の答えになる**——ここが区別できると `.copy()` をおまじないで書かなくなります。

判定手順は「その変数に対して `df[...] = ` や `inplace=True` を書くか？ 書かないなら `.copy()` は不要」。

#### ⑤ 検証を関数の外に出すと、実装と検証の独立性が保てる

現状 `pipeline()` は「抽出」と「検証」を両方やっています。指摘①の同義反復が起きた一因は、**同じ関数の中で書いたために手近な変数を使い回してしまった**ことにあります。

```python
def extract_peak_impression_day(df): ...   # 抽出だけ
def _validate(df, result): ...             # 検証だけ（引数として入力と出力を受ける）
```

検証関数が入力と出力しか知らないようにすると、**実装の中間変数を流用できなくなる**ので、構造的に独立した検証を書くことになります。task02 の指摘⑩で「関数名が責務を過小申告している」と書いたのと同じ話で、`pipeline` という名前も中身（抽出＋検証）を言っていません。

### 可読性・命名

#### ⑥ `tmp_camp_ncnt_raw` は読み解くのに時間がかかる

```python
tmp_camp_ncnt_raw / tmp_camp_ncnt_result
```

3つ問題があります。`tmp_` は「一時変数」しか言っていない（関数ローカルは全部一時変数）。`camp` と `ncnt` の二重の略語で、`ncnt` は "number count" と読めますが意味が重複しています。`raw` / `result` の対比も、比較しているのが「期待値と実際値」であることを表していません。

```python
expected_campaign_count / actual_row_count      # 既存FBの模範解答の命名。こちらが読める
```

`tmp_` については task02 の指摘⑫でも触れているので、**そこだけは意識的に外してみてください。** 変数名に「何が入っているか」を書くと、後で `print` して中身を確認する手間が減ります。

#### ⑦ 引数名がモジュール変数と同名

```python
df_perf = pd.DataFrame({...})              # モジュールレベル
def pipeline(df_perf: pd.DataFrame): ...   # 引数が同名（シャドーイング）
```

動作は正しく、関数内では引数が優先されます。ただし読む側は「モジュール変数を使っているのか引数を使っているのか」を毎回確認する必要があります。また引数名を特定のデータセット名（`df_perf`）にすると、この関数が汎用であることが伝わりません。既存FBの模範解答は `df` にしています。

型ヒント `(df_perf: pd.DataFrame) -> pd.DataFrame` を付けている点は3タスク連続で維持されていて良い習慣です。

#### ⑧ 出力の index と行順が非決定的

抽出後の `tmp_df` は**元の index を保持**するので、`2, 3, 5` のような非連続な値になります。また行順は `impressions` 降順（102, 101, 103）で、`campaign_id` 順ではありません。

パイプラインの出力を後段でファイル出力・`concat`・テストで比較する場合、index と行順は効いてきます。

```python
.sort_values('campaign_id').reset_index(drop=True)
```

task02 の指摘①で「pandas の index は行の名前であって行番号ではない」と書いた話の続きです。**出力する DataFrame は index を振り直す**のを既定の作法にしておくと安全です。

### 本番運用の視点

#### ⑨ NaN と空データでの挙動が未定義

**`campaign_id` に NaN がある場合**、あなたの実装と既存FBの模範解答で**結果が食い違います。**

- `drop_duplicates(subset=['campaign_id'])` は NaN を1つの値として扱い、**NaN の行を1行残します**
- `nunique()` は NaN を**除外**します
- `groupby('campaign_id')` も既定で NaN を**除外**します

したがって NaN を含むデータでは、あなたの実装は 4 行を返すのに `nunique()` は 3 を返します。**既存FBの模範解答のアサーションは、この場合に限って実際に失敗します**（指摘①で「模範解答も同義反復」と書きましたが、この1点だけは検知できます）。どちらが正しい仕様かはビジネス側の判断です。

**`impressions` が全て NaN のキャンペーンがある場合：**

- あなたの実装：`sort_values` は既定で NaN を末尾に置く（`na_position='last'`）ので、**NaN の行が1行残ります**
- `idxmax()`：全て NaN のグループでは**例外を投げます**

「静かに NaN を返す」か「落ちる」かの違いで、パイプラインとしてはどちらが望ましいか決めておく必要があります。

**空の DataFrame の場合：** 両カウントが 0 で一致するので検証を通り、空の DataFrame を返します。上流の連携が止まっていても「正常終了」します。実務では最低行数のしきい値チェックを入れます。

#### ⑩ フォルダ名が `taks03` になっている（`task03` の綴り間違い）

```
python/daily/taks03/     ← task03 のはず
```

これは実際に問題を起こしました。**このレビューの冒頭でタスク一覧を出したとき、`ls python/daily/task*` では `taks03` がヒットせず、存在しないものとして扱われました。** `task*` というグロブに `taks03` は一致しません。

同種の被害：`find . -path '*task03*'`、タスクフォルダを走査する自動化、`sync-tasks.sh` の保護対象パス判定（`FB_from_Claude_*` の親を `task{NN}` で探す処理）。

**綴りの問題が3件連続しています。** task02 のコミットメッセージの `claense`、task04 のタイトル・コミットの `monday`（曜日は大文字始まり）、そして今回のパス `taks03`。

コミットメッセージは修正できませんが、**フォルダ名は今なら直せます。**

```bash
git mv python/daily/taks03 python/daily/task03    # upstream 側で実行
```

**注意：** これを upstream で実行すると、次回の `sync-tasks.sh` は旧パスを削除して新パスを追加します。その際**このレビューフォルダ（`taks03/FB_from_Claude_01/`）は旧パスに取り残される**ので、スクリプトが警告を出したら `task03/` 配下へ手で移動してください（スクリプトの設計上、リネームは自動追従できません）。

再発防止としては、**エディタのスペルチェッカを git コミット欄とファイル名でも効かせる**設定（VSCode の Code Spell Checker）が実効的です。識別子・パス・コミットメッセージの綴りは、後から `grep` で見つけられるかどうかを左右します。

#### ⑪ 既存FBの模範解答が、そのままでは実行できない

2点あります。

**`FB/answer.py` が 0 バイト**（空ファイル）です。模範解答のスクリプトとして置かれたようですが中身がありません。

**`FB/README.md` のコードブロックが破損しています。**

```python
df_perf = pd.DataFrame({
    "campaign_id":,        # ← 値が欠落
    "date": ["2026-09-01", ...],
    "impressions":,        # ← 値が欠落
    "clicks"               # ← 値が欠落
})
```

これは `SyntaxError` になるので、**模範解答をコピーして動かして比べる、ということができません。** task01 の `FB/README.md` にも同じ破損があります（`"campaign_id":,` `"clicks":`）。

生成元のツール側で配列リテラルが落ちているようなので、**FBを受け取った時点でコードブロックが完全か確認する**のを習慣にしてください。模範解答が動かないと、比較による学習ができなくなります。

---

## 英語のスキル（PR #7）

既存FBは冒頭1行（`Grouping ... and get ...`）だけを添削しています。それ以外を挙げます。

### 構成：自分の良いテンプレートから後退している

PR #2 と PR #5 では `# Purpose` / `# How` / `# Note` という見出し構成を使っていました。今回は**説明文がそのまま H1 見出しになっています。**

```markdown
# Grouping the dataframe by campaign_id and get the rows with the highest impression value using `drop_duplicates`.
```

見出しに文章を入れると、GitHub の PR 一覧やメール通知で長い文が見出しとして表示されます。また**見出しに句点（`.`）は付けません。** 前回までのテンプレートに戻すのが最も簡単な改善です。

### 内容：同点の扱いが書かれていない（コードの穴と同じ）

PR は「最大インプレッションの行を取る」と書いていますが、**同点のときどうなるかに触れていません。** 指摘②のとおりコード側も未定義なので、**説明と実装が同じ穴を共有しています。**

task04 でも同じ構図でした（PRの期間記述がコードのオフバイワンと同じ誤りだった）。**仕様を書こうとすると実装の穴に気づく**——これがPRを書く最大の効用です。「同点なら古い日付を優先する」と書こうとした時点で、コードにその制御が無いことに気づけます。

### 語彙・文法

```
✗ Grouping the dataframe by campaign_id and get the rows with the highest impression value
✓ Group the dataframe by `campaign_id` and extract the row with the highest `impressions` per campaign.
```

既存FBは動詞の形（`Grouping`/`get` → 原形で統一）を指摘済みなので、それ以外を3点。

- **`impression value` → `` `impressions` ``。** 列名は `impressions`（複数形）です。**コード識別子は正確に、バックティックで囲む**のが原則です。`impression value` と書くと `grep` で引っかかりません
- **`the rows` → `the row`。** キャンペーンごとに**1行**なので単数。複数形だと「複数行残る実装」と読めます
- **`per campaign` を足す。** 「グループごとに1行」という最も重要な性質が原文から落ちています

### 「詰まったこと」を英語で書く

内容は日本語ですが、**ここを英語にするのが今回いちばん練習価値が高い**部分です。実務で最も難しい英語は「自分が分かっていないことを、卑下せずに正確に伝える」表現です。

```markdown
# Note

Working out how to count unique values took me about an hour. I tried
`groupby()['campaign_id'].nunique()`, `.shape` and `.size()`, and none of them
gave me a single number to compare against.

In the end `.size` worked, once I realised it is an attribute rather than a
method. What I had actually got wrong was the granularity of the question:
`groupby` answers "one value per group", but I wanted one value for the whole
frame, so `df['campaign_id'].nunique()` was what I needed all along.

I would appreciate a sanity check on whether the row-count comparison is a
meaningful assertion here.
```

使える型を4つ挙げます。**task02 で挙げたものの続き**なので、合わせて8つになります。

- `Working out how to X took me about an hour` — 所要時間を事実として述べる（`I struggled` より客観的）
- `none of them gave me ...` — 試して駄目だったことを、結果ベースで書く
- `once I realised it is an attribute rather than a method` — 原因の言語化。`A rather than B` は対比の定型
- `What I had actually got wrong was ...` — **自己診断の提示。** これが書けると「詰まった人」ではなく「原因を特定できる人」として読まれます

最後の一文（`I would appreciate a sanity check on whether ...`）を入れると、**レビュアーに具体的な確認を依頼できます。** 今回まさに指摘①がそれに該当したので、書いてあれば最短で答えが返ってきた箇所です。

### タイトルとコミットメッセージ

```
✗ feat(pipeline) answer task03
✓ feat(pipeline): extract the peak-impression day per campaign

✗ feat(pipeline) add ai_review
✓ docs(task03): add AI review and model answer
```

- **コロンが必須**です（Conventional Commits のパーサが認識できません）。task02・task04 でも同じ指摘をしているので、**3回目**です
- `answer task03` は**何をしたかを言っていません。** タイトルは半年後に `git log` を読む自分のためのものなので、「どのタスクか」ではなく「何を実装したか」を書きます
- 2つ目のコミットはフィードバック文書の追加なので **`feat` ではなく `docs`**。type を正しく選ぶと `git log --grep` と自動 CHANGELOG が機能します
- `ai_review` → `AI review`（頭字語は大文字、スネークケースはコード識別子用）

### ブランチ運用（PR #6）

PR #6 `feat(pipeline) add python task03` の**ブランチ名が `sql/task04` になっています。** python task03 の内容を sql/task04 のブランチから出しているので、後から履歴を追うときに混乱します。ブランチ名は内容に合わせてください（`python/task03`）。PR #7 は正しく `python/task03` でした。

---

## 一言だけ聞きたいこと（丸暗記か理解かの確認）

模範解答（`idxmax()`）とは別解なので、提出版はすべて自力の産物です。そのうえで3問だけ。

1. **`ascending=False` を `ascending=True` に変えたら（＝最小値を取る実装ミス）、いまの検証はエラーになりますか？**
   （指摘①の核心です。「実装と同じ操作で期待値を作ると検証にならない」が掴めているかの確認。task02 の `validate="m:1"` のときと同じ問いです）

2. **`campaign_id=101` に `impressions=3200` の行がもう1日あったとき、出力されるのはどちらの日ですか？**
   （指摘②。答えが「決まっていない」だと分かれば十分です。そのうえで、どう決めるべきかを自分で決めてみてください）

3. **今回 `tmp_df = df_perf.copy()` を書きましたが、task02 のときと違って不要です。その違いを1つの基準で説明できますか？**
   （指摘④。task02 の FB_from_Claude_01 に基準を書いてあります。同じ基準で逆の答えになる理由が言えれば、`.copy()` はもう迷いません）

---

## まとめ

**再生できている部分：** ヒントで与えられた2解法に乗らず `sort_values` + `drop_duplicates` という第3の正解を自力構成、`assert` ではなく `raise ValueError` を選ぶ判断（**既存FBより本番向きなので従わないでください**）、エラーメッセージに実測値を両方入れる habit（3タスク連続）、`.size` が属性であることの自力診断、詰まった箇所を記録する習慣（3タスク連続）。

**穴を3段階に分けると：**

1. **API の区別**（属性かメソッドか、`groupby` を挟むべきか）— 一番浅い層。上の「形を尋ねるものは属性、計算するものはメソッド」と「答えが1つ欲しいなら `groupby` を使わない」の2原則で潰せます。**1時間かけた箇所ですが、優先度は最も低い**です
2. **決定論性**（同点時の挙動、非安定ソート、文字列日付、index ⇒ 指摘②③⑧）— 中間層。「同じ入力で同じ出力が返るか」という観点が、まだ意識の外にあります
3. **検証の設計**（⇒ 指摘①）— **ここが今回の本命で、task02 から数えて2回目**です。実装と同じ操作で期待値を作ると、検証は実装のコピーになり何も守りません。「検証は実装と違う道具で書く」を原則として持ってください。dbt のテスト設計もまったく同じ思想です

**既存FBが見落としていた点：** `.size` を直しても検証が同義反復のままである点（①、最重要）、同点時の非決定性と `sort_values` の非安定性（②）、文字列日付のソート（③）、捨てられる `.copy()`（④）、NaN・空データでの挙動（⑨）、フォルダ名の綴り（⑩）、模範解答が破損していて実行不能（⑪）。加えて既存FBの「`assert` を使え」は本番のデータ品質チェックとしては逆です。

**PR の英語**は、前回まで使っていた `# Purpose` / `# How` / `# Note` テンプレートに戻すのが最も費用対効果が高い改善です。コロン抜けは3回目なので、コミットテンプレートを設定してしまうのも手です。

同じフォルダに修正版 `revised_answer.py` を置きました（**実行していません**）。差分の理由は冒頭の docstring に列挙しています。

**次にやるなら：** 既存FBの提案（`total_clicks` を同じ行に結合＝Window関数的な集計）は良い課題ですが、その前に**今回のコードに指摘①の検証を足すだけの練習**を1本入れると効きます。`ascending` を反転させて検証が落ちることを確認する——それだけで「検証が効いている」という感覚が手に入ります。
