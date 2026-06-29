{# Use the model's +schema verbatim (no <profile_schema>_<custom> concatenation).
   Iceberg REST namespaces are explicit (staging, marts) — we don't want the
   default dbt prefixing that yields names like STAGING_staging. #}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
