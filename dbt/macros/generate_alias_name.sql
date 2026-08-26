{# Force table identifiers to UPPERCASE.

   Snowflake folds unquoted identifiers to uppercase automatically; DuckDB
   (writing here via the Horizon REST catalog) is case-preserving, so we
   reproduce that behavior by hand. Symmetric with generate_schema_name. #}
{% macro generate_alias_name(custom_alias_name=none, node=none) -%}
    {%- if custom_alias_name -%}
        {{ custom_alias_name | trim | upper }}
    {%- elif node.version -%}
        {{ (node.name ~ "_v" ~ (node.version | replace(".", "_"))) | upper }}
    {%- else -%}
        {{ node.name | upper }}
    {%- endif -%}
{%- endmacro %}
