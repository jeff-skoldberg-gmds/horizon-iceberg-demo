-- Thin 1:1 transform: reads ICE_RAW.LANDING.HELLO_WORLD, writes ICE_TRANSFORMED.STAGING.STG_HELLO_WORLD.
-- See NOTES_horizon_write_path.md for the write path.

with source as (

    select * from {{ source('landing', 'HELLO_WORLD') }}

)

select
    id          as id,
    message     as message,
    created_at  as created_at
from source
limit 20_000