-- Use case 10: the view should hold unique records for the combination of
-- object_key, channel, source_description, and consent_start_date.
-- Warn: two active rows differing only by communication_type would show here,
-- which can be legitimate. It flags unexpected view-level duplication.

{{ config(severity='warn') }}

select
    OBJECT_KEY,
    CHANNEL,
    SOURCE_DESCRIPTION,
    CONSENT_START_DATE,
    count(*) as row_count
from {{ ref('vw_consumer_preferences_dbt') }}
group by OBJECT_KEY, CHANNEL, SOURCE_DESCRIPTION, CONSENT_START_DATE
having count(*) > 1
