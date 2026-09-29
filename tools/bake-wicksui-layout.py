"""Bake the hunter profile into WicksUI/Core/Layout.lua as the shipped defaults."""
import re
from lupa import LuaRuntime

SV = r"C:\Program Files (x86)\World of Warcraft\_classic_beta_\WTF\Account\51031842#1\SavedVariables\WicksUI.lua"
OUT = r"C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\WicksUI\Core\Layout.lua"

L = LuaRuntime()
L.execute(open(SV, encoding="utf-8").read())
hunter = L.globals().WicksUIDB.profiles.hunter


def py(v):
    if hasattr(v, "keys"):
        return {k: py(v[k]) for k in v.keys()}
    return v


p = py(hunter)
gen = p["general"]
modern = gen["styleSizes"]["modern"]

# The OG snapshot: what the profile has now (it is in OG).
og = {"bars": {k: {"size": b["size"], "spacing": b["spacing"]} for k, b in p["actionbars"]["bars"].items()},
      "units": {k: {"width": u["width"], "height": u["height"]} for k, u in p["unitframes"]["units"].items()},
      "minimap": {"square": True, "ring": False, "fill": True}}
modern = {"bars": modern["bars"], "units": modern["units"],
          "minimap": {"square": False, "ring": False, "fill": True}}

# The shipped profile is in Modern.
for k, s in modern["bars"].items():
    p["actionbars"]["bars"][k]["size"], p["actionbars"]["bars"][k]["spacing"] = s["size"], s["spacing"]
for k, s in modern["units"].items():
    p["unitframes"]["units"][k]["width"], p["unitframes"]["units"][k]["height"] = s["width"], s["height"]
p["minimap"].update(modern["minimap"])

# Bookkeeping and per-machine values stay out.
for k in ["installed", "flatRestored", "ptSans", "shadedDefault", "presetFor", "style", "uiScale",
          "moversLocked", "styleSizes"]:
    gen.pop(k, None)
gen["styleSizes"] = {"modern": modern, "wick": og}

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
