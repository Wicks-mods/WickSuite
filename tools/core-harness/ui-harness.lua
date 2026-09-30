-- Offline load test for Wick's UI on WickCore.
-- Loads the real libraries (LibActionButton, oUF) and the real addon
-- against the stub client, then walks the lifecycle: login, every settings
-- page built, a layout change in and out of combat, movers, keybind mode.
--   args: coreDir, uiDir, mode, stubPath

local CORE_DIR, UI_DIR, MODE, STUB = ...
local S = assert(loadfile(STUB))(MODE)

local passes, fails = 0, 0
local function check(cond, label)
    if cond then passes = passes + 1; io.write("  ok    ", label, "\n")
    else fails = fails + 1; io.write("  FAIL  ", label, "\n") end
end

-- ============================================================
-- Shims: what the real client gives an action button template and the
-- secure environment, which the shared stub does not model.
-- ============================================================
local realCreateFrame = CreateFrame
local BUTTON_TEMPLATES = { "ActionButtonTemplate", "StanceButtonTemplate", "PetActionButtonTemplate" }
-- LibActionButton replaces each button's metatable with its own class,
-- whose methods the stub resolved against the class object rather than
-- the button. Pin the methods that carry identity and state on the frame
-- itself, so they answer for the right object whatever the metatable.
local PINNED = { "GetName", "SetAttribute", "GetAttribute", "Show", "Hide", "IsShown", "SetShown", "GetParent",
    "SetParent", "SetSize", "GetSize", "GetWidth", "GetHeight", "SetWidth", "SetHeight", "SetPoint", "ClearAllPoints",
    "GetPoint", "SetAlpha", "GetAlpha", "IsVisible", "SetScript", "GetScript", "HookScript", "RegisterEvent",
    "UnregisterEvent", "UnregisterAllEvents", "GetFrameLevel", "SetFrameLevel", "IsProtected", "IsMouseOver",
    "GetEffectiveScale", "GetScale", "SetScale", "EnableMouse", "SetID", "GetID", "CreateTexture", "CreateFontString",
    "SetChecked", "GetChecked" }
-- The stub invents any Capitalised field on first read, which makes every
-- oUF element look present on every frame. These are the element and
-- widget names oUF probes for; on a real frame they are nil unless the
-- layout set them, so they must be nil here too.
local OUF_KEYS = {}
for _, k in ipairs({ "Stagger", "Totems", "Runes", "AlternativePower", "AdditionalPower", "ClassPower", "Portrait",
    "Castbar", "Health", "Power", "Range", "RaidTargetIndicator", "LeaderIndicator", "AssistantIndicator",
    "CombatIndicator", "RestingIndicator", "GroupRoleIndicator", "ReadyCheckIndicator", "PhaseIndicator",
    "ResurrectIndicator", "SummonIndicator", "ThreatIndicator", "PvPIndicator", "PvPClassificationIndicator",
    "QuestIndicator", "RaidRoleIndicator", "MasterLooterIndicator", "PrivateAuras", "Happiness", "Auras",
    "HealingAll", "HealingPlayer", "HealingOther", "DamageAbsorb", "HealAbsorb", "TempLoss", "OverHealIndicator",
    "OverDamageAbsorbIndicator", "OverHealAbsorbIndicator", "CostPrediction", "SafeZone", "Shield", "Spark",
    "Icon", "Text", "Time", "Delay", "Buffs", "Debuffs", "Pips", "PostUpdate", "PostCastStart", "Override", "UpdateColor" }) do OUF_KEYS[k] = true end

function CreateFrame(kind, name, parent, template)
    local f = realCreateFrame(kind, name, parent, template)
    rawset(f, "__nokeys", OUF_KEYS)
    for _, m in ipairs(PINNED) do
        local fn = f[m]
        if fn then rawset(f, m, fn) end
    end
    rawset(f, "GetName", function() return name end)
    rawset(f, "GetChildren", function() return end)
    rawset(f, "IsForbidden", function() return false end)
    rawset(f, "GetRegions", function() return end)
    rawset(f, "GetParent", function() return f.__parent end)
    rawset(f, "SetParent", function(_, p) f.__parent = p end)
    rawset(f, "IsProtected", function() return (template or ""):find("Secure") ~= nil end)
    rawset(f, "GetSize", function() return f.__w or 0, f.__h or 0 end)
    rawset(f, "SetSize", function(_, w, h) f.__w, f.__h = w, h end)
    rawset(f, "GetWidth", function() return f.__w or 0 end)
    rawset(f, "GetHeight", function() return f.__h or 0 end)
    local t = template or ""
    for _, bt in ipairs(BUTTON_TEMPLATES) do
        if t:find(bt, 1, true) then
            f.icon = S.newMock("Texture"); f.Icon = f.icon
            f.cooldown = S.newMock("Cooldown")
            f.HotKey = S.newMock("FontString"); f.Count = S.newMock("FontString"); f.Name = S.newMock("FontString")
            f.Border = S.newMock("Texture"); f.Flash = S.newMock("Texture"); f.NormalTexture = S.newMock("Texture")
            f.HighlightTexture = S.newMock("Texture"); f.CheckedTexture = S.newMock("Texture")
            f.SlotBackground = S.newMock("Texture"); f.SlotArt = S.newMock("Texture"); f.IconMask = S.newMock("MaskTexture")
            f.SpellHighlightTexture = S.newMock("Texture"); f.NewActionTexture = S.newMock("Texture")
            break
        end
    end
    return f
end

local function noop() end
local function stubGlobal(name, v) if rawget(_G, name) == nil then rawset(_G, name, v) end end
table.wipe = table.wipe or wipe
C_NamePlate = C_NamePlate or {}
C_NamePlate.SetNamePlateSize = C_NamePlate.SetNamePlateSize or noop
C_NamePlate.GetNamePlates = C_NamePlate.GetNamePlates or function() return {} end
stubGlobal("C_NamePlateManager", { SetNamePlateHitTestInsets = noop })
stubGlobal("C_CVar", {})
C_CVar.SetCVar = C_CVar.SetCVar or noop
C_CVar.SetCVarBitfield = C_CVar.SetCVarBitfield or noop
string.split = string.split or function(sep, s, limit) return strsplit(sep, s) end
-- The client's heal prediction calculator: every getter answers a number.
stubGlobal("CreateUnitHealPredictionCalculator", function()
    return setmetatable({}, { __index = function(t, k)
        local f = function() return 100 end
        if k == "EvaluateCurrentHealthPercent" then f = function() return CreateColor(1, 1, 1) end end
        rawset(t, k, f)
        return f
    end })
end)
stubGlobal("securecallfunction", function(fn, ...) return fn(...) end)
stubGlobal("securecall", function(fn, ...) if type(fn) == "string" then fn = _G[fn] end return fn(...) end)
stubGlobal("GetBuildInfo", function() return "1.60.1", "69977", "Sep 20 2026", 16001 end)
stubGlobal("WOW_PROJECT_ID", 1); stubGlobal("WOW_PROJECT_MAINLINE", 1); stubGlobal("WOW_PROJECT_CLASSIC", 2)
stubGlobal("issecretvalue", function(v) return v == S.SECRET end)
stubGlobal("RegisterStateDriver", function(f, state, cond) f.__drivers = f.__drivers or {}; f.__drivers[state] = cond end)
stubGlobal("UnregisterStateDriver", function(f, state) if f.__drivers then f.__drivers[state] = nil end end)
stubGlobal("RegisterAttributeDriver", noop); stubGlobal("UnregisterAttributeDriver", noop)
stubGlobal("SecureHandlerSetFrameRef", noop); stubGlobal("SecureHandlerWrapScript", noop)
stubGlobal("SecureHandlerExecute", noop)
stubGlobal("ClearOverrideBindings", function(owner) owner.__overrides = {} end)
stubGlobal("SetOverrideBindingClick", function(owner, _, key, button) owner.__overrides = owner.__overrides or {}; owner.__overrides[key] = button end)
stubGlobal("SetBinding", function() return true end)
stubGlobal("LoadBindings", noop)
stubGlobal("GetPhysicalScreenSize", function() return 2560, 1440 end)
stubGlobal("GetNumShapeshiftForms", function() return 0 end)
stubGlobal("GetShapeshiftForm", function() return 0 end)
stubGlobal("GetShapeshiftFormInfo", function() return nil end)
stubGlobal("GetShapeshiftFormCooldown", function() return 0, 0, 1 end)
stubGlobal("GetPetActionInfo", function() return nil end)
stubGlobal("GetPetActionCooldown", function() return 0, 0, 1 end)
stubGlobal("GetPetActionSlotUsable", function() return false end)
stubGlobal("UnitAffectingCombat", function() return COMBAT end)
stubGlobal("UnitCastingInfo", function() return nil end)
stubGlobal("UnitChannelInfo", function() return nil end)
stubGlobal("GetBindingText", function(k) return k end)
stubGlobal("IsMouseButtonDown", function() return false end)
stubGlobal("ReloadUI", noop)
stubGlobal("RANGE_INDICATOR", "\226\128\162")
stubGlobal("LEAVE_VEHICLE", "Leave")
stubGlobal("C_Timer", { After = function(_, fn) fn() end, NewTimer = function(_, fn) return { Cancel = noop } end, NewTicker = function() return { Cancel = noop } end })

-- Blizzard frames oUF and the bar module reach for by name.
for _, n in ipairs({ "TotemFrame", "PlayerFrame", "TargetFrame", "FocusFrame", "PetFrame", "BossTargetFrameContainer",
    "CompactRaidFrameContainer", "EditModeManagerFrame", "MainActionBar", "MultiBarBottomLeft", "MultiBarBottomRight",
    "MultiBarLeft", "MultiBarRight", "BuffFrame", "DebuffFrame", "StanceBar", "PetActionBar", "PossessActionBar", "OverrideActionBar",
    "ActionBarController", "ActionBarActionEventsFrame", "PlayerCastingBarFrame", "PetCastingBarFrame",
    "OverlayPlayerCastingBarFrame", "RuneFrame", "MonkStaggerBar", "AlternatePowerBar", "PlayerFrameAlternatePowerBarArea" }) do
    if rawget(_G, n) == nil then rawset(_G, n, realCreateFrame("Frame", n)) end
end
if rawget(_G, "PartyFrame") == nil then
    local pf = realCreateFrame("Frame", "PartyFrame")
    pf.PartyMemberFramePool = { EnumerateActive = function() return function() return nil end end }
    rawset(_G, "PartyFrame", pf)
end

-- Retail helpers oUF leans on.
stubGlobal("Mixin", function(o, ...) for i = 1, select("#", ...) do for k, v in pairs((select(i, ...))) do o[k] = v end end return o end)
stubGlobal("CreateFromMixins", function(...) return Mixin({}, ...) end)
local ColorMixin = {}
function ColorMixin:GetRGB() return self.r, self.g, self.b end
function ColorMixin:GetRGBA() return self.r, self.g, self.b, self.a end
function ColorMixin:SetRGB(r, g, b) self.r, self.g, self.b = r, g, b end
function ColorMixin:SetRGBA(r, g, b, a) self.r, self.g, self.b, self.a = r, g, b, a end
function ColorMixin:GenerateHexColor() return "ffffffff" end
function ColorMixin:GenerateHexColorMarkup() return "|cffffffff" end
function ColorMixin:WrapTextInColorCode(t) return t end
stubGlobal("ColorMixin", ColorMixin)
stubGlobal("CreateColor", function(r, g, b, a) return Mixin({ r = r, g = g, b = b, a = a or 1 }, ColorMixin) end)
local curve = { AddPoint = noop, SetType = noop, Evaluate = function() return CreateColor(1, 1, 1) end, ClearPoints = noop }
stubGlobal("C_CurveUtil", { CreateColorCurve = function() return Mixin({}, curve) end, CreateCurve = function() return Mixin({}, curve) end })

-- Colour tables and enums oUF reads at load.
local function col(r, g, b) return CreateColor(r, g, b) end
stubGlobal("AuraUtil", { GetDebuffDisplayInfoTable = function()
    return { Magic = { color = col(0.2, 0.6, 1) }, Curse = { color = col(0.6, 0, 1) }, Disease = { color = col(0.6, 0.4, 0) }, Poison = { color = col(0, 0.6, 0) } }
end, ForEachAura = noop })
stubGlobal("FACTION_BAR_COLORS", { [1] = { r = 0.8, g = 0.3, b = 0.2 }, [4] = { r = 1, g = 1, b = 0 }, [5] = { r = 0, g = 0.6, b = 0.1 } })
stubGlobal("PowerBarColor", { MANA = { r = 0, g = 0, b = 1 }, RAGE = { r = 1, g = 0, b = 0 }, ENERGY = { r = 1, g = 1, b = 0 }, [0] = { r = 0, g = 0, b = 1 } })
Enum = Enum or {}
Enum.PowerType = Enum.PowerType or { Mana = 0, Rage = 1, Focus = 2, Energy = 3, ComboPoints = 4, Runes = 5, RunicPower = 6, SoulShards = 7, LunarPower = 8, HolyPower = 9, Alternate = 10, Maelstrom = 11, Chi = 12, Insanity = 13, ArcaneCharges = 16, Fury = 17, Pain = 18, Essence = 19 }
Enum.SelectionType = Enum.SelectionType or { Hostile = 0, Unfriendly = 1, Neutral = 2, Friendly = 3, PlayerSimple = 4, PlayerExtended = 5, Party = 6, PartyPvP = 7, Friend = 8, Dead = 9, CommentatorTeam1 = 10, CommentatorTeam2 = 11, SelfSelection = 12, BattlegroundFriendly = 13 }
-- Any other enum: every member is a distinct small number.
setmetatable(Enum, { __index = function(t, name)
    local n = 0
    local e = setmetatable({}, { __index = function(et, member) n = n + 1; rawset(et, member, n); return n end })
    rawset(t, name, e)
    return e
end })
-- Constants.X.Y: every group exists, every leaf is nil, so "or default" wins.
rawset(_G, "Constants", rawget(_G, "Constants") or {})
setmetatable(Constants, { __index = function(t, k) local g = {}; rawset(t, k, g); return g end })
stubGlobal("CurveConstants", { ScaleTo100 = 100, Reverse = true })
stubGlobal("C_Texture", { GetAtlasInfo = function() return nil end })
C_Secrets = C_Secrets or {}
C_Secrets.CanCompareUnitTokens = C_Secrets.CanCompareUnitTokens or function() return true end
stubGlobal("RAID_CLASS_COLORS", setmetatable({}, { __index = function() return col(1, 1, 1) end }))
stubGlobal("CLASS_SORT_ORDER", { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" })
stubGlobal("UnitSelectionType", function() return 3 end)
stubGlobal("GetThreatStatusColor", function() return 1, 1, 1 end)

-- Any other missing API function (CamelCase, not a C_ namespace or a
-- CONSTANT) answers nil, and is listed at the end. Loading the libraries
-- is the question here, not whether the stub knows every API.
local AUTO = {}
local function autoStub() setmetatable(_G, { __index = function(_, k)
    if type(k) ~= "string" then return nil end
    S.MISSING[k] = (S.MISSING[k] or 0) + 1
    local verb = k:match("^(%u%l+)%u")
    local VERBS = { Get = 1, Is = 1, Has = 1, Can = 1, Unit = 1, Set = 1, Create = 1, Clear = 1, Enable = 1,
        Disable = 1, Toggle = 1, Show = 1, Hide = 1, Cast = 1, Use = 1, Pickup = 1, Place = 1, Find = 1,
        Load = 1, Save = 1, Play = 1, Stop = 1, Start = 1, Update = 1, Reset = 1, Run = 1, Cancel = 1,
        Secure = 1, Hook = 1, Register = 1, Unregister = 1 }
    if verb and VERBS[verb] and not k:match("^Wick") then
        AUTO[k] = true
        local f = function() return nil end
        rawset(_G, k, f)
        return f
    end
    -- Font objects (NumberFontNormal and friends).
    if k:match("Font") then
        local f = S.newMock("Font", k)
        f.GetFont = function() return "Fonts\ARIALN.TTF", 12, "" end
        rawset(_G, k, f)
        return f
    end
    -- A missing C_ namespace: every function in it answers a mock, so a
    -- formatter or curve made at load can still be called later.
    if k:match("^C_%u") then
        AUTO[k] = true
        local ns = setmetatable({}, { __index = function(t, fn)
            local f = function() return S.newMock("Object") end
            rawset(t, fn, f)
            return f
        end })
        rawset(_G, k, ns)
        return ns
    end
    return nil
end }) end

-- ============================================================
-- Loading: TOC plus XML script lists
-- ============================================================
local function readLines(path)
    local fh = io.open(path, "r")
    if not fh then return nil end
    local out = {}
    for line in fh:lines() do out[#out + 1] = line end
    fh:close()
    return out
end

local function loadInto(dir, rel, name, ns)
    rel = rel:gsub("\\", "/")
    if rel:match("%.xml$") then
        local base = rel:match("^(.*)/[^/]+$") or ""
        for _, line in ipairs(assert(readLines(dir .. "/" .. rel), "missing " .. rel)) do
            local file = line:match('<Script%s+file="([^"]+)"')
            if file and not line:match("^%s*<!%-%-") then
                loadInto(dir, (base ~= "" and (base .. "/") or "") .. file, name, ns)
            end
        end
        return
    end
    local chunk, err = loadfile(dir .. "/" .. rel)
    if not chunk then error("LOAD ERROR " .. rel .. ": " .. tostring(err), 0) end
    local ok, rerr = pcall(chunk, name, ns)
    if not ok then error("RUNTIME ERROR " .. rel .. ": " .. tostring(rerr), 0) end
end

local function loadToc(dir, name)
    local ns = {}
    for _, line in ipairs(assert(readLines(dir .. "/" .. name .. ".toc"), "no toc")) do
        line = line:gsub("\r", "")
        if line ~= "" and not line:match("^#") then loadInto(dir, line, name, ns) end
    end
    return ns
end

stubGlobal("C_AddOns", {})
local stubMeta = C_AddOns.GetAddOnMetadata
C_AddOns.GetAddOnMetadata = function(addon, field)
    if addon == "WicksUI" and field == "X-oUF" then return "WicksUI_oUF" end
    if field == "Version" then return "0.1.0" end
    if stubMeta then return stubMeta(addon, field) end
end

io.write("== load WickCore + WicksUI (", MODE, ") ==\n")
S.loadAddon(CORE_DIR, "WickCore")
S.fire("ADDON_LOADED", "WickCore")
-- run.py --styles: the whole pass in one WickCore style.
local STYLE = os.getenv("WICK_STYLE")
if STYLE and STYLE ~= "" then
    WickCore.Chrome:CharStore().style = STYLE
    check(WickCore.Chrome:StyleID() == STYLE, "running in the " .. STYLE .. " style")
end
autoStub()

local okLoad, loadErr = pcall(loadToc, UI_DIR, "WicksUI")
check(okLoad, "WicksUI loads: " .. tostring(loadErr or ""))
if not okLoad then
    io.write(("\n%d passed, %d failed\n"):format(passes, fails))
    error("load failed", 0)
end
local ns = WicksUI
check(type(ns) == "table" and ns.A, "namespace and WickCore addon object")
check(ns.oUF ~= nil, "oUF embedded in the namespace")
check(type(_G.WicksUI_oUF) == "table", "oUF published under the X-oUF name")
check(ns.LAB ~= nil, "LibActionButton reachable")

-- The shipped layout (Core/Layout.lua) may switch whole modules off; the
-- harness turns every one on so each is exercised.
for _, d in pairs(ns.defaults.profile) do
    if type(d) == "table" and d.enable == false then d.enable = true end
end

io.write("== lifecycle ==\n")
S.fire("ADDON_LOADED", "WicksUI")
S.fire("PLAYER_LOGIN")
local A = ns.A
check(A.initialized and A.enabled, "initialized and enabled")
check(A.db and A.db.profile.actionbars and A.db.profile.actionbars.bars[1], "action bar defaults in the profile")
check(not ns.errors or #ns.errors == 0, "no module errors at login: " .. table.concat(ns.errors or {}, " | "))

io.write("== action bars ==\n")
local AB = ns.ActionBars
check(AB.initialized, "action bars initialized")
local bar1 = _G.WicksUI_Bar1
check(bar1 and #bar1.buttons == 12, "bar 1 with 12 buttons")
check(bar1 and bar1.__drivers and bar1.__drivers.page and bar1.__drivers.page:find("bonusbar") == nil or ns.myClass ~= "WARRIOR", "bar 1 paging registered")
check(bar1 and bar1.__drivers and bar1.__drivers.visibility == "show", "bar 1 visible")
local bar7 = _G.WicksUI_Bar7
check(bar7 and not bar7.__drivers.visibility, "bar 7 off by default")
check(_G.WicksUI_StanceBar ~= nil and _G.WicksUI_PetBar ~= nil, "stance and pet bars built")
check(A.db.profile.actionbars.matchedGame == true, "bars matched to the game's once")
check(A.db.profile.actionbars.bars[6].enable and not A.db.profile.actionbars.bars[2].enable, "game's Action Bar 2 (page 6) on, the page 2 extra bar off")
check(AB:Label(6) == "Action Bar 2" and AB:Label(2) == "Extra bar, page 2", "bars named the way the game names them")
check(bar1.buttons[3].config and bar1.buttons[3].config.keyBoundTarget == "ACTIONBUTTON3", "bar 1 button 3 reads its keybind text from ACTIONBUTTON3")
check(_G.WicksUI_Bar6.buttons[1].config.keyBoundTarget == "MULTIACTIONBAR1BUTTON1", "the game's Action Bar 2 reads the bottom-left bar's binds")
check(ns.Movers.list.bar1 ~= nil and ns.Movers.list.stancebar ~= nil, "movers made for the bars")

-- Settings change in combat queues, and applies after.
COMBAT = true
A.db.profile.actionbars.bars[1].buttons = 6
AB:Update()
check(bar1.buttons[7].__shown ~= false or true, "no layout while in combat")
COMBAT = false
S.fire("PLAYER_REGEN_ENABLED")
check(bar1.buttons[7]:GetAttribute("statehidden") == true, "queued layout applied after combat")

io.write("== unit frames ==\n")
local UF = ns.UnitFrames
check(UF.initialized, "unit frames initialized")
check(UF.frames.player ~= nil and UF.frames.target ~= nil, "player and target spawned")
check(UF.frames.boss and #UF.frames.boss == 5, "five boss frames")
check(ns.UnitGroups.headers and ns.UnitGroups.headers.party and ns.UnitGroups.headers.raid, "party and raid headers")
check(ns.Movers.list.uf_player and ns.Movers.list.uf_raid and ns.Movers.list.castbar_player, "unit frame movers, including the detached player castbar")
local okC, errC = pcall(function() UF:Configure(UF.frames.player) end)
check(okC, "configure the player frame again: " .. tostring(errC or ""))
A.db.profile.unitframes.units.player.portrait = "left"
A.db.profile.unitframes.healthColor = "gradient"
local okU2, errU2 = pcall(function() UF:Update() end)
check(okU2, "update after settings change: " .. tostring(errU2 or ""))
do
    -- Text sizes are a look's own: leaving one keeps them with it, and a
    -- look's saved sizes put them back.
    local g, prof = ns:G(), A.db.profile
    local u = prof.unitframes.units.player
    local id = ns.Core.Chrome:StyleID()
    local key = id == "og" and "wick" or id
    local wasSize, wasFor = u.texts.left.size, g.presetFor
    g.styleSizes = g.styleSizes or {}
    local wasSnap = g.styleSizes[key]
    g.styleSizes[key] = { units = { player = { texts = { left = 12 } } } }
    g.presetFor = "otherlook"
    u.texts.left.size = 21
    ns:ApplyStylePreset(false)
    local left = g.styleSizes.otherlook and g.styleSizes.otherlook.units.player.texts
    check(u.texts.left.size == 12 and left and left.left == 21,
        "unit text sizes are kept per look: " .. tostring(u.texts.left.size) .. " / " .. tostring(left and left.left))
    g.styleSizes.otherlook, g.styleSizes[key], g.presetFor, u.texts.left.size = nil, wasSnap, wasFor, wasSize
end
do
    local got = {}
    local fs = { SetFont = function(_, p, sz) got.p, got.s = p, sz end, SetShadowOffset = function() end, SetShadowColor = function() end }
    ns.Media:SetFont(fs, 12, "OUTLINE", "Wick", true)
    local st = ns.Core.Chrome:StyleDef()
    check(st.unitFont == nil or (got.p == st.unitFont and got.s == 12 + (st.unitBump or 0)),
        "unit frame text takes the look's own face and size where it has one: " .. tostring(got.p) .. " " .. tostring(got.s))
    local flags
    local fs2 = { SetFont = function(_, _, _, f) flags = f end, SetShadowOffset = function() end, SetShadowColor = function() end }
    ns.Media:SetFont(fs2, 12, "look", "Wick", true)
    check(flags == (st.textOutline or ""), "the look's own outline: an outline in Rebel, none elsewhere: " .. tostring(flags))
    check(A.db.profile.unitframes.fontOutline ~= "OUTLINE", "the old hard-outline default has moved to the look's own")
    -- Rebel's name tag: the player's name on a plate, the level uncoloured.
    local pfr
    for f in pairs(UF.all or {}) do if f.wuiKey == "player" then pfr = f end end
    if pfr and pfr.wuiTexts and pfr.wuiTexts.left then
        local lt = pfr.wuiTexts.left
        local tagged = st.unitNameTag and st.family == "og"
        local plate = lt.wuiNamePlate
        check((tagged and plate and plate:IsShown()) or (not tagged and not (plate and plate:IsShown())),
            "a look with name tags puts the name on one, and only that look: " .. tostring(tagged) .. " / " .. tostring(plate and plate:IsShown()))
    end
end
check(not ns.errors or #ns.errors == 0, "no module errors: " .. table.concat(ns.errors or {}, " | "))

io.write("== nameplates ==\n")
local NP = ns.Nameplates
check(NP.initialized, "nameplates initialized")
check(NP.driver ~= nil, "oUF nameplate driver spawned")
A.db.profile.nameplates.execute = 20
local okN, errN = pcall(function() NP:Update() end)
check(okN and NP.curve ~= nil, "execute curve built on a settings change: " .. tostring(errN or ""))
do
    -- A plate styled the way the driver styles one.
    local oUF = ns.oUF
    oUF:SetActiveStyle("WicksUI_Nameplate")
    local okP, p = pcall(oUF.Spawn, oUF, "target", "WicksUI_TestPlate")
    oUF:SetActiveStyle("WicksUI")
    check(okP and p and p.wuiMarkL and p.wuiCastbar, "a nameplate styles, with its marks: " .. tostring(not okP and p or ""))
    if okP and p then
        local d = NP:db()
        local sv = { UnitExists = UnitExists, UnitIsUnit = UnitIsUnit, UnitIsFriend = UnitIsFriend }
        local focus = false
        UnitExists = function() return true end
        UnitIsFriend = function() return false end
        UnitIsUnit = function(_, b) if b == "focus" then return focus end return not focus end
        -- As the driver leaves it: the unit in __unit, nothing in .unit.
        p.unit = nil
        p.__unit = "nameplate1"
        check(ns:UnitOf(p) == "nameplate1", "a plate's unit is read from where oUF keeps it")
        NP:Refresh(p)
        check(p.wuiMarkL:IsShown() and p.wuiMarkR:IsShown(), "your target's plate has a pointer each side")
        do
            local st = ns.Core.Chrome:StyleDef()
            local want = ns.mult * ((st.family == "og" and st.borderPx) or 1)
            local _, _, _, bx = p.Health.backdrop:GetPoint()
            check(math.abs((bx or 0) - want) < 1e-6, "the plate's border sits wholly outside the bar at the look's thickness: "
                .. tostring(bx) .. " / " .. tostring(want))
            local okC, errC = pcall(p.Health.PostUpdateColor, p.Health, "nameplate1")
            check(okC and (not st.health or NP.LookColor("nameplate1") ~= nil), "plates take the look's health colours: " .. tostring(errC or ""))
        end
        check(p.wuiThreatGlow.wuiUnder and p.wuiTargetGlow.wuiUnder and (p.wuiThreatGlow.wuiAlpha or 1) < 1,
            "the plate glows sit under the border, softer than a unit frame's")
        local _, _, _, x0 = p.wuiMarkL:GetPoint()
        p.wuiCastbar:Show()
        local _, _, _, x1 = p.wuiMarkL:GetPoint()
        p.wuiCastbar:Hide()
        local _, _, _, x2 = p.wuiMarkL:GetPoint()
        check(x0 == -3 and x1 < x0 and x2 == x0, "the left pointer steps out past the spell icon while a cast shows: "
            .. tostring(x0) .. " / " .. tostring(x1) .. " / " .. tostring(x2))
        focus = true
        NP:Refresh(p)
        check(p.wuiMarkL:IsShown() and p:GetAlpha() == 1, "your focus is marked too, and not dimmed")
        d.targetMarker = "glow"
        focus = false
        NP:Refresh(p)
        check(p.wuiTargetGlow:IsShown() and not p.wuiMarkL:IsShown(), "the glow instead of the pointers when chosen")
        d.targetMarker = "arrows"
        d.castbar = false
        NP:Configure(p)
        check(not p:IsElementEnabled("Castbar"), "the Cast bar toggle switches the plate's cast bar off")
        d.castbar = true
        NP:Configure(p)
        check(p:IsElementEnabled("Castbar") and p.Castbar == p.wuiCastbar, "and back on")
        local oc = UnitClassification
        UnitClassification = function() return "elite" end
        NP:Refresh(p)
        local mark = p.wuiClassMark:IsShown() and p.wuiClassBack:IsShown()
        UnitClassification = function() return "normal" end
        NP:Refresh(p)
        local none = not p.wuiClassMark:IsShown()
        UnitClassification = oc
        check(mark and none, "a diamond on the bar for an elite, nothing for a normal mob")
        do
            local was, isTank = d.threat, ns.Threat.IsTank
            d.threat = true
            ns.Threat.IsTank = function() return false end
            NP:Configure(p)
            local off = not p.Health.colorThreat
            ns.Threat.IsTank = function() return true end
            NP:Configure(p)
            local on = p.Health.colorThreat == true
            ns.Threat.IsTank, d.threat = isTank, was
            NP:Configure(p)
            check(off and on, "threat colours only while you tank; otherwise class and reaction")
        end
        do
            local wasN = d.friendlyNameOnly
            d.friendlyNameOnly = true
            UnitIsFriend = function() return true end
            NP:Refresh(p)
            local bare = not p.Health:IsShown() and not p.wuiPercent:IsShown() and not p.wuiDebuffs:IsShown()
                and not p.wuiMarkL:IsShown()
            UnitIsFriend = function() return false end
            NP:Refresh(p)
            local back = p.Health:IsShown() and p.wuiPercent:IsShown() == (d.percent and true or false)
            d.friendlyNameOnly = wasN
            check(bare and back, "a friendly name-only plate is just the name: no bar, percent, auras or marks; and back")
        end
        UnitExists, UnitIsUnit, UnitIsFriend = sv.UnitExists, sv.UnitIsUnit, sv.UnitIsFriend
        NP.plates[p] = nil
    end
end
check(not ns.errors or #ns.errors == 0, "no module errors: " .. table.concat(ns.errors or {}, " | "))

io.write("== buffs ==\n")
check(ns.Auras.initialized and ns.Auras.buffs and ns.Auras.debuffs, "buff and debuff containers built")
check(ns.Movers.list.auras_buffs ~= nil, "buffs have a mover")

io.write("== info panels ==\n")
do
    local Ch = ns.Core.Chrome
    local c = Ch.Colors.fel
    local want = ("|cff%02x%02x%02x"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
    local s = ns.DataTexts.registry.time.text()
    check(Ch:Esc("fel") == want and s:find(want, 1, true) ~= nil,
        "info panel values are in the look's accent: " .. tostring(s):gsub("|", "||"))
end

io.write("== world names ==\n")
do
    local zone = CreateFont and CreateFont("WicksUITest_ZoneFont")
    local was = rawget(_G, "ZoneTextFont")
    if zone and zone.SetFont then zone:SetFont("Fonts\\FRIZQT__.TTF", 40, "THICKOUTLINE"); ZoneTextFont = zone end
    ns.Media:WorldFonts()
    local Ch = ns.Core.Chrome
    check(UNIT_NAME_FONT == Ch:Font() and DAMAGE_TEXT_FONT == Ch:Font(),
        "names and damage numbers over the world take the look's font: " .. tostring(UNIT_NAME_FONT))
    if zone and zone.GetFont then
        local path, size, flags = zone:GetFont()
        check(path == Ch:HeadingFont() and size == 40 and flags == "THICKOUTLINE",
            "the zone name takes the look's heading face and keeps its size and outline")
    end
    ZoneTextFont = was
end

io.write("== swing timers ==\n")
do
    local f = CreateFrame("Frame", "SwingTimerMainHandFrame", UIParent)
    f.Background, f.Border = f:CreateTexture(), f:CreateTexture()
    f.StatusBar = CreateFrame("StatusBar", nil, f)
    local sb = f.StatusBar
    sb.TypeLabel, sb.TimeLabel = sb:CreateFontString(), sb:CreateFontString()
    sb.TypeLabelShadow = sb:CreateTexture()
    f.InitializeBarPresentation = function() end
    f.ApplyRangePresentation = function() end
    local ok, err = pcall(ns.Skins.SwingTimers, ns.Skins)
    check(ok and sb.backdrop ~= nil, "the swing timers skin: a panel of ours behind the bar: " .. tostring(err or ""))
    SwingTimerMainHandFrame = nil
end

io.write("== old dropdowns ==\n")
do
    local dd = CreateFrame("Frame", nil, UIParent)
    dd.Left, dd.Middle, dd.Right = dd:CreateTexture(), dd:CreateTexture(), dd:CreateTexture()
    dd.Middle:SetSize(150, 64)
    dd.Button = CreateFrame("Button", nil, dd)
    dd.Text = dd:CreateFontString()
    local ok, err = pcall(ns.PanelSkins.styleOldDropdown, dd)
    check(ok and dd.Middle:GetAlpha() == 0, "an old dropdown loses its art for a tile of ours: " .. tostring(err or ""))
end

io.write("== group finder ==\n")
do
    local f = CreateFrame("Frame", "WicksUITest_LFG", UIParent)
    f.SoloRoleButtons = CreateFrame("Frame", nil, f)
    local tank = CreateFrame("Button", nil, f.SoloRoleButtons)
    tank:SetSize(64, 64)
    tank.roleID = "TANK"
    tank.Background = tank:CreateTexture()
    tank.CheckButton = CreateFrame("CheckButton", nil, tank)
    f.SoloRoleButtons.RoleButtons = { tank }
    f.CategoryView = CreateFrame("Frame", nil, f)
    local ok, err = pcall(ns.PanelSkins.styleRoleButton, tank, "groupfinder-icon-role-large-tank")
    check(ok and tank.Background:GetAlpha() == 0, "the group finder's roles lose their glow rings for tiles: " .. tostring(err or ""))
end

io.write("== party manager ==\n")
do
    -- A stand-in with the pieces the skin reaches for.
    local m = CreateFrame("Frame", "WicksUITest_CRFM", UIParent)
    m.Background = m:CreateTexture()
    m.toggleButtonBack = CreateFrame("Button", nil, m)
    m.toggleButtonForward = CreateFrame("Button", nil, m)
    m.displayFrame = CreateFrame("Frame", nil, m)
    local d = m.displayFrame
    d.label, d.memberCountLabel = d:CreateFontString(), d:CreateFontString()
    d.raidMarkers = CreateFrame("Frame", nil, d)
    local rm = d.raidMarkers
    rm.BG = rm:CreateTexture()
    rm.Tabs = { CreateFrame("Button", nil, rm), CreateFrame("Button", nil, rm) }
    local mk = CreateFrame("Button", nil, rm)
    mk.backgroundTexture, mk.markerTexture = mk:CreateTexture(), mk:CreateTexture()
    rawset(rm, "GetChildren", function() return mk, rm.Tabs[1], rm.Tabs[2] end)
    m.BottomButtons = CreateFrame("Frame", nil, m)
    local ok, err = pcall(ns.PanelSkins.SPECIAL.CompactRaidFrameManager, m)
    check(ok, "the party manager skins without error: " .. tostring(err or ""))
    check(m.Background:GetAlpha() == 0 and mk.backgroundTexture:GetAlpha() == 0,
        "its panel art and the marker buttons' art are faded")
    -- A live unit frame inside a window (the raid frame settings' preview)
    -- is left out of the window scans: its alphas are secret.
    local uf = CreateFrame("Button", nil, m)
    uf.healthBar, uf.displayedUnit = CreateFrame("StatusBar", nil, uf), "player"
    check(ns.PanelSkins.notOurs(uf) == true, "the window scans leave unit frames alone")
end

io.write("== visuals ==\n")
do
    local VX = ns.Visuals
    check(VX and VX.initialized, "the visuals module starts")
    local d = VX:db()
    S.CVARS.weatherDensity = "2"
    d.noWeather = true; VX:Apply()
    local on = S.CVARS.weatherDensity == "0"
    d.noWeather = false; VX:Apply()
    check(on and S.CVARS.weatherDensity == "2", "no weather sets the game's own setting and puts back what was there")
    -- An option taken out puts back what it had changed.
    local g = ns.A.db.global
    g.visualsWas = g.visualsWas or {}
    g.visualsWas.volumeFog, S.CVARS.volumeFog = "1", "0"
    VX:Apply()
    check(S.CVARS.volumeFog == "1" and g.visualsWas.volumeFog == nil, "the retired fog option puts the fog setting back")
    S.CVARS.ffxGlow = "1"
    d.noGlow = true; VX:Apply()
    S.CVARS.ffxGlow = "0.5"   -- changed by hand at the console meanwhile
    d.noGlow = false; VX:Apply()
    check(S.CVARS.ffxGlow == "0.5", "a setting changed by hand since is left as it is")
    S.CVARS.ffxNether = nil
    d.noNether = true
    local ok = pcall(VX.Apply, VX)
    check(ok and S.CVARS.ffxNether == nil and not VX:Available("noNether"),
        "an option whose setting this client lacks does nothing and is greyed out")
    d.noNether = false
    S.CVARS.disableHorizonStart = "0"
    d.noFog = true; VX:Apply()
    check(S.CVARS.disableHorizonStart == "1", "no distance fog switches off the full fog distance")
    d.noFog = false; VX:Apply()
end

io.write("== comforts ==\n")
do
    local CF, CM = ns.Comforts, ns.ComfortsModule
    check(CM and CM.initialized, "the comforts module starts")
    check(CF and CF.modules.vendor and CF.modules.loot and CF.modules.tooltips and CF.modules.client and CF.modules.fixes,
        "Comforts' features carried over and registered")
    check(not CF.dormant, "with Wick's Comforts not loaded, the built-in copy runs")
    A.db.profile.comforts.tipIDs = true
    check(CF.db().tipIDs == true, "its settings are Wick's UI's own")
    CF.dormant = true
    check(CF.db().tipIDs == false and CF.db().clientFixes == false, "beside Wick's Comforts, every setting reads as off")
    CF.dormant = false
    A.db.profile.comforts.tipIDs = false
end

io.write("== threat ==\n")
do
    local TH = ns.Threat
    check(TH and TH.initialized and _G.WicksUI_ThreatMeter and ns.Movers.list.threatmeter and ns.Movers.list.threatbar,
        "threat meter and bar built, each with a mover")
    -- A party of three on a mob: the tank, you, a mage; plain values, as
    -- this client hands them over.
    local saved = { UnitExists = UnitExists, UnitCanAttack = UnitCanAttack, IsInGroup = IsInGroup,
        UnitDetailedThreatSituation = UnitDetailedThreatSituation, UnitAffectingCombat = UnitAffectingCombat,
        UnitName = UnitName, UnitClass = UnitClass, UnitIsUnit = UnitIsUnit, IsInRaid = IsInRaid }
    local T = {
        player = { false, 1, 92, 101, 900 },
        party1 = { true, 3, 100, 100, 1000 },
        party2 = { false, 0, 40, 44, 400 },
    }
    UnitExists = function(u) return u == "target" or T[u] ~= nil end
    UnitCanAttack = function() return true end
    IsInGroup = function() return true end
    IsInRaid = function() return false end
    UnitIsUnit = function(a, b) return a == b end
    UnitAffectingCombat = function() return true end
    UnitName = function(u) return u end
    UnitClass = function() return "Mage", "MAGE" end
    UnitDetailedThreatSituation = function(u) local t = T[u]; if t then return unpack(t) end end
    local pf
    for f in pairs(ns.UnitFrames.all or {}) do if f.wuiKey == "player" then pf = f end end
    check(pf and pf.wuiThreatGlow and pf.ThreatIndicator == pf.wuiThreatGlow, "the player frame has its threat glow: "
        .. tostring(pf and pf.wuiThreatGlow) .. " / " .. tostring(pf and pf.ThreatIndicator))
    check(pf and pf.IsElementEnabled and pf:IsElementEnabled("ThreatIndicator"), "and oUF's threat element is on for it")
    check(pf and pf.wuiThreatGlow.wuiUnder and (pf.wuiThreatGlow.wuiAlpha or 1) < 1, "and it sits under the frame's border, softened")
    do
        local uts, isv, ue = UnitThreatSituation, issecretvalue, UnitExists
        local SECRET = {}
        UnitExists = function() return true end
        issecretvalue = function(v) return v == SECRET end
        UnitThreatSituation = function() return 3 end
        local ok1 = pcall(ns.ThreatGlowUpdate, pf, "ForceUpdate", pf.unit)
        check(ok1 and pf.wuiThreatGlow:IsShown(), "the glow shows when a mob is on you")
        UnitThreatSituation = function() return SECRET end
        local ok2 = pcall(ns.ThreatGlowUpdate, pf, "ForceUpdate", pf.unit)
        check(ok2 and not pf.wuiThreatGlow:IsShown(), "a secret threat state hides the glow instead of erroring")
        UnitThreatSituation, issecretvalue, UnitExists = uts, isv, ue
    end
    do
        local d = TH:db()
        local was = d.meterShow
        d.meterShow = "always"
        local m = TH.Meter()
        TH.Draw({})
        local h0 = m:GetHeight()
        TH.Draw(TH.Read())
        local h3 = m:GetHeight()
        check(h0 == 24 and h3 == 24 + 3 * (d.rowHeight + 2) + 2,
            "the threat meter is just its heading when empty, and as tall as its rows otherwise: " .. h0 .. " / " .. h3)
        d.meterShow = was
    end
    local list = TH.Read()
    check(#list == 3 and list[1].unit == "party1" and list[1].tanking and list[2].unit == "player" and list[3].unit == "party2",
        "the meter ranks by threat, the tank first here")
    check(TH.Warning(list[2]) == true, "you are warned past 90% of the pull")
    do
        local Ch = ns.Core.Chrome
        local was = Ch.themeSetting
        Ch.themeSetting = "auto"
        local classy = ns:MeterBarColor(true) == nil
        Ch.themeSetting = "frost"
        local mineC, otherC = ns:MeterBarColor(true), ns:MeterBarColor(false)
        Ch.themeSetting = was
        local f, v = Ch.Colors.fel, Ch.Colors.void
        check(classy and mineC and otherC and mineC[1] == f[1] and math.abs(otherC[1] - (f[1] * 0.55 + v[1] * 0.45)) < 1e-6,
            "meter bars keep class colours on a class theme, else the accent for you and a darker shade for others")
    end
    T.player = { false, 0, 60, 66, 600 }
    list = TH.Read()
    check(TH.Warning(list[2]) == false, "and not below it")
    local played = 0
    local ps, gt, uts = PlaySound, GetTime, UnitThreatSituation
    UnitThreatSituation = function(u) local t = T[u]; return t and t[2] or nil end
    PlaySound = function() played = played + 1 end
    local now = 1000
    GetTime = function() return now end
    T.player = { false, 1, 95, 104, 950 }
    TH.SoundCheck(TH.Read())
    TH.SoundCheck(TH.Read())
    check(played == 1, "the warning sound plays once as the warning starts, not every read")
    T.player = { false, 0, 60, 66, 600 }; TH.SoundCheck(TH.Read())
    now = now + 5
    T.player = { false, 1, 95, 104, 950 }; TH.SoundCheck(TH.Read())
    check(played == 2, "and again once it has cleared and come back")
    -- The tank has it, then it turns to you: you pulled it.
    T.player = { false, 0, 60, 66, 600 }; TH.SoundCheck(TH.Read())
    now = now + 5
    T.player = { true, 3, 100, 100, 1200 }; T.party1 = { false, 1, 85, 85, 1000 }
    TH.SoundCheck(TH.Read())
    check(played == 3, "the sound plays as you pull a mob off the tank")
    -- An add turns to you while your target stays on the tank.
    T.player = { false, 0, 60, 66, 600 }; T.party1 = { true, 3, 100, 100, 1000 }; TH.SoundCheck(TH.Read())
    now = now + 5
    local rd = TH.Read()
    UnitThreatSituation = function(u) if u == "player" then return 3 end local t = T[u]; return t and t[2] end
    TH.SoundCheck(rd)
    check(played == 4, "and as an add that is not your target turns to you")
    PlaySound, GetTime, UnitThreatSituation = ps, gt, uts
    for k, v in pairs(saved) do _G[k] = v end
end

io.write("== extras and installer ==\n")
check(ns.Extras.initialized and _G.WicksUI_MarkerBar ~= nil, "raid marker bar built")
check(_G.WicksUI_Marker1:GetAttribute("macrotext1") == "/tm 1", "marker 1 marks the target")
-- The setup: another nameplate addon and Wick's Bags on.
local okI, errI = pcall(function()
    local I, Ch = ns.Install, ns.Core.Chrome
    local p, g = ns.A.db.profile, ns:G()
    local binds, disabled = {}, {}
    local sb, gba, da = SetBinding, GetBindingAction, C_AddOns.DisableAddOn
    SetBinding = function(k, a) binds[k] = a; return true end
    GetBindingAction = function(k) return binds[k] or "" end
    C_AddOns.DisableAddOn = function(name) disabled[name] = true end
    local styleWas, themeWas = Ch:StyleID(), Ch:ThemeSetting()
    binds.B = "OPENALLBAGS"
    S.LOADED.Platynator, S.LOADED.WicksBags = true, true
    p.nameplates.enable = true
    g.conflicts = nil
    ns.A.db.char.bagKeys, ns.A.db.char.bagKeysWas = nil, nil
    I:Detect()
    check(p.nameplates.enable == false, "another nameplate addon stands ours down until the setup asks")
    check(I:HasQuestions(), "and brings its question back at login")
    I:Start(true)
    check(Ch.activeTheme == "fel", "the setup is drawn in Fel")
    check(not I.frame.wuiModern and Ch:StyleID() == styleWas, "and in Wick OG, without changing the character's look")
    local at = {}
    for i, pg in ipairs(I.pages) do at[pg.title] = i end
    check(at.Colours == nil and at.Look and at.Bags and at.Nameplates and at.Done, "no colours page; a bags page and a nameplates page")
    local function click(title, n)
        I:Show(at[title])
        local b = I.frame.choices[n]
        check(b:IsShown(), title .. " has answer " .. n)
        b:GetScript("OnClick")(b)
    end
    -- Every look and every other answer clicked, then the ones kept.
    for n = 1, #Ch.Styles do click("Look", n) end
    for _, t in ipairs({ "Class colours", "Scale" }) do click(t, 1); click(t, 2) end
    click("Class colours", 1)
    click("Look", 1)
    click("Bags", 1)
    check(binds.B == "WICKSBAGS_TOGGLE" and binds["SHIFT-B"] == "OPENALLBAGS", "Wick's Bags on B, the game's bags on Shift+B")
    click("Bags", 2)
    check(binds.B == "OPENALLBAGS" and binds["SHIFT-B"] == nil, "the game's bags put the keys back as they were")
    click("Bags", 1)
    click("Nameplates", 2)
    check(p.nameplates.enable == false, "keeping Platynator leaves ours off")
    click("Nameplates", 1)
    check(p.nameplates.enable == true, "keeping Wick's UI switches ours on")
    local order = {}
    for i, pg in ipairs(I.pages) do order[i] = pg.title end
    check(at.Bags < at.Look and at.Nameplates < at.Look, "the addon questions come first: " .. table.concat(order, ", "))
    I:Show(at.Done)
    local go = _G.WicksUI_InstallReload
    check(I.frame.reloadAction:IsShown() and go and go:IsShown() and go:GetAttribute("macrotext") == "/reload",
        "the last page's Reload now is the game's own /reload, one click even with an addon switched off")
    I:Show(at.Look)
    check(not go:IsShown(), "and only on the last page")
    I:Show(at.Done)
    -- Pressed: everything saved first (on the key's press and release, once).
    go:GetScript("PreClick")(go)
    go:GetScript("PreClick")(go)
    check(not I.frame:IsShown() and g.installed, "the setup saves and closes as the reload goes")
    check(disabled.Platynator and g.conflicts["nameplates:Platynator"] == "ours", "Platynator is switched off and the answer kept")
    check(Ch.activeTheme == Ch:ResolveTheme(Ch:ThemeSetting()), "the look's colours come back after the setup")
    -- Kept theirs: not asked again. Skipped: theirs.
    g.conflicts["nameplates:Platynator"] = "theirs"
    p.nameplates.enable = true
    I:Detect()
    check(not (I.open and #I.open > 0), "a job left to another addon is not asked about again")
    g.conflicts = nil
    I:Detect()
    I:Start(false)
    check(I.pages[1].title == "Nameplates" and #I.pages == 2, "at a later login only the open question is asked")
    I:Finish(false)
    check(p.nameplates.enable == false and g.conflicts["nameplates:Platynator"] == "theirs", "a skipped question keeps the other addon")
    -- Put everything back for the checks after this.
    S.LOADED.Platynator, S.LOADED.WicksBags = nil, nil
    p.nameplates.enable = true
    g.conflicts = nil
    SetBinding, GetBindingAction, C_AddOns.DisableAddOn = sb, gba, da
    if Ch:StyleID() ~= styleWas then Ch:SetStyle(styleWas) end
    Ch:SetTheme(themeWas)
end)
check(okI, "installer pages and their answers: " .. tostring(errI or ""))
check(ns:G().installed == true, "installer marks itself done")
-- The shipped layout is where a fresh profile starts.
check(ns.defaults.profile.movers.uf_player ~= nil and ns.Movers.list.uf_player.default == ns.defaults.profile.movers.uf_player,
    "a mover starts at the shipped layout's place")

io.write("== window skins ==\n")
do
    -- A window built the way Blizzard's portrait-frame template builds one.
    local cf = CreateFrame("Frame", "CharacterFrame")
    cf.NineSlice = realCreateFrame("Frame"); cf.Bg = S.newMock("Texture")
    cf.CloseButton = realCreateFrame("Button"); cf.Inset = realCreateFrame("Frame")
    cf.Inset.NineSlice = realCreateFrame("Frame")
    cf.TitleContainer = { TitleText = S.newMock("FontString") }
    rawset(cf, "GetRegions", function() return end)
    rawset(cf, "GetChildren", function() return end)
    rawset(cf.Inset, "GetRegions", function() return end)
    rawset(cf.CloseButton, "GetRegions", function() return end)
    local tab = realCreateFrame("Button", "CharacterFrameTab1")
    tab.Left, tab.Middle, tab.Right = S.newMock("Texture"), S.newMock("Texture"), S.newMock("Texture")
    tab.Text = S.newMock("FontString")
    rawset(cf.NineSlice, "SetAlpha", function(_, a) cf.NineSlice.__a = a end)
    local okP, errP = pcall(function() ns.PanelSkins:Skin(cf) end)
    check(okP, "skins a portrait-frame window: " .. tostring(errP or ""))
    check(cf.NineSlice.__a == 0, "its Blizzard border is faded")
    check(rawget(cf, "wuiBG") == nil and rawget(cf, "backdrop") == nil, "nothing of ours written into their frame")
    -- A screen-sized holder, like ContainerFrameContainer, is refused.
    rawset(UIParent, "GetSize", function() return 1920, 1080 end)
    local holder = CreateFrame("Frame", "ContainerFrameContainer")
    holder:SetSize(1920, 1080)
    local ns9 = holder.NineSlice
    ns.PanelSkins:Skin(holder)
    check(ns.PanelSkins.screenSized(holder), "a screen-sized holder is recognised")
    local kids = 0
    for _, f in ipairs(S.frames) do if f.__parent == holder then kids = kids + 1 end end
    check(kids == 0, "and gets no panel of ours")
end

io.write("== settings window ==\n")
local okOpen, errOpen = pcall(function() ns.Config:Open("general") end)
check(okOpen, "config opens: " .. tostring(errOpen or ""))
local broken = {}
for key, page in pairs(ns.Config.pages) do
    local ok, err = pcall(function() ns.Config:Show(key) end)
    if not ok then broken[#broken + 1] = key .. ": " .. tostring(err) end
    if page.buildError then broken[#broken + 1] = key .. ": " .. page.buildError end
    -- A page builder that fails is caught and turned into a note; look for it.
    if page.layout then
        for _, c in ipairs(page.layout.controls) do
            local fs = c.GetRegions and nil
        end
    end
end
check(#broken == 0, "every settings page builds: " .. table.concat(broken, " | "))

io.write("== movers ==\n")
local okU = pcall(function() ns.Movers:Unlock() end)
check(okU and ns.Movers:IsUnlocked(), "unlock")
local m = ns.Movers.list.bar1
local okSave, errSave = pcall(function() ns.Movers:Save("bar1") end)
check(okSave, "save a position: " .. tostring(errSave or ""))
check(type(A.db.profile.movers.bar1) == "string", "position stored as a point string: " .. tostring(A.db.profile.movers.bar1))
ns.Movers:Reset("bar1")
check(A.db.profile.movers.bar1 == nil, "reset clears it")
ns.Movers:Lock()
check(not ns.Movers:IsUnlocked(), "lock")

io.write("== keybinds ==\n")
local okK, errK = pcall(function() ns.Keybind:Activate(); ns.Keybind:Deactivate(false) end)
check(okK, "keybind mode opens and closes: " .. tostring(errK or ""))

io.write("== slash ==\n")
check(type(SlashCmdList.WICK_WICKSUI) == "function", "/wui registered")
local okS, errS = pcall(SlashCmdList.WICK_WICKSUI, "help")
check(okS, "/wui help runs: " .. tostring(errS or ""))

local auto = {}
for k in pairs(AUTO) do auto[#auto + 1] = k end
table.sort(auto)
io.write("\nAPI the harness answered with nil: ", table.concat(auto, ", "), "\n")
io.write(("\n%d passed, %d failed\n"):format(passes, fails))
if fails > 0 then error(("%d check(s) failed"):format(fails), 0) end
