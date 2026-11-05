"""Bake the suite's current settings into an addon that loads them back.

On the Forever beta the client writes every addon's saved variables at
logout and hands back nothing at load. Addon files themselves load fine,
though, so this reads what the game wrote to WTF and generates
!WicksProfile, which puts those tables back before anything else starts.

Run it after logging out, from anywhere:

    python WickSuite/tools/make-profile.py
    python WickSuite/tools/make-profile.py --list     # what it would take

Log out first, or you will bake whatever was on disk before this session.
"""
import argparse
import io
import os
import re
import sys
import time

BETA = "C:/Program Files (x86)/World of Warcraft/_forever_"
ADDONS = BETA + "/Interface/AddOns"
TARGET = ADDONS + "/!WicksProfile"

# Ours only. Blizzard's own saved variables are left alone: several load
# before any addon does, so putting them back is not ours to attempt.
OURS = re.compile(r"^(WickCore|Wicks)[A-Za-z]*$")

# Not worth carrying. The probe's file is a pile of diagnostic reports and
# runs to hundreds of kilobytes.
SKIP = {"WicksProbeDB"}


def declared_globals():
    """Saved variables the installed addons actually declare.

    WTF keeps a file long after its addon is gone, and baking one back is
    how you end up carrying a setting for something you deleted.
    """
    names = set()
    if not os.path.isdir(ADDONS):
        return names
    for folder in os.listdir(ADDONS):
        toc = os.path.join(ADDONS, folder, folder + ".toc")
        if not os.path.isfile(toc):
            continue
        for line in io.open(toc, encoding="utf-8", errors="replace"):
            m = re.match(r"##\s*SavedVariables(?:PerCharacter)?\s*:\s*(.+)", line)
            if m:
                for n in m.group(1).split(","):
                    names.add(n.strip())
    return names


def account_dirs():
    root = BETA + "/WTF/Account"
    if not os.path.isdir(root):
        sys.exit("No WTF/Account folder. Is the beta client installed here?")
    return [os.path.join(root, d) for d in os.listdir(root)
            if os.path.isdir(os.path.join(root, d)) and not d.startswith("SavedVariables")]


def saved_files():
    """Every account-level saved-variable file belonging to the suite."""
    out = []
    for acct in account_dirs():
        sv = os.path.join(acct, "SavedVariables")
        if not os.path.isdir(sv):
            continue
        for name in sorted(os.listdir(sv)):
            if not name.endswith(".lua"):
                continue
            stem = name[:-4]
            if not OURS.match(stem):
                continue
            out.append(os.path.join(sv, name))
    return out


def globals_in(path):
    """The global names a saved-variable file assigns, in order.

    The client writes these one per file in a fixed shape: a name, then
    ' = {' at the start of a line. Anything else is inside a table.
    """
    text = io.open(path, encoding="utf-8").read()
    return re.findall(r"^([A-Za-z_][A-Za-z0-9_]*) = ", text, re.MULTILINE), text


def newest_write():
    """When the game last wrote any of the files we care about."""
    latest = 0.0
    for path in saved_files():
        try:
            latest = max(latest, os.path.getmtime(path))
        except OSError:
            pass
    return latest


def parses(path):
    """Refuse to ship a Profile.lua that will not load.

    The game rewrites these files in place, so a bake taken mid-write can
    catch a half-finished table. Cheap to check, and the alternative is an
    addon that errors at load.
    """
    try:
        import lupa
    except ImportError:
        return True     # no checker available; the bake is no worse than before
    try:
        lupa.LuaRuntime().execute(io.open(path, encoding="utf-8").read())
        return True
    except Exception as exc:
        print("  generated file does not load, keeping the previous one:", exc)
        return False


def watch():
    """Re-bake whenever the game writes, so the snapshot never goes stale.

    The game writes its saved variables at logout and at every reload. A
    stale bake does not merely miss changes, it puts the old values back
    over them, so keeping this running is the difference between the
    profile helping and fighting.
    """
    import shutil
    target = TARGET + "/Profile.lua"
    print("Watching for settings the game writes. Ctrl-C to stop.")
    last = newest_write()
    print("  current bake is %s" % (time.strftime("%H:%M:%S", time.localtime(
        os.path.getmtime(target))) if os.path.exists(target) else "missing"))
    while True:
        time.sleep(2)
        now = newest_write()
        if now <= last:
            continue
        # Let the client finish. A write that is still moving is not done.
        settle = now
        while True:
            time.sleep(1.5)
            again = newest_write()
            if again == settle:
                break
            settle = again
        last = settle
        backup = target + ".prev"
        if os.path.exists(target):
            shutil.copyfile(target, backup)
        try:
            bake(quiet=True)
        except Exception as exc:
            print("  bake failed:", exc)
            continue
        if not parses(target) and os.path.exists(backup):
            shutil.copyfile(backup, target)
            continue
        print("  re-baked at %s" % time.strftime("%H:%M:%S"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true", help="show what would be baked and stop")
    ap.add_argument("--watch", action="store_true",
                    help="stay running and re-bake whenever the game writes new settings")
    args = ap.parse_args()

    if args.watch:
        watch()
        return

    bake(list_only=args.list)


def bake(list_only=False, quiet=False):
    files = saved_files()
    if not files:
        sys.exit("Nothing found. Log out at least once so the game writes its files.")

    live = declared_globals()
    chunks, taken, skipped = [], [], []
    for path in files:
        names, text = globals_in(path)
        keep = [n for n in names if n not in SKIP and n in live]
        for n in names:
            if n not in SKIP and n not in live:
                skipped.append((n, "no installed addon declares it"))
        if not keep:
            skipped.append((os.path.basename(path), "nothing to keep"))
            continue
        # Point each assignment at our staging table instead of the global,
        # so loading this file does not overwrite anything by itself.
        body = text
        for n in names:
            if n not in keep:
                # Drop the whole assignment rather than stage it.
                body = re.sub(r"^%s = \{.*?^\}\n" % re.escape(n), "", body,
                              flags=re.MULTILINE | re.DOTALL)
                continue
            body = re.sub(r"^%s = " % re.escape(n), 'WicksProfileData["%s"] = ' % n,
                          body, count=1, flags=re.MULTILINE)
        chunks.append("-- from %s\n%s" % (os.path.basename(path), body.rstrip()))
        taken.extend(keep)

    if list_only:
        print("Would bake %d globals from %d files:" % (len(taken), len(chunks)))
        for n in sorted(taken):
            print("   ", n)
        for name, why in skipped:
            print("    (skipped %s: %s)" % (name, why))
        return

    os.makedirs(TARGET, exist_ok=True)
    # Ship the addon's fixed parts too, so the whole thing is reproducible
    # from this repo rather than existing only on one machine.
    here = os.path.dirname(os.path.abspath(__file__))
    for fixed in ("Loader.lua", "!WicksProfile.toc"):
        src = os.path.join(here, "wicksprofile", fixed)
        if os.path.isfile(src):
            io.open(os.path.join(TARGET, fixed), "w", encoding="utf-8", newline="\n").write(
                io.open(src, encoding="utf-8").read())

    stamp = time.strftime("%Y-%m-%d %H:%M")
    header = (
        "-- Generated by WickSuite/tools/make-profile.py on %s.\n"
        "-- Do not edit: run the script again after changing settings in game.\n"
        "--\n"
        "-- These are the suite's saved variables as the game last wrote them.\n"
        "-- They are staged here rather than assigned, and Loader.lua puts\n"
        "-- back only the ones the client did not supply itself.\n\n"
        "WicksProfileStamp = \"%s\"\n"
        "WicksProfileData = {}\n\n" % (stamp, stamp))
    io.open(TARGET + "/Profile.lua", "w", encoding="utf-8", newline="\n").write(
        header + "\n\n".join(chunks) + "\n")

    if quiet:
        return
    print("Baked %d globals from %d files into %s/Profile.lua"
          % (len(taken), len(chunks), TARGET))
    for n in sorted(taken):
        print("   ", n)
    print("\nReload in game and the settings come back.")


if __name__ == "__main__":
    main()
