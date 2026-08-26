# No Slop Comments

Comments must be short and human-readable. No preambles, no restating what the code obviously does, no "changed X to Y" narration. If a comment wouldn't survive a human writing it by hand, don't write it.

# Always Use uv

This project manages Python with `uv`. Never use `pip` or `uv pip install` — use `uv add` / `uv remove` so `pyproject.toml` and `uv.lock` stay in sync.
