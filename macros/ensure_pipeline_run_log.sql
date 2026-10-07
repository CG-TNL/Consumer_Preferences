-- Ensures CONSUMER_PREFERENCES_PIPELINE_RUN_LOG_DBT exists before models build and before the log writes
-- Called from on-run-start and from log_run_results

{% macro ensure_pipeline_run_log() %}
  {% set log_table = target.database ~ '.' ~ target.schema ~ '.CONSUMER_PREFERENCES_PIPELINE_RUN_LOG_DBT' %}
  {% set create_sql %}
    create table if not exists {{ log_table }} (
      INVOCATION_ID     varchar,
      NODE_ID           varchar,
      RESOURCE_TYPE     varchar,
      NODE_NAME         varchar,
      STATUS            varchar,
      EXECUTION_SECONDS float,
      ROWS_AFFECTED     number,
      MESSAGE           varchar,
      LOGGED_AT         timestamp_ntz
    )
  {% endset %}
  {% if execute %}
    {% do run_query(create_sql) %}
  {% endif %}
{% endmacro %}
