# 💻 シニア・データエンジニア（テックリード）からの挑戦状 #2

## 今回選んだテーマ： 半構造化データの安全な展開（LATERAL FLATTEN による行数爆発とメモリ枯渇の回避）

---

### 業務要件（シナリオ）

あなたはグローバルECプラットフォーム「OmniCart」のリード・データエンジニアです。

現在、モバイルアプリおよびWebフロントエンドから送信される生イベントログを、Snowflake上のテーブル `raw_user_clickstream`（`VARIANT` 型カラム `event_payload` を含む）にリアルタイムで取り込んでいます。

このログには、ユーザーが画面上で操作した複数の商品インタラクション情報（インプレッション、カート追加、クリックなど）がJSON配列（`interactions` 配列）としてネストされています。

今回、アナリティクスチームおよびレコメンデーションAIチームから以下のデータ抽出・加工要件（マートテーブル作成）が下りてきました。

1. **抽出対象の厳格な絞り込み**:
   分析対象は、**`US` リージョン（`country_code = 'US'`）** かつ **`2026-08-25` 以降（`event_timestamp >= '2026-08-25 00:00:00'`）** に発生したイベントログのみです。
2. **ネストされた配列の展開とフィルタリング**:
   `event_payload` 内の `interactions` 配列を展開し、各要素の中の `action_type` が **`'PURCHASE_INTENT'`** であるもののみを抽出してください。
3. **メタデータおよびアイテム詳細の取得**:
   抽出結果には、以下のカラムを含める必要があります。
   * `event_id` (VARCHAR)
   * `user_id` (VARCHAR)
   * `event_timestamp` (TIMESTAMP_NTZ)
   * `item_id` (VARCHAR) - `interactions` 配列内の各要素の `item_id`
   * `position_index` (INT) - `interactions` 配列内のインデックス順序（0始まり）
   * `discount_applied` (BOOLEAN) - 各アイテムの属性に含まれる `applied_discount`（NULLの場合は `FALSE` として扱うこと）
   * `raw_item_price` (DECIMAL(10,2)) - 各アイテムの `price`
4. **行数爆発（Cartesian Product / Explosion）の罠**:
   本番環境の `raw_user_clickstream` には、1イベントあたり数千件のダミーインタラクションを含むボットトラフィックや、EU/APACリージョンの巨大なトラフィックが混ざっています。
   **ナイーブにルートテーブル全体に対して `LATERAL FLATTEN` を実行してから WHERE 句で絞り込もうとすると、展開後のレコード数が数十億行に爆発し、ウェアハウスが Spillage（Local/Remote Disk Spilling）を起こしてクエリがタイムアウト（OOM）** します。

---

### 制約条件 & テックリードからの要求：

本番ウェアハウスのコンピュートコストを最小化し、クエリオプティマイザがプッシュダウン（Predicate Pushdown / Partition Pruning）を最大限効かせられるよう、以下のアーキテクチャ要件を遵守してください。

1. **早期フィルタリング（Early Filtering）の徹底**:
   `LATERAL FLATTEN` を適用する前に、必ずパーティション刈り込み（`event_timestamp`）およびクラスタリングキー（`country_code`）による絞り込みが物理的に先に行われる構造にすること。
2. **不要な列スキャン（Column Pruning）の排除**:
   JSON展開処理において不要な巨大ペイロード全体をメモリに乗せ続けないよう、必要なVARIANTパスのみを射出・参照すること。
3. **CTEの多段ネスト禁止（Single-stage CTE または インライン最適化）**:
   dbtモデルとして記述する際、中間CTEを無駄に5つも6つも作らず、可読性と実行効率を両立したクリーンなSQLで記述すること。
4. **型安全なキャスト（Safe Casting）**:
   生JSONの欠損や不正なデータ型によるクエリクラッシュを防ぐため、適切なSnowflakeのキャスト演算子（`::` または `TRY_TO_*` 関数）を使用すること。

---

### テーブル定義（DDL & サンプルデータ）

テスト用のDDLだ。Snowflake環境で実行してテストテーブルを作成してください。

```sql
-- テスト用テーブルの作成
CREATE OR REPLACE TRANSIENT TABLE raw_user_clickstream (
    event_id VARCHAR,
    user_id VARCHAR,
    country_code VARCHAR,
    event_timestamp TIMESTAMP_NTZ,
    event_payload VARIANT
);

-- テストデータのインサート
INSERT INTO raw_user_clickstream (event_id, user_id, country_code, event_timestamp, event_payload)
SELECT 
    'EVT_101', 'USR_001', 'US', '2026-08-25 10:00:00'::TIMESTAMP_NTZ,
    PARSE_JSON('{
        "device": "iOS",
        "interactions": [
            {"item_id": "PROD_A", "action_type": "IMPRESSION", "price": 10.00, "applied_discount": false},
            {"item_id": "PROD_B", "action_type": "PURCHASE_INTENT", "price": 49.99, "applied_discount": true},
            {"item_id": "PROD_C", "action_type": "CLICK", "price": 15.50}
        ]
    }')
UNION ALL
SELECT 
    'EVT_102', 'USR_002', 'US', '2026-08-25 11:30:00'::TIMESTAMP_NTZ,
    PARSE_JSON('{
        "device": "Android",
        "interactions": [
            {"item_id": "PROD_D", "action_type": "PURCHASE_INTENT", "price": 120.00, "applied_discount": null},
            {"item_id": "PROD_E", "action_type": "PURCHASE_INTENT", "price": 5.00, "applied_discount": false}
        ]
    }')
UNION ALL
-- 罠1: 対象外リージョン（EU）かつ膨大な配列データ（展開前に除外されるべき）
SELECT 
    'EVT_103', 'USR_BOT_01', 'EU', '2026-08-25 12:00:00'::TIMESTAMP_NTZ,
    PARSE_JSON('{
        "device": "Bot",
        "interactions": [
            {"item_id": "SPAM_1", "action_type": "PURCHASE_INTENT", "price": 999.00},
            {"item_id": "SPAM_2", "action_type": "PURCHASE_INTENT", "price": 999.00},
            {"item_id": "SPAM_3", "action_type": "PURCHASE_INTENT", "price": 999.00}
        ]
    }')
UNION ALL
-- 罠2: 対象外日時（過去データ。展開前にプルーニングされるべき）
SELECT 
    'EVT_104', 'USR_003', 'US', '2026-08-20 09:00:00'::TIMESTAMP_NTZ,
    PARSE_JSON('{
        "device": "Web",
        "interactions": [
            {"item_id": "PROD_OLD", "action_type": "PURCHASE_INTENT", "price": 30.00, "applied_discount": true}
        ]
    }')
UNION ALL
-- 罠3: 対象レコードだが PURCHASE_INTENT が配列内に1件も存在しないケース
SELECT 
    'EVT_105', 'USR_004', 'US', '2026-08-25 15:00:00'::TIMESTAMP_NTZ,
    PARSE_JSON('{
        "device": "Web",
        "interactions": [
            {"item_id": "PROD_VIEW_ONLY", "action_type": "IMPRESSION", "price": 25.00}
        ]
    }');
```

---

### 期待される結果セット

正しく最適化されたSQLを実行すると、以下の **3レコードのみ** が返されるはずです（ソート順は `event_id`, `position_index`）。

| EVENT_ID | USER_ID | EVENT_TIMESTAMP | ITEM_ID | POSITION_INDEX | DISCOUNT_APPLIED | RAW_ITEM_PRICE |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **EVT_101** | USR_001 | 2026-08-25 10:00:00.000 | PROD_B | 1 | TRUE | 49.99 |
| **EVT_102** | USR_002 | 2026-08-25 11:30:00.000 | PROD_D | 0 | FALSE | 120.00 |
| **EVT_102** | USR_002 | 2026-08-25 11:30:00.000 | PROD_E | 1 | FALSE | 5.00 |

---

解答のSQLを書いてみてください。
もし余裕があれば、前回同様に「なぜこの構造が物理的に最もSpillageを防ぎ、最速なのか」を英語のPull Request（PR）ディスクリプション形式で添えて提出してください！
