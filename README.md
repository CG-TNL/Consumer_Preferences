# Consumer Preferences dbt POC

A dbt reimplementation of `SP_CONSUMER_PREFERENCES_LOAD_DAILY`. All sources feed
one staging model and one snapshot, so the schema stays small as sources grow.
History works the same as the old ACTIVE flag, but the snapshot does it natively.

## Flow

    raw sources  ->  stg_consumer_prefs (one incremental staging table)
                          |
                     snap_consumer_prefs (one SCD2 snapshot)
                          |
                     consumer_preferences_dbt (target table, ACTIVE flag)
                          |
                     vw_consumer_preferences_dbt (clean serving view)

- One staging model unions every source. Each source keeps its own incremental
  watermark by filtering on its own SOURCE_SYSTEM_ID max ETL_TIMESTAMP.
- The snapshot records a change as a new version and keeps the old one.
  Current version = `dbt_valid_to is null`. This equals the old `ACTIVE = TRUE`.
- Identical rows create no new version. This is the old identical-row skip.
- consumer_preferences_dbt reads the snapshot and maps validity to ACTIVE. It is
  the raw layer: it holds all data, including invalid keys and null decisions.
- vw_consumer_preferences_dbt is the clean layer. It keeps only valid phone and
  email keys, defaults null or empty decisions by channel (email opt-in,
  phone/sms opt-out), and derives consent end dates.

Resilience: if a source's table is missing this run, that source is skipped with
a warning and the others still load (see the have_ checks in stg_consumer_prefs).
A subtler structural break, like a renamed column, still fails the shared staging
model. For full per-source isolation you would split staging into per-source
models. That is the trade-off for keeping the footprint small.

Change management and DEV-to-PRD promotion gated on tests: see GITHUB.md.
Presenting this? See DEMO_WALKTHROUGH.md.

## What is built

All seven sources are wired end to end inside the single staging model:

- Source 1 (CCPA): one source row splits into an email row and a phone row.
- Source 2 (DNC): single channel, the simplest pattern.
- Source 3 (External Leads): email, phone, and sms branches from opt-in flags.
- Source 4 (Journey): two proc blocks folded in, with the quote and tour-record
  joins for the Offer Transaction rows.
- Source 5 (FF Hello Profiles): main and TAP feeds unioned, with the CM_SEGMENT
  join for the consumer group; email, phone, and sms branches.
- Source 6 (OFSLL): Address and Telecoms tables, phone and sms per table, from
  the call and text permission flags; transactional.
- Source 7 (SFMC): STOP opt-outs, with the previous shared keyword carried in as
  the consumer group.

## Add a source

1. `models/sources/_sources.yml`: register the table with a freshness block.
2. `models/staging/stg_consumer_prefs.sql`: add the source's src + normalized
   CTEs (output the 10 columns, include the per-source watermark filter), then
   add it to the final union.
3. `seeds/consumer_preference_sources_dbt.csv`: add a registry row.

The snapshot, target table, and views do not change. The contract on the
staging model stops the build if a new source does not output the 10 columns.

## Health and reporting

- `CONSUMER_PREFERENCES_PIPELINE_RUN_LOG_DBT` gets one row per model, snapshot, test, and source each run:
  status, rows, run seconds, message. Query it to see what ran and what failed.
- Test results (pass/warn/fail + counts) are consolidated in the run log, one
  table for all tests. Per-test failure tables are off to keep the schema clean;
  turn `store_failures` on, or add Elementary, if you want failing rows persisted.
- `dbt source freshness` reports how stale each source is.
- The email report reuses `FN_SEND_EMAIL` and the notification-id-14 recipients.

## Health checks in place

On the raw table (structural only, bad data is allowed here):
- Shape: not_null on keys, accepted_values on CHANNEL and COMMUNICATION_TYPE.
- Referential: SOURCE_SYSTEM_ID must exist in the source registry.
- One active per key: exactly one ACTIVE row per business key (error).
- Active source coverage: each active source has rows in the table (warn).
- Consumer group present: active rows should carry a CONSUMER_GROUP (warn).

On the clean view (strict, the view must be correct):
- DECISION not null and in (OPT-IN, OPT-OUT), after channel defaulting.
- Valid contact key: phone/SMS 10 to 11 digits, email well formed (error).
- Consent end date always set: NULLs become 9999-12-31 (error).
- End after start: CONSENT_END_DATE not before CONSENT_START_DATE (warn).
- No unexpected duplication per object_key, channel, source, start date (warn).

Later, with a package such as Elementary: row-count anomalies, run-duration
regression, and freshness anomalies.

## Run

    dbt deps            # only if you add packages later
    dbt seed            # loads the source registry
    dbt build           # staging, snapshots, marts, and tests in DAG order
    dbt source freshness

## Reloading data

Normal runs pull each source from its own max ETL_TIMESTAMP. To reload from a
fixed point instead, pass vars. Merge upserts the re-pulled rows.

    -- one source from a date
    build --vars '{reload_from: "2026-01-01", reload_source: 1}'

    -- several sources from a date
    build --vars '{reload_from: "2026-01-01", reload_source: [1, 4]}'

    -- all sources from a date
    build --vars '{reload_from: "2026-01-01"}'

    -- per-source dates in one run (reload only the ids listed)
    build --vars '{reload_from: {1: "2026-01-01", 5: "2025-06-01"}}'

    -- everything, ignore the watermark entirely
    build --full-refresh

## Running sources at different cadences

Normal `build` processes every present source incrementally. To run only some
sources on a given job, pass run_sources. Sources left out keep their existing
rows untouched. This is how AutoSys runs heavy sources (DNC, OFSLL) daily and
light ones more often, without ever running the project twice at once.

    -- only the light, frequent sources (hourly job)
    build --vars '{run_sources: [3, 4, 7]}'

    -- only the heavy sources (daily job)
    build --vars '{run_sources: [2, 6]}'

    -- one source
    build --vars '{run_sources: 5}'

run_sources (which sources run) and reload_from (from what date) combine:

    build --vars '{run_sources: [2], reload_from: {2: "2026-01-01"}}'

A reload only changes the snapshot if a checked column changed
(DECISION, CONSENT_START_DATE, CONSENT_END_DATE, CONSUMER_GROUP). To force a
non-checked change (like a SOURCE_IDENTIFIER swap) through, delete that source's
rows from SNAP_CONSUMER_PREFS and STG_CONSUMER_PREFS, then build.

## Scheduling with AutoSys (snowsql)

AutoSys triggers each run with a snowsql call that executes the project. The
project stays one object; AutoSys decides when and with which sources. Because
Snowflake will not run the same dbt project object twice at once, stagger the
jobs so they do not overlap.

Daily job for the heavy sources (full incremental):

    snowsql -a <account> -u <user> -r <role> -w DEV_TNL_BUS_EDA_WH \
      -q "EXECUTE DBT PROJECT DEV_WD_USR_WRKSPC_DB.WD_EDA.CONSUMER_PREFERENCES ARGS='build --vars {run_sources: [2, 6]}';"

Hourly job for the light sources only:

    snowsql -a <account> -u <user> -r <role> -w DEV_TNL_BUS_EDA_WH \
      -q "EXECUTE DBT PROJECT DEV_WD_USR_WRKSPC_DB.WD_EDA.CONSUMER_PREFERENCES ARGS='build --vars {run_sources: [3, 4, 7]}';"

Everything at a set time (no source filter):

    snowsql -a <account> -u <user> -r <role> -w DEV_TNL_BUS_EDA_WH \
      -q "EXECUTE DBT PROJECT DEV_WD_USR_WRKSPC_DB.WD_EDA.CONSUMER_PREFERENCES ARGS='build';"

Backfill one source from a date, on demand:

    snowsql -a <account> -u <user> -r <role> -w DEV_TNL_BUS_EDA_WH \
      -q "EXECUTE DBT PROJECT DEV_WD_USR_WRKSPC_DB.WD_EDA.CONSUMER_PREFERENCES ARGS='build --vars {run_sources: [1], reload_from: {1: \"2026-01-01\"}}';"

Notes:
- Each snowsql call returns non-zero if the build has any failure, so the AutoSys
  job fails and downstream jobs hold. The scheduler gets a clean success or failure.
- Keep the schedules non-overlapping. If two must be close, chain them in AutoSys
  (one starts after the other completes) rather than running both at once.
- A native Snowflake task is the alternative trigger if you ever want it in-DB:
  CREATE TASK ... AS EXECUTE DBT PROJECT ... ARGS='build';

## Scheduling with AutoSys ($$SNF_PRC_CALL)

AutoSys triggers through the standard proc-call wrapper: EXECUTE DBT PROJECT is
wrapped in a caller's-rights procedure and AutoSys calls that. A failed build
makes EXECUTE DBT PROJECT raise, so the proc fails and the job registers the
failure. Setup is a one-time three steps, then AutoSys just calls the proc.

Step 1: deploy the dbt project object. The wrapper calls the project by name,
so a schema-level DBT PROJECT object must exist. Running from a workspace
(EXECUTE DBT PROJECT FROM WORKSPACE ...) does not create it, and that variant
only runs for the workspace owner, so it can not be used for AutoSys. In the
Snowsight workspace, open the project, then Connect -> Deploy dbt project:

- Name: CONSUMER_PREFERENCES
- Database: DEV_WD_USR_WRKSPC_DB
- Schema: WD_EDA
- Default target: dev

Confirm it exists:

    SHOW DBT PROJECTS IN SCHEMA DEV_WD_USR_WRKSPC_DB.WD_EDA;

Once the Git integration is live, recreate it from the repo instead, so deploys
are reproducible:

    CREATE OR REPLACE DBT PROJECT DEV_WD_USR_WRKSPC_DB.WD_EDA.CONSUMER_PREFERENCES
        FROM '@DEV_WD_USR_WRKSPC_DB.WD_EDA.CONSUMER_PREFS_REPO/branches/main/consumer_preferences_dbt'
        DEFAULT_TARGET = 'dev';

Step 2: create the wrapper procs. Run scheduling/autosys_wrapper_procs.sql once
(paste into a worksheet, or run from the synced repo):

    EXECUTE IMMEDIATE FROM @DEV_WD_USR_WRKSPC_DB.WD_EDA.CONSUMER_PREFS_REPO/branches/main/consumer_preferences_dbt/scheduling/autosys_wrapper_procs.sql;

This creates SP_CONSUMER_PREFS_DBT_FULL (all sources), _DAILY (run_sources
[2, 6]), and _HOURLY (run_sources [3, 4, 7]). Test one:

    CALL DEV_WD_USR_WRKSPC_DB.WD_EDA.SP_CONSUMER_PREFS_DBT_FULL();

Step 3: the AutoSys command. common_prc_call.sh takes six args:
[connection] [db] [schema] [proc] [priority] [maillist]. Matches the existing
SP_CCPA_PID_RETRIEVAL job:

    $$SNF_PRC_CALL $$SNF_AUTOSYS_WH <workspace_db> WD_EDA "SP_CONSUMER_PREFS_DBT_FULL()"   3 $$SQL_MAILLIST_DIR/eda
    $$SNF_PRC_CALL $$SNF_AUTOSYS_WH <workspace_db> WD_EDA "SP_CONSUMER_PREFS_DBT_DAILY()"  3 $$SQL_MAILLIST_DIR/eda
    $$SNF_PRC_CALL $$SNF_AUTOSYS_WH <workspace_db> WD_EDA "SP_CONSUMER_PREFS_DBT_HOURLY()" 3 $$SQL_MAILLIST_DIR/eda

Arg notes:
- $$SNF_AUTOSYS_WH is the snowsql connection (-c), not a warehouse. The build
  itself uses the warehouse in the profile target (DEV_TNL_BUS_EDA_WH).
- <workspace_db> and WD_EDA set the snowsql session db and schema (-d, -s). The
  proc is called unqualified, so these must be DEV_WD_USR_WRKSPC_DB and WD_EDA.
  Use the DB variable if one exists, else the literal DEV_WD_USR_WRKSPC_DB.
- Use FULL for one job that runs everything; use DAILY plus HOURLY only if you
  split heavy and light sources across cadences. Keep cadences non-overlapping,
  since the project can not run twice at once.

Failure handling: common_prc_call.sh runs snowsql with exit_on_error=true. A
failed build makes EXECUTE DBT PROJECT raise, the CALL fails, snowsql exits
non-zero, and the script fires common_autojob_notifier.sh, the AutoSys job
fails. The proc does not need to emit a code. If the CALL instead succeeds, the
script reads a custom "XC: <n>" code from the job log if present; our proc emits
none, so a clean run is exit 0.


## Notes

- Build location: everything dbt creates lands in
  `DEV_WD_USR_WRKSPC_DB.WD_EDA`, staging tables, snapshots, both
  views, the seed, and `CONSUMER_PREFERENCES_PIPELINE_RUN_LOG_DBT`. This isolates the project from the
  shared dev spot. Change it in one place: the profile database and schema.
- Sources are separate. They read from `WD_INT_DB` and `WD_LZ_DB`, set in
  `_sources.yml`. The build-location change does not touch them.
- Environments use dbt targets, not `SPLIT_PART`. DEV works now. For PRD, add a
  prod output in `dbt_projects_profiles.yml` and run `--target prod`. No model changes.
- The source registry is a seed, not a driver table. It keeps a LAST_ETL_UPDATE
  column only to feed the view's SOURCE_LAST_UPDATE field; dbt does not use it to
  drive the load. The real last-load time per source lives in CONSUMER_PREFERENCES_PIPELINE_RUN_LOG_DBT.
- The serving view mirrors the live VW_CONSUMER_PREFERENCES_DBT: ACTIVE rows only,
  strict email validation, simple consent end date. It adds the channel-based
  default for null or empty decisions.
