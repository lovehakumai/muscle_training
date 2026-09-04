import pandas as pd

# ----------------------------------------------------
# Daily campaign performance log data
# ----------------------------------------------------
df_perf = pd.DataFrame({
    "campaign_id": [101, 101, 101, 102, 102, 103],
    "date": ["2026-09-01", "2026-09-02", "2026-09-03", "2026-09-01", "2026-09-02", "2026-09-01"],
    "impressions": [1500, 3200, 2400, 4500, 4100, 800],
    "clicks": [120, 310, 180, 400, 380, 50]
})
def pipeline(df_perf: pd.DataFrame)->pd.DataFrame:
    tmp_df = df_perf.copy()
    tmp_df = tmp_df.sort_values(by = 'impressions', ascending=False).drop_duplicates(subset=['campaign_id'], keep='first')
    tmp_camp_ncnt_raw = df_perf.drop_duplicates(subset=['campaign_id']).size
    tmp_camp_ncnt_result = tmp_df.size

    if tmp_camp_ncnt_raw != tmp_camp_ncnt_result:
        error_txt = f'Error at unique number of campaign_id: raw {tmp_camp_ncnt_raw} , result: {tmp_camp_ncnt_result}'
        raise ValueError(error_txt)
        
    return tmp_df 

def main():
    df = pipeline(df_perf)
    print(df)

if __name__ == '__main__':
    main()