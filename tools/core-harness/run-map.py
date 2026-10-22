"""Wick's Map offline test.

    python WickSuite/tools/core-harness/run-map.py          # TBC Anniversary and Forever stubs
    python WickSuite/tools/core-harness/run-map.py tbc

Runs on Lua 5.1, the game's runtime. Exits non-zero on any failed check.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__)).replace("\\", "/")
sys.path.insert(0, HERE)
import run as R  # noqa: E402

modes = sys.argv[1:] or ["tbc", "modern"]
ok = True
for mode in modes:
    ok = R.run(HERE + "/map-harness.lua", mode, R.BETA_ADDONS + "/WickCore", R.ANNIV_ADDONS,
               mode, HERE + "/stubclient.lua", lua51=True) and ok
    print()
sys.exit(0 if ok else 1)
