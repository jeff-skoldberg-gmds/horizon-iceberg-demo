"""Read-only inspector for the horizon_hello_world dlt pipeline's own metadata.

Uses pipeline.dataset() instead of querying Snowflake -- for a filesystem
destination this spins up DuckDB to read the underlying files directly, no
Snowflake round-trip needed. Attaches to existing local state only; doesn't
run hello_world_pipeline.py.
"""

import botocore.session
import dlt
from dlt.destinations import filesystem

# dlt.attach() alone hands S3 auth to DuckDB's credential_chain resolver, which
# can't complete our SSO exchange. A live botocore session makes dlt hand
# DuckDB frozen static keys instead.
session = botocore.session.Session(profile="gmds")

pipeline = dlt.pipeline(
    pipeline_name="horizon_hello_world",
    destination=filesystem(preferred_table_format="iceberg", credentials=session),
    dataset_name="LANDING",
)
dataset = pipeline.dataset()

# each table's own timestamp column -- .limit() alone follows DuckDB's glob
# order over the JSONL files, not recency
timestamp_column = {
    "_dlt_loads": "inserted_at",
    "_dlt_version": "inserted_at",
    "_dlt_pipeline_state": "created_at",
}
for table_name, ts_col in timestamp_column.items():
    print(f"\n=== {table_name} (latest 5 by {ts_col}) ===")
    print(dataset(f'SELECT * FROM "{table_name}" ORDER BY {ts_col} DESC LIMIT 5').arrow())
