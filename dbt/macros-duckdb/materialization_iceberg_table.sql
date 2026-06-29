{#
  Custom materialization: a native Iceberg table in an attached Horizon REST catalog.

  dbt-duckdb's stock `table` materialization builds `<model>__dbt_tmp` then renames it
  over the final relation. Against a Snowflake Horizon REST catalog that swap deletes the
  temp table's data files, and the vended S3 creds are Put/Get/List only -> 403 Forbidden.

  Horizon also can't do the multi-table transactions/commit endpoint DuckDB uses for a
  staged swap. So we do the one shape Horizon accepts (proven natively): DROP the old
  table, then a single CREATE TABLE AS SELECT straight into the catalog — one per-table
  commit, no temp relation, no rename, no file delete. Pair with the ice_transformed
  attach options in profiles.yml (stage_create_tables false / disable_multi_table_commit
  true / remove_files_on_delete false / skip_create_table_metadata_updates true).

  No parquet round-trip, no pyiceberg, no Snowflake compute — DuckDB writes Iceberg.
#}
{% materialization iceberg_table, adapter='duckdb' %}

  {%- set target_relation = this.incorporate(type='table') -%}

  {{ run_hooks(pre_hooks, inside_transaction=False) }}

  -- Horizon assigns table locations under the external volume; just ensure the namespace.
  -- iceberg-REST forbids re-creating a table dropped in the SAME transaction. dbt-duckdb
  -- runs in autocommit, and run_query commits each statement on its own — so the schema
  -- and drop land in their own transactions, separate from the CREATE below.
  {% do run_query('create schema if not exists ' ~ target_relation.database ~ '.' ~ target_relation.schema) %}
  {% do run_query('drop table if exists ' ~ target_relation) %}

  {% call statement('main', auto_begin=True) -%}
    create table {{ target_relation }} as (
      {{ sql }}
    )
  {%- endcall %}

  -- CRUCIAL: with STAGE_CREATE_TABLES false, DuckDB-iceberg commits the empty table to
  -- Horizon eagerly, but the data-file append is bound to this DuckDB transaction. dbt
  -- doesn't auto-commit a custom materialization, so without this the table lands with
  -- the right schema but ZERO rows (no data snapshot). Commit flushes the append.
  {% do adapter.commit() %}

  {{ run_hooks(post_hooks, inside_transaction=False) }}

  {{ return({'relations': [target_relation]}) }}

{% endmaterialization %}
