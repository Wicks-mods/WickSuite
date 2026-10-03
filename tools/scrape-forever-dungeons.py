"""Collect the loot tables of Forever's levelling dungeons from Wowhead.

Wowhead's Forever database carries real stats and real drop sources, and a
dungeon's zone page embeds its drop list as JSON inside a Listview. That
is far kinder than scraping rendered pages: one request per dungeon, no
browser, and the fields come out typed.

    python WickSuite/tools/scrape-forever-dungeons.py
    python WickSuite/tools/scrape-forever-dungeons.py --one 1581

Writes WickSuite/data/forever/dungeon-loot.json.

Stat values are not in the listview, only on each item's own tooltip, so
this collects the roster: what drops, from whom, at what item level and
for which slot. Stats are a second pass, deliberately separate so this
one stays a single cheap request per dungeon.
"""
import argparse
import io
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(HERE, "..", "data", "forever")
UA = "Wicksmods BIS data collector (https://github.com/Wicksmods)"
PAUSE = 1.5      # be a good guest; this is someone else's bandwidth

# Every five-player dungeon Forever has, from
# wowhead.com/forever/zones/instances. That page is rendered by script so
# it cannot be fetched here; it was read once in a browser and the ids
# written down. Re-read it when the beta adds dungeons, which it does:
# this list was hand-written from Classic knowledge to begin with and was
# missing Ruins of Lordaeron, the Hall of Thanes, Karazhan Crypts, and
# all four of Dire Maul, Stratholme, Scholomance and Blackrock Depths.
#
# Level ranges are Forever's own, not Classic's; several have been
# retuned. None means Wowhead does not give one yet, and a range is
# worked out from what the loot requires instead.
#
# Zones with nothing in them are kept on purpose. Wowhead's Forever data
# is crowdsourced, so an empty dungeon today is a filled one later, and
# the emitter drops anything still empty.
DUNGEONS = [
    (2437,  "Ragefire Chasm",          "15-25"),
    (1581,  "The Deadmines",           "15-25"),
    (718,   "Wailing Caverns",         "17-27"),
    (209,   "Shadowfang Keep",         "22-30"),
    (719,   "Blackfathom Deeps",       "22-32"),
    (717,   "The Stockade",            "22-32"),
    (721,   "Gnomeregan",              "26-36"),
    (796,   "Scarlet Monastery",       "26-45"),
    (491,   "Razorfen Kraul",          "32-42"),
    (722,   "Razorfen Downs",          "37-47"),
    (1337,  "Uldaman",                 "42-52"),
    (2100,  "Maraudon",                "42-52"),
    (2557,  "Dire Maul",               "44-54"),
    (1176,  "Zul'Farrak",              "46-56"),
    (2017,  "Stratholme",              "48-58"),
    (1417,  "Temple of Atal'Hakkar",   "50-60"),
    (1584,  "Blackrock Depths",        "52-60"),
    (1583,  "Blackrock Spire",         "55-60"),
    (2057,  "Scholomance",             "55-60"),
    # New in Forever. No level range published yet.
    (16611, "Ruins of Lordaeron",      None),
    (16919, "The Hall of Thanes",      None),
    (16074, "Karazhan Crypts",         None),
    (16732, "Excavation Site: Wetlands", None),
    (15828, "The Burning of Andorhal", None),
    (17191, "Manor Mistmantle",        None),
    (16632, "Half-Pint Tavern",        None),
    (16295, "The Scarab Dais",         None),
    (16544, "City of Dalaran",         None),
]

# Sort key for "the order you would actually run them": the bottom of the
# level range, and anything without one last.
def level_key(levels):
    if not levels:
        return (1, 0)
    try:
        return (0, int(str(levels).split("-")[0]))
    except ValueError:
        return (1, 0)


# Wowhead's slot numbering, for the slots a levelling character cares
# about. Anything not here is a bag, a reagent or similar.
SLOTS = {
    1: "Head", 2: "Neck", 3: "Shoulder", 4: "Shirt", 5: "Chest", 6: "Waist",
    7: "Legs", 8: "Feet", 9: "Wrist", 10: "Hands", 11: "Finger", 12: "Trinket",
    13: "One-Hand", 14: "Shield", 15: "Ranged", 16: "Back", 17: "Two-Hand",
    20: "Chest", 21: "Main Hand", 22: "Off Hand", 23: "Held in Off-hand",
    25: "Thrown", 26: "Ranged", 28: "Relic",
}
QUALITY = { 0: "poor", 1: "common", 2: "uncommon", 3: "rare", 4: "epic", 5: "legendary" }


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode("utf-8", "replace")


def fetch(zone_id):
    return get("https://www.wowhead.com/forever/zone=%d" % zone_id)


def extract_json_array(text, start):
    """Read one balanced [...] beginning at start, respecting strings."""
    assert text[start] == "["
    depth, i, in_str, esc = 0, start, False, False
    while i < len(text):
        c = text[i]
        if in_str:
            if esc:
                esc = False
            elif c == "\\":
                esc = True
            elif c == '"':
                in_str = False
        else:
            if c == '"':
                in_str = True
            elif c in "[{":
                depth += 1
            elif c in "]}":
                depth -= 1
                if depth == 0:
                    return text[start:i + 1]
        i += 1
    raise ValueError("unterminated array")


def listview(html, want):
    """One item Listview off a zone page, by its id.

    A zone page carries several: 'drops' is what the bosses and trash
    give up, 'quest-rewards' is what you are handed for finishing
    something there. Both are gear you would plan around.
    """
    for m in re.finditer(r"template:\s*'item'", html):
        seg = html[m.start():m.start() + 600]
        if ("id: '%s'" % want) not in seg:
            continue
        d = html.index("data:", m.start())
        bracket = html.index("[", d)
        return json.loads(extract_json_array(html, bracket))
    return []


# Walking each creature's own page was tried and is not worth it. The
# zone page carries a curated list; a creature page carries everything it
# has ever been seen to drop, which is overwhelmingly world drops. For
# Uldaman that turned seven items into five hundred, and filtering out
# Wowhead's commondrop flag and anything under a one percent rate still
# left forty-five, of which two were actually Uldaman loot. The rest were
# world greens: Hibernal, Chromite, Gothic Plate, Champion's.
#
# A thin dungeon here means the data has not been recorded yet, not that
# the zone page is hiding it. Archaedas lists sixty-three drops and none
# of them are his real table. Re-run this later instead.


def tidy(row):
    slot = row.get("slot") or 0
    sources = []
    for sm in row.get("sourcemore") or []:
        if sm.get("n"):
            sources.append(sm["n"])
    return {
        "id": row.get("id"),
        "name": row.get("name") or row.get("displayName"),
        "ilvl": row.get("level"),
        "reqLevel": row.get("reqlevel"),
        "quality": QUALITY.get(row.get("quality"), str(row.get("quality"))),
        "slot": SLOTS.get(slot),
        "slotId": slot,
        "itemClass": row.get("classs"),
        "itemSubclass": row.get("subclass"),
        "dps": row.get("dps") or None,
        "speed": row.get("speed") or None,
        "droppedBy": sources,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", help="comma-separated zone ids; the rest of the file is left alone")
    ap.add_argument("--one", type=int, help="a single zone id, for a quick check")
    args = ap.parse_args()

    wanted = None
    if args.only:
        wanted = {int(z.strip()) for z in args.only.split(",") if z.strip()}
    elif args.one:
        wanted = {args.one}
    targets = [d for d in DUNGEONS if d[0] in wanted] if wanted else DUNGEONS
    if not targets:
        sys.exit("No dungeon in the list with that zone id.")

    # Keep any stats already fetched: re-running the roster should not
    # silently undo three minutes of tooltip requests.
    known, previous = {}, {}
    existing_path = os.path.normpath(os.path.join(OUT_DIR, "dungeon-loot.json"))
    if os.path.exists(existing_path):
        prev = json.loads(io.open(existing_path, encoding="utf-8").read())
        previous = prev.get("dungeons", {})
        for dung in previous.values():
            for bucket in ("drops", "questRewards", "items"):
                for it in dung.get(bucket, []):
                    if it.get("id") and it.get("stats"):
                        known[it["id"]] = it["stats"]

    out, total, equippable = {}, 0, 0
    for i, (zone, name, levels) in enumerate(targets):
        if i:
            time.sleep(PAUSE)
        try:
            html = fetch(zone)
            drops = [tidy(r) for r in listview(html, "drops")]
            quests = [tidy(r) for r in listview(html, "quest-rewards")]
        except (urllib.error.URLError, ValueError, json.JSONDecodeError) as exc:
            print("  %-24s FAILED: %s" % (name, exc))
            continue
        # Gear only. The rest is cloth, recipes and vendor trash.
        def gear_only(items):
            g = [i for i in items
                 if i["slot"] and i["quality"] in ("uncommon", "rare", "epic", "legendary")]
            g.sort(key=lambda i: (i["slot"], -(i["ilvl"] or 0)))
            return g

        for lst in (drops, quests):
            for it in lst:
                if it["id"] in known:
                    it["stats"] = known[it["id"]]

        d, q = gear_only(drops), gear_only(quests)
        # An empty answer never erases what is on file. A new dungeon's
        # bosses can be known from their own tooltips before Wowhead's
        # zone page lists a single drop (Excavation Site, 2026-10-03), and
        # a re-run must not throw that away because the page is still bare.
        was = previous.get(name) or {}
        if not d and was.get("drops"):
            d = was["drops"]
            print("  %-24s zone page has no drops; keeping the %d on file" % (name, len(d)))
        if not q and was.get("questRewards"):
            q = was["questRewards"]
        # Nothing published, so say what the loot itself asks for rather
        # than leaving the column blank.
        derived = False
        if not levels:
            reqs = [i["reqLevel"] for i in d + q if i.get("reqLevel")]
            if reqs:
                levels, derived = "%d-%d" % (min(reqs), max(reqs)), True
        entry = { "zoneId": zone, "levels": levels or "", "drops": d, "questRewards": q }
        if derived:
            entry["levelsDerived"] = True
        if was.get("dropsNote"):
            entry["dropsNote"] = was["dropsNote"]
        out[name] = entry
        total += len(drops) + len(quests)
        equippable += len(d) + len(q)
        print("  %-24s %3d dropped, %3d from quests" % (name, len(d), len(q)))

    if wanted:
        # Only some were asked for, so keep what was already on file for
        # the rest. Writing just the scraped ones would quietly delete
        # the other thirteen dungeons.
        merged = dict(previous)
        merged.update(out)
        out = merged

    # Keep the file in run order whichever subset was scraped.
    out = dict(sorted(out.items(), key=lambda kv: level_key(kv[1].get("levels"))))

    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.normpath(os.path.join(OUT_DIR, "dungeon-loot.json"))
    io.open(path, "w", encoding="utf-8", newline="\n").write(
        json.dumps({
            "source": "wowhead.com/forever, zone drop listviews",
            "collected": time.strftime("%Y-%m-%d"),
            "note": ("Roster only; stat values live on each item's tooltip and need a "
                 "second pass. Coverage is uneven, because Wowhead's Forever data "
                 "grows from what players actually see: the early dungeons are well "
                 "filled in and the later ones are thin. Re-run as the beta goes on."),
            "dungeons": out,
        }, indent=2, ensure_ascii=False) + "\n")
    print("\n%d entries across %d dungeons, %d of them gear" % (total, len(out), equippable))
    print("Written to %s" % path)


if __name__ == "__main__":
    main()
