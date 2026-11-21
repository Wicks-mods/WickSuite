"""Collect the quest rewards worth crossing a zone for.

Wowhead's item database has a Quest criterion, but it means quest *item*,
the grey thing in your bag: 314 rows, not one of them with an equip slot.
What is wanted is the other thing, rewards handed out for finishing a
quest, and those live on each zone's page in a `quest-rewards` listview,
exactly like the dungeon loot does.

So this walks the outdoor zones the way the dungeon scrape walks the
instances. One request per zone.

    python WickSuite/tools/scrape-forever-questrewards.py --from-crawl data/forever/raw/<file>.json

Writes WickSuite/data/forever/quest-rewards.json.

Since the release (checked 2026-11-15) www.wowhead.com answers HTTP 403
to a plain request, so the pages are read in a browser and saved as one
json file, which --from-crawl reads. Without it this still tries the
network and fails.
A crawl saved for this tool usually holds rare and better only, so
--min 2 needs a crawl that kept the greens.

Blue and above by default. A zone hands out dozens of greens and they are
not worth planning a route around; a blue is. Pass --min to widen it.
"""
import argparse
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
OUT_DIR = os.path.join(HERE, "..", "data", "forever")
OUT = os.path.join(OUT_DIR, "quest-rewards.json")
UA = "Wicksmods BIS data collector (https://github.com/Wicksmods)"
PAUSE = 1.5

# The outdoor levelling zones, both factions and the shared ones. Zone
# ids are Wowhead's. Instances are deliberately absent: the dungeon
# scrape already has their quest rewards and would double them up.
#
# Reviewed against wowhead.com/forever/zones on 2026-11-15, after the
# release: the four new zones (Zephras Isle, Riverglades, Shen'dralas,
# Mount Hyjal), Alterac Mountains and the other four capitals joined, and
# zone 33 is Stranglethorn Vale, one zone, not the northern half.
ZONES = [
    (16593, "Zephras Isle"),     (16591, "Riverglades"),
    (16651, "Shen'dralas"),      (616,  "Mount Hyjal"),
    (36,   "Alterac Mountains"), (1537, "Ironforge"),
    (1638, "Thunder Bluff"),     (1497, "Undercity"),
    (1657, "Darnassus"),
    (1,    "Dun Morogh"),        (3,    "Badlands"),
    (4,    "Blasted Lands"),     (8,    "Swamp of Sorrows"),
    (10,   "Duskwood"),          (11,   "Wetlands"),
    (12,   "Elwynn Forest"),     (14,   "Durotar"),
    (15,   "Dustwallow Marsh"),  (16,   "Azshara"),
    (17,   "The Barrens"),       (28,   "Western Plaguelands"),
    (33,   "Stranglethorn Vale"), (38,   "Loch Modan"),
    (40,   "Westfall"),          (41,   "Deadwind Pass"),
    (44,   "Redridge Mountains"),(45,   "Arathi Highlands"),
    (46,   "Burning Steppes"),   (47,   "The Hinterlands"),
    (51,   "Searing Gorge"),     (85,   "Tirisfal Glades"),
    (130,  "Silverpine Forest"), (139,  "Eastern Plaguelands"),
    (141,  "Teldrassil"),        (148,  "Darkshore"),
    (215,  "Mulgore"),           (267,  "Hillsbrad Foothills"),
    (331,  "Ashenvale"),         (357,  "Feralas"),
    (361,  "Felwood"),           (400,  "Thousand Needles"),
    (405,  "Desolace"),          (406,  "Stonetalon Mountains"),
    (440,  "Tanaris"),           (490,  "Un'Goro Crater"),
    (493,  "Moonglade"),         (618,  "Winterspring"),
    (1377, "Silithus"),          (1519, "Stormwind City"),
    (1637, "Orgrimmar"),
]


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=45) as r:
        return r.read().decode("utf-8", "replace")


def array_at(text, start):
    """The bracketed array beginning at start, brackets balanced."""
    depth, i = 0, start
    while i < len(text):
        if text[i] == "[":
            depth += 1
        elif text[i] == "]":
            depth -= 1
            if depth == 0:
                return text[start:i + 1]
        i += 1
    raise ValueError("unbalanced array")


def quest_rewards(html):
    for m in re.finditer(r"template:\s*'item'", html):
        seg = html[m.start():m.start() + 600]
        if "id: 'quest-rewards'" not in seg:
            continue
        d = html.index("data:", m.start())
        return json.loads(array_at(html, html.index("[", d)))
    return []


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--min", type=int, default=3,
                    help="lowest quality to keep; 3 is rare (blue), 2 uncommon")
    ap.add_argument("--one", type=int, help="a single zone id, for a quick look")
    ap.add_argument("--from-crawl",
                    help="json saved from a browser: zones -> zone id -> { questRewards }")
    args = ap.parse_args()

    crawl, crawl_date = None, None
    if args.from_crawl:
        doc = json.loads(io.open(args.from_crawl, encoding="utf-8").read())
        crawl = {int(k): v for k, v in (doc.get("zones") or {}).items()}
        crawl_date = doc.get("collected")

    zones = [(z, n) for z, n in ZONES if not args.one or z == args.one]
    out, kept, seen = {}, 0, 0

    for zid, name in zones:
        print("  %-26s " % name, end="", flush=True)
        if crawl is not None:
            if zid not in crawl:
                print("not in the crawl")
                continue
            rows = crawl[zid].get("questRewards") or []
            seen += (crawl[zid].get("questRewardsSeen") or len(rows)) - len(rows)
        else:
            try:
                rows = quest_rewards(get("https://www.wowhead.com/forever/zone=%d" % zid))
            except (urllib.error.URLError, TimeoutError, ValueError, json.JSONDecodeError) as exc:
                print("failed: %s" % exc)
                continue

        seen += len(rows)
        good = []
        for r in rows:
            if (r.get("quality") or 0) < args.min:
                continue
            # No slot means it is not something you wear, so it is not a
            # reward worth routing a levelling path around.
            if not r.get("slot"):
                continue
            row = {
                "id": r["id"],
                "name": r.get("name") or "",
                "quality": r.get("quality"),
                "slotId": r.get("slot"),
                "ilvl": r.get("level"),
                "reqLevel": r.get("reqlevel"),
                "cls": r.get("classs"),
                "sub": r.get("subclass"),
            }
            # Wowhead's faction flag (1 Alliance, 2 Horde, 3 both) and class
            # mask, when the row has them. A reward from the other faction's
            # quest is not one to send a player after.
            if r.get("side"):
                row["side"] = r["side"]
            if r.get("reqclass"):
                row["reqClass"] = r["reqclass"]
            good.append(row)

        if good:
            out[name] = {"zoneId": zid, "rewards": good}
        kept += len(good)
        print("%3d rewards, %2d kept" % (
            (crawl[zid].get("questRewardsSeen") or len(rows)) if crawl is not None else len(rows),
            len(good)))
        if crawl is None:
            time.sleep(PAUSE)

    index = {}
    for zone, d in out.items():
        for r in d["rewards"]:
            index[str(r["id"])] = zone

    os.makedirs(OUT_DIR, exist_ok=True)
    io.open(OUT, "w", encoding="utf-8", newline="\n").write(json.dumps({
        "source": "wowhead.com/forever zone pages, quest-rewards listviews",
        "collected": crawl_date or datetime.date.today().isoformat(),
        "note": "outdoor zones only; the dungeon scrape already holds instance quest rewards",
        "minQuality": args.min,
        "zones": out,
        "index": index,
    }, indent=1, ensure_ascii=False) + "\n")

    print()
    print("%d zones, %d rewards seen, %d kept at quality %d and above"
          % (len(out), seen, kept, args.min))
    print("wrote %s" % os.path.normpath(OUT))


if __name__ == "__main__":
    sys.exit(main())
