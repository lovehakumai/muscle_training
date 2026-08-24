import requests
import polars as pl
from tenacity import retry, stop_after_attempt, wait_exponential

# 1. Tenacityによるリトライ設定（500系エラー時に最大5回リトライ）
@retry(
    stop=stop_after_attempt(5),
    wait=wait_exponential(multiplier=1, max=10),
    reraise=True
)
def fetch_api_data(url: str) -> list:
    print(f"APIへリクエストを送信中...: {url}")
    response = requests.get(url)
    
    if 500 <= response.status_code < 600:
        print(f"⚠️ 500系エラー({response.status_code})を検知。リトライします...")
        response.raise_for_status()
        
    response.raise_for_status()
    return response.json()

def main() -> None:
    # テスト用のダミーAPI（ユーザー情報を10件返します）
    url = "https://jsonplaceholder.typicode.com/users"
    
    try:
        data = fetch_api_data(url)
        df = pl.DataFrame(data)
        
        print("\n✅ データの取得・変換に成功しました！\n")
        print("=== 📊 データプレビュー ===")
        print(df.head(3))
        
        print("\n=== 🔍 欠損値(Null)のカウント ===")
        print(df.null_count())
        
        print("\n=== 📈 基本統計量 (プロファイリング) ===")
        print(df.describe())
        
    except Exception as e:
        print(f"\n❌ エラーが発生しました: {e}")

# ↓直接ファイルを実行した時にだけmain()を動かすおまじない
if __name__ == "__main__":
    main()