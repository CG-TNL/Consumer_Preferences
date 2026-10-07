-- Clean serving view. Mirrors the live VW_CONSUMER_PREFERENCES:
-- only ACTIVE rows, valid contact keys, simple consent end date, same columns.
-- Added per request: null or empty decisions default by channel
--   (email/media -> opt-in, phone/sms -> opt-out). The live view does not
--   do this; the source procedure defaults at staging instead.

{{ config(materialized='view') }}

with base_data as (
    select
        cp.OBJECT_KEY,
        cp.CHANNEL,
        cp.COMMUNICATION_TYPE,
        -- Default a null or empty decision by channel
        case
            when cp.DECISION is not null and trim(cp.DECISION) != '' then cp.DECISION
            when cp.CHANNEL in ('EMAIL', 'MEDIA') then 'OPT-IN'
            when cp.CHANNEL in ('PHONE', 'SMS') then 'OPT-OUT'
            else cp.DECISION
        end as DECISION,
        cp.CONSENT_START_DATE,
        cp.CONSENT_END_DATE,
        cp.CONSUMER_GROUP,
        cp.SOURCE_IDENTIFIER,
        cp.SOURCE_SYSTEM_ID,
        cs.SOURCE_DESCRIPTION,
        cs.SOURCE_DATABASE,
        cs.SOURCE_SCHEMA,
        cs.SOURCE_TABLE,
        cs.IS_ACTIVE as SOURCE_IS_ACTIVE,
        cs.LAST_ETL_UPDATE as SOURCE_LAST_UPDATE,
        cp.ETL_TIMESTAMP,
        cp.ACTIVE
    from {{ ref('consumer_preferences_dbt') }} cp
    left join {{ ref('consumer_preference_sources_dbt') }} cs
        on cp.SOURCE_SYSTEM_ID = cs.SOURCE_SYSTEM_ID
    where cp.ACTIVE = true
      and (
            (cp.CHANNEL in ('PHONE', 'SMS') and length(cp.OBJECT_KEY) between 10 and 11)
            or (cp.CHANNEL = 'EMAIL'
                and length(cp.OBJECT_KEY) > 5
                and contains(cp.OBJECT_KEY, '@')
                and length(cp.OBJECT_KEY) - length(replace(cp.OBJECT_KEY, '@', '')) = 1
                and position('@' in cp.OBJECT_KEY) > 1
                and position('@' in cp.OBJECT_KEY) < length(cp.OBJECT_KEY))
            or cp.CHANNEL not in ('PHONE', 'SMS', 'EMAIL')
          )
)

select
    OBJECT_KEY,
    CHANNEL,
    COMMUNICATION_TYPE,
    DECISION,
    CONSENT_START_DATE,
    case
        when CONSENT_END_DATE >= dateadd(year, 10, current_timestamp()) then '9999-12-31'::date
        when CONSENT_END_DATE is null then '9999-12-31'::date
        else CONSENT_END_DATE
    end as CONSENT_END_DATE,
    CONSUMER_GROUP,
    SOURCE_IDENTIFIER,
    SOURCE_SYSTEM_ID,
    SOURCE_DESCRIPTION,
    SOURCE_DATABASE,
    SOURCE_SCHEMA,
    SOURCE_TABLE,
    SOURCE_IS_ACTIVE,
    SOURCE_LAST_UPDATE,
    ETL_TIMESTAMP,
    ACTIVE
from base_data
