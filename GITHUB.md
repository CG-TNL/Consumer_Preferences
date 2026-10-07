# Change management with GitHub

This project uses GitHub for change tracking and to gate promotion from DEV to
PRD. Two workflows live in .github/workflows/. Both use the Snowflake CLI to
deploy the dbt project object from Git and run it inside Snowflake, the same way
the project runs in production.

## The flow

1. Work on a branch. Edit models, tests, or sources.
2. Open a pull request into main. dbt_ci.yml runs automatically: it deploys the
   project from the branch into DEV and runs build (models plus tests).
3. The check is green only if there are no failures. Error-severity tests and
   model errors fail the check. Warnings are allowed.
4. A reviewer approves the pull request. Merge into main.
5. dbt_promote_prod.yml runs on the merge. It deploys into PRD and builds, but
   the job waits for a named approver before it touches PRD.

Every change is a pull request: who changed what, why, the review, and the test
result are all recorded. That is the change-management trail.

## The two databases (sandbox)

For the sandbox demo, DEV and PRD are two databases in one account:
- DEV builds into TEST_DB.WD_EDA
- PRD builds into TEST_PRD_DB.WD_EDA

The profile has a dev target and a prod target pointing at those two. For the
real environment, swap the database and role values in dbt_projects_profiles.yml.

## The DEV to PRD approval (GitHub Environment)

The manual approver is a GitHub Environment protection rule, not code.

1. Repo Settings, Environments, New environment, name it production.
2. Under Deployment protection rules, turn on Required reviewers and add the
   approver (or a team). Save.
3. The promote workflow declares environment: production. When it runs on a merge
   to main, the deploy job pauses with "Waiting for review". The named reviewer
   opens the run and clicks Review deployments, then Approve. Only then does the
   PRD deploy run. A reject stops it.

This gives a real, logged sign-off: who approved, when, and the run it belongs to.

## Make the merge gate real: branch protection

Repo Settings, Branches, add a rule for main:
- Require a pull request before merging.
- Require status checks to pass: select the dbt CI / build_and_test check.
- Require a review.

With this on, nothing merges to main unless the PR check is green and a reviewer
approved. So nothing even reaches the PRD workflow until DEV build and tests pass.

## Secrets to set

Repo Settings, Secrets and variables, Actions. Add:

- SNOWFLAKE_ACCOUNT
- SNOWFLAKE_USER
- SNOWFLAKE_PASSWORD        (key-pair auth is better; swap in when ready)
- SNOWFLAKE_ROLE            (role for the DEV deploy)
- SNOWFLAKE_PROD_ROLE       (role for the PRD deploy)
- SNOWFLAKE_WAREHOUSE

No secret is ever committed. The workflows read them at run time.

## Notes

- Both workflows use snow dbt deploy then snow dbt execute. Deploy copies the
  branch files into a project object; execute runs build inside Snowflake.
- The DEV object is TEST_DB.WD_EDA.CONSUMER_PREFERENCES, the PRD object is
  TEST_PRD_DB.WD_EDA.CONSUMER_PREFERENCES. For real use, rename to the real
  databases.
- A time-based soak (a change must run clean in DEV for N days before it can
  promote) is a planned addition, not yet wired. Today the gate is a green PR
  check plus the approver.
