"""dltHub deployment manifest — declares schedulable jobs for this workspace.

Pipeline logic stays in hello_world_pipeline.py; this just declares when
dltHub Runtime should run it. Edit the trigger(s) and `dlthub deploy` again
to change cadence.
"""

import dlt
from dlt.common.runtime.slack import send_slack_message
from dlt.hub.run import job, trigger

from hello_world_pipeline import main

__all__ = ["hello_world_pipeline"]  # only deploy what's listed here


def _notify_failure(exc: Exception) -> None:
    # dltHub Platform has no built-in failure alerting, so the job notifies itself.
    hook = dlt.secrets.get("runtime.slack_incoming_hook")
    if not hook or "hooks.slack.com" not in hook:
        return
    try:
        send_slack_message(
            hook,
            f":rotating_light: *hello_world_pipeline* failed on dltHub Platform\n```{exc!r}```",
        )
    except Exception:
        pass  # never let the notifier hide the original failure


# The dashboard trigger wins at runtime, so keep this in sync with it rather than fighting it.
@job(
    name="hello_world_pipeline",
    trigger=trigger.schedule("0 6 * * *"),
)
def hello_world_pipeline():
    try:
        main()
    except Exception as exc:
        _notify_failure(exc)
        raise  # re-raise so the job still shows as failed on the platform
