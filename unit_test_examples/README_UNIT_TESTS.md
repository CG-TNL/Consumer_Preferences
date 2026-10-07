# Unit test examples

These are templates. dbt does not parse this folder, so nothing here runs until
you move it into the model folders. That keeps a half-written test from breaking
the build.

## What a unit test does

A data test (in `tests/`) runs against real table data and asks "is the output
sane?". A unit test runs against rows YOU provide and asks "does the transform
turn this exact input into this exact output?". You give `given` (mock inputs)
and `expect` (the rows you should get back). dbt builds the model on your mock
rows only and compares.

Unit tests run inside `dbt build`. A failing unit test fails the build, so green
each one once before you rely on it.

## How to run one

1. Move the file into the model's folder:
   - view tests   -> `models/marts/`
   - staging tests -> `models/staging/`
2. Run it:
   - `dbt build --select vw_consumer_preferences_dbt`
   - `dbt build --select stg_consumer_prefs`
3. If it is red, dbt prints the expected vs actual rows. Fix the `expect`
   values (timestamp format, column set) until green.

## The files

- `example_view_decision_defaulting.yml`: start here. The view has no source
  guard, so you mock only its two refs. Checks the channel-based decision
  default (EMAIL/MEDIA -> OPT-IN, PHONE/SMS -> OPT-OUT).
- `example_staging_ccpa_split.yml`: one CCPA row becomes an email row and a
  phone row.
- `example_staging_new_sources.yml`: OFSLL default-to-OPT-OUT, and an SFMC STOP.

## The staging trick: run_sources override

The staging model includes a branch for every source table that exists, so a
plain staging unit test would ask you to mock all twelve source tables. Set
`run_sources` in the test's `overrides` to the one source you are testing:

    overrides:
      vars:
        run_sources: [1]

Now only that source's branch builds, and you mock only that one source.

## Notes

- `expect` compares the full output set, order-independent. List every row the
  model should produce for your input, not just the one you care about.
- Match column names to the model output. For staging that is the 10 contract
  columns; for the view it is the 17 output columns.
- Keep inputs tiny. Two or three rows prove the logic.
