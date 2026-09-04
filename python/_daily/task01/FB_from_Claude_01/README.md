# python/daily/task01 レビュー（tenacity によるリトライロジック）

対象：`python/daily/task01/setup.py`（提出版）、`python/daily/task01/FB/setup.py`（FB反映版）、PR #2 `feat(apicall) add tenacity to let script retry requesting for 5 times`

> 注記：この環境では `uv` / スクリプト実行が使えなかったため、**実行はせず机上トレースと静的読解**で評価しています。挙動に関する記述（呼び出し回数など）はコードを追った結果であり、実測値ではありません。

---

## 良かったところ

### 1. 白紙から `@retry` デコレータの形に持っていけている（提出版）

```python
from tenacity import retry, stop_after_attempt, wait_fixed
@retry
def fetch_data_from_unstable_api():
```

「答えを見れば分かるが白紙では書けない」という課題に対して、ここは**再生（production）できている側**です。`tenacity` は「デコレータでリトライを外付けする」という設計思想のライブラリで、その骨格を自力で出せているのは、API名の暗記ではなくライブラリの使い方の型を掴めている証拠です。引数の中身が空だったのは減点ですが、それは**知識の穴（どのパラメータがあるか）**であって、**設計の穴ではない**。前者は調べれば埋まります。

### 2. FB反映版のコメントが「自分の言葉」になっている

```python
stop = stop_after_attempt(5), # 5 in maximum
wait = wait_fixed(1), # interval is 1 sec
retry = retry_if_exception_type(RuntimeError), # retry is available only with RuntimeError
reraise = True # after 5 times retrying, it will raise error again.
```

`FB/README.md` の模範解答のコメントは日本語（`# 最大5回までリトライ` など）でした。それを**英語で書き直している**のが重要です。丸写しなら日本語コメントがそのまま残ります。訳し直すという行為は、一度自分の頭を通さないとできません。SKILL のレビュー観点で言う「模範解答をなぞらず自分の言葉で書いている箇所」が、まさにここです。

### 3. `main()` のエラーメッセージも自分の言葉に置き換えている

```python
print(f"\n[FATAL] Pipeline is stopped unexpectedly : {e}")
```

模範解答は `パイプラインが異常終了しました` でした。`[FATAL]` というログレベルの接頭辞を残しつつ英語化する判断は、実務のログ設計として正しい方向です（後述する通り、`print` を `logging` に替えるとさらに良くなります）。

### 4. PR #2 の構成（Purpose / How / Note）が既に実務水準

特に **Note に「このエラーは意図的なものだ」と書いた判断**を強く評価します。

```
This script's error is intentional one, developed for understanding how to code the error handling logic in python.
```

レビュアーが `raise RuntimeError` を見た瞬間に抱く「これバグでは？」という疑問を、先回りして潰しています。これは経験の浅いエンジニアがまず書けない項目です。英文の粗さは後述しますが、**「何を書くべきか」の判断は既に正しい**。

---

## 技術的な評価

ここからは実務のレビューと同じ基準で書きます。

### 正確性

#### ① 【提出版】`@retry` が無引数 → 無限リトライ（既に `FB/README.md` で指摘済み）

既存FBの指摘は正しいです。無引数の `@retry` は `stop=stop_never`, `wait=wait_none` 相当で、**待機なしで永久にリトライ**します。今回はモックが4回目以降必ず成功するので止まりますが、本番APIが恒久障害（例：認証エラー、エンドポイント廃止）に落ちた場合、プロセスはCPUを焼きながら永久に回り続けます。ここは既にFB反映版で修正済みなので、これ以上は繰り返しません。

#### ② 【提出版・既存FBが見落としている】`call_count += 1` の移動で、成功が1回分後ろにズレている

既存FBは「モック関数を改変した」という**設計上の問題**としてしか指摘していませんが、この改変は**挙動そのものを変えています**。

```python
# 提出版：チェックの「後」でインクリメント
if call_count < 4:
    print(f"[API] Call {call_count}: ...")
    call_count += 1     # ← ここ
    raise RuntimeError("API Temporary Error")
```

元の課題コードは**チェックの前**にインクリメントしていました。この差でどうなるか、机上トレースすると：

| | 元のモック | 提出版のモック |
|---|---|---|
| 出力されるログ | `Call 1` 〜 `Call 3` 失敗 → `Call 4` 成功 | `Call 0` 〜 `Call 3` 失敗 → `Call 4` 成功 |
| 成功までの試行回数 | **4回** | **5回** |

問題が2つあります。

1. **ログの表示が0始まりになった。** 課題文が期待していた `[API] Call 1:` が `[API] Call 0:` になります。人間が「何回目で落ちたか」を数える際の off-by-one は、障害対応で最も時間を溶かすタイプのバグです。
2. **より深刻：成功に必要な試行回数が4回から5回に増えた。** その結果、FB反映版で `stop_after_attempt(5)` を付けたコードは、**5回目＝許容された最後の試行でギリギリ成功している**状態です。マージン（余裕）がゼロ。もしここで `stop_after_attempt(4)` と書いていたら、「4回目で成功するモック」なのに `RetryError` で落ちていました。

**次にどうするか：** FB反映版では元のモックに戻せているので、コード上は解決済みです。持ち帰るべき教訓は「**カウンタのインクリメント位置は仕様である**」ということ。`count += 1` を「今から1回試行する」の意味で置くのか「1回失敗した」の意味で置くのかを、最初に決めてコメントに書く癖をつけてください。

#### ③ 【FB反映版・未指摘】`stop_after_attempt(5)` は「リトライ5回」ではなく「試行5回（＝リトライ4回）」

これは PR の記述と実装が食い違っている箇所です。

- PR #2 の本文：`retry on its requesting to the api server 5 times in maximum`（最大5回リトライする）
- 実装：`stop_after_attempt(5)` = **初回1回 + リトライ4回 = 合計5回の呼び出し**

`tenacity` の `attempt` は「試行」であって「リトライ」ではありません。「最大5回リトライ」を厳密に実装するなら `stop_after_attempt(6)` です。

これは細かい話に見えて、実務では効きます。SLA や課金APIのレート制限を「リトライ回数」で契約している場合、この1回のズレが仕様違反になります。**次にどうするか：** PR に書くときは `up to 5 attempts (1 initial call + 4 retries)` のように、曖昧さが残らない言い方をする。コード側なら `MAX_ATTEMPTS = 5` と定数に名前を付けて意図を固定します。

#### ④ 【FB反映版・未指摘。今回の最重要指摘】`except Exception` で握りつぶすと、パイプラインが「成功」扱いになる

```python
def main():
    try:
        df = fetch_data_with_retry()
        ...
    except Exception as e:
        print(f"\n[FATAL] Pipeline is stopped unexpectedly : {e}")
```

模範解答由来のコードですが、**本番のデータパイプラインとしてはこれが一番危険です。**

`reraise=True` を苦労して指定して例外を上まで飛ばしたのに、`main()` がそれを捕まえて `print` して終わっています。結果、**プロセスの終了コードは 0（正常終了）**。Airflow・Dagster・cron・GitHub Actions のいずれも、終了コード0を見て「タスク成功」と判定します。

つまりこのコードは、**5回リトライして全部失敗した後、「成功しました」と嘘の報告をして静かに終わる**。下流のモデルは空データや前日のデータで動き続け、誰も気づきません。これは「サイレント障害」と呼ばれる、データ基盤で最も見つけにくい事故です。

**次にどうするか：** 握りつぶすなら、必ず異常終了させる。

```python
import sys, logging

def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    try:
        df = fetch_data_with_retry()
    except RuntimeError:
        logging.exception("[FATAL] Data extraction failed after all retries.")
        return 1          # ← 非ゼロで返して、オーケストレータに失敗を伝える
    logging.info("Extracted %d rows", len(df))
    print(df)
    return 0

if __name__ == "__main__":
    sys.exit(main())
```

ポイントは3つ。`return 1` / `sys.exit` で**終了コードを立てる**、`except Exception` ではなく**リトライ対象と同じ `RuntimeError` に絞る**（`retry_if_exception_type(RuntimeError)` と一貫させる）、`logging.exception` で**スタックトレースを残す**。

### イディオム・パフォーマンス

#### ⑤ リトライが「観測できない」

現状、何回リトライしたかが分かるのは、モック関数が親切に `print` してくれているからです。**本番のAPIクライアントは何も print しません。** つまり本番に持っていくと、リトライは完全に不可視になります。「たまに処理が3秒遅い」以外の痕跡が残りません。

`tenacity` にはこのための引数があります。

```python
import logging
from tenacity import before_sleep_log

logger = logging.getLogger(__name__)

@retry(
    stop=stop_after_attempt(5),
    wait=wait_fixed(1),
    retry=retry_if_exception_type(RuntimeError),
    reraise=True,
    before_sleep=before_sleep_log(logger, logging.WARNING),  # ← リトライごとにWARNを出す
)
```

これを入れると「retrying in 1.0 seconds as it raised RuntimeError...」がログに残り、後から**リトライ率の推移**を追えるようになります。リトライ率は「APIが壊れかけている」ことを事前に教えてくれる最良のシグナルです。

#### ⑥ 【提出版】未使用インポートが2つ

```python
from tenacity import retry, stop_after_attempt, wait_fixed  # stop_after_attempt と wait_fixed を使っていない
```

提出版は `retry` だけを使い、残り2つは未使用です（`ruff`/`flake8` の F401）。**これは実は良い兆候でもあります**——「使うはずだと分かっていたが、書き方を思い出せなかった」痕跡だからです。認識はできていて再生ができなかった、というギャップが可視化された箇所。`ruff check` をコミット前に走らせる習慣をつけると、この種の「書きかけ」が自動で見つかります。

#### ⑦ 課題文のコメントが残っている

```python
from tenacity import retry, stop_after_attempt, wait_fixed # 必要なモジュールは適宜調整してくれ
```

これは出題文からのコピー跡です。FB反映版でも残っています。**提出物に出題者の指示文が残っているのは、レビュアーから見て「読み返していない」サインに見えます。** 些細ですが、実際のPRでは印象を大きく損ねる部分なので、コミット前に自分の差分を1回通読する癖をつけてください。

#### ⑧ `wait_fixed(1)` の1秒は、本番では短すぎる

`FB/README.md` の「次回追加制約案」でも触れられていますが、補足します。固定1秒間隔は、相手が過負荷（503）のときに**一番やってはいけない挙動**です。全クライアントが同じ1秒間隔で叩き続けるため、負荷が減らず、復旧を遅らせます（thundering herd 問題）。`wait_exponential(multiplier=1, max=30)` + jitter が定石です。ここは次回の課題として残しておいてください。

#### ⑨ PEP8：キーワード引数の `=` に空白を入れない

```python
stop = stop_after_attempt(5),   # ✗ E251
stop=stop_after_attempt(5),     # ✓
```

関数のキーワード引数では `=` の前後に空白を入れないのがPEP8です（型注釈付きのデフォルト値だけは例外で `x: int = 1`）。`ruff format` / `black` を入れれば自動で直ります。

### 可読性・命名

#### ⑩ ファイル名が `setup.py` なのは避けたい

これは**中身よりも影響が大きい**指摘です。`setup.py` は Python パッケージングにおいて**予約された意味を持つファイル名**で、「このディレクトリはビルド可能なパッケージである」というシグナルです。ビルドツールや `pip install .` が拾いに来る可能性があり、実際にこのリポジトリは `pyproject.toml` + `uv_build` でパッケージ管理しているので、名前が衝突する概念です。

**次にどうするか：** `retry_extraction.py` や `main.py`（task02 と揃える）にリネームする。ドリルであっても、**ファイル名は最初のドキュメント**です。

### 本番運用の視点

#### ⑪ リトライだけでは「ハング」は防げない — タイムアウトが必要

今回はモックなので該当しませんが、実APIに差し替えた瞬間に効いてくる論点なので書いておきます。

`@retry` は**例外が発生したとき**にリトライします。ところが本番で一番厄介な障害は「例外が出ない」パターン——**サーバーが接続を受け付けたまま応答を返さない**ケースです。この場合 `requests.get()` はデフォルトで**無限に待ち続け**、例外を投げないのでリトライも発動せず、プロセスはただ止まります。

```python
resp = requests.get(url, timeout=(3.0, 10.0))  # (接続タイムアウト, 読み取りタイムアウト)
```

**リトライとタイムアウトは必ずセットで設計する。** 片方だけでは意味がありません。これはデータ基盤の設計レビューで必ず確認される論点です。

#### ⑫ `pandas` が `pyproject.toml` に宣言されていない

```toml
dependencies = [
    "dbt-core>=1.12.3", "dbt-snowflake>=1.12.0",
    "polars>=1.43.2",      # ← polars はある
    "python-dotenv>=1.2.3", "requests>=2.34.2",
    "seaborn>=0.13.2",     # ← pandas はこれ経由で間接的に入っているだけ
    "tenacity>=9.1.4",
]
```

task01・task02 とも `import pandas as pd` しているのに、`pandas` は直接依存として宣言されていません。今動いているのは `seaborn` が `pandas` に依存しているおかげ（`uv.lock` にも `seaborn` の依存として `pandas` が入っています）。

つまり、**`seaborn` を外した瞬間に両タスクが `ImportError` で壊れます。** これは実務で「なぜか本番だけ動かない」の典型的な原因です。

**次にどうするか：** `uv add pandas`。ルールは「**import するものは宣言する**」。間接依存に頼るのは、他人のパッケージの内部実装に依存しているのと同じことです。

### 英語のスキル（PR #2）

既存FBが `Let script to have retry` → `Implement a retry mechanism` の書き換えと `temporal` → `transient` を指摘しています。これは正しいので、それ以外を挙げます。

#### 文法：`let` の語法

```
✗ Let script to have retry on its requesting to the api server 5 times in maximum.
```

3点あります。

1. **`let` は原形不定詞をとる**（`to` は付かない）。`let X do`、`allow X to do`。この2つの使い分けは混同されやすいので、セットで覚えると効率的です。
2. **冠詞がない。** `Let script` → `the script`。可算名詞の単数は、ほぼ必ず冠詞か所有格が必要です。日本語話者の英文で最も多い指摘がこれなので、「単数名詞を書いたら冠詞を確認する」を機械的なチェックにしてしまうのが早いです。
3. **`in maximum` は英語にない表現。** `up to 5 times` / `a maximum of 5 attempts` / `at most 5 times`。**`up to` が一番自然で短い**ので、これを第一候補に。

#### 語彙：`its requesting`

動詞から作った名詞を無理に使うと不自然になります。`its requesting to the api server` → `its requests to the API server`（名詞 `request` がある）。**「-ing 形にする前に、対応する名詞があるか確認する」**と英文が一段自然になります。同様に `the suspension of the data extraction` も硬いので `extraction failures` で十分です。

#### 表記：固有名詞・型名

- `api server` → **`API server`**（頭字語は大文字）
- `runtimeerror` → **`` `RuntimeError` ``**（クラス名は正確に、バックティックで囲む）

コード上の識別子を正確に書くのは、英語力ではなく**エンジニアとしての正確性**として見られます。`grep` で引っかからない綴りは、レビュアーの手間を増やします。

#### 冠詞：`is intentional one`

```
✗ This script's error is intentional one
✓ The errors in this script are intentional
```

`one` を使うなら `an intentional one` ですが、そもそも `one` は不要です。**形容詞を述語にできるときは、名詞を足さない**方が英語として自然になります。

#### コミットメッセージ：Conventional Commits にはコロンが必要

```
✗ feat(apicall) add tenacity to let script retry requesting for 5 times
✓ feat(api): add tenacity retry with a cap of 5 attempts
```

Conventional Commits の書式は `type(scope): description` で、**コロンが必須**です（コロンがないとツールがパースできません）。スコープも `apicall` より `api` の方が一般的。

#### 添削版PR本文（そのまま使える形）

```markdown
# Purpose
Add a retry mechanism to the API extraction step, capped at 5 attempts
(1 initial call + 4 retries), so that transient server errors such as
`503 Service Unavailable` no longer abort the pipeline.

# How
Wrapped the API call in `fetch_data_with_retry()` and decorated it with
`tenacity.retry`. The mock client itself is left untouched, which keeps the
retry policy separate from the transport layer and mirrors how we would wrap
a real third-party SDK.

Retry policy:
- `stop_after_attempt(5)` — bounded, so a permanent outage fails fast instead of hanging
- `wait_fixed(1)` — avoids busy-waiting on the upstream server
- `retry_if_exception_type(RuntimeError)` — only transient errors are retried
- `reraise=True` — surfaces the original exception once retries are exhausted

# Note
The failures in this script are intentional: it is a drill for practising
error-handling patterns, not a real integration.
```

変えたところの意図：**冒頭の1文で「何を・どこに・どういう上限で」を言い切る**、リトライ設定を**箇条書き＋「なぜその値か」**にする（レビュアーが設定値の妥当性だけ見て承認できる）、`bounded` / `fail fast` / `transient` のような**この文脈の定型語を使う**。この3つを押さえると、英語の巧拙とは別に「レビューしやすいPR」になります。

---

## 一言だけ聞きたいこと（丸暗記か理解かの確認）

FB反映版は模範解答とほぼ一致しているため、この2問だけ確認させてください。**答えられれば理解、詰まったらそこがまだ穴です。**

1. **`@retry` をモック関数（`fetch_data_from_unstable_api`）に直接付けた場合と、ラッパー関数（`fetch_data_with_retry`）に付けた場合で、「動作」に違いはありますか？**
   （ヒント：既存FBは「サードパーティのコードは変更できない」という**実務上の制約**を理由に挙げていました。それ以外に、テストのしやすさという観点での違いを説明できますか。「同じAPIに対して、処理Aでは3回・処理Bでは10回リトライしたい」となったらどう書きますか？）

2. **`stop_after_attempt(5)` のとき、モック関数は最大何回呼ばれますか？ そして「リトライは何回」ですか？**
   （この2つの数字が違う理由を自分の言葉で言えるかどうかが、指摘③を本当に理解したかの分かれ目です）

---

## まとめ

**再生できている部分：** デコレータでリトライを外付けする構造、PRを Purpose/How/Note で組む判断、意図的なエラーであることを明記する配慮。ここは既に自力の実装力があります。

**穴：** ライブラリのパラメータ知識（調べれば埋まる、心配しなくていい）と、**「失敗したときにプロセスをどう終わらせるか」という運用視点**（指摘④）。後者だけは、コードが動くかどうかを見ていても永久に気づけない領域なので、意識的に取りに行く価値があります。Snowflake/dbt の文脈でも「失敗を確実に失敗として伝える」は毎日出てくるテーマです。

なお、既存の `FB/README.md` は良いフィードバックですが、**`except Exception` の終了コード問題（④）とモック改変による試行回数のズレ（②）は見落としています**。模範解答も無条件に信じず、「この `try/except` は誰のために何をしているのか」と一度疑う目線を持てると、レビューされる側からレビューする側に回れます。
