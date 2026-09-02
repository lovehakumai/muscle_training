import pandas as pd

# ----------------------------------------------------
# Sales transaction data (Target to keep original row count)
# ----------------------------------------------------
df_sales = pd.DataFrame({
    "transaction_id": [1, 2, 3, 4, 5],
    "product_id": [101, 102, 101, 999, 102], # '999' is an invalid product_id missing in master
    "amount": [1200, 1500, 800, 300, 2000]
})

# ----------------------------------------------------
# Product master data (Contains a duplicate entry due to system bug)
# ----------------------------------------------------
df_products = pd.DataFrame({
    "product_id": [101, 102, 103, 101], # '101' is duplicated
    "category": ["Electronics", "Furniture", "Apparel", "Electronics_New"]
})

# ----------------------------------------------------
# [PIPELINE] function
# ----------------------------------------------------
def cleanse_raw_data(df_products: pd.DataFrame, df_sales: pd.DataFrame) -> pd.DataFrame:
    """
    Deduplicate product master and merge with sales transactions safely.
    """
    # ----------------------------------------------------
    # [CLEANSE] df_products
    # Keep only the last occurrence of duplicate product_ids
    # ----------------------------------------------------
    tmp_products = df_products.drop_duplicates(subset=["product_id"], keep="last")

    # ----------------------------------------------------
    # [MERGE] LEFT JOIN df_sales and df_products
    # Ensure a many-to-one mapping relationship
    # ----------------------------------------------------
    tmp_sales = df_sales.copy()
    merged_df = pd.merge(
        tmp_sales, 
        tmp_products, 
        on="product_id", 
        how="left", 
        validate="many_to_one"
    )

    # ----------------------------------------------------
    # [FILLNA] Handle missing master keys
    # Replace NaN values in 'category' with 'Unknown'
    # ----------------------------------------------------
    merged_df["category"] = merged_df["category"].fillna("Unknown")

    # ----------------------------------------------------
    # [ASSERTION] Ensure transaction rows are preserved
    # ----------------------------------------------------
    assert len(merged_df) == len(df_sales), (
        f"Error: Row count changed from {len(df_sales)} to {len(merged_df)}"
    )
    
    return merged_df

def main():
    merged_df = cleanse_raw_data(df_products, df_sales)
    print(merged_df)

if __name__ == '__main__':
    main()
