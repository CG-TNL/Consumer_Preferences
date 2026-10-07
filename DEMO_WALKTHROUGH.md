# Consumer Preferences dbt POC, Demo Walkthrough

A talk track for presenting the pipeline. Each section has what to say and what
to show. Rehearse the live steps once before the real demo.

Environment for the demo: dbt 1.9.4 on dbt Projects on Snowflake, running in
DEV_WD_USR_WRKSPC_DB.WD_EDA. All seven sources are wired: CCPA, DNC, External
Leads, Journey, FF Hello Profiles, OFSLL, and SFMC.

---

## 1. The pitch (30 seconds)

"We rebuilt the Consumer Preferences load as a dbt project. It does everything
the old procedure did, the same target table, the same ACTIVE history, the same
email, but it is modular, tested, self-documenting, and easy to extend. Adding a
source or reloading a date is now a small, safe change instead of editing an
800-line procedure."

---

## 1a. 30-minute agenda

- 0-3   The problem and the pitch (sections 1-2)
- 3-8   Architecture, the two tiers, and the file tour (sections 3, 3a)
- 8-17  Live build and data walkthrough (section 4)
- 17-22 Tests, the failure spectrum, freshness, and health (sections 7, 7a, 8, 8a, 10)
- 22-26 Scheduling and CI/CD promotion (sections 9, 11)
- 26-30 Improvements over the old SQL, then Q&A (sections 12-13)

Rehearse note: kick off the live build early (section 4) and talk over it, the
build takes a few minutes, so use that time for the design narrative.

---

## 2. The problem we started from

Talking points:
- The old load was one large stored procedure. All seven sources, the history
  logic, the dedup, and the email lived in a single file.
- To change one source, you edited the whole procedure and re-tested all of it.
- There were no automated data-quality checks, no freshness checks, and no
  history of what ran or how long it took beyond the summary email.
- The ACTIVE flag was maintained by hand: deactivate, insert, re-activate, per
  source, in procedural steps.

One line: "It worked, but it was one big block that was risky to change and hard
to see into."

---

## 3. Architecture at a glance

Show the flow (draw it or show the README diagram):

    raw sources  ->  stg_consumer_prefs      (one staging table)
                 ->  snap_consumer_prefs      (one SCD2 snapshot = history + ACTIVE)
                 ->  consumer_preferences_dbt  (raw target table)
                 ->  vw_consumer_preferences_dbt (clean serving view)

Say it in plain terms:
- Staging normalizes every source into one shape: 10 columns.
- The snapshot keeps full history and marks the current row, like the ACTIVE flag.
- The target table is the raw layer: it holds everything, even imperfect data.
- The view is the clean layer: valid contacts only, decisions completed.

---

## 3a. File structure, what's in the project

Open the tree and give the tour. *"The layout tells you what each part does."*

    models/
      sources/     _sources.yml          -- the raw inputs we read, plus freshness rules
      staging/     stg_consumer_prefs     -- one model: normalize every source to 10 columns
                   _staging.yml           -- the 10-column contract and its tests
      marts/       consumer_preferences_dbt          -- the target table (raw layer)
                   vw_consumer_preferences_dbt       -- the clean serving view
                   vw_consumer_preferences_pipeline_health_dbt  -- health view
                   _marts.yml             -- tests and docs for the marts
    snapshots/     snap_consumer_prefs    -- SCD2 history and the ACTIVE flag
    seeds/         consumer_preference_sources_dbt.csv  -- the source registry
    macros/        reusable logic (see below)
    tests/         singular data tests (business rules)
    .github/workflows/   CI and promote-to-PRD pipelines
    dbt_project.yml           project config (materializations, hooks, vars)
    dbt_projects_profiles.yml connection settings per environment

What each folder is for, in one line each:
- sources: declares the real tables we read and how fresh they should be.
- staging: the one place raw source shapes become our common shape.
- marts: what people query: the table and the views.
- snapshots: keeps history and marks the live row; this is the ACTIVE logic.
- seeds: small reference data we control, loaded as a table.
- macros: shared building blocks: env prefix, the incremental/reload watermark,
  the run-log writer, the email sender, and the schema helper.
- tests: business-rule checks that live in their own files.
- .github/workflows: the change-management gates.

Say: *"A new engineer can look at this and know where everything lives. Compare
that to one 800-line procedure where it all ran together."*

---

## 4. Live demo (the core of it)

Do these in the Snowsight Workspace, in order. Say the italic line as you click.

1. Show the file tree. *"The whole pipeline is a handful of small files, grouped
   by job: sources, one staging model, one snapshot, the target and views, and
   the tests."*

2. Click Compile. *"This parses the whole project without touching the
   warehouse, it validates every reference, the contract, and the SQL."*

3. Click Build. *"One command runs it end to end in dependency order: load the
   registry, build staging, snapshot, the target table, the views, then run the
   tests."* While it runs, move to the design points in section 5.

4. Show the two tiers side by side in a worksheet:

        -- raw layer: holds everything, per source
        select SOURCE_SYSTEM_ID, count(*) total, count_if(ACTIVE) active_rows
        from WD_EDA.CONSUMER_PREFERENCES_DBT group by 1 order by 1;

        -- clean layer: fewer rows, valid contacts, decisions completed
        select count(*) from WD_EDA.VW_CONSUMER_PREFERENCES_DBT;

   *"The table keeps every record, including invalid phone numbers and odd
   emails. The view is what marketing consumes, it filters to valid contacts
   and fills in missing decisions by channel."*

5. Show pipeline health:

        select * from WD_EDA.VW_CONSUMER_PREFERENCES_PIPELINE_HEALTH_DBT;

   *"One view tells me, per step, whether it ran, when it last succeeded, how
   long it took versus its recent average, and how many rows it wrote."*

6. Show the run log:

        select node_name, status, execution_seconds, rows_affected
        from WD_EDA.CONSUMER_PREFERENCES_PIPELINE_RUN_LOG_DBT
        order by logged_at desc;

   *"Every run writes this automatically. It is our audit trail."*

7. Show a data-quality signal. Point at a WARN in the build output. *"We caught
   3,479 CCPA rows with no source identifier. The old pipeline let those through
   silently. Here it is visible: the count shows in the build output and in the
   run log, but because it is a warning, it does not block the load."*

8. Show a reload. *"If I need to reprocess a source from a point in time, it is
   one command, no editing tables. And it is flexible."*

        -- one source from a date
        build --vars '{reload_from: "2026-01-01", reload_source: 1}'
        -- several sources, same date
        build --vars '{reload_from: "2026-01-01", reload_source: [1, 4]}'
        -- per-source dates in one run
        build --vars '{reload_from: {1: "2026-01-01", 5: "2025-06-01"}}'

   *"Any source not named keeps its normal watermark. The re-pulled rows merge
   in, no duplicates, no full rebuild."*

9. Show how easy a new source is. Open stg_consumer_prefs.sql. *"To add a
   source, I add its normalized block here and a registry row. The 10-column
   contract stops the build if the new source does not fit the shape, so I can't
   break the target by accident."*

10. Show resilience (optional live, or describe). *"If a source's table is
    missing one day, the run skips that source with a warning and still loads the
    rest, one broken feed does not stop the pipeline."* To show it live: point a
    source's table in _sources.yml at a name that does not exist, run build, show
    the skip warning in the output and the other sources still loading, then
    revert.

11. Point at the tests and CI. *"Every build runs about fifty checks. And in
    GitHub, a pull request must pass those checks before it can merge and reach
    production."* Show the run output's PASS/WARN counts, and the GitHub Actions
    check on a PR if it is set up.

---

## 5. Design and logic, the "why" (say while Build runs)

- History without hand-coding. *"A dbt snapshot gives us slowly-changing
  history for free. The current version is the ACTIVE row. Identical records
  create no new version, that is the old identical-row skip, built in."*
- Incremental, per source. *"Each source only reads what changed since its own
  last load. A daily source and an hourly source stay independent."*
- Contract enforcement. *"Every source must output the same 10 columns and
  types. If it doesn't, the build fails before it reaches the target."*
- Two tiers on purpose. *"Raw table for truth, view for use. We never lose data,
  and consumers always get clean data."*
- Decision defaulting. *"If a decision is missing, the view fills it by channel:
  email opt-in, phone and SMS opt-out. The raw table still shows the original."*
- One schema, no sprawl. *"Everything builds into one workspace schema. We even
  keep the test-result tables there, so we never need new schemas."*

---

## 6. Options and variability we built in

Frame this as "the pipeline flexes without code rewrites."

- Incremental everywhere. Staging pulls only changed rows per source. The target
  table replaces only the business keys that changed. Nothing rebuilds fully on a
  normal run.
- Reload from a date: one source, a list of sources, or a per-source date map.
- Full rebuild only when you want it: `--full-refresh`.
- DEV to PRD by target: no model changes, just a second profile target. The
  environment prefix is a variable.
- Freshness thresholds per source, tunable as we learn each cadence.
- Severity per check: warnings surface issues without blocking; errors stop a bad
  load. We chose the level per check deliberately.
- Source-outage resilience: if a source's table is missing this run, the
  pipeline skips it with a warning and loads the others. One broken feed does
  not stop the rest.
- Fewer objects vs full isolation: we chose one staging model and one snapshot
  for a small footprint. The guard covers a missing source; a subtler break like
  a renamed column still fails the shared staging. We name this openly.

---

## 6a. Adding a source, step by step (Source 3 example)

Pick one of the sources still in the old procedure, External Leads, and show
how it would come in. Keep it high level; the point is how little it takes.

*"External Leads has an email, a phone, and a cell, each with a Y/N opt-in flag.
Three channels from one row. Here is everything I touch to add it."*

Step 1, register it in `_sources.yml`, with a freshness rule:

    - name: external_leads
      loaded_at_field: "TRY_TO_TIMESTAMP(ETL_INSERT_DATE::string)"
      freshness:
        warn_after:  {count: 24, period: hour}
        error_after: {count: 48, period: hour}

Step 2, one block in stg_consumer_prefs.sql: the outage check, the normalized
CTEs, and the union branches. Abbreviated:

    {%- set have_external = load_relation(source('marketing_crm', 'external_leads')) is not none -%}
    ...
    {% if have_external %}
    ext_email as (
        select
            EMAIL                             as OBJECT_KEY,
            'EMAIL'                           as CHANNEL,
            'MARKETING'                       as COMMUNICATION_TYPE,
            case when upper(trim(EMAIL_OPT_IN)) in ('Y','TRUE')  then 'OPT-IN'
                 when upper(trim(EMAIL_OPT_IN)) in ('N','FALSE') then 'OPT-OUT'
                 else 'OPT-IN' end            as DECISION,
            TRY_TO_TIMESTAMP(ETL_INSERT_DATE::string) as CONSENT_START_DATE,
            cast(null as timestamp_ntz)       as CONSENT_END_DATE,
            SOURCE                            as CONSUMER_GROUP,
            EXTERNAL_LEAD_ID::varchar         as SOURCE_IDENTIFIER,
            3                                 as SOURCE_SYSTEM_ID,
            TRY_TO_TIMESTAMP(ETL_INSERT_DATE::string) as ETL_TIMESTAMP
        from ext_src
        where EMAIL is not null and trim(EMAIL) != ''
    ),
    -- phone and sms branches follow the same shape
    {% endif %}

Then add its branches to the union list. Step 3, a registry row in the seed
(already present as row 3). That is it.

Now the part to land, *"I did not write a single new test for the shape."*
- The 10-column contract already applies to every source in this model, so
  External Leads is instantly held to non-null keys and valid channel, type, and
  decision. A wrong column or a bad value fails the build.
- The whole-table checks: one active per key, source coverage, consumer group -
  automatically include Source 3, because they run over the table, not per source.
- Freshness starts the moment I add the _sources.yml block.
- If I want an External-Leads-specific rule, it is a few lines in a test file.

Compare to the old way: *"Adding this source used to mean editing the 800-line
procedure, its ACTIVE logic, and the email. Here it is one block, one registry
row, and it inherits every check we already have."*

Rehearse note: do not type it all live. Show the one block and the registry row,
then point at the tests it inherits for free. That contrast is the whole point.

---

## 7. Tests, what they guard

Tie these to the KRAK-295 use cases when asked.

Shape and structure:
- 10-column contract on staging.
- not_null on the keys; accepted_values on channel, communication type, decision.
- Referential: every source id exists in the registry.

Business integrity:
- Exactly one ACTIVE row per business key (error). Proves the history logic.
- Every active source has rows (warn). Catches a source that stopped delivering.
- Consumer group present (warn). Use case 2.

Clean-view guarantees:
- Decision never null, only OPT-IN or OPT-OUT after defaulting.
- Valid contact keys only (error). Use case 4.
- Consent end date always set: nulls become 9999-12-31 (error). Use case 5.
- No unexpected duplication per object, channel, source, start date (warn). Use case 10.

Say: "About fifty checks run every build. Every result, pass, warn, or fail,
with row counts, rolls up into one table, the run log, instead of scattering a
table per test. If we want the actual failing rows persisted, that is a single
consolidated failures table or Elementary, a deliberate choice, not clutter."

---

## 7a. Warn vs error vs break, the failure spectrum

They will ask "what actually happens when something goes wrong?" First explain
how a run flows, in the simplest terms. Then the three levels fall right out.

### How a run flows (the assembly-line version)

The pipeline is an assembly line. Each station builds one table, start to finish,
then hands off to the next:

    Station 1: load the registry (seed)
    Station 2: build the raw combined table (staging)
    Station 3: build the history (snapshot)
    Station 4: build the target table
    Station 5: build the clean views

Two rules make everything else obvious:

Rule 1, each table is all-or-nothing. A station either finishes its table
completely or it does not touch it. There is no half-built table. If a station
cannot finish, its table keeps exactly what it had from the last run.

Rule 2, a check runs right after a station, and a failed check stops the line
there. The stations before it already finished, they keep today's work. The
stations after it never run, they keep yesterday's work. The bad rows are parked
at the stopped station; the next station never pulls them forward.

So when someone asks "how can some data be fine and some not?", it is never one
table half-done. It is that the early tables have today's data and the later
tables still have yesterday's good data, because the line stopped in the middle.

And "how do the bad rows not move up?", the clean view is the last station. If a
check upstream stops the line, that station never runs, so the view still shows
yesterday's good data. The bad rows sit in an earlier table where we can see them.
They were never carried forward, because the step that carries them never ran.

### The three levels

Warning, the check waves it through. The line keeps running, every table gets
today's data. We just write the issue to the log.
- Example: the source-id check. 3,479 CCPA rows have no id. The load ran, the
  rows are in, the count is in the run log. Nothing stops.

Error, the check stops the line. The station being checked already finished, so
its table has today's data. Every station after it is held at yesterday's data.
The bad rows are parked; the clean view never pulls them.
- Example: two ACTIVE rows for the same person and channel. That check sits on
  the target table (station 4). It stops the line before the views (station 5),
  so the target holds the bad rows but the views people use still show yesterday.

Break, the station itself jams. It cannot finish its table, so by Rule 1 that
table keeps yesterday's data, and every station after it is held too.
- Example: a source renames a column the staging query reads. Station 2 cannot
  finish, so the raw table stays as yesterday's and nothing downstream changes.
- The contract is the gentle version of a break: a wrong-shaped new source fails
  at station 2, before it can reach the target.

The one we softened on purpose, a missing source. A whole missing source table
would jam station 2 (a break). The outage guard turns it into a warning instead:
that one source is skipped, the others still build, the line keeps running.

### Worked examples, follow the data to the target and the view

First clear up the thing that trips people up: a row can be in the target table
but not in the view for two completely different reasons.
1. The view filters it out on purpose, every run. Invalid phones and odd emails
   live in the raw target, and the view's rules drop them. Not a failure, the
   two tiers doing their job.
2. A failed check held the view from rebuilding at all. Then the view is not
   missing a few rows, it is simply yesterday's entire view, untouched.

Now walk real cases through the line. Target = CONSUMER_PREFERENCES_DBT.
View = VW_CONSUMER_PREFERENCES_DBT.

1) A 5-digit phone number comes in from DNC.
   - Nothing stops. It is bad data, but the parsers do not choke on it.
   - Target: the row is there. The raw layer keeps everything.
   - View: not there. The view keeps only 10-to-11-digit phones, so it drops it.
   - Normal filtering, not a failure. The run is green.

2) A CCPA row arrives with no MISC1 source id (our 3,479 rows).
   - The source-id check is a warning, so nothing stops.
   - Target: the row is there, with a null source id.
   - View: the row is there too: a missing id does not make a contact invalid.
   - Green run; the count is in the log.

3) A code change makes CONSENT_END_DATE come out as text, not a timestamp
   (the contract bug we hit and fixed).
   - The contract check jams station 2 (staging). The build fails there.
   - Target: unchanged: still yesterday's data. Station 4 never ran.
   - View: unchanged: still yesterday's view. Station 5 never ran.
   - Nobody downstream saw anything new. We fixed staging and re-ran.

4) Two rows end up ACTIVE for the same phone and channel.
   - Staging, snapshot, and the target all build today's data. Then the
     one-active-per-key check runs on the target and errors, stopping the line
     before the views.
   - Target: today's data: including the two active rows the check caught.
   - View: unchanged: still yesterday's view, because station 5 was held.
   - Consumers read the view, so they never saw the bad state. Fix and re-run.

5) The whole DNC source table is missing one morning.
   - The guard skips DNC with a warning; the line keeps running for the others.
   - Target: DNC's existing rows untouched; CCPA and Journey get today's data.
   - View: same: DNC rows as they were, the others refreshed.

Say it plainly: *"Bad values still land in the target, because the target is our
raw record. The view is where they get cleaned or held. A warning lets data
through; an error or a break stops the line, and then the view just stays as
yesterday's until we fix it."*

| Level | Example here | The line | Result |
|---|---|---|---|
| Warn | CCPA rows with no id | Keeps running | All tables today's data |
| Error (check) | Two ACTIVE for one key | Stops at the check | Checked table today's; later tables held at yesterday's |
| Break (SQL) | A source column renamed | Jams at that station | That table and all after it stay yesterday's |
| Missing source | DNC table absent | Keeps running | DNC skipped, others today's |

Two things to land:
- A failed run never corrupts a table. Because each table is all-or-nothing, the
  worst case is a table stays as yesterday's good data. There is no half-written
  table and no partly-promoted bad data.
- This ties to promotion: warnings do not stop the line or block a merge; errors
  and breaks stop the line and block the merge, so they cannot reach PRD.

How to show it safely:
- Warn: already there: point at the WARN line and the count in the run log.
- Missing source: point one source in _sources.yml at a table that does not
  exist, build, show the skip warning and the others loading, then revert.
- Error or break: describe them and point at what would trigger each. Do not
  deliberately break the build live on demo day.

Rehearse note: the line that wins the room is *"a failed run never corrupts the
table, the worst case is it keeps yesterday's good data, and the bad rows sit in
plain sight one step short of where they would have done harm."*

---

## 8. Pipeline health and observability

- Health view: one row per step with status, last success, duration trend, rows.
- Run log: full per-run audit, written automatically by run hooks.
- Freshness: `dbt source freshness` reports how stale each source is.
- Email: reuses the existing FN_SEND_EMAIL, same recipients as before.
- Snowsight built-ins: run history, logs, and column-level lineage for free.
- Resilience is visible: a skipped source writes a warning to the run output, so
  a missing feed is obvious, not silent.
- Next tier (needs a package): Elementary for row-count anomalies and
  run-duration regression alerts.

---

## 8a. Freshness, in depth

This is worth showing on its own. Freshness answers one question per source: how
long since its newest row arrived? It catches a feed that quietly stopped
updating before stale data flows downstream.

How it is configured, in `_sources.yml`, per source:

    - name: cm_dnc_phone
      loaded_at_field: "TRY_TO_TIMESTAMP(DNC_ETL_TAG_UPD::string)"
      freshness:
        warn_after:  {count: 24, period: hour}
        error_after: {count: 48, period: hour}

Two parts:
- loaded_at_field is the column that marks when a row landed. It can be an
  expression, we wrap some sources in TRY_TO_TIMESTAMP because they store the
  timestamp oddly (DNC as a tag string, CCPA as a 17-digit number).
- warn_after and error_after are the thresholds. They are per source on purpose,
  because each feed has its own rhythm.

Run it and read it live:

    dbt source freshness

*"For each source, dbt takes the newest loaded_at value, compares it to now, and
grades it."* The output is one line per source:

    PASS  cm_dnc_phone .................. 3h old
    WARN  cust_info_srch_ccpa_req_tbl ... 30h old
    ERROR tmmarketing_texting_permission  52h old

Set the thresholds to the cadence. A daily feed warns at 24h and errors at 48h.
An hourly feed would be tighter, warn at 2h, error at 6h. Say: *"We tune each
source to what 'late' means for that source."*

Freshness pairs with a data test, and it is worth drawing the distinction:
- Freshness catches "not updated recently": the feed stalled.
- The active-source-coverage test catches "no rows at all": the feed is empty.
- Together they catch both a stalled feed and an empty one.

Where it fits: freshness checks the inputs; the health view and run log check the
run itself. *"Freshness tells me the data going in is current. The health view
tells me the run that processed it was healthy."*

Versus the old procedure: *"The old load had no concept of freshness. If an
upstream feed stopped, we would not know until someone noticed stale opt-outs.
Now a stale source is flagged the moment we check."*

Rehearse note: run `dbt source freshness` right after the build in the demo, so
you show inputs-are-current and run-is-healthy back to back.

---

## 9. Scheduling, Snowflake and AutoSys

Two ways this runs on a schedule. Know both; present the one your team uses.

Native Snowflake task (self-contained in Snowflake):

    CREATE OR REPLACE TASK DEV_WD_USR_WRKSPC_DB.WD_EDA.TSK_CONSUMER_PREFERENCES_DBT
        WAREHOUSE = 'PRD_TNL_BUS_EDA_WH'
        SCHEDULE = 'USING CRON 0 4 * * * America/New_York'
    AS
        EXECUTE DBT PROJECT DEV_WD_USR_WRKSPC_DB.WD_EDA.CONSUMER_PREFERENCES ARGS='build';

*"The whole run is one line, EXECUTE DBT PROJECT with the build argument, on a
cron, on our own warehouse."*

Enterprise scheduler (AutoSys):
*"If AutoSys is our standard, the AutoSys job triggers the same run, it calls
Snowflake through the CLI to execute the dbt project, and downstream AutoSys
jobs depend on its success. We get the shop-standard dependencies, retries, and
alerting, and Snowflake still does the work."* The AutoSys command runs something
like `snow dbt execute ...` or a `snowsql` call that runs the EXECUTE DBT PROJECT.

Rehearse note: if asked "how does this fit our scheduler," answer with the two
options and say the pipeline does not care which triggers it, it is one command
either way.

---

## 10. Unit testing

Two kinds of testing, and it is worth naming the difference.
- Data tests (the ~50 we run) check the real data: not null, valid values,
  one active per key, and so on. They answer "is the data sane?"
- Unit tests check the transform logic against made-up input rows, with no real
  data. They answer "does the SQL turn this exact input into this exact output?"
  This is how we catch a logic regression before it ever touches data.

You give `given` (mock input rows) and `expect` (the rows you should get back).
dbt builds the model on your mock rows only and compares. Unit tests run inside
`dbt build`, so a failing one fails the build, green each once before relying
on it.

### The staging trick: run_sources override

The staging model includes a branch for every source table that exists. A plain
staging unit test would therefore ask you to mock all twelve source tables. We
set run_sources in the test's `overrides` to the one source under test, so only
that branch builds and you mock only that source:

    unit_tests:
      - name: ccpa_row_splits_email_and_phone
        model: stg_consumer_prefs
        overrides:
          vars:
            run_sources: [1]          -- only CCPA builds; mock only CCPA
        given:
          - input: source('marketing_crm', 'cust_info_srch_ccpa_req_tbl')
            rows:
              - {EMAIL_ADDRESS: 'jane@x.com', AREA_CODE: '303', PHONE_NUMBER: '555-1234',
                 MISC1: 'ID1', MISC2: 'OPT-OUT', MISC3: '2026-01-01',
                 LOAD_DATE: '2026-01-01', ETL_TAG_UPD: '20260101000000000'}
        expect:
          rows:
            - {OBJECT_KEY: 'jane@x.com', CHANNEL: 'MEDIA', COMMUNICATION_TYPE: 'MARKETING',
               DECISION: 'OPT-OUT', CONSUMER_GROUP: 'CCPA', SOURCE_IDENTIFIER: 'ID1', SOURCE_SYSTEM_ID: 1}
            - {OBJECT_KEY: '3035551234', CHANNEL: 'PHONE', COMMUNICATION_TYPE: 'MARKETING',
               DECISION: 'OPT-OUT', CONSUMER_GROUP: 'CCPA', SOURCE_IDENTIFIER: 'ID1', SOURCE_SYSTEM_ID: 1}

### More examples we ship

The `unit_test_examples/` folder has ready templates (dbt does not run that
folder, so they cannot break the build until you move them in):
- view decision defaulting: EMAIL/MEDIA default OPT-IN, PHONE/SMS default OPT-OUT
- CCPA email/phone split (above)
- OFSLL permission neither Y nor N defaults to OPT-OUT
- SFMC STOP becomes a PHONE OPT-OUT

Start with the view test: the view has no source guard, so you mock only its two
refs. To use any of them, move the file into models/marts/ or models/staging/
and run `dbt build --select <model>`.

Rehearse note: validate a test once against your data before demoing it, because
unit tests run inside build and the expected values must match exactly (watch
timestamp format). If you want it live in the demo, get it green first;
otherwise present it as the capability with the templates.

*"This is how we stop a logic regression before it ever touches data, we assert
the transform on fixed inputs."*

---

## 11. CI/CD and change management (GitHub)

See GITHUB.md for setup. The story:
- Every change is a pull request. Who, what, why, and the review are recorded.
- On the PR, the dbt CI workflow builds and tests the project. The check passes
  only if there are no failures, warnings are allowed.
- Branch protection requires that check to merge. So nothing reaches PRD unless
  the tests pass.
- Merging to main triggers the promote-to-PRD workflow.

*"Promotion from DEV to PRD is gated on the tests. If a test fails, the pull
request cannot merge, and the change cannot reach production. Change control is
built into the workflow, not a manual checklist."*

Rehearse note: this is the answer to any governance or audit question, point to
the PR history and the required check.

---

## 12. Improvements over the original SQL

Present as before and after.

| Area | Original procedure | dbt POC |
|---|---|---|
| Structure | One ~800-line procedure | Small models grouped by job |
| Change one source | Edit and retest the whole proc | Edit that source's block |
| History / ACTIVE | Hand-coded deactivate/insert/activate | Native snapshot |
| Watermark | Column managed in a driver table | Derived per source, plus a reload knob |
| Data quality | None automated | Contract + ~50 tests, warn/error severities |
| Freshness | None | Native per-source freshness |
| Observability | Summary email only | Run log + health view + lineage + email |
| Error handling | Per-source try/catch in code | DAG ordering + test gating + run log |
| Reloads | Manual driver-table edits | One command; per-source or per-date |
| Source outage | Whole load fails | Missing source skipped, others load |
| Unit testing | Not possible | Transform logic tested on mock inputs |
| Scheduling | Job runs the proc | Snowflake task or AutoSys runs one command |
| Promotion | Manual, no gate | PR + required tests gate DEV to PRD |
| Environments | SPLIT_PART on the database name | dbt targets and a variable |
| Documentation | Comments in one file | Self-documenting models, tests, and lineage |

One line: "Same outputs, but now it is modular, tested, observable, and safe to
change."

---

## 13. Q&A prep

- "What's the difference between a warning and a failure?" *"A warning is a
  heads-up, the data loads and we log it, like the CCPA rows with no source id.
  A failure is a broken rule or broken SQL, the run stops in a controlled way,
  the bad data is held back, and the last good data stays. Warnings don't block
  promotion; failures do."* (Full spectrum in section 7a.)
- "What if a source breaks?" *"Two cases. Bad data does not break anything: the
  parsers use TRY functions, so bad values become warnings, not failures. A
  missing source table is handled too: the run skips that source with a warning
  and loads the rest, so one broken feed does not stop the pipeline. The one
  thing that still fails the shared staging is a subtler structural break, like a
  renamed column, and arguably we want that loud. For full per-source isolation
  we would split staging into per-source models; we chose the small footprint."*
- "Is the history the same as before?" *"Yes. The snapshot keeps every version
  and marks the current one. The target table mirrors the old table exactly,
  including the ACTIVE column."*
- "How do we go to production?" *"Add a prod target to the profile and run
  against it. No model changes. The environment prefix switches automatically."*
- "How expensive is it?" *"Everything is incremental. Staging reads only changed
  rows per source, and the target table replaces only the business keys that
  changed in a run, no full rebuild. A first load or a --full-refresh reads
  everything; normal daily runs are small."*
- "Does the email still work if the run fails hard?" *"The summary email runs at
  the end. For a hard failure alert, the Snowflake task should send its own, a
  small add we have noted."*
- "Can we trust it matches the old pipeline?" *"That is the next step: a
  reconciliation that compares this output against the live table by business
  key before we cut over."*
- "How does it schedule in our stack?" *"Either a native Snowflake task on a
  cron, or an AutoSys job that triggers the run and hangs downstream jobs off it.
  The pipeline is one command to execute, so either scheduler works."*
- "How do you test the logic itself, not just the data?" *"Unit tests. We feed
  fixed input rows and assert the exact output, for example, that one CCPA row
  becomes an email row and a phone row with the right decisions. They run in the
  build, with no real data needed."*
- "How is change controlled?" *"Through GitHub. Every change is a pull request,
  the tests must pass to merge, and merging is what promotes to PRD. The trail is
  the PR history and the required check."*

---

## 14. Soundbites to land

- "The old load was one block. This is small parts that each do one thing."
- "Raw table for truth. Clean view for use."
- "History and the ACTIVE flag are native now, not hand-coded."
- "Every build tests itself and logs what it did."
- "Adding a source is a small change, and the contract stops me from breaking it."
- "Reloading a date is one command, not a table edit."
- "One broken feed skips itself; the rest of the pipeline still runs."
- "Nothing reaches production unless the tests pass."
