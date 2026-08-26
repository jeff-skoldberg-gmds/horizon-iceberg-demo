"""hello_world dlt pipeline -> Snowflake Horizon Iceberg via the Iceberg REST API.

OSS path: dlt `filesystem` destination + table_format="iceberg", pointed at
Snowflake Horizon's Iceberg REST catalog. Horizon vends temp S3 creds, so no
AWS keys live in this project. Catalog auth: .dlt/secrets.toml. Bucket:
.dlt/config.toml.
"""

import dlt
from dlt.destinations import filesystem

# Snowflake rejects CREATE TABLE with an explicit location; Horizon assigns
# one itself. Patch create_table to drop it (only affects first-time creates).
import dlt.common.libs.pyiceberg as _ice
import pyarrow as _pa


def _create_table_catalog_managed_location(
    catalog, table_id, table_location, schema,
    partition_columns=None, partition_spec=_ice.UNPARTITIONED_PARTITION_SPEC, properties=None,
):
    if isinstance(schema, _pa.Schema):
        schema = _ice.ensure_iceberg_compatible_arrow_schema(schema)
    catalog.create_table(
        identifier=table_id,
        schema=schema,
        partition_spec=partition_spec,
        properties=properties or {},
    )


_ice.create_table = _create_table_catalog_managed_location


@dlt.resource(
    table_name="HELLO_WORLD",  # kept uppercase verbatim (config.toml)
    write_disposition="append",
    primary_key="ID",
    table_format="iceberg",
)
def hello_world(pairs: int = None):
    """Yield `pairs` hello/world row-pairs. Defaults to HELLO_WORLD_PAIRS env var, else random."""
    import datetime as _dt
    import os as _os
    import random as _random
    import uuid as _uuid

    if pairs is None:
        env_pairs = _os.environ.get("HELLO_WORLD_PAIRS")
        pairs = int(env_pairs) if env_pairs else _random.randint(1, 50)

    now = _dt.datetime.now(_dt.timezone.utc)
    for _ in range(pairs):
        yield [
            {"ID": str(_uuid.uuid4()), "MESSAGE": "hello", "CREATED_AT": now},
            {"ID": str(_uuid.uuid4()), "MESSAGE": "world", "CREATED_AT": now},
        ]


def _mirror_dlt_system_tables_to_iceberg(pipeline: "dlt.Pipeline") -> None:
    """Mirror dlt's JSON system tables into Iceberg — JSON stays the source of truth."""
    import datetime as _dt
    import json as _json

    from dlt.common.libs.pyiceberg import write_iceberg_table
    from dlt.pipeline.state_sync import state_doc as _state_doc

    schema = pipeline.default_schema
    now = _dt.datetime.now(_dt.timezone.utc)
    load_id = pipeline.list_completed_load_packages()[-1]

    loads_rows = [
        {
            "load_id": load_id,
            "schema_name": schema.name,
            "status": 0,
            "inserted_at": now,
            "schema_version_hash": schema.version_hash,
        }
    ]
    version_rows = [
        {
            "version": schema.version,
            "engine_version": schema.ENGINE_VERSION,
            "inserted_at": now,
            "schema_name": schema.name,
            "version_hash": schema.version_hash,
            "schema": _json.dumps(schema.to_dict()),
        }
    ]

    state_rows = [dict(_state_doc(pipeline.state, load_id=load_id))]

    targets = {
        schema.loads_table_name: loads_rows,
        schema.version_table_name: version_rows,
        schema.state_table_name: state_rows,
    }

    with pipeline.destination_client() as job_client:
        catalog = job_client.get_open_table_catalog("iceberg")
        namespace = job_client.dataset_name
        try:
            catalog.create_namespace_if_not_exists((namespace,))
        except Exception:
            pass

        for table_name, rows in targets.items():
            arrow = _pa.Table.from_pylist(rows)
            table_id = f"{namespace}.{table_name}"
            try:
                tbl = catalog.load_table(table_id)
            except Exception:
                _ice.create_table(catalog, table_id, None, arrow.schema)
                tbl = catalog.load_table(table_id)
            write_iceberg_table(table=tbl, data=arrow, write_disposition="replace")
            print(f"mirrored {table_name} -> iceberg ({arrow.num_rows} row(s))")


def main() -> None:
    pipeline = dlt.pipeline(
        pipeline_name="horizon_hello_world",
        destination=filesystem(preferred_table_format="iceberg"),  # data tables only; system tables mirrored separately below
        dataset_name="LANDING",  # must match ICE_RAW.LANDING
    )

    load_info = pipeline.run(hello_world())
    print(load_info)

    _mirror_dlt_system_tables_to_iceberg(pipeline)


if __name__ == "__main__":
    main()
