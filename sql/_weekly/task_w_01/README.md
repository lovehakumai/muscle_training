# SQL Weekly task_w_01

今回選んだテーマ: 5. dbt のテスト設計

## 業務要件（シナリオ）

あなたはECサイトのロイヤリティポイントプログラムのデータ基盤を担当しています。
現在、ユーザーの日次の獲得ポイントを集計するモデル `fct_user_daily_points` を dbt で開発しようとしていますが、上流システムから連携される `raw_transactions` には以下のようないくつかの懸念があることが分かっています。

- リトライ処理の不具合により、同一の `transaction_id` が重複して連携されることがある（ポイントの二重付与事故に繋がる）。
- 購入キャンセルによるマイナス金額のレコードや、ポイントが未設定（NULL）のレコードが混ざることがある。
- システム障害で丸1日データが連携されない「0件の区間（日）」が発生するリスクがある。
- システムのバグにより、異常に巨大なポイントが記録されることがある。

テックリードから、「単に集計クエリを書くだけでなく、dbt のテスト機能を最大限に活用して、これらのデータ異常を本番環境に出さない堅牢なパイプラインを設計してほしい」と依頼されました。

## 制約条件 & テックリードからの要求

✓ `models/` 配下に、`fct_user_daily_points` (user_id, date, total_points_earned, transaction_count) の集計モデルを作成すること（重複の排除など適切な処理を行うこと）。
✓ モデルに対し、`not_null`, `unique` などの generic tests（YAML）を過不足なく設定すること。
✓ generic tests では捕まえられない複雑な異常（例：マイナスポイントの不自然な集計、異常値、特定の日のデータ欠落・0件区間など）を捉えるための singular tests（SQL）を少なくとも2つ作成すること。
✓ **（最重要）書いた「すべてのテスト（generic/singular 共通）」について、PR の英語ディスクリプション内で『そのテストが失敗する入力データの例（壊れる条件）』を1つずつ具体的に説明すること。** 「このテストが失敗する入力を挙げられないのであれば、そのテストは何も守っていないのと同じだ」とテックリードは言っています。

## テーブル定義（DDL & サンプルデータ）

`setup.sql` と同じ内容です。

```sql
CREATE DATABASE IF NOT EXISTS MUSCLE_TRAINING;
USE DATABASE MUSCLE_TRAINING;
CREATE SCHEMA IF NOT EXISTS RAW;
USE SCHEMA RAW;

CREATE OR REPLACE TABLE raw_transactions (
    transaction_id VARCHAR,
    user_id INT,
    transaction_timestamp TIMESTAMP,
    purchase_amount INT,
    points_earned INT
);

INSERT INTO raw_transactions (transaction_id, user_id, transaction_timestamp, purchase_amount, points_earned) VALUES
('TXN-001', 1, '2026-09-01 10:00:00', 1000, 10),
('TXN-002', 2, '2026-09-01 11:30:00', 500, 5),
('TXN-003', 3, '2026-09-02 12:00:00', 2000, 20),
('TXN-003', 3, '2026-09-02 12:05:00', 2000, 20),
('TXN-004', 1, '2026-09-02 15:00:00', -1000, -10),
('TXN-005', 4, '2026-09-03 09:00:00', 300, NULL),
('TXN-006', 5, '2026-09-05 10:00:00', 99999999, 999999)
```

## 環境構築

```bash
python sql/run_sql.py _weekly/task_w_01/setup.sql --env {環境名}
```
※dbt プロジェクトの初期化（`dbt init` 等）が必要な場合はご自身で実施してください。

## 提出物

- dbt モデル（`models/` 配下）と YAML
- singular tests（`tests/` 配下）
- PR の英語ディスクリプション（必ず「各テストが失敗する入力例」を含めること）

---

解答の SQL とテストを書いてみてください。

**最低10分は何も見ずに書き切ってから提出してください。**
