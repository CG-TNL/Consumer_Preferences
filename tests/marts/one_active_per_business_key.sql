-- Fails if any business key has more than one ACTIVE row
-- This proves the snapshot active-version logic is sound

select
    OBJECT_KEY,
    CHANNEL,
    COMMUNICATION_TYPE,
    SOURCE_SYSTEM_ID,
    count(*) as active_rows
from {{ ref('consumer_preferences_dbt') }}
where ACTIVE = true
group by 1, 2, 3, 4
having count(*) > 1
