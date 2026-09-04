"""Revised from python/daily/taks03/my_answer.py.

NOT EXECUTED: this is a static revision, never run.

Differences from the submission, and why:

  1. The validation actually validates. The original compared
     `df_perf.drop_duplicates(subset=['campaign_id'])` against the result of
     the same drop_duplicates call, so both sides were always
     `nunique()` and the check could never fail. Reversing `ascending` would
     have returned the minimum-impression day for every campaign with the row
     count still correct and no error raised. The peak check below is computed
     with groupby().max() -- a different code path from the extraction -- so it
     catches that.

  2. Ties are decided. `sort_values` defaults to kind='quicksort', which is not
     stable, so two rows sharing a campaign's maximum impressions could be
     ordered either way and `keep='first'` picked an arbitrary one. Sorting by
     `date` as a secondary key with kind='stable' makes the result reproducible.

  3. `date` is parsed. As strings, these values only sort correctly because
     they happen to be ISO-8601; an MM/DD/YYYY feed would sort 2026 before
     2025 with no error.

  4. No `.copy()`. The original copied the frame and then immediately replaced
     the copy with the result of sort_values, discarding it. Neither
     sort_values nor drop_duplicates mutates its input, so nothing needed
     protecting. (Contrast task02, where a column was being added and the copy
     was required.)

  5. Extraction and validation are separate functions, so the validation only
     sees the input and the output and cannot reuse the extraction's
     intermediate values -- which is how the tautology in (1) crept in.

  6. Deterministic output shape: sorted by campaign_id with the index reset,
     rather than left in impressions-descending order with the original
     non-contiguous index.

  7. ValueError rather than assert. `assert` is stripped under `python -O` /
     PYTHONOPTIMIZE=1, which would remove the data-quality gate entirely. The
     submission already got this right; keeping it.
"""

import pandas as pd

# ----------------------------------------------------
# Daily campaign performance log data
# ----------------------------------------------------
df_perf = pd.DataFrame({
    "campaign_id": [101, 101, 101, 102, 102, 103],
    "date": ["2026-09-01", "2026-09-02", "2026-09-03", "2026-09-01", "2026-09-02", "2026-09-01"],
    "impressions": [1500, 3200, 2400, 4500, 4100, 800],
    "clicks": [120, 310, 180, 400, 380, 50],
})


def extract_peak_impression_day(df: pd.DataFrame) -> pd.DataFrame:
    """Return one row per campaign: the day with the highest impressions.

    Ties on `impressions` are broken by the earliest `date`, so the same input
    always produces the same output.
    """
    result = (
        df
        .assign(date=lambda d: pd.to_datetime(d["date"]))
        .sort_values(
            by=["impressions", "date"],
            ascending=[False, True],
            kind="stable",  # the default quicksort is not stable
        )
        .drop_duplicates(subset=["campaign_id"], keep="first")
        .sort_values("campaign_id")
        .reset_index(drop=True)
    )

    _validate_peaks(df, result)
    return result


def _validate_peaks(df: pd.DataFrame, result: pd.DataFrame) -> None:
    """Check the result against groupby().max(), not against the extraction.

    Takes only the input and the output on purpose: with no access to the
    extraction's intermediate values, the check cannot accidentally restate
    the implementation.
    """
    # Shape: one row per campaign. len() counts rows; .size counts rows * columns.
    expected_campaigns = df["campaign_id"].nunique()
    if len(result) != expected_campaigns:
        raise ValueError(
            f"Expected one row per campaign ({expected_campaigns}), "
            f"got {len(result)} rows."
        )

    # Content: the retained row really does carry the group maximum. This is the
    # assertion that can fail -- flip `ascending` above and it fires immediately.
    expected_peaks = df.groupby("campaign_id")["impressions"].max().sort_index()
    actual_peaks = result.set_index("campaign_id")["impressions"].sort_index()
    if not actual_peaks.equals(expected_peaks):
        raise ValueError(
            "Extracted rows are not the per-campaign maximum.\n"
            f"expected:\n{expected_peaks}\n"
            f"actual:\n{actual_peaks}"
        )


def main():
    print(extract_peak_impression_day(df_perf))


if __name__ == "__main__":
    main()
