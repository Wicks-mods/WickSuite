"""Collect Forever's crafted gear from Wowhead, profession by profession.

Each profession page writes its whole recipe list into a `listviewspells`
array: what it makes, the skill it needs, the reagents, and the skill
levels at which the recipe goes yellow, green and grey.

A recipe says nothing about the thing it makes, so each profession's own
crafted item list is fetched too, for slot, item level and class. That
link is read off the profession page rather than guessed: blacksmithing
is 86;2 but leatherworking is 86;8, tailoring 86;10 and engineering 86;5.
Taking one of those for all four joins four professions' recipes against
one profession's items and quietly comes out blacksmithing only.

Two pages per profession, eight in total.

    python WickSuite/tools/scrape-forever-crafted.py --from-crawl data/forever/raw/<file>.json

Writes WickSuite/data/forever/crafted.json.

Since the release (checked 2026-11-15) www.wowhead.com answers HTTP 403
to a plain request, so the pages are read in a browser and saved as one
json file, which --from-crawl reads. Without it this still tries the
network and fails.
In the browser both lists are plain globals on their pages,
window.listviewspells and window.listviewitems.

The rows are nearly JSON but the page appends an unquoted `quality:` and
`popularity:` to each one, so bare keys are quoted before parsing. That
is safe here because the array is machine generated and regular; it is
not a general purpose JavaScript reader.

Only equipment carries a slot, which is how the sharpening stones, bags
and ammunition are told apart from the things you wear.
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
OUT = os.path.join(OUT_DIR, "crafted.json")
UA = "Wicksmods BIS data collector (https://github.com/Wicksmods)"
PAUSE = 1.5      # someone else's bandwidth

# The professions that make equipment. Alchemy, cooking and first aid
# make consumables, and enchanting improves gear rather than making it,
# so none of them belong in a list of things to wear. Engineering is in
# because it makes goggles, guns and trinkets.
PROFESSIONS = [
    "blacksmithing",
    "leatherworking",
    "tailoring",
    "engineering",
]


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=45) as r:
        return r.read().decode("utf-8", "replace")


def crafted_items_link(html):
    """Each profession page links to its own crafted item list.

    The filter number differs per profession and is not derivable, so it
    is read off the page. Taking blacksmithing's 86;2 for everything gave
    four professions' recipes joined against one profession's items, and
    the join quietly came out blacksmithing only.
    """
    m = re.search(r"items\?filter=([0-9;]+)", html)
    return ("https://www.wowhead.com/forever/items?filter=" + m.group(1)) if m else None


def items(html):
    """The crafted item listview: slot, item level, quality and class."""
    m = re.search(r"listviewitems\s*=\s*(\[.*?\]);", html, re.S)
    if not m:
        return []
    fixed = re.sub(r'([{,])([A-Za-z_]\w*):', r'\1"\2":', m.group(1))
    return json.loads(fixed)


def recipes(html):
    m = re.search(r"listviewspells\s*=\s*(\[.*?\]);", html, re.S)
    if not m:
        return []
    fixed = re.sub(r'([{,])([A-Za-z_]\w*):', r'\1"\2":', m.group(1))
    return json.loads(fixed)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--one", help="a single profession, for a quick look")
    ap.add_argument("--from-crawl",
                    help="json saved from a browser: professions -> name -> { spells, items }")
    args = ap.parse_args()

    crawl, crawl_date = None, None
    if args.from_crawl:
        doc = json.loads(io.open(args.from_crawl, encoding="utf-8").read())
        crawl = doc.get("professions") or {}
        crawl_date = doc.get("collected")

    wanted = [args.one] if args.one else PROFESSIONS
    out, totals = {}, {}

    for prof in wanted:
        url = "https://www.wowhead.com/forever/spells/professions/%s" % prof
        print("%-16s " % prof, end="", flush=True)
        meta, link = {}, None
        if crawl is not None:
            if prof not in crawl:
                print("not in the crawl")
                continue
            rows = crawl[prof].get("spells") or []
            for it in crawl[prof].get("items") or []:
                meta[it["id"]] = it
        else:
            try:
                page = get(url)
                rows = recipes(page)
            except (urllib.error.URLError, TimeoutError, ValueError, json.JSONDecodeError) as exc:
                print("failed: %s" % exc)
                continue
            link = crafted_items_link(page)

        # The items this profession makes, with the fields a recipe has
        # no room for.
        if link:
            time.sleep(PAUSE)
            try:
                for it in items(get(link)):
                    meta[it["id"]] = it
            except (urllib.error.URLError, TimeoutError, ValueError, json.JSONDecodeError) as exc:
                print("(item list failed: %s) " % exc, end="")

        made = []
        for r in rows:
            creates = r.get("creates") or []
            if not creates or not isinstance(creates[0], int):
                continue
            # The profession's own "learn this profession" rows create
            # nothing and are already filtered by the check above.
            it = meta.get(creates[0]) or {}
            entry = {
                "item": creates[0],
                "spell": r.get("id"),
                "name": r.get("name") or r.get("displayName") or "",
                "skill": r.get("learnedat"),
                # orange, yellow, green, grey
                "colors": r.get("colors"),
                "reagents": [list(x) for x in (r.get("reagents") or [])],
                "quality": it.get("quality", r.get("quality")),
            }
            # Only equipment carries a slot, which is how the sharpening
            # stones, bags and ammo are told from the things you wear.
            if it.get("slot"):
                entry["slotId"] = it["slot"]
                entry["ilvl"] = it.get("level")
                entry["reqLevel"] = it.get("reqlevel")
                entry["cls"] = it.get("classs")
                entry["sub"] = it.get("subclass")
                entry["gear"] = True
            made.append(entry)

        out[prof] = made
        totals[prof] = len(made)
        print("%d recipes, %d make something" % (len(rows), len(made)))
        if crawl is None and prof != wanted[-1]:
            time.sleep(PAUSE)

    # item id -> profession, the question the emitter asks.
    index = {}
    for prof, made in out.items():
        for m in made:
            index[str(m["item"])] = {"prof": prof, "skill": m.get("skill"),
                                     "spell": m.get("spell"), "gear": m.get("gear", False)}

    os.makedirs(OUT_DIR, exist_ok=True)
    io.open(OUT, "w", encoding="utf-8", newline="\n").write(json.dumps({
        "source": "wowhead.com/forever/spells/professions, listviewspells arrays",
        "collected": crawl_date or datetime.date.today().isoformat(),
        "note": "slot and item level are not on a recipe; the profession's item list fills those",
        "professions": out,
        "index": index,
    }, indent=1, ensure_ascii=False) + "\n")

    print()
    gear = sum(1 for v in index.values() if v.get("gear"))
    print("total craftable items: %d across %d professions, of which %d are equipment"
          % (len(index), len(out), gear))
    for prof, made in out.items():
        print("   %-16s %4d recipes, %3d equipment"
              % (prof, len(made), sum(1 for m in made if m.get("gear"))))
    print("wrote %s" % os.path.normpath(OUT))


if __name__ == "__main__":
    sys.exit(main())
