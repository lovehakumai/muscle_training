"""Retry drill (task01) — revised per FB_from_Claude_01/README.md.

Differences from python/task01/FB/setup.py:
  - main() returns a non-zero exit code on failure, so an orchestrator
    (Airflow / cron / CI) actually sees the failure instead of a silent success.
  - print() -> logging, and before_sleep_log() makes each retry observable
    even when the upstream client logs nothing.
  - The retry policy catches only RuntimeError, matching retry_if_exception_type.
  - MAX_ATTEMPTS is named so that "attempts" vs "retries" is unambiguous.
"""

import logging
import sys

import pandas as pd
from tenacity import (
    before_sleep_log,
    retry,
    retry_if_exception_type,
    stop_after_attempt,
    wait_fixed,
)

logger = logging.getLogger(__name__)

# 1 initial call + 4 retries. The mock succeeds on the 4th call, so this
# leaves one attempt of headroom.
MAX_ATTEMPTS = 5

# ----------------------------------------------------
# Mock API (treated as third-party code: never modified)
# Calls 1-3 raise a transient error; the 4th returns a DataFrame.
# ----------------------------------------------------
call_count = 0


def fetch_data_from_unstable_api() -> pd.DataFrame:
    global call_count
    call_count += 1
    if call_count < 4:
        print(f"[API] Call {call_count}: 503 Service Unavailable (Temporary Error)")
        raise RuntimeError("API Temporary Error")

    print(f"[API] Call {call_count}: 200 OK (Success)")
    return pd.DataFrame({
        "campaign_id": [101, 102],
        "clicks": [1500, 2300],
    })


# ----------------------------------------------------
# Retry wrapper: the policy lives here, not inside the client.
# Keeping it separate means the same client can be wrapped with a
# different policy per caller, and the client stays trivially mockable.
# ----------------------------------------------------
@retry(
    stop=stop_after_attempt(MAX_ATTEMPTS),
    wait=wait_fixed(1),
    retry=retry_if_exception_type(RuntimeError),
    reraise=True,
    before_sleep=before_sleep_log(logger, logging.WARNING),
)
def fetch_data_with_retry() -> pd.DataFrame:
    return fetch_data_from_unstable_api()


def main() -> int:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)-8s %(message)s",
    )
    logger.info("Starting extraction (up to %d attempts)...", MAX_ATTEMPTS)

    try:
        df = fetch_data_with_retry()
    except RuntimeError:
        # Log the traceback, then fail loudly: a non-zero exit code is the
        # only thing an orchestrator reads.
        logger.exception("[FATAL] Extraction failed after %d attempts.", MAX_ATTEMPTS)
        return 1

    logger.info("Extracted %d rows.", len(df))
    print(df)
    return 0


if __name__ == "__main__":
    sys.exit(main())
