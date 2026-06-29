"""dltHub deployment manifest — declares schedulable jobs for this workspace.

The pipeline logic stays in hello_world_pipeline.py (still runnable as a plain
script: `uv run python hello_world_pipeline.py`). This file only declares *when*
dltHub Runtime should run it. Schedules live as code here — to change the
cadence, edit the trigger(s) and `dlthub deploy` again.
"""

from dlt.hub.run import job, trigger

from hello_world_pipeline import main

# Only deploy what's listed here — prevents accidentally registering anything else
# that happens to live in this module's namespace.
__all__ = ["hello_world_pipeline"]

# Every 30 minutes during the 8 AM–5 PM US/Eastern business window. dltHub allows
# only ONE interval trigger per job, and a single cron's minute field can't depend
# on the hour — so "8-17" ticks :00/:30 through 5:30 PM (includes the 5:00 PM run
# plus one tail at 5:30). Timezone makes the cron tick on Eastern wall-clock
# (DST-aware) rather than UTC.
@job(
    name="hello_world_pipeline",
    trigger=trigger.schedule("*/30 8-17 * * *"),
    require={"timezone": "America/New_York"},
)
def hello_world_pipeline():
    main()
