"""Add stat values to the dungeon loot roster.

The zone listviews give the roster but not the numbers. Wowhead has a
tooltip endpoint that returns one item as a small JSON blob, which is far
lighter than pulling the whole item page, so this fills in the stats a
second at a time.

    python WickSuite/tools/scrape-forever-item-stats.py

Reads and rewrites WickSuite/data/forever/dungeon-loot.json, adding a
"stats" object to each entry. Items already carrying stats are skipped,
so it is safe to stop it and run it again.
"""
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
UA = "Wicksmods BIS data collector (https://github.com/Wicksmods)"
PAUSE = 0.7

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
    text = re.sub(r"<(?:br|/?(?:div|table|tr|td|p))\b[^>]*>", "\n", text)
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


def main():
    if not os.path.exists(DATA):
        sys.exit("No roster yet. Run scrape-forever-dungeons.py first.")
    doc = json.loads(io.open(DATA, encoding="utf-8").read())

    todo = []
    for dungeon in doc["dungeons"].values():
        for bucket in ("drops", "questRewards"):
            for item in dungeon.get(bucket, []):
                if item.get("id") and "stats" not in item:
                    todo.append(item)

    if not todo:
        print("Every item already has stats.")
        return

    print("Fetching stats for %d items, about %d seconds." % (todo and len(todo), len(todo) * PAUSE))
    done, failed = 0, 0
    for i, item in enumerate(todo):
        if i:
            time.sleep(PAUSE)
        try:
            item["stats"] = parse(tooltip(item["id"]))
            done += 1
        except (urllib.error.URLError, json.JSONDecodeError, TimeoutError) as exc:
            failed += 1
            print("   %s failed: %s" % (item["name"], exc))
        if done and done % 50 == 0:
            print("   %d of %d" % (done, len(todo)))
            io.open(DATA, "w", encoding="utf-8", newline="\n").write(
                json.dumps(doc, indent=2, ensure_ascii=False) + "\n")

    doc["note"] = doc["note"].replace(
        "Roster only; stat values live on each item's tooltip and need a second pass. ", "")
    doc["statsCollected"] = time.strftime("%Y-%m-%d")
    io.open(DATA, "w", encoding="utf-8", newline="\n").write(
        json.dumps(doc, indent=2, ensure_ascii=False) + "\n")
    print("Filled %d, failed %d." % (done, failed))


if __name__ == "__main__":
    main()
