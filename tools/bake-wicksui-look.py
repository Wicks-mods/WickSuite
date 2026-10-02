"""Bake one look's own layout into Wick's UI, from a profile that is in it.

    python bake-wicksui-look.py crisp              (finds the profile in Crisp)
    python bake-wicksui-look.py crisp <profile>    (or names it)
    add --write to save; without it the snapshot is only shown

A look's layout is what Wick's UI keeps per look: frame positions, each
bar's size, spacing and shape, unit frame sizes, text sizes, power and
cast bar sizes, health colours and the minimap's shape. It is saved to
WickSuite/data/wicksui-looks/<look>.json and written into Core/Layout.lua
under general.styleSizes, so every profile meeting the look for the first
time starts in it. bake-wicksui-layout.py keeps these files when it bakes.
"""
import json
import os
import re
import sys
from lupa import LuaRuntime

SV = r"C:\Program Files (x86)\World of Warcraft\_classic_beta_\WTF\Account\51031842#1\SavedVariables\WicksUI.lua"
LAYOUT = r"C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\WicksUI\Core\Layout.lua"
LOOKS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data", "wicksui-looks")

args = [a for a in sys.argv[1:] if not a.startswith("--")]
WRITE = "--write" in sys.argv
if not args:
    sys.exit(__doc__)
look = args[0]
key_for = "wick" if look == "og" else look   # Wick OG is kept as "wick"

L = LuaRuntime()
L.execute(open(SV, encoding="utf-8").read())
db = L.globals().WicksUIDB


def py(v):
    if hasattr(v, "keys"):
        return {k: py(v[k]) for k in v.keys()}
    return v


profiles = py(db.profiles)
if len(args) > 1:
    name = args[1]
else:
    inlook = [n for n, p in profiles.items() if (p.get("general") or {}).get("presetFor") == key_for]
    if len(inlook) != 1:
        sys.exit("profiles in %s: %s; name one" % (look, inlook or "none"))
    name = inlook[0]
p = profiles[name]
assert (p.get("general") or {}).get("presetFor") == key_for, "%s is not in %s" % (name, look)

snap = {"bars": {}, "units": {}}
for bid, d in (p.get("actionbars", {}).get("bars") or {}).items():
    snap["bars"][bid] = {k: d[k] for k in ("size", "spacing", "perRow", "buttons", "growth") if k in d}
for ukey, u in (p.get("unitframes", {}).get("units") or {}).items():
    e = {k: u[k] for k in ("width", "height", "powerHeight") if k in u}
    if isinstance(u.get("texts"), dict):
        e["texts"] = {slot: t["size"] for slot, t in u["texts"].items() if isinstance(t, dict) and "size" in t}
    if isinstance(u.get("castbar"), dict):
        e["castbar"] = {k: u["castbar"][k] for k in ("width", "height") if k in u["castbar"]}
    snap["units"][ukey] = e
if p.get("unitframes", {}).get("healthColor"):
    snap["healthColor"] = p["unitframes"]["healthColor"]
if p.get("movers"):
    snap["movers"] = dict(p["movers"])
mm = p.get("minimap") or {}
snap["minimap"] = {k: mm[k] for k in ("square", "ring", "fill") if k in mm}

blob = json.dumps(snap)
for bad in ["Wickid", "Despliff", "jspli", "Splifftastic"]:
    assert bad not in blob, bad
print("look %s from profile %s: %d bars, %d unit frames, %d movers, minimap %s"
      % (look, name, len(snap["bars"]), len(snap["units"]), len(snap.get("movers", {})), snap["minimap"]))
if not WRITE:
    print(json.dumps(snap, indent=1)[:1500])
    sys.exit(0)


def lkey(k):
    if isinstance(k, (int, float)):
        return "[%s]" % (int(k) if float(k).is_integer() else k)
    if re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", k):
        return k
    return "[%r]" % k


def lua(v, ind):
    pad = "    " * ind
    if isinstance(v, dict):
        if not v:
            return "{}"
        items = sorted(v.items(), key=lambda kv: (isinstance(kv[0], str), str(kv[0]) if isinstance(kv[0], str) else kv[0]))
        return "{\n" + "".join("%s%s = %s,\n" % (pad, lkey(k), lua(x, ind + 1)) for k, x in items) + "    " * (ind - 1) + "}"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(int(v)) if float(v).is_integer() else repr(round(v, 4))
    if isinstance(v, str):
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"') + '"'
    raise TypeError(type(v))


os.makedirs(LOOKS, exist_ok=True)
with open(os.path.join(LOOKS, look + ".json"), "w", encoding="utf-8") as f:
    json.dump(snap, f, indent=1, sort_keys=True)

src = open(LAYOUT, encoding="utf-8").read()
m = re.search(r"^        styleSizes = \{\n", src, re.M)
assert m, "no general.styleSizes in Layout.lua"
entry = "            %s = %s,\n" % (key_for, lua(snap, 4))
# Replace this look's block if it is there already, else add it first.
old = re.search(r"^            %s = \{\n.*?^            \},\n" % re.escape(key_for), src[m.end():], re.M | re.S)
if old:
    a, b = m.end() + old.start(), m.end() + old.end()
    src = src[:a] + entry + src[b:]
else:
    src = src[:m.end()] + entry + src[m.end():]
open(LAYOUT, "w", encoding="utf-8", newline="").write(src)
print("written:", os.path.join(LOOKS, look + ".json"), "and Layout.lua")
