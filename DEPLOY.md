# Deploy to Snowflake using only the web UI (Snowsight)

No CLI needed. You build the project in a Snowsight Workspace, run it, deploy it
as a DBT PROJECT object, then schedule a task.

## Step 0, One-time prerequisites

This project builds into DEV_WD_USR_WRKSPC_DB.WD_EDA, which already exists. You
do not create a schema.

You need, in that schema: the right to create a dbt project object, plus the
usual CREATE TABLE and CREATE VIEW, and read access to the source tables in
WD_INT_DB and WD_LZ_DB. If your account already has full rights under
WD_USR_WRKSPC_DB, you are set. If the dbt project create right is missing, send
this one line to your admin:

    GRANT CREATE DBT PROJECT ON SCHEMA DEV_WD_USR_WRKSPC_DB.WD_EDA TO ROLE <your_role>;

## Step 1, Open Workspaces

Sign in to Snowsight. In the navigation menu, select Projects, then Workspaces.

## Step 2, Get the project files into a workspace

Two ways. Option A (Git) is recommended if you can make a repo.

### Option A, Connect a Git repo (recommended)

This needs an admin once: creating the API integration and secret requires
CREATE INTEGRATION rights. Your GitHub token cannot connect to Snowflake without
that integration object. If you cannot get the admin steps done, use Option B -
the Git connection will not work without them.

You do the GitHub part. An admin does the one-time Snowflake integration.

You, in GitHub (web):
1. Create a private repository (company code, keep it private).
2. Unzip the project bundle and upload its contents so that dbt_project.yml sits
   at the repo root, not inside a subfolder. GitHub's "Add file, Upload files"
   accepts a dragged folder and keeps the paths.
3. Create a fine-grained personal access token scoped to just this repo, with
   Contents read access. Copy it once.

An admin, in a Snowsight worksheet (needs CREATE INTEGRATION rights):
1. Store the token as a secret. Run this in a worksheet, not from a file, and
   never commit the token. Note the token lands in Snowflake query history.

        CREATE OR REPLACE SECRET DEV_WD_USR_WRKSPC_DB.WD_EDA.GIT_PAT
          TYPE = password
          USERNAME = '<your-github-username>'
          PASSWORD = '<your-github-PAT>';

2. Create the API integration that allows that secret.

        CREATE OR REPLACE API INTEGRATION CONSUMER_PREFERENCES_GIT_API
          API_PROVIDER = git_https_api
          API_ALLOWED_PREFIXES = ('https://github.com/<owner>')
          ALLOWED_AUTHENTICATION_SECRETS = (DEV_WD_USR_WRKSPC_DB.WD_EDA.GIT_PAT)
          ENABLED = TRUE;

You, in Snowsight:
1. Projects, then Workspaces. From the Workspaces list, under Create Workspace,
   select From Git repository.
2. Enter the repository HTTPS URL and a workspace name.
3. Select the API integration CONSUMER_PREFERENCES_GIT_API. For a private repo,
   select Personal access token and pick the GIT_PAT secret.
4. Select Create. The files load into the workspace.

### Option B, Paste the files manually (no admin needed)

Create a workspace (My Workspace is fine). In the editor, recreate this exact
folder tree and paste each file's contents:

    dbt_project.yml
    dbt_projects_profiles.yml
    models/sources/_sources.yml
    models/staging/_staging.yml
    models/staging/stg_consumer_prefs.sql
    models/marts/_marts.yml
    models/marts/consumer_preferences_dbt.sql
    models/marts/vw_consumer_preferences_dbt.sql
    models/marts/vw_consumer_preferences_pipeline_health_dbt.sql
    snapshots/snap_consumer_prefs.sql
    seeds/consumer_preference_sources_dbt.csv
    macros/ensure_pipeline_run_log.sql
    macros/log_run_results.sql
    macros/send_email_report.sql
    tests/one_active_per_business_key.sql
    tests/consent_end_after_start.sql
    tests/invalid_contact_keys.sql
    tests/active_source_coverage.sql
    tests/consumer_group_present.sql
    tests/view_duplicate_business_rows.sql


## Step 3, Check the profile

Open dbt_projects_profiles.yml. Set the role and warehouse for the dev target.
Confirm the database is DEV_WD_USR_WRKSPC_DB and the schema is
WD_EDA. Leave account and user blank; the workspace runs as you.

## Step 4, Run it in the workspace

Below the editor, open the Output tab. In the menu bar above the editor, confirm
the correct Project and Profile are selected. From the command list, run in order:

    dbt seed
    dbt build
    dbt source freshness

`dbt build` runs the models, snapshots, and tests together in dependency order.
Read the Output tab. Fix any errors before deploying.

## Step 5, Deploy the project object

From the top right of the workspace, select Connect, then Deploy dbt project.
In the popup:
- Under Select location, choose DEV_WD_USR_WRKSPC_DB and WD_EDA.
- Under Select or Create dbt project, choose Create dbt project.
- Name it CONSUMER_PREFERENCES. Set the default target to dev.

This creates a schema-level DBT PROJECT object. Every later deploy adds a new
version you can roll back to.

## Step 6, Schedule the daily run

In a Snowsight worksheet, create the task in the same database and schema as the
project object. It needs a user-managed warehouse.

    CREATE OR REPLACE TASK DEV_WD_USR_WRKSPC_DB.WD_EDA.TSK_CONSUMER_PREFERENCES_DBT
        WAREHOUSE = 'PRD_TNL_BUS_EDA_WH'
        SCHEDULE = 'USING CRON 0 4 * * * America/New_York'
    AS
        EXECUTE DBT PROJECT DEV_WD_USR_WRKSPC_DB.WD_EDA.CONSUMER_PREFERENCES ARGS='build';

    -- Tasks start suspended. Resume it:
    ALTER TASK DEV_WD_USR_WRKSPC_DB.WD_EDA.TSK_CONSUMER_PREFERENCES_DBT RESUME;

## Step 7, Watch it

- Run history, logs, and lineage: Snowsight shows these for the project object.
- Your own health view: query VW_CONSUMER_PREFERENCES_PIPELINE_HEALTH_DBT in the project schema.
- Per-run detail: query CONSUMER_PREFERENCES_PIPELINE_RUN_LOG_DBT.

## Redeploy after a change

Edit the files in the workspace, run dbt build to check, then Connect, then use
the existing dbt deployment to add a new version. The task picks up the new
version on its next run.
