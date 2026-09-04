import pandas as pd
from tenacity import retry, stop_after_attempt, wait_fixed # 必要なモジュールは適宜調整してくれ

# ----------------------------------------------------
# 準備用のダミー関数（モックAPI）
# 3回目までの呼び出しは一時的なエラーを投げ、4回目でデータ（DataFrame）を返す。
# ----------------------------------------------------
call_count = 0

@retry
def fetch_data_from_unstable_api():
    global call_count
    if call_count < 4:
        print(f"[API] Call {call_count}: 503 Service Unavailable (Temporary Error)")
        call_count += 1
        raise RuntimeError("API Temporary Error")
    else:
        print(f"[API] Call {call_count}: 200 OK (Success)")
        return pd.DataFrame({
            "campaign_id": [101, 102],
            "clicks": [1500, 2300]
        })

def main():
    df = fetch_data_from_unstable_api()
    print(df)


if __name__ == "__main__":
    main()