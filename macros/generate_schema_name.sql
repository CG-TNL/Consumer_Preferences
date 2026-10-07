-- Keep every object in the profile's schema (WD_EDA).
-- dbt normally appends suffixes for custom schemas, such as the
-- dbt_test__audit schema used by store_failures. We cannot create schemas
-- here, so ignore the suffix and put everything in target.schema.

{% macro generate_schema_name(custom_schema_name, node) -%}
    {{ target.schema | trim }}
{%- endmacro %}
