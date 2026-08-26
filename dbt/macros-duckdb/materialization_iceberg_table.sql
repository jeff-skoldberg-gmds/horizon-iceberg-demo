{#
  Native Iceberg table via the Horizon REST catalog.

  dbt-duckdb's stock `table` materialization stages a temp table then renames
  it in, which needs a file delete Horizon's vended creds don't grant (403),
  plus a multi-table commit Horizon doesn't support. So this does the one
  shape Horizon accepts: DROP, then a single CREATE TABLE AS SELECT straight
  into the catalog. Pair with the ice_transformed attach options in profiles.yml.
#}
{% materialization iceberg_table, adapter='duckdb' %}

  {%- set target_relation = this.incorporate(type='table') -%}

  {{ run_hooks(pre_hooks, inside_transaction=False) }}

  -- run_query autocommits each statement, so the drop lands in its own transaction --
  -- iceberg-REST forbids recreating a table dropped in the same transaction as the CREATE below.
  {% do run_query('create schema if not exists ' ~ target_relation.database ~ '.' ~ target_relation.schema) %}
  {% do run_query('drop table if exists ' ~ target_relation) %}

  {% call statement('main', auto_begin=True) -%}
    create table {{ target_relation }} as (
      {{ sql }}
    )
  {%- endcall %}

  -- without this the table lands with the right schema but zero rows -- dbt doesn't
  -- auto-commit a custom materialization, and the data-file append needs a flush.
  {% do adapter.commit() %}

  {{ run_hooks(post_hooks, inside_transaction=False) }}

  {{ return({'relations': [target_relation]}) }}

{% endmaterialization %}
