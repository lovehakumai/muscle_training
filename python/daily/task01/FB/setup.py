import pandas as pd
from tenacity import retry, stop_after_attempt, wait_fixed, retry_if_exception_type

# ----------------------------------------------------
# 準備用のダミー関数（モックAPI）
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
        "campaign_id": [101, 102],
        "clicks": [1500, 2300]
    })

@retry(
    stop = stop_after_attempt(5), # 5 in maximum
    wait = wait_fixed(1), # interval is 1 sec
    retry = retry_if_exception_type(RuntimeError), # retry is available only with RuntimeError
    reraise = True # after 5 times retrying, it will raise error again.
)
def fetch_data_with_retry():
    return fetch_data_from_unstable_api()

def main():
    try:
        print("Start extraction...")
        df = fetch_data_with_retry()
        print("\n---[DWH Staging Data]---")
        print(df)
    except Exception as e:
        print(f"\n[FATAL] Pipeline is stopped unexpectedly : {e}")

if __name__ == "__main__":
    main()