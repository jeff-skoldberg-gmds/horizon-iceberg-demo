{# Force table identifiers to UPPERCASE.

   Normal Snowflake dbt gets uppercase tables for free: Snowflake's SQL engine folds
   unquoted identifiers to uppercase at parse time. Here the writes are executed by
   DuckDB against the Horizon REST catalog, and DuckDB is case-PRESERVING — it stores
   the identifier exactly as dbt emits it (the lowercase model filename). There is no
   quoting config that changes this; case folding is a Snowflake-engine behavior we
   bypass. So we reproduce production behavior here: lowercase filenames in, uppercase
   identifiers out. Symmetric with generate_schema_name (which uppercases namespaces). #}
{% macro generate_alias_name(custom_alias_name=none, node=none) -%}
    {%- if custom_alias_name -%}
        {{ custom_alias_name | trim | upper }}
    {%- elif node.version -%}
        {{ (node.name ~ "_v" ~ (node.version | replace(".", "_"))) | upper }}
    {%- else -%}
        {{ node.name | upper }}
    {%- endif -%}
{%- endmacro %}
