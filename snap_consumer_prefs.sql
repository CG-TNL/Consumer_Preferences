-- SCD2 history for all sources in one snapshot
-- check strategy writes a new version only when a business column changes
-- Current version = dbt_valid_to is null (equals the old ACTIVE = TRUE)

{% snapshot snap_consumer_prefs %}

{{ config(
    target_schema=target.schema,
    unique_key='BUSINESS_KEY',
    strategy='check',
    check_cols=['DECISION', 'CONSENT_START_DATE', 'CONSENT_END_DATE', 'CONSUMER_GROUP'],
    invalidate_hard_deletes=false
) }}

-- Keep the latest normalized row per business key before snapshotting
with ranked as (
    select
        *,
        MD5(OBJECT_KEY || '|' || CHANNEL || '|' || COMMUNICATION_TYPE || '|' || SOURCE_SYSTEM_ID::varchar) as BUSINESS_KEY,
        row_number() over (
            partition by OBJECT_KEY, CHANNEL, COMMUNICATION_TYPE, SOURCE_SYSTEM_ID
            order by CONSENT_START_DATE desc nulls last, ETL_TIMESTAMP desc
        ) as rn
    from {{ ref('stg_consumer_prefs') }}
)

select * exclude (rn)
from ranked
where rn = 1

{% endsnapshot %}
