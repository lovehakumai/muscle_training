# 💻 シニア・データエンジニア（テックリード）からの挑戦状 #3

## 今回選んだテーマ： Spillage（ディスク溢れ）の回避

### 業務要件（シナリオ）
あなたは急成長中のFinTech決済プラットフォーム「ApexPay」のリード・データエンジニアです。

現在、毎月数億件規模の決済トランザクションが発生しており、財務レポーティング用の月次集計マートテーブル `fct_monthly_merchant_financial_summary` を構築するdbtパイプラインを運用しています。

しかし、前回の月末バッチ実行時、ダウンストリームのダッシュボード更新が大幅に遅延し、FinOpsチームから「特定の中間モデルでウェアハウスのメモリが枯渇し、Local Disk Spillingのみならず Remote Disk Spilling（S3/クラウドストレージへの退避）が数十GB発生してウェアハウスのクレジット消費が跳ね上がっている」と重大インシデントとしてエスカレーションされました。

調査の結果、以下の実務特有の泥臭い仕様変更とデータ特性が原因であることが判明しました：

1. **仕様変更による不要な巨大列の引きずり回し**:
   以前のパイプライン改修の際、デバッグ用に追加された巨大なペイロード列（監査ログのRAW JSONテキストやユーザーエージェント文字列など）を中間CTEで `SELECT *` でそのまま保持し続けたまま、複数テーブルのJOINとGROUP BY集計を行っていました。
2. **多対多（Many-to-Many）のファンアウト（行数爆発）の罠**:
   加盟店（Merchant）テーブル、端末（Terminal）テーブル、決済トランザクション（Transaction）テーブルを結合する際、加盟店ごとに複数端末が存在し、さらに端末のステータス履歴テーブル（SCD Type 2）が最新状態に絞り込まれていないため、ナイーブにJOINすると結合キーで爆発的な中間積（Cartesian-like explosion）が発生していました。
3. **WHERE句の遅延適用（遅すぎるフィルタリング）**:
   財務監査チームが必要としているのは「**2026年7月度（`2026-07-01` 〜 `2026-07-31`）**」かつ「**決済ステータスが `SETTLED`（清算済み）**」の確定トランザクションのみですが、すべての結合と巨大な集計が終わった「最後の最後」に `WHERE settlement_month = '2026-07'` で絞り込んでいました。これにより、過去数年分の全履歴データがJOINのハッシュテーブルと集計バッファに乗り、メモリを完全に圧迫していました。

あなたの任務は、これらのボトルネックを根本から排除し、**Spillageを完全にゼロ（ゼロ・スピリング）** に抑えつつ、加盟店ごとの月次サマリーを正確に集計するdbtモデルSQLを設計することです。

---

### 制約条件 & テックリードからの要求：

1. **早期射影（Early Column Pruning）と早期絞り込み（Early Predicate Pushdown）の徹底**:
   各ソーステーブルを参照する最初のステップで、必要な列のみに絞り込み、かつ日付範囲（2026年7月度）および決済ステータス（`SETTLED`）のフィルターを物理的にJOINの前に適用すること。不要な巨大テキスト列（`raw_payload`, `user_agent_details`）は結合パスに持ち込まないこと。
2. **集計先行パターン（Pre-Aggregation / Early Aggregation）の適用**:
   端末履歴や加盟店テーブルとトランザクションテーブルを巨大な行数のままJOINしてからGROUP BYするのではなく、可能な限りJOINの前にトランザクションテーブル側で加盟店単位の事前集計（Pre-aggregation）を行うか、あるいは端末テーブルの最新化を事前に行ってからJOINし、JOIN中間テーブルの行数爆発を抑え込むこと。
3. **CTEの責務分離（Single Responsibility CTEs）**:
   各CTEの役割（Filtering -> Pre-aggregating -> Enriching / Final Joining）を明確にし、メモリ消費を最小化するクリーンなdbtモデル構成とすること。

---

### テーブル定義（DDL & サンプルデータ）
テスト用のDDLだ。

```SQL
-- 1. 加盟店マスタ
CREATE OR REPLACE TRANSIENT TABLE raw_merchants (
    merchant_id VARCHAR,
    merchant_name VARCHAR,
    category VARCHAR,
    country_code VARCHAR
);

-- 2. 決済端末マスタ（SCD Type 2履歴形式：1つの加盟店に複数端末が存在し、履歴行もある）
CREATE OR REPLACE TRANSIENT TABLE raw_terminals (
    terminal_id VARCHAR,
    merchant_id VARCHAR,
    terminal_model VARCHAR,
    is_active BOOLEAN,
    valid_from TIMESTAMP_NTZ,
    valid_to TIMESTAMP_NTZ
);

-- 3. 決済トランザクションテーブル（本番では数億行規模。巨大なペイロードを含む）
CREATE OR REPLACE TRANSIENT TABLE raw_transactions (
    transaction_id VARCHAR,
    merchant_id VARCHAR,
    terminal_id VARCHAR,
    transaction_timestamp TIMESTAMP_NTZ,
    transaction_status VARCHAR,
    amount DECIMAL(12,2),
    fee_amount DECIMAL(12,2),
    raw_payload VARCHAR,          -- 巨大なデバッグ用JSONテキスト（Spillageの元凶）
    user_agent_details VARCHAR    -- 巨大な文字列
);

-- テストデータのインサート
INSERT INTO raw_merchants (merchant_id, merchant_name, category, country_code) VALUES
('MCH_001', 'Tokyo Bistro', 'FOOD_BEVERAGE', 'JP'),
('MCH_002', 'Global Retail US', 'RETAIL', 'US'),
('MCH_003', 'Kyoto Sweets', 'FOOD_BEVERAGE', 'JP');

INSERT INTO raw_terminals (terminal_id, merchant_id, terminal_model, is_active, valid_from, valid_to) VALUES
-- MCH_001の端末（旧端末と現行端末）
('TRM_101', 'MCH_001', 'MODEL_A', FALSE, '2025-01-01 00:00:00', '2026-06-30 23:59:59'),
('TRM_101', 'MCH_001', 'MODEL_A_V2', TRUE, '2026-07-01 00:00:00', NULL),
('TRM_102', 'MCH_001', 'MODEL_B', TRUE, '2026-01-01 00:00:00', NULL),

-- MCH_002の端末
('TRM_201', 'MCH_002', 'MODEL_X', TRUE, '2026-01-01 00:00:00', NULL);

INSERT INTO raw_transactions (
    transaction_id, 
    merchant_id, 
    terminal_id, 
    transaction_timestamp, 
    transaction_status, 
    amount, 
    fee_amount, 
    raw_payload, 
    user_agent_details
)
-- 正常系: 2026年7月のSETTLEDトランザクション（対象）
SELECT 'TX_001', 'MCH_001', 'TRM_101', '2026-07-05 14:00:00'::TIMESTAMP_NTZ, 'SETTLED', 1000.00, 30.00, REPEAT('DUMMY_JSON_PAYLOAD_', 50), 'Mozilla/5.0 Tokyo-Client'
UNION ALL
SELECT 'TX_002', 'MCH_001', 'TRM_102', '2026-07-15 18:30:00'::TIMESTAMP_NTZ, 'SETTLED', 2500.00, 75.00, REPEAT('DUMMY_JSON_PAYLOAD_', 50), 'Mozilla/5.0 Tokyo-Client'
UNION ALL
SELECT 'TX_003', 'MCH_002', 'TRM_201', '2026-07-20 10:15:00'::TIMESTAMP_NTZ, 'SETTLED', 500.00, 15.00, REPEAT('DUMMY_JSON_PAYLOAD_', 50), 'Mozilla/5.0 US-Client'
UNION ALL
-- 罠1: 2026年7月だが、ステータスがFAILEDやREFUNDED（集計対象外。早期除外されるべき）
SELECT 'TX_004', 'MCH_001', 'TRM_101', '2026-07-08 12:00:00'::TIMESTAMP_NTZ, 'FAILED', 8000.00, 0.00, REPEAT('DUMMY_JSON_PAYLOAD_', 50), 'Mozilla/5.0 Tokyo-Client'
UNION ALL
SELECT 'TX_005', 'MCH_002', 'TRM_201', '2026-07-22 16:00:00'::TIMESTAMP_NTZ, 'REFUNDED', 300.00, 9.00, REPEAT('DUMMY_JSON_PAYLOAD_', 50), 'Mozilla/5.0 US-Client'
UNION ALL
-- 罠2: 対象ステータス(SETTLED)だが、過去月または未来月（2026年6月や8月。パーティション刈り込みで早期除外されるべき）
SELECT 'TX_006', 'MCH_001', 'TRM_101', '2026-06-30 23:55:00'::TIMESTAMP_NTZ, 'SETTLED', 4000.00, 120.00, REPEAT('DUMMY_JSON_PAYLOAD_', 50), 'Mozilla/5.0 Tokyo-Client'
UNION ALL
SELECT 'TX_007', 'MCH_003', 'TRM_301', '2026-08-01 01:00:00'::TIMESTAMP_NTZ, 'SETTLED', 1200.00, 36.00, REPEAT('DUMMY_JSON_PAYLOAD_', 50), 'Mozilla/5.0 Kyoto-Client';
```

---

### 期待される結果セット

財務レポーティングに必要な最終出力は、**2026年7月度**の加盟店別サマリーです。
（出力列：`merchant_id`, `merchant_name`, `country_code`, `total_settled_amount`, `total_fee_amount`, `settled_tx_count`, `active_terminal_count`）

| MERCHANT_ID | MERCHANT_NAME | COUNTRY_CODE | TOTAL_SETTLED_AMOUNT | TOTAL_FEE_AMOUNT | SETTLED_TX_COUNT | ACTIVE_TERMINAL_COUNT |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **MCH_001** | Tokyo Bistro | JP | 3500.00 | 105.00 | 2 | 2 |
| **MCH_002** | Global Retail US | US | 500.00 | 15.00 | 1 | 1 |

* 注1: `MCH_001` の `active_terminal_count` は現時点で有効（`is_active = TRUE` かつ `valid_to IS NULL`）な端末数（TRM_101の現行行とTRM_102で計2台）。
* 注2: `MCH_003` は2026年7月に有効な清算トランザクションが存在しないため、月次レポート結果には含まれません（INNER JOINまたはトランザクション起点での集計）。

---

解答のSQLを書いてみてください。
また、もし余裕があれば、**「なぜこの順序で絞り込み・事前集計を行ったのか、どのようにSpillageを防いだのか」** を説明する **英語でのPR Description** も添えて提出してください！
楽しみに待っています！
