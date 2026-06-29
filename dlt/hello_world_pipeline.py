"""hello_world dlt pipeline -> Snowflake Horizon Iceberg via the Iceberg REST API.

Open-source path (no dlt+ / no licensed destination):

    dlt `filesystem` destination
      + resource hint  table_format="iceberg"   (writes via pyiceberg)
      + an Iceberg REST catalog pointed at Snowflake Horizon

Snowflake Horizon exposes an Iceberg REST Catalog API and (public preview, 2026)
accepts *external writes* to Snowflake-managed Iceberg tables. dlt/pyiceberg commit
through that endpoint; Horizon stays the catalog owner and vends temporary S3
credentials, so no AWS keys live in this project.

Maps to the Terraform stack in tf/:
    database (REST "warehouse") = ICE_RAW                  -> [iceberg_catalog].warehouse
    schema (REST namespace)     = LANDING                  -> dataset_name
    table                       = hello_world
    storage                     = s3://my-org-iceberg/horizon (external volume HORIZON_EXT_VOL)

Catalog connection + auth live in .dlt/secrets.toml ([iceberg_catalog]).
The bucket location lives in .dlt/config.toml ([destination.filesystem]).

NOT run yet -- scaffold only. When ready:
    uv run python hello_world_pipeline.py
"""

import dlt
from dlt.destinations import filesystem

# --- Snowflake Horizon compatibility shim -----------------------------------
# dlt's filesystem+iceberg destination always creates tables with an EXPLICIT
# location (derived from bucket_url). Snowflake-managed Iceberg rejects that
# ("Creating a table with an explicit location is not allowed") — Horizon assigns
# the location itself under the external volume (HORIZON_EXT_VOL). So we wrap
# dlt's create_table to omit `location`, which is the intended external-write
# flow. Everything else (schema, namespace, data write via vended creds) is
# unchanged. dlt only passes a location on CREATE; writes to an existing table
# already send none, so this only affects first-time table creation.
import dlt.common.libs.pyiceberg as _ice
import pyarrow as _pa


def _create_table_catalog_managed_location(
    catalog, table_id, table_location, schema,
    partition_columns=None, partition_spec=_ice.UNPARTITIONED_PARTITION_SPEC, properties=None,
):
    if isinstance(schema, _pa.Schema):
        schema = _ice.ensure_iceberg_compatible_arrow_schema(schema)
    # NOTE: table_location intentionally dropped — Snowflake Horizon controls it.
    catalog.create_table(
        identifier=table_id,
        schema=schema,
        partition_spec=partition_spec,
        properties=properties or {},
    )


_ice.create_table = _create_table_catalog_managed_location
# ----------------------------------------------------------------------------


@dlt.resource(
    table_name="HELLO_WORLD",            # UPPERCASE: case-sensitive naming (config.toml) keeps it verbatim
    write_disposition="append",          # insert rows on each run rather than replacing the table
    primary_key="ID",
    table_format="iceberg",  # OSS dlt routes this through pyiceberg + the REST catalog
)
def hello_world(pairs: int = None):
    """`pairs` hello/world row-pairs of mock data, stamped with the current load time.

    Each pair is one "hello" + one "world" row, so the output keeps its shape; `pairs`
    just scales how many of them. Defaults to the HELLO_WORLD_PAIRS env var (or 1), so
    you can load more rows without editing code:  HELLO_WORLD_PAIRS=100 <run command>.

    ID is a per-row UUID so appended rows stay unique across runs (the table uses
    write_disposition="append", so reusing fixed ints would collide every run).
    """
    import datetime as _dt
    import os as _os
    import uuid as _uuid

    if pairs is None:
        pairs = int(_os.environ.get("HELLO_WORLD_PAIRS", "100"))

    now = _dt.datetime.now(_dt.timezone.utc)
    for _ in range(pairs):
        yield [
            {"ID": str(_uuid.uuid4()), "MESSAGE": "hello", "CREATED_AT": now},
            {"ID": str(_uuid.uuid4()), "MESSAGE": "world", "CREATED_AT": now},
        ]


def _mirror_dlt_system_tables_to_iceberg(pipeline: "dlt.Pipeline") -> None:
    """Create/replace iceberg copies of dlt's system tables in the Horizon REST catalog.

    The filesystem destination writes _dlt_loads / _dlt_version / _dlt_pipeline_state as
    plain JSON files for its own bookkeeping (and reads them back that way), so we cannot
    flip them to iceberg via config. Instead we re-materialize their current contents as
    iceberg tables through the destination's OWN catalog client — the exact same vended-
    credentials + pyiceberg flow the data table uses, so the "no Snowflake compute"
    property is preserved. The JSON files remain dlt's source of truth; these iceberg
    tables are a queryable mirror for inspection in Snowflake.
    """
    import datetime as _dt
    import json as _json

    from dlt.common.libs.pyiceberg import write_iceberg_table
    from dlt.pipeline.state_sync import state_doc as _state_doc

    schema = pipeline.default_schema
    now = _dt.datetime.now(_dt.timezone.utc)
    load_id = pipeline.list_completed_load_packages()[-1]

    # Reconstruct the rows dlt just wrote, from authoritative in-process objects.
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

    # _dlt_pipeline_state: the compressed state lives in a base64 *text* column (not a raw
    # binary blob), so it is iceberg-compatible. Build the same doc dlt would persist.
    state_rows = [dict(_state_doc(pipeline.state, load_id=load_id))]

    # Column names mirror dlt's own _dlt_loads / _dlt_version / _dlt_pipeline_state schemas.
    targets = {
        schema.loads_table_name: loads_rows,
        schema.version_table_name: version_rows,
        schema.state_table_name: state_rows,
    }

    with pipeline.destination_client() as job_client:
        catalog = job_client.get_open_table_catalog("iceberg")
        namespace = job_client.dataset_name  # "LANDING"
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
                # create_table is monkeypatched above to omit the explicit location,
                # which Snowflake-managed iceberg requires.
                _ice.create_table(catalog, table_id, None, arrow.schema)
                tbl = catalog.load_table(table_id)
            write_iceberg_table(table=tbl, data=arrow, write_disposition="replace")
            print(f"mirrored {table_name} -> iceberg ({arrow.num_rows} row(s))")


def main() -> None:
    pipeline = dlt.pipeline(
        pipeline_name="horizon_hello_world",
        # preferred_table_format="iceberg" is a destination *capability* override: dlt's
        # prepare_load_table() applies it as the default table_format to every DATA table
        # that doesn't set one explicitly. NOTE: it does NOT reach the dlt system tables —
        # the filesystem destination special-cases _dlt_loads / _dlt_version /
        # _dlt_pipeline_state and writes them as plain JSON files (see
        # FilesystemClient._store_load / _store_current_state / _update_schema_in_storage),
        # bypassing the iceberg load-job path entirely. We still set it because it is the
        # correct declarative default for any future data tables; the system tables are
        # mirrored into iceberg separately by _mirror_dlt_system_tables_to_iceberg() below.
        destination=filesystem(preferred_table_format="iceberg"),  # bucket_url + [iceberg_catalog] from .dlt/*.toml
        dataset_name="LANDING",     # Iceberg namespace == Snowflake schema (must match ICE_RAW.LANDING)
    )

    load_info = pipeline.run(hello_world())
    print(load_info)

    # dlt won't make its own bookkeeping tables iceberg (they're written as JSON files by
    # the filesystem destination). Mirror them into the SAME Horizon REST catalog so they
    # become queryable Snowflake iceberg tables — still no Snowflake compute, same vended
    # credentials + pyiceberg path as the data table.
    _mirror_dlt_system_tables_to_iceberg(pipeline)


if __name__ == "__main__":
    main()
