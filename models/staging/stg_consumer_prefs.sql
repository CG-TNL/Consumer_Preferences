-- All sources normalized to the shared 10-column contract, unioned into one
-- staging table. Each source keeps its own incremental watermark via
-- cp_incremental_filter, and its own outage guard (have_ check): if a source
-- table is missing this run, that source is skipped with a warning and the
-- others still load. This does not catch a renamed column.
--
-- To add a source: add its have_ check, its CTE block, and its union branch.

{{ config(
    materialized='incremental',
    unique_key=['SOURCE_SYSTEM_ID', 'SOURCE_IDENTIFIER', 'CHANNEL', 'COMMUNICATION_TYPE'],
    incremental_strategy='merge'
) }}

{# run_sources lets AutoSys run subsets at different cadences.
   'all' (default), one SOURCE_SYSTEM_ID, or a list. Example hourly job:
   build --vars '{run_sources: [3, 4, 7]}'  (skip the heavy daily sources) #}
{% set run_sources = var('run_sources', 'all') %}
{% set enabled_ids = [] %}
{% if run_sources is string and run_sources == 'all' %}
    {% set enabled_ids = [1, 2, 3, 4, 5, 6, 7] %}
{% elif run_sources is number %}
    {% set enabled_ids = [run_sources | int] %}
{% else %}
    {% for x in run_sources %}{% do enabled_ids.append(x | int) %}{% endfor %}
{% endif %}

{# have_ = selected to run this build AND the table is present. The enabled
   check comes first so source() is only referenced for selected sources, which
   lets a unit test with a run_sources override mock only the source it targets. #}
{% set have_dnc             = (2 in enabled_ids) and (load_relation(source('marketing_crm', 'cm_dnc_phone')) is not none) %}
{% set have_ccpa            = (1 in enabled_ids) and (load_relation(source('marketing_crm', 'cust_info_srch_ccpa_req_tbl')) is not none) %}
{% set have_journey         = (4 in enabled_ids) and (load_relation(source('sfdc_customservice', 'tmmarketing_texting_permission__c')) is not none) %}
{% set have_external        = (3 in enabled_ids) and (load_relation(source('marketing_crm', 'external_leads')) is not none) %}
{% set have_ff              = (5 in enabled_ids) and (load_relation(source('marketing_ownermart', 'ff_hello_profiles')) is not none) %}
{% set have_ff_tap          = (5 in enabled_ids) and (load_relation(source('marketing_ownermart', 'ff_hello_profiles_tap')) is not none) %}
{% set have_segment         = (5 in enabled_ids) and (load_relation(source('wd_dg', 'cm_segment')) is not none) %}
{% set have_ofsll_address   = (6 in enabled_ids) and (load_relation(source('ofsll_lz', 'address')) is not none) %}
{% set have_ofsll_telecoms  = (6 in enabled_ids) and (load_relation(source('ofsll_lz', 'telecoms')) is not none) %}
{% set have_sfmc            = (7 in enabled_ids) and (load_relation(source('marketing_response', 'sms_messagetracking_combined')) is not none) %}

{% if execute %}
    {% if (2 in enabled_ids) and not have_dnc %}{% do log("stg_consumer_prefs: DNC selected but source not found, skipping", info=true) %}{% endif %}
    {% if (1 in enabled_ids) and not have_ccpa %}{% do log("stg_consumer_prefs: CCPA selected but source not found, skipping", info=true) %}{% endif %}
    {% if (4 in enabled_ids) and not have_journey %}{% do log("stg_consumer_prefs: Journey selected but source not found, skipping", info=true) %}{% endif %}
    {% if (3 in enabled_ids) and not have_external %}{% do log("stg_consumer_prefs: External Leads selected but source not found, skipping", info=true) %}{% endif %}
    {% if (5 in enabled_ids) and not have_ff %}{% do log("stg_consumer_prefs: FF Hello Profiles selected but source not found, skipping", info=true) %}{% endif %}
    {% if (6 in enabled_ids) and not have_ofsll_address %}{% do log("stg_consumer_prefs: OFSLL Address selected but source not found, skipping", info=true) %}{% endif %}
    {% if (6 in enabled_ids) and not have_ofsll_telecoms %}{% do log("stg_consumer_prefs: OFSLL Telecoms selected but source not found, skipping", info=true) %}{% endif %}
    {% if (7 in enabled_ids) and not have_sfmc %}{% do log("stg_consumer_prefs: SFMC selected but source not found, skipping", info=true) %}{% endif %}
{% endif %}

with

{% if have_dnc %}
-- Source 2: DNC
dnc_src as (
    select *
    from {{ source('marketing_crm', 'cm_dnc_phone') }}
    where DNC_ETL_TAG_UPD is not null
      and TRY_TO_TIMESTAMP(LEFT(TO_VARCHAR(DNC_ETL_TAG_UPD), 14), 'YYYYMMDDHH24MISS') is not null
      and PHONE_NUMBER is not null
      and trim(PHONE_NUMBER) != ''
    {{ cp_incremental_filter(2, "TRY_TO_TIMESTAMP(LEFT(TO_VARCHAR(DNC_ETL_TAG_UPD), 14), 'YYYYMMDDHH24MISS')") }}
),
dnc_norm as (
    select
        REGEXP_REPLACE(PHONE_NUMBER, '[^0-9]', '')      as OBJECT_KEY,
        'PHONE'                                         as CHANNEL,
        'MARKETING'                                     as COMMUNICATION_TYPE,
        'OPT-OUT'                                       as DECISION,
        TRY_TO_TIMESTAMP(START_DATE::string)            as CONSENT_START_DATE,
        TRY_TO_TIMESTAMP(EXPIRED_DATE::string)          as CONSENT_END_DATE,
        CONCAT('DNC_', DNC_LIST)                        as CONSUMER_GROUP,
        DNC_PHONE_ID::varchar                           as SOURCE_IDENTIFIER,
        2                                               as SOURCE_SYSTEM_ID,
        TRY_TO_TIMESTAMP(LEFT(TO_VARCHAR(DNC_ETL_TAG_UPD), 14), 'YYYYMMDDHH24MISS')       as ETL_TIMESTAMP
    from dnc_src
),
{% endif %}

{% if have_ccpa %}
-- Source 1: CCPA
ccpa_src as (
    select *
    from {{ source('marketing_crm', 'cust_info_srch_ccpa_req_tbl') }}
    where ETL_TAG_UPD is not null
      and TRY_TO_TIMESTAMP(LEFT(TO_VARCHAR(ETL_TAG_UPD), 14), 'YYYYMMDDHH24MISS') is not null
      and UPPER(MISC2) in ('OPT-OUT', 'DELETE')
    {{ cp_incremental_filter(1, "TRY_TO_TIMESTAMP(LEFT(TO_VARCHAR(ETL_TAG_UPD), 14), 'YYYYMMDDHH24MISS')") }}
),
ccpa_email as (
    select
        EMAIL_ADDRESS                                                            as OBJECT_KEY,
        'MEDIA'                                                                  as CHANNEL,
        'MARKETING'                                                              as COMMUNICATION_TYPE,
        UPPER(case when UPPER(MISC2) = 'DELETE' then 'OPT-OUT' else MISC2 end)   as DECISION,
        COALESCE(
            TRY_TO_TIMESTAMP(MISC3::string),
            TRY_TO_TIMESTAMP(LOAD_DATE::string),
            TRY_TO_TIMESTAMP(LEFT(TO_VARCHAR(ETL_TAG_UPD), 14), 'YYYYMMDDHH24MISS')
        )                                                                        as CONSENT_START_DATE,
        cast(null as timestamp_ntz)                                              as CONSENT_END_DATE,
        'CCPA'                                                                   as CONSUMER_GROUP,
        MISC1::varchar                                                           as SOURCE_IDENTIFIER,
        1                                                                        as SOURCE_SYSTEM_ID,
        TRY_TO_TIMESTAMP(LEFT(TO_VARCHAR(ETL_TAG_UPD), 14), 'YYYYMMDDHH24MISS')  as ETL_TIMESTAMP
    from ccpa_src
    where EMAIL_ADDRESS is not null
      and trim(EMAIL_ADDRESS) != ''
),
ccpa_phone as (
    select
        REGEXP_REPLACE(CONCAT(COALESCE(AREA_CODE, ''), COALESCE(PHONE_NUMBER, '')), '[^0-9]', '') as OBJECT_KEY,
        'PHONE'                                                                  as CHANNEL,
        'MARKETING'                                                              as COMMUNICATION_TYPE,
        UPPER(case when UPPER(MISC2) = 'DELETE' then 'OPT-OUT' else MISC2 end)   as DECISION,
        COALESCE(
            TRY_TO_TIMESTAMP(MISC3::string),
            TRY_TO_TIMESTAMP(LOAD_DATE::string),
            TRY_TO_TIMESTAMP(LEFT(TO_VARCHAR(ETL_TAG_UPD), 14), 'YYYYMMDDHH24MISS')
        )                                                                        as CONSENT_START_DATE,
        cast(null as timestamp_ntz)                                              as CONSENT_END_DATE,
        'CCPA'                                                                   as CONSUMER_GROUP,
        MISC1::varchar                                                           as SOURCE_IDENTIFIER,
        1                                                                        as SOURCE_SYSTEM_ID,
        TRY_TO_TIMESTAMP(LEFT(TO_VARCHAR(ETL_TAG_UPD), 14), 'YYYYMMDDHH24MISS')  as ETL_TIMESTAMP
    from ccpa_src
    where (AREA_CODE is not null or PHONE_NUMBER is not null)
      and trim(CONCAT(COALESCE(AREA_CODE, ''), COALESCE(PHONE_NUMBER, ''))) != ''
),
{% endif %}

{% if have_journey %}
-- Source 4: Journey
journey_main_src as (
    select *
    from {{ source('sfdc_customservice', 'tmmarketing_texting_permission__c') }}
    where LASTMODIFIEDDATE is not null
      and TRY_TO_TIMESTAMP(LASTMODIFIEDDATE::string) is not null
      and TMPHONE_NUMBER__C is not null
      and trim(TMPHONE_NUMBER__C) != ''
      and UPPER(TRIM(TMOPT_IN_FOR__C)) != 'OFFER TRANSACTION'
    {{ cp_incremental_filter(4, "TRY_TO_TIMESTAMP(LASTMODIFIEDDATE::string)") }}
),
journey_offer_src as (
    select *
    from {{ source('sfdc_customservice', 'tmmarketing_texting_permission__c') }}
    where LASTMODIFIEDDATE is not null
      and TRY_TO_TIMESTAMP(LASTMODIFIEDDATE::string) is not null
      and TMPHONE_NUMBER__C is not null
      and trim(TMPHONE_NUMBER__C) != ''
      and UPPER(TRIM(TMOPT_IN_FOR__C)) = 'OFFER TRANSACTION'
      and UPPER(TRIM(TM_OPT_IN_TEXT_MESSAGE__C)) = 'TRUE'
    {{ cp_incremental_filter(4, "TRY_TO_TIMESTAMP(LASTMODIFIEDDATE::string)") }}
),
journey_quote as (
    select
        t.LASTMODIFIEDDATE,
        t.TMPHONE_NUMBER__C,
        t.TMSOURCE__C,
        t.ID,
        case when w.TMTOURENDTIME__C is not null then w.TMTOURENDTIME__C else q.EXPIRATION_DT end as EXPIRATION_DATE_DEFINED
    from journey_offer_src t
    left join {{ source('sfdc_customservice', 'quote_v') }} q
        on t.TMSOURCE_ID__C = q.QUOTENUMBER
    left join {{ source('sfdc_customservice', 'tmtourrecord__c') }} w
        on t.TMSOURCE_ID__C = w.OFFER_TRANSACTION_NUMBER__C
),
journey_sms_main as (
    select
        REGEXP_REPLACE(TMPHONE_NUMBER__C, '[^0-9]', '')          as OBJECT_KEY,
        'SMS'                                                    as CHANNEL,
        case
            when UPPER(TRIM(TMOPT_IN_FOR__C)) = 'FULL TCPA' and UPPER(TRIM(TMSOURCE__C)) = 'JOURNEY OFFERS' then 'MARKETING'
            when UPPER(TRIM(TMOPT_IN_FOR__C)) = 'FULL TCPA' then 'ALL'
            when UPPER(TRIM(TMOPT_IN_FOR__C)) = 'TOUR' then 'TRANSACTIONAL'
            else 'TRANSACTIONAL'
        end                                                      as COMMUNICATION_TYPE,
        case
            when UPPER(TRIM(TMSOURCE__C)) like '%OPT%OUT%' then 'OPT-OUT'
            when UPPER(TRIM(TM_OPT_IN_TEXT_MESSAGE__C)) = 'TRUE' then 'OPT-IN'
            else 'OPT-OUT'
        end                                                      as DECISION,
        case
            when UPPER(TRIM(TMSOURCE__C)) like '%OPT%OUT%' then TRY_TO_TIMESTAMP(TMOPT_OUT_DATE__C::string)
            else COALESCE(TRY_TO_TIMESTAMP(TMRECEIVED_DATE__C::string), TRY_TO_TIMESTAMP(LASTMODIFIEDDATE::string))
        end                                                      as CONSENT_START_DATE,
        cast(null as timestamp_ntz)                              as CONSENT_END_DATE,
        COALESCE(TMSOURCE__C, 'JOURNEY')                         as CONSUMER_GROUP,
        ID::varchar                                              as SOURCE_IDENTIFIER,
        4                                                        as SOURCE_SYSTEM_ID,
        TRY_TO_TIMESTAMP(LASTMODIFIEDDATE::string)               as ETL_TIMESTAMP
    from journey_main_src
    where REGEXP_REPLACE(TMPHONE_NUMBER__C, '[^0-9]', '') != ''
      and (UPPER(TRIM(TMSOURCE__C)) like '%OPT%OUT%' or UPPER(TRIM(TM_OPT_IN_TEXT_MESSAGE__C)) = 'TRUE')
),
journey_phone_main as (
    select
        REGEXP_REPLACE(TMPHONE_NUMBER__C, '[^0-9]', '')          as OBJECT_KEY,
        'PHONE'                                                  as CHANNEL,
        'MARKETING'                                              as COMMUNICATION_TYPE,
        case
            when UPPER(TRIM(TMSOURCE__C)) like '%OPT%OUT%' then 'OPT-OUT'
            when UPPER(TRIM(TM_OPT_IN_TEXT_MESSAGE__C)) = 'TRUE' then 'OPT-IN'
            else 'OPT-OUT'
        end                                                      as DECISION,
        case
            when UPPER(TRIM(TMSOURCE__C)) like '%OPT%OUT%' then TRY_TO_TIMESTAMP(TMOPT_OUT_DATE__C::string)
            else COALESCE(TRY_TO_TIMESTAMP(TMRECEIVED_DATE__C::string), TRY_TO_TIMESTAMP(LASTMODIFIEDDATE::string))
        end                                                      as CONSENT_START_DATE,
        cast(null as timestamp_ntz)                              as CONSENT_END_DATE,
        COALESCE(TMSOURCE__C, 'JOURNEY')                         as CONSUMER_GROUP,
        ID::varchar                                              as SOURCE_IDENTIFIER,
        4                                                        as SOURCE_SYSTEM_ID,
        TRY_TO_TIMESTAMP(LASTMODIFIEDDATE::string)               as ETL_TIMESTAMP
    from journey_main_src
    where UPPER(TRIM(TMOPT_IN_FOR__C)) = 'FULL TCPA'
      and UPPER(TRIM(TMSOURCE__C)) = 'JOURNEY OFFERS'
      and REGEXP_REPLACE(TMPHONE_NUMBER__C, '[^0-9]', '') != ''
),
journey_offer_sms as (
    select
        REGEXP_REPLACE(TMPHONE_NUMBER__C, '[^0-9]', '')          as OBJECT_KEY,
        'SMS'                                                    as CHANNEL,
        'MARKETING'                                              as COMMUNICATION_TYPE,
        'OPT-IN'                                                 as DECISION,
        TRY_TO_TIMESTAMP(EXPIRATION_DATE_DEFINED::string)        as CONSENT_START_DATE,
        TRY_TO_TIMESTAMP(EXPIRATION_DATE_DEFINED::string)        as CONSENT_END_DATE,
        COALESCE(TMSOURCE__C, 'JOURNEY')                         as CONSUMER_GROUP,
        ID::varchar                                              as SOURCE_IDENTIFIER,
        4                                                        as SOURCE_SYSTEM_ID,
        TRY_TO_TIMESTAMP(LASTMODIFIEDDATE::string)               as ETL_TIMESTAMP
    from journey_quote
    where REGEXP_REPLACE(TMPHONE_NUMBER__C, '[^0-9]', '') != ''
),
{% endif %}

{% if have_external %}
-- Source 3: External Leads
ext_src as (
    select *
    from {{ source('marketing_crm', 'external_leads') }}
    where ETL_INSERT_DATE is not null
      and TRY_TO_TIMESTAMP(ETL_INSERT_DATE::string) is not null
    {{ cp_incremental_filter(3, "TRY_TO_TIMESTAMP(ETL_INSERT_DATE::string)") }}
),
ext_phone as (
    select
        REGEXP_REPLACE(COALESCE(HOME_PHONE, WORK_PHONE), '[^0-9]', '') as OBJECT_KEY,
        'PHONE'                                                       as CHANNEL,
        'MARKETING'                                                   as COMMUNICATION_TYPE,
        case when UPPER(TRIM(PHONE_OPT_IN)) in ('Y', 'TRUE') then 'OPT-IN'
             when UPPER(TRIM(PHONE_OPT_IN)) in ('N', 'FALSE') then 'OPT-OUT'
             else 'OPT-OUT' end                                       as DECISION,
        COALESCE(TRY_TO_TIMESTAMP(SOURCE_TIMESTAMP::string), TRY_TO_TIMESTAMP(ETL_INSERT_DATE::string)) as CONSENT_START_DATE,
        cast(null as timestamp_ntz)                                   as CONSENT_END_DATE,
        SOURCE                                                        as CONSUMER_GROUP,
        EXTERNAL_LEAD_ID::varchar                                     as SOURCE_IDENTIFIER,
        3                                                             as SOURCE_SYSTEM_ID,
        TRY_TO_TIMESTAMP(ETL_INSERT_DATE::string)                     as ETL_TIMESTAMP
    from ext_src
    where (PHONE_OPT_IN is null or trim(PHONE_OPT_IN) = '' or UPPER(TRIM(PHONE_OPT_IN)) in ('Y', 'N', 'TRUE', 'FALSE'))
      and COALESCE(CELL_PHONE, WORK_PHONE, HOME_PHONE) is not null
      and trim(COALESCE(CELL_PHONE, WORK_PHONE, HOME_PHONE)) != ''
),
ext_email as (
    select
        EMAIL                                                        as OBJECT_KEY,
        'EMAIL'                                                      as CHANNEL,
        'MARKETING'                                                  as COMMUNICATION_TYPE,
        case when UPPER(TRIM(EMAIL_OPT_IN)) in ('Y', 'TRUE') then 'OPT-IN'
             when UPPER(TRIM(EMAIL_OPT_IN)) in ('N', 'FALSE') then 'OPT-OUT'
             else 'OPT-IN' end                                       as DECISION,
        COALESCE(TRY_TO_TIMESTAMP(SOURCE_TIMESTAMP::string), TRY_TO_TIMESTAMP(ETL_INSERT_DATE::string)) as CONSENT_START_DATE,
        cast(null as timestamp_ntz)                                  as CONSENT_END_DATE,
        SOURCE                                                       as CONSUMER_GROUP,
        EXTERNAL_LEAD_ID::varchar                                    as SOURCE_IDENTIFIER,
        3                                                            as SOURCE_SYSTEM_ID,
        TRY_TO_TIMESTAMP(ETL_INSERT_DATE::string)                    as ETL_TIMESTAMP
    from ext_src
    where (EMAIL_OPT_IN is null or trim(EMAIL_OPT_IN) = '' or UPPER(TRIM(EMAIL_OPT_IN)) in ('Y', 'N', 'TRUE', 'FALSE'))
      and EMAIL is not null and trim(EMAIL) != ''
),
ext_sms as (
    select
        REGEXP_REPLACE(COALESCE(CELL_PHONE, HOME_PHONE, WORK_PHONE), '[^0-9]', '') as OBJECT_KEY,
        'SMS'                                                        as CHANNEL,
        'MARKETING'                                                  as COMMUNICATION_TYPE,
        case when UPPER(TRIM(SMS_OPT_IN)) in ('Y', 'TRUE') then 'OPT-IN'
             when UPPER(TRIM(SMS_OPT_IN)) in ('N', 'FALSE') then 'OPT-OUT'
             else 'OPT-OUT' end                                      as DECISION,
        COALESCE(TRY_TO_TIMESTAMP(SOURCE_TIMESTAMP::string), TRY_TO_TIMESTAMP(ETL_INSERT_DATE::string)) as CONSENT_START_DATE,
        cast(null as timestamp_ntz)                                  as CONSENT_END_DATE,
        SOURCE                                                       as CONSUMER_GROUP,
        EXTERNAL_LEAD_ID::varchar                                    as SOURCE_IDENTIFIER,
        3                                                            as SOURCE_SYSTEM_ID,
        TRY_TO_TIMESTAMP(ETL_INSERT_DATE::string)                    as ETL_TIMESTAMP
    from ext_src
    where (SMS_OPT_IN is null or trim(SMS_OPT_IN) = '' or UPPER(TRIM(SMS_OPT_IN)) in ('Y', 'N', 'TRUE', 'FALSE'))
      and CELL_PHONE is not null and trim(CELL_PHONE) != ''
),
{% endif %}

{% if have_ff %}
-- Source 5: FF Hello Profiles (Brand Movers)
ff_src as (
    select E_MAIL, H_PHONE, A_PHONE, PHONE_OPT_IN, EMAIL_OPT_IN, MARKETING_OPT_IN, LOAD_DATE, PROFILE_ID, SSK
    from {{ source('marketing_ownermart', 'ff_hello_profiles') }}
    where LOAD_DATE is not null and TRY_TO_TIMESTAMP(LOAD_DATE::string) is not null
    {{ cp_incremental_filter(5, "TRY_TO_TIMESTAMP(LOAD_DATE::string)") }}
    {% if have_ff_tap %}
    union all
    select E_MAIL, H_PHONE, A_PHONE, PHONE_OPT_IN, cast(null as varchar) as EMAIL_OPT_IN, cast(null as varchar) as MARKETING_OPT_IN, LOAD_DATE, PROFILE_ID, SSK
    from {{ source('marketing_ownermart', 'ff_hello_profiles_tap') }}
    where LOAD_DATE is not null and TRY_TO_TIMESTAMP(LOAD_DATE::string) is not null
    {{ cp_incremental_filter(5, "TRY_TO_TIMESTAMP(LOAD_DATE::string)") }}
    {% endif %}
),
ff_seg as (
    select
        ff.*,
        {% if have_segment %}seg.SEGMENT_DESCRIPTION{% else %}cast(null as varchar) as SEGMENT_DESCRIPTION{% endif %}
    from ff_src ff
    {% if have_segment %}
    left join {{ source('wd_dg', 'cm_segment') }} seg on ff.SSK = CONCAT(seg.SOURCE_ID, seg.SEGMENT_ID)
    {% endif %}
),
ff_email as (
    select
        E_MAIL                                              as OBJECT_KEY,
        'EMAIL'                                             as CHANNEL,
        'MARKETING'                                         as COMMUNICATION_TYPE,
        case when UPPER(TRIM(EMAIL_OPT_IN)) in ('Y', 'TRUE') then 'OPT-IN'
             when UPPER(TRIM(EMAIL_OPT_IN)) in ('N', 'FALSE') then 'OPT-OUT'
             else 'OPT-IN' end                             as DECISION,
        TRY_TO_TIMESTAMP(LOAD_DATE::string)                as CONSENT_START_DATE,
        cast(null as timestamp_ntz)                        as CONSENT_END_DATE,
        COALESCE(SEGMENT_DESCRIPTION, 'HELLO_PROFILES')    as CONSUMER_GROUP,
        PROFILE_ID::varchar                                as SOURCE_IDENTIFIER,
        5                                                  as SOURCE_SYSTEM_ID,
        TRY_TO_TIMESTAMP(LOAD_DATE::string)                as ETL_TIMESTAMP
    from ff_seg
    where (EMAIL_OPT_IN is null or trim(EMAIL_OPT_IN) = '' or UPPER(TRIM(EMAIL_OPT_IN)) in ('Y', 'N', 'TRUE', 'FALSE'))
      and E_MAIL is not null and trim(E_MAIL) != ''
),
ff_phone as (
    select
        REGEXP_REPLACE(COALESCE(H_PHONE, A_PHONE), '[^0-9]', '') as OBJECT_KEY,
        'PHONE'                                            as CHANNEL,
        'MARKETING'                                        as COMMUNICATION_TYPE,
        case when UPPER(TRIM(PHONE_OPT_IN)) in ('Y', 'TRUE') then 'OPT-IN'
             when UPPER(TRIM(PHONE_OPT_IN)) in ('N', 'FALSE') then 'OPT-OUT'
             else 'OPT-OUT' end                            as DECISION,
        TRY_TO_TIMESTAMP(LOAD_DATE::string)                as CONSENT_START_DATE,
        cast(null as timestamp_ntz)                        as CONSENT_END_DATE,
        COALESCE(SEGMENT_DESCRIPTION, 'HELLO_PROFILES')    as CONSUMER_GROUP,
        PROFILE_ID::varchar                                as SOURCE_IDENTIFIER,
        5                                                  as SOURCE_SYSTEM_ID,
        TRY_TO_TIMESTAMP(LOAD_DATE::string)                as ETL_TIMESTAMP
    from ff_seg
    where (PHONE_OPT_IN is null or trim(PHONE_OPT_IN) = '' or UPPER(TRIM(PHONE_OPT_IN)) in ('Y', 'N', 'TRUE', 'FALSE'))
      and COALESCE(H_PHONE, A_PHONE) is not null and trim(COALESCE(H_PHONE, A_PHONE)) != ''
),
ff_sms as (
    select
        REGEXP_REPLACE(COALESCE(H_PHONE, A_PHONE), '[^0-9]', '') as OBJECT_KEY,
        'SMS'                                              as CHANNEL,
        'MARKETING'                                        as COMMUNICATION_TYPE,
        case when UPPER(TRIM(MARKETING_OPT_IN)) in ('Y', 'TRUE') then 'OPT-IN'
             when UPPER(TRIM(MARKETING_OPT_IN)) in ('N', 'FALSE') then 'OPT-OUT'
             else 'OPT-OUT' end                            as DECISION,
        TRY_TO_TIMESTAMP(LOAD_DATE::string)                as CONSENT_START_DATE,
        cast(null as timestamp_ntz)                        as CONSENT_END_DATE,
        COALESCE(SEGMENT_DESCRIPTION, 'HELLO_PROFILES')    as CONSUMER_GROUP,
        PROFILE_ID::varchar                                as SOURCE_IDENTIFIER,
        5                                                  as SOURCE_SYSTEM_ID,
        TRY_TO_TIMESTAMP(LOAD_DATE::string)                as ETL_TIMESTAMP
    from ff_seg
    where (MARKETING_OPT_IN is null or trim(MARKETING_OPT_IN) = '' or UPPER(TRIM(MARKETING_OPT_IN)) in ('Y', 'N', 'TRUE', 'FALSE'))
      and COALESCE(H_PHONE, A_PHONE) is not null and trim(COALESCE(H_PHONE, A_PHONE)) != ''
),
{% endif %}

{% if have_ofsll_address %}
-- Source 6: OFSLL Address
ofsll_addr_src as (
    select *
    from {{ source('ofsll_lz', 'address') }}
    where LAST_UPDATE_DATE is not null and TRY_TO_TIMESTAMP(LAST_UPDATE_DATE::string) is not null
      and ADR_PHONE is not null and trim(ADR_PHONE) != ''
    {{ cp_incremental_filter(6, "TRY_TO_TIMESTAMP(LAST_UPDATE_DATE::string)") }}
),
ofsll_addr_phone as (
    select
        REGEXP_REPLACE(REGEXP_REPLACE(ADR_PHONE::string, '[.]0*$', ''), '[^0-9]', '')            as OBJECT_KEY,
        'PHONE'                                            as CHANNEL,
        'TRANSACTIONAL'                                    as COMMUNICATION_TYPE,
        case when UPPER(TRIM(ADR_PERMISSION_TO_CALL_IND)) = 'Y' then 'OPT-IN'
             when UPPER(TRIM(ADR_PERMISSION_TO_CALL_IND)) = 'N' then 'OPT-OUT'
             else 'OPT-OUT' end                            as DECISION,
        TRY_TO_TIMESTAMP(LAST_UPDATE_DATE::string)         as CONSENT_START_DATE,
        cast(null as timestamp_ntz)                        as CONSENT_END_DATE,
        'OFSLL ADDRESS'                                    as CONSUMER_GROUP,
        ADR_ID::varchar                                    as SOURCE_IDENTIFIER,
        6                                                  as SOURCE_SYSTEM_ID,
        TRY_TO_TIMESTAMP(LAST_UPDATE_DATE::string)         as ETL_TIMESTAMP
    from ofsll_addr_src
    where (ADR_PERMISSION_TO_CALL_IND is null or trim(ADR_PERMISSION_TO_CALL_IND) = '' or UPPER(TRIM(ADR_PERMISSION_TO_CALL_IND)) in ('Y', 'N'))
),
ofsll_addr_sms as (
    select
        REGEXP_REPLACE(REGEXP_REPLACE(ADR_PHONE::string, '[.]0*$', ''), '[^0-9]', '')            as OBJECT_KEY,
        'SMS'                                              as CHANNEL,
        'TRANSACTIONAL'                                    as COMMUNICATION_TYPE,
        case when UPPER(TRIM(ADR_PERMISSION_TO_TEXT_IND)) = 'Y' then 'OPT-IN'
             when UPPER(TRIM(ADR_PERMISSION_TO_TEXT_IND)) = 'N' then 'OPT-OUT'
             else 'OPT-OUT' end                            as DECISION,
        TRY_TO_TIMESTAMP(LAST_UPDATE_DATE::string)         as CONSENT_START_DATE,
        cast(null as timestamp_ntz)                        as CONSENT_END_DATE,
        'OFSLL ADDRESS'                                    as CONSUMER_GROUP,
        ADR_ID::varchar                                    as SOURCE_IDENTIFIER,
        6                                                  as SOURCE_SYSTEM_ID,
        TRY_TO_TIMESTAMP(LAST_UPDATE_DATE::string)         as ETL_TIMESTAMP
    from ofsll_addr_src
    where (ADR_PERMISSION_TO_TEXT_IND is null or trim(ADR_PERMISSION_TO_TEXT_IND) = '' or UPPER(TRIM(ADR_PERMISSION_TO_TEXT_IND)) in ('Y', 'N'))
),
{% endif %}

{% if have_ofsll_telecoms %}
-- Source 6: OFSLL Telecoms
ofsll_tel_src as (
    select *
    from {{ source('ofsll_lz', 'telecoms') }}
    where LAST_UPDATE_DATE is not null and TRY_TO_TIMESTAMP(LAST_UPDATE_DATE::string) is not null
      and TEL_PHONE is not null and trim(TEL_PHONE) != ''
    {{ cp_incremental_filter(6, "TRY_TO_TIMESTAMP(LAST_UPDATE_DATE::string)") }}
),
ofsll_tel_phone as (
    select
        REGEXP_REPLACE(REGEXP_REPLACE(TEL_PHONE::string, '[.]0*$', ''), '[^0-9]', '')            as OBJECT_KEY,
        'PHONE'                                            as CHANNEL,
        'TRANSACTIONAL'                                    as COMMUNICATION_TYPE,
        case when UPPER(TRIM(TEL_PERMISSION_TO_CALL_IND)) = 'Y' then 'OPT-IN'
             when UPPER(TRIM(TEL_PERMISSION_TO_CALL_IND)) = 'N' then 'OPT-OUT'
             else 'OPT-OUT' end                            as DECISION,
        TRY_TO_TIMESTAMP(LAST_UPDATE_DATE::string)         as CONSENT_START_DATE,
        cast(null as timestamp_ntz)                        as CONSENT_END_DATE,
        'OFSLL TELECOMS'                                   as CONSUMER_GROUP,
        TEL_ID::varchar                                    as SOURCE_IDENTIFIER,
        6                                                  as SOURCE_SYSTEM_ID,
        TRY_TO_TIMESTAMP(LAST_UPDATE_DATE::string)         as ETL_TIMESTAMP
    from ofsll_tel_src
    where (TEL_PERMISSION_TO_CALL_IND is null or trim(TEL_PERMISSION_TO_CALL_IND) = '' or UPPER(TRIM(TEL_PERMISSION_TO_CALL_IND)) in ('Y', 'N'))
),
ofsll_tel_sms as (
    select
        REGEXP_REPLACE(REGEXP_REPLACE(TEL_PHONE::string, '[.]0*$', ''), '[^0-9]', '')            as OBJECT_KEY,
        'SMS'                                              as CHANNEL,
        'TRANSACTIONAL'                                    as COMMUNICATION_TYPE,
        case when UPPER(TRIM(TEL_PERMISSION_TO_TEXT_IND)) = 'Y' then 'OPT-IN'
             when UPPER(TRIM(TEL_PERMISSION_TO_TEXT_IND)) = 'N' then 'OPT-OUT'
             else 'OPT-OUT' end                            as DECISION,
        TRY_TO_TIMESTAMP(LAST_UPDATE_DATE::string)         as CONSENT_START_DATE,
        cast(null as timestamp_ntz)                        as CONSENT_END_DATE,
        'OFSLL TELECOMS'                                   as CONSUMER_GROUP,
        TEL_ID::varchar                                    as SOURCE_IDENTIFIER,
        6                                                  as SOURCE_SYSTEM_ID,
        TRY_TO_TIMESTAMP(LAST_UPDATE_DATE::string)         as ETL_TIMESTAMP
    from ofsll_tel_src
    where (TEL_PERMISSION_TO_TEXT_IND is null or trim(TEL_PERMISSION_TO_TEXT_IND) = '' or UPPER(TRIM(TEL_PERMISSION_TO_TEXT_IND)) in ('Y', 'N'))
),
{% endif %}

{% if have_sfmc %}
-- Source 7: SFMC SMS tracking (STOP opt-outs)
sfmc_stops as (
    select distinct REGEXP_REPLACE(MOBILE, '[^0-9]+', '') as cleaned_mobile
    from {{ source('marketing_response', 'sms_messagetracking_combined') }}
    where MODIFIEDDATETIME is not null and TRY_TO_TIMESTAMP(MODIFIEDDATETIME::string) is not null
      and UPPER(TRIM(SHAREDKEYWORD)) = 'STOP' and OUTBOUND = TRUE
      and MOBILE is not null and trim(MOBILE) != ''
    {{ cp_incremental_filter(7, "TRY_TO_TIMESTAMP(MODIFIEDDATETIME::string)") }}
),
sfmc_history as (
    select sms.*
    from {{ source('marketing_response', 'sms_messagetracking_combined') }} sms
    inner join sfmc_stops p on REGEXP_REPLACE(sms.MOBILE, '[^0-9]+', '') = p.cleaned_mobile
    where sms.MODIFIEDDATETIME is not null and TRY_TO_TIMESTAMP(sms.MODIFIEDDATETIME::string) is not null
      and sms.MOBILE is not null and trim(sms.MOBILE) != ''
),
sfmc_lag as (
    select *,
        LAG(SHAREDKEYWORD) over (
            partition by REGEXP_REPLACE(MOBILE, '[^0-9]+', '')
            order by TRY_TO_TIMESTAMP(MODIFIEDDATETIME::string) asc
        ) as prev_shared_keyword
    from sfmc_history
),
sfmc_norm as (
    select
        REGEXP_REPLACE(MOBILE, '[^0-9]+', '')              as OBJECT_KEY,
        'PHONE'                                            as CHANNEL,
        case when SHORTCODE = '59595' then 'MARKETING'
             when SHORTCODE = '59637' then 'TRANSACTIONAL'
             else 'MARKETING' end                          as COMMUNICATION_TYPE,
        'OPT-OUT'                                          as DECISION,
        TRY_TO_TIMESTAMP(ACTIONDATETIME::string)           as CONSENT_START_DATE,
        cast(null as timestamp_ntz)                        as CONSENT_END_DATE,
        case when SHORTCODE = '59595' then prev_shared_keyword
             when SHORTCODE = '59637' then 'OFSLL'
             else 'UNKNOWN SHORTCODE' end                  as CONSUMER_GROUP,
        SUBSCRIBERID::varchar                              as SOURCE_IDENTIFIER,
        7                                                  as SOURCE_SYSTEM_ID,
        TRY_TO_TIMESTAMP(MODIFIEDDATETIME::string)         as ETL_TIMESTAMP
    from sfmc_lag
    where REGEXP_REPLACE(MOBILE, '[^0-9]+', '') != ''
),
{% endif %}

-- Always-present CTE so the WITH clause stays valid no matter which sources ran
_guard as (select 1 as x)

{%- set branches = [] -%}
{%- if have_dnc -%}
    {%- do branches.append("select * from dnc_norm where OBJECT_KEY is not null and OBJECT_KEY != ''") -%}
{%- endif -%}
{%- if have_ccpa -%}
    {%- do branches.append("select * from ccpa_email where OBJECT_KEY is not null and OBJECT_KEY != ''") -%}
    {%- do branches.append("select * from ccpa_phone where OBJECT_KEY is not null and OBJECT_KEY != ''") -%}
{%- endif -%}
{%- if have_journey -%}
    {%- do branches.append("select * from journey_sms_main where OBJECT_KEY is not null and OBJECT_KEY != '' and CONSENT_START_DATE is not null") -%}
    {%- do branches.append("select * from journey_phone_main where OBJECT_KEY is not null and OBJECT_KEY != '' and CONSENT_START_DATE is not null") -%}
    {%- do branches.append("select * from journey_offer_sms where OBJECT_KEY is not null and OBJECT_KEY != '' and CONSENT_START_DATE is not null") -%}
{%- endif -%}
{%- if have_external -%}
    {%- do branches.append("select * from ext_phone where OBJECT_KEY is not null and OBJECT_KEY != ''") -%}
    {%- do branches.append("select * from ext_email where OBJECT_KEY is not null and OBJECT_KEY != ''") -%}
    {%- do branches.append("select * from ext_sms where OBJECT_KEY is not null and OBJECT_KEY != ''") -%}
{%- endif -%}
{%- if have_ff -%}
    {%- do branches.append("select * from ff_email where OBJECT_KEY is not null and OBJECT_KEY != ''") -%}
    {%- do branches.append("select * from ff_phone where OBJECT_KEY is not null and OBJECT_KEY != ''") -%}
    {%- do branches.append("select * from ff_sms where OBJECT_KEY is not null and OBJECT_KEY != ''") -%}
{%- endif -%}
{%- if have_ofsll_address -%}
    {%- do branches.append("select * from ofsll_addr_phone where OBJECT_KEY is not null and OBJECT_KEY != ''") -%}
    {%- do branches.append("select * from ofsll_addr_sms where OBJECT_KEY is not null and OBJECT_KEY != ''") -%}
{%- endif -%}
{%- if have_ofsll_telecoms -%}
    {%- do branches.append("select * from ofsll_tel_phone where OBJECT_KEY is not null and OBJECT_KEY != ''") -%}
    {%- do branches.append("select * from ofsll_tel_sms where OBJECT_KEY is not null and OBJECT_KEY != ''") -%}
{%- endif -%}
{%- if have_sfmc -%}
    {%- do branches.append("select * from sfmc_norm where OBJECT_KEY is not null and OBJECT_KEY != ''") -%}
{%- endif -%}

{% if branches | length > 0 %}
{{ branches | join('\nunion all\n') }}
{% else %}
-- No sources available this run: return an empty set with the right shape
select
    cast(null as varchar)       as OBJECT_KEY,
    cast(null as varchar)       as CHANNEL,
    cast(null as varchar)       as COMMUNICATION_TYPE,
    cast(null as varchar)       as DECISION,
    cast(null as timestamp_ntz) as CONSENT_START_DATE,
    cast(null as timestamp_ntz) as CONSENT_END_DATE,
    cast(null as varchar)       as CONSUMER_GROUP,
    cast(null as varchar)       as SOURCE_IDENTIFIER,
    cast(null as number)        as SOURCE_SYSTEM_ID,
    cast(null as timestamp_ntz) as ETL_TIMESTAMP
where false
{% endif %}
