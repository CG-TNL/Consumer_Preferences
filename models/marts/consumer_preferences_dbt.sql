-- Target table that mirrors the existing CONSUMER_PREFERENCES structure.
-- Incremental: each run replaces only the business keys that changed in the
-- latest snapshot run, so the whole table is never rebuilt. On first run (or
-- --full-refresh) it loads every row.
-- ACTIVE = TRUE means this is the live version (snapshot dbt_valid_to is null).

{{ config(
    materialized='incremental',
    unique_key=['OBJECT_KEY', 'CHANNEL', 'COMMUNICATION_TYPE', 'SOURCE_SYSTEM_ID'],
    incremental_strategy='delete+insert'
) }}

with snap as (
    select * from {{ ref('snap_consumer_prefs') }}
),

{% if is_incremental() %}
-- Business keys touched in the most recent snapshot run (opened or closed)
changed_keys as (
    select distinct OBJECT_KEY, CHANNEL, COMMUNICATION_TYPE, SOURCE_SYSTEM_ID
    from snap
    where dbt_valid_from = (select max(dbt_valid_from) from snap)
       or dbt_valid_to   = (select max(dbt_valid_from) from snap)
),
{% endif %}

final as (
    select
        s.OBJECT_KEY,
        s.CHANNEL,
        s.COMMUNICATION_TYPE,
        s.DECISION,
        s.CONSENT_START_DATE,
        s.CONSENT_END_DATE,
        s.CONSUMER_GROUP,
        s.SOURCE_IDENTIFIER,
        s.SOURCE_SYSTEM_ID,
        s.ETL_TIMESTAMP,
        iff(s.dbt_valid_to is null, true, false) as ACTIVE
    from snap s
    {% if is_incremental() %}
    inner join changed_keys c
        on  s.OBJECT_KEY         = c.OBJECT_KEY
        and s.CHANNEL            = c.CHANNEL
        and s.COMMUNICATION_TYPE = c.COMMUNICATION_TYPE
        and s.SOURCE_SYSTEM_ID   = c.SOURCE_SYSTEM_ID
    {% endif %}
)

select *
from final
