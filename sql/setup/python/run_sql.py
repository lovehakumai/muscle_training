import argparse
import os
import sys
from pathlib import Path
from dotenv import load_dotenv
import snowflake.connector


def parse_args():
    parser = argparse.ArgumentParser(description="Snowflake SQL Runner")
    parser.add_argument("sql_file", help="Path to the SQL file to execute")
    parser.add_argument(
        "--env",
        default=None,
        help="Environment name to load (e.g., task01 -> loads .env.task01)",
    )
    return parser.parse_args()


def load_environment(env_name: str | None):
    """Load the .env file based on the provided --env argument."""
    if env_name:
        env_file = Path(f"setup/envs/.env.{env_name}")
        print(env_file)
    else:
        env_file = Path("setup/envs/.env")
        
    if not env_file.exists():
        print(f"⚠️  Warning: Configuration file '{env_file}' not found.")
    else:
        print(f"🔧 Loaded environment configuration: {env_file}")
        load_dotenv(dotenv_path=env_file, override=True)


def execute_sql_file(file_path: str):
    print(f"🚀 Executing SQL file: {file_path}")

    user = os.getenv("SNOWFLAKE_USER")
    password = os.getenv("SNOWFLAKE_PASSWORD")
    account = os.getenv("SNOWFLAKE_ACCOUNT")
    warehouse = os.getenv("SNOWFLAKE_WAREHOUSE")
    database = os.getenv("SNOWFLAKE_DATABASE")
    schema = os.getenv("SNOWFLAKE_DEFAULT_SCHEMA")

    if not all([user, password, account]):
        print("Error: Required connection credentials are not set in the environment variables.")
        print(f"  user      : {user}")
        print(f"  account   : {account}")
        print(f"  warehouse : {warehouse}")
        print(f"  database  : {database}")
        print(f"  schema    : {schema}")
        sys.exit(1)

    try:
        # Connect without specifying database and schema initially
        # to prevent connection errors if they do not exist yet.
        conn = snowflake.connector.connect(
            user=user,
            password=password,
            account=account,
            warehouse=warehouse
        )
    except Exception as e:
        print(f"❌ Failed to connect to Snowflake: {e}")
        sys.exit(1)

    try:
        cursor = conn.cursor()
        
        # Create database if it does not exist and switch to it
        if database:
            print(f"Checking/Creating database: {database}")
            cursor.execute(f"CREATE DATABASE IF NOT EXISTS {database}")
            cursor.execute(f"USE DATABASE {database}")
            
            # Create schema if it does not exist and switch to it
            if schema:
                print(f"Checking/Creating schema: {schema}")
                cursor.execute(f"CREATE SCHEMA IF NOT EXISTS {schema}")
                cursor.execute(f"USE SCHEMA {schema}")

        # Read and execute the target SQL file
        with open(file_path, "r", encoding="utf-8") as f:
            sql_queries = f.read()

        cursors = conn.execute_string(sql_queries)

        for cur in cursors:
            print("\n=== Execution Result ===")
            for row in cur:
                print(row)

        print("\n✅ Execution completed successfully!")

    except Exception as e:
        print(f"\n❌ An error occurred: {e}")
    finally:
        conn.close()


if __name__ == "__main__":
    args = parse_args()
    
    # 1. Load the specified env file
    load_environment(args.env)
    
    # 2. Execute SQL
    execute_sql_file(args.sql_file)