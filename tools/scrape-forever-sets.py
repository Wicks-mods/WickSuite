"""Collect Forever's item sets from Wowhead.

One page carries the lot. wowhead.com/forever/item-sets writes the whole
catalogue into a plain `itemSets = [...]` variable before it builds the
Listview, so unlike the dungeon pages there is nothing to page through
and no per-set request to make: one fetch, 500-odd sets, 3000-odd pieces.

    python WickSuite/tools/scrape-forever-sets.py --from-crawl data/forever/raw/<file>.json

Since the release (checked 2026-11-15) www.wowhead.com answers HTTP 403
to a plain request, so the pages are read in a browser and saved as one
json file, which --from-crawl reads. Without it this still tries the
network and fails.
In the browser the array is the global window.itemSets.

Writes WickSuite/data/forever/item-sets.json, holding both the sets and a
flat item id to set name index, which is what the emitter actually wants:
the question at emit time is always "what set is this item in", never
"what is in this set".

Sets whose pieces are not in the gear data are kept anyway. They cost a
few bytes and the gear data grows as the beta fills in.
"""
import io
import json
import os
import re
import sys
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(HERE, "..", "data", "forever")
OUT = os.path.join(OUT_DIR, "item-sets.json")
URL = "https://www.wowhead.com/forever/item-sets"
UA = "Wicksmods BIS data collector (https://github.com/Wicksmods)"


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=45) as r:
        return r.read().decode("utf-8", "replace")


def parse(html):
    # The array sits between `itemSets = ` and the Listview that renders
    # it. Non-greedy to the first `];` so a later array cannot be swept in.
    m = re.search(r"itemSets\s*=\s*(\[.*?\]);", html, re.S)
    if not m:
        raise SystemExit("no itemSets array on the page; Wowhead changed shape")
    return json.loads(m.group(1))


def main():
    crawl_date = None
    if len(sys.argv) == 3 and sys.argv[1] == "--from-crawl":
        doc = json.loads(io.open(sys.argv[2], encoding="utf-8").read())
        raw, crawl_date = doc.get("sets") or [], doc.get("collected")
        if not raw:
            raise SystemExit("no sets in that crawl")
    else:
        print("fetching %s" % URL)
        try:
            html = get(URL)
        except (urllib.error.URLError, TimeoutError) as exc:
            raise SystemExit("fetch failed: %s" % exc)
        raw = parse(html)

    sets, index, skipped = {}, {}, 0
    for s in raw:
        pieces = [p for p in (s.get("pieces") or []) if isinstance(p, int)]
        name = (s.get("name") or "").strip()
        if not name or not pieces:
            skipped += 1
            continue
        sets[str(s["id"])] = {
            "name": name,
            "pieces": pieces,
            # Wowhead's own popularity, which is the only ordering signal
            # the page gives. Useful for showing the sets people chase
            # first rather than alphabetically.
            "popularity": s.get("popularity"),
        }
        for p in pieces:
            # A piece in two sets is possible and the later one wins, the
            # same way the page itself resolves it.
            index[str(p)] = name

    os.makedirs(OUT_DIR, exist_ok=True)
    io.open(OUT, "w", encoding="utf-8", newline="\n").write(json.dumps({
        "source": "wowhead.com/forever/item-sets, itemSets array",
        "collected": crawl_date or __import__("datetime").date.today().isoformat(),
        "note": "index maps item id to set name; that is the question the emitter asks",
        "sets": sets,
        "index": index,
    }, indent=1, ensure_ascii=False) + "\n")

    print("sets: %d   pieces: %d   items indexed: %d   skipped (no name or no pieces): %d"
          % (len(sets), sum(len(v["pieces"]) for v in sets.values()), len(index), skipped))
    print("wrote %s" % os.path.normpath(OUT))


if __name__ == "__main__":
    sys.exit(main())
