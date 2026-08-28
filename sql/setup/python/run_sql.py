import argparse
import os
import sys
from pathlib import Path
from dotenv import load_dotenv
import snowflake.connector


def parse_args():
    parser = argparse.ArgumentParser(description="Snowflake SQL Runner")
    parser.add_argument("sql_file", help="実行するSQLファイルのパス")
    parser.add_argument(
        "--env",
        default=None,
        help="読み込む環境名（例: task01 -> .env.task01 を読み込み）",
    )
    return parser.parse_args()


def load_environment(env_name: str | None):
    """--env の指定に応じて .env ファイルを切り替えて読み込む"""
    if env_name:
        env_file = Path(f"setup/envs/.env.{env_name}")
        print(env_file)
    else:
        env_file = Path("setup/envs/.env")
    if not env_file.exists():
        print(f"⚠️  警告: 設定ファイル '{env_file}' が見つかりません。")
    else:
        print(f"🔧 環境設定を読み込みました: {env_file}")
        load_dotenv(dotenv_path=env_file, override=True)


def execute_sql_file(file_path: str):
    print(f"🚀 SQLファイルを実行します: {file_path}")

    user = os.getenv("SNOWFLAKE_USER")
    password = os.getenv("SNOWFLAKE_PASSWORD")
    account = os.getenv("SNOWFLAKE_ACCOUNT")
    warehouse = os.getenv("SNOWFLAKE_WAREHOUSE")
    database = os.getenv("SNOWFLAKE_DATABASE")
    schema = os.getenv("SNOWFLAKE_DEFAULT_SCHEMA")

    if not all([user, password, account]):
        print("Error: 接続に必要な認証情報が環境変数に設定されていません")
        print(f"  user      : {user}")
        print(f"  account   : {account}")
        print(f"  warehouse : {warehouse}")
        print(f"  database  : {database}")
        print(f"  schema    : {schema}")
        sys.exit(1)

    try:
        conn = snowflake.connector.connect(
            user=user,
            password=password,
            account=account,
            warehouse=warehouse,
            database=database,
            schema=schema,
        )
    except Exception as e:
        print(f"❌ Snowflakeへの接続に失敗しました: {e}")
        sys.exit(1)

    try:
        with open(file_path, "r", encoding="utf-8") as f:
            sql_queries = f.read()

        cursors = conn.execute_string(sql_queries)

        for cursor in cursors:
            print("\n=== 実行結果 ===")
            for row in cursor:
                print(row)

        print("\n✅ 実行完了！")

    except Exception as e:
        print(f"\n❌ エラーが発生しました: {e}")
    finally:
        conn.close()


if __name__ == "__main__":
    args = parse_args()
    
    # 1. 指定された env ファイルをロード
    load_environment(args.env)
    
    # 2. SQL 実行
    execute_sql_file(args.sql_file)