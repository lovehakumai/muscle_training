import pandas as pd
import numpy as np

# User purchase data with missing values
df_users = pd.DataFrame({
    'user_id': [1, 2, 3, 4, 5],
    'purchase_amount': [1500, np.nan, 3000, 400, np.nan],
    'member_rank': pd.Series(['Gold', 'Silver', 'Gold', np.nan, 'Silver'], dtype='category')
})

def cleanse_data(df_users: pd.DataFrame) -> pd.DataFrame:
    """
    [修正版スクリプトの差分]
    - tmp_users['member_rank']: astype('string') を経由する処理を削除し、
      cat.add_categories を使ってカテゴリを追加してから fillna する形に変更
      （未使用のカテゴリオブジェクトのメタデータ消失を防ぐため）
    - tmp_users という中身を説明しない変数名を cleansed_users に変更（Pass 2 による指摘）
    """
    cleansed_users = df_users.copy()
    
    # カテゴリのメタデータを維持するため、cat.add_categories を使用
    if 'Bronze' not in cleansed_users['member_rank'].cat.categories:
        cleansed_users['member_rank'] = cleansed_users['member_rank'].cat.add_categories(['Bronze'])
    cleansed_users['member_rank'] = cleansed_users['member_rank'].fillna('Bronze')
    
    cleansed_users['purchase_amount'] = cleansed_users['purchase_amount'].astype('Int64').fillna(0)
    
    cleansed_users = cleansed_users.sort_values(by=['purchase_amount', 'user_id'], ascending=[False, True]).reset_index(drop=True)

    return cleansed_users

def main():
    df = cleanse_data(df_users)
    print(df)

if __name__ == '__main__':
    main()
