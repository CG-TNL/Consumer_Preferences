-- One place to read pipeline health, built from CONSUMER_PREFERENCES_PIPELINE_RUN_LOG_DBT
-- Per node: last status, time since last success, last vs 7-day-average duration,
-- last rows, run counts, and the last message. Failures sort to the top.
-- References the run-log table directly since a run hook owns it, not a model.

{{ config(materialized='view') }}

with log as (
    select * from {{ target.database }}.{{ target.schema }}.CONSUMER_PREFERENCES_PIPELINE_RUN_LOG_DBT
),

latest as (
    select
        NODE_NAME, RESOURCE_TYPE, STATUS, EXECUTION_SECONDS, ROWS_AFFECTED,
        MESSAGE, LOGGED_AT
    from log
    qualify row_number() over (partition by NODE_NAME order by LOGGED_AT desc) = 1
),

agg as (
    select
        NODE_NAME,
        count(*) as total_runs,
        count(case when LOGGED_AT >= dateadd(day, -7, current_timestamp()) then 1 end) as runs_7d,
        max(case when STATUS in ('success', 'pass') then LOGGED_AT end) as last_success_at,
        avg(case when LOGGED_AT >= dateadd(day, -7, current_timestamp()) then EXECUTION_SECONDS end) as avg_seconds_7d
    from log
    group by NODE_NAME
)

select
    l.NODE_NAME,
    l.RESOURCE_TYPE,
    l.STATUS                                              as LAST_STATUS,
    a.last_success_at                                     as LAST_SUCCESS_AT,
    datediff(hour, a.last_success_at, current_timestamp()) as HOURS_SINCE_SUCCESS,
    l.EXECUTION_SECONDS                                   as LAST_SECONDS,
    round(a.avg_seconds_7d, 1)                            as AVG_SECONDS_7D,
    l.ROWS_AFFECTED                                       as LAST_ROWS,
    a.runs_7d                                             as RUNS_7D,
    a.total_runs                                          as TOTAL_RUNS,
    l.LOGGED_AT                                           as LAST_RUN_AT,
    l.MESSAGE                                             as LAST_MESSAGE
from latest l
join agg a on l.NODE_NAME = a.NODE_NAME
order by
    iff(l.STATUS in ('success', 'pass'), 1, 0),
    l.NODE_NAME
