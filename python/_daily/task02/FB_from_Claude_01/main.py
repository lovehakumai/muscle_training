"""Merge drill (task02) — revised per FB_from_Claude_01/README.md.

Differences from python/task02/FB/main.py:
  - Split into two single-responsibility functions (dedupe / join), mirroring
    the stg_ vs fct_ split in dbt. Each is independently testable.
  - reset_index(drop=True) before deduping, so the logic no longer depends on
    df_products arriving with a unique RangeIndex.
  - The tautological row-count assert is replaced by a check that can actually
    fail: master coverage. Row count cannot change once validate="m:1" passes.
  - raise ValueError instead of assert, so the data-quality gate survives
    python -O / PYTHONOPTIMIZE=1.
  - Unmatched keys are counted and logged *before* fillna hides them.
"""

import logging

import pandas as pd

logger = logging.getLogger(__name__)

# Fail the run if more than this share of sales rows have no product master.
# Set to 0.25 so the 1-in-5 miss in the sample data passes; in production this
# is tuned from the observed baseline (a real feed sits well under 1%).
MAX_UNMATCHED_RATE = 0.25

UNKNOWN_CATEGORY = "Unknown"


def dedupe_product_master(df_products: pd.DataFrame) -> pd.DataFrame:
    """Keep one row per product_id, retaining the last occurrence.

    NOTE: "last occurrence" is positional, i.e. it trusts the incoming row
    order. Once the master carries an updated_at column, sort by it first:

        df.sort_values(["product_id", "updated_at"])
          .drop_duplicates(subset=["product_id"], keep="last")

    Until then, an unsorted master silently yields the wrong category.
    """
    deduped = (
        df_products
        .reset_index(drop=True)  # do not rely on the caller's index
        .drop_duplicates(subset=["product_id"], keep="last")
    )

    dropped = len(df_products) - len(deduped)
    if dropped:
        logger.warning("Dropped %d duplicate product master row(s).", dropped)
    return deduped


def join_sales_with_category(
    df_sales: pd.DataFrame,
    df_products: pd.DataFrame,
) -> pd.DataFrame:
    """Left join sales onto the deduped product master and backfill misses.

    validate="many_to_one" makes an unexpected many-to-many relationship fail
    loudly rather than inflate the row count, so the join is safe by
    construction instead of by after-the-fact assertion.
    """
    deduped_products = dedupe_product_master(df_products)

    enriched = pd.merge(
        df_sales,
        deduped_products,
        on="product_id",
        how="left",
        validate="many_to_one",
    )

    # Count the misses BEFORE fillna hides them. This is the check that can
    # actually catch a broken upstream feed; the row count cannot change here.
    unmatched = int(enriched["category"].isna().sum())
    unmatched_rate = unmatched / len(enriched) if len(enriched) else 0.0
    logger.info(
        "Unmatched product_id rows: %d / %d (%.1f%%)",
        unmatched, len(enriched), unmatched_rate * 100,
    )
    if unmatched_rate > MAX_UNMATCHED_RATE:
        raise ValueError(
            f"Product master coverage degraded: {unmatched_rate:.1%} of sales "
            f"rows have no matching product_id (threshold "
            f"{MAX_UNMATCHED_RATE:.1%})."
        )

    enriched["category"] = enriched["category"].fillna(UNKNOWN_CATEGORY)
    return enriched


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(levelname)-8s %(message)s")

    # ----------------------------------------------------
    # Sales transaction data (row count must be preserved)
    # ----------------------------------------------------
    df_sales = pd.DataFrame({
        "transaction_id": [1, 2, 3, 4, 5],
        "product_id": [101, 102, 101, 999, 102],  # 999 is missing in master
        "amount": [1200, 1500, 800, 300, 2000],
    })

    # ----------------------------------------------------
    # Product master data (101 is duplicated due to a system bug)
    # ----------------------------------------------------
    df_products = pd.DataFrame({
        "product_id": [101, 102, 103, 101],
        "category": ["Electronics", "Furniture", "Apparel", "Electronics_New"],
    })

    # 999 is 1 of 5 rows (20%), just under MAX_UNMATCHED_RATE. Lower the
    # threshold to 0.05 to watch the coverage gate fire.
    enriched = join_sales_with_category(df_sales, df_products)
    print(enriched)


if __name__ == "__main__":
    main()
