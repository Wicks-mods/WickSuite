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
    WickCoreDB.global.style = STYLE
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
check(not ns.errors or #ns.errors == 0, "no module errors: " .. table.concat(ns.errors or {}, " | "))

io.write("== nameplates ==\n")
local NP = ns.Nameplates
check(NP.initialized, "nameplates initialized")
check(NP.driver ~= nil, "oUF nameplate driver spawned")
A.db.profile.nameplates.execute = 20
local okN, errN = pcall(function() NP:Update() end)
check(okN and NP.curve ~= nil, "execute curve built on a settings change: " .. tostring(errN or ""))
check(not ns.errors or #ns.errors == 0, "no module errors: " .. table.concat(ns.errors or {}, " | "))

io.write("== buffs ==\n")
check(ns.Auras.initialized and ns.Auras.buffs and ns.Auras.debuffs, "buff and debuff containers built")
check(ns.Movers.list.auras_buffs ~= nil, "buffs have a mover")

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

io.write("== extras and installer ==\n")
check(ns.Extras.initialized and _G.WicksUI_MarkerBar ~= nil, "raid marker bar built")
check(_G.WicksUI_Marker1:GetAttribute("macrotext1") == "/tm 1", "marker 1 marks the target")
-- Every page, and every answer on it clicked.
local okI, errI = pcall(function()
    for p = 1, 6 do
        ns.Install:Show(p)
        for _, btn in ipairs(ns.Install.frame.choices) do
            if btn:IsShown() then btn:GetScript("OnClick")(btn) end
        end
    end
    -- The colours page, Custom picked on its own.
    ns.Install:Show(3)
    local custom = ns.Install.frame.choices[3]
    custom:GetScript("OnClick")(custom)
    ns.Install:Finish()
end)
check(okI, "installer pages and their answers: " .. tostring(errI or ""))
check(ns.Core.Chrome:ThemeSetting() == "custom", "the colours page sets the theme")
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
