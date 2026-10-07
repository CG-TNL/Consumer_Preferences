-- Per-source incremental lower bound for the staging model.
-- Normal run: pull rows newer than the max ETL_TIMESTAMP already loaded for
--   that source.
-- Reload: pass vars to pull from a fixed point instead.
--   reload_from can be:
--     a single date  -> applies to reload_source ('all' by default, or a list)
--     a map of id:date -> each listed source reloads from its own date
-- Examples:
--   build --vars '{reload_from: "2026-01-01", reload_source: 1}'        one source
--   build --vars '{reload_from: "2026-01-01", reload_source: [1, 4]}'   several, same date
--   build --vars '{reload_from: "2026-01-01"}'                          all, same date
--   build --vars '{reload_from: {1: "2026-01-01", 5: "2025-06-01"}}'    per-source dates

{% macro cp_incremental_filter(source_id, ts_expr) %}
    {%- set reload_from = var('reload_from', none) -%}
    {%- set reload_source = var('reload_source', 'all') -%}
    {%- set reload_date = none -%}

    {%- if is_incremental() and reload_from is not none -%}
        {%- if reload_from is mapping -%}
            -- per-source map: reload only the ids present, each from its own date
            {%- for k, v in reload_from.items() -%}
                {%- if k | string == source_id | string -%}
                    {%- set reload_date = v -%}
                {%- endif -%}
            {%- endfor -%}
        {%- else -%}
            -- single date: apply to reload_source (all, one id, or a list)
            {%- set applies = false -%}
            {%- if reload_source is string and reload_source == 'all' -%}
                {%- set applies = true -%}
            {%- elif (reload_source is string) or (reload_source is number) -%}
                {%- set applies = (reload_source | string == source_id | string) -%}
            {%- else -%}
                {%- set id_list = [] -%}
                {%- for x in reload_source -%}{%- do id_list.append(x | string) -%}{%- endfor -%}
                {%- set applies = (source_id | string in id_list) -%}
            {%- endif -%}
            {%- if applies -%}{%- set reload_date = reload_from -%}{%- endif -%}
        {%- endif -%}
    {%- endif -%}

    {%- if is_incremental() -%}
        {%- if reload_date is not none -%}
            and {{ ts_expr }} > '{{ reload_date }}'::timestamp_ntz
        {%- else -%}
            and {{ ts_expr }} > (select max(ETL_TIMESTAMP) from {{ this }} where SOURCE_SYSTEM_ID = {{ source_id }})
        {%- endif -%}
    {%- endif -%}
{% endmacro %}
