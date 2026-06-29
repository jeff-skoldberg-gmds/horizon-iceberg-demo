-- Test model: a plain dbt view on top of the persisted staging table.
--
-- Unlike stg_hello_world (an Iceberg TABLE in ICE_TRANSFORMED), this is a normal
-- `view` materialization, so it lives only in the local DuckDB database — Horizon's
-- REST catalog / DuckDB's iceberg extension can't persist a cross-engine view
-- ("Not implemented Error: Create View"). It reads the staging table back and keeps
-- just the "hello" greetings (the staging data is "hello"/"world" tokens).
{{ config(materialized="table") }}

select
    id,
    message,
    created_at
from {{ ref('stg_hello_world') }}
where message = 'hello'
