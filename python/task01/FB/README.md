すばらしい、さっそくの解答コードとプロフェッショナルなPR（Pull Request）英語コメントの提出、ありがとうございます！

何もない状態から tenacity のインポートや関数の骨組みを組み立てて書き切ったその姿勢、まさにエンジニアの鏡です。

それでは、提出いただいたコードに対して、データエンジニアの視点から厳格にレビューおよびフィードバックを行います。

---

### 1. 模範解答の提示

実務において、API通信を行う関数（サードパーティ製ライブラリなど）はコードを変更できないケースが多いため、**「データ取得を行うモック関数」と「リトライロジックを制御するラッパー関数」を分離する設計**が最も堅牢で美しく、テストが容易です。

以下に模範解答を提示します。

```python
import pandas as pd
from tenacity import retry, stop_after_attempt, wait_fixed, retry_if_exception_type

# ----------------------------------------------------
# 準備用のダミー関数（モックAPI：変更不可とする）
# 3回目までの呼び出しは一時的なエラーを投げ、4回目でデータ（DataFrame）を返す。
# ----------------------------------------------------
call_count = 0

def fetch_data_from_unstable_api():
    global call_count
    call_count += 1
    if call_count < 4:
        print(f"[API] Call {call_count}: 503 Service Unavailable (Temporary Error)")
        raise RuntimeError("API Temporary Error")
    
    print(f"[API] Call {call_count}: 200 OK (Success)")
    return pd.DataFrame({
        "campaign_id":,
        "clicks":
    })

# ----------------------------------------------------
# リトライ制御ラッパー関数（データエンジニアリングの責務領域）
# ----------------------------------------------------
@retry(
    stop=stop_after_attempt(5),               # 最大5回までリトライ
    wait=wait_fixed(1),                      # リトライ間隔を1秒固定にする
    retry=retry_if_exception_type(RuntimeError), # RuntimeErrorの場合のみリトライ
    reraise=True                             # 5回失敗した場合は元の例外をそのまま上に投げる
)
def fetch_data_with_retry():
    # 外部API関数をラップして安全に呼び出す
    return fetch_data_from_unstable_api()

def main():
    try:
        print("データ抽出処理を開始します...")
        df = fetch_data_with_retry()
        print("\n--- [DWHロード前ステージングデータ] ---")
        print(df)
    except Exception as e:
        print(f"\n[FATAL] パイプラインが異常終了しました: {e}")

if __name__ == "__main__":
    main()
```

---

### 2. ユーザーの解答と模範解答のギャップ

提出いただいたコードには、実務データパイプラインの観点から**3つの大きな改善ポイント（ギャップ）**があります。

#### ① リトライ上限（stop）の設定漏れ
提出コードでは `@retry` とだけデコレータが記述されており、**引数が空**になっています。
tenacity のデフォルトの挙動では、引数がない場合は**「無限に即時リトライ」**を繰り返します。期待する条件であった「最大5回」という制限が適用されていないため、もしAPIが恒久的に壊れていた場合、無限ループに陥りサーバーやクライアントのプロセスがハングしてしまいます。
必ず `@retry(stop=stop_after_attempt(5))` のように、リトライの上限境界を定義しましょう。

#### ② 待機時間（wait）と例外制御（retry）の欠落
エラー直後に秒間何十回ものスピードで即時リトライ（ビジーウェイト）を仕掛けると、相手サーバーへ負荷をかける「DDoS攻撃」のようになってしまいます。`wait=wait_fixed(1)` などの待機時間を設けるのが実務における作法です。また、`retry_if_exception_type(RuntimeError)` のように「リトライすべき例外」を限定することで、予期せぬ別のエラー（例：`NameError` や `TypeError`）が発生した際に無駄なリトライをして時間を無駄にすることを防げます。

#### ③ モック関数のロジック改変
提示したダミー関数（モックAPI）の内部に直接 `@retry` デコレータを書き加えて、さらに内部で `call_count` をインクリメントする位置を変更されていました。
実際の開発では、サードパーティのAPIクライアント（SDK）の関数ソースコードを直接書き換えることは不可能です。そのため、上記模範解答のように「元関数はそのまま触らずに、リトライ用のラッパー関数を別途用意してデコレートする」という**疎結合な設計**を意識すると、モックテストと本番環境の切り替えが非常にスムーズになります。

---

### 3. 次回同テーマに追加する制約の提案

もし今回のリトライ制御がシンプルに感じられた場合、次回はさらにデータパイプラインの実務に近づけるため、以下の制約を追加して挑戦してみることを提案します：

> **【次回追加制約案】**
> 「**Exponential Backoff（指数関数的バックオフ）とJitter（ゆらぎ）を適用**し、さらに、エラーの例外オブジェクトの中から『HTTPステータスコード』を判別して、**429（Too Many Requests）と503（Service Unavailable）の時のみリトライさせ、401（Unauthorized）などの認証エラー時はリトライせずに即座に例外をスロー（reraise）してパイプラインを落とす**動的フィルタリングロジックを実装せよ。」

---

### 4. 英語コミュニケーションの軽量レビュー

提出いただいたPRの英文は十分に意味が通じる素晴らしい内容ですが、海外のシニアエンジニアやレビュアーに向けて、より洗練された自然なビジネス・技術英語にブラッシュアップします。

* **オリジナル：**
  > Let script to have retry on its requesting to the api server 5 times in maximum.
  > This feature is for avoiding the suspension of the data extraction caused by temporal server errors such as 503 Service Unavailable.
* **添削案（洗練された表現）：**
  > **Implement a retry mechanism for API requests, capped at a maximum of 5 attempts.**
  > **This prevents data extraction failures caused by transient server errors, such as 503 Service Unavailable.**

* **解説：**
  `Let script to have ~` は少し不自然な使役表現に聞こえるため、開発現場では `Implement ~`（〜を実装する）と能動的な動詞から書き始めるのが一般的です。また、一時的なエラーは `temporal`（時間の、世俗の）よりも **`transient`（一時的な、過渡的な）** という技術用語を使うと、データインフラの文脈として非常にプロフェッショナルな印象になります。

---

今日のドリルはここまでです！今回の気づき（tenacityのパラメータ指定や関数のカプセル化設計）は、実務のデータパイプライン構築で100%活きてきます。素晴らしい挑戦でした。

⚙️ **次回は、どのテーマ（groupby集計、merge結合、またはスキーマバリデーション）に挑戦しますか？**