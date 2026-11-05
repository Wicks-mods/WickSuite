"""Set bonuses, from Classic, because Forever has none published yet.

Wowhead's Forever set tooltip carries the name and nothing else: 106
characters, no pieces, no bonuses. The Classic tooltip for the same set
id is complete, in a clean "N pieces: effect" form.

These are the same sets carried forward, so Classic is the best source
there is. It is not authority. The dungeon scrape already had to note
that Forever retuned level brackets Classic had, and a bonus is just as
retunable, so every line collected here is marked as Classic sourced and
the addon says so rather than presenting it as this build's own.

    python WickSuite/tools/scrape-set-bonuses.py

Writes WickSuite/data/forever/set-bonuses.json, for the sets the gear
data actually carries and no others: there are 528 sets and we ship 37.
"""
import datetime
import io
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "..", "data", "forever")
ADDON = ("C:/Program Files (x86)/World of Warcraft/_forever_/Interface/"
         "AddOns/WicksGear")
OUT = os.path.join(DATA, "set-bonuses.json")
UA = "Wicksmods BIS data collector (https://github.com/Wicksmods)"
PAUSE = 1.0


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode("utf-8", "replace")


def carried():
    """Set names the emitted gear data actually tags items with."""
    names = set()
    for f in ("Data.lua", "DataCrafted.lua", "DataQuests.lua"):
        p = os.path.join(ADDON, f)
        if os.path.exists(p):
            names |= set(re.findall(r'set = "([^"]+)"',
                                    io.open(p, encoding="utf-8").read()))
    return names


def bonuses(tooltip):
    """"N pieces: effect" out of the tooltip html."""
    text = re.sub(r"<[^>]+>", "\n", tooltip)
    text = re.sub(r"\n+", "\n", text).strip()
    out = []
    for m in re.finditer(r"(\d+)\s+pieces?:\s*\n?([^\n]+)", text):
        effect = m.group(2).strip()
        if effect:
            out.append({"pieces": int(m.group(1)), "text": effect})
    return out


def main():
    index = json.loads(io.open(os.path.join(DATA, "item-sets.json"),
                               encoding="utf-8").read())
    want = carried()
    ids = {v["name"]: k for k, v in index["sets"].items() if v["name"] in want}
    print("gear data tags %d sets; %d have an id" % (len(want), len(ids)))

    out, missing = {}, []
    for name in sorted(ids):
        sid = ids[name]
        try:
            raw = get("https://nether.wowhead.com/classic/tooltip/item-set/%s" % sid)
            rows = bonuses(json.loads(raw).get("tooltip") or "")
        except (urllib.error.URLError, TimeoutError, ValueError,
                json.JSONDecodeError) as exc:
            print("  %-34s failed: %s" % (name, exc))
            time.sleep(PAUSE)
            continue
        if rows:
            out[name] = {"setId": int(sid), "bonuses": rows}
            print("  %-34s %d bonuses" % (name, len(rows)))
        else:
            missing.append(name)
            print("  %-34s none published" % name)
        time.sleep(PAUSE)

    io.open(OUT, "w", encoding="utf-8", newline="\n").write(json.dumps({
        "source": "nether.wowhead.com/classic tooltip endpoint",
        "collected": datetime.date.today().isoformat(),
        "note": ("Classic's bonuses, not Forever's. Forever publishes none yet: "
                 "its set tooltip carries the name and nothing else. Forever has "
                 "retuned things Classic had before, so treat these as a guide "
                 "and say so wherever they are shown."),
        "approximate": True,
        "sets": out,
        "withoutBonuses": missing,
    }, indent=1, ensure_ascii=False) + "\n")

    print()
    print("%d sets with bonuses, %d without" % (len(out), len(missing)))
    print("wrote %s" % os.path.normpath(OUT))


if __name__ == "__main__":
    sys.exit(main())
