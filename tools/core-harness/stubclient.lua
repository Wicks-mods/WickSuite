-- Stub WoW client for offline load tests. Shared by the WickCore harness and
-- the per-product harnesses.
--
--   local S = assert(loadfile("stubclient.lua"))("modern" | "legacy")
--
-- Returns a table with fire(event, ...), SECRET, SENT, CHAT, MISSING and the
-- mode flag. World state is global so tests can flip it: COMBAT, LOGGED,
-- IN_GROUP, BANK_OPEN.

unpack = unpack or table.unpack
math.atan2 = math.atan2 or math.atan
date = os.date
time = os.time
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
strsplit = strsplit or function(sep, s) local out = {} for piece in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = piece end return unpack(out) end
strtrim = strtrim or function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
format = string.format

-- Three client shapes:
--   "modern"  Forever: the 12.x engine, Mainline FrameXML, secrets on.
--   "tbc"     TBC Anniversary 2.5.6: the same engine with Classic FrameXML.
--             The modern API set, plus the legacy globals as deprecation
--             fallbacks; no secrets, no aura containers, no ping, no class
--             talents, no InterfaceOptions panel.
--   "legacy"  The lowest common denominator: an Era-shaped client with
--             none of the modern API.
-- S.modern is "speaks the modern API"; S.forever is "is Forever".
local MODE = ... or "modern"
local TBC = MODE == "tbc"
local MODERN = MODE == "modern" or TBC
-- Midnight rules (secret values in combat, aura reads that throw) are
-- Forever's alone; TBC has the API shape without the restrictions.
local SECRETS = MODE == "modern"
local S = { mode = MODE, modern = MODERN, tbc = TBC, forever = MODE == "modern", secrets = SECRETS,
            SENT = {}, CHAT = {}, MISSING = {} }

COMBAT = false
LOGGED = true
IN_GROUP = false
BANK_OPEN = false
OPENED = nil

-- A secret value, modelled on what the live client does with one.
--
-- It can be passed along and rendered, and nothing else. Reading a
-- method off it, concatenating it, measuring it or ordering it all
-- raise the way the client raises, with the client's wording, so a
-- harness check reproduces the error a player would actually see.
--
-- What cannot be modelled: `secret == "x"`. Lua only consults __eq when
-- both operands are tables, so a comparison against a string literal
-- returns false here and raises in game. That is the exact shape of the
-- bug that spammed the chat frame from Board.lua, so code handling an
-- event payload is expected to ask issecretvalue first and not to lean
-- on this stub noticing.
local function secretRefusal(op)
    return function()
        error("attempt to " .. op .. " a secret string value, while execution "
            .. "tainted by an AddOn", 2)
    end
end

S.SECRET = setmetatable({}, {
    __tostring = function() return "<secret>" end,
    __index    = secretRefusal("index"),
    __concat   = secretRefusal("concatenate"),
    __len      = secretRefusal("get length of"),
    __lt       = secretRefusal("compare"),
    __le       = secretRefusal("compare"),
})
local SECRET = S.SECRET

-- Any read of an undefined global is recorded, so a harness can print what the
-- code under test reached for that the stub does not provide.
setmetatable(_G, { __index = function(_, k)
    if type(k) == "string" then S.MISSING[k] = (S.MISSING[k] or 0) + 1 end
    return nil
end })

-- ---------- mock frames -------------------------------------------------
-- Real clients accept nearly any event name; only a few are flavor-specific.
-- Registering one of these raises, which is what WickCore's pcall fallbacks
-- are tested against.
-- The TBC list is the 2.5.6 probe's (WickSuite/data/probe-reports, 2026-10-02):
-- of the events the suite registers, these seven the client refused.
local INVALID_EVENTS = TBC
    and { HONOR_LEVEL_UPDATE = true, UNIT_POWER_POINT_CHARGE = true, LEARNED_SPELL_IN_TAB = true,
          ACTIVE_COMBAT_CONFIG_CHANGED = true, GAME_RULES_CHANGED = true, PLAYER_SWING = true,
          PLAYER_SWING_RANGE_UPDATE = true }
    or MODERN
    and { LEARNED_SPELL_IN_TAB = true, TRADE_SKILL_UPDATE = true }
    or  { ADDON_RESTRICTION_STATE_CHANGED = true, BANK_TABS_CHANGED = true, TRAIT_CONFIG_UPDATED = true,
          ACTIVE_COMBAT_CONFIG_CHANGED = true, CURRENCY_DISPLAY_UPDATE = true }
local function eventValid(e) return type(e) == "string" and e:match("^[A-Z][A-Z0-9_]+$") ~= nil and not INVALID_EVENTS[e] end

-- Widgets built on Model rather than on Frame, and the scripts they
-- will not take. Learned from the game, which raises on the assignment.
local MODEL_KINDS = {
    Model = true, DressUpModel = true, PlayerModel = true,
    CinematicModel = true, ModelScene = true,
}
local NOT_ON_MODEL = { OnDoubleClick = true, OnClick = true }

S.SPELL_NAMES = { [1784] = "Stealth", [1752] = "Sinister Strike" }

local ALL_FRAMES = {}
S.frames = ALL_FRAMES
S.regions = {}

local function newMock(kind, name)
    local self = { __kind = kind, __name = name, __scripts = {}, __events = {}, __w = 100, __h = 100,
                   __shown = false, __text = "", __children = {} }
    local mt = {}
    mt.__index = function(t, k)
        if k == "RegisterEvent" then
            return function(_, e)
                if not eventValid(e) then error("Attempt to register unknown event '" .. tostring(e) .. "'", 2) end
                t.__events[e] = true
            end
        elseif k == "UnregisterEvent" then return function(_, e) t.__events[e] = nil end
        elseif k == "UnregisterAllEvents" then return function() t.__events = {} end
        elseif k == "SetScript" then return function(_, n, fn)
                -- A model widget does not inherit the click handlers a
                -- frame has, and the client raises rather than ignoring
                -- one. Taking it quietly is how a line that cannot run
                -- in the game stayed green here.
                if MODEL_KINDS[t.__kind] and NOT_ON_MODEL[n] then
                    error(t.__kind .. ":SetScript(): Cannot assign script handler for '"
                        .. n:lower() .. "' (script type not supported by this object)", 2)
                end
                t.__scripts[n] = fn
            end
        elseif k == "HookScript" then return function(_, n, fn)
                local prev = t.__scripts[n]
                t.__scripts[n] = function(...) if prev then prev(...) end fn(...) end
            end
        elseif k == "GetScript" then return function(_, n) return t.__scripts[n] end
        -- Regions are tracked like frames. Only frames were, so a check
        -- about what a theme repaints had nothing to look at: the
        -- things that carry a colour are textures and font strings.
        elseif k == "CreateTexture" or k == "CreateFontString" or k == "CreateLine" then
            return function()
                local r = newMock(k)
                -- Which file painted it, so a check can ask about one
                -- addon rather than about every region at once.
                local info = debug.getinfo(2, "S")
                r.__src = info and info.short_src or "?"
                S.regions[#S.regions + 1] = r
                return r
            end
        -- Whether a frame takes mouse input decides whether it swallows a
        -- click meant for what is underneath it, so it is worth recording.
        elseif k == "SetAltArrowKeyMode" then return function(_, v) t.__altArrow = v and true or false end
        elseif k == "SetFacing" then return function(_, v) t.__facing = v end
        -- Putting a unit on a model puts it back to front-on, which is
        -- the reason anything that redresses has to turn it back.
        elseif k == "SetUnit" then return function() t.__facing = 0 end
        elseif k == "SetFrameStrata" then return function(_, v) t.__strata = v end
        elseif k == "GetFrameStrata" then return function() return t.__strata end
        elseif k == "EnableMouse" then return function(_, v) t.__mouseEnabled = v and true or false end
        elseif k == "IsMouseEnabled" then return function() return t.__mouseEnabled end
        elseif k == "IsShown" or k == "IsVisible" then return function() return t.__shown end
        elseif k == "Show" then return function() t.__shown = true; if t.__scripts.OnShow then t.__scripts.OnShow(t) end end
        elseif k == "Hide" then return function()
                local was = t.__shown
                t.__shown = false
                -- A box that hides lets go of the keyboard, as the client's do.
                if t.__focus then
                    t.__focus = false
                    if t.__scripts.OnEditFocusLost then t.__scripts.OnEditFocusLost(t) end
                end
                if was and t.__scripts.OnHide then t.__scripts.OnHide(t) end
            end
        -- Edit box focus. Each box keeps its own; that one box at a time
        -- holds the keyboard is not modelled, a check asks about one box.
        -- An unknown method answers with a mock, and a mock is true, so
        -- without these every box read as focused.
        elseif k == "SetFocus" then return function()
                if t.__focus then return end
                t.__focus = true
                if t.__scripts.OnEditFocusGained then t.__scripts.OnEditFocusGained(t) end
            end
        elseif k == "ClearFocus" then return function()
                if not t.__focus then return end
                t.__focus = false
                if t.__scripts.OnEditFocusLost then t.__scripts.OnEditFocusLost(t) end
            end
        elseif k == "HasFocus" then return function() return t.__focus and true or false end
        -- A click from code runs the button's click script, as in the game.
        elseif k == "Click" then return function(_, button)
                if t.__scripts.OnClick then t.__scripts.OnClick(t, button or "LeftButton", false) end
            end
        elseif k == "SetShown" then return function(_, v) if v then t:Show() else t:Hide() end end
        elseif k == "SetSize" then return function(_, w, h) t.__w, t.__h = w, h end
        elseif k == "SetWidth" then return function(_, w) t.__w = w end
        elseif k == "SetWordWrap" then return function(_, v) t.__wordWrap = v and true or false end
        elseif k == "SetHeight" then return function(_, h) t.__h = h end
        elseif k == "GetWidth" then return function() return t.__w end
        elseif k == "GetHeight" then return function() return t.__h end
        elseif k == "GetSize" then return function() return t.__w, t.__h end
        elseif k == "GetCenter" then return function() return 0, 0 end
        elseif k == "GetLeft" or k == "GetBottom" then return function() return 0 end
        elseif k == "GetRight" or k == "GetTop" then return function() return 100 end
        -- Scale is recorded rather than shrugged off, because point
        -- offsets are read in the frame's own scale: code that rescales
        -- a frame and does not correct for it walks the frame across
        -- the screen, and a stub that always answers 1 cannot show it.
        elseif k == "SetScale" then return function(_, v) t.__scale = tonumber(v) or 1 end
        elseif k == "GetEffectiveScale" or k == "GetScale" then return function() return t.__scale or 1 end
        elseif k == "ClearAllPoints" then return function() t.__points = {} end
        elseif k == "GetPoint" then return function()
                local pts = t.__points
                local p = pts and pts[#pts]
                -- Nothing anchored yet: the old fixed answer, so the
                -- checks written against it still mean what they did.
                if not p then return "CENTER", nil, "CENTER", 12, -34 end
                return p[1], p[2], p[3], p[4], p[5]
            end
        elseif k == "SetPoint" then return function(_, point, rel, ...)
                -- SetPoint has three shapes and they have to be stored
                -- as one, or GetPoint hands back the arguments of
                -- whichever shape was used last.
                -- Retail rule: a protected frame (secure templates) may anchor
                -- only to frames, never to a texture or font string.
                if MODERN and t.__template and t.__template:find("^Secure") and type(rel) == "table"
                   and (rel.__kind == "Texture" or rel.__kind == "FontString" or rel.__kind == "CreateTexture" or rel.__kind == "CreateFontString") then
                    error("Action[SetPoint] failed because[Cannot anchor protected frames to regions]: attempted from: Button:SetPoint.", 2)
                end
                local a, b, c = ...
                local relPoint, x, y
                if rel == nil or type(rel) == "number" then
                    -- SetPoint(point), SetPoint(point, x, y)
                    relPoint, x, y, rel = point, rel, a, t.__parent
                elseif type(a) == "string" then
                    -- SetPoint(point, relativeTo, relativePoint, x, y).
                    -- The string is what tells the two apart: the other
                    -- shape has a number in that slot.
                    relPoint, x, y = a, b, c
                else
                    -- SetPoint(point, relativeTo, x, y)
                    relPoint, x, y = point, a, b
                end
                t.__points = t.__points or {}
                t.__points[#t.__points + 1] = { point, rel, relPoint, x, y }
            end
        -- SetAllPoints is two anchors, which is how a page that fills its
        -- window is held; GetNumPoints counts what is stored, so a check
        -- can tell a page in its window from one pulled out of it. A frame
        -- never anchored still answers 1, as it always did.
        elseif k == "SetAllPoints" then return function(_, rel)
                rel = rel or t.__parent
                t.__points = { { "TOPLEFT", rel, "TOPLEFT", 0, 0 }, { "BOTTOMRIGHT", rel, "BOTTOMRIGHT", 0, 0 } }
            end
        elseif k == "GetNumPoints" then return function()
                local n = t.__points and #t.__points or 0
                return n > 0 and n or 1
            end
        elseif k == "SetText" then return function(_, s, r, g, b, a, wrap)
                -- Retail tooltips: SetText(text [, r, g, b, a, wrap]) or a color
                -- object; argument five must be a number. TBC accepted the wrap
                -- flag there because alpha was optional.
                if MODERN and t.__kind == "GameTooltip" and a ~= nil and type(a) ~= "number" then
                    error("bad argument #5 to 'SetText' (outside of expected range -3.402823e+38 to 3.402823e+38 - Usage: self:SetText(text [, color, alpha, wrap]))", 2)
                end
                t.__text = s
            end
        elseif k == "GetText" then return function() return t.__text end
        elseif k == "GetStringWidth" then return function() return #tostring(t.__text) * 6 end
        -- Height has to account for wrapping, because that is the part
        -- layout code gets wrong: a note that wraps to three lines but
        -- reports one line of height lands under whatever follows it.
        elseif k == "GetStringHeight" then
            return function()
                local txt = tostring(t.__text or "")
                local perLine = math.max(1, math.floor((t.__w or 300) / 5.5))
                local lines = 0
                for chunk in (txt .. "\n"):gmatch("([^\n]*)\n") do
                    lines = lines + math.max(1, math.ceil(#chunk / perLine))
                end
                return math.max(1, lines) * 13
            end
        elseif k == "GetName" then return function() return t.__name end
        elseif k == "GetObjectType" then return function() return t.__kind end
        elseif k == "GetParent" then return function() return t.__parent end
        elseif k == "SetParent" then return function(_, p) t.__parent = p end
        elseif k == "GetItem" then return function() return "Hearthstone", "|Hitem:6948|h[Hearthstone]|h" end
        elseif k == "GetChecked" then return function() return t.__checked end
        elseif k == "SetChecked" then return function(_, v) t.__checked = v end
        elseif k == "IsMouseOver" then return function() return false end
        -- Recorded rather than fixed at 1, so a check can ask which of
        -- two overlapping buttons the click belongs to.
        elseif k == "SetID" then return function(_, v) t.__id = v end
        elseif k == "GetID" then return function() return t.__id or 0 end
        elseif k == "SetFrameLevel" then return function(_, v) t.__level = v end
        elseif k == "GetFrameLevel" then return function() return t.__level or 1 end
        elseif k == "GetFrameStrata" then return function() return "MEDIUM" end
        elseif k == "SetAlpha" then return function(_, a) t.__alpha = a end
        elseif k == "GetAlpha" then return function() return t.__alpha or 1 end
        elseif k == "GetTexture" then return function() return t.__tex end
        elseif k == "SetTexture" then return function(_, v) t.__tex = v end
        elseif k == "SetDesaturated" then return function(_, v) t.__desaturated = v and true or false end
        elseif k == "SetMaskTexture" then return function(_, v) t.__maskTex = v end
        elseif k == "GetNumLines" then return function() return 1 end
        elseif k == "NumLines" then return function() return 1 end
        elseif k == "GetCursorPosition" then return function() return 0 end
        -- A button's enabled state, kept, so a check can switch one off
        -- and see what is drawn for it.
        elseif k == "IsEnabled" then return function() return not t.__disabled end
        elseif k == "Enable" then return function() t.__disabled = nil end
        elseif k == "Disable" then return function() t.__disabled = true end
        elseif k == "SetEnabled" then return function(_, v) t.__disabled = not v or nil end
        elseif k == "SetAttribute" then return function(_, a, v)
                -- A protected frame's attributes are locked for the
                -- duration of a fight. Anything that wants to change
                -- what it does mid-combat has to not be secure.
                if COMBAT and t.__template and t.__template:find("Secure") then
                    error("Interface action failed because of an AddOn", 2)
                end
                t.__attr = t.__attr or {}
                t.__attr[a] = v
            end
        elseif k == "GetAttribute" then return function(_, a) return t.__attr and t.__attr[a] end
        elseif k == "SetStatusBarColor" then return function(_, r, g, b, a) t.__color = { r, g, b, a } end
        elseif k == "SetStatusBarTexture" then return function(_, tex) t.__statusTex = tex end
        elseif k == "GetStatusBarTexture" then return function() return t.__statusTexObj or t end
        elseif k == "SetColorTexture" then return function(_, r, g, b, a) t.__color = { r, g, b, a } end
        elseif k == "SetTextColor" then return function(_, r, g, b, a) t.__textColor = { r, g, b, a } end
        elseif k == "GetTextColor" then return function()
                local c = t.__textColor or { 1, 1, 1, 1 }
                return c[1], c[2], c[3], c[4] or 1
            end
        elseif k == "SetTextHeight" then return function(_, h) t.__textHeight = h end
        -- Slider
        elseif k == "SetMinMaxValues" then return function(_, lo, hi) t.__min, t.__max = lo, hi end
        elseif k == "GetMinMaxValues" then return function() return t.__min or 0, t.__max or 0 end
        elseif k == "SetValue" then return function(_, v) t.__value = v end
        elseif k == "GetValue" then return function() return t.__value or 0 end
        elseif k == "SetValueStep" then return function(_, v) t.__step = v end
        elseif k == "GetValueStep" then return function() return t.__step or 1 end
        -- ScrollFrame
        elseif k == "SetScrollChild" then return function(_, c) t.__scrollChild = c end
        elseif k == "GetScrollChild" then return function() return t.__scrollChild end
        elseif k == "GetVerticalScroll" then return function() return t.__scroll or 0 end
        elseif k == "SetVerticalScroll" then return function(_, v) t.__scroll = v end
        elseif k == "GetVerticalScrollRange" then return function() return 0 end
        end
        if type(k) ~= "string" or not k:match("^[A-Z]") then return nil end
        local blocked = rawget(t, "__nokeys")
        if blocked and blocked[k] then return nil end
        -- Unknown Capitalized key: either a method we do not model or a template
        -- child region (b.IconBorder, b.Count). A callable child mock serves
        -- both: b:Foo() calls it, b.Foo:Hide() indexes it.
        local child = newMock(k)
        child.__parent = t
        rawset(t, k, child)
        return child
    end
    mt.__call = function(t) return t end
    return setmetatable(self, mt)
end
S.newMock = newMock

-- Templates whose base type is the retail intrinsic ItemButton. Creating one
-- as a plain "Button" on a modern client keeps the virtual template's own
-- children but drops the intrinsic's regions (icon, Count, IconBorder,
-- NormalTexture), which is exactly what Forever did on first login.
local ITEM_BUTTON_TEMPLATES = { ContainerFrameItemButtonTemplate = true, ItemButtonTemplate = true }
local INTRINSIC_KEYS = { Count = true, IconTexture = true, IconBorder = true, IconOverlay = true,
                         IconOverlay2 = true, NormalTexture = true, PushedTexture = true, Stock = true }
S.ITEM_BUTTONS = {}

function CreateFrame(kind, name, parent, template)
    kind = kind or "Frame"
    if kind == "ItemButton" and not MODERN then
        error("CreateFrame: Unknown frame type 'ItemButton'", 2)
    end
    -- The aura container intrinsic is Forever's alone (Blizzard_AuraContainer
    -- is not in the TBC 2.5.6 UI source).
    if kind == "AuraContainer" and (TBC or not MODERN) then
        error("CreateFrame: Unknown frame type 'AuraContainer'", 2)
    end
    local f = newMock(kind, name)
    f.__parent = parent
    f.__template = template
    if name then _G[name] = f end
    if MODERN and (kind == "ItemButton" or (template and ITEM_BUTTON_TEMPLATES[template])) then
        if kind == "ItemButton" then
            -- Intrinsic regions, keyed and named the way the XML does it.
            f.icon = newMock("Texture", name and (name .. "IconTexture"))
            f.Count = newMock("FontString", name and (name .. "Count"))
            f.IconBorder = newMock("Texture")
            f.NormalTexture = newMock("Texture", name and (name .. "NormalTexture"))
            if name then
                _G[name .. "IconTexture"] = f.icon
                _G[name .. "Count"] = f.Count
                _G[name .. "NormalTexture"] = f.NormalTexture
            end
        else
            -- Wrong base type: the intrinsic's regions never exist.
            f.__nokeys = INTRINSIC_KEYS
        end
        S.ITEM_BUTTONS[#S.ITEM_BUTTONS + 1] = f
    elseif template and ITEM_BUTTON_TEMPLATES[template] and name then
        -- Legacy client: the old XML template names its regions globally.
        f.__legacyRegions = true
        _G[name .. "IconTexture"] = newMock("Texture", name .. "IconTexture")
        _G[name .. "Count"] = newMock("FontString", name .. "Count")
    end
    ALL_FRAMES[#ALL_FRAMES + 1] = f
    return f
end

function S.fire(event, ...)
    for _, f in ipairs(ALL_FRAMES) do
        if f.__events[event] and f.__scripts.OnEvent then
            local ok, err = pcall(f.__scripts.OnEvent, f, event, ...)
            if not ok then print("  OnEvent error (" .. event .. "): " .. tostring(err)) end
        end
    end
end

UIParent = newMock("Frame", "UIParent"); UIParent.__w, UIParent.__h = 1600, 900
Minimap = newMock("Minimap", "Minimap"); Minimap.__w = 140
-- Forever ships the compass ring and keeps the zoom controls on the frame.
-- Classic FrameXML (TBC and Era) keeps the old round border and the named
-- cluster pieces around it.
if MODERN and not TBC then
    -- Blizzard sizes the container to the ring art, larger than the map.
    MinimapCluster = newMock("Frame", "MinimapCluster")
    MinimapCluster.MinimapContainer = newMock("Frame", "MinimapContainer")
    MinimapCluster.MinimapContainer.__w, MinimapCluster.MinimapContainer.__h = 240, 240
    Minimap.__w, Minimap.__h = 198, 198
    MinimapCompassTexture = newMock("Texture", "MinimapCompassTexture")
    MinimapCompassTextureUnderlay = newMock("Texture", "MinimapCompassTextureUnderlay")
else
    MinimapCluster = newMock("Frame", "MinimapCluster")
    MinimapBorder = newMock("Texture", "MinimapBorder")
    MinimapBorderTop = newMock("Texture", "MinimapBorderTop")
    MinimapZoneTextButton = newMock("Button", "MinimapZoneTextButton")
    MiniMapMailFrame = newMock("Frame", "MiniMapMailFrame")
    MiniMapTracking = newMock("Frame", "MiniMapTracking")
    MiniMapBattlefieldFrame = newMock("Frame", "MiniMapBattlefieldFrame")
    GameTimeFrame = newMock("Button", "GameTimeFrame")
    MinimapZoomIn = newMock("Button", "MinimapZoomIn")
    MinimapZoomOut = newMock("Button", "MinimapZoomOut")
    MiniMapWorldMapButton = newMock("Button", "MiniMapWorldMapButton")
end
-- Tooltips accumulate lines, and a test that cannot read them back can
-- only check that nothing threw.
local function tooltipMock(name)
    local t = newMock("GameTooltip", name)
    t.__lines = {}
    local realIndex = getmetatable(t).__index
    getmetatable(t).__index = function(tbl, k)
        if k == "AddLine" then
            return function(_, text) tbl.__lines[#tbl.__lines + 1] = tostring(text) end
        elseif k == "SetText" then
            return function(_, text) tbl.__lines = { tostring(text) } end
        elseif k == "SetHyperlink" then
            return function(_, link) tbl.__hyperlink = link; tbl.__lines = { "<game tooltip>" } end
        elseif k == "ClearLines" then
            return function() tbl.__lines = {} end
        elseif k == "Text" then
            return function() return table.concat(tbl.__lines, "|") end
        end
        return realIndex(tbl, k)
    end
    return t
end

GameTooltip = tooltipMock("GameTooltip")
ItemRefTooltip = tooltipMock("ItemRefTooltip")
BankFrame = newMock("Frame", "BankFrame")
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) S.CHAT[#S.CHAT + 1] = msg end }
SlashCmdList = {}
ITEM_QUALITY_COLORS = {}
for q = 0, 5 do ITEM_QUALITY_COLORS[q] = { r = 1, g = 1, b = 1, hex = "|cffffffff" } end
StaticPopupDialogs = {}
NUM_BAG_SLOTS = 4
NUM_BANKBAGSLOTS = 7
MAX_WATCHED_TOKENS = 3
WOW_PROJECT_MAINLINE, WOW_PROJECT_CLASSIC = 1, 2
RAID_CLASS_COLORS = {}
do
    local hexes = { WARRIOR = "C69B6D", PALADIN = "F48CBA", HUNTER = "AAD372", ROGUE = "FFF468", PRIEST = "FFFFFF",
                    SHAMAN = "0070DD", MAGE = "3FC7EB", WARLOCK = "8788EE", DRUID = "FF7C0A" }
    for tok, h in pairs(hexes) do
        RAID_CLASS_COLORS[tok] = { r = tonumber(h:sub(1, 2), 16) / 255, g = tonumber(h:sub(3, 4), 16) / 255, b = tonumber(h:sub(5, 6), 16) / 255 }
    end
end

function print(...) local parts = {} for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end S.CHAT[#S.CHAT + 1] = table.concat(parts, " ") end

-- ---------- shared client functions --------------------------------------
function GetLocale() return "enUS" end
function GetRealmName() return "Classic Beta PvP" end
function UnitName(unit)
    if unit == "pet" then return S.PET_NAME or "Wolfie" end
    return "Wick"
end
CLASS = "SHAMAN"
local CLASS_NAMES = { SHAMAN = { "Shaman", 7 }, WARLOCK = { "Warlock", 9 }, DRUID = { "Druid", 11 }, HUNTER = { "Hunter", 3 }, ROGUE = { "Rogue", 4 } }
function UnitClass() local c = CLASS_NAMES[CLASS] or { CLASS, 0 } return c[1], CLASS, c[2] end
function UnitRace() return "Orc", "Orc", 2 end
function UnitExists(u) return u == "player" or u == "pet" or (S.HAS_TARGET and u == "target") or (S.UNITS and S.UNITS[u]) or false end
function UnitCreatureFamily(unit)
    if unit == "target" then return S.TARGET_FAMILY end
    return S.PET_FAMILY or (CLASS == "HUNTER" and "Wolf" or "Imp")
end
-- The player's own book. Entries are { name, rank, icon, spellID }; a
-- test sets S.SPELLBOOK and both dialects read the same list.
S.SPELLBOOK = {
    { "Fireball", "Rank 7", "Interface\\Icons\\Fireball", 133 },
    { "Conjure Water", "Rank 4", "Interface\\Icons\\Water", 5504 },
    { "Conjure Food", "Rank 3", "Interface\\Icons\\Food", 587 },
    -- The forms the legacy player book used to answer with, kept
    -- so a druid reading its own book still finds them.
    { "Flight Form", "", "Interface\\Icons\\Flight", 33943 },
    { "Cat Form", "", "Interface\\Icons\\Cat", 768 },
}

function HasPetSpells()
    local list = S.PET_SPELLS
    if not list then return nil end
    return #list, "PET"
end
function GetSpellBookItemName(i, book)
    if book ~= "pet" then return nil end
    local e = S.PET_SPELLS and S.PET_SPELLS[i]
    return e and e[1] or nil
end
function IsPassiveSpell(i, book)
    if book ~= "pet" then return false end
    local e = S.PET_SPELLS and S.PET_SPELLS[i]
    return e ~= nil and e[2] == "passive"
end
-- The pet book carries an icon and a spell id as well as a name, which is
-- what lets the bestiary draw an ability instead of spelling it out.
function GetSpellBookItemTexture(i, book)
    if book ~= "pet" then return nil end
    local e = S.PET_SPELLS and S.PET_SPELLS[i]
    return e and e[3] or nil
end
function GetSpellBookItemInfo(i, book)
    if book ~= "pet" then return nil end
    local e = S.PET_SPELLS and S.PET_SPELLS[i]
    if not e then return nil end
    return "SPELL", e[4]
end
-- Unit identity. Not restricted on this client, which is what makes layer
-- fingerprinting possible at all, so the GUID comes back as a plain string.
function UnitGUID(unit)
    if unit == "player" then return "Player-4619-006648E8" end
    return S.GUIDS and S.GUIDS[unit] or nil
end

-- Chat channels.
S.CHANNELS = S.CHANNELS or {}
function GetChannelList()
    local out = {}
    for i, c in ipairs(S.CHANNELS) do
        out[#out + 1] = i
        out[#out + 1] = c
        out[#out + 1] = false
    end
    return unpack(out)
end
function GetChannelName(name)
    for i, c in ipairs(S.CHANNELS) do
        if c:lower() == tostring(name):lower() then return i, c end
    end
    return 0
end
function JoinChannelByName(name)
    S.CHANNELS[#S.CHANNELS + 1] = name
    return true
end

-- Character sheet numbers, and the conversions the sheet itself uses.
-- These take a stat value as an argument, which is what lets a paperdoll
-- ask what a piece would do without anyone reimplementing the formulas.
S.STATS = S.STATS or { 20, 35, 40, 20, 40 }   -- str, agi, sta, int, spi
function UnitStat(_, index)
    local v = S.STATS[index] or 0
    return v, v, 0, 0
end
function UnitArmor() return 0, S.ARMOR or 200, 0, 0, 0 end
function GetAttackPowerForStat(index, value)
    if index == 1 then return value * 2 end   -- strength
    if index == 2 then return value * 1 end   -- agility
    return 0
end
function GetRangedAttackPowerForStat(index, value)
    if index == 2 then return value * 2 end
    return 0
end
function GetCritChanceFromStat(index, value)
    if index == 2 then return value / 330 end
    return 0
end
function GetSpellCritChanceFromStat(index, value) return value / 600 end

-- The totals the character sheet shows, as against the conversions
-- above, which say what a change to a stat is worth. Attack power comes
-- back in three parts, the way the client gives it.
function UnitAttackPower()
    if S.AP_SECRET then return SECRET, SECRET, SECRET end
    return 120, 40, -10
end
function UnitRangedAttackPower() return 80, 0, 0 end
function GetCritChance() return 14.2 end
function GetSpellCritChance() return 5.3 end
function UnitHPPerStamina() return 10 end
STAMINA_BREAK = 20
INTELLECT_BREAK = 20
MANA_PER_INTELLECT = 15
ARMOR_PER_AGILITY = 2

-- Unit frames, enough of them to check what gets painted what colour.
function UnitIsPlayer(unit) return S.IS_PLAYER == nil or S.IS_PLAYER[unit] ~= false end
function UnitIsConnected() return true end
RAID_CLASS_COLORS = RAID_CLASS_COLORS or {}
function UnitFrameHealthBar_Update(bar, unit)
    if not bar then return end
    bar.unit = unit
    bar:SetStatusBarColor(0, 1, 0)      -- the flat green Blizzard uses
end
function UnitFrameHealthBar_OnValueChanged(bar) end
-- Both forms the client takes: a global function's name, or a table and
-- the name of a method on it. The second was missing, so every post-hook
-- on a frame's method (a row's Init, a bar's layout) quietly did nothing.
function hooksecurefunc(a, b, c)
    local tbl, name, fn = _G, a, b
    if type(a) == "table" then tbl, name, fn = a, b, c end
    local orig = tbl[name]
    if type(orig) ~= "function" then return end
    tbl[name] = function(...) local r = { orig(...) } fn(...) return unpack(r) end
end
PlayerFrame = PlayerFrame or nil

function UnitCreatureType(unit)
    if unit == "target" then return S.TARGET_TYPE or "Beast" end
    return "Beast"
end
function UnitIsDead() return false end
function HasPetUI() return true, CLASS == "HUNTER" end
-- Hunter pet reads. Modern: C_PetInfo. Legacy: the old globals.
local PET = { happiness = 2, damage = 100, rate = 1, loyalty = "Best Friend", total = 12, used = 7, diet = { "Meat", "Fish" } }
S.PET = PET
local function petHappiness() if COMBAT and SECRETS then return SECRET, SECRET, SECRET end return PET.happiness, PET.damage, PET.rate end
-- Mana by default. A druid changes it by changing form, which is what
-- makes the bar under a nameplate mean different things.
function UnitPowerType() return S.POWER_TYPE or 0 end
-- The client's own power colours, which a product should prefer over
-- its own constants.
PowerBarColor = {
    MANA   = { r = 0.00, g = 0.00, b = 1.00 },
    RAGE   = { r = 1.00, g = 0.00, b = 0.00 },
    ENERGY = { r = 1.00, g = 0.96, b = 0.41 },
}
-- Nameplates. One plate, handed out for whichever unit is asked about,
-- which is enough to check that something attaches to the right anchor.
S.NAMEPLATE = nil
C_NamePlate = {
    GetNamePlateForUnit = function(unit)
        if unit ~= "target" or not S.HAS_TARGET then return nil end
        if not S.NAMEPLATE then
            local plate = S.newMock("NamePlate")
            plate.UnitFrame = S.newMock("Frame")
            plate.UnitFrame.HealthBarsContainer = S.newMock("Frame")
            -- Lowercase, so the mock's capitalised-key rule will not
            -- invent it. The real plate has one and it is the anchor
            -- the combo pips prefer.
            plate.UnitFrame.name = S.newMock("FontString")
        S.NAMEPLATE = plate
        end
        return S.NAMEPLATE
    end,
    GetNamePlates = function() return {} end,
}

function UnitPowerMax(_, powerType)
    if powerType == 4 then return S.POWER_SECRET and SECRET or 5 end
    if powerType == 3 then return S.POWER_SECRET and SECRET or (S.ENERGY_MAX or 100) end
    return 1000
end
function GetComboPoints() return S.POWER_SECRET and SECRET or (S.COMBO or 0) end
function UnitIsUnit(a, b) return a == b or (S.HAS_TARGET and a == "nameplate1" and b == "target") end
function UnitHealthMax() return 500 end
-- Shapeshift bar: druid forms and warrior stances come through the same
-- API. S.STANCE is the one you are in (0 for none), S.STANCE_COUNT how
-- many the character has learned.
S.STANCE = S.STANCE or 0
S.STANCE_COUNT = S.STANCE_COUNT or 0
local STANCE_NAMES = { "Battle Stance", "Defensive Stance", "Berserker Stance" }
function GetShapeshiftForm() return S.STANCE end
function GetShapeshiftFormInfo(i)
    if type(i) ~= "number" or i < 1 or i > S.STANCE_COUNT then return nil end
    -- texture, name, isActive, isCastable
    return 132349 + i, STANCE_NAMES[i] or ("Form " .. i), S.STANCE == i, true
end
function GetNumShapeshiftForms() return S.STANCE_COUNT end
function IsSwimming() return false end
function IsOutdoors() return true end
function GetRealZoneText() return "Elwynn Forest" end
function IsFlyableArea() return false end
function GetBindingKey() return nil end
function SetBindingClick() return true end

-- The chat edit boxes. This client brings them up in the old alt arrow
-- mode, where the arrows steer your character instead of moving the
-- cursor, so an addon that offers to change that needs them here.
NUM_CHAT_WINDOWS = 10
for i = 1, NUM_CHAT_WINDOWS do
    local box = newMock("EditBox", "ChatFrame" .. i .. "EditBox")
    box.__altArrow = true          -- as the client hands it over
    _G["ChatFrame" .. i .. "EditBox"] = box
end


-- A merchant. S.REPAIR_COST is what the repair would come to, and
-- S.REPAIRED records the call, so a test can tell "did not repair"
-- apart from "repaired and said nothing".
S.REPAIR_COST = 0
S.REPAIRED = nil
function CanMerchantRepair() return S.CAN_REPAIR ~= false end
function GetRepairAllCost()
    -- Two returns, which is the whole point: guarding this call inline
    -- with `and` keeps only the first and silently kills the feature.
    return S.REPAIR_COST or 0, (S.REPAIR_COST or 0) > 0
end
function RepairAllItems(useGuild) S.REPAIRED = useGuild and "guild" or "self" end
function CanGuildBankRepair() return S.GUILD_REPAIR == true end
function GetGuildBankWithdrawMoney() return S.GUILD_FUNDS or 0 end
-- Guild bank. S.GB.tabs[i] = { name, icon, viewable, canDeposit, remaining,
-- items = { [slot] = { tex, count, locked, quality, link } } }. Each call a
-- player can make is recorded so a check can ask what a click did.
S.GB = { tabs = {}, current = 1, money = 0, queries = {}, picked = {}, stored = {}, split = {} }
function GetNumGuildBankTabs() return #S.GB.tabs end
function GetGuildBankTabInfo(i)
    local t = S.GB.tabs[i]
    if not t then return nil end
    return t.name, t.icon, t.viewable ~= false, t.canDeposit ~= false, -1, t.remaining or -1
end
function GetCurrentGuildBankTab() return S.GB.current end
function SetCurrentGuildBankTab(i) S.GB.current = i end
function QueryGuildBankTab(i) S.GB.queries[#S.GB.queries + 1] = i end
local function gbItem(tab, slot)
    local t = S.GB.tabs[tab]
    return t and t.items and t.items[slot]
end
function GetGuildBankItemInfo(tab, slot)
    local it = gbItem(tab, slot)
    if not it then return nil end
    return it.tex, it.count or 1, it.locked or false, false, it.quality or 1
end
function GetGuildBankItemLink(tab, slot) local it = gbItem(tab, slot) return it and it.link end
function PickupGuildBankItem(tab, slot) S.GB.picked[#S.GB.picked + 1] = tab .. ":" .. slot end
function AutoStoreGuildBankItem(tab, slot) S.GB.stored[#S.GB.stored + 1] = tab .. ":" .. slot end
function SplitGuildBankItem(tab, slot, n) S.GB.split[#S.GB.split + 1] = tab .. ":" .. slot .. "x" .. n end
function GetGuildBankMoney() return S.GB.money end
function CanWithdrawGuildBankMoney() return S.GB.canWithdraw == true end
function DepositGuildBankMoney(m) S.GB.deposited = m end
function CloseGuildBankFrame() S.GB.closed = (S.GB.closed or 0) + 1 end
function HandleModifiedItemClick() return false end
function IsModifiedClick() return false end
function StaticPopup_Hide(which) S.HIDDEN_POPUP = which end
-- Blizzard_GuildBankUI's bootstrap: the frame itself loads on demand the
-- first time the vault is opened, then shows.
function ShowGuildBankFrame()
    if not rawget(_G, "GuildBankFrame") then
        _G.GuildBankFrame = S.newMock("Frame", "GuildBankFrame")
        GuildBankFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
    end
    GuildBankFrame:Show()
end
function SaveBindings() end
function GetCurrentBindingSet() return 1 end
function GetWeaponEnchantInfo()
    if S.TEMPENCH_API and S.TEMPENCH_API.classic == false then return nil end
    -- Main hand, off hand, ranged: four values each, has/expiry/charges/id.
    local out = {}
    for _, slot in ipairs({ 16, 17, 18 }) do
        local e = S.TEMPENCH[slot]
        out[#out + 1] = e and true or false
        out[#out + 1] = e and e.remainingTimeMs or nil
        out[#out + 1] = e and e.chargesRemaining or nil
        out[#out + 1] = e and e.enchantID or nil
    end
    return out[1], out[2], out[3], out[4], out[5], out[6], out[7], out[8],
           out[9], out[10], out[11], out[12]
end
function GetItemCooldown() return 0, 0, 1 end
function PlaySound() end
SOUNDKIT = { UI_AUTOLOOT_COMPLETE = 798 }
BOOKTYPE_SPELL = "spell"
function GetSpellTexture() return 136048 end
function CreateFromMixins(...) local o = {} for i = 1, select("#", ...) do for k, v in pairs(select(i, ...)) do o[k] = v end end return o end
S.LEVEL = S.LEVEL or 30
function UnitLevel() return S.LEVEL end
function UnitFactionGroup() return "Horde", "Horde" end
function IsLoggedIn() return LOGGED end
function InCombatLockdown() return COMBAT end
function IsInGroup() return IN_GROUP end
function IsInRaid() return false end
function IsInGuild() return false end
function IsControlKeyDown() return S.CTRL == true end

-- The dressing room. S.DRESSED records what was sent to it, so a test
-- can tell it was asked rather than only that nothing threw.
function DressUpItemLink(link) S.DRESSED = link return true end
function IsShiftKeyDown() return false end
function IsAltKeyDown() return false end
function GetTime() return os.clock() end
function GetCursorPosition() return 0, 0 end
function GetCursorInfo() return nil end
function CursorHasItem() return false end
function ClearCursor() end
function GetMoney() return S.MONEY or 123456 end
-- The structured tooltip. S.TOOLTIP_LINES_FOR lets a test put words in
-- the client's mouth, which is how the set bonus reader is exercised:
-- on the real client those lines are Forever's own set data. The
-- namespace belongs to the modern API; an Era-shaped client has none
-- (and the TBC block below takes these two calls off again).
if MODERN then
C_TooltipInfo = C_TooltipInfo or {}
C_TooltipInfo.GetHyperlink = function(link)
    if not S.TOOLTIP_LINES_FOR then return nil end
    local lines = {}
    for _, t in ipairs(S.TOOLTIP_LINES_FOR) do lines[#lines + 1] = { leftText = t } end
    return { lines = lines }
end

-- What the game writes on an equipped weapon. The temporary coating is
-- a line like "Instant Poison (23 min) (60 Charges)", which is where a
-- product has to read it from on a client whose functions all go quiet.
C_TooltipInfo.GetInventoryItem = function(unit, slot)
    if S.TEMPENCH_API and S.TEMPENCH_API.tooltip == false then return nil end
    local lines = { { leftText = "Some Weapon" }, { leftText = "One-Hand" } }
    local e = S.TEMPENCH[slot]
    if e then
        lines[#lines + 1] = { leftText = ("%s (%d min) (%d Charges)"):format(
            S.TEMPENCH_NAME or "Instant Poison",
            math.floor((e.remainingTimeMs or 0) / 60000), e.chargesRemaining or 0) }
    end
    lines[#lines + 1] = { leftText = "Durability 57 / 75" }
    return { lines = lines }
end
end

function GetInventoryItemID(unit, inv)
    -- S.EQUIPPED_IDS lets a test dress the character, which is what
    -- counting set pieces needs.
    if S.EQUIPPED_IDS and S.EQUIPPED_IDS[inv] then return S.EQUIPPED_IDS[inv] end
    if inv and inv >= 20 and inv <= 23 then return 4500 end
    if CLASS == "HUNTER" and inv == 0 then return 2512 end   -- Rough Arrow
    if CLASS == "HUNTER" and inv == 18 then return 2504 end  -- Worn Shortbow
    return nil
end
function GetInventoryItemCount(unit, inv) return inv == 0 and 150 or 1 end
INVSLOT_AMMO, INVSLOT_RANGED = 0, 18
INVSLOT_MAINHAND, INVSLOT_OFFHAND = 16, 17
-- Temporary weapon enchantments. Main hand coated, off hand bare.
S.TEMPENCH = { [16] = { remainingTimeMs = 1800000, chargesRemaining = 40, enchantID = 603 } }
-- Which calls for reading a coating this client has. Three real clients
-- offer three different shapes and no addon can tell from the inside
-- which it is on, so a check has to be able to take them away.
S.TEMPENCH_API = S.TEMPENCH_API or { paperdoll = true, item = true, classic = true, tooltip = true }
function GetInventoryItemTexture(unit, inv) return inv and inv >= 20 and inv <= 23 and 133633 or nil end
function GetInventoryItemLink(_, slot) return S.EQUIPPED and S.EQUIPPED[slot] or nil end
function GetInventorySlotInfo() return 20 end
function PickupBagFromSlot() end
function PutItemInBag() end
function ToggleBag() end
function ToggleBackpack() end
function OpenBag() end
function OpenBackpack() end
function CloseAllBags() end
function PlaySound() end
function StaticPopup_Show(which) S.LAST_POPUP = which end
function GetScreenWidth() return 1600 end
function GetScreenHeight() return 900 end
function GetTotemInfo(slot)
    if SECRETS and COMBAT then return SECRET, SECRET, SECRET, SECRET, nil, SECRET, SECRET end
    if slot == 1 then return true, "Strength of Earth Totem", 100, 120, 136024, 1, 8075 end
    return false, "", 0, 0, nil, 0, 0
end
function UnitPower(unit, ptype)
    if ptype == 7 then return 0 end
    -- Energy follows the same switch the combo count does, so a check
    -- can see both a readable pool and a withheld one. Everything else
    -- on this client is secret and stays that way.
    if ptype == 3 then return S.POWER_SECRET and SECRET or (S.ENERGY or 100) end
    if MODERN then return SECRET end
    return 650
end
C_Timer = { After = function(_, fn) fn() end, NewTicker = function() return { Cancel = function() end } end }
-- Macros. Two packed lists, account then character, addressed by a
-- single slot number with the character list starting after the account
-- maximum, exactly as the client does it. GetMacroIndexByName searches
-- the account list only, because that is what this build does. Every
-- create or edit is counted so a test can tell "saved" from "noticed
-- nothing changed".
S.MACROS = S.MACROS or { acct = {}, char = {} }
S.MACRO_WRITES = 0
Constants = Constants or {}
Constants.MacroConsts = Constants.MacroConsts or { MAX_ACCOUNT_MACROS = 120, MAX_CHARACTER_MACROS = 30 }
local MACRO_BASE = Constants.MacroConsts.MAX_ACCOUNT_MACROS
local function macroAt(slot)
    if slot <= MACRO_BASE then return S.MACROS.acct, slot end
    return S.MACROS.char, slot - MACRO_BASE
end
function GetNumMacros() return #S.MACROS.acct, #S.MACROS.char end
function GetMacroInfo(slot)
    if type(slot) ~= "number" then return nil end
    local list, i = macroAt(slot)
    local m = list[i]
    if not m then return nil end
    -- After a restart the server hands every body back with a newline on
    -- the end. A test flips this on to be the restart.
    local body = m.body
    if S.MACRO_SERVER_NEWLINE and body then body = body .. string.char(10) end
    return m.name, m.icon, body, list == S.MACROS.char
end
function GetMacroIndexByName(name)
    for i, m in ipairs(S.MACROS.acct) do if m.name == name then return i end end
    return 0
end
function CreateMacro(name, icon, body, perChar)
    if COMBAT then error("Interface action failed because of an AddOn", 2) end
    local list = perChar == true and S.MACROS.char or S.MACROS.acct
    local cap = perChar == true and Constants.MacroConsts.MAX_CHARACTER_MACROS or MACRO_BASE
    if #list >= cap then return nil end
    if type(body) == "string" and #body > 255 then error("macro body too long", 2) end
    list[#list + 1] = { name = name, icon = icon, body = body }
    S.MACRO_WRITES = S.MACRO_WRITES + 1
    return perChar == true and (MACRO_BASE + #list) or #list
end
function EditMacro(slot, name, icon, body)
    if COMBAT then error("Interface action failed because of an AddOn", 2) end
    local list, i = macroAt(slot)
    local m = list[i]
    if not m then return end
    if name then m.name = name end
    if icon then m.icon = icon end
    if body then
        if #body > 255 then error("macro body too long", 2) end
        m.body = body
    end
    S.MACRO_WRITES = S.MACRO_WRITES + 1
end
function DeleteMacro(slot)
    if COMBAT then error("Interface action failed because of an AddOn", 2) end
    local list, i = macroAt(slot)
    if list[i] then table.remove(list, i) end
end

-- Escape. The game walks UISpecialFrames, hides whatever is shown, and
-- opens the game menu only when nothing was.
UISpecialFrames = UISpecialFrames or {}
function CloseSpecialWindows()
    local found = false
    for _, name in ipairs(UISpecialFrames) do
        local f = rawget(_G, name)
        if f and f.IsShown and f:IsShown() then f:Hide(); found = true end
    end
    return found
end

-- Console variables. S.CVARS survives a simulated reload, the way the
-- real ones survive a session, which is what the settings store relies on.
S.CVARS = S.CVARS or {}
C_CVar = {
    RegisterCVar = function(n, v) if S.CVARS[n] == nil then S.CVARS[n] = v or "" end end,
    GetCVar = function(n) return S.CVARS[n] end,
    SetCVar = function(n, v) S.CVARS[n] = tostring(v) end,
    AreCVarsLoaded = function() return true end,
}
function GetCVar(n) return S.CVARS[n] end
function SetCVar(n, v) S.CVARS[n] = tostring(v) end

-- Some numeric variables have a ceiling the client silently clamps to.
-- Addons that want "as far as this build allows" have to discover it by
-- setting and reading back, so the stub has to clamp the same way.
S.CVAR_CEILING = S.CVAR_CEILING or {}
local rawSetCVar = SetCVar
local function clampingSet(n, v)
    local cap = S.CVAR_CEILING[n]
    local num = tonumber(v)
    if cap and num and num > cap then v = cap end
    return rawSetCVar(n, v)
end
SetCVar = clampingSet
C_CVar.SetCVar = function(n, v) return clampingSet(n, v) end

-- Quest handing. Every call records what it was asked to do so a test
-- can tell an automatic accept from a player one.
S.QUEST = S.QUEST or {}
function AcceptQuest() S.QUEST.accepted = (S.QUEST.accepted or 0) + 1 end
function ConfirmAcceptQuest() S.QUEST.confirmed = (S.QUEST.confirmed or 0) + 1 end
function IsQuestCompletable() return S.QUEST.completable ~= false end
function CompleteQuest() S.QUEST.completeAsked = (S.QUEST.completeAsked or 0) + 1 end
function GetNumQuestChoices() return S.QUEST.choices or 0 end
function GetQuestReward(index) S.QUEST.rewarded = index or -1 end

C_GossipInfo = {
    GetAvailableQuests = function() return S.QUEST.available or {} end,
    GetActiveQuests    = function() return S.QUEST.active or {} end,
    SelectAvailableQuest = function(id) S.QUEST.pickedAvailable = id end,
    SelectActiveQuest    = function(id) S.QUEST.pickedActive = id end,
}

-- The proc glow overlay.
S.GLOW = S.GLOW or {}
function ActionButton_ShowOverlayGlow(b) S.GLOW[b] = true end
function ActionButton_HideOverlayGlow(b) S.GLOW[b] = false end
-- A handful of Blizzard addons the client really does register, so code
-- that asks "is this present?" gets a truthful answer instead of always no.
local INSTALLED = {
    ["Blizzard_GroupFinder_VanillaStyle"] = true,
}

S.LOADED = S.LOADED or {}
C_AddOns = {
    GetNumAddOns = function() return 0 end,
    GetAddOnInfo = function(name) if INSTALLED[name] then return name end return nil end,
    -- Load on demand: S.LOADED[name] marks one as having loaded.
    IsAddOnLoaded = function(name) return (S.LOADED and S.LOADED[name]) and true or false end,
    LoadAddOn = function() return false end,
    GetAddOnMetadata = function() return nil end,
    EnableAddOn = function() end,
}

-- Items: slots 1..3 of every real container hold Hearthstones; the rest are
-- empty so the Free aggregate path runs.
local function slotHasItem(bag, slot) return slot <= 3 end
local ITEM_LINK = "|cffffffff|Hitem:6948::::::::1:::::|h[Hearthstone]|h|r"

S.BAGS_SCANNED = {}
-- S.BAG_FAMILY[bag] is the family bit the client reports for a special
-- bag: 1 quiver, 2 ammo pouch, 4 soul bag. S.SLOT_ITEMS[bag][slot] stages
-- an item { id, count, link, icon } in place of the default Hearthstone.
S.BAG_FAMILY = S.BAG_FAMILY or {}
S.SLOT_ITEMS = S.SLOT_ITEMS or {}
local function staged(bag, slot)
    local b = S.SLOT_ITEMS[bag]
    return b and b[slot] or nil
end
local function stagedLink(it)
    if it.link then return it.link end
    local e = S.ITEMS and S.ITEMS[it.id]
    local name = (e and e.name) or ("item " .. it.id)
    return ("|cffffffff|Hitem:%d::::::::20:::::::::|h[%s]|h|r"):format(it.id, name)
end
-- WoW ships a bit library; plain Lua does not.
bit = bit or {
    band = function(a, b) local r, m = 0, 1 while a > 0 and b > 0 do if a % 2 == 1 and b % 2 == 1 then r = r + m end a, b, m = math.floor(a / 2), math.floor(b / 2), m * 2 end return r end,
    bor  = function(a, b) local r, m = 0, 1 while a > 0 or b > 0 do if a % 2 == 1 or b % 2 == 1 then r = r + m end a, b, m = math.floor(a / 2), math.floor(b / 2), m * 2 end return r end,
}
local function numSlots(bag)
    S.BAGS_SCANNED[bag] = (S.BAGS_SCANNED[bag] or 0) + 1
    if bag == 5 and MODERN then return 12 end   -- a reagent bag is equipped
    if bag == 0 then return MODERN and 20 or 16 end
    if bag >= 1 and bag <= 4 then return 16 end
    if MODERN then
        if bag == -1 then return 0 end                -- keyring on Forever: unknown, stub empty
        if bag >= 6 and bag <= 14 then return bag <= 7 and 28 or 0 end
        return 0
    end
    if bag == -2 then return 12 end                   -- TBC keyring
    if bag == -1 then return BANK_OPEN and 28 or 0 end
    if bag >= 5 and bag <= 11 then return (BANK_OPEN and bag <= 6) and 16 or 0 end
    return 0
end

if MODERN then
    function GetBuildInfo() return "1.60.1", "69893", "Sep 16 2026", 16001, "", "" end
    WOW_PROJECT_ID = 1
    function issecretvalue(v) return v == SECRET end
    -- Systems WickCore's capability flags read at load. Edit Mode is on
    -- every 12.x-engine client; the tracker and boss frames are Mainline
    -- FrameXML and come off again for TBC below.
    EditModeManagerFrame = newMock("Frame", "EditModeManagerFrame")
    ObjectiveTrackerFrame = newMock("Frame", "ObjectiveTrackerFrame")
    BossTargetFrameContainer = newMock("Frame", "BossTargetFrameContainer")
    -- A portrait-template window, as the client's generation is read off it.
    CharacterFrame = newMock("Frame", "CharacterFrame")
    Enum = {
        AddOnRestrictionType = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4, Chat = 5 },
        BagIndex = { Accountbanktab = -3, Characterbanktab = -2, Keyring = -1, Backpack = 0, ReagentBag = 5,
                     CharacterBankTab_1 = 6, CharacterBankTab_2 = 7, CharacterBankTab_3 = 8 },
        BankType = { Character = 0, Guild = 1, Account = 2 },
        PlayerInteractionType = { Banker = 8, GuildBanker = 10 },
        ItemConsumableSubclass = { Bandage = 7, Itemenhancement = 8, ItemenhancementTemporary = 9 },
        TooltipDataType = { Item = 0, Unit = 2 },
        SpellBookSpellBank = { Player = 0, Pet = 1 },
        PowerType = { Mana = 0, Rage = 1, Focus = 2, Energy = 3, ComboPoints = 4, SoulShards = 7 },
    }
    C_RestrictedActions = { IsAddOnRestrictionActive = function(v) return v == 0 and COMBAT end }
    C_PetInfo = {
        GetPetHappiness = petHappiness,
        GetPetLoyalty = function() return PET.loyalty end,
        GetPetTrainingPoints = function() return PET.total, PET.used end,
        GetPetFoodTypes = function() return PET.diet end,
        CanPetEatItem = function(id) return id == 6948 end,   -- the mock bags hold only Hearthstones
    }
    C_PaperDollInfo = { AmmoNeeded = function() return CLASS == "HUNTER" end, IsRangedSlotShown = function() return true end,
        GetTemporaryEnchantmentInfo = function(slot)
            if S.TEMPENCH_API and S.TEMPENCH_API.paperdoll == false then return nil end
            return S.TEMPENCH[slot]
        end }
    C_ClassColor = { GetClassColor = function(tok) local c = RAID_CLASS_COLORS[tok]; return c and { r = c.r, g = c.g, b = c.b } end }
    C_XMLUtil = {
        GetTemplateInfo = function(t)
            if ITEM_BUTTON_TEMPLATES[t] then return { type = "ItemButton", width = 37, height = 37 } end
            return { type = "Frame", width = 0, height = 0 }
        end,
    }
    C_Secrets = { HasSecretRestrictions = function() return true end, ShouldCooldownsBeSecret = function() return COMBAT end,
        ShouldUnitPowerBeSecret = function() return S.POWER_SECRET end,
        ShouldUnitPowerMaxBeSecret = function() return S.POWER_SECRET end }

    C_GameRules = { GetActiveGameMode = function() return 3 end, IsHardcoreActive = function() return false end, IsSelfFoundAllowed = function() return false end }
    C_Item = {
        GetItemInfo = function(id)
            -- The real one returns nothing until the item has arrived
            -- from the server, which is the whole reason the addon has
            -- a queue and a redraw.
            if type(id) == "number" and S.UNKNOWN and S.UNKNOWN[id] then return nil end
            if type(id) == "number" and S.UNCACHED and S.UNCACHED[id] then return nil end
            if type(id) == "number" and S.ITEMS and S.ITEMS[id] then
                local link = ("|cffffffff|Hitem:%d::::::::20:::::::::|h[item %d]|h|r"):format(id, id)
                local e = S.ITEMS[id]
                -- quality is the third return and sellPrice the eleventh;
                -- a staged item gets to decide both, so a test can be a
                -- grey worth forty copper.
                return e.name or ("item %d"):format(id), link, e.quality or 3, 1, 0,
                       e.type or "Armor", e.sub or "", e.stack or 1, e.equipLoc or "", 134414,
                       e.sellPrice or 0, e.classID or 4, e.subClassID or 2, 1, 0, nil, false, true
            end
            local name = CLASS == "MAGE" and "Conjured Spring Water" or "Hearthstone"
            -- Per id even in the catch-all. One shared link for every
            -- item let a test pass while the addon confused them.
            local link = ("|cffffffff|Hitem:%d::::::::20:::::::::|h[%s]|h|r")
                :format(tonumber(id) or 6948, name)
            return name, link, 1, 1, 0, "Consumable", "Food & Drink", 20, "", 134414, 0, 15, 0, 1, 0, nil, false, true
        end,
        GetItemInfoInstant = function(id)
            local e = S.ITEMS and S.ITEMS[id]
            if e then
                return id, e.type or "Armor", e.sub or "", e.equipLoc or "", 134414,
                       e.classID or 4, e.subClassID or 2
            end
            if CLASS == "ROGUE" then return 6948, "Consumable", "Item Enhancement", "", 134414, 0, 9 end
            return 6948, "Miscellaneous", "Junk", "", 134414, 15, 0
        end,
        GetItemCount = function(id) return id == 17030 and 0 or 1 end,
        GetItemIconByID = function() return 134414 end,
        -- Answered from the client's own files, so it works for an item
        -- that has never arrived from the server.
        GetItemNameByID = function(id)
            if S.UNKNOWN and S.UNKNOWN[id] then return nil end
            local e = S.ITEMS and S.ITEMS[id]
            if e then return e.name or ("item " .. tostring(id)) end
            return nil
        end,
        GetItemStats = function(link)
            -- Read the id out of the link the way the real one does,
            -- falling back to whatever the test mapped by hand.
            local id = tonumber(tostring(link):match("item:(%d+)"))
                or (S.LINK_TO_ID and S.LINK_TO_ID[link])
            if id and S.UNKNOWN and S.UNKNOWN[id] then return nil end
            local e = id and S.ITEMS and S.ITEMS[id]
            if e and e.stats then return e.stats end
            return { ITEM_MOD_STAMINA_SHORT = 10 }
        end,
        -- Item data is not in memory until asked for, which is the whole
        -- reason the gear panel has a loading step.
        IsItemDataCachedByID = function(id)
            -- The client raises on a missing id rather than answering false.
            if id == nil then error("bad argument #1 to '?' (Usage: local isCached = C_Item.IsItemDataCachedByID(itemInfo))", 2) end
            if S.UNCACHED and S.UNCACHED[id] then return false end
            return true
        end,
        RequestLoadItemDataByID = function(id)
            if S.UNCACHED then S.UNCACHED[id] = nil end
            S.REQUESTED = (S.REQUESTED or 0) + 1
        end,
        GetItemSpell = function() return "Hearth", 8690 end,
        GetItemQualityColor = function(q) return 1, 1, 1, "|cffffffff" end,
        GetItemCooldown = function() return 0, 0, 1 end,
        GetWeaponEnchantInfo = function(slot)
            if S.TEMPENCH_API and S.TEMPENCH_API.item == false then return nil end
            local e = S.TEMPENCH[slot]
            if not e then return { enchants = {} } end
            return { enchants = { { hasEnchant = true, timeLeft = e.remainingTimeMs, charges = e.chargesRemaining, enchantID = e.enchantID, enchantIconID = 132273 } } } end,
    }
    C_Spell = {
        GetSpellInfo = function(id) return { name = "Fireball", iconID = 135812, originalIconID = 135812, castTime = 3500, minRange = 0, maxRange = 35, spellID = 133 } end,
        -- A name per id where a check needs to tell two apart, and
        -- the old single answer for everything else.
        GetSpellName = function(id) return (S.SPELL_NAMES or {})[id] or "Fireball" end,
        GetSpellTexture = function() return 135812 end,
        -- The live client keeps isActive and isEnabled as plain
        -- booleans under combat restrictions while the times go
        -- secret, which is what lets a tracker show readiness without
        -- reading anything it is not allowed to.
        GetSpellCooldown = function(id)
            local on = S.ON_COOLDOWN and S.ON_COOLDOWN[id] or false
            return { startTime = (COMBAT and SECRETS) and SECRET or (on and 100 or 0),
                     duration = (COMBAT and SECRETS) and SECRET or (on and 30 or 0),
                     isEnabled = true, isActive = on, modRate = 1 }
        end,
    }
    C_SpellBook = { IsSpellKnown = function() return not S.ALL_UNKNOWN end }
    C_Container = {
        GetContainerNumSlots = numSlots,
        GetContainerNumFreeSlots = function(bag) return math.max(0, numSlots(bag) - 3), S.BAG_FAMILY[bag] or 0 end,
        GetContainerItemInfo = function(bag, slot)
            local it = staged(bag, slot)
            if it then
                return { iconFileID = it.icon or 132382, stackCount = it.count or 1, isLocked = false, quality = 1, hyperlink = stagedLink(it), itemID = it.id, isBound = false }
            end
            if S.SLOT_ITEMS[bag] then return nil end   -- a staged bag holds only what was staged
            if not slotHasItem(bag, slot) or slot > numSlots(bag) then return nil end
            return { iconFileID = 134414, stackCount = 1, isLocked = false, quality = 1, hyperlink = ITEM_LINK, itemID = 6948, isBound = true }
        end,
        GetContainerItemLink = function(bag, slot)
            local it = staged(bag, slot)
            if it then return stagedLink(it) end
            if S.SLOT_ITEMS[bag] then return nil end
            if slotHasItem(bag, slot) and slot <= numSlots(bag) then return ITEM_LINK end
        end,
        GetContainerItemID = function(bag, slot)
            local it = staged(bag, slot)
            if it then return it.id end
            if S.SLOT_ITEMS[bag] then return nil end
            if slotHasItem(bag, slot) and slot <= numSlots(bag) then return 6948 end
        end,
        UseContainerItem = function() end,
        PickupContainerItem = function() end,
        ContainerIDToInventoryID = function(bag) return 19 + bag end,
        GetItemCooldown = function() return 0, 0, 1 end,
        SortBags = function() S.SORTED = (S.SORTED or 0) + 1 end,
        SortBank = function() S.SORTED_BANK = (S.SORTED_BANK or 0) + 1 end,
    }
    C_Bank = {
        -- Swappable, so a test can be a character who has never been
        -- granted the free first tab.
        FetchNumPurchasedBankTabs = function() return S.BANK_TABS or 2 end,
        FetchMaxNumBankTabs = function() return 9 end,
        FetchPurchasedBankTabData = function() return { { ID = 6, name = "Consumables", icon = 133633 }, { ID = 7, name = "Gear", icon = 133634 } } end,
        FetchNextPurchasableBankTabData = function() return { tabCost = 100000 } end,
        PurchaseBankTab = function() S.PURCHASED_TAB = true end,
        CloseBankFrame = function() BANK_OPEN = false end,
    }
    C_UnitAuras = {
        GetAuraDataByIndex = function(unit, i, filter)
            if COMBAT and SECRETS then error("GetAuraDataByIndex(): Auras cannot be accessed when secret while tainted") end
            if i > 2 then return nil end
            return { name = i == 1 and "Lightning Shield" or "Water Shield", icon = 136051, applications = 3, duration = 600, expirationTime = 1000, spellId = 324 }
        end,
        GetAuraDataBySpellName = function(unit, name)
            if COMBAT and SECRETS then error("GetAuraDataBySpellName(): Auras cannot be accessed when secret while tainted") end
            return { name = name, spellId = 324 }
        end,
    }
    C_QuestLog = {
        GetNumQuestLogEntries = function() return 12, 9 end,
        GetInfo = function(i) return { title = "Quest " .. i, level = 10, isHeader = false, isComplete = false, questID = 100 + i, questLogIndex = i } end,
    }
    function GetNumGroupMembers() return IN_GROUP and 5 or 0 end
    C_CurrencyInfo = {
        GetCoinTextureString = function(c) return c .. "c" end,
        GetBackpackCurrencyInfo = function(i) if i == 1 then return { name = "Honor", quantity = 250, iconFileID = 1455894, currencyTypesID = 1792 } end end,
    }
    C_ChatInfo = {
        RegisterAddonMessagePrefix = function() return true end,
        SendAddonMessage = function(prefix, msg, chan) S.SENT[#S.SENT + 1] = { prefix, msg, chan } end,
        InChatMessagingLockdown = function() return false end,
    }
    C_TradeSkillUI = { GetBaseProfessionInfo = function() return { professionName = "Alchemy", skillLevel = 150, maxSkillLevel = 225, professionID = 171 } end }
    C_ClassTalents = { GetActiveConfigID = function() return 4242 end }
    C_Traits = {}
    TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) S.TOOLTIP_HOOK = fn end }
    S.MULTICAST = {}
    function SetMultiCastSpell(action, spellID) S.MULTICAST[action] = spellID end
    function GetMultiCastTotemSpells(slot) return 8075 end
    C_SpellBook.IsSpellKnown = function(id)
        if S.ALL_UNKNOWN then return false end
        return id ~= 33943 and id ~= 40120 and id ~= 6229
    end
    -- One line for the player's book, one for the pet's, so a caller
    -- that iterates lines sees the same spells the legacy tabs give.
    C_SpellBook.GetNumSpellBookSkillLines = function() return 2 end
    C_SpellBook.GetSpellBookSkillLineInfo = function(i)
        if i == 1 then
            return { name = "General", itemIndexOffset = 0,
                     numSpellBookItems = #(S.SPELLBOOK or {}),
                     isGuild = false, shouldHide = false }
        end
        -- A guild line is somebody else's spells; a caller asking what
        -- this character can cast should skip it.
        return { name = "Guild", itemIndexOffset = 500, numSpellBookItems = 1,
                 isGuild = true, shouldHide = false }
    end
    C_SpellBook.GetSpellBookItemName = function(i, bank)
        if bank == 1 then
            local e = S.PET_SPELLS and S.PET_SPELLS[i]
            return e and e[1] or nil
        end
        local e = S.SPELLBOOK and S.SPELLBOOK[i]
        if not e then return nil end
        return e[1], e[2]
    end
    C_SpellBook.GetSpellBookItemTexture = function(i, bank)
        if bank == 1 then
            local e = S.PET_SPELLS and S.PET_SPELLS[i]
            return e and e[3] or nil
        end
        local e = S.SPELLBOOK and S.SPELLBOOK[i]
        return e and e[3] or nil
    end
    C_SpellBook.HasPetSpells = function()
        local list = S.PET_SPELLS
        if not list then return nil end
        return #list, "PET"
    end
    C_SpellBook.GetSpellBookItemInfo = function(i, bank)
        if bank == 1 then
            local e = S.PET_SPELLS and S.PET_SPELLS[i]
            if not e then return nil end
            return { name = e[1], isPassive = e[2] == "passive", iconID = e[3], spellID = e[4] }
        end
        local e = S.SPELLBOOK and S.SPELLBOOK[i]
        if not e then return nil end
        return { name = e[1], subName = e[2], iconID = e[3], spellID = e[4],
                 itemType = "Spell", isPassive = false }
    end
    C_Spell.GetSpellInfo = function(idOrName)
        if S.UNKNOWN_SPELLS and S.UNKNOWN_SPELLS[idOrName] then return nil end
        local names = { [133] = "Fireball", [783] = "Travel Form", [768] = "Cat Form", [1066] = "Aquatic Form", [16864] = "Omen of Clarity" }
        local name = type(idOrName) == "string" and idOrName or (names[idOrName] or ("Spell " .. tostring(idOrName)))
        local id = type(idOrName) == "number" and idOrName or (name == "Searing Totem" and 3599 or 133)
        return { name = name, iconID = 135812, originalIconID = 135812, castTime = (id == 133) and 3500 or 0, minRange = 0, maxRange = 35, spellID = id }
    end
    C_Traits = {
        GenerateImportString = function() return "CkEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" end,
        GetLoadoutSerializationVersion = function() return 2 end,
        GetConfigInfo = function(id) return { ID = id, name = "Loadout A", treeIDs = { 900 } } end,
        GetTreeInfo = function(cfg, tree) return { ID = tree } end,
        GetTreeCurrencyInfo = function() return { { spent = 31, quantity = 0, maxQuantity = 51 }, { spent = 20, quantity = 0, maxQuantity = 51 }, { spent = 0, quantity = 0, maxQuantity = 51 } } end,
        GetTreeHash = function() return { 0 } end,
    }
    C_ClassTalents = { GetActiveConfigID = function() return 4242 end,
        ImportLoadout = function(cfg, entries, name, text) S.IMPORTED = { cfg, name, text } return true end }
    ClassTalentImportExportMixin = {
        ImportLoadout = function(self, text, name)
            if text == "" then self:ShowImportError("empty") return false end
            return C_ClassTalents.ImportLoadout(self:GetConfigID(), {}, name, text)
        end,
    }
    C_Item.GetItemCooldown = function() return 0, 0, 1 end
    Settings = {
        RegisterCanvasLayoutCategory = function(f, n) return { ID = "cat:" .. n, GetID = function(s) return s.ID end } end,
        RegisterCanvasLayoutSubcategory = function(root, f, n) return { ID = "sub:" .. n, GetID = function(s) return s.ID end } end,
        RegisterAddOnCategory = function() end,
        OpenToCategory = function(id) OPENED = id end,
    }
end

-- The legacy globals: the whole API of an Era-shaped client, and on TBC
-- 2.5.6 the deprecation fallbacks (Blizzard_Deprecated, alive while the
-- loadDeprecationFallbacks CVar is on) that the TBC addons still call.
if not MODERN or TBC then
    function GetBuildInfo() return "2.5.5", "51536", "Sep 12 2026", 20505 end
    WOW_PROJECT_ID, WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5, 5
    -- A legacy client has no consumable subclass enum, so a rogue's bag
    -- item is named like a poison to exercise the name fallback.
    function GetItemInfo(id)
        -- Staged items answer for themselves here too; the eighth return is the stack size.
        local e = S.ITEMS and S.ITEMS[id]
        if e then
            local link = ("|cffffffff|Hitem:%d::::::::20:::::::::|h[%s]|h|r"):format(id, e.name or ("item " .. id))
            return e.name or ("item " .. id), link, e.quality or 3, 1, 0, e.type or "Armor", e.sub or "", e.stack or 1, e.equipLoc or "", 134414, e.sellPrice or 0, e.classID or 4, e.subClassID or 2, 1, 0, nil, false
        end
        local name = CLASS == "ROGUE" and "Instant Poison" or "Hearthstone"
        return name, ITEM_LINK, 1, 1, 0, "Consumable", "Consumable", 1, "",
            "Interface\\Icons\\INV_Misc_Rune_01", 0, 15, 0, 1, 0, nil, false
    end
    function GetItemInfoInstant(id)
        -- Staged items answer for themselves on the legacy client too.
        local e = S.ITEMS and S.ITEMS[id]
        if e then return id, e.type or "Armor", e.sub or "", e.equipLoc or "", 134414, e.classID or 4, e.subClassID or 2 end
        return 6948, "Miscellaneous", "Junk", "", 134414, 15, 0
    end
    function GetItemCount(id) return id == 17030 and 0 or 1 end
    function GetItemIcon() return "Interface\\Icons\\INV_Misc_Rune_01" end
    function GetItemStats(link) return { ITEM_MOD_STAMINA_SHORT = 10 } end
    function GetItemSpell() return "Hearth", 8690 end
    function GetItemQualityColor(q) return 1, 1, 1, "|cffffffff" end
    function GetItemCooldown() return 0, 0, 1 end
    function GetPetHappiness() return PET.happiness, PET.damage, PET.rate end
    function GetPetLoyalty() return PET.loyalty end
    function GetPetTrainingPoints() return PET.total, PET.used end
    function GetPetFoodTypes() return unpack(PET.diet) end
    function GetSpellInfo(id)
        if S.UNKNOWN_SPELLS and S.UNKNOWN_SPELLS[id] then return nil end
        -- The same names the modern path gives, so a check about which
        -- spell a macro casts means the same thing on both clients.
        return (S.SPELL_NAMES or {})[id] or "Fireball",
               "Rank 1", "Interface\\Icons\\Spell_Fire_FlameBolt", 3500, 0, 35, 133
    end
    function GetSpellTexture() return "Interface\\Icons\\Spell_Fire_FlameBolt" end
    function GetSpellCooldown(id)
        local on = S.ON_COOLDOWN and S.ON_COOLDOWN[id] or false
        return (on and 100 or 0), (on and 30 or 0), 1, 1
    end
    function IsSpellKnown() return not S.ALL_UNKNOWN end
    GetContainerNumSlots = numSlots
    function GetContainerNumFreeSlots(bag) return math.max(0, numSlots(bag) - 3), S.BAG_FAMILY[bag] or 0 end
    function GetContainerItemInfo(bag, slot)
        local it = staged(bag, slot)
        if it then return it.icon or 132382, it.count or 1, false, 1, false, false, stagedLink(it), false, false, it.id, false end
        if S.SLOT_ITEMS[bag] then return nil end
        if not slotHasItem(bag, slot) or slot > numSlots(bag) then return nil end
        return "Interface\\Icons\\INV_Misc_Rune_01", 1, false, 1, false, false, ITEM_LINK, false, false, 6948, true
    end
    function GetContainerItemLink(bag, slot)
        local it = staged(bag, slot)
        if it then return stagedLink(it) end
        if S.SLOT_ITEMS[bag] then return nil end
        if slotHasItem(bag, slot) and slot <= numSlots(bag) then return ITEM_LINK end
    end
    function GetContainerItemID(bag, slot)
        local it = staged(bag, slot)
        if it then return it.id end
        if S.SLOT_ITEMS[bag] then return nil end
        if slotHasItem(bag, slot) and slot <= numSlots(bag) then return 6948 end
    end
    function UseContainerItem() end
    function PickupContainerItem() end
    function ContainerIDToInventoryID(bag) return 19 + bag end
    function GetNumBankSlots() return 2 end
    function GetBankSlotCost() return 10000 end
    function PurchaseSlot() S.PURCHASED_SLOT = true end
    function PickupBankItem() end
    function BankButtonIDToInvSlotID(slot) return 39 + slot end
    function CloseBankFrame() BANK_OPEN = false end
    function GetHonorCurrency() return 120 end
    function GetArenaCurrency() return 0 end
    function UnitAura(unit, i, filter)
        if i > 2 then return nil end
        return i == 1 and "Lightning Shield" or "Water Shield", "Interface\\Icons\\x", 3, nil, 600, 1000, "player", false, false, 324
    end
    function GetNumQuestLogEntries() return 12, 9 end
    function GetQuestLogTitle(i) return "Quest " .. i, 10, 0, false, false, false, 0, 100 + i end
    function GetNumRaidMembers() return 0 end
    function GetNumPartyMembers() return IN_GROUP and 4 or 0 end
    function GetCoinTextureString(c) return c .. "c" end
    function RegisterAddonMessagePrefix() return true end
    function SendAddonMessage(prefix, msg, chan) S.SENT[#S.SENT + 1] = { prefix, msg, chan } end
    function GetTradeSkillLine() return "Alchemy", 150, 225 end
    function GetTalentInfo() return "Convection", "x", 1, 1, 5, 5 end
    function GetNumTalentTabs() return 3 end
    function GetTalentTabInfo(i) return "Tab" .. i, "x", i == 1 and 31 or 10 end
    function GetNumSpellTabs() return 1 end
    function GetSpellTabInfo()
        return "General", "x", 0, #(S.SPELLBOOK or {})
    end
    -- The druid forms, but only for the player book: this also answers
    -- for "pet", and swallowing that argument hid the pet list entirely.
    function GetSpellBookItemName(i, book)
        if book == "pet" then
            local e = S.PET_SPELLS and S.PET_SPELLS[i]
            return e and e[1] or nil
        end
        local e = S.SPELLBOOK and S.SPELLBOOK[i]
        if not e then return nil end
        return e[1], e[2]
    end
    function GetSpellBookItemTexture(i, book)
        if book == "pet" then
            local e = S.PET_SPELLS and S.PET_SPELLS[i]
            return e and e[3] or nil
        end
        local e = S.SPELLBOOK and S.SPELLBOOK[i]
        return e and e[3] or nil
    end
    function GetSpellBookItemInfo(i, book)
        if book == "pet" then
            local e = S.PET_SPELLS and S.PET_SPELLS[i]
            if not e then return nil end
            return "SPELL", e[4]
        end
        local e = S.SPELLBOOK and S.SPELLBOOK[i]
        if not e then return nil end
        return "SPELL", e[4]
    end
    -- Druid forms, hunter pet and aspect spells: a levelled character.
    local KNOWN = { [33943]=1, [133]=1, [883]=1, [6991]=1, [13163]=1, [1066]=1, [783]=1, [768]=1 }
    function IsSpellKnown(id)
        if S.ALL_UNKNOWN then return false end
        return KNOWN[id] == true or KNOWN[id] == 1
    end
    function InterfaceOptions_AddCategory() end
    function InterfaceOptionsFrame_OpenToCategory(f) OPENED = f end
end

-- TBC Anniversary 2.5.6: what it lacks against Forever, read off Blizzard's
-- classic_anniversary UI source (2.5.6.69795, 2026-10-02). The restriction
-- state is the one entry still to be confirmed by the in-game probe; it is
-- modelled as "the API exists and nothing is restricted".
if TBC then
    function GetBuildInfo() return "2.5.6", "69795", "Sep 12 2026", 20506, "", "" end
    WOW_PROJECT_ID, WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5, 5
    function issecretvalue() return false end
    C_Secrets.HasSecretRestrictions = function() return false end
    C_Secrets.ShouldCooldownsBeSecret = function() return false end
    C_Secrets.ShouldUnitPowerBeSecret = function() return false end
    C_Secrets.ShouldUnitPowerMaxBeSecret = function() return false end
    C_RestrictedActions.IsAddOnRestrictionActive = function() return false end
    C_ClassTalents = nil
    ClassTalentImportExportMixin = nil
    local templateInfo = C_XMLUtil.GetTemplateInfo
    local ABSENT_TEMPLATES = { CustomAuraContainerTemplate = true, PingableUnitFrameTemplate = true }
    C_XMLUtil.GetTemplateInfo = function(t)
        if ABSENT_TEMPLATES[t] then return nil end
        return templateInfo(t)
    end
    InterfaceOptions_AddCategory = nil
    InterfaceOptionsFrame_OpenToCategory = nil
    ObjectiveTrackerFrame = nil
    BossTargetFrameContainer = nil
    QuestWatchFrame = newMock("Frame", "QuestWatchFrame")
    -- Tooltips carry no data table on this client: the processor exists and
    -- never runs (probed 2026-10-02), and the tooltip info API is absent.
    if C_TooltipInfo then C_TooltipInfo.GetHyperlink = nil; C_TooltipInfo.GetInventoryItem = nil end
    -- The game's windows are the old Classic kind: CharacterFrame has no
    -- NineSlice, which is what WickCore reads to tell the generation.
    CharacterFrame = newMock("Frame", "CharacterFrame")
    rawset(CharacterFrame, "__nokeys", { NineSlice = true, PortraitContainer = true, TitleContainer = true })
    -- Names a harness must not invent a stand-in for on this client. The
    -- function names are from the 2.5.6 probe's missing list.
    S.ABSENT = { C_ClassTalents = true, ClassTalentImportExportMixin = true, InterfaceOptions_AddCategory = true,
                 InterfaceOptionsFrame_OpenToCategory = true, ObjectiveTrackerFrame = true, BossTargetFrameContainer = true,
                 ClickBindingFrame = true, LegacySystemFrame = true, CollectionsJournal = true,
                 EncounterJournal = true, ProfessionsFrame = true, PlayerSpellsFrame = true, AuctionHouseFrame = true,
                 C_PingSystem = true, NameUtil = true,
                 UnitSelectionType = true, PlayerVehicleHasComboPoints = true, GetUnitChargedPowerPoints = true,
                 UnitIsMercenary = true, UnitHonorLevel = true, UnitIsQuestBoss = true, GetMouseFocus = true,
                 C_LevelLink = true, GetContainerNumSlots = true, GetContainerItemInfo = true, GetNumPartyMembers = true,
                 GetNumRaidMembers = true, GetAddOnMetadata = true, IsAddOnLoaded = true }
end

-- Load a list of files as one addon, passing (addonName, ns) like the client.
-- The list of Lua files an addon's own toc asks the game to load, in
-- order. Reading it means a harness cannot quietly fall behind a new
-- file the way a hand-kept list does.
function S.tocFiles(dir, name)
    local fh = io.open(dir .. "/" .. name .. ".toc", "r")
    if not fh then return nil end
    local files = {}
    for raw in fh:lines() do
        local line = raw:gsub("\r", "")
        line = line:gsub("^%s+", ""):gsub("%s+$", "")
        if line:match("%.lua$") and not line:match("^#") then
            files[#files + 1] = line
        end
    end
    fh:close()
    return files
end

function S.loadAddon(dir, name, files)
    files = files or S.tocFiles(dir, name)
        or error("no file list and no readable toc for " .. name, 0)
    local ns = {}
    for _, f in ipairs(files) do
        local chunk, err = loadfile(dir .. "/" .. f)
        if not chunk then error("LOAD ERROR " .. f .. ": " .. tostring(err), 0) end
        local ok, rerr = pcall(chunk, name, ns)
        if not ok then error("RUNTIME ERROR " .. f .. ": " .. tostring(rerr), 0) end
    end
    return ns
end

-- Missing-global report: only Capitalized names, which is what a WoW API
-- looks like. Lowercase misses are Lua locals the mock does not model.
function S.missingReport()
    local names = {}
    for k in pairs(S.MISSING) do
        -- Skip template child lookups (_G["WicksBagsSlot3IconBorder"]); they
        -- are expected misses, not API gaps.
        if k:match("^[A-Z]") and not k:match("^Wicks%a+Slot%d") then names[#names + 1] = k end
    end
    table.sort(names)
    return names
end

return S
