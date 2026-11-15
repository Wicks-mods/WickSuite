"""Add stat values to the dungeon loot roster.

The zone listviews give the roster but not the numbers. Wowhead has a
tooltip endpoint that returns one item as a small JSON blob, which is far
lighter than pulling the whole item page, so this reads the stats one
item at a time. It is also the check that an id is a real Forever item:
an id with no tooltip does not go into the addon.

    python WickSuite/tools/scrape-forever-item-stats.py              read what is missing, then apply
    python WickSuite/tools/scrape-forever-item-stats.py --refresh    read every item again
    python WickSuite/tools/scrape-forever-item-stats.py --fetch-only fill the cache, leave the roster alone
    python WickSuite/tools/scrape-forever-item-stats.py --apply-only write the cache into the roster

What a tooltip said is kept in WickSuite/data/forever/item-tooltips.json,
item id -> { name, itemLevel, requiresLevel, droppedBy, stats, read },
so the roster can be rebuilt from a new crawl without asking for 1,500
tooltips again, and so each number has a date beside it. Applying writes
a "stats" object onto each entry of dungeon-loot.json. It is safe to stop
a read and run it again: the cache is saved every fifty items.

Stats read during the beta are not trusted after the release, because
Forever retunes items between builds. --refresh is how they are replaced.
"""
import argparse
import html as htmllib
import io
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.normpath(os.path.join(HERE, "..", "data", "forever", "dungeon-loot.json"))
CACHE = os.path.normpath(os.path.join(HERE, "..", "data", "forever", "item-tooltips.json"))
UA = "Wicksmods BIS data collector (https://github.com/Wicksmods)"
PAUSE = 1.5      # someone else's bandwidth

# What a levelling character is actually choosing between. Spell power and
# the rest of the Burning Crusade vocabulary barely exists at this level,
# so the list stays short on purpose.
PRIMARY = ("Strength", "Agility", "Stamina", "Intellect", "Spirit")


def tooltip(item_id):
    url = "https://nether.wowhead.com/forever/tooltip/item/%d" % item_id
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.loads(r.read().decode("utf-8", "replace"))


def parse(tip):
    """Pull numbers out of the tooltip markup.

    Wowhead's tooltip is HTML rather than structured stats, so this reads
    it the way a person would: the plus-N lines, armour, and the weapon
    header. Anything it does not recognise is left out rather than
    guessed at.
    """
    # Comments and inline spans sit mid-sentence: a rating is written
    # "+<!--rtg38-->10 Attack Power" and a spell power value is wrapped in
    # its own span. Those vanish and only the block tags break a line,
    # or every Equip line loses its number.
    text = tip.get("tooltip") or ""
    text = re.sub(r"<!--.*?-->", "", text)
    text = re.sub(r"<(?:br|/?(?:div|table|tr|td|th|p))\b[^>]*>", "\n", text)
    text = re.sub(r"<[^>]+>", "", text)
    text = htmllib.unescape(text)
    stats = {}

    for name in PRIMARY:
        m = re.search(r"([+-]\d+)\s+%s\b" % name, text)
        if m:
            stats[name.lower()] = int(m.group(1))

    m = re.search(r"(\d+)\s+Armor\b", text)
    if m:
        stats["armor"] = int(m.group(1))

    for school in ("Arcane", "Fire", "Nature", "Frost", "Shadow"):
        m = re.search(r"([+-]\d+)\s+%s Resistance" % school, text)
        if m:
            stats[school.lower() + "Res"] = int(m.group(1))

    # Weapons: the damage range and speed sit together in the header.
    m = re.search(r"(\d+)\s*-\s*(\d+)\s+Damage", text)
    if m:
        stats["minDamage"], stats["maxDamage"] = int(m.group(1)), int(m.group(2))
    m = re.search(r"Speed\s+([\d.]+)", text)
    if m:
        stats["speed"] = float(m.group(1))
    m = re.search(r"\(([\d.]+)\s+damage per second\)", text)
    if m:
        stats["dps"] = float(m.group(1))

    # Anything on an Equip line is worth keeping verbatim: at this level it
    # is usually spell damage or a regen effect, and parsing every phrasing
    # would be guesswork.
    equips = [l.strip() for l in text.split("\n") if l.strip().startswith("Equip:")]
    if equips:
        stats["equip"] = equips

    return stats


def read_one(item_id):
    """One cache record: what the tooltip says about this id, and when."""
    tip = tooltip(item_id)
    raw = tip.get("tooltip") or ""
    rec = {"name": tip.get("name"), "stats": parse(tip), "read": time.strftime("%Y-%m-%d")}
    # The level lines are marked in the markup itself, which is steadier
    # than matching the words around them.
    m = re.search(r"<!--ilvl-->(\d+)", raw)
    if m:
        rec["itemLevel"] = int(m.group(1))
    m = re.search(r"<!--rlvl-->(\d+)", raw)
    if m:
        rec["requiresLevel"] = int(m.group(1))
    # Some tooltips name the one creature that drops the piece. Useful
    # where the zone page only says "somewhere in this dungeon".
    m = re.search(r'whtt-droppedby">Dropped by:\s*([^<]+)<', raw)
    if m:
        rec["droppedBy"] = htmllib.unescape(m.group(1)).strip()
    return rec


def roster_items(doc):
    for dungeon in doc["dungeons"].values():
        for bucket in ("drops", "questRewards"):
            for item in dungeon.get(bucket, []):
                if item.get("id"):
                    yield item


def save(path, doc, indent):
    io.open(path, "w", encoding="utf-8", newline="\n").write(
        json.dumps(doc, indent=indent, ensure_ascii=False, sort_keys=(indent == 1)) + "\n")


def fetch(doc, cache, refresh):
    today = time.strftime("%Y-%m-%d")
    ids, seen = [], set()
    for item in roster_items(doc):
        iid = item["id"]
        if iid in seen:
            continue
        seen.add(iid)
        rec = cache["items"].get(str(iid))
        # A refresh rereads everything not already read today, so a run
        # that was stopped picks up where it left off.
        if rec and (not refresh or rec.get("read") == today) and not rec.get("failed"):
            continue
        ids.append(iid)

    if not ids:
        print("Every item in the roster has a tooltip on file.")
        return
    print("Reading %d tooltips, about %d minutes." % (len(ids), len(ids) * (PAUSE + 0.4) / 60))
    done = failed = missing = 0
    for i, iid in enumerate(ids):
        if i:
            time.sleep(PAUSE)
        try:
            cache["items"][str(iid)] = read_one(iid)
            done += 1
        except urllib.error.HTTPError as exc:
            # Not found is an answer, not a failure: the id is not an
            # item Forever has, so it must not ship.
            if exc.code == 404:
                cache["items"][str(iid)] = {"missing": True, "read": today}
                missing += 1
                print("   %d has no tooltip (404)" % iid)
            else:
                cache["items"].setdefault(str(iid), {})["failed"] = str(exc)
                failed += 1
                print("   %d failed: %s" % (iid, exc))
        except (urllib.error.URLError, json.JSONDecodeError, TimeoutError, OSError) as exc:
            cache["items"].setdefault(str(iid), {})["failed"] = str(exc)
            failed += 1
            print("   %d failed: %s" % (iid, exc))
        if (i + 1) % 50 == 0:
            print("   %d of %d" % (i + 1, len(ids)), flush=True)
            save(CACHE, cache, 1)
    cache["collected"] = today
    save(CACHE, cache, 1)
    print("Read %d, not found %d, failed %d." % (done, missing, failed))


def apply(doc, cache):
    """Write what the tooltips said onto the roster.

    The tooltip wins over the listview for item level and required
    level, since it is the item's own page rather than a list row, and
    every disagreement is printed so it can be looked at.
    """
    filled = bare = differ = 0
    for item in roster_items(doc):
        rec = cache["items"].get(str(item["id"]))
        if not rec or rec.get("missing") or "stats" not in rec:
            item.pop("stats", None)
            item["unconfirmed"] = True
            bare += 1
            continue
        item.pop("unconfirmed", None)
        item["stats"] = rec["stats"]
        filled += 1
        for mine, theirs in (("ilvl", "itemLevel"), ("reqLevel", "requiresLevel")):
            if isinstance(rec.get(theirs), int) and item.get(mine) != rec[theirs]:
                differ += 1
                print("   %-34s %s %s on the zone page, %s on its tooltip"
                      % ((item.get("name") or "")[:34], mine, item.get(mine), rec[theirs]))
                item[mine] = rec[theirs]
        if rec.get("name") and item.get("name") != rec["name"]:
            differ += 1
            print("   %d is %r on the zone page and %r on its tooltip"
                  % (item["id"], item.get("name"), rec["name"]))
            item["name"] = rec["name"]
        if rec.get("droppedBy") and not item.get("droppedBy"):
            item["droppedBy"] = [rec["droppedBy"]]
    doc["note"] = doc.get("note", "").replace(
        "Roster only; stat values live on each item's tooltip and need a second pass. ", "")
    doc["statsCollected"] = cache.get("collected") or time.strftime("%Y-%m-%d")
    save(DATA, doc, 2)
    print("Applied %d, %d without a tooltip (marked unconfirmed), %d fields corrected."
          % (filled, bare, differ))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--refresh", action="store_true",
                    help="read every item again, not only the ones with nothing on file")
    ap.add_argument("--fetch-only", action="store_true",
                    help="fill the cache and leave dungeon-loot.json alone")
    ap.add_argument("--apply-only", action="store_true",
                    help="write the cache into dungeon-loot.json without reading anything")
    args = ap.parse_args()

    if not os.path.exists(DATA):
        sys.exit("No roster yet. Run scrape-forever-dungeons.py first.")
    doc = json.loads(io.open(DATA, encoding="utf-8").read())
    cache = {"source": "nether.wowhead.com/forever/tooltip/item/<id>", "items": {}}
    if os.path.exists(CACHE):
        cache = json.loads(io.open(CACHE, encoding="utf-8").read())

    if not args.apply_only:
        fetch(doc, cache, args.refresh)
    if not args.fetch_only:
        # Read the roster again: a long read may have outlived an import.
        doc = json.loads(io.open(DATA, encoding="utf-8").read())
        apply(doc, cache)


if __name__ == "__main__":
    main()
