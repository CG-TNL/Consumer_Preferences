-- The clean view must contain no invalid contact keys
-- Matches the view's own validity rule:
--   phone/sms: 10 to 11 digits, digits only
--   email: length > 5, exactly one @, not first or last character
-- The table is allowed to hold invalid keys; the view is not.

select *
from {{ ref('vw_consumer_preferences_dbt') }}
where (CHANNEL in ('PHONE', 'SMS')
        and (length(OBJECT_KEY) not between 10 and 11 or OBJECT_KEY rlike '[^0-9]'))
   or (CHANNEL = 'EMAIL'
        and not (length(OBJECT_KEY) > 5
                 and length(OBJECT_KEY) - length(replace(OBJECT_KEY, '@', '')) = 1
                 and position('@' in OBJECT_KEY) > 1
                 and position('@' in OBJECT_KEY) < length(OBJECT_KEY)))
