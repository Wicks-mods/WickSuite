"""Offline load tests for WickCore and the products built on it.

    python WickSuite/tools/core-harness/run.py                 # WickCore, Forever-shaped stub client
    python WickSuite/tools/core-harness/run.py --tbc           # WickCore, TBC Anniversary 2.5.6-shaped stub client
    python WickSuite/tools/core-harness/run.py --legacy        # WickCore, Era-shaped stub client (no modern API)
    python WickSuite/tools/core-harness/run.py --both          # WickCore, modern + legacy
    python WickSuite/tools/core-harness/run.py --all           # WickCore, modern + legacy + tbc
    python WickSuite/tools/core-harness/run.py --bags --both   # Wick's Bags on WickCore, both
    python WickSuite/tools/core-harness/run.py --kits --both   # Totems, Demons, Forms kits, both
    python WickSuite/tools/core-harness/run.py --probe        # Wick's Probe, aura-route watcher
    python WickSuite/tools/core-harness/run.py --ui           # Wick's UI, Forever only
    python WickSuite/tools/core-harness/run.py --suite        # the TBC addons on WickCore (Quest Key, Concession Stand, Demons, Ledger, Bags)

Exits non-zero on any failed check.
"""

import argparse
import os
import sys

try:
    import lupa
except ImportError:
    sys.exit("lupa is not installed. pip install lupa")

BETA_ADDONS = r"C:/Program Files (x86)/World of Warcraft/_classic_beta_/Interface/AddOns"
ANNIV_ADDONS = r"C:/Program Files (x86)/World of Warcraft/_anniversary_/Interface/AddOns"
HERE = os.path.dirname(os.path.abspath(__file__)).replace("\\", "/")


def run(harness, mode, *args, lua51=False):
    # The game runs Lua 5.1. Libraries that name a local _ENV (oUF's tags)
    # only behave as they do in game on a 5.1 runtime.
    if lua51:
        import lupa.lua51 as runtime
        lua = runtime.LuaRuntime(unpack_returned_tuples=True)
    else:
        runtime = lupa
        lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    runner = lua.eval(
        "function(harness, ...)"
        "  local f = assert(loadfile(harness))"
        "  return f(...)"
        "end"
    )
    try:
        runner(harness, *args)
        return True
    except (lupa.LuaError, runtime.LuaError) as e:
        print(f"harness failed ({mode}):\n{e}")
        return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--core", default=BETA_ADDONS + "/WickCore")
    ap.add_argument("--bags-dir", default=BETA_ADDONS + "/WicksBags")
    ap.add_argument("--bags", action="store_true", help="run the Wick's Bags product harness")
    ap.add_argument("--kits", action="store_true", help="run the class kits harness (Totems, Demons, Forms)")
    ap.add_argument("--gear", action="store_true", help="run the Wick's Gear harness")
    ap.add_argument("--ui", action="store_true", help="run the Wick's UI harness")
    ap.add_argument("--suite", action="store_true", help="run the TBC suite harness (the addons on WickCore in _anniversary_)")
    ap.add_argument("--probe", action="store_true",
                    help="run the Wick's Probe harness (aura-route watcher)")
    ap.add_argument("--legacy", action="store_true", help="Era-shaped stub client, none of the modern API")
    ap.add_argument("--tbc", action="store_true", help="TBC Anniversary 2.5.6-shaped stub client")
    ap.add_argument("--both", action="store_true", help="modern and legacy")
    ap.add_argument("--all", action="store_true", help="modern, legacy and tbc")
    ap.add_argument("--styles", action="store_true",
                    help="with --ui: run once in every WickCore style; with --bags: in Modern, OG and Classic")
    args = ap.parse_args()

    stub = HERE + "/stubclient.lua"
    if args.all:
        modes = ["modern", "legacy", "tbc"]
    elif args.both:
        modes = ["modern", "legacy"]
    elif args.tbc:
        modes = ["tbc"]
    elif args.legacy:
        modes = ["legacy"]
    else:
        modes = ["modern"]
    # Wick's Gear is Forever only. It reads C_Item and WickCore's modern
    # dialect throughout, so a legacy pass would only ever fail on the
    # first line that asks the client for an item.
    if args.gear:
        modes = ["modern"]
    # The probe's aura work is a question about the Forever client, so
    # there is nothing for a legacy pass to say about it.
    if args.probe:
        modes = ["modern"]
    # Wick's UI ships to Forever and TBC Anniversary, both 12.x-engine
    # clients; the Era-shaped stub has nothing to say about it.
    if args.ui:
        modes = ["modern", "tbc"] if args.all else (["tbc"] if args.tbc else ["modern"])
    # The TBC addons ship to one client; the stub shaped like it is the
    # only pass that says anything about them.
    if args.suite:
        modes = ["tbc"]
    ok = True
    for mode in modes:
        if args.bags:
            for style in (["modern", "og", "classic"] if args.styles else [""]):
                os.environ["WICK_STYLE"] = style
                if style:
                    print(f"-- style {style}")
                ok = run(HERE + "/bags-harness.lua", mode, args.core, args.bags_dir, mode, stub) and ok
        elif args.kits:
            ok = run(HERE + "/kits-harness.lua", mode, args.core, BETA_ADDONS, mode, stub) and ok
        elif args.ui:
            for style in (["modern", "og", "hologram", "rebel", "gilded", "arena", "foundry", "frost", "crisp", "classic"] if args.styles else [""]):
                os.environ["WICK_STYLE"] = style
                if style:
                    print(f"-- style {style}")
                ok = run(HERE + "/ui-harness.lua", mode, args.core, BETA_ADDONS + "/WicksUI", mode, stub, lua51=True) and ok
        elif args.suite:
            for style in (["og", "modern", "classic"] if args.styles else [""]):
                os.environ["WICK_STYLE"] = style
                if style:
                    print(f"-- style {style}")
                ok = run(HERE + "/suite-harness.lua", mode, args.core, ANNIV_ADDONS, mode, stub) and ok
        elif args.gear:
            ok = run(HERE + "/gear-harness.lua", mode, args.core, BETA_ADDONS, mode, stub) and ok
        elif args.probe:
            probe = BETA_ADDONS + "/WicksProbe"
            ok = run(HERE + "/probe-verbs.lua", mode, probe, stub) and ok
            ok = run(HERE + "/probe-harness.lua", mode, probe, stub) and ok
        else:
            ok = run(HERE + "/harness.lua", mode, args.core, mode, stub) and ok
        print()
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
