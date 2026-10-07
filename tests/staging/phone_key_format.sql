-- Warn if a PHONE or SMS key is not 10 or 11 digits in staging
-- Catches phone corruption before the view silently drops it, for example a
-- NUMBER(38,8) source phone whose fractional zeros leak into the key
{{ config(severity='warn') }}

select
    SOURCE_SYSTEM_ID,
    CHANNEL,
    COMMUNICATION_TYPE,
    OBJECT_KEY,
    length(OBJECT_KEY) as key_length
from {{ ref('stg_consumer_prefs') }}
where CHANNEL in ('PHONE', 'SMS')
  and not REGEXP_LIKE(OBJECT_KEY, '^[0-9]{10,11}$')
