-- Warn if an active registered source produced no rows in the target
-- Catches a source that silently stopped delivering

{{ config(severity='warn') }}

select
    s.SOURCE_SYSTEM_ID,
    s.SOURCE_DESCRIPTION
from {{ ref('consumer_preference_sources_dbt') }} s
left join {{ ref('consumer_preferences_dbt') }} t
    on s.SOURCE_SYSTEM_ID = t.SOURCE_SYSTEM_ID
where lower(s.IS_ACTIVE::string) = 'true'
group by 1, 2
having count(t.SOURCE_SYSTEM_ID) = 0
