-- Use case 2: every source record should have a CONSUMER_GROUP.
-- Warn, not error: dev data has known gaps (for example SFMC).
-- Returns the offending rows so store_failures captures which sources miss it.

{{ config(severity='warn') }}

select
    SOURCE_SYSTEM_ID,
    OBJECT_KEY,
    CHANNEL,
    COMMUNICATION_TYPE
from {{ ref('consumer_preferences_dbt') }}
where ACTIVE = true
  and (CONSUMER_GROUP is null or trim(CONSUMER_GROUP) = '')
