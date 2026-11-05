"""Carry macros from one WoW install to another.

Written for Anniversary to the Forever beta, and kept because the same
move has to happen again at launch.

Macros live in macros-cache.txt, one file for the account and one per
character. The format is a header line, the body, and END:

    VER 3 0000000000000001 "water" "132793"
    #showtooltip
    /cast Conjure Water
    END

The id's top byte is the scope: 00 is an account macro, 01 is a
character one. The rest is a sequence within that scope, so anything
merged in has to be renumbered or the client drops the collision.

    python WickSuite/tools/import-macros.py            # say what it would do
    python WickSuite/tools/import-macros.py --apply    # do it

Nothing is written while the game is running: the client rewrites its
own WTF on the way out and would throw the import away.
"""
import argparse
import io
import os
import re
import shutil
import subprocess
import sys
import time

WOW = "C:/Program Files (x86)/World of Warcraft"
SRC = WOW + "/_anniversary_/WTF/Account/WICKIDSPLIFF"
DST = WOW + "/_forever_/WTF/Account/WICKIDSPLIFF"

# Character macros only make sense on a character of the same class, so
# the mapping is written down rather than guessed from a name at runtime.
# source character -> (class, destination character)
CHARACTERS = {
    "Nightslayer/Wickshift":  ("druid", "70/Druidica-Despliff"),
    "Nightslayer/Wickizard":  ("mage",  "70/Magica-Despliff"),
    "Nightslayer/Wickpocket": ("rogue", "70/Pocketlint-Despliff"),
    # Mystwick is a warlock and Wickisoholy a priest. There is no
    # character of either class on the beta, so they have nowhere to go.
}

HEADER = re.compile(r'^VER 3 ([0-9A-Fa-f]{16}) "(.*)" "(.*)"$')


def parse(path):
    """-> [(id, name, icon, [body lines])] in file order."""
    if not os.path.exists(path):
        return []
    out, cur = [], None
    for raw in io.open(path, encoding="utf-8", errors="replace").read().splitlines():
        m = HEADER.match(raw)
        if m:
            cur = (m.group(1).upper(), m.group(2), m.group(3), [])
            out.append(cur)
        elif raw == "END":
            cur = None
        elif cur is not None:
            cur[3].append(raw)
    return out


def render(entries):
    lines = []
    for mid, name, icon, body in entries:
        lines.append('VER 3 %s "%s" "%s"' % (mid, name, icon))
        lines.extend(body)
        lines.append("END")
    return "\n".join(lines) + "\n"


def renumber(entries, scope):
    """Hand out a fresh sequence within one scope, keeping file order."""
    out = []
    for i, (_, name, icon, body) in enumerate(entries, start=1):
        out.append(("%02X%s%012X" % (scope, "00", i), name, icon, body))
    return out


def merge(existing, incoming, scope):
    """Existing macros keep their place; a name already there is not
    overwritten, because the one already on this account is the one the
    player has been using."""
    have = set(n.lower() for _, n, _, _ in existing)
    added = [e for e in incoming if e[1].lower() not in have]
    skipped = [e[1] for e in incoming if e[1].lower() in have]
    return renumber(list(existing) + added, scope), added, skipped


def wow_running():
    try:
        out = subprocess.check_output(
            ["tasklist", "/FI", "IMAGENAME eq WowB.exe", "/FI", "IMAGENAME eq WowClassic.exe"],
            stderr=subprocess.STDOUT).decode("utf-8", "replace")
    except Exception:
        return False
    return ".exe" in out.lower()


def write(path, text, apply_it):
    if not apply_it:
        return
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if os.path.exists(path):
        shutil.copy2(path, path + ".bak-" + time.strftime("%Y%m%d-%H%M%S"))
    # The client writes these without a BOM and with Windows line ends.
    io.open(path, "w", encoding="utf-8", newline="\r\n").write(text)


def do_account(apply_it):
    src = parse(SRC + "/macros-cache.txt")
    dstpath = DST + "/macros-cache.txt"
    dst = parse(dstpath)
    merged, added, skipped = merge(dst, src, 0x00)
    print("Account (general) macros")
    print("  already there: %d  bringing over: %d" % (len(dst), len(added)))
    for _, name, _, _ in added:
        print("    + %s" % name)
    for name in skipped:
        print("    = %s (a macro of that name is already here, left alone)" % name)
    write(dstpath, render(merged), apply_it)
    return len(added)


def do_characters(apply_it):
    total = 0
    print("\nCharacter macros")
    for srcchar, (klass, dstchar) in sorted(CHARACTERS.items()):
        src = parse("%s/%s/macros-cache.txt" % (SRC, srcchar))
        if not src:
            continue
        dstpath = "%s/%s/macros-cache.txt" % (DST, dstchar)
        dst = parse(dstpath)
        merged, added, skipped = merge(dst, src, 0x01)
        print("  %s -> %s (%s): %d already there, %d brought over"
              % (srcchar.split("/")[-1], dstchar.split("/")[-1], klass, len(dst), len(added)))
        for _, name, _, _ in added:
            print("      + %s" % name)
        for name in skipped:
            print("      = %s (left alone)" % name)
        write(dstpath, render(merged), apply_it)
        total += len(added)
    return total


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true", help="write the files")
    args = ap.parse_args()

    if args.apply and wow_running():
        print("World of Warcraft is running. It rewrites its own WTF folder when")
        print("it exits, which would throw this away. Close the client and run")
        print("this again.")
        return 1

    if not os.path.isdir(SRC):
        print("No source account at %s" % SRC)
        return 1

    n = do_account(args.apply) + do_characters(args.apply)
    print("")
    if args.apply:
        print("Wrote %d macros. The old files are beside the new ones as .bak-<time>." % n)
    else:
        print("Dry run: %d macros would move. Add --apply to write them." % n)
    return 0


if __name__ == "__main__":
    sys.exit(main())
