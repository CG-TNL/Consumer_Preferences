-- Builds an HTML run summary from CONSUMER_PREFERENCES_PIPELINE_RUN_LOG_DBT and sends it with the
-- existing FN_SEND_EMAIL. Recipients come from VW_NOTIFICATION_DESTINATARIES,
-- notification id 14, same as the original procedure.
-- Note: an on-run-end hook does not fire if the run aborts before it. Add a
-- failure alert to the Snowflake task wrapper for the hard-failure path.

{% macro send_email_report() %}
  {% if execute %}

    {% set env = var("env_prefix") %}
    {% set fn = env ~ '_TNL_COMMON_DB.TNL_UTILITIES.FN_SEND_EMAIL' %}
    {% set recip_view = env ~ '_TNL_COMMON_DB.TNL_UTILITIES.VW_NOTIFICATION_DESTINATARIES' %}
    {% set log_table = target.database ~ '.' ~ target.schema ~ '.CONSUMER_PREFERENCES_PIPELINE_RUN_LOG_DBT' %}

    {% set recip_sql %}
      select coalesce(listagg(DESTINATARY_EMAIL, ','), '')
      from {{ recip_view }}
      where DESTINATARIES_ACTIVE = 1 and NOTIFICATIONID = 14
    {% endset %}
    {% set recipients = run_query(recip_sql).columns[0].values()[0] %}

    {% if recipients and recipients | length > 0 %}

      {% set body_sql %}
        select
          '<br>Hello Team,</br><br>Consumer Preferences dbt run summary (' || current_date() || ')</br>'
          || '<table border="2"><tr><th>Model</th><th>Type</th><th>Status</th><th>Rows</th><th>Seconds</th></tr>'
          || listagg(
               '<tr><td>' || NODE_NAME || '</td><td>' || RESOURCE_TYPE || '</td><td>' || STATUS
               || '</td><td>' || coalesce(ROWS_AFFECTED::varchar, '') || '</td><td>'
               || round(EXECUTION_SECONDS, 1) || '</td></tr>', ''
             ) within group (order by NODE_NAME)
          || '</table>'
          || '<br>Issues: ' || sum(iff(STATUS not in ('success', 'pass'), 1, 0)) || '</br>'
          || '<br>-EDA Team'
        from {{ log_table }}
        where INVOCATION_ID = '{{ invocation_id }}'
      {% endset %}
      {% set body = run_query(body_sql).columns[0].values()[0] %}

      {% set subject = env ~ ' Consumer Preferences dbt run' %}
      {% set call_sql %}
        call {{ fn }}(
          '{{ recipients | replace("'", "''") }}',
          '{{ subject }}',
          '{{ (body | replace("'", "''")) if body else 'No run detail found.' }}'
        )
      {% endset %}
      {% do run_query(call_sql) %}

    {% endif %}
  {% endif %}
{% endmacro %}
