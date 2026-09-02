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
def cleanse_raw_data(df_products:pd.DataFrame, df_sales:pd.DataFrame)-> pd.DataFrame:
    """
    [CLENSE] df_products  
    Implements process for duplicated product_id, only product_id with max number of id will be remained.  
    [MERGE] LEFT JOIN df_sales and df_products  
    key = [product_id, index]
    [ASSERTION] df_sales's row number should not be changed  
    """
    # ----------------------------------------------------
    # [CLEANSE] df_products
    # ----------------------------------------------------
    tmp_products = df_products.copy()
    tmp_products['idx'] = tmp_products.index
    tmp_products['product_id'] = tmp_products['product_id']
    max_idx = tmp_products.copy()
    max_idx = max_idx.groupby('product_id')['idx'].max().reset_index()
    tmp_products = pd.merge( tmp_products, max_idx, on = ['product_id', 'idx'], how='inner'  ).drop('idx', axis=1)

    # ----------------------------------------------------
    # [MERGE] LEFT JOIN df_sales and df_products  
    # ----------------------------------------------------
    tmp_sales = df_sales.copy()
    merged_df = pd.merge(tmp_sales, tmp_products, on = 'product_id', how = 'left')

    # ----------------------------------------------------
    # [MERGE] LEFT JOIN df_sales and df_products  
    # ----------------------------------------------------
    assert len(merged_df) == len(df_sales), f"Error : df_sales's row number is changed by merge. \n merged_row : {len(merged_df)} \n df_sales_row : {len(df_sales)}."
    return merged_df

def main():
    merged_df = cleanse_raw_data(df_products, df_sales)
    print(merged_df)

if __name__ == '__main__':
    main()