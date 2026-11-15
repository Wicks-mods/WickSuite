"""Collect the loot tables of Forever's dungeons from Wowhead.

Wowhead's Forever database carries real stats and real drop sources, and a
dungeon's zone page embeds its drop list as JSON inside a Listview. That
is far kinder than scraping rendered pages: one read per dungeon, and the
fields come out typed.

    python WickSuite/tools/scrape-forever-dungeons.py --from-crawl data/forever/raw/<file>.json
    python WickSuite/tools/scrape-forever-dungeons.py --from-crawl <file> --only 1583

Writes WickSuite/data/forever/dungeon-loot.json.

Since the release (checked 2026-11-15) www.wowhead.com answers HTTP 403
to a plain request, so this can no longer fetch the pages itself. The
pages are read in a browser instead and their Listview rows saved as one
json file, zone id -> { title, drops, questRewards }, which --from-crawl
reads. Running without it still tries the network, and says so when it is
refused. Wowhead also puts up a human check after about 35 zone pages
read by script in a tab, so a crawl is a few pages at a time and never
worked around.

Stat values are not in the listview, only on each item's own tooltip, so
this collects the roster: what drops, from whom, at what item level and
for which slot. Stats are a second pass (scrape-forever-item-stats.py),
and the tooltip host still answers a plain request.
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

# Every dungeon in Forever's release, in the order of Wowhead's dungeon
# overview guide (wowhead.com/forever/guide/dungeons-overview-locations-details,
# updated 2026-11-15 for patch 1.60.1), which is also where the level
# ranges come from. They are Forever's own, not Classic's: most were
# retuned. Wowhead's database list (/forever/zones/instances) still shows
# some of the older ranges, and its roadmap guide gives the new dungeons
# slightly different ones; the dungeon guide is the newest of the three.
# A dungeon with wings carries the span of all of them.
#
# Zone ids are Wowhead's, read off /forever/zones/instances. Two to
# watch: the Temple of Atal'Hakkar is 1477 (1417, "Sunken Temple", is an
# empty page and is what this list asked for until 2026-11-15), and
# City of Dalaran has two ids, of which 16544 is the dungeon. 16560 hands
# out level 44 rewards, which no level 28 dungeon does, so it is left out
# until someone can say what it is.
#
# None means nothing is published, and a range is worked out from what
# the loot requires instead.
DUNGEONS = [
    (16919, "The Hall of Thanes",        "13-18"),   # new in Forever
    (2437,  "Ragefire Chasm",            "13-18"),
    (16611, "Ruins of Lordaeron",        "15-20"),   # new
    (718,   "Wailing Caverns",           "15-25"),
    (1581,  "The Deadmines",             "18-23"),
    (209,   "Shadowfang Keep",           "22-30"),
    (717,   "The Stockade",              "22-30"),
    (16732, "Excavation Site: Wetlands", "24-29"),   # new
    (719,   "Blackfathom Deeps",         "24-32"),
    (16544, "City of Dalaran",           "28-33"),   # new
    (796,   "Scarlet Monastery",         "28-45"),   # four wings, 28-38 to 35-45
    (721,   "Gnomeregan",                "29-38"),
    (491,   "Razorfen Kraul",            "30-40"),
    (16550, "The Drowned City",          "35-40"),   # new
    (16842, "Krol'dok Stronghold",       "40-45"),   # new
    (722,   "Razorfen Downs",            "40-50"),
    (1337,  "Uldaman",                   "42-52"),
    (1176,  "Zul'Farrak",                "44-54"),
    (2100,  "Maraudon",                  "45-57"),   # three wings, 45-53 to 48-57
    (16620, "Alcaz Prison",              "48-53"),   # new
    (1477,  "Temple of Atal'Hakkar",     "50-60"),
    (1584,  "Blackrock Depths",          "52-60"),
    (16554, "Blackmaw Hold",             "55-60"),   # new
    (1583,  "Blackrock Spire",           "55-60"),   # lower 55-60, upper 58-60
    (16667, "The Shaper's Terrace",      "58-60"),   # new; no loot on Wowhead yet
    (2557,  "Dire Maul",                 "58-60"),
    (2057,  "Scholomance",               "58-60"),
    (2017,  "Stratholme",                "58-60"),
    # On Wowhead's instance list but not in the release guide. Kept so a
    # later crawl notices if one of them fills in; the emitter drops
    # anything still empty.
    (16074, "Karazhan Crypts",           None),
    (15828, "The Burning of Andorhal",   None),
    (17191, "Manor Mistmantle",          None),
    (16632, "Half-Pint Tavern",          None),
    (16295, "The Scarab Dais",           None),
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
    out = {
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
    # Wowhead's faction flag (1 Alliance, 2 Horde) and class mask. Kept
    # in the json for whoever wants them; the addon's rows do not carry
    # either yet.
    if row.get("side"):
        out["side"] = row["side"]
    if row.get("reqclass"):
        out["reqClass"] = row["reqclass"]
    return out


def from_here(row, zone):
    """Whether a drop row really belongs to this dungeon.

    A zone page's drop list is fed by what players loot there, so it
    picks up world drops too: Staff of Jordan on Krol'dok Stronghold,
    Hibernal Armor in Blackrock Depths. Those rows carry no sourcemore at
    all. A real drop names the creature it comes from, or, when several
    creatures in the dungeon share it, the dungeon itself.
    """
    for sm in row.get("sourcemore") or []:
        if sm.get("n") or sm.get("z") == zone:
            return True
    return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", help="comma-separated zone ids; the rest of the file is left alone")
    ap.add_argument("--one", type=int, help="a single zone id, for a quick check")
    ap.add_argument("--from-crawl", action="append", default=[],
                    help="json saved from a browser: zone id -> { drops, questRewards }. "
                         "May be given more than once; a later file wins for a zone it holds.")
    args = ap.parse_args()

    crawl, crawl_date = {}, None
    for path in args.from_crawl:
        doc = json.loads(io.open(path, encoding="utf-8").read())
        crawl.update({int(k): v for k, v in (doc.get("zones") or {}).items()})
        crawl_date = max(crawl_date or "", doc.get("collected") or "")

    wanted = None
    if args.only:
        wanted = {int(z.strip()) for z in args.only.split(",") if z.strip()}
    elif args.one:
        wanted = {args.one}
    if crawl:
        # A crawl seldom holds every dungeon. The ones it lacks keep what
        # is on file instead of being asked for over a network that says no.
        wanted = (wanted & set(crawl)) if wanted else set(crawl)
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
        try:
            if crawl:
                raw_drops = crawl[zone].get("drops") or []
                raw_quests = crawl[zone].get("questRewards") or []
            else:
                if i:
                    time.sleep(PAUSE)
                html = fetch(zone)
                raw_drops = listview(html, "drops")
                raw_quests = listview(html, "quest-rewards")
        except urllib.error.HTTPError as exc:
            print("  %-26s FAILED: %s%s" % (name, exc, (
                "  (Wowhead refuses plain requests now; read the page in a "
                "browser and pass --from-crawl)") if exc.code == 403 else ""))
            continue
        except (urllib.error.URLError, ValueError, json.JSONDecodeError) as exc:
            print("  %-26s FAILED: %s" % (name, exc))
            continue
        strays = [r for r in raw_drops if (r.get("slot") and (r.get("quality") or 0) >= 2
                                           and not from_here(r, zone))]
        drops = [tidy(r) for r in raw_drops if from_here(r, zone)]
        quests = [tidy(r) for r in raw_quests]
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
        print("  %-26s %3d dropped, %3d from quests%s" % (
            name, len(d), len(q),
            ("   (%d world drops left out)" % len(strays)) if strays else ""))

    if wanted:
        # Only some were asked for, so keep what was already on file for
        # the rest. Writing just the scraped ones would quietly delete
        # the other thirteen dungeons.
        merged = dict(previous)
        merged.update(out)
        out = merged

    # Keep the file in run order whichever subset was scraped: the order
    # of the list above, which is the guide's, and anything the list no
    # longer names after that by the bottom of its range.
    place = {name: n for n, (_, name, _) in enumerate(DUNGEONS)}
    out = dict(sorted(out.items(), key=lambda kv: (
        place.get(kv[0], len(place)), level_key(kv[1].get("levels")))))

    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.normpath(os.path.join(OUT_DIR, "dungeon-loot.json"))
    io.open(path, "w", encoding="utf-8", newline="\n").write(
        json.dumps({
            "source": "wowhead.com/forever, zone drop listviews",
            "collected": crawl_date or time.strftime("%Y-%m-%d"),
            "note": ("Roster only; stat values live on each item's tooltip and need a "
                 "second pass. Wowhead's Forever data grows from what players "
                 "actually loot, so a new dungeon can be thin for a while. A drop is "
                 "kept only when its row names a creature or the dungeon as its source."),
            "dungeons": out,
        }, indent=2, ensure_ascii=False) + "\n")
    print("\n%d entries across %d dungeons, %d of them gear" % (total, len(out), equippable))
    print("Written to %s" % path)


if __name__ == "__main__":
    main()
