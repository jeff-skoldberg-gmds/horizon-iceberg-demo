"""hello_world dlt pipeline -> Snowflake Horizon Iceberg, REST-catalog-only.

Alternative to hello_world_pipeline.py: a custom sink destination instead of
`filesystem()`. Horizon's vended creds are object-scoped per table prefix,
not bucket-scoped, so `filesystem()`'s bucket-level ops (ListBucket,
HeadBucket) fail against them; a sink writes straight through pyiceberg and
never calls those. Also writes dlt's own system tables the same way, so no
separate mirror step is needed.

Tradeoffs: no pipeline.dataset() querying, no state restore between runs, no
automatic schema evolution (see view_pipeline_metadata.py for the query path).

Catalog auth: .dlt/secrets.toml ([iceberg_catalog]).
"""

import dlt
import pyarrow as pa
import pyarrow.parquet as pq
from dlt.common.libs.pyiceberg import ensure_iceberg_compatible_arrow_schema, get_catalog, write_iceberg_table
from pyiceberg.table import UNPARTITIONED_PARTITION_SPEC

NAMESPACE = "LANDING"
TABLE = "HELLO_WORLD"
PIPELINE_NAME = "horizon_hello_world"


def _load_or_create_table(catalog, table_id: str, schema: pa.Schema):
    """Load `table_id`, creating it first if needed. No explicit `location` -- Horizon assigns one itself."""
    try:
        return catalog.load_table(table_id)
    except Exception:
        catalog.create_table(
            identifier=table_id,
            schema=ensure_iceberg_compatible_arrow_schema(schema),
            partition_spec=UNPARTITIONED_PARTITION_SPEC,
            properties={},
        )
        return catalog.load_table(table_id)


@dlt.destination(
    loader_file_format="parquet",
    batch_size=0,  # callable gets the parquet file path directly, once per table
    skip_dlt_columns_and_tables=False,  # also route _dlt_loads/_dlt_version/_dlt_pipeline_state here
    naming_convention="direct",  # no case-folding; keep identifiers verbatim
)
def iceberg_rest_sink(file_path, table) -> None:
    catalog = get_catalog(iceberg_catalog_type="rest")  # PAT auth, resolved via dlt.secrets internally
    catalog.create_namespace_if_not_exists((NAMESPACE,))

    table_name = table["name"]
    if table_name.startswith("_dlt"):
        table_name = f"{PIPELINE_NAME}{table_name}"  # avoid collision with other pipelines in this namespace

    arrow = pq.read_table(file_path)
    tbl = _load_or_create_table(catalog, f"{NAMESPACE}.{table_name}", arrow.schema)
    write_iceberg_table(table=tbl, data=arrow, write_disposition="append")


@dlt.resource(
    table_name=TABLE,    # uppercase: naming_convention="direct" keeps it verbatim
    write_disposition="append",
    primary_key="ID",
)
def hello_world(pairs: int = None):
    """Yield `pairs` hello/world row-pairs. Defaults to HELLO_WORLD_PAIRS env var (or 100)."""
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


def main() -> None:
    pipeline = dlt.pipeline(
        pipeline_name=PIPELINE_NAME,
        destination=iceberg_rest_sink,
        dataset_name=NAMESPACE,
    )

    load_info = pipeline.run(hello_world())
    print(load_info)


if __name__ == "__main__":
    main()
