import pandas as pd
import numpy as np

# User purchase data with missing values
df_users = pd.DataFrame({
    'user_id': [1, 2, 3, 4, 5],
    'purchase_amount': [1500, np.nan, 3000, 400, np.nan],
    'member_rank': pd.Series(['Gold', 'Silver', 'Gold', np.nan, 'Silver'], dtype='category')
})