-- Warn if a consent window ends before it starts, in the clean view

{{ config(severity='warn') }}

select *
from {{ ref('vw_consumer_preferences_dbt') }}
where CONSENT_START_DATE is not null
  and CONSENT_END_DATE is not null
  and CONSENT_END_DATE < CONSENT_START_DATE
