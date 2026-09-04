-- Revised from sql/_daily/task04/my_answer.sql
-- NOT EXECUTED: this is a static revision, never run against Snowflake.
--
-- Differences from the submission, and why:
--
--   1. DATE_TRUNC on the boundary. The submission's `baseline` inherits the
--      time component of SESSION_DATE. That is harmless only because
--      DATEDIFF('day', ...) discards the time part -- switch to a >= / <
--      comparison without adding DATE_TRUNC and Monday's early-morning sales
--      are silently dropped every week. Note the reference date below keeps a
--      time component on purpose, the way a real batch would pass it.
--
--   2. Half-open interval [start, end) instead of
--      `DATEDIFF('day', baseline, sale_timestamp) BETWEEN 0 AND 7`, which
--      covered eight days and double-counted the execution week's Monday.
--
--   3. Boundaries computed into session variables rather than a CTE, so the
--      predicate operands are fixed before the query is planned instead of
--      relying on the optimizer to fold a scalar subquery into a constant.
--      Side effect: no CTEs at all, so the "two CTEs maximum" constraint is
--      met with room to spare (the submission used three).
--
--   4. No `base` CTE. Its ORDER BY guaranteed nothing -- ordering inside a CTE
--      does not propagate -- while being the most spill-prone operation in the
--      query, which is the very cost the PR set out to avoid.
--
--   5. Week label taken from the variable instead of MIN() over a constant,
--      and the total is COALESCEd. A week with no sales now reports 0 rather
--      than a (NULL, NULL) row.
--
--   6. `target_flg` dropped: `CASE WHEN <boolean> THEN true ELSE false END` is
--      the boolean expression itself, and filtering on a calculated column
--      blocks partition pruning.

USE SCHEMA MUSCLE_DB_TASK04.RAW;

-- Reference date. In production this is the batch execution timestamp; a time
-- component is included here to show the boundary logic is immune to it.
SET SESSION_DATE = '2026-09-01 03:15:00.000'::timestamp_ntz;

-- DAYOFWEEKISO is 1 on Monday regardless of the WEEK_START parameter, so
-- subtracting (DAYOFWEEKISO - 1) lands on this week's Monday and a further
-- 7 days lands on last week's Monday. No week number is ever materialised,
-- which is why the calendar/ISO year mismatch needs no special handling:
--   2026-09-01 (Tue) -> [2026-08-24 00:00, 2026-08-31 00:00)
--   2026-01-06 (Tue) -> [2025-12-29 00:00, 2026-01-05 00:00)
SET WEEK_START = date_trunc(
    'day',
    dateadd(day, -(DAYOFWEEKISO($SESSION_DATE) - 1) - 7, $SESSION_DATE)
);
SET WEEK_END = dateadd(day, 7, $WEEK_START);

-- Sanity check on the boundaries themselves. Run this during development:
-- start_dow must be 'Mon' and span_days must be 7. Either assertion alone
-- would have caught the eight-day off-by-one before submitting.
--
--   select
--       $WEEK_START as week_start
--       , $WEEK_END as week_end
--       , dayname($WEEK_START) as start_dow
--       , datediff('day', $WEEK_START, $WEEK_END) as span_days
--   ;

select
    $WEEK_START as week_start_date
    -- 0 rows in range still returns one row, so report 0 rather than NULL.
    , coalesce(sum(amount), 0) as amount_sum
from raw_weekly_sales
where
    -- Raw column compared against fixed values: sargable, and the upper bound
    -- is exclusive so the execution week's Monday is not counted twice.
    sale_timestamp >= $WEEK_START
    and sale_timestamp < $WEEK_END
;
