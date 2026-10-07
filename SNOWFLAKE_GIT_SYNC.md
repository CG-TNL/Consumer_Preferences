# Connect GitHub to Snowflake

Goal: make the GitHub repo readable inside Snowflake, so a Snowsight workspace
(or a dbt project object) syncs from Git. Three objects do the connection: a
secret (the token), an API integration (the allow-list), and a Git repository
(the link). Your DBA runs the account-level ones (marked DBA).

Names below use DEV_WD_USR_WRKSPC_DB.WD_EDA. Change if needed.

## 1. Secret with a GitHub token (private repo only)

Use a GitHub personal access token with read access to the repo.

    CREATE OR REPLACE SECRET DEV_WD_USR_WRKSPC_DB.WD_EDA.GITHUB_PAT
        TYPE = password
        USERNAME = '<github_username>'
        PASSWORD = '<github_personal_access_token>';

## 2. API integration (DBA)

Needs CREATE INTEGRATION. Point the prefix at your org or repo.

    CREATE OR REPLACE API INTEGRATION GITHUB_API_EDA
        API_PROVIDER = git_https_api
        API_ALLOWED_PREFIXES = ('https://github.com/<org>')
        ALLOWED_AUTHENTICATION_SECRETS = (DEV_WD_USR_WRKSPC_DB.WD_EDA.GITHUB_PAT)
        ENABLED = TRUE;

For a public repo, drop ALLOWED_AUTHENTICATION_SECRETS and the secret.

## 3. Git repository object (the link)

    CREATE OR REPLACE GIT REPOSITORY DEV_WD_USR_WRKSPC_DB.WD_EDA.CONSUMER_PREFS_REPO
        API_INTEGRATION = GITHUB_API_EDA
        GIT_CREDENTIALS = DEV_WD_USR_WRKSPC_DB.WD_EDA.GITHUB_PAT   -- omit for public repo
        ORIGIN = 'https://github.com/<org>/<repo>.git';

## 4. Fetch and verify

    ALTER GIT REPOSITORY DEV_WD_USR_WRKSPC_DB.WD_EDA.CONSUMER_PREFS_REPO FETCH;

    SHOW GIT BRANCHES IN DEV_WD_USR_WRKSPC_DB.WD_EDA.CONSUMER_PREFS_REPO;
    LS @DEV_WD_USR_WRKSPC_DB.WD_EDA.CONSUMER_PREFS_REPO/branches/main;

The repository object is a stage. Files are at
@...CONSUMER_PREFS_REPO/branches/<branch>/<path>. FETCH pulls the latest commit;
re-run it (or let the workspace pull) to sync new commits.

## 5. Use it, two ways

### A. Snowsight workspace from the repo (the everyday path)
Projects > Workspaces > create from Git repository. Pick API integration
GITHUB_API_EDA, and the secret for a private repo. The repo files load into the
workspace. From there: edit, Pull and Push against the branch, and Deploy dbt
project. This is the sync you asked for.

### B. dbt project object straight from the Git stage (no workspace)
Deploy the project object from the fetched repo, then execute it. project_root
points at the folder that holds dbt_project.yml.

    CREATE OR REPLACE DBT PROJECT DEV_WD_USR_WRKSPC_DB.WD_EDA.CONSUMER_PREFERENCES
        FROM '@DEV_WD_USR_WRKSPC_DB.WD_EDA.CONSUMER_PREFS_REPO/branches/main/consumer_preferences_dbt'
        DEFAULT_TARGET = 'dev';

    EXECUTE DBT PROJECT DEV_WD_USR_WRKSPC_DB.WD_EDA.CONSUMER_PREFERENCES ARGS='build --target dev';

To pick up new commits later: FETCH the repo (step 4), then
ALTER DBT PROJECT ... ADD VERSION FROM the same stage path, or re-run
CREATE OR REPLACE DBT PROJECT.

## Grants the DBA may need

- USAGE on the API integration to your role.
- USAGE on the secret to your role.
- READ on the Git repository to your role (or ownership).
- The role in dbt_projects_profiles.yml (DEV_FRL_TNL_BUS_EDA_DBA) must be able
  to build in DEV_WD_USR_WRKSPC_DB.WD_EDA.

## Note on packages

This project vendors no dbt packages, so `dbt deps` and an external access
integration are not needed. If you add packages later, `dbt deps` needs an
external access integration to reach the package host, that is a separate DBA
setup.
