-- materialized as a table, not a view: Horizon's Iceberg catalog can't persist a cross-engine view
{{ config(materialized="table") }}

select
    id,
    message,
    created_at
from {{ ref('stg_hello_world') }}
where message = 'world'
