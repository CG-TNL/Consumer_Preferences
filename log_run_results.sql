-- Writes one row per model, snapshot, test, and source to CONSUMER_PREFERENCES_PIPELINE_RUN_LOG_DBT
-- at the end of every run. Answers: did it run, did it fail, how many rows,
-- how long, and what the message was.

{% macro log_run_results() %}
  {% if execute and results | length > 0 %}

    {% set log_table = target.database ~ '.' ~ target.schema ~ '.CONSUMER_PREFERENCES_PIPELINE_RUN_LOG_DBT' %}

    {% do ensure_pipeline_run_log() %}

    {% set values = [] %}
    {% for r in results %}
      {% set rows_affected = 'null' %}
      {% if r.adapter_response and r.adapter_response.get('rows_affected') is not none %}
        {% set rows_affected = r.adapter_response.get('rows_affected') %}
      {% endif %}
      {% set msg = (r.message | replace("'", "''")) if r.message else '' %}
      {% set row = "('" ~ invocation_id ~ "','" ~ r.node.unique_id ~ "','"
                   ~ r.node.resource_type ~ "','" ~ r.node.name ~ "','"
                   ~ r.status ~ "'," ~ r.execution_time ~ "," ~ rows_affected
                   ~ ",'" ~ msg ~ "',current_timestamp())" %}
      {% do values.append(row) %}
    {% endfor %}

    {% set insert_sql %}
      insert into {{ log_table }} values
      {{ values | join(',\n') }}
    {% endset %}
    {% do run_query(insert_sql) %}

  {% endif %}
{% endmacro %}
