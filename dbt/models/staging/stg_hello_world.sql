-- Staging model: thin 1:1 transform over the dlt-landed raw Iceberg table.
--
-- READ:  ICE_RAW.LANDING.HELLO_WORLD via the attached `ice_raw` Horizon REST catalog.
-- WRITE: persisted natively into ICE_TRANSFORMED.STAGING.STG_HELLO_WORLD as a
--        Snowflake-managed Iceberg table — DuckDB writes straight to the Horizon REST
--        catalog (bound via +catalog_name in dbt_project.yml). No plugin, no parquet
--        round-trip, no Snowflake compute. See NOTES_horizon_write_path.md.

with source as (

    select * from {{ source('landing', 'HELLO_WORLD') }}

)

select
    id          as id,
    message     as message,
    created_at  as created_at
from source
