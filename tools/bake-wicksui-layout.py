"""Bake a Wick's UI profile into WicksUI/Core/Layout.lua as the shipped defaults.

    python bake-wicksui-layout.py [profile]      (default: safe)

The shipped profile is in Wick Modern. If the profile is in another style
now, its saved Wick Modern snapshot (sizes, positions, minimap, health
colours) is laid over it first. Every other style snapshot it has is kept,
so those styles start where the profile had them.
"""
import re
import sys
from lupa import LuaRuntime

SV = r"C:\Program Files (x86)\World of Warcraft\_classic_beta_\WTF\Account\51031842#1\SavedVariables\WicksUI.lua"
OUT = r"C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\WicksUI\Core\Layout.lua"
NAME = sys.argv[1] if len(sys.argv) > 1 else "safe"

L = LuaRuntime()
L.execute(open(SV, encoding="utf-8").read())
src = L.globals().WicksUIDB.profiles[NAME]
assert src, "no profile named " + NAME


def py(v):
    if hasattr(v, "keys"):
        return {k: py(v[k]) for k in v.keys()}
    return v


p = py(src)
gen = p["general"]
snaps = dict(gen.get("styleSizes") or {})
current = gen.get("presetFor") or "modern"

if current != "modern":
    m = snaps.get("modern")
    assert m, NAME + " is in " + current + " and has no Wick Modern snapshot to ship"
    for k, v in (m.get("bars") or {}).items():
        p["actionbars"]["bars"][k]["size"], p["actionbars"]["bars"][k]["spacing"] = v["size"], v["spacing"]
    for k, v in (m.get("units") or {}).items():
        p["unitframes"]["units"][k]["width"], p["unitframes"]["units"][k]["height"] = v["width"], v["height"]
    if m.get("minimap"):
        p["minimap"].update(m["minimap"])
    if m.get("movers"):
        p["movers"] = dict(m["movers"])
    if m.get("healthColor"):
        p["unitframes"]["healthColor"] = m["healthColor"]
snaps.pop("modern", None)

# Bookkeeping and per-machine values stay out.
for k in ["installed", "flatRestored", "ptSans", "shadedDefault", "presetFor", "style", "uiScale",
          "moversLocked", "styleSizes", "lookHealth"]:
    gen.pop(k, None)
# The shipped profile is in Wick Modern; the other styles it has been in
# keep their snapshots.
if snaps:
    gen["styleSizes"] = snaps
print("baking", NAME, "from", current, "| other styles kept:", sorted(snaps))

blob = repr(p)
for bad in ["Wickid", "Despliff", "jspli"]:
    assert bad not in blob, bad


def key(k):
    if isinstance(k, (int, float)):
        return "[%s]" % (int(k) if float(k).is_integer() else k)
    if re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", k):
        return k
    return "[%r]" % k


def lua(v, ind=1):
    pad = "    " * ind
    if isinstance(v, dict):
        if not v:
            return "{}"
        items = sorted(v.items(), key=lambda kv: (isinstance(kv[0], str), str(kv[0]) if isinstance(kv[0], str) else kv[0]))
        return "{\n" + "".join("%s%s = %s,\n" % (pad, key(k), lua(x, ind + 1)) for k, x in items) + "    " * (ind - 1) + "}"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(int(v)) if float(v).is_integer() else repr(round(v, 4))
    if isinstance(v, str):
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'
    if v is None:
        return "nil"
    raise TypeError(type(v))


head = '''-- Wick's UI
-- Core/Layout.lua: the layout the interface starts with.
--
-- Wick's own setup, baked from a played profile: every setting and every
-- frame's position. It is laid over the modules' defaults once they are
-- all registered, so a new profile starts here and "Reset" comes back
-- here. Only keys the defaults know are taken (the movers and the per
-- style sizes excepted), so a setting that has since gone is dropped
-- rather than carried along. The game's scale is left out: it belongs to
-- the screen, and the first-run setup asks for it.
--
-- Regenerate with WickSuite/tools/bake-wicksui-layout.py.

local ADDON, ns = ...

local LAYOUT = '''

tail = '''

local OPEN = { movers = true, styleSizes = true }

local function over(dst, src, open)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if open or OPEN[k] then
                dst[k] = ns:Copy(v)
            elseif type(dst[k]) == "table" then
                over(dst[k], v, false)
            end
        elseif open or dst[k] ~= nil then
            dst[k] = v
        end
    end
end

-- Bars and units are keyed tables the defaults fill in, so those are
-- walked like any other.
function ns:ApplyDefaultLayout()
    over(ns.defaults.profile, LAYOUT, false)
end
ns.DEFAULT_LAYOUT = LAYOUT
ns:ApplyDefaultLayout()
'''

open(OUT, "w", encoding="utf-8", newline="\n").write(head + lua(p) + tail)
print("wrote", OUT, len(head + lua(p) + tail), "bytes")
