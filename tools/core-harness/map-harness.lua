-- Wick's Map offline harness. A small fake world map (Cosmic > Azeroth >
-- Eastern Kingdoms > Elwynn Forest, Kalimdor beside it) with the parts of
-- the game's map canvas Wick's Map reads, and the C_Map answers for it.
--   The wheel: down a level at the end of the game's zoom, up a level at
--   the start of it, never while the game is still zooming, the pause
--   between steps, the zoom overlay, the switches, and on a secrets client
--   no change during a fight.
--   The spot under the cursor: glides about it within a map, and a new
--   level opens at the size the smaller map was drawn, on the same spot.
--   The terrain: the real tile data, the grid found from a map's corners,
--   the fade measured against the zone's painting, tiles placed and reused.
--   The marker: right-click drops and clears, Shift and the left button
--   pass, a click on a continent lands in the zone under it, the pin, the
--   arrow's distance and direction, arrival, the slash forms, and on a
--   client with the game's waypoint, that waypoint.
--   And that nothing of ours is written into the game's map tables.
-- args: coreDir, addonsDir, mode, stubPath
local CORE_DIR, ADDONS_DIR, MODE, STUB = ...
local S = assert(loadfile(STUB))(MODE)

local passes, fails = 0, 0
local function check(cond, label)
    if cond then passes = passes + 1; io.write("  ok    ", label, "\n")
    else fails = fails + 1; io.write("  FAIL  ", label, "\n") end
end
local function near(a, b, eps) return a and b and math.abs(a - b) <= (eps or 1e-6) end
local function plain(s) return (tostring(s):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local mark = 0
local function chatSince() local t = {} for i = mark + 1, #S.CHAT do t[#t + 1] = plain(S.CHAT[i]) end return table.concat(t, " | ") end
local function clearChat() mark = #S.CHAT end

-- ---------- a clock the harness owns ----------
NOW = 1000
GetTime = function() return NOW end
local function advance(secs) NOW = NOW + secs end

-- ---------- the world ----------
-- Every map's art is one Classic-sized layer of twelve tiles.
-- Each map's zoom range, as its art layers report it (the fake canvas is
-- the art's own size, so the scales are the layers' own).
local RANGES = {}
local MAPS = {
    [946]  = { name = "Cosmic", parent = 0, type = 0 },
    [947]  = { name = "Azeroth", parent = 946, type = 1 },
    [1414] = { name = "Kalimdor", parent = 947, type = 2, cont = 1 },
    [1415] = { name = "Eastern Kingdoms", parent = 947, type = 2, cont = 0 },
    [1429] = { name = "Elwynn Forest", parent = 1415, type = 3, cont = 0 },
    -- A zone the size of a real one, for zooming past the game's steps.
    [1945] = { name = "Outland", parent = 946, type = 2, cont = 530 },
    [1944] = { name = "Hellfire Peninsula", parent = 1945, type = 3, cont = 530 },
}
-- Where each map sits on its parent.
local RECTS = {
    ["947:946"]   = { 0.1, 0.6, 0.1, 0.9 },
    ["1414:947"]  = { 0.05, 0.45, 0.1, 0.9 },
    ["1415:947"]  = { 0.55, 0.95, 0.1, 0.9 },
    ["1429:1415"] = { 0.40, 0.50, 0.70, 0.80 },
}
-- World boxes in yards. Positions come back as (north, west), the reverse
-- of what a reader might guess, so the arrow cannot be right by luck.
local BOX = {
    [1415] = { top = 4000, left = 6000, h = 8000, w = 12000 },
}
BOX[1429] = { top = 4000 - 0.70 * 8000, left = 6000 - 0.40 * 12000, h = 0.1 * 8000, w = 0.1 * 12000 }
BOX[1944] = { top = 3000, left = 2500, h = 3000, w = 4500 }
local function vec(x, y) return { x = x, y = y, GetXY = function(v) return v.x, v.y end } end

local PLAYER = { map = 1429, x = 0.5, y = 0.9 }
PRELOADED = {}
FACING = 0
GetPlayerFacing = function() return FACING end

C_Map = {
    GetMapInfo = function(id)
        local m = MAPS[id]
        return m and { mapID = id, name = m.name, parentMapID = m.parent, mapType = m.type } or nil
    end,
    GetMapInfoAtPosition = function(id, x, y)
        local child
        if id == 946 then child = 947
        elseif id == 947 then child = (x < 0.5) and 1414 or 1415
        elseif id == 1415 then
            if x >= 0.40 and x <= 0.50 and y >= 0.70 and y <= 0.80 then child = 1429 end
        elseif id == 1429 then child = 1429   -- the zone itself: nothing deeper
        end
        return child and C_Map.GetMapInfo(child) or nil
    end,
    GetMapRectOnMap = function(child, parent)
        local r = RECTS[child .. ":" .. parent]
        if r then return r[1], r[2], r[3], r[4] end
    end,
    GetMapArtLayers = function(id)
        if not MAPS[id] then return nil end
        local r = RANGES[id] or { lo = 1, hi = 1 }
        return { { layerWidth = 1002, layerHeight = 668, tileWidth = 256, tileHeight = 256, minScale = r.lo, maxScale = r.hi } }
    end,
    GetMapArtLayerTextures = function(id)
        local t = {}
        for i = 1, 12 do t[i] = id * 100 + i end
        return t
    end,
    GetWorldPosFromMapPos = function(id, v)
        local b, m = BOX[id], MAPS[id]
        if not b then return nil end
        return m.cont, vec(b.top - v.y * b.h, b.left - v.x * b.w)
    end,
    GetMapPosFromWorldPos = function(cont, pos, id)
        local b, m = BOX[id], MAPS[id]
        if not (b and m.cont == cont) then return nil end
        return id, vec((b.left - pos.y) / b.w, (b.top - pos.x) / b.h)
    end,
    GetBestMapForUnit = function() return PLAYER.map end,
    RequestPreloadMap = function(id) PRELOADED[id] = true end,
    GetPlayerMapPosition = function(id)
        if id == PLAYER.map then return vec(PLAYER.x, PLAYER.y) end
        local cont, pos = C_Map.GetWorldPosFromMapPos(PLAYER.map, vec(PLAYER.x, PLAYER.y))
        local _, mp = C_Map.GetMapPosFromWorldPos(cont, pos, id)
        return mp
    end,
}
C_MapExplorationInfo = {
    GetExploredMapTextures = function(id)
        if id ~= 1429 then return nil end
        return { { textureWidth = 300, textureHeight = 200, offsetX = 100, offsetY = 50,
                   isShownByMouseOver = false, fileDataIDs = { 1, 2, 3, 4 } } }
    end,
}
local sounds = {}
PlaySound = function(id) sounds[#sounds + 1] = id end
SHIFT = false
IsShiftKeyDown = function() return SHIFT end
GameTooltip = GameTooltip or CreateFrame("GameTooltip", "GameTooltip")

-- ---------- the game's world map, the parts that are read ----------
-- The fake keeps its own state in this local table, never on the frames,
-- so any key that appears on them later was put there by the addon.
-- Geometry as the game's canvas has it: the scroll frame is W x H with its
-- top left at (0, TOP) on screen; the canvas in it is the map art, W x H,
-- drawn at MAP.scale with the map point (MAP.cx, MAP.cy) in the middle.
local W, H, TOP = 1002, 668, 100
local MAP = { id = 947, scale = 1, target = 1, lo = 1, hi = 1, cx = 0.5, cy = 0.5,
              set = {}, handlers = {}, instant = 0 }
local LEVELS = { { scale = 1 } }
local function range(id, lo, hi, n) RANGES[id] = { lo = lo, hi = hi, n = n } end
local function applyRange(id)
    local r = RANGES[id] or { lo = 1, hi = 1, n = 1 }
    MAP.lo, MAP.hi = r.lo, r.hi
    for i = #LEVELS, 1, -1 do LEVELS[i] = nil end
    for i = 1, r.n do
        LEVELS[i] = { scale = (r.n == 1) and r.lo or (r.lo + (r.hi - r.lo) * (i - 1) / (r.n - 1)) }
    end
end
local wm = S.newMock("Frame", "WorldMapFrame")
local sc = S.newMock("ScrollFrame")
local canvas = S.newMock("Frame")
rawset(sc, "GetLeft", function() return 0 end)
rawset(sc, "GetTop", function() return TOP end)
rawset(sc, "GetWidth", function() return W end)
rawset(sc, "GetHeight", function() return H end)
rawset(sc, "GetEffectiveScale", function() return 1 end)
-- A scaled frame reports its edges in its own scaled units.
rawset(canvas, "GetEffectiveScale", function() return MAP.scale end)
rawset(canvas, "GetWidth", function() return W end)
rawset(canvas, "GetHeight", function() return H end)
rawset(canvas, "GetLeft", function() return (W / 2 - MAP.cx * W * MAP.scale) / MAP.scale end)
rawset(canvas, "GetTop", function() return (TOP - (H / 2 - MAP.cy * H * MAP.scale)) / MAP.scale end)
rawset(sc, "Child", canvas)
rawset(sc, "zoomLevels", LEVELS)
rawset(sc, "targetScale", 1)
rawset(sc, "GetCanvasScale", function() return MAP.scale end)
rawset(sc, "GetScaleForMinZoom", function() return MAP.lo end)
rawset(sc, "GetScaleForMaxZoom", function() return MAP.hi end)
rawset(sc, "GetCurrentScrollX", function() return MAP.cx end)
rawset(sc, "GetCurrentScrollY", function() return MAP.cy end)
-- As the canvas does it: zoom about the point given, from where the map
-- is now, then hold the centre inside the map's edges.
local function ipz(s, px, py)
    local r = MAP.scale / s
    px = px + (MAP.cx - px) * r
    py = py + (MAP.cy - py) * r
    MAP.scale, MAP.target = s, s
    rawset(sc, "targetScale", s)
    local ex, ey = 0.5 / s, 0.5 / s
    MAP.cx = math.max(ex, math.min(1 - ex, px))
    MAP.cy = math.max(ey, math.min(1 - ey, py))
    MAP.tx, MAP.ty = MAP.cx, MAP.cy
end
-- The canvas's frame update: the view slides to its pan target.
local function settleGame() MAP.cx, MAP.cy = MAP.tx or MAP.cx, MAP.ty or MAP.cy end
rawset(sc, "InstantPanAndZoom", function(_, s, px, py)
    MAP.instant = MAP.instant + 1
    ipz(s, px, py)
end)
-- Forever's canvas asks the click-through question; TBC's has no such
-- method. Declared either way, because the stub's frames make up any
-- method they are asked for, and that would read as a field we wrote.
rawset(sc, "ShouldNavigateIgnoreZoneMapPositionData", MODE ~= "tbc" and function() return false end or false)

-- The mouse: a point on the screen. aim() puts it over a map point as the
-- map is drawn now; under() reads what is beneath it.
local CURSOR = { 0, TOP }
GetCursorPosition = function() return CURSOR[1], CURSOR[2] end
local function aim(nx, ny)
    CURSOR[1] = W / 2 + (nx - MAP.cx) * W * MAP.scale
    CURSOR[2] = TOP - (H / 2 + (ny - MAP.cy) * H * MAP.scale)
end
local function under()
    return MAP.cx + (CURSOR[1] - W / 2) / (W * MAP.scale),
           MAP.cy + ((TOP - CURSOR[2]) - H / 2) / (H * MAP.scale)
end

-- The game's own wheel handler, as the canvas runs it: one step on from
-- the step the scale is at. Both clients' world maps zoom instantly (a
-- whole step at once, about the cursor); the canvas's other mode sets a
-- zoom target it glides to by itself.
MAP.instantMode = true
local function stepIndex(s)
    local best = 1
    for i, z in ipairs(LEVELS) do if s >= z.scale - 1e-9 then best = i else break end end
    return best
end
sc:SetScript("OnMouseWheel", function(_, delta)
    if MAP.instantMode then
        local atEnd = (delta > 0 and MAP.scale == MAP.hi) or (delta < 0 and MAP.scale == MAP.lo)
        if not atEnd then MAP.tx, MAP.ty = under() end
    end
    local i = stepIndex(MAP.scale)
    local out, inn = LEVELS[i - 1] or LEVELS[i], LEVELS[i + 1] or LEVELS[i]
    local nextS
    if delta > 0 and inn.scale > MAP.scale then nextS = inn.scale
    elseif delta < 0 and out.scale < MAP.scale then nextS = out.scale end
    if not nextS then return end
    if MAP.instantMode then
        local ux, uy = under()
        ipz(nextS, ux, uy)
    else
        MAP.target = nextS
        rawset(sc, "targetScale", MAP.target)
    end
end)
rawset(wm, "ScrollContainer", sc)
rawset(wm, "GetMapID", function() return MAP.id end)
-- A new map opens whole and centred, as ResetZoom leaves it.
rawset(wm, "SetMapID", function(_, id)
    MAP.id = id
    applyRange(id)
    MAP.scale, MAP.target, MAP.cx, MAP.cy = MAP.lo, MAP.lo, 0.5, 0.5
    rawset(sc, "targetScale", MAP.lo)
    MAP.set[#MAP.set + 1] = id
end)
rawset(wm, "GetCanvas", function() return canvas end)
rawset(wm, "GetNormalizedCursorPosition", function()
    local x, y = under()
    return math.max(0, math.min(1, x)), math.max(0, math.min(1, y))
end)
rawset(wm, "AddCanvasClickHandler", function(_, fn, pri) MAP.handlers[#MAP.handlers + 1] = { fn = fn, pri = pri } end)
local function show(id) wm:SetMapID(id) end
-- Pin levels as the game's manager hands them out: the explored areas at
-- 2001, the top pin at 2800.
local PINS = { maxLevel = 2800 }
function PINS:GetValidFrameLevel(t) return t == "PIN_FRAME_LEVEL_MAP_EXPLORATION" and 2001 or 2000 end
rawset(wm, "GetPinFrameLevelsManager", function() return PINS end)
-- A screen 768 pixels tall, so one unit of a frame at scale 1 is a pixel.
GetPhysicalScreenSize = function() return 1366, 768 end
WorldMapFrame = wm
wm:Show()

local function keys(t) local k = {} for n in pairs(t) do k[n] = true end return k end
local before = { wm = keys(wm), sc = keys(sc), canvas = keys(canvas) }

-- ---------- load ----------
io.write("== ", MODE, " ==\n")
WicksMapDB = nil
S.loadAddon(CORE_DIR, "WickCore")
S.fire("ADDON_LOADED", "WickCore")
local Core = WickCore
local ok, err = pcall(S.loadAddon, ADDONS_DIR .. "/WicksMap", "WicksMap")
check(ok, "WicksMap loads: " .. tostring(err or ""))
if not ok then error(err, 0) end
S.fire("ADDON_LOADED", "WicksMap")
local REAL = WicksMap.TILE_RUNS
local function count(runs) local n = 0 for i = 3, #runs, 4 do n = n + runs[i] end return n end
local function lookup(runs, col, row)
    for i = 1, #runs - 3, 4 do
        if runs[i] == col and row >= runs[i + 1] and row < runs[i + 1] + runs[i + 2] then return runs[i + 3] + row - runs[i + 1] end
    end
end
check(REAL and count(REAL[0]) == 1224 and count(REAL[1]) == 1105 and count(REAL[530]) == 840,
    "terrain tiles for the Eastern Kingdoms, Kalimdor and Outland (1224, 1105, 840)")
check(lookup(REAL[1], 40, 28) == 208332 and lookup(REAL[1], 41, 29) == 208377, "Kalimdor's tiles by the listfile's ids")
-- A whole grid with ids the checks can work out: 100000 + column * 64 + row.
local SYNTH = {}
for col = 0, 63 do local r = { col, 0, 64, 100000 + col * 64 } for _, v in ipairs(r) do SYNTH[#SYNTH + 1] = v end end
WicksMap.TILE_RUNS = { [0] = SYNTH, [530] = SYNTH }
-- The stub reports a player already logged in, so the addon has read its
-- tiles by now; read them again.
WicksMap.Terrain.Decode()
Core.debug = true   -- handler errors reach chat, where they are checked
S.fire("PLAYER_LOGIN")
S.fire("PLAYER_ENTERING_WORLD", true, false)
local ns = WicksMap
local A = Core.addons.WicksMap
local db = ns.DB()
local Zoom, Marker = ns.Zoom, ns.Marker

local function wheel(delta)
    Zoom.watcher.__scripts.OnUpdate(Zoom.watcher)
    sc.__scripts.OnMouseWheel(sc, delta)
end
local function glide(dt) Zoom.driver.__scripts.OnUpdate(Zoom.driver, dt) end
local function settle() advance(1) end
local function rightClick(x, y, button)
    local h = MAP.handlers[1]
    return h and h.fn(wm, button or "RightButton", x, y)
end
local function slash(msg) SlashCmdList.WICK_WICKSMAP(msg) end
local function noErrors(label)
    local c = chatSince()
    check(not c:find("handler:", 1, true) and not c:find("error:", 1, true) and not c:find("debug", 1, true),
        label .. " (no errors in chat)" .. (c ~= "" and ("  [" .. c .. "]") or ""))
end

io.write("== login ==\n")
check(A and A.title == "Wick's Map" and A.version == "0.1.0", "a WickCore addon, Wick's Map 0.1.0")
check(A.enabled and db ~= nil, "enabled at login, with its saved variable")
check(db.wheel and db.anchor and db.onPlayer and db.animate and db.terrain and db.rightClick and db.arrow and db.autoClear, "every switch starts on")
check(Core.Options.pages.WicksMap ~= nil, "a page under Wick's Mods")
check(Core.Launcher.entries.WicksMap ~= nil, "a line in the launcher")
check(ns.attached and Zoom.attached and Marker.attached, "hooked onto the world map")
check(#MAP.handlers == 1 and MAP.handlers[1].pri == 100, "one canvas click handler, ahead of the game's")
check(ns.Terrain.layer:GetFrameLevel() == 2002, "the terrain sits just over the explored areas: " .. tostring(ns.Terrain.layer:GetFrameLevel()))
check(Marker.layer:GetFrameLevel() == 2810 and Zoom.ov:GetFrameLevel() == 2820, "the marker and the zoom above every pin")
local native = Marker:Native()
check(native == (MODE ~= "tbc" and C_Map.SetUserWaypoint ~= nil), "the game's waypoint only where the client has one")

io.write("== the wheel ==\n")
clearChat()
show(947); aim(0.7, 0.5)
wheel(1)
check(MAP.id == 1415, "in over the eastern half of Azeroth opens the Eastern Kingdoms")
local ov = Zoom.ov
check(ov and ov:IsShown() and Zoom.anim and Zoom.anim.n, "the zoom plays, with the continent placed on the world")
check(ov.back.mapID == 947 and ov.front.mapID == 1415, "the world behind, the continent in front")
check(ov.back.used == 12, "twelve tiles of art: " .. tostring(ov.back.used))
local tile = ov.back.tex[4]
local w, h = tile:GetSize()
check(w == 1002 - 768 and h == 256, "the last column is cropped to the map's edge: " .. tostring(w) .. "x" .. tostring(h))
local S0, E0 = Zoom.anim.S, Zoom.anim.E
check(near(S0.x, 0.55 * 1002) and near(S0.w, 0.4 * 1002) and near(E0.w, 1002), "from the continent's place on the world to the whole frame")
check(ov.front:GetAlpha() == 0, "the continent starts unseen")
check(ov.front.mask ~= nil and ov.back.mask == nil, "the map coming in has feathered edges")
wheel(1)
check(MAP.id == 1415, "a second notch straight after waits out the pause")
local upd = ov.__scripts.OnUpdate
upd(ov, 0.16)
check(Zoom.anim and Zoom.anim.phase == "zoom" and ov.front:GetAlpha() > 0, "halfway: the continent is coming in")
upd(ov, 0.25)
check(Zoom.anim and Zoom.anim.phase == "fade", "the camera move ends, then the fade")
local s = ov.front:GetScale()
check(near(s * 1002, 1002, 0.01) and near(ov.front:GetAlpha(), 1), "ending exactly over the game's map")
upd(ov, 0.2)
check(not Zoom.anim and not ov:IsShown(), "and the overlay is gone")

settle()
aim(0.45, 0.75)
wheel(1)
check(MAP.id == 1429, "in over Elwynn on the continent opens Elwynn Forest")
check(ov.front.used == 12 + 2, "the zone's explored parts are drawn over its art: " .. tostring(ov.front.used))
local ex = ov.front.tex[13]
local ew, eh = ex:GetSize()
check(ew == 256 and eh == 200 and ov.front.tex[14]:GetSize() == 44, "explored pieces cropped the way the game crops them")
settle()
wheel(1)
check(MAP.id == 1429 and Zoom.glide ~= nil, "nothing deeper under the cursor: the map stays, and the wheel goes on into the terrain")
settle()
aim(0.5, 0.5)
wheel(-1)
check(MAP.id == 1415 and Zoom.anim and Zoom.anim.dir == "out", "out goes up to the continent, zooming out")
check(near(Zoom.anim.E.x, 0.40 * 1002) and near(Zoom.anim.E.w, 0.1 * 1002), "the zone shrinks into its place on the continent")
settle(); upd(ov, 1); upd(ov, 1)
wheel(-1); check(MAP.id == 947, "out again: Azeroth")
settle(); wheel(-1); check(MAP.id == 946, "and the cosmic map")
settle(); wheel(-1); check(MAP.id == 946, "nothing above that")

io.write("== the game's own zoom comes first ==\n")
settle()
db.anchor = false
range(1415, 1, 2, 2)
show(1415); aim(0.45, 0.75)
wheel(1)
check(MAP.id == 1415 and MAP.scale == 2 and not Zoom.glide, "smooth zoom off: the game's own jump, left alone")
local jx, jy = under()
check(near(jx, 0.45) and near(jy, 0.75), "(the game's jump is about the cursor too)")
aim(0.45, 0.75)
settle(); wheel(1)
check(MAP.id == 1429, "all the way in: the next notch opens the zone")
show(1415); ipz(2, 0.5, 0.5)
settle(); wheel(-1)
check(MAP.id == 1415 and MAP.scale == 1, "zoomed in, out first zooms back out")
settle(); wheel(-1)
check(MAP.id == 947, "all the way out: up a level")
show(1429); aim(0.25, 0.5)
settle(); wheel(-1)
check(MAP.id == 1415 and MAP.scale == 1 and near(MAP.cx, 0.5), "with the spot kept off, the continent opens whole")
-- The canvas's other mode: a zoom target it glides to by itself.
MAP.instantMode = false
show(1415); aim(0.45, 0.75)
wheel(1)
check(MAP.target == 2 and MAP.scale == 1 and not Zoom.glide, "a canvas that glides by itself is left to it")
MAP.scale = 1.5
settle(); wheel(1)
check(MAP.id == 1415, "still on its way in: the map stays")
MAP.scale = 2; MAP.target = 2; aim(0.45, 0.75)
settle(); wheel(1)
check(MAP.id == 1429, "there, the next notch opens the zone")
MAP.instantMode = true
db.anchor = true

io.write("== the spot under the cursor stays put ==\n")
db.onPlayer = false
settle(); upd(ov, 1); upd(ov, 1)
range(1415, 1, 16, 4)   -- steps at 1, 6, 11 and 16
range(1429, 1, 4, 4)
show(1415); aim(0.45, 0.75)
local calls = MAP.instant
wheel(1)
check(Zoom.glide and near(Zoom.glide.to, 6) and MAP.scale == 1, "a notch in: the game's jump is taken back and glided instead")
glide(0.11)
local ux, uy = under()
check(MAP.scale > 1 and MAP.scale < 6 and near(ux, 0.45) and near(uy, 0.75),
    ("halfway (x%.2f), the spot under the cursor has not moved"):format(MAP.scale))
glide(1)
ux, uy = under()
check(MAP.scale == 6 and not Zoom.glide and near(ux, 0.45) and near(uy, 0.75), "at the next step, the spot is still under the cursor")
check(MAP.instant > calls, "through the canvas's own InstantPanAndZoom")
wheel(1); glide(0.05); wheel(1)
check(Zoom.glide and near(Zoom.glide.to, 16), "a second notch during the glide goes a step further")
glide(1)
ux, uy = under()
check(MAP.scale == 16 and near(ux, 0.45) and near(uy, 0.75), "all the way in, still on the same spot")
check(PRELOADED[1429], "and the zone under the cursor already loading")
settle(); wheel(1)
ux, uy = under()
check(MAP.id == 1429 and near(MAP.scale, 1.6) and near(ux, 0.5) and near(uy, 0.5),
    ("in to the zone: opened at the size it was drawn (x%.2f), the same spot under the cursor"):format(MAP.scale))
settle(); upd(ov, 1); upd(ov, 1)
show(1429); aim(0.25, 0.5)
settle(); wheel(-1)
ux, uy = under()
check(MAP.id == 1415 and near(MAP.scale, 10) and near(ux, 0.425) and near(uy, 0.75),
    ("out to the continent: zoomed so the zone keeps its size (x%.2f), the same spot under the cursor"):format(MAP.scale))
local seam = Zoom.anim
check(seam and seam.n and near(seam.E.x, seam.S.x, 0.01) and near(seam.E.w, seam.S.w, 0.01),
    "so the zone stays where it was while the continent comes in around it")
settle(); upd(ov, 1); upd(ov, 1)
-- Zooming in about a point never shows past the map's edge; zooming out
-- near one can, and the canvas holds the edge.
show(1415); sc:InstantPanAndZoom(11, 0, 0.5)
CURSOR[1] = 900
wheel(-1); glide(1)
check(MAP.scale == 6 and near(MAP.cx, 0.5 / 6), "zooming out against the map's edge stops at the edge")
show(1415); aim(0.45, 0.75)
wheel(1)
check(Zoom.glide ~= nil, "a glide under way")
show(1429)
glide(0.05)
check(Zoom.glide == nil and MAP.scale == 1, "a map changed meanwhile ends it")
if Core.Client.hasSecrets then
    COMBAT = true
    show(1415); aim(0.45, 0.75)
    settle(); wheel(1)
    check(not Zoom.glide and MAP.scale == 6, "in a fight on a secrets client, the game's own jump")
    COMBAT = false
end
db.onPlayer = true

io.write("== zooming in on yourself ==\n")
settle(); upd(ov, 1); upd(ov, 1)
-- The player stands in Elwynn at (0.5, 0.9), which is (0.45, 0.79) on the
-- continent.
local function playerOnScreen()
    local R = ns.CanvasRect(sc)
    local px, py = C_Map.GetPlayerMapPosition(MAP.id):GetXY()
    return R.x + px * R.w, R.y + py * R.h
end
show(1415); aim(0.42, 0.72)
local sx0, sy0 = playerOnScreen()
wheel(1)
check(Zoom.glide and Zoom.glide.a.mode == "player", "the cursor over your zone: the zoom is on you")
glide(1)
local sx1, sy1 = playerOnScreen()
check(MAP.scale == 6 and near(sx1, sx0 + (501 - sx0) / 2, 0.01) and near(sy1, sy0 + (334 - sy0) / 2, 0.01),
    ("closing in on you, and bringing you halfway to the middle (%.1f, %.1f)"):format(sx1, sy1))
SHIFT = true
wheel(1)
check(Zoom.glide and Zoom.glide.a.mode == "cursor", "Shift held: where the cursor is")
SHIFT = false
glide(1)
aim(0.2, 0.3)
wheel(-1)
check(Zoom.glide and Zoom.glide.a.mode == "cursor", "the cursor somewhere else: there")
glide(1)
-- In the middle of Elwynn, clear of its edges, which the canvas holds.
PLAYER.y = 0.5
show(1415); ipz(16, 0.45, 0.75); aim(0.42, 0.72)
local bx, by = playerOnScreen()
settle(); wheel(1)
local ax, ay = playerOnScreen()
check(MAP.id == 1429 and near(ax, bx, 0.01) and near(ay, by, 0.01),
    "into your zone from the continent, you stay where you were on screen")
PLAYER.y = 0.9
settle(); upd(ov, 1); upd(ov, 1)
show(1944); aim(0.5, 0.5)
check(Zoom:Anchor(wm, 1).mode == "cursor", "on a map you are not on, the cursor")
show(1415); aim(0.45, 0.79)
db.onPlayer = false
check(Zoom:Anchor(wm, 1).mode == "cursor", "and with the setting off")
db.onPlayer = true
range(1415, 1, 1, 1); range(1429, 1, 1, 1)
show(947)

io.write("== terrain ==\n")
settle(); upd(ov, 1); upd(ov, 1)
local T = ns.Terrain
local function tilesShown() local n = 0 for _ in pairs(T.shown) do n = n + 1 end return n end
local function step() T.layer.__scripts.OnUpdate(T.layer) end
range(1429, 1, 4, 4); range(1415, 1, 16, 4)
local g = T.GeometryOf(1429)
check(g and near(g.u0, 29.75) and near(g.u1, 32) and near(g.v0, 35) and near(g.v1, 36.5),
    "Elwynn found in the tile grid from its corners (columns 29.75 to 32, rows 35 to 36.5)")
show(1429); step()
check(tilesShown() == 0 and T.layer:GetAlpha() == 0, "the whole zone: the painted map alone")
local HALF = (math.log(2.5) / math.log(4) - 0.5) / 0.5
MAP.scale, MAP.target, MAP.cx, MAP.cy = 1.6, 1.6, 0.5, 0.5
step()
check(tilesShown() == 0, "the first third of the zone's zoom: still the painted map")
MAP.scale, MAP.target = 2.5, 2.5
step()
check(tilesShown() == 4 and near(T.layer:GetAlpha(), HALF, 1e-6),
    ("past halfway in: four tiles, part faded in (%.2f)"):format(T.layer:GetAlpha()))
MAP.scale, MAP.target = 4, 4
step()
local a, b = T.shown[30 * 64 + 35], T.shown[31 * 64 + 35]
check(tilesShown() == 2 and a and b and a.wickTile == 101955 and b.wickTile == 102019,
    "close in: the two tiles in view, by their ids")
check(T.layer:GetAlpha() == 1, "and at the game's closest step, all terrain")
local _, _, _, tx, ty = a:GetPoint()
local tw, th = a:GetSize()
check(near(tx, 0.25 / 2.25 * 1002, 0.01) and near(ty, 0, 0.01) and near(tw, 1002 / 2.25, 0.01) and near(th, 668 / 1.5, 0.01),
    ("each tile on its own 533 yards of the canvas (%.1f, %.1f, %.1f x %.1f)"):format(tx, ty, tw, th))
check(T.layer:GetParent() == canvas, "inside the map's canvas, so the pins stay on top")
step()
check(T.shown[30 * 64 + 35] == a, "nothing moved: nothing redrawn")
MAP.cx = 0.2
step()
check(T.shown[30 * 64 + 35] == a and T.shown[31 * 64 + 35] == nil and T.shown[29 * 64 + 35] ~= nil, "panned west: the tile that left is reused")
show(1415)
MAP.scale, MAP.target, MAP.cx, MAP.cy = 10, 10, 0.45, 0.75
step()
check(tilesShown() == 0, "the continent zoomed until Elwynn fills the frame: still the painted map, as on Elwynn")
MAP.scale, MAP.target = 25, 25
step()
check(tilesShown() > 0 and near(T.layer:GetAlpha(), HALF, 1e-6), "further in on the continent, the terrain comes as it would on the zone")
show(947); step()
check(tilesShown() == 0, "the world map has no place in the grid")
show(1414); step()
check(tilesShown() == 0, "nor does a continent with no tiles listed")
show(1429); MAP.scale, MAP.target, MAP.cx, MAP.cy = 4, 4, 0.5, 0.5
db.terrain = false
T:Refresh(); step()
check(tilesShown() == 0 and not T.layer:IsShown(), "switched off, no terrain")
db.terrain = true
T:Refresh(); step()
check(tilesShown() == 2, "back on")
range(1415, 1, 1, 1); range(1429, 1, 1, 1)
show(947); step()

io.write("== past the game's closest zoom ==\n")
settle()
range(1944, 1, 2, 3)   -- steps at 1, 1.5 and 2
show(1944); aim(0.5, 0.5)
local cap = T:DeepCap(wm)
check(cap and near(cap, 2.5 * 4500 * 256 / (1002 * 1600 / 3), 1e-6),
    ("our zoom goes to x%.2f, where a terrain pixel is 2.5 screen pixels"):format(cap or -1))
wheel(1); glide(1); wheel(1); glide(1)
step()
check(MAP.scale == 2 and T.layer:GetAlpha() == 1, "at the game's closest step: all terrain")
show(1944); aim(0.5, 0.5)
wheel(1); glide(0.05); wheel(1); glide(0.05); wheel(1)
check(Zoom.glide and near(Zoom.glide.to, 3), "notches during the glide in carry on past the closest step into the terrain")
glide(1)
check(MAP.scale == 3, "and get there")
show(1944); aim(0.5, 0.5); wheel(1); glide(1); wheel(1); glide(1)
wheel(1)
check(Zoom.glide and near(Zoom.glide.to, 3), "one notch more goes on into the terrain")
glide(1)
local dx, dy = under()
check(MAP.scale == 3 and near(dx, 0.5) and near(dy, 0.5), "about the cursor, like any other step")
wheel(1); glide(0.05); wheel(1)
check(Zoom.glide and near(Zoom.glide.to, cap), "notches faster than the glide go on, up to the limit")
glide(1)
check(near(MAP.scale, cap), "at the limit")
wheel(1)
check(not Zoom.glide and near(MAP.scale, cap), "and no further")
local hx, hy = MAP.cx, MAP.cy
CURSOR[1], CURSOR[2] = 120, TOP - 120
wheel(1); wheel(1); settleGame()
check(MAP.cx == hx and MAP.cy == hy and near(MAP.scale, cap), "more notches at the limit leave the view where it is")
-- On the way to the limit, a notch that cannot zoom further keeps the
-- glide's spot rather than taking up wherever the cursor has moved to.
ipz(cap / 1.5, MAP.cx, MAP.cy)
aim(0.5, 0.5)
wheel(1)
local heading = Zoom.glide and Zoom.glide.a
glide(0.05)
CURSOR[1], CURSOR[2] = 120, TOP - 120
wheel(1)
check(Zoom.glide and Zoom.glide.a == heading and near(Zoom.glide.to, cap), "a notch on the way to the limit changes nothing")
glide(1)
wheel(-1)
check(Zoom.glide and near(Zoom.glide.to, cap / 1.5), "out comes back by the same steps, not the game's")
glide(1); wheel(-1); glide(1); wheel(-1)
check(Zoom.glide and Zoom.glide.to == 2, "landing on the game's closest step")
glide(1); wheel(-1)
check(Zoom.glide and Zoom.glide.to == 1.5, "and the game's own steps from there")
glide(1)
ipz(2, MAP.cx, MAP.cy)
db.terrain = false
T:Refresh()
wheel(1)
check(not Zoom.glide and MAP.scale == 2, "with the terrain off, the game's closest step is the end")
db.terrain = true
T:Refresh()
if Core.Client.hasSecrets then
    COMBAT = true
    wheel(1)
    check(not Zoom.glide and MAP.scale == 2, "in a fight on a secrets client, no further either")
    COMBAT = false
end
show(1415); aim(0.7, 0.5)
settle(); wheel(1)
check(not Zoom.glide and MAP.id == 1415 and MAP.scale == 1, "a continent with no zone under the cursor goes no further")
range(1944, 1, 1, 1)
show(947); step()

io.write("== the switches ==\n")
settle(); upd(ov, 1); upd(ov, 1)
db.animate = false
show(947); aim(0.2, 0.5)
wheel(1)
check(MAP.id == 1414 and not ov:IsShown(), "zoom off: the map cuts to Kalimdor")
db.animate = true
db.wheel = false
settle(); wheel(-1)
check(MAP.id == 1414, "wheel off: the map stays")
db.wheel = true
if Core.Client.hasSecrets then
    COMBAT = true
    settle(); wheel(-1)
    check(MAP.id == 1414, "in a fight on a secrets client, the wheel leaves the map alone")
    COMBAT = false
    settle(); wheel(-1)
    check(MAP.id == 947, "out of it, the wheel changes maps again")
else
    COMBAT = true
    settle(); wheel(-1)
    check(MAP.id == 947, "no secret values here: a fight changes nothing")
    COMBAT = false
end
noErrors("the wheel")

io.write("== the marker ==\n")
clearChat()
settle(); upd(ov, 1); upd(ov, 1)
MAP.id = 1415
check(rightClick(0.45, 0.75, "LeftButton") == false, "a left click is the game's")
SHIFT = true
check(rightClick(0.45, 0.75) == false, "Shift+right-click goes up a level, as before")
SHIFT = false
db.rightClick = false
check(rightClick(0.45, 0.75) == false, "switched off, a right-click is the game's")
db.rightClick = true

local SET, TRACK, CLEARED = nil, nil, 0
if MODE ~= "tbc" then
    -- The game's waypoint, as Forever has it. It goes on zones only.
    UiMapPoint = { CreateFromCoordinates = function(id, x, y) return { uiMapID = id, position = vec(x, y) } end }
    C_SuperTrack = { SetSuperTrackedUserWaypoint = function(v) TRACK = v end }
    C_Map.CanSetUserWaypointOnMap = function(id) return MAPS[id] and MAPS[id].type == 3 end
    C_Map.SetUserWaypoint = function(p) SET = p end
    C_Map.ClearUserWaypoint = function() SET = nil; CLEARED = CLEARED + 1 end
    C_Map.HasUserWaypoint = function() return SET ~= nil end
    C_Map.GetUserWaypoint = function() return SET end
    C_Map.GetUserWaypointPositionForMap = function(id)
        if not SET then return nil end
        if id == SET.uiMapID then return SET.position end
        local cont, pos = C_Map.GetWorldPosFromMapPos(SET.uiMapID, SET.position)
        local _, mp = C_Map.GetMapPosFromWorldPos(cont, pos, id)
        return mp
    end
    check(Marker:Native(), "the game's waypoint is used")
    check(rightClick(0.45, 0.71) == true, "right-click on the continent is ours")
    check(SET and SET.uiMapID == 1429 and near(SET.position.x, 0.5) and near(SET.position.y, 0.1),
        "the waypoint lands in Elwynn, at the same spot")
    check(TRACK == true, "and is tracked, so the game shows it in the world")
    check(not Marker.layer:IsShown() and not (Marker.win and Marker.win:IsShown()), "no pin or arrow of ours beside it")
    check(rightClick(0.4505, 0.7105) == true and SET == nil and CLEARED == 1 and TRACK == false, "right-click on it again takes it away")
    -- A realm whose rules switch the map pin off gets ours instead.
    Enum = Enum or {}
    Enum.GameRule = { WorldMapTrackingPinDisabled = 77 }
    C_GameRules = C_GameRules or {}
    C_GameRules.IsGameRuleActive = function(rule) return rule == 77 end
    check(not Marker:Native(), "with the rule on, our own marker")
end

check(rightClick(0.45, 0.71) == true, "right-click on the continent drops a marker")
local m = db.marker
check(m and m.mapID == 1429 and near(m.x, 0.5) and near(m.y, 0.1), "kept on Elwynn, at the same spot")
check(Marker.layer:IsShown(), "the pin layer shows")
Marker.layer.__scripts.OnUpdate(Marker.layer)
local p, rel, rp, px, py = Marker.layer.pin:GetPoint()
check(rp == "TOPLEFT" and near(px, 0.45 * 1002, 0.01) and near(py, -0.71 * 668, 0.01),
    ("the pin sits on Elwynn's spot on the continent (%.1f, %.1f)"):format(px or -1, py or -1))
MAP.id = 1429
Marker.layer.__scripts.OnUpdate(Marker.layer)
p, rel, rp, px, py = Marker.layer.pin:GetPoint()
check(near(px, 0.5 * 1002, 0.01) and near(py, -0.1 * 668, 0.01), "and on the zone map where it was dropped")

local win = Marker.win
check(win and win:IsShown(), "the arrow window shows")
local ROT
rawset(win.arrow, "SetRotation", function(_, r) ROT = r end)
Marker:UpdateArrow()
check(plain(win.dist:GetText()) == "640 yd", "640 yards to the marker: " .. plain(win.dist:GetText()))
check(near(ROT, 0, 1e-6), "facing north, the arrow points straight up")
FACING = math.pi / 2
Marker:UpdateArrow()
check(near(ROT, -math.pi / 2, 1e-6), "facing west, it points right")
FACING = 0
db.marker = { mapID = 1429, x = 0.9, y = 0.9 }
Marker:UpdateArrow()
check(plain(win.dist:GetText()) == "480 yd" and near(ROT, -math.pi / 2, 1e-6), "a marker due east: 480 yards, pointing right")
check(Marker:Describe():find("Elwynn Forest  90.0, 90.0", 1, true) ~= nil, "the launcher line: " .. tostring(Marker:Describe()))

MAP.id = 1415
check(rightClick(0.49, 0.79) == true and db.marker == nil, "right-click on the marker takes it away")
check(not Marker.layer:IsShown() and not win:IsShown(), "and the pin and arrow go with it")

io.write("== the slash command and arrival ==\n")
slash("45.5 61")
m = db.marker
check(m and m.mapID == 1429 and near(m.x, 0.455) and near(m.y, 0.61), "/wmap 45.5 61 puts a marker in the zone you are in")
check(win:IsShown(), "with the arrow")
win.close:Click()
check(not win:IsShown() and Marker.arrowClosed, "closing the arrow puts it away")
Marker:Refresh()
check(not win:IsShown(), "and it stays away for this marker")
PLAYER.x, PLAYER.y = 0.455, 0.612
Marker.arrowClosed = nil
clearChat()
Marker:Refresh()
check(db.marker == nil and chatSince():find("reached your marker", 1, true) ~= nil, "walking onto it puts it away: " .. chatSince())
slash("12 34")
slash("clear")
check(db.marker == nil, "/wmap clear takes it away")
clearChat()
slash("clear")
check(chatSince():find("no marker", 1, true) ~= nil, "and says so when there is none")
slash("200 10")
check(db.marker == nil, "coordinates past 100 are refused")
MAP.id = 947
check(rightClick(0.55 + 0.45 * 0.4, 0.1 + 0.71 * 0.8) == true, "right-click on the world map")
m = db.marker
check(m and m.mapID == 1429 and near(m.x, 0.5) and near(m.y, 0.1), "lands in Elwynn through the continent")
slash("clear")
clearChat()
check(rightClick(0.2, 0.5) == true and db.marker == nil, "a place with no world position is refused")
check(chatSince():find("cannot go there", 1, true) ~= nil, "and says why: " .. chatSince())
clearChat()
noErrors("the marker")

io.write("== nothing of ours on the game's map ==\n")
local function added(t, was)
    local out = {}
    for k in pairs(t) do if not was[k] then out[#out + 1] = tostring(k) end end
    table.sort(out)
    return out
end
local a1, a2, a3 = added(wm, before.wm), added(sc, before.sc), added(canvas, before.canvas)
-- targetScale is the fake's own stand-in for the canvas field it reads.
for i = #a2, 1, -1 do if a2[i] == "targetScale" then table.remove(a2, i) end end
check(#a1 == 0 and #a2 == 0 and #a3 == 0, "no new fields on the map, its scroll frame or its canvas"
    .. ((#a1 + #a2 + #a3 > 0) and ("  [" .. table.concat(a1, ",") .. " | " .. table.concat(a2, ",") .. " | " .. table.concat(a3, ",") .. "]") or ""))

local missing = S.missingReport()
io.write("\nAPI the stub answered with nil: ", table.concat(missing, ", "), "\n")
io.write(("\n%s: %d passed, %d failed\n"):format(MODE, passes, fails))
if fails > 0 then error(("%d check(s) failed"):format(fails), 0) end
print("PASS")
