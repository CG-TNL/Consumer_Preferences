-- Wrapper procedures so AutoSys can trigger the dbt build through $$SNF_PRC_CALL.
-- Each cadence is its own no-arg proc (passing a run_sources list as an arg
-- through the wrapper is awkward).
--
-- Caller's rights (execute as caller) is required to run EXECUTE DBT PROJECT
-- inside a procedure. A failed build makes EXECUTE DBT PROJECT raise, so the
-- proc fails and the AutoSys job registers the failure.

create or replace procedure DEV_WD_USR_WRKSPC_DB.WD_EDA.SP_CONSUMER_PREFS_DBT_DAILY()
returns string
language sql
execute as caller
as
$$
begin
  execute immediate 'execute dbt project DEV_WD_USR_WRKSPC_DB.WD_EDA.CONSUMER_PREFERENCES args=''build --target dev --vars {run_sources: [2, 6]}''';
  return 'consumer_preferences daily build ok';
end;
$$;

create or replace procedure DEV_WD_USR_WRKSPC_DB.WD_EDA.SP_CONSUMER_PREFS_DBT_HOURLY()
returns string
language sql
execute as caller
as
$$
begin
  execute immediate 'execute dbt project DEV_WD_USR_WRKSPC_DB.WD_EDA.CONSUMER_PREFERENCES args=''build --target dev --vars {run_sources: [3, 4, 7]}''';
  return 'consumer_preferences hourly build ok';
end;
$$;

create or replace procedure DEV_WD_USR_WRKSPC_DB.WD_EDA.SP_CONSUMER_PREFS_DBT_FULL()
returns string
language sql
execute as caller
as
$$
begin
  execute immediate 'execute dbt project DEV_WD_USR_WRKSPC_DB.WD_EDA.CONSUMER_PREFERENCES args=''build --target dev''';
  return 'consumer_preferences full build ok';
end;
$$;
