-- Wick's Map offline harness. A small fake world map (Cosmic > Azeroth >
-- Eastern Kingdoms > Elwynn Forest, Kalimdor beside it) with the parts of
-- the game's map canvas Wick's Map reads, and the C_Map answers for it.
--   The wheel: down a level at the end of the game's zoom, up a level at
--   the start of it, never while the game is still zooming, the pause
--   between steps, the zoom overlay, the switches, and on a secrets client
--   no change during a fight.
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
local MAPS = {
    [946]  = { name = "Cosmic", parent = 0, type = 0 },
    [947]  = { name = "Azeroth", parent = 946, type = 1 },
    [1414] = { name = "Kalimdor", parent = 947, type = 2, cont = 1 },
    [1415] = { name = "Eastern Kingdoms", parent = 947, type = 2, cont = 0 },
    [1429] = { name = "Elwynn Forest", parent = 1415, type = 3, cont = 0 },
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
local function vec(x, y) return { x = x, y = y, GetXY = function(v) return v.x, v.y end } end

local PLAYER = { map = 1429, x = 0.5, y = 0.9 }
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
        return { { layerWidth = 1002, layerHeight = 668, tileWidth = 256, tileHeight = 256, minScale = 1, maxScale = 1 } }
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
    GetPlayerMapPosition = function(id)
        if id ~= PLAYER.map then return nil end
        return vec(PLAYER.x, PLAYER.y)
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
local MAP = { id = 947, scale = 1, target = 1, lo = 1, hi = 1, cursor = { 0.7, 0.5 }, set = {}, handlers = {} }
local wm = S.newMock("Frame", "WorldMapFrame")
local sc = S.newMock("ScrollFrame")
local canvas = S.newMock("Frame")
rawset(canvas, "GetLeft", function() return 0 end)
rawset(canvas, "GetTop", function() return 100 end)
rawset(canvas, "GetWidth", function() return 1002 end)
rawset(canvas, "GetHeight", function() return 668 end)
rawset(sc, "Child", canvas)
rawset(sc, "GetCanvasScale", function() return MAP.scale end)
rawset(sc, "GetScaleForMinZoom", function() return MAP.lo end)
rawset(sc, "GetScaleForMaxZoom", function() return MAP.hi end)
-- Forever's canvas asks the click-through question; TBC's has no such
-- method. Declared either way, because the stub's frames make up any
-- method they are asked for, and that would read as a field we wrote.
rawset(sc, "ShouldNavigateIgnoreZoneMapPositionData", MODE ~= "tbc" and function() return false end or false)
-- The game's own wheel handler, as the canvas runs it: a zoom target
-- within the map's range.
sc:SetScript("OnMouseWheel", function(_, delta)
    if delta > 0 and MAP.scale < MAP.hi then MAP.target = MAP.hi
    elseif delta < 0 and MAP.scale > MAP.lo then MAP.target = MAP.lo end
    rawset(sc, "targetScale", MAP.target)
end)
rawset(wm, "ScrollContainer", sc)
rawset(wm, "GetMapID", function() return MAP.id end)
rawset(wm, "SetMapID", function(_, id) MAP.id = id; MAP.scale, MAP.target = MAP.lo, MAP.lo; MAP.set[#MAP.set + 1] = id end)
rawset(wm, "GetCanvas", function() return canvas end)
rawset(wm, "GetNormalizedCursorPosition", function() return MAP.cursor[1], MAP.cursor[2] end)
rawset(wm, "AddCanvasClickHandler", function(_, fn, pri) MAP.handlers[#MAP.handlers + 1] = { fn = fn, pri = pri } end)
-- targetScale is read with rawget, as the canvas keeps it.
local function syncTarget() rawset(sc, "targetScale", MAP.target) end
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
Core.debug = true   -- handler errors reach chat, where they are checked
S.fire("PLAYER_LOGIN")
S.fire("PLAYER_ENTERING_WORLD", true, false)
local ns = WicksMap
local A = Core.addons.WicksMap
local db = ns.DB()
local Zoom, Marker = ns.Zoom, ns.Marker

local function wheel(delta)
    syncTarget()
    local fn = sc.__scripts.OnMouseWheel
    fn(sc, delta)
    syncTarget()
end
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
check(db.wheel and db.animate and db.rightClick and db.arrow and db.autoClear, "every switch starts on")
check(Core.Options.pages.WicksMap ~= nil, "a page under Wick's Mods")
check(Core.Launcher.entries.WicksMap ~= nil, "a line in the launcher")
check(ns.attached and Zoom.attached and Marker.attached, "hooked onto the world map")
check(#MAP.handlers == 1 and MAP.handlers[1].pri == 100, "one canvas click handler, ahead of the game's")
local native = Marker:Native()
check(native == (MODE ~= "tbc" and C_Map.SetUserWaypoint ~= nil), "the game's waypoint only where the client has one")

io.write("== the wheel ==\n")
clearChat()
MAP.id, MAP.cursor = 947, { 0.7, 0.5 }
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
wheel(1)
check(MAP.id == 1415, "a second notch straight after waits out the pause")
local upd = ov.__scripts.OnUpdate
upd(ov, 0.16)
check(Zoom.anim and Zoom.anim.phase == "zoom" and ov.front:GetAlpha() > 0, "halfway: the continent is coming in")
upd(ov, 0.2)
check(Zoom.anim and Zoom.anim.phase == "fade", "the camera move ends, then the fade")
local s = ov.front:GetScale()
check(near(s * 1002, 1002, 0.01) and near(ov.front:GetAlpha(), 1), "ending exactly over the game's map")
upd(ov, 0.2)
check(not Zoom.anim and not ov:IsShown(), "and the overlay is gone")

settle()
MAP.cursor = { 0.45, 0.75 }
wheel(1)
check(MAP.id == 1429, "in over Elwynn on the continent opens Elwynn Forest")
check(ov.front.used == 12 + 2, "the zone's explored parts are drawn over its art: " .. tostring(ov.front.used))
local ex = ov.front.tex[13]
local ew, eh = ex:GetSize()
check(ew == 256 and eh == 200 and ov.front.tex[14]:GetSize() == 44, "explored pieces cropped the way the game crops them")
settle()
wheel(1)
check(MAP.id == 1429, "nothing deeper under the cursor: the map stays")
settle()
MAP.cursor = { 0.5, 0.5 }
wheel(-1)
check(MAP.id == 1415 and Zoom.anim and Zoom.anim.dir == "out", "out goes up to the continent, zooming out")
check(near(Zoom.anim.E.x, 0.40 * 1002) and near(Zoom.anim.E.w, 0.1 * 1002), "the zone shrinks into its place on the continent")
settle(); upd(ov, 1); upd(ov, 1)
wheel(-1); check(MAP.id == 947, "out again: Azeroth")
settle(); wheel(-1); check(MAP.id == 946, "and the cosmic map")
settle(); wheel(-1); check(MAP.id == 946, "nothing above that")

io.write("== the game's own zoom comes first ==\n")
settle()
MAP.id, MAP.lo, MAP.hi, MAP.scale, MAP.target = 1415, 1, 2, 1, 1
MAP.cursor = { 0.45, 0.75 }
wheel(1)
check(MAP.id == 1415 and MAP.target == 2, "a map that zooms: the first notch zooms it")
MAP.scale = 1.5
settle(); wheel(1)
check(MAP.id == 1415, "still on its way in: the map stays")
MAP.scale = 2; MAP.target = 2
settle(); wheel(1)
check(MAP.id == 1429, "all the way in: the next notch opens the zone")
MAP.id, MAP.lo, MAP.hi, MAP.scale, MAP.target = 1415, 1, 2, 2, 2
settle(); wheel(-1)
check(MAP.id == 1415 and MAP.target == 1, "zoomed in, out first zooms back out")
MAP.scale = 1; MAP.target = 1
settle(); wheel(-1)
check(MAP.id == 947, "all the way out: up a level")
MAP.lo, MAP.hi, MAP.scale, MAP.target = 1, 1, 1, 1

io.write("== the switches ==\n")
settle(); upd(ov, 1); upd(ov, 1)
db.animate = false
MAP.id, MAP.cursor = 947, { 0.2, 0.5 }
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
