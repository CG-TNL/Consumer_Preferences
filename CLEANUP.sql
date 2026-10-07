-- Reset the Consumer Preferences dbt POC. Drops only this project's objects.
-- Run in a Snowsight worksheet. Safe: uses IF EXISTS and names each object.
-- After this, run dbt build to recreate everything from scratch.

-- Views first (they depend on the tables)
drop view if exists DEV_WD_USR_WRKSPC_DB.WD_EDA.VW_CONSUMER_PREFERENCES_DBT;
drop view if exists DEV_WD_USR_WRKSPC_DB.WD_EDA.VW_CONSUMER_PREFERENCES_PIPELINE_HEALTH_DBT;

-- Target, staging, snapshots, seed, run log
drop table if exists DEV_WD_USR_WRKSPC_DB.WD_EDA.CONSUMER_PREFERENCES_DBT;
drop table if exists DEV_WD_USR_WRKSPC_DB.WD_EDA.STG_CONSUMER_PREFS;
drop table if exists DEV_WD_USR_WRKSPC_DB.WD_EDA.SNAP_CONSUMER_PREFS;
drop table if exists DEV_WD_USR_WRKSPC_DB.WD_EDA.CONSUMER_PREFERENCE_SOURCES_DBT;
drop table if exists DEV_WD_USR_WRKSPC_DB.WD_EDA.CONSUMER_PREFERENCES_PIPELINE_RUN_LOG_DBT;

-- Old per-source objects from the earlier design (drop if they exist)
drop table if exists DEV_WD_USR_WRKSPC_DB.WD_EDA.STG_CONSUMER_PREFS_DNC;
drop table if exists DEV_WD_USR_WRKSPC_DB.WD_EDA.STG_CONSUMER_PREFS_CCPA;
drop table if exists DEV_WD_USR_WRKSPC_DB.WD_EDA.STG_CONSUMER_PREFS_JOURNEY;
drop table if exists DEV_WD_USR_WRKSPC_DB.WD_EDA.SNAP_CONSUMER_PREFS_DNC;
drop table if exists DEV_WD_USR_WRKSPC_DB.WD_EDA.SNAP_CONSUMER_PREFS_CCPA;
drop table if exists DEV_WD_USR_WRKSPC_DB.WD_EDA.SNAP_CONSUMER_PREFS_JOURNEY;

-- Test failure tables (store_failures) have generated names. This SELECT builds
-- the DROP statements for them. Run it, review the output, then run those drops.
select
    'drop ' || iff(table_type = 'VIEW', 'view', 'table') || ' if exists '
    || table_schema || '.' || table_name || ';' as drop_statement
from DEV_WD_USR_WRKSPC_DB.information_schema.tables
where table_schema = 'WD_EDA'
  and (
        table_name ilike '%CONSUMER_PREF%'
        or table_name in (
            'ONE_ACTIVE_PER_BUSINESS_KEY',
            'INVALID_CONTACT_KEYS',
            'CONSENT_END_AFTER_START',
            'ACTIVE_SOURCE_COVERAGE',
            'CONSUMER_GROUP_PRESENT',
            'VIEW_DUPLICATE_BUSINESS_ROWS'
        )
  )
order by 1;
