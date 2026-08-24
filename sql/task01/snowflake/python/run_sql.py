import sys
import snowflake.connector
from dotenv import load_dotenv
import os 

load_dotenv()

def execute_sql_file(file_path: str):
    print(f"🚀 SQLファイルを実行します: {file_path}")
    
    # 1. Snowflakeへの接続設定
    # ※実務では環境変数（os.getenv）などから取得するのが安全です
    user = os.getenv("SNOWFLAKE_USER")
    password = os.getenv("SNOWFLAKE_PASSWORD")
    account = os.getenv("SNOWFLAKE_ACCOUNT")
    warehouse = os.getenv("SNOWFLAKE_WAREHOUSE")
    database = os.getenv("SNOWFLAKE_DATABASE")
    schema = os.getenv("SNOWFLAKE_DEFAULT_SCHEMA")
    if not all([user, password, account]):
        print("Error: .env doesn't have enough authentification info")
        print("user : ", user)
        print("account : ", account)
        print("warehouse : ", warehouse)
        print("database : ", database)
        print("schema : ", schema)
        sys.exit(1)

    conn = snowflake.connector.connect(
        user=user,
        password = password,
        account = account,
        warehouse = warehouse,
        database = database,
        schema = schema
    )

    try:
        # 2. SQLファイルの読み込み
        with open(file_path, 'r', encoding='utf-8') as f:
            sql_queries = f.read()

        # 3. SQLの実行
        # execute_string を使うことで、ファイル内に複数のSQL文（;区切り）があっても順番に実行してくれます
        cursors = conn.execute_string(sql_queries)
        
        for cursor in cursors:
            print("\n=== 実行結果 ===")
            # 取得したデータを表示（必要に応じてPolarsのDataFrameに渡すことも可能です）
            for row in cursor:
                print(row)
                
        print("\n✅ 実行完了！")

    except Exception as e:
        print(f"\n❌ エラーが発生しました: {e}")
    finally:
        conn.close()

if __name__ == "__main__":
    # コマンドライン引数からファイルパスを受け取る
    if len(sys.argv) < 2:
        print("使い方: uv run python python/run_sql.py <実行したいSQLファイルのパス>")
        sys.exit(1)
        
    sql_file = sys.argv[1]
    execute_sql_file(sql_file)