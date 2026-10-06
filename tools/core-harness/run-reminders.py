"""Wick's Reminders offline test: two sessions, the second fed the first's saved variable.

    python WickSuite/tools/core-harness/run-reminders.py          # TBC Anniversary and Forever stubs
    python WickSuite/tools/core-harness/run-reminders.py tbc

Runs on Lua 5.1, the game's runtime. Exits non-zero on any failed check.
"""
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__)).replace("\\", "/")
sys.path.insert(0, HERE)
import run as R  # noqa: E402

SV = (tempfile.gettempdir() + "/wicks-reminders-sv.lua").replace("\\", "/")
modes = sys.argv[1:] or ["tbc", "modern"]
ok = True
for mode in modes:
    for phase in ("1", "2"):
        ok = R.run(HERE + "/reminders-harness.lua", mode, R.BETA_ADDONS + "/WickCore", R.ANNIV_ADDONS,
                   mode, HERE + "/stubclient.lua", phase, SV, lua51=True) and ok
        print()
sys.exit(0 if ok else 1)
