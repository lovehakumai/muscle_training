import pandas as pd
import numpy as np

# User purchase data with missing values
df_users = pd.DataFrame({
    'user_id': [1, 2, 3, 4, 5],
    'purchase_amount': [1500, np.nan, 3000, 400, np.nan],
    'member_rank': pd.Series(['Gold', 'Silver', 'Gold', np.nan, 'Silver'], dtype='category')
})

def cleanse_data(df_users:pd.DataFrame)-> pd.DataFrame:
    """
    Cleanse the user_data following the process below:  
    [CONSTRAINTS] Using .copy(), avoid changing the original DataFrame  

    [FILL NULL] Replacement of Null values of columns below  
    `member_rank` -> `Bronze`, data type is category  
    `purchase_amount` -> `0`, data type is Int64  
    
    [Deterministic] `purchase_amount` is sorted in descent order.  
    Users with same amount will be sorted by user_id in ascend order,  
    Additionally, index is starts with 0.  
    """
    tmp_users = df_users.copy()
    tmp_users['member_rank'] = tmp_users['member_rank'].astype('string').fillna('Bronze').astype('category')
    tmp_users['purchase_amount'] = tmp_users['purchase_amount'].astype('Int64').fillna(0)
    tmp_users = tmp_users.sort_values(by = ['purchase_amount', 'user_id'], ascending = [False, True]).reset_index(drop=True)

    return tmp_users

def main():
    df = cleanse_data(df_users)
    print(df)


if __name__ == '__main__':
    main()
    