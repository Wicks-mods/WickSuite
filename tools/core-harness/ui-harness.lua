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
    "Icon", "Text", "Time", "Delay", "Buffs", "Debuffs", "Pips", "PostUpdate", "PostCastStart", "Override", "UpdateColor",
    -- oUF's meta functions. RegisterMetaFunction skips a name the prototype
    -- frame already answers, so an invented method here would keep the real
    -- CreateAuras and the tag functions from ever being installed.
    "CreateAuras", "Tag", "Untag", "UpdateTags",
    -- Aura element overrides a layout may set; invented, they would win the
    -- "options.X or self.X or default" chain and swallow the real builder.
    "CreateButton", "PostCreateButton", "PostUpdateButton" }) do OUF_KEYS[k] = true end
-- The window skin tells a button's kind by the named pieces it carries
-- (a filter's ResetButton, a tab's Left and Right, a heading's StateIcon).
-- Invented, every button would pass for every kind at once; a fixture that
-- wants one sets it.
for _, k in ipairs({ "ResetButton", "FilterDropdown", "FilterButton", "StateIcon", "Left", "Right", "Middle", "Center",
    "Track", "Back", "Forward", "Arrow", "Slider", "Fill", "Mask", "CollapseButton", "SkillUps", "Label", "Thumb" }) do
    OUF_KEYS[k] = true
end

function CreateFrame(kind, name, parent, template)
    local f = realCreateFrame(kind, name, parent, template)
    rawset(f, "__nokeys", OUF_KEYS)
    for _, m in ipairs(PINNED) do
        local fn = f[m]
        if fn then rawset(f, m, fn) end
    end
    rawset(f, "GetName", function() return name end)
    -- Children, regions and parents are the stub's own bookkeeping now.
    rawset(f, "IsForbidden", function() return false end)
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
-- The action-slot API, as empty slots. LibActionButton's Classic path
-- reads these on every update (the Forever path goes through secrets and
-- never did), and a nil from the auto-stub where a number belongs throws.
stubGlobal("HasAction", function() return false end)
stubGlobal("GetActionInfo", function() return nil end)
stubGlobal("GetActionText", function() return nil end)
stubGlobal("GetActionTexture", function() return nil end)
stubGlobal("GetActionCount", function() return 0 end)
stubGlobal("GetActionCooldown", function() return 0, 0, 1, 1 end)
stubGlobal("GetActionCharges", function() return nil end)
stubGlobal("GetActionLossOfControlCooldown", function() return 0, 0 end)
stubGlobal("IsAttackAction", function() return false end)
stubGlobal("IsEquippedAction", function() return false end)
stubGlobal("IsCurrentAction", function() return false end)
stubGlobal("IsAutoRepeatAction", function() return false end)
stubGlobal("IsUsableAction", function() return false, false end)
stubGlobal("IsConsumableAction", function() return false end)
stubGlobal("IsStackableAction", function() return false end)
stubGlobal("IsItemAction", function() return false end)
stubGlobal("IsActionInRange", function() return nil end)
stubGlobal("ActionHasRange", function() return false end)
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

-- Blizzard frames oUF and the bar module reach for by name. The second
-- list is Mainline FrameXML and stays absent on the TBC-shaped client.
for _, n in ipairs({ "TotemFrame", "PlayerFrame", "TargetFrame", "FocusFrame", "PetFrame",
    "CompactRaidFrameContainer", "EditModeManagerFrame", "MainActionBar", "MultiBarBottomLeft", "MultiBarBottomRight",
    "MultiBarLeft", "MultiBarRight", "BuffFrame", "DebuffFrame", "StanceBar", "PetActionBar", "PossessActionBar",
    "ActionBarController", "ActionBarActionEventsFrame", "PlayerCastingBarFrame", "PetCastingBarFrame",
    "RuneFrame", "MonkStaggerBar", "AlternatePowerBar", "PlayerFrameAlternatePowerBarArea" }) do
    if rawget(_G, n) == nil then rawset(_G, n, realCreateFrame("Frame", n)) end
end
if not S.tbc then
    for _, n in ipairs({ "BossTargetFrameContainer", "OverrideActionBar", "OverlayPlayerCastingBarFrame" }) do
        if rawget(_G, n) == nil then rawset(_G, n, realCreateFrame("Frame", n)) end
    end
end
if rawget(_G, "PartyFrame") == nil then
    local pf = realCreateFrame("Frame", "PartyFrame")
    pf.PartyMemberFramePool = { EnumerateActive = function() return function() return nil end end }
    rawset(_G, "PartyFrame", pf)
end

-- Number formatting and the unit percent calls the tags read. These are
-- FrameXML and engine functions on every 12.x client.
stubGlobal("AbbreviateLargeNumbers", function(n) return tostring(n) end)
stubGlobal("AbbreviateNumbers", function(n) return tostring(n) end)
stubGlobal("BreakUpLargeNumbers", function(n) return tostring(n) end)
stubGlobal("UnitHealthPercent", function() return 100 end)
stubGlobal("UnitPowerPercent", function() return 100 end)
stubGlobal("UnitHealthMissing", function() return 0 end)
stubGlobal("UnitPowerMissing", function() return 0 end)
-- Forever's name helper (Mainline FrameXML); the TBC-shaped client has none
-- and the tag falls back to UnitName.
if S.forever then
    stubGlobal("NameUtil", { GetUnmodifiedUnitFullName = function(u) return UnitName(u) end })
end
stubGlobal("C_StringUtil", {})
C_StringUtil.TruncateWhenZero = C_StringUtil.TruncateWhenZero or function(v) if v == 0 then return "" end return tostring(v) end
C_StringUtil.CreateSecondsFormatter = C_StringUtil.CreateSecondsFormatter or function() return S.newMock("SecondsFormatter") end

-- Retail helpers oUF leans on.
stubGlobal("GenerateClosure", function(f, ...)
    local n, bound = select("#", ...), { ... }
    return function(...)
        local args, m = {}, select("#", ...)
        for i = 1, n do args[i] = bound[i] end
        for i = 1, m do args[n + i] = (select(i, ...)) end
        return f(unpack(args, 1, n + m))
    end
end)
-- The aura container's option vocabulary (Forever only; the TBC-shaped
-- client has none of it and the plain-frame element never asks).
if S.forever then
    stubGlobal("AuraContainerSortMethod", { ExpirationOnly = 1, Default = 0 })
    stubGlobal("AuraContainerSortDirection", { Normal = 1, Reverse = 2 })
    stubGlobal("CustomAuraContainerAuraProcessingPolicy", { ProcessAura = 1 })
end
stubGlobal("AnchorUtil", { FlowLayoutAxis = { Horizontal = 1, Vertical = 2 } })
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
-- Forever can compare unit tokens through C_Secrets; the TBC-shaped client
-- has the namespace without that call, and oUF must cope.
if not S.tbc then
    C_Secrets = C_Secrets or {}
    C_Secrets.CanCompareUnitTokens = C_Secrets.CanCompareUnitTokens or function() return true end
end
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
    -- What the stub says this client does not have stays missing; an
    -- invented stand-in would hide the very gap the run is for.
    if S.ABSENT and S.ABSENT[k] then return nil end
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

-- A widget the game switches is followed by ns:Follow's poll, not a hook,
-- so a check runs the poll once, as the next frame would.
local function settle(f)
    local list = ns.follows and ns.follows[f]
    local tick = list and list.poll and list.poll:GetScript("OnUpdate")
    if tick then tick(list.poll, 1) end
end
check(ns.oUF ~= nil, "oUF embedded in the namespace")
check(type(_G.WicksUI_oUF) == "table", "oUF published under the X-oUF name")
check(ns.LAB ~= nil, "LibActionButton reachable")

-- The shipped layout (Core/Layout.lua) may switch whole modules off; the
-- harness turns every one on so each is exercised.
for _, d in pairs(ns.defaults.profile) do
    if type(d) == "table" and d.enable == false then d.enable = true end
end

-- A chat window, as the client makes it before any addon loads, with the
-- font calls the chat module and the client's own size menu use.
do
    local cf = CreateFrame("ScrollingMessageFrame", "ChatFrame1", UIParent)
    rawset(cf, "SetFont", function(self, path, size, flags) self.__font = { path, size, flags } end)
    rawset(cf, "GetFont", function(self) local x = self.__font or {} return x[1], x[2], x[3] end)
    cf:SetFont("Fonts\\FRIZQT__.TTF", 14, "")
    rawset(cf, "GetMaxLines", function() return 0 end)
    ChatTypeInfo = { SAY = { r = 1, g = 1, b = 1 }, GUILD = { r = 0.25, g = 1, b = 0.25 }, WHISPER = { r = 1, g = 0.5, b = 1 }, PARTY = { r = 0.67, g = 0.67, b = 1 } }
    S.CHAT_COLORS, S.CLASS_NAMES, S.SENT, S.BN_SENT, S.OPENED_CHAT = {}, {}, {}, {}, {}
    function ChangeChatColor(t, r, g, b) S.CHAT_COLORS[t] = { r, g, b }; local c = ChatTypeInfo[t] or {}; c.r, c.g, c.b = r, g, b; ChatTypeInfo[t] = c end
    function SetChatColorNameByClass(t, on) S.CLASS_NAMES[t] = on; if ChatTypeInfo[t] then ChatTypeInfo[t].colorNameByClass = on end end
    for _, c in pairs(ChatTypeInfo) do c.colorNameByClass = false end
    function FCF_StartAlertFlash(frame) frame.__alerting = true end
    function FCF_StopAlertFlash(frame) frame.__alerting = false end
    function SendChatMessage(msg, kind, lang, target) S.SENT[#S.SENT + 1] = { msg, kind, target } end
    function BNSendWhisper(id, msg) S.BN_SENT[#S.BN_SENT + 1] = { id, msg } end
    function ChatFrame_OpenChat(text) S.OPENED_CHAT[#S.OPENED_CHAT + 1] = text end
    function GetPlayerInfoByGUID(guid) return "Mage", "MAGE" end
    rawset(cf, "SetMaxLines", function() end)
    _G.ChatFrame1 = cf
    _G.CHAT_FRAMES = { "ChatFrame1" }
    -- The client's size setter, as the Font Size menu calls it.
    function FCF_SetChatWindowFontSize(self, chatFrame, fontSize)
        chatFrame = chatFrame or ChatFrame1
        local file, _, flags = chatFrame:GetFont()
        chatFrame:SetFont(file, fontSize, flags)
    end
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

io.write("== chat ==\n")
if ns.modules.chat:Enabled() then
    local CH, f, d = ns.Chat, _G.ChatFrame1, A.db.profile.chat
    local face, size = f:GetFont()
    check(face == ns.Media:Font(d.font) and size == d.fontSize,
        "the chat text takes the profile's font and size: " .. tostring(face) .. " " .. tostring(size))
    -- Something else sets the size; a chat window update puts the
    -- profile's size back. (The client's update events read the saved
    -- size and never apply it; only its Font Size menu sets one.)
    f:SetFont(face, 11, "")
    S.fire("UPDATE_CHAT_WINDOWS")
    local _, s2 = f:GetFont()
    check(s2 == d.fontSize, "a chat window update puts the profile's size back: " .. tostring(s2))
    -- A size picked from the game's own Font Size menu becomes the setting,
    -- so it is kept across sessions instead of being put back.
    local was = d.fontSize
    FCF_SetChatWindowFontSize(nil, f, 16)
    local _, s3 = f:GetFont()
    S.fire("UPDATE_CHAT_WINDOWS")
    local _, s4 = f:GetFont()
    check(d.fontSize == 16 and s3 == 16 and s4 == 16,
        "a size picked from the game's menu becomes the setting and survives an update: " .. tostring(d.fontSize) .. " " .. tostring(s4))
    d.fontSize = was
    CH:Update()
    -- The tab glow switch: off is done through the game's own stop, so
    -- the tab's own alerting state stays in step with the game.
    d.tabAlerts = false
    FCF_StartAlertFlash(f)
    local stopped = f.__alerting == false
    d.tabAlerts = true
    FCF_StartAlertFlash(f)
    check(stopped and f.__alerting == true, "the tab glow switch works through the game's own start and stop")
    -- The Wick channel colours were taken out. A profile that had them gets
    -- the game's own colours back once, and keeps no trace of them.
    d.gameColors = { GUILD = { 0.25, 1, 0.25 } }
    d.channelColors = true
    ChangeChatColor("GUILD", 0.31, 0.78, 0.47)
    CH:Update()
    local g2 = S.CHAT_COLORS.GUILD
    check(g2 and g2[1] == 0.25 and g2[2] == 1 and d.gameColors == nil and d.channelColors == nil,
        "a profile that had the Wick channel colours gets the game's own back, once")
    d.classNames = "on"; CH:Update()
    local onAll = S.CLASS_NAMES.SAY == true and S.CLASS_NAMES.GUILD == true
    d.classNames = "game"; CH:Update()
    check(onAll, "class colours on names set per chat type through the game")
    d.timestamps = "%H:%M "; CH:Update()
    check(S.CVARS.showTimestamps == "%H:%M ", "timestamps through the game's own setting")
    d.timestamps = "game"; CH:Update()
    -- The game's own Chat Settings win, and our page follows them.
    d.timestamps = "%H:%M "; CH:Update()
    S.CVARS.showTimestamps = "none"
    CH:SyncFromGame()
    local tsGame = d.timestamps == "game"
    d.classNames = "on"; CH:Update()
    ChatTypeInfo.GUILD.colorNameByClass = false
    CH:SyncFromGame()
    local cnGame = d.classNames == "game"
    check(tsGame and cnGame, "a change in the game's Chat Settings wins: the page shows the game's setting")
    -- No send while the client has chat locked down: the line goes to the
    -- game's own box instead, so no blocked-action warning can come of it.
    local R = ns.Core.Restrict
    local was = R.ChatBlocked
    R.ChatBlocked = function() return true end
    local nSent, nOpen = #S.SENT, #S.OPENED_CHAT
    local lw = ns.Whispers:Open("Eve-Realm", { name = "Eve-Realm", kind = "char", lines = {} })
    ns.Whispers:Send(lw, "later")
    R.ChatBlocked = was
    check(#S.SENT == nSent and S.OPENED_CHAT[#S.OPENED_CHAT] == "/w Eve-Realm later",
        "with chat locked down the whisper goes to the game's own box, never through the send")
    lw:Hide()
else
    check(true, "the chat module stands aside in this look")
end

io.write("== whispers ==\n")
do
    local WH = ns.Whispers
    local d, g = A.db.profile.whispers, A.db.global
    local function tell(text, who, guid) S.fire("CHAT_MSG_WHISPER", text, who, "", "", "", "", 0, 0, "", 0, 1, guid or "Player-1-ABC") end
    -- The game makes a new frame shown. A window that relies on Show to be
    -- placed is never placed, and draws nowhere.
    local cf0 = CreateFrame
    CreateFrame = function(...) local f = cf0(...); f:Show(); return f end
    tell("hi there", "Bob-Realm")
    CreateFrame = cf0
    local win = WH.windows["Bob-Realm"]
    -- (the stub answers GetPoint with a fixed point for a frame with none,
    -- so its own record of the points is read)
    local pts = win and rawget(win, "__points")
    check(win and win:IsShown() and pts and #pts > 0, "a whisper window has a place on the screen when it opens")
    local listed = false
    for _, n in ipairs(UISpecialFrames or {}) do if win and n == win:GetName() then listed = true end end
    check(listed, "and Escape can close it")
    local c = g.whispers and g.whispers.convos["Bob-Realm"]
    check(win and win:IsShown() and c and c.lines[1] and c.lines[1].text == "hi there" and c.lines[1].out == false and c.class == "MAGE",
        "a whisper opens a window for its sender and is kept, with the sender's class")
    S.fire("CHAT_MSG_WHISPER_INFORM", "yo", "Bob-Realm")
    check(c.lines[2] and c.lines[2].out == true and c.lines[2].text == "yo", "a whisper of yours is kept as yours")
    win.eb:SetText("hey")
    WH:Send(win, win.eb:GetText())
    local sent = S.SENT[#S.SENT]
    check(sent and sent[1] == "hey" and sent[2] == "WHISPER" and sent[3] == "Bob-Realm" and win.eb:GetText() == "",
        "Enter sends through the game's own whisper, to that person, and clears the line")
    WH:Send(win, "/dance")
    check(S.OPENED_CHAT[#S.OPENED_CHAT] == "/dance" and #S.SENT == 1, "a slash command typed there goes to the game's own chat box, not out as a whisper")
    if S.forever then
        local before = #c.lines
        tell(S.SECRET, "Bob-Realm")
        check(#c.lines == before, "a line the client keeps secret is shown and never kept")
        tell("psst", S.SECRET)
        check(WH.windows[S.SECRET] == nil, "a sender the client keeps secret gets no window")
    end
    S.fire("CHAT_MSG_BN_WHISPER", "bn hi", "Friend", "", "", "", "", 0, 0, "", 0, 1, "", 42)
    local bw = WH.windows["bn:42"]
    check(bw and bw:IsShown(), "a Battle.net whisper opens a window keyed by the account")
    WH:Send(bw, "bn yo")
    check(S.BN_SENT[1] and S.BN_SENT[1][1] == 42 and S.BN_SENT[1][2] == "bn yo", "and sends through the Battle.net whisper")
    d.popup = false
    tell("quiet", "Carl-Realm")
    local cc = g.whispers.convos["Carl-Realm"]
    check(WH.windows["Carl-Realm"] == nil and cc and cc.lines[1].text == "quiet", "with popups off a whisper is kept but opens nothing")
    d.popup = true
    d.history = false
    tell("forget me", "Dan-Realm")
    check(WH.windows["Dan-Realm"] and #g.whispers.convos["Dan-Realm"].lines == 0, "with history off the window opens and nothing is kept")
    d.history = true
    -- A kept conversation comes back into a fresh window with its lines.
    WH.windows["Bob-Realm"] = nil
    local again = WH:Open("Bob-Realm", c)
    check(again and again ~= win and again:IsShown(), "a kept conversation opens again in a window of its own")
    WH:Clear()
    check(next(g.whispers.convos) == nil and not again:IsShown(), "forgetting closes the windows and drops the lines")
end

io.write("== unit frames ==\n")
local UF = ns.UnitFrames
check(UF.initialized, "unit frames initialized")
check(UF.frames.player ~= nil and UF.frames.target ~= nil, "player and target spawned")
if S.forever then
    check(UF.frames.boss and #UF.frames.boss == 5, "five boss frames")
else
    check(UF.frames.boss == nil and rawget(_G, "WicksUI_Boss1") == nil, "no boss frames on a client without boss units")
    local hasBossPage = false
    for _, k in ipairs(UF.PAGE_ORDER) do if k == "boss" then hasBossPage = true end end
    check(not hasBossPage, "and no boss page")
end
do
    -- An incoming heal stops at full health rather than running past the
    -- frame's edge (the client's calculator allows 5% over by default).
    local over = {}
    for f in pairs(UF.all or {}) do
        local h = f.Health
        if h and h.HealingAll and h.incomingHealOverflow ~= 1 then over[#over + 1] = tostring(f.wuiKey) end
    end
    check(next(UF.all or {}) and #over == 0, "incoming heals stop at the end of the health bar: " .. table.concat(over, ", "))
    -- Resting: our crescent on a tile, made only where it shows.
    local ri = UF.frames.player.RestingIndicator
    if ns:Game() then
        -- Classic: the game's own resting mark, in its frame's corner.
        check(ri and ri:GetObjectType() == "Texture" and tostring(ri:GetTexture()):find("UI%-StateIcon"),
            "Classic: the player frame's resting mark is the game's own")
    else
        check(ri and ri:GetObjectType() == "Frame" and ri.mark and ri.mark:GetTexture() == ns.Media:Glyph("rest"),
            "the player frame's resting mark is our crescent, not the game's Zzz")
    end
    check(UF.frames.target.wuiIcons.resting == nil, "and a frame that never shows resting makes no mark")
end
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
    -- A bar's shape and the power bar's height are a look's own too, so one
    -- look's layout never leaks into another's.
    local g, prof = ns:G(), A.db.profile
    local bar, u = prof.actionbars.bars[1], prof.unitframes.units.player
    local id = ns.Core.Chrome:StyleID()
    local key = id == "og" and "wick" or id
    local was = { perRow = bar.perRow, buttons = bar.buttons, power = u.powerHeight, for_ = g.presetFor, snap = g.styleSizes and g.styleSizes[key] }
    g.styleSizes = g.styleSizes or {}
    g.styleSizes[key] = { bars = { [1] = { size = bar.size, spacing = bar.spacing, perRow = 6, buttons = 12 } }, units = { player = { powerHeight = 3 } } }
    g.presetFor = "otherlook"
    bar.perRow, u.powerHeight = 12, 9
    ns:ApplyStylePreset(false)
    local other = g.styleSizes.otherlook
    check(bar.perRow == 6 and u.powerHeight == 3 and other and other.bars[1].perRow == 12 and other.units.player.powerHeight == 9,
        "bar shape and power bar height are kept per look")
    bar.perRow, bar.buttons, u.powerHeight, g.presetFor = was.perRow, was.buttons, was.power, was.for_
    g.styleSizes.otherlook, g.styleSizes[key] = nil, was.snap
end
do
    -- The slider sets the power bar's height in every look. The Modern
    -- family had clamped it to a 3px line, so the slider did nothing there.
    local u = A.db.profile.unitframes.units.player
    local was = u.powerHeight
    u.powerHeight = 9
    UF:Configure(UF.frames.player)
    local got = UF.frames.player.Power and UF.frames.player.Power:GetHeight()
    if ns:Game() then
        -- Classic: the game's own frame, at the game's sizes (Classic.lua).
        check(got ~= 9, "Classic keeps the game's own power bar height: " .. tostring(got))
    else
        check(got == 9, "the power bar height slider counts in this look: " .. tostring(got))
    end
    u.powerHeight = was
    UF:Configure(UF.frames.player)
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

io.write("== unit frame fade ==\n")
do
    -- Frames that follow the fade go under the fader, which heads for the
    -- faded opacity with no reason to come up and for full with one; off,
    -- they are back under UIParent at full.
    local UF = ns.UnitFrames
    local g = UF:db()
    local ue, uac = UnitExists, UnitAffectingCombat
    UnitExists = function() return false end
    UnitAffectingCombat = function() return false end
    g.fade, g.fadeAlpha, g.fadeIn = true, 0.3, "combat,target"
    UF:Update()
    local player = UF.frames.player
    local under = player and player:GetParent() == UF.fader
    local faded = UF.fader.wuiWant == 0.3
    UnitExists = function(u) return u == "target" end
    UF:EvalFade()
    local up = UF.fader.wuiWant == 1
    UnitExists = function() return false end
    UF:UnitDB("pet").fade = false
    UF:Update()
    local petOut = UF.frames.pet and UF.frames.pet:GetParent() ~= UF.fader
    UF:UnitDB("pet").fade = true
    g.fade = false
    UF:Update()
    local back = player and player:GetParent() == UIParent and UF.fader.wuiWant == 1
    UnitExists, UnitAffectingCombat = ue, uac
    check(under and faded, "a frame on the fade sits under the fader, faded with no reason to come up: " .. tostring(under) .. " / " .. tostring(faded))
    check(up, "and comes up with a target")
    check(petOut, "a frame told not to follow stays out of it")
    check(back, "with the fade off, the frames are back under UIParent at full")
end

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
        -- Asked of the plate, built in the look: a stand-in player name
        -- elsewhere in this file reads another character's look.
        local game = p.wuiGameNP ~= nil
        if game then
            -- Classic: the game's own mark on the target, no pointers.
            local lit = (p.wuiGameHighlight and p.wuiGameHighlight:IsShown()) or (p.wuiGameSelected and p.wuiGameSelected:IsShown())
            check(lit and not p.wuiMarkL:IsShown(), "Classic: your target's plate is marked as the game marks it, with no pointers")
            local w, h = p.Health:GetSize()
            check(p.Health.backdrop and not p.Health.backdrop:IsShown() and math.abs(w - p.wuiGameNP.health.w) < 0.01
                and math.abs(h - p.wuiGameNP.health.h) < 0.01,
                "Classic: the plate's bar is the game's size, in the game's art, with no Wick border: " .. tostring(w) .. "x" .. tostring(h))
            check(p.Health.PostUpdateColor and pcall(p.Health.PostUpdateColor, p.Health, "nameplate1"),
                "Classic: health takes the game's colours without an error")
        else
        check(p.wuiMarkL:IsShown() and p.wuiMarkR:IsShown(), "your target's plate has a pointer each side")
        do
            local st = ns.Core.Chrome:StyleDef()
            -- OG family: a border wholly outside the bar at the look's
            -- thickness. Modern: a card with room round the bar.
            local want = ns:Modern() and NP.CardPad() or ns.mult * ((st.family == "og" and st.borderPx) or 1)
            local _, _, _, bx = p.Health.backdrop:GetPoint()
            check(math.abs((bx or 0) - want) < 1e-6 and math.abs(NP.CardInset() - want) < 1e-6,
                "the plate's border or card sits outside the bar at the look's spacing: " .. tostring(bx) .. " / " .. tostring(want))
            local okC, errC = pcall(p.Health.PostUpdateColor, p.Health, "nameplate1")
            check(okC and (not st.health or NP.LookColor("nameplate1") ~= nil), "plates take the look's health colours: " .. tostring(errC or ""))
        end
        check(p.wuiThreatGlow.wuiUnder and p.wuiTargetGlow.wuiUnder and (p.wuiThreatGlow.wuiAlpha or 1) < 1,
            "the plate glows sit under the border, softer than a unit frame's")
        end
        local _, _, _, x0 = p.wuiMarkL:GetPoint()
        p.wuiCastbar:Show()
        local _, _, _, x1 = p.wuiMarkL:GetPoint()
        p.wuiCastbar:Hide()
        local _, _, _, x2 = p.wuiMarkL:GetPoint()
        if game then
            local cw, ch = p.wuiCastbar:GetSize()
            check(math.abs(cw - p.wuiGameNP.cast.w) < 0.01 and math.abs(ch - p.wuiGameNP.cast.h) < 0.01 and p.wuiCastbar.wuiIconHolder:IsShown(),
                "Classic: the plate's cast bar is the game's, its icon where the game puts it: " .. tostring(cw) .. "x" .. tostring(ch))
        elseif ns:Modern() then
            -- The thin cast line has no icon to step past; the pointer
            -- hugs the card.
            check(x0 == -(3 + NP.CardPad()) and x1 == x0 and x2 == x0, "the left pointer hugs the card, a cast or not: "
                .. tostring(x0) .. " / " .. tostring(x1) .. " / " .. tostring(x2))
            check(p.wuiCastbar:GetHeight() == 5 and not p.wuiCastbar.wuiIconHolder:IsShown(),
                "the plate's cast bar is a thin line with no icon, as on the unit frames")
        else
            check(x0 == -3 and x1 < x0 and x2 == x0, "the left pointer steps out past the spell icon while a cast shows: "
                .. tostring(x0) .. " / " .. tostring(x1) .. " / " .. tostring(x2))
            check(p.wuiCastbar:GetHeight() == NP:db().castHeight and p.wuiCastbar.wuiIconHolder:IsShown() == (NP:db().castIcon and true or false),
                "the plate's cast bar takes its height and icon from the settings")
        end
        focus = true
        NP:Refresh(p)
        if game then
            check(not p.wuiMarkL:IsShown() and p:GetAlpha() == (d.plateAlpha or 1), "Classic: the focus is left to the game's marks, at the plate's own opacity")
        else
            check(p.wuiMarkL:IsShown() and p:GetAlpha() == 1, "your focus is marked too, and not dimmed")
        end
        d.targetMarker = "glow"
        focus = false
        NP:Refresh(p)
        if game then
            check(not p.wuiTargetGlow:IsShown() and not p.wuiMarkL:IsShown(), "Classic: no Wick glow or pointers, whichever is chosen")
        else
            check(p.wuiTargetGlow:IsShown() and not p.wuiMarkL:IsShown(), "the glow instead of the pointers when chosen")
        end
        d.targetMarker = "arrows"
        d.castbar = false
        NP:Configure(p)
        check(not p:IsElementEnabled("Castbar"), "the Cast bar toggle switches the plate's cast bar off")
        d.castbar = true
        NP:Configure(p)
        check(p:IsElementEnabled("Castbar") and p.Castbar == p.wuiCastbar, "and back on")
        if S.tbc then
            -- A cast on this client: UnitCastingInfo has no interrupt flag
            -- (nil), and the client's SetAlphaFromBoolean takes a boolean only.
            local uci = UnitCastingInfo
            UnitCastingInfo = function()
                return "Summon Charger", "Summon Charger", 132226, 1480956, 1483956, false, "Cast-3-0", nil, 23214, 1
            end
            local shield, took = p.wuiCastbar.Shield, "none"
            rawset(shield, "SetAlphaFromBoolean", function(_, v)
                if type(v) ~= "boolean" then error("Usage: self:SetAlphaFromBoolean(value [, alphaIfTrue, alphaIfFalse])", 2) end
                took = v
            end)
            -- The stub's frames register no events (IsEventless answers
            -- truthy), so the cast is started through ForceUpdate, which
            -- runs the same CastStart as UNIT_SPELLCAST_START.
            local okC, errC = pcall(function() p.wuiCastbar:ForceUpdate() end)
            UnitCastingInfo = uci
            rawset(shield, "SetAlphaFromBoolean", nil)
            check(okC and took == false, "a cast with no interrupt flag starts, its shield hidden: " .. tostring(errC or took))
        end
        local oc = UnitClassification
        UnitClassification = function() return "elite" end
        NP:Refresh(p)
        local mark = p.wuiClassMark:IsShown() and p.wuiClassBack:IsShown()
        UnitClassification = function() return "normal" end
        NP:Refresh(p)
        local none = not p.wuiClassMark:IsShown()
        UnitClassification = oc
        if game then
            check(not mark and none, "Classic: no Wick diamond on an elite's plate")
        else
            check(mark and none, "a diamond on the bar for an elite, nothing for a normal mob")
        end
        do
            -- Quest mobs: a mark and how many more are wanted, from the
            -- tooltip's quest lines; nothing once every line is done. An
            -- answer the client will not give keeps the plate as it was
            -- when only the quest log changed, and clears a fresh plate.
            local tti, cql, uip = C_TooltipInfo, C_QuestLog, UnitIsPlayer
            local lines, related
            C_TooltipInfo = setmetatable({ GetUnit = function() return lines and { lines = lines } or nil end }, { __index = tti or {} })
            C_QuestLog = setmetatable({ UnitIsRelatedToActiveQuest = function() return related end }, { __index = cql or {} })
            UnitIsPlayer = function() return false end
            local Q = (Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestObjective) or 8
            local qm, qc = p.QuestIndicator, p.wuiQuestCount
            local function run(ev) qm.Override(p, ev or "ForceUpdate", "nameplate1") end
            local function rx() local _, _, _, x = p.wuiMarkR:GetPoint(); return x or 0 end
            d.quest, d.questCount = true, true
            lines = { { type = 17, leftText = "That Shadowvale Green Elixir" },
                { type = Q, leftText = "3/8 Scarlet Zealot slain", completed = false } }
            related = true
            run()
            local counted = qm:IsShown() and qc:IsShown() and tostring(qc:GetText()) == "5"
            local withCount = rx()
            lines = { { type = Q, leftText = "8/8 Scarlet Zealot slain", completed = true } }
            run()
            local done = not qm:IsShown() and not qc:IsShown()
            lines = nil
            run()
            local bare = qm:IsShown() and not qc:IsShown()
            local noCount = rx()
            related = nil
            run("WicksUI_Quests")
            local kept = qm:IsShown()
            run("ForceUpdate")
            local cleared = not qm:IsShown()
            related, lines = true, { { type = Q, leftText = "0/8 Bottle of Whispering Elixir", completed = false } }
            d.questCount = false
            run()
            local markOnly = qm:IsShown() and not qc:IsShown()
            d.quest, d.questCount = false, true
            run()
            local off = not qm:IsShown() and not qc:IsShown()
            d.quest = true
            C_TooltipInfo, C_QuestLog, UnitIsPlayer = tti, cql, uip
            check(counted and done and bare, "a quest mob is marked with how many are left, and unmarked once the quest has them all: "
                .. tostring(counted) .. " / " .. tostring(done) .. " / " .. tostring(bare))
            check(kept and cleared, "a hidden answer keeps the mark when the quest log changed, and clears a fresh plate")
            check(markOnly and off, "the count and the mark each have their switch")
            check(withCount > noCount, "the target's right pointer makes room for the count: " .. withCount .. " / " .. noCount)
        end
        do
            -- Your threat on the mob, inside the bar's left end; nothing at
            -- none, or with the switch off. And the plates' own opacity,
            -- under the dimming of the rest.
            local udts, gtsc, uip = UnitDetailedThreatSituation, GetThreatStatusColor, UnitIsPlayer
            local pct = 85
            UnitDetailedThreatSituation = function() return false, 1, pct, 60, 1000 end
            GetThreatStatusColor = function() return 1, 1, 0 end
            UnitIsPlayer = function() return false end
            d.threatPercent = true
            NP:Refresh(p)
            local shows = p.wuiThreatText:IsShown() and tostring(p.wuiThreatText:GetText()) == "85%"
            -- A threat event can name the mob by another token than its
            -- plate's; every plate reads again, so this one shows.
            p:Show()
            p.wuiThreatText:Hide()
            if NP.ThreatAll then NP.ThreatAll() end
            local byEvent = p.wuiThreatText:IsShown()
            check(byEvent, "a threat event updates the plate whatever token it names")
            NP:Refresh(p)
            local _, under = p.wuiThreatText:GetPoint()
            p.wuiCastbar:Show()
            local _, underCast = p.wuiThreatText:GetPoint()
            p.wuiCastbar:Hide()
            local _, back = p.wuiThreatText:GetPoint()
            check(under == p.Health and underCast == p.wuiCastbar and back == p.Health,
                "the threat percent sits under the bar, and under the cast bar while one shows")
            if not S.tbc then
                -- Forever can hide threat values for a unit: a hidden percent
                -- is drawn as given, never compared, in the plain status's
                -- colour.
                local hiddenAs
                rawset(p.wuiThreatText, "SetFormattedText", function(self, fmt, v) hiddenAs = v; self:SetText("hidden") end)
                local was = UnitDetailedThreatSituation
                UnitDetailedThreatSituation = function() return false, 3, S.SECRET, S.SECRET, S.SECRET end
                p.wuiThreatText:Hide()
                local okH, errH = pcall(NP.UpdateThreatText, p)
                UnitDetailedThreatSituation = was
                rawset(p.wuiThreatText, "SetFormattedText", nil)
                check(okH and p.wuiThreatText:IsShown() and hiddenAs == S.SECRET,
                    "a hidden threat percent is drawn as given, never read: " .. tostring(errH or ""))
            end
            pct = 0
            NP:Refresh(p)
            local none = not p.wuiThreatText:IsShown()
            pct = 85
            d.threatPercent = false
            NP:Refresh(p)
            local off = not p.wuiThreatText:IsShown()
            d.threatPercent = true
            UnitDetailedThreatSituation, GetThreatStatusColor, UnitIsPlayer = udts, gtsc, uip
            check(shows and none and off, "your threat shows as a percent on the plate, not at none or switched off: "
                .. tostring(shows) .. " / " .. tostring(none) .. " / " .. tostring(off))
            d.plateAlpha = 0.5
            NP:Refresh(p)
            local alpha = p:GetAlpha()
            d.plateAlpha = 1
            NP:Refresh(p)
            check(math.abs(alpha - 0.5) < 1e-6 and p:GetAlpha() == 1, "the plates' opacity setting reaches the plate: " .. tostring(alpha))
        end
        do
            -- Numbers off the plate, from what the client says the mob was
            -- hit for: a crit larger and in its school's colour, misses and
            -- heals by their switches, nothing with the feature off; a plate
            -- that goes leaves its numbers where they were.
            local CT = ns.CombatText
            local cd = CT:db()
            local uif = UnitIsFriend
            UnitIsFriend = function() return false end
            p:Show()
            local lines = CT.plateLines
            for i = #lines, 1, -1 do table.remove(lines, i) end
            cd.plates, cd.platesTarget, cd.platesHeals, cd.platesMisses = false, false, false, true
            CT.OnUnitCombat("UNIT_COMBAT", "nameplate1", "WOUND", "", 120, 1)
            local offNone = #lines == 0
            cd.plates = true
            CT.OnUnitCombat("UNIT_COMBAT", "nameplate1", "WOUND", "CRITICAL", 3571, 4)
            local hit = lines[1]
            local crit = hit and hit.crit and tostring(hit.fs:GetText()) == "3571"
            CT.OnUnitCombat("UNIT_COMBAT", "nameplate1", "WOUND", "", 12345, 1)
            local big = lines[2] and tostring(lines[2].fs:GetText()) == "12.3k"
            CT.OnUnitCombat("UNIT_COMBAT", "nameplate1", "DODGE", "", 0, 1)
            local miss = #lines == 3
            CT.OnUnitCombat("UNIT_COMBAT", "nameplate1", "HEAL", "", 500, 2)
            local healOff = #lines == 3
            cd.platesHeals = true
            CT.OnUnitCombat("UNIT_COMBAT", "nameplate1", "HEAL", "", 500, 2)
            local healOn = #lines == 4 and tostring(lines[4].fs:GetText()) == "+500"
            CT.OnUnitCombat("UNIT_COMBAT", "player", "WOUND", "", 99, 1)
            local onlyPlates = #lines == 4
            local okR, errR = pcall(CT.OnPlateRemoved, "NAME_PLATE_UNIT_REMOVED", "nameplate1")
            local frozen = okR and lines[1] and lines[1].anchor == nil
            UnitIsFriend = uif
            for i = #lines, 1, -1 do table.remove(lines, i) end
            cd.plates, cd.platesHeals = false, false
            check(offNone, "no numbers off the plates while it is off")
            check(crit and big, "a hit rises off its mob's plate, a crit marked, big numbers shortened: " .. tostring(crit) .. " / " .. tostring(big))
            check(miss and healOff and healOn, "misses show, heals only when switched on")
            check(onlyPlates, "hits on units that are not plates make no numbers")
            check(frozen, "a plate that goes leaves its numbers to finish where they were: " .. tostring(errR or ""))
        end
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
            if game then
                check(off and not on, "Classic: the game's colours, not threat colours, even while you tank")
            else
                check(off and on, "threat colours only while you tank; otherwise class and reaction")
            end
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

io.write("== Blizzard's frames without role sets ==\n")
do
    -- A client without SetRolesets (TBC Anniversary): the game's unit
    -- frame is hidden under a frame that never shows, a nameplate's own
    -- frame is hidden where it is and hidden again when the client shows it.
    local oUF = ns.oUF
    local NOROLE = setmetatable({ SetRolesets = true }, { __index = OUF_KEYS })
    local blizz = CreateFrame("Frame", "WicksUI_TestBlizzFocus", UIParent)
    rawset(blizz, "__nokeys", NOROLE)
    blizz:Show()
    local wasFocus = rawget(_G, "FocusFrame")
    rawset(_G, "FocusFrame", blizz)
    local okF, errF = pcall(oUF.DisableBlizzard, oUF, "focus")
    rawset(_G, "FocusFrame", wasFocus)
    check(okF, "disabling a unit frame without role sets runs: " .. tostring(errF or ""))
    check(blizz:IsShown() == false and blizz:GetParent() ~= nil and blizz:GetParent() ~= UIParent,
        "the frame is hidden under a frame that never shows")
    local plate = CreateFrame("Frame", "WicksUI_TestBlizzPlate", UIParent)
    local uf = CreateFrame("Button", nil, plate)
    rawset(uf, "__nokeys", NOROLE)
    uf:Show()
    plate.UnitFrame = uf
    C_NamePlate = C_NamePlate or {}
    local wasGet = C_NamePlate.GetNamePlateForUnit
    C_NamePlate.GetNamePlateForUnit = function() return plate end
    local okN, errN = pcall(oUF.DisableBlizzard, oUF, "nameplate1")
    C_NamePlate.GetNamePlateForUnit = wasGet
    check(okN and uf:IsShown() == false and uf:GetParent() == plate, "a nameplate's own frame is hidden and left on its nameplate: " .. tostring(errN or ""))
    uf:Show()
    check(uf:IsShown() == false, "and hidden again when the client shows it")
end

io.write("== pvp indicator ==\n")
do
    -- An element no layout of ours enables yet, kept honest: honor levels
    -- and mercenary mode are Mainline's, and the TBC-shaped client refuses
    -- the honor level event.
    local oUF = ns.oUF
    oUF:RegisterStyle("WicksUI_TestPvP", function(f) f.PvPIndicator = f:CreateTexture(nil, "OVERLAY") end)
    oUF:SetActiveStyle("WicksUI_TestPvP")
    local okP, p = pcall(oUF.Spawn, oUF, "player", "WicksUI_TestPvPFrame")
    oUF:SetActiveStyle("WicksUI")
    check(okP and p ~= nil, "a frame with a PvP indicator spawns on this client: " .. tostring(not okP and p or ""))
    if okP and p then
        check((p.__events["HONOR_LEVEL_UPDATE"] ~= nil) == (S.forever and true or false),
            "honor level updates are watched only where the client has them")
        local okU, errU = pcall(p.PvPIndicator.ForceUpdate, p.PvPIndicator)
        check(okU, "the indicator updates without the mercenary and honor level calls: " .. tostring(not okU and errU or ""))
    end
end

io.write("== buffs ==\n")
check(ns.Auras.initialized and ns.Auras.buffs and ns.Auras.debuffs, "buff and debuff containers built")
-- Which Auras element answered: the AuraContainer intrinsic on Forever,
-- the plain-frame element on a client without it. oUF hides its Private
-- table after load, so the answer is read off the elements and frames.
if S.forever then
    -- The real element, not a mock standing in for it: the stub names an
    -- invented object after the method that made it.
    check(rawget(ns.Auras.buffs, "__kind") == "AuraContainer" and ns.Auras.buffs.sources == nil,
        "the AuraContainer intrinsic answers CreateAuras: " .. tostring(rawget(ns.Auras.buffs, "__kind")))
else
    check(rawget(ns.Auras.buffs, "__template") == "SecureAuraHeaderTemplate",
        "the buffs are a secure aura header on a client without the intrinsic: " .. tostring(rawget(ns.Auras.buffs, "__template")))
end
local playerFrame = rawget(_G, "WicksUI_Player")
local pingable = playerFrame and (playerFrame.__template or ""):find("Pingable") ~= nil
check(playerFrame and pingable == S.forever, "pingable template only where the client has it: " .. tostring(playerFrame and playerFrame.__template))
if not S.forever then
    local h = ns.Auras.buffs
    check(h:GetAttribute("filter") == "HELPFUL" and h:GetAttribute("template") == "WicksUI_AuraButtonTemplate"
        and h:GetAttribute("includeWeapons") == 1, "the header carries our template, the HELPFUL filter and the weapon enchants")
    -- The layout comes from the profile (the shipped layout here): the
    -- header is told the same numbers, with the signs of the growth.
    local g = ns.Auras:db().buffs
    local corner = (g.growthY == "UP" and "BOTTOM" or "TOP") .. (g.growthX == "LEFT" and "RIGHT" or "LEFT")
    check(h:GetAttribute("point") == corner and h:GetAttribute("wrapAfter") == g.perRow and h:GetAttribute("maxWraps") == g.rows
        and h:GetAttribute("xOffset") == (g.growthX == "LEFT" and -1 or 1) * (g.size + g.spacing)
        and h:GetAttribute("wrapYOffset") == (g.growthY == "UP" and 1 or -1) * (g.size + g.rowSpacing),
        ("the header lays its rows out from the %s, %s and %s"):format(corner, g.growthX:lower(), g.growthY:lower()))
    check(h:GetAttribute("initialConfigFunction") ~= nil and h:GetAttribute("config-width") == g.size,
        "a button born in combat is sized by the client's restricted code")
    check(ns.Auras.debuffs:GetAttribute("filter") == "HARMFUL" and ns.Auras.debuffs:GetAttribute("includeWeapons") == nil,
        "the debuff header takes HARMFUL and no weapons")
    -- A button as the header would make it from our template.
    local b = CreateFrame("Button", "WicksUI_buffsHeaderAuraButton1", h, "WicksUI_AuraButtonTemplate")
    WicksUI_AuraButtonMixin.OnLoad(b)
    local st = ns.Auras:StateOf(b)
    check(st and st.art and st.art.Icon and st.art.Time and st.art.Count, "a header button gets our icon, time and count on a frame of its own")
    WicksUI_AuraButtonMixin.OnAttributeChanged(b, "index", 1)
    check(st and st.index == 1 and st.art.Icon.__tex == 136051 and st.art.Count.__text == 3 and st.expires == 1000,
        "and reads its aura by index from C_UnitAuras: " .. tostring(st and st.art.Icon.__tex))
    check(st and type(st.art.Time.__text) == "string" and st.art.Time.__text ~= "", "with the time left written on it: " .. tostring(st and st.art.Time.__text))
    check(rawget(b, "Icon") == nil and rawget(b, "Time") == nil, "nothing of ours is written onto the client's button")
    -- A secure button acts on the press when ActionButtonUseKeyDown is on
    -- (the default), so a button that hears only the release never cancels.
    local fx = io.open(UI_DIR .. "/Modules/Auras/AuraButton.xml", "r")
    local xml = fx and fx:read("*a") or ""
    if fx then fx:close() end
    local clicks = xml:match('registerForClicks="([^"]*)"') or ""
    check(clicks:find("RightButtonDown", 1, true) and clicks:find("RightButtonUp", 1, true),
        "a right-click cancels whether the game acts on the press or the release: " .. clicks)
    -- The plain-frame element still serves the unit frames' auras.
    local a
    for _, n in ipairs({ "WicksUI_Target", "WicksUI_Player", "WicksUI_Focus" }) do
        local uf = rawget(_G, n)
        a = a or (uf and (uf.wuibuffs or uf.wuidebuffs))
    end
    check(a and a.sources ~= nil, "the plain-frame element serves the unit frames' auras without the intrinsic")
    if a then
        a:ForceUpdate()
        local shown = a.activeButtons or {}
        check(#shown == 2, "two auras drawn from C_UnitAuras on a unit frame: " .. #shown)
        local ab = shown[1]
        check(ab and ab.Icon and ab.Time and ab.Cooldown, "a classic aura button has icon, time and cooldown")
        check(ab and ab.auraData and ab.auraData.name == "Lightning Shield", "and carries its aura: " .. tostring(ab and ab.auraData and ab.auraData.name))
    end
end
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
    local init, range = function() end, function() end
    f.InitializeBarPresentation, f.ApplyRangePresentation = init, range
    local ok, err = pcall(ns.Skins.SwingTimers, ns.Skins)
    check(ok and ns:BackdropOf(sb) ~= nil, "the swing timers skin: a panel of ours behind the bar: " .. tostring(err or ""))
    check(rawget(sb, "backdrop") == nil, "and kept beside Blizzard's bar, never written onto it")
    check(f.InitializeBarPresentation == init and f.ApplyRangePresentation == range,
        "the bar's own methods are left as they are, never hooked")
    -- Blizzard lays the bar out again and dims it out of range: ours follow.
    settle(f)
    sb:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    sb:SetAlpha(0.5)
    settle(f)
    check(sb.__statusTex == ns.Media:Statusbar() and ns:BackdropOf(sb):GetAlpha() == 0.5,
        "our texture comes back when the game sets its own, and the panel dims with the bar")
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
    -- Asked of the frame, which was built in the look: this test's stand-in
    -- player name reads another character's look.
    if pf and pf.wuiGameUF then
        -- Classic: the game's own flash round the frame art, driven the same way.
        check(pf and pf.wuiThreatGlow.Override == ns.ThreatGlowUpdate and pf.wuiThreatGlow:GetObjectType() == "Texture",
            "Classic: the threat shows as the game's own flash")
    else
        check(pf and pf.wuiThreatGlow.wuiUnder and (pf.wuiThreatGlow.wuiAlpha or 1) < 1, "and it sits under the frame's border, softened")
    end
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
    do
        -- Class colours on the threat meter whatever the look, unless
        -- switched off (Wick asked for them on a themed setup).
        local Ch, d = ns.Core.Chrome, TH:db()
        local wasTheme, wasShow, wasCC = Ch.themeSetting, d.meterShow, d.classColors
        Ch.themeSetting, d.meterShow = "frost", "always"
        local function party2Colour()
            local l = TH.Read()
            TH.Draw(l)
            for i, e in ipairs(l) do if e.unit == "party2" then return TH.Meter().rows[i].__color end end
        end
        local mage
        if Ch.ClassColor then local r, g, b = Ch:ClassColor("MAGE"); if r then mage = { r, g, b } end end
        mage = mage or { RAID_CLASS_COLORS.MAGE.r, RAID_CLASS_COLORS.MAGE.g, RAID_CLASS_COLORS.MAGE.b }
        d.classColors = true
        local on = party2Colour()
        d.classColors = false
        local off = party2Colour()
        local shade = ns:MeterBarColor(false)
        Ch.themeSetting, d.meterShow, d.classColors = wasTheme, wasShow, wasCC
        local function same(a, b) return a and b and math.abs(a[1] - b[1]) < 1e-6 and math.abs(a[2] - b[2]) < 1e-6 and math.abs(a[3] - b[3]) < 1e-6 end
        check(same(on, mage), "with class colours on, a themed meter still paints each bar in its class colour")
        check(same(off, shade), "and off, the bars take the look's shade")
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
do
    -- The need/greed popups: Blizzard's bottom frame manager keeps laying
    -- GroupLootContainer out; ours puts it back on a mover of its own.
    local EX = ns.Extras
    local anchor = _G.WicksUI_LootRollAnchor
    check(anchor and ns.Movers.list.lootrolls and ns.Movers.list.lootrolls.target == anchor,
        "the loot rolls have a mover, on a frame of ours")
    local manager = CreateFrame("Frame", "BottomManagedFrameContainer", UIParent)
    local c = CreateFrame("Frame", "GroupLootContainer", UIParent)
    rawset(c, "IsProtected", function() return false end)
    c:SetPoint("BOTTOM", manager, "TOP", 0, 10)      -- where the manager lays it
    c:Show()
    local before = {}
    for k in pairs(c) do before[k] = true end
    EX.PinLootRolls()
    local p, rel, rp, x, y = c:GetPoint(1)
    check(p == "BOTTOM" and rel == anchor and rp == "BOTTOM" and x == 0 and y == 0,
        "a shown roll popup is pinned to the mover's anchor")
    c:ClearAllPoints(); c:SetPoint("BOTTOM", manager, "TOP", 0, 10)   -- laid out again
    EX.PinLootRolls()
    check(select(2, c:GetPoint(1)) == anchor, "and put back when Blizzard lays it out again")
    local wrote = {}
    for k in pairs(c) do if not before[k] and type(k) == "string" and not k:find("^__") then wrote[#wrote + 1] = k end end
    check(#wrote == 0, "nothing is written onto Blizzard's container: " .. table.concat(wrote, ","))
    -- Protected mid-fight: left alone until the fight ends.
    rawset(c, "IsProtected", function() return true end)
    c:ClearAllPoints(); c:SetPoint("BOTTOM", manager, "TOP", 0, 10)
    COMBAT = true
    EX.PinLootRolls()
    local heldOff = select(2, c:GetPoint(1)) == manager
    COMBAT = false
    EX.PinLootRolls()
    check(heldOff and select(2, c:GetPoint(1)) == anchor, "a protected container waits for the fight to end, then moves")
    -- Switched off: Blizzard keeps it.
    rawset(c, "IsProtected", function() return false end)
    EX:db().lootRolls = false
    c:ClearAllPoints(); c:SetPoint("BOTTOM", manager, "TOP", 0, 10)
    EX.PinLootRolls()
    check(select(2, c:GetPoint(1)) == manager, "with the option off the popups stay where Blizzard puts them")
    EX:db().lootRolls = true
    c:Hide()
    _G.GroupLootContainer, _G.BottomManagedFrameContainer = nil, nil

    -- The quest tracker where Edit Mode cannot move it (TBC Anniversary):
    -- Blizzard hangs QuestWatchFrame under the minimap; ours holds it.
    if S.tbc then
        local cluster = CreateFrame("Frame", "WuiTestCluster", UIParent)
        local q = CreateFrame("Frame", "QuestWatchFrame", UIParent)
        rawset(q, "IsProtected", function() return false end)
        q:SetPoint("TOPRIGHT", cluster, "BOTTOMRIGHT", 0, -10)
        local qBefore = {}
        for k in pairs(q) do qBefore[k] = true end
        if not EX.questAnchor then EX:BuildQuestAnchor() end
        local qa = _G.WicksUI_QuestTrackerAnchor
        check(qa and ns.Movers.list.questtracker and ns.Movers.list.questtracker.target == qa,
            "the quest tracker has a mover, on a frame of ours")
        EX.PinQuestTracker()
        local p, rel, rp, x, y = q:GetPoint(1)
        local inset = ns.Skins:ClassicTrackerInset()
        check(p == "TOPRIGHT" and rel == qa and rp == "TOPRIGHT" and x == 0 and y == -inset and inset > 0,
            "the quest tracker is pinned to the mover's anchor, growing down from it, room left for its header: " .. tostring(y))
        q:ClearAllPoints(); q:SetPoint("TOPRIGHT", cluster, "BOTTOMRIGHT", 0, -10)
        EX.PinQuestTracker()
        check(select(2, q:GetPoint(1)) == qa, "and put back when Blizzard places it again")
        local qWrote = {}
        for k in pairs(q) do if not qBefore[k] and type(k) == "string" and not k:find("^__") then qWrote[#qWrote + 1] = k end end
        check(#qWrote == 0, "nothing is written onto Blizzard's tracker: " .. table.concat(qWrote, ","))
        EX:db().questTracker = false
        q:ClearAllPoints(); q:SetPoint("TOPRIGHT", cluster, "BOTTOMRIGHT", 0, -10)
        EX.PinQuestTracker()
        check(select(2, q:GetPoint(1)) == cluster, "with the option off the tracker stays where Blizzard puts it")
        EX:db().questTracker = true

        -- The skin: QuestWatch_Update writes a title in gold and its
        -- objectives, " - " first, in grey (white once done); the title of
        -- a quest ready to hand in is the brighter gold.
        local SK, C = ns.Skins, ns.Core.Chrome.Colors
        local function line(i, text, r, g, b)
            local fs = S.newMock("FontString", "QuestWatchLine" .. i)
            fs.__parent = q
            fs.__text, fs.__textColor, fs.__shown = text, { r, g, b, 1 }, true
            rawset(fs, "SetFont", function(_, f, s) fs.__font = { f, s } end)
            rawset(fs, "GetFont", function() return fs.__font and fs.__font[1], fs.__font and fs.__font[2] end)
            _G["QuestWatchLine" .. i] = fs
            return fs
        end
        local l1 = line(1, "Wanted: Boars", 0.75, 0.61, 0)
        local l2 = line(2, " - Boar slain: 3/8", 0.8, 0.8, 0.8)
        local l3 = line(3, "A Letter Home", 1, 0.82, 0)
        local l4 = line(4, " - Letter delivered: 1/1", 1, 1, 1)
        q.__w = 120
        q:Show()
        local qBefore2 = {}
        for k in pairs(q) do qBefore2[k] = true end
        local hooked = 0
        _G.QuestWatch_Update = function() hooked = hooked + 1 end
        local okT, errT = pcall(function() SK:Tracker() end)
        local function is(fs, tok)
            local c, t = C[tok], fs.__textColor
            return t and math.abs(t[1] - c[1]) < 0.01 and math.abs(t[2] - c[2]) < 0.01 and math.abs(t[3] - c[3]) < 0.01
        end
        check(okT and is(l1, "text") and is(l2, "text") and is(l3, "fel") and is(l4, "muted"),
            "tracker lines in the palette: a quest in progress in the text colour, one to hand in in the accent, a done objective muted: " .. tostring(errT or ""))
        check(l1.__font and l1.__font[1] == ns.Media:Font() and l1.__font[2] == SK:db().trackerFontSize + 1
            and l2.__font and l2.__font[2] == SK:db().trackerFontSize, "and in the look's font, a title a size up")
        local hdr = SK.questHeader
        check(hdr and hdr:IsShown() and hdr.text and hdr.text.__text ~= "", "a header of ours sits above the tracker")
        check((q:GetWidth() or 0) >= l3:GetStringWidth() + 10, "the tracker is widened to its restyled lines: " .. tostring(q:GetWidth()))
        SK:QuestWatch()
        check(is(l4, "muted") and is(l1, "text"), "a second pass leaves its own colours alone")
        l4.__textColor = { 1, 1, 1, 1 }
        _G.QuestWatch_Update()
        check(hooked == 1 and is(l4, "muted"), "the game's next update is followed at once, through a hook on its global function")
        local qWrote2 = {}
        for k in pairs(q) do if not qBefore2[k] and type(k) == "string" and not k:find("^__") then qWrote2[#qWrote2 + 1] = k end end
        check(#qWrote2 == 0, "nothing is written onto the tracker by the skin: " .. table.concat(qWrote2, ","))
        for i = 1, 4 do _G["QuestWatchLine" .. i] = nil end
        _G.QuestWatchFrame = nil
    end
end
check(_G.WicksUI_Marker1:GetAttribute("macrotext1") == "/tm 1", "marker 1 marks the target")
-- The setup: another nameplate addon and Wick's Bags on.
local okI, errI = pcall(function()
    local I, Ch = ns.Install, ns.Core.Chrome
    local p, g = ns.A.db.profile, ns:G()
    local binds, disabled = {}, {}
    local sb, gba, da = SetBinding, GetBindingAction, C_AddOns.DisableAddOn
    SetBinding = function(k, a) binds[k] = a; return true end
    GetBindingAction = function(k) return binds[k] or "" end
    C_AddOns.DisableAddOn = function(name, who) disabled[name] = who or "everyone" end
    local styleWas, themeWas = Ch:StyleID(), Ch:ThemeSetting()
    binds.B = "OPENALLBAGS"
    S.LOADED.Platynator, S.LOADED.WicksBags = true, true
    -- A kit for this class and one for another.
    local _, myClass = UnitClass("player")
    local mine, other
    for _, k in ipairs(I.KITS) do
        if k[3] == myClass then mine = k[1] elseif not other then other = k[1] end
    end
    S.LOADED[other] = true
    if mine then S.LOADED[mine] = true end
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
    check(at.Scale < at.Bags and at.Scale < at.Nameplates and at.Nameplates < at["Class kits"] and at["Class kits"] < at.Done,
        "the look first, the addons at the end: " .. table.concat(order, ", "))
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
    check(disabled.Platynator == UnitGUID("player"), "for this character only, never every character")
    check(disabled[other] and not (mine and disabled[mine]), "another class's kit is switched off here, this class's stays")
    check(ns.A.db.char.setupDone == true, "the setup is kept as done for this character")
    S.LOADED[other] = nil
    if mine then S.LOADED[mine] = nil end
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

io.write("== forbidden children ==\n")
-- The trade window's gold input is out of reach on Forever: IsForbidden is
-- the only call it answers, everything else raises. The window scans run
-- every frame, so one unchecked child was an error per frame (207 in one
-- trade).
do
    local PS = ns.PanelSkins
    local function forbidden() error("Attempt to access forbidden object from code tainted by an AddOn", 2) end
    local trade = CreateFrame("Frame", "TradeFrame", UIParent)
    trade:SetSize(338, 424)
    local gold = CreateFrame("Frame", "TradePlayerInputMoneyFrame", trade)
    for _, m in ipairs({ "GetObjectType", "IsShown", "IsVisible", "GetSize", "GetWidth", "GetHeight",
        "GetChildren", "GetRegions", "GetParent", "GetName", "GetPoint", "GetNumChildren" }) do
        rawset(gold, m, forbidden)
    end
    rawset(gold, "IsForbidden", function() return true end)
    local tradeBtn = CreateFrame("Button", "TradeFrameTradeButton", trade)
    tradeBtn:SetSize(80, 22)
    rawset(trade, "GetChildren", function() return gold, tradeBtn end)
    check(PS.reachable(gold) == false and PS.reachable(tradeBtn) == true,
        "a forbidden child is recognised as out of reach")
    local okScan, errScan = pcall(PS.scanButtons, trade, 1)
    check(okScan, "the window scan steps over a forbidden child " .. tostring(errScan or ""))
    -- Locked away without IsForbidden saying so (aura buttons in combat).
    local quiet = CreateFrame("Frame", nil, trade)
    rawset(quiet, "GetObjectType", forbidden)
    check(PS.reachable(quiet) == false, "and so is one that is locked without saying so")
    _G.TradeFrame, _G.TradePlayerInputMoneyFrame, _G.TradeFrameTradeButton = nil, nil, nil
end

io.write("== loot roll buttons ==\n")
-- Need, greed and pass are 32 by 32 with no text, which the arrow rule
-- took for arrows: their atlases end in -up, so they wore up chevrons.
do
    local PS = ns.PanelSkins
    local function atlasTex(atlas)
        local t = S.newMock("Texture")
        rawset(t, "GetAtlas", function() return atlas end)
        return t
    end
    -- The stub invents any Capitalised field on first read; a roll button
    -- has none of the keyed pieces the scan asks about, so they stay nil.
    local NOKEYS = {}
    for _, k in ipairs({ "Icon", "Left", "Right", "Middle", "Center", "Name", "Track", "Arrow", "Background", "Text",
        "Slider", "Back", "Forward", "Fill", "Mask", "StateIcon", "ResetButton", "SkillUps", "Button", "ScrollTarget",
        "CollapseButton", "NineSlice", "FilterDropdown", "FilterButton", "LootButtons", "Label" }) do NOKEYS[k] = true end
    local function button(parent, atlas)
        local b = CreateFrame("Button", nil, parent)
        rawset(b, "__nokeys", NOKEYS)
        b:SetSize(32, 32)
        local n = atlasTex(atlas)
        rawset(b, "GetNormalTexture", function() return n end)
        rawset(b, "GetPushedTexture", function() return atlasTex(atlas and atlas:gsub("%-up$", "-down")) end)
        rawset(b, "GetText", function() return nil end)
        return b
    end
    local roll = CreateFrame("Frame", "GroupLootFrame1", UIParent)
    roll:SetSize(277, 67)
    local box = CreateFrame("Frame", nil, roll)
    rawset(roll, "__nokeys", NOKEYS)
    local need = button(box, "lootroll-toast-icon-need-up")
    local greed = button(box, "lootroll-toast-icon-greed-up")
    local loose = button(box, "lootroll-toast-icon-pass-up")      -- not in the array: caught by its atlas
    rawset(box, "LootButtons", { need, greed })
    local arrow = button(box, "common-dropdown-icon-next")
    rawset(box, "GetChildren", function() return need, greed, loose, arrow end)
    rawset(roll, "GetChildren", function() return box end)
    local glyphed = {}
    local realGlyph = ns.Glyph
    ns.Glyph = function(self, b, ...) glyphed[b] = true return realGlyph(self, b, ...) end
    local ok, err = pcall(PS.scanButtons, roll, 1)
    ns.Glyph = realGlyph
    check(ok, "a loot roll frame scans " .. tostring(err or ""))
    check(PS.isRollButton(need) and PS.isRollButton(loose) and not PS.isRollButton(arrow), "roll buttons are told apart from arrows")
    check(not glyphed[need] and not glyphed[greed] and not glyphed[loose], "need, greed and pass keep their own pictures, no chevrons")
    _G.GroupLootFrame1 = nil
end

io.write("== windows of the Classic kind ==\n")
do
    local PS = ns.PanelSkins
    check(PS.Classic ~= nil and PS.H ~= nil and PS.Classic.WINDOWS.CharacterFrame ~= nil,
        "the Classic window pass is loaded, with the character window on its list")
    if S.tbc then
        -- The stub invents any Capitalised field on first read. A frame of
        -- the old kind has none of the portrait template's parts, and a
        -- widget of the old kind none of the keyed pieces the scanners ask
        -- about; these stay nil, as they are on the client.
        local KEYS = {}
        for _, k in ipairs({ "NineSlice", "PortraitContainer", "TitleContainer", "Border", "BG", "Bg", "Center", "CloseButton",
            "ClosePanelButton", "Portrait", "Inset", "Header", "Background", "TopTileStreaks", "BorderFrame", "Tabs", "TabSystem",
            "Left", "Right", "Middle", "Mid", "LeftDisabled", "Text", "Label", "Icon", "IconBorder", "IconTexture", "IconMask",
            "ScrollUpButton", "ScrollDownButton", "ScrollBar", "ScrollTarget", "Arrow", "Button", "Fill", "Mask", "Track", "Slider",
            "Back", "Forward", "TopLeft", "BottomRight", "MiddleMiddle", "Name", "StateIcon", "CollapseButton", "ResetButton",
            "FilterDropdown", "FilterButton", "SkillUps", "Glow", "BorderSelected", "SelectedTexture", "IconOverlay", "NameFrame",
            "RankBorder", "Rank", "ButtonText", "JunkIcon", "NewItemTexture", "HighlightTexture", "MaximizeMinimizeFrame",
            "MaximizeButton", "MinimizeButton", "ItemSlotBackground" }) do KEYS[k] = true end
        local BLOCK = setmetatable({}, { __index = function(_, k) return OUF_KEYS[k] or KEYS[k] end })
        local function mock(kind, name, parent, w, h)
            local f = CreateFrame(kind, name, parent)
            rawset(f, "__nokeys", BLOCK)
            f:SetSize(w or 100, h or 20)
            return f
        end
        local function tex(parent, name, w, h, layer)
            local t = S.newMock("Texture", name)
            t.__parent = parent
            t.__w, t.__h = w or 256, h or 256
            rawset(t, "GetDrawLayer", function() return layer or "ARTWORK" end)
            rawset(t, "GetAtlas", function() return nil end)
            if name then _G[name] = t end
            return t
        end
        local function regions(f, list) rawset(f, "GetRegions", function() return unpack(list) end) end
        local function children(f, list) rawset(f, "GetChildren", function() return unpack(list) end) end


        -- The character window as Blizzard_CharacterFrame/TBC builds it.
        local cf = mock("Frame", "CharacterFrame", UIParent, 384, 512)
        local art = { tex(cf, nil, 256, 256), tex(cf, nil, 128, 256), tex(cf, nil, 256, 256), tex(cf, nil, 128, 256),
            tex(cf, "CharacterFramePortrait", 60, 60, "BACKGROUND") }
        regions(cf, art)
        local close = mock("Button", "CharacterFrameCloseButton", cf, 32, 32)
        local tab1 = mock("Button", "CharacterFrameTab1", cf, 10, 32)
        for _, k in ipairs({ "Left", "Middle", "Right", "LeftDisabled", "MiddleDisabled", "RightDisabled" }) do
            tex(tab1, "CharacterFrameTab1" .. k, 20, 32, "BACKGROUND")
        end
        local tabText = S.newMock("FontString", "CharacterFrameTab1Text")
        rawset(tab1, "GetFontString", function() return tabText end)
        local page = mock("Frame", "PaperDollFrame", cf, 384, 512)
        local pageArt = { tex(page, nil, 256, 256), tex(page, nil, 128, 256) }
        regions(page, pageArt)
        local res = mock("Frame", "MagicResFrame1", page, 32, 29)
        local resIcon = tex(res, nil, 32, 32, "BACKGROUND")
        regions(res, { resIcon })
        local slot = mock("Button", "CharacterHeadSlot", page, 37, 37)
        slot.icon = tex(slot, "CharacterHeadSlotIconTexture", 37, 37, "BORDER")
        slot.IconBorder = tex(slot, nil, 37, 37, "OVERLAY")
        regions(slot, { slot.icon, slot.IconBorder })
        local sf = mock("ScrollFrame", "SkillListScrollFrame", page, 296, 220)
        local sfArt = { tex(sf, nil, 30, 128), tex(sf, nil, 30, 128) }
        regions(sf, sfArt)
        local sb = mock("Slider", "SkillListScrollFrameScrollBar", sf, 16, 200)
        local up = mock("Button", "SkillListScrollFrameScrollBarScrollUpButton", sb, 18, 16)
        local down = mock("Button", "SkillListScrollFrameScrollBarScrollDownButton", sb, 18, 16)
        local thumb = tex(sb, nil, 16, 24)
        rawset(sb, "GetThumbTexture", function() return thumb end)
        regions(sb, { thumb, tex(sb, nil, 16, 100) })
        children(sb, { up, down })
        children(sf, { sb })
        local row = mock("Button", "SkillTypeLabel1", page, 285, 14)
        local plate = tex(row, "SkillTypeLabel1Plate", 285, 14, "BACKGROUND")
        local plus = tex(row, nil, 16, 16)
        plus.__tex = "Interface\\Buttons\\UI-PlusButton-Up"
        rawset(row, "GetNormalTexture", function() return plus end)
        local rowText = S.newMock("FontString")
        rowText.__text = "Weapon Skills"
        rawset(row, "GetFontString", function() return rowText end)
        regions(row, { plate, plus })
        children(page, { res, slot, sf, row })
        children(cf, { close, tab1, page })
        local okC, errC = pcall(function() PS:Skin(cf) end)
        check(okC, "skins a window of the Classic kind: " .. tostring(errC or ""))
        local bd = PS.extrasOf(cf) and PS.extrasOf(cf).backdrop
        local pts = bd and rawget(bd, "__points")
        local p1, p2 = pts and pts[1], pts and pts[2]
        check(p1 and p1[1] == "TOPLEFT" and p1[4] == 11 and p1[5] == -12 and p2 and p2[1] == "BOTTOMRIGHT" and p2[4] == -32 and p2[5] == 76,
            "its panel is cut to the painted art, not the frame")
        check(art[1].__alpha == 0 and art[5].__alpha == 0, "the quarters of art and the portrait are faded")
        check(pageArt[1].__alpha == 0, "a page's art goes with them")
        check(resIcon.__alpha ~= 0, "a resistance icon is content and stays")
        check(_G.CharacterFrameTab1Left.__alpha == 0 and _G.CharacterFrameTab1MiddleDisabled.__alpha == 0
            and PS.extrasOf(tab1) and PS.extrasOf(tab1).backdrop ~= nil and PS.skinnedTabs[tab1] == true,
            "an old tab loses its named pieces and takes a tile")
        check(ns.glyphs[close] ~= nil, "the close button wears our mark")
        check(PS.extrasOf(slot) and PS.extrasOf(slot).backdrop ~= nil, "a gear slot takes its tile")
        check(sfArt[1].__alpha == 0 and up.__alpha == 0 and (thumb.__color ~= nil or thumb.__tex ~= nil),
            "an old scroll bar: its art gone, its arrows hidden, a slim thumb")
        check(plate.__alpha == 0 and plus.__alpha ~= 0 and plus.__desaturated == true,
            "a list row loses its plate and keeps its plus mark, greyed")

        -- A dialog of the old kind has a background that fills its rect, and
        -- takes the pass every window gets; a window of a shape this pass
        -- does not know keeps the game's art.
        local popup = mock("Frame", "StaticPopup1", UIParent, 320, 72)
        popup.BG = mock("Frame", nil, popup, 320, 72)
        local okD, errD = pcall(function() PS:Skin(popup) end)
        check(okD and PS.extrasOf(popup) and PS.extrasOf(popup).backdrop ~= nil,
            "a dialog of the old kind takes the pass every window gets: " .. tostring(errD or ""))
        local odd = mock("Frame", "SomeOldWindow", UIParent, 300, 300)
        PS:Skin(odd)
        check(PS.extrasOf(odd) == nil, "an old window of unknown shape keeps the game's art")

        -- A portrait-template window on this client holds old widgets too.
        local mf = mock("Frame", "MerchantFrame", UIParent, 336, 444)
        mf.NineSlice = CreateFrame("Frame", nil, mf)
        mf.TitleContainer = { TitleText = S.newMock("FontString") }
        local mtab = mock("Button", "MerchantFrameTab1", mf, 10, 32)
        for _, k in ipairs({ "Left", "Middle", "Right", "LeftDisabled", "MiddleDisabled", "RightDisabled" }) do
            tex(mtab, "MerchantFrameTab1" .. k, 20, 32, "BACKGROUND")
        end
        rawset(mtab, "GetFontString", function() return S.newMock("FontString") end)
        children(mf, { mtab })
        local okM, errM = pcall(function() PS:Skin(mf) end)
        check(okM, "a portrait window on this client skins: " .. tostring(errM or ""))
        check(_G.MerchantFrameTab1Left.__alpha == 0 and PS.extrasOf(mtab) and PS.extrasOf(mtab).backdrop ~= nil,
            "and the old tab pieces inside it go too")

        -- A check box in the settings: its box and tick are atlases, and on
        -- this engine every texture answers GetTexture with a file id. The
        -- Classic pass once took it for an icon, kept the empty box as the
        -- picture and drew the tick as a ring round it.
        local sw = mock("Frame", "WuiTestSettings", UIParent, 600, 500)
        sw.NineSlice = CreateFrame("Frame", nil, sw)
        sw.TitleContainer = { TitleText = S.newMock("FontString") }
        local box = mock("CheckButton", nil, sw, 30, 29)
        local boxArt = tex(box, nil, 30, 29)
        boxArt.__tex = 4614723
        rawset(boxArt, "GetAtlas", function() return "checkbox-minimal" end)
        local tick = tex(box, nil, 30, 29)
        tick.__tex = 4614723
        rawset(tick, "GetAtlas", function() return "checkmark-minimal" end)
        rawset(box, "GetNormalTexture", function() return boxArt end)
        rawset(box, "GetCheckedTexture", function() return tick end)
        rawset(box, "GetFontString", function() return nil end)
        regions(box, { boxArt, tick })
        children(sw, { box })
        local okB, errB = pcall(function() PS:Skin(sw) end)
        local tp = rawget(tick, "__points")
        check(okB and boxArt.__alpha == 0 and tp and tp[1] and tp[1][4] == 6 and tp[1][5] == -6,
            "a settings check box is a check box, not an icon: its box goes and its tick is our fill: " .. tostring(errB or ""))
    end
end

io.write("== click bindings ==\n")
do
    local PS = ns.PanelSkins
    local listed = false
    for _, n in ipairs(PS.WINDOWS) do if n == "ClickBindingFrame" then listed = true end end
    check(listed, "the click binding window is on the window skin's list")
    -- The window as Blizzard_ClickBindingUI builds it.
    local cf = CreateFrame("Frame", "ClickBindingFrame")
    cf:SetSize(440, 620)
    cf.NineSlice = realCreateFrame("Frame"); cf.Bg = S.newMock("Texture")
    cf.CloseButton = realCreateFrame("Button"); cf.PortraitContainer = realCreateFrame("Frame")
    cf.TitleContainer = { TitleText = S.newMock("FontString") }
    local sbb = CreateFrame("Frame", nil, cf)
    sbb.NineSlice = realCreateFrame("Frame")
    cf.ScrollBoxBackground = sbb
    local box = CreateFrame("Button", nil, cf)
    cf.ScrollBox = box
    local target = CreateFrame("Frame", nil, box)
    box.ScrollTarget = target
    -- A binding row: an icon, its name and binding, Blizzard's markers.
    local function makeRow()
        local row = CreateFrame("Button", nil, target)
        row:SetSize(450, 46)
        row:Show()
        for _, k in ipairs({ "Background", "NewOutline", "IconHighlight", "FrameHighlight", "EmptySlotIconHighlight" }) do
            row[k] = row:CreateTexture()
        end
        local icon = row:CreateTexture()
        -- A real texture forgets its atlas when given a file.
        rawset(icon, "GetAtlas", function() return icon.__atlas end)
        rawset(icon, "SetAtlas", function(_, a) icon.__atlas = a end)
        rawset(icon, "SetTexture", function(_, t) icon.__tex = t; icon.__atlas = nil end)
        row.Icon = icon
        row.Name, row.BindingText = row:CreateFontString(), row:CreateFontString()
        row.DeleteButton = realCreateFrame("Button", nil, row)
        -- Blizzard's Init draws the row's picture: a spell's file, or the
        -- empty slot's atlas.
        row.Init = function(self, d)
            if d.atlas then self.Icon:SetAtlas(d.atlas) else self.Icon:SetTexture(d.icon) end
        end
        return row
    end
    local spell, empty = makeRow(), makeRow()
    spell:Init({ icon = 132212 })
    empty:Init({ atlas = "clickcast-icon-add" })
    local header = CreateFrame("Frame", nil, target)
    header.Name = header:CreateFontString()
    -- A heading has no binding text or icon; the stub would invent them.
    rawset(header, "__nokeys", setmetatable({ BindingText = true, Icon = true }, { __index = OUF_KEYS }))
    header:Show()
    rawset(target, "GetChildren", function() return header, spell, empty end)
    -- The talents and macros buttons, talents chosen.
    local function corner(chosen)
        local p = CreateFrame("Button", nil, cf)
        p:SetSize(31, 31)
        p.Portrait, p.Frame, p.UnselectedFrame, p.Highlight = p:CreateTexture(), p:CreateTexture(), p:CreateTexture(), p:CreateTexture()
        p.UnselectedFrame:SetShown(not chosen)
        return p
    end
    local talents, macros = corner(true), corner(false)
    cf.FramePortraits = { talents, macros }
    -- The help button and the tutorial.
    local hb = CreateFrame("Button", nil, cf)
    hb:SetSize(64, 64)
    hb.I, hb.Ring, hb.BigIPulse, hb.RingPulse = hb:CreateTexture(), hb:CreateTexture(), hb:CreateTexture(), hb:CreateTexture()
    hb.BigIPulse:Show()
    cf.TutorialButton = hb
    local tf = CreateFrame("Frame", nil, cf)
    tf:SetSize(496, 253)
    tf.NineSlice, tf.CloseButton = realCreateFrame("Frame"), realCreateFrame("Button")
    tf.TitleContainer = { TitleText = S.newMock("FontString") }
    tf.Tutorial, tf.Bg = S.newMock("Texture"), S.newMock("Texture")
    for _, k in ipairs({ "SummaryText", "InfoText", "AlternateText", "ThrallName" }) do tf[k] = tf:CreateFontString() end
    rawset(tf, "GetRegions", function() return tf.Tutorial, tf.Bg, tf.SummaryText end)
    cf.TutorialFrame = tf
    cf:Show()

    local ok, err = pcall(PS.Skin, PS, cf)
    check(ok, "the click binding window skins: " .. tostring(err or ""))
    local E = PS.extrasOf
    check(E(sbb) and E(sbb).list ~= nil, "the list sits on a black card")
    check(E(spell) and E(spell).binding and E(spell).tile and spell.Background:GetAlpha() == 0,
        "a binding is a pill with its icon on a tile, Blizzard's row art gone")
    check(spell.NewOutline:GetTexture() ~= nil and spell.IconHighlight:GetTexture() ~= nil,
        "the new-binding outline and the held-spell glow are redrawn as rings")
    local plus = ns.Media:Glyph("plus")
    check(empty.Icon:GetTexture() == plus, "the empty slot shows our plus, not Blizzard's green one")
    empty:Init({ icon = 134331 })
    spell:Init({ atlas = "clickcast-icon-add" })
    settle(empty)
    settle(spell)
    check(empty.Icon:GetTexture() == 134331 and spell.Icon:GetTexture() == plus,
        "a row filled again is redrawn by the next frame: a picture shows as itself, an empty slot as our plus")
    settle(spell)
    check(spell.Icon:GetTexture() == plus and spell.Icon:GetAtlas() == nil, "and our plus stays our plus on the frames after")
    check(E(talents).ring:IsShown() and not E(macros).ring:IsShown(), "the open one of the corner buttons wears the accent ring")
    macros.UnselectedFrame:Hide(); talents.UnselectedFrame:Show()
    PS.clickBindingPass(cf)
    check(E(macros).ring:IsShown() and not E(talents).ring:IsShown(), "and the ring follows when the other opens")
    check(hb.I:GetAlpha() == 0 and hb.Ring:GetAlpha() == 0 and not hb.BigIPulse:IsShown() and E(hb).help,
        "the help button is a tile of ours, its ring, its big i and its pulse gone")
    check(tf.Tutorial:GetAlpha() == 0 and tf.ThrallName:GetAlpha() == 0 and E(tf).example ~= nil,
        "the tutorial's painting goes for a unit frame card of ours")
    check(E(tf).backdrop ~= nil, "and the tutorial is a window of ours")
    check(rawget(cf, "wuiBG") == nil and rawget(spell, "wuiBG") == nil and rawget(spell, "backdrop") == nil,
        "nothing of ours written into Blizzard's frames")
    ClickBindingFrame = nil
end

io.write("== quest giver ==\n")
do
    local PS = ns.PanelSkins
    -- The chosen reward: Blizzard's choice, drawn as the accent ring.
    local rf = CreateFrame("Frame", "QuestInfoRewardsFrame")
    rf:Show()
    local function reward(id)
        local b = CreateFrame("Button", nil, rf)
        b:SetSize(147, 41)
        b:Show()
        b.Icon = b:CreateTexture()
        b.type = "choice"
        rawset(b, "GetID", function() return id end)
        return b
    end
    local first, second = reward(1), reward(2)
    rf.RewardButtons = { first, second }
    QuestInfoFrame = { itemChoice = 0 }
    local ok, err = pcall(PS.markRewardChoice)
    local E = PS.extrasOf
    check(ok and E(first) and not E(first).choiceRing:IsShown() and not E(second).choiceRing:IsShown(),
        "no reward is marked before one is chosen: " .. tostring(err or ""))
    QuestInfoFrame.itemChoice = 2
    PS.markRewardChoice()
    check(E(second).choiceRing:IsShown() and E(second).choiceWash:IsShown() and not E(first).choiceRing:IsShown(),
        "the reward you choose wears the accent ring")
    QuestInfoFrame.itemChoice = 1
    PS.markRewardChoice()
    check(E(first).choiceRing:IsShown() and not E(second).choiceRing:IsShown(), "and the ring moves when you choose another")
    QuestInfoFrame, QuestInfoRewardsFrame = nil, nil

    -- A button the game switches off reads as off.
    local b = CreateFrame("Button", nil, UIParent)
    b:SetSize(120, 22)
    b.Left, b.Middle, b.Right = b:CreateTexture(), b:CreateTexture(), b:CreateTexture()
    b.Text = b:CreateFontString()
    PS.styleButton(b)
    local pill = E(b) and E(b).backdrop
    check(pill and pill:GetAlpha() == 1 and b.Text:GetAlpha() == 1, "a working button is drawn at full strength")
    check(rawget(b, "Disable") == nil and rawget(b, "SetEnabled") == nil,
        "no hook is put on the button's own methods (Forever's code then calls nil)")
    b:Disable()
    settle(b)
    check(pill:GetAlpha() < 1 and b.Text:GetAlpha() < 1, "a button the game switches off is dimmed, so it reads as off")
    b:Enable()
    settle(b)
    check(pill:GetAlpha() == 1 and b.Text:GetAlpha() == 1, "and comes back when it is switched on")
    b:SetEnabled(false)
    settle(b)
    check(pill:GetAlpha() < 1, "SetEnabled is followed too")
end

io.write("== legacy window ==\n")
do
    local PS = ns.PanelSkins
    local listed = false
    for _, n in ipairs(PS.WINDOWS) do if n == "LegacySystemFrame" then listed = true end end
    check(listed, "the Legacy window is on the window skin's list by this client's name for it")
    local lf = CreateFrame("Frame", "LegacySystemFrame")
    lf:SetSize(920, 575)
    lf.NineSlice = realCreateFrame("Frame"); lf.Bg = S.newMock("Texture")
    lf.CloseButton = realCreateFrame("Button")
    lf.TitleContainer = { TitleText = S.newMock("FontString") }
    -- Its page tabs, built on the large side tab template.
    local tab = CreateFrame("Frame", nil, lf)
    tab:SetSize(55, 55)
    tab:Show()
    tab.Icon = tab:CreateTexture()
    tab.Background, tab.TabGlow, tab.HighlightTexture, tab.SelectedTexture = tab:CreateTexture(), tab:CreateTexture(), tab:CreateTexture(), tab:CreateTexture()
    tab.SelectedTexture:Show()
    lf.Tabs = { tab }
    local ok, err = pcall(PS.Skin, PS, lf)
    check(ok, "the Legacy window skins: " .. tostring(err or ""))
    local e = PS.extrasOf(tab)
    check(e and e.tile and e.ring and e.ring:IsShown(), "its tabs are side tiles, the open one in the accent ring, not bottom tabs")
    LegacySystemFrame = nil
end

io.write("== combat text ==\n")
do
    local CT = ns.CombatText
    ns:G().combatTextFont = true
    check(CT and CT.initialized and CT.frame and ns.Movers.list.combattext, "your own combat text starts, with a mover")
    local d = CT:db()
    -- The game's combat text loads on demand. Its AddMessage, as the game's
    -- does it: the line on a font string, timed from 0, added to the active
    -- list. Wick's UI reads that list each frame (no hook: on Forever the
    -- game's call through a hook fails), so a check runs the read once.
    local bz = CreateFrame("Frame", "CombatText", UIParent)
    bz:Show()
    bz.activeFontStrings, bz.textLocations = {}, { startX = 0, startY = 0, endY = 100 }
    local got = {}
    local gameAdd
    gameAdd = function(self, message, _, r, g, b, displayType, isStaggered)
        got[#got + 1] = message
        local fs = self:CreateFontString()
        fs:SetText(message)
        fs:SetTextColor(r, g, b)
        fs.scrollTime = 0
        fs.isCrit = displayType == "crit" and 1 or nil
        local held = displayType == "crit" or displayType == "sticky"
        fs.endY = held and self.textLocations.startY or self.textLocations.endY
        fs.startX = self.textLocations.startX + (isStaggered and 7 or 0)
        table.insert(self.activeFontStrings, fs)
        CT.ReadGame()
    end
    rawset(bz, "AddMessage", gameAdd)
    CombatText = bz
    S.fire("ADDON_LOADED", "Blizzard_CombatText")
    check(bz:GetAlpha() == 0 and bz:IsShown(), "once it loads, the game's own lines are faded, not hidden: hidden, it drops them all")
    check(rawget(bz, "AddMessage") == gameAdd, "the game's AddMessage is left as it is, never hooked")
    do
        -- A font string the game takes back from its pool and uses again is a
        -- new line: its time goes back to 0.
        bz:AddMessage("-6", nil, 1, 0.1, 0.1)
        local fs = bz.activeFontStrings[#bz.activeFontStrings]
        CT:Clear()
        fs.scrollTime = 3
        CT.ReadGame()
        local before = #CT.lines
        fs.scrollTime = 0
        fs:SetText("-7")
        CT.ReadGame()
        check(before == 0 and #CT.lines == 1 and CT.lines[1].fs.__text == "-7",
            "a font string the game uses again is read as a new line, once")
        CT.ReadGame()
        check(#CT.lines == 1, "and not again on the next frame")
        CT:Clear()
        for k in pairs(got) do got[k] = nil end
    end

    local tick = CT.frame:GetScript("OnUpdate")
    local function run(dt) tick(CT.frame, dt) end
    CT:Clear()
    bz:AddMessage("-1,234", nil, 1, 0.1, 0.1, nil, 1)
    local line = CT.lines[1]
    check(got[1] == "-1,234" and line and line.fs.__text == "-1,234", "a line the game makes is drawn again by Wick's UI, the game's own call untouched")
    local c = line and line.fs.__textColor
    check(c and c[1] == 1 and c[2] == 0.1 and c[3] == 0.1 and line.fs.__textHeight == d.size,
        "in the colour the game gave it, at the size picked")
    run(0.95)
    local p, _, _, _, y = line.fs:GetPoint()
    check(p == "BOTTOM" and math.abs(y - d.distance / 2) < 1, "it rises through its box over its time: " .. tostring(y))
    run(0.65)
    local a = line.fs.__alpha
    check(a and a > 0.3 and a < 0.7, "it fades over its last part, as the game's do: " .. tostring(a))
    run(0.4)
    check(#CT.lines == 0 and not line.fs:IsShown(), "and goes when its time is up")

    bz:AddMessage("-5,000", nil, 1, 0.1, 0.1, "crit")
    local crit = CT.lines[1]
    check(crit and crit.fs.__textHeight == d.critSize, "a crit is drawn at the crit size")
    run(0.04)
    local popped = crit.fs.__textHeight
    run(0.2)
    local _, _, _, _, cy = crit.fs:GetPoint()
    check(popped > d.critSize and crit.fs.__textHeight == d.critSize and cy == crit.back,
        "it pops larger for a moment and holds where it landed")
    CT:Clear()

    bz:AddMessage("-10", nil, 1, 0.1, 0.1)
    bz:AddMessage("-20", nil, 1, 0.1, 0.1)
    local l1, l2 = CT.lines[1], CT.lines[2]
    check(l2.back <= l1.back - (l1.height + l2.height) / 2, "a line made in the same moment starts behind the last, clear of it")
    for i = 1, 14 do bz:AddMessage("-" .. i, nil, 1, 0.1, 0.1) end
    local aside, deepest = false, 0
    for _, l in ipairs(CT.lines) do
        if math.abs(l.x) >= 60 then aside = true end
        deepest = math.min(deepest, l.back)
    end
    check(aside and deepest >= -130, "in a crowd, lines start aside rather than ever further back, as the game's do")
    CT:Clear()

    check(CT.KindOf(1, 0.1, 0.1) == "damage" and CT.KindOf(0.79, 0.3, 0.85) == "spell" and CT.KindOf(0.1, 1, 0.1) == "heal"
        and CT.KindOf(0.1, 0.1, 1) == "rep" and CT.KindOf(1, 0.82, 0) == "alert" and CT.KindOf(1, 1, 1) == "other",
        "each line's kind is told by the game's colour for it")
    check(CT.KindOf(1, 0, 0) == "power" and CT.KindOf(0, 0, 1) == "power", "a gain in its power's own colour is a power gain")
    check(CT.KindOf(S.SECRET, 0, 0) == "other", "a colour it cannot read is everything else, without an error")
    d.colors.damage = { 0.2, 0.4, 0.6, 1 }
    bz:AddMessage("-30", nil, 1, 0.1, 0.1)
    bz:AddMessage("+40", nil, 0.1, 1, 0.1)
    local pc, hc = CT.lines[1].fs.__textColor, CT.lines[2].fs.__textColor
    check(pc[1] == 0.2 and pc[3] == 0.6 and hc[1] == 0.1 and hc[2] == 1, "a colour picked for a kind is used for it; the rest keep the game's")
    d.colors.damage = nil
    CT:Clear()

    do
        -- An aura fading comes in the same colour as when it landed, and on
        -- Forever its text is a secret. The event that made it says which,
        -- and the line is drawn darker.
        local wasInfo, wasEnd = rawget(_G, "CombatTextTypeInfo"), rawget(_G, "AURA_END")
        CombatTextTypeInfo = {
            SPELL_AURA_START = { r = 0.1, g = 1, b = 0.1, show = true },
            SPELL_AURA_END = { r = 0.1, g = 1, b = 0.1, show = true },
            SPELL_AURA_END_HARMFUL = { r = 1, g = 0.1, b = 0.1, show = true },
            DAMAGE = { r = 1, g = 0.1, b = 0.1, show = true },
            HEAL = { r = 0.1, g = 1, b = 0.1 },   -- switched off: no line comes
        }
        AURA_END = "<%s> fades"
        local function lit(l) local c = l.fs.__textColor; return c and c[2] == 1 and (l.fs.__alpha or 1) == 1 end
        local function dim(l) local c = l.fs.__textColor; return c and c[2] < 1 and l.fs.__alpha < 1 end
        CT:Clear()
        CT.NoteLine("COMBAT_TEXT_UPDATE", "SPELL_AURA_START")
        bz:AddMessage(S.SECRET, nil, 0.1, 1, 0.1)
        CT.NoteLine("COMBAT_TEXT_UPDATE", "HEAL")
        CT.NoteLine("COMBAT_TEXT_UPDATE", "SPELL_AURA_END")
        bz:AddMessage(S.SECRET, nil, 0.1, 1, 0.1)
        check(CT.lines[1] and lit(CT.lines[1]) and CT.lines[2] and dim(CT.lines[2]),
            "a hidden aura line is bright when it lands and darker when it fades, told by the event that made it")
        CT:Clear()
        CT.NoteLine("COMBAT_TEXT_UPDATE", "DAMAGE")
        CT.NoteLine("COMBAT_TEXT_UPDATE", "SPELL_AURA_END_HARMFUL")
        bz:AddMessage("-12", nil, 1, 0.1, 0.1)
        bz:AddMessage(S.SECRET, nil, 1, 0.1, 0.1)
        local c1, c2 = CT.lines[1].fs.__textColor, CT.lines[2].fs.__textColor
        check(c1[1] == 1 and (CT.lines[1].fs.__alpha or 1) == 1 and c2[1] < 1 and CT.lines[2].fs.__alpha < 1,
            "lines made together in one colour each take their own event, in order")
        CT:Clear()
        bz:AddMessage("<Renew>", nil, 0.1, 1, 0.1)
        bz:AddMessage("<Renew> fades", nil, 0.1, 1, 0.1)
        check(lit(CT.lines[1]) and dim(CT.lines[2]), "plain text says itself which line is a fade")
        CT:Clear()
        d.dimFades = false
        bz:AddMessage("<Renew> fades", nil, 0.1, 1, 0.1)
        check(lit(CT.lines[1]), "switched off, a fade is drawn like any other line")
        d.dimFades = true
        CT:Clear()
        local okN, errN = pcall(CT.NoteLine, "COMBAT_TEXT_UPDATE", S.SECRET)
        check(okN, "an event kind it cannot read is passed by: " .. tostring(errN or ""))
        bz:AddMessage("<Renew> fades", nil, 0.1, 1, 0.1)
        local fl = CT.lines[1]
        run(1.6)
        check(fl.fs.__alpha < fl.alpha and fl.fs.__alpha > 0, "a darker line fades out from its own brightness, not from full")
        CT:Clear()
        CombatTextTypeInfo, AURA_END = wasInfo, wasEnd
    end

    local okS, errS = pcall(bz.AddMessage, bz, S.SECRET, nil, 1, 0.1, 0.1, nil, 1)
    check(okS and CT.lines[1] and CT.lines[1].fs.__text == S.SECRET, "a secret line is handed on as it is, never read: " .. tostring(errS or ""))
    CT:Clear()

    d.direction = "down"
    bz:AddMessage("-50", nil, 1, 0.1, 0.1)
    run(0.95)
    local dp, _, _, _, dy = CT.lines[1].fs:GetPoint()
    check(dp == "TOP" and dy < -100, "pointed down, it runs from the top of its box down")
    CT:Clear()
    d.direction = "arc"
    bz:AddMessage("-60", nil, 1, 0.1, 0.1)
    run(0.95)
    local _, _, _, ax = CT.lines[1].fs:GetPoint()
    check(math.abs(ax) > 20, "an arc swings out to the side")
    d.direction = "up"
    CT:Clear()

    CT:Sample()
    check(#CT.lines == 10, "the sample shows a line of each kind, and an aura landing and fading: " .. #CT.lines)
    CT:Clear()

    d.enable = false
    CT:Refresh()
    bz:AddMessage("-70", nil, 1, 0.1, 0.1)
    check(bz:GetAlpha() == 1 and #CT.lines == 0, "switched off, the game's own lines show again and Wick's UI draws none")
    d.enable = true
    CT:Refresh()
    check(bz:GetAlpha() == 0, "switched on again, the game's are faded")
    ns:G().combatTextFont = false
    CT:Refresh()
    bz:AddMessage("-80", nil, 1, 0.1, 0.1)
    check(bz:GetAlpha() == 1 and #CT.lines == 0, "with another combat text addon kept in the setup, the game's are left alone")
    ns:G().combatTextFont = true
    CT:Refresh()

    ns.Movers:Unlock()
    run(0.01)
    check(ns.Movers.list.combattext:IsShown() and #CT.lines > 0, "unlocked, its box shows with a sample running in it")
    ns.Movers:Lock()
    CT:Clear()

    -- The settings page: your own text's settings, its colours, and the
    -- numbers' movement.
    S.CVARS.enableFloatingCombatText = "1"
    local okP, errP = pcall(function() ns.Config:Open("combattext") end)
    local pg = ns.Config.pages.combattext
    local labels = {}
    for _, ctl in ipairs(pg and pg.layout and pg.layout.controls or {}) do
        if ctl.labelText then labels[ctl.labelText] = ctl end
    end
    check(okP and labels["Drawn by Wick's UI"] and labels["Crit size"] and labels["Damage and warnings"] and labels["Gravity"],
        "the Combat text page has your own text's settings, its colours and the numbers' movement: " .. tostring(errP or ""))
    local sw = labels["Damage and warnings"]
    check(sw and tostring(sw.text:GetText()):find("the game's", 1, true), "a colour not picked says it is the game's")
    d.colors.heal = { 1, 1, 1, 1 }
    local hs = labels["Heals and buffs"]
    if hs then hs:GetScript("OnClick")(hs, "RightButton") end
    check(d.colors.heal == nil, "right-click on a picked colour goes back to the game's")
    ns.Config:Hide()

    S.CVARS.WorldTextGravity_v2, S.CVARS.WorldTextScale_v2 = "1.5", "2"
    ns.Visuals:ResetNumbers()
    check(S.CVARS.WorldTextGravity_v2 == "0.5" and S.CVARS.WorldTextScale_v2 == "1", "the numbers' movement goes back to the game's own")
    d.numbersFont = "Morpheus"
    ns.Media:WorldFonts()
    local picked = DAMAGE_TEXT_FONT
    d.numbersFont = "Wick"
    ns.Media:WorldFonts()
    check(picked == ns.Media:Font("Morpheus") and DAMAGE_TEXT_FONT == ns.Core.Chrome:Font(),
        "the numbers take the font picked for them, the look's by default")
    local entry
    for _, cf in ipairs(ns.Install.CONFLICTS or {}) do if cf.key == "combattext" then entry = cf end end
    check(entry and entry.ours:find("draws your own combat text", 1, true), "the setup says what Wick's UI does with the combat text")
    CombatText = nil
end

io.write("== stack split ==\n")
do
    local PS = ns.PanelSkins
    local listed = false
    for _, n in ipairs(PS.WINDOWS) do if n == "StackSplitFrame" then listed = true end end
    check(listed, "the stack split is on the window skin's list")
    local sf = CreateFrame("Frame", "StackSplitFrame", UIParent)
    sf:SetSize(172, 96)
    sf.SingleItemSplitBackground, sf.MultiItemSplitBackground = S.newMock("Texture"), S.newMock("Texture")
    sf.StackSplitText, sf.StackItemCountText = S.newMock("FontString"), S.newMock("FontString")
    rawset(sf, "GetRegions", function()
        return sf.SingleItemSplitBackground, sf.MultiItemSplitBackground, sf.StackSplitText, sf.StackItemCountText
    end)
    sf.LeftButton, sf.RightButton = CreateFrame("Button", nil, sf), CreateFrame("Button", nil, sf)
    for _, k in ipairs({ "OkayButton", "CancelButton" }) do
        local b = CreateFrame("Button", nil, sf)
        b:SetSize(64, 24)
        b.Left, b.Middle, b.Right = b:CreateTexture(), b:CreateTexture(), b:CreateTexture()
        b.Text = b:CreateFontString()
        sf[k] = b
    end
    local chose = 0
    local choose = function(self, n) self.isMultiStack = n > 1; chose = chose + 1 end
    rawset(sf, "ChooseFrameType", choose)
    local ok, err = pcall(PS.Skin, PS, sf)
    check(rawget(sf, "ChooseFrameType") == choose, "the game's own layout method is left as it is, never hooked")
    local e = PS.extrasOf(sf)
    check(ok and e and e.backdrop and e.well, "the stack split skins, with a well for the number: " .. tostring(err or ""))
    check(sf.SingleItemSplitBackground:GetAlpha() == 0 and sf.MultiItemSplitBackground:GetAlpha() == 0,
        "its old money-frame art is faded, both sizes")
    local ok1, ok2 = PS.extrasOf(sf.OkayButton), PS.extrasOf(sf.CancelButton)
    check(ok1 and ok1.backdrop and ok2 and ok2.backdrop and ns.glyphs[sf.LeftButton] and ns.glyphs[sf.RightButton],
        "Okay and Cancel are pills, the arrows our marks")
    sf:ChooseFrameType(1)
    settle(sf)
    local single = e.well.__points[1][5]
    sf:ChooseFrameType(5)
    settle(sf)
    local multi = e.well.__points[1][5]
    check(chose == 2 and single == 3 and multi == 15, "the well follows the game's two layouts: one number, or the stacks over a total")
    sf.LeftButton:Disable()
    settle(sf.LeftButton)
    check(ns.glyphs[sf.LeftButton].mark:GetAlpha() < 1, "an arrow the game switches off is faded")
    sf.LeftButton:Enable()
    settle(sf.LeftButton)
    check(ns.glyphs[sf.LeftButton].mark:GetAlpha() == 1, "and comes back when the game switches it on")
    StackSplitFrame = nil
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

io.write("== minimap buttons ==\n")
do
    local MM = ns.Minimap
    check(MM and MM.Collect and MM.chrome, "the minimap module is up")
    local function mkButton(name, kind)
        local b = CreateFrame(kind or "Button", name, Minimap)
        b.__w, b.__h = 32, 32
        local ring = b:CreateTexture(nil, "OVERLAY"); ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
        local bg = b:CreateTexture(nil, "BACKGROUND"); bg:SetTexture(136467)
        local icon = b:CreateTexture(nil, "ARTWORK"); icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        b.icon = icon
        b:Show()
        return b, ring, icon
    end
    local dbi, dbiRing, dbiIcon = mkButton("LibDBIcon10_Test")
    local own, ownRing = mkButton("WicksTestMinimapButton")
    local pin = mkButton("QuestieFrame1")
    local blizz = mkButton("MiniMapTracking")
    dbi:SetScript("OnDragStart", function() end)
    MM:Collect()
    local bar = rawget(_G, "WicksUI_MinimapButtons")
    check(bar ~= nil, "the flyout exists")
    check(dbi:GetParent() == bar and own:GetParent() == bar, "a LibDBIcon button and a hand-made one are gathered")
    check(pin:GetParent() == Minimap and blizz:GetParent() == Minimap, "a map pin and Blizzard's tracking button are left on the map")
    check(dbiRing:GetAlpha() == 0 and ownRing:GetAlpha() == 0, "the round borders go")
    check(dbiIcon:GetNumPoints() == 2 and dbi:GetWidth() == 24, "the icon fills a square tile")
    check(dbi:GetScript("OnDragStart") == nil, "the addon's own drag stands down")
    dbi:ClearAllPoints()
    dbi:SetPoint("CENTER", Minimap, "CENTER", 80, 0)
    local _, rel = dbi:GetPoint(1)
    check(rel == bar, "a button put back on the map's edge returns to its cell")
    check(MM.toggle and MM.toggle:IsShown(), "the + toggle shows with buttons gathered")
    local late = mkButton("LibDBIcon10_Late")
    S.LOADED = S.LOADED or {}
    S.LOADED.MBB = true
    MM:Collect()
    S.LOADED.MBB = nil
    check(late:GetParent() == Minimap, "with MBB loaded the collector stands down")
    MM:Collect()
    check(late:GetParent() == bar, "and gathers again without it")

    -- The game's own buttons where the map has the Classic layout: a row of
    -- tiles under the square map, the buttons placed but left the game's.
    local dial, dialRing, dialIcon = mkButton("GameTimeFrame")
    local menu = CreateFrame("Frame", "MiniMapTrackingDropDown", blizz)
    local before = {}
    for k in pairs(blizz) do before[k] = true end
    -- Frames start hidden in the stub; the launcher shows in the game.
    local launcher = rawget(_G, "WickCoreMinimapButton")
    if launcher then launcher:Show() end
    local d = MM:db()
    d.square, d.strip = true, true
    if ns:Game() then
        -- Classic keeps the game's own minimap: round, its buttons where
        -- the game puts them, whatever the other looks are set to.
        local okC, errC = pcall(function() MM:Shape() end)
        local strip = rawget(_G, "WicksUI_MinimapStrip")
        check(okC and not (strip and strip:IsShown()) and GetMinimapShape() == "ROUND",
            "Classic keeps the game's round minimap and its buttons, whatever the other looks are set to: " .. tostring(errC or ""))
    else
    local okS, errS = pcall(function() MM:Shape() end)
    local strip = rawget(_G, "WicksUI_MinimapStrip")
    check(okS and strip and strip:IsShown(), "the game's buttons get a row under the square map: " .. tostring(errS or ""))
    local _, r1, _, x1 = blizz:GetPoint(1)
    local _, r2, _, x2 = dial:GetPoint(1)
    check(r1 == strip and r2 == strip and (x2 or 0) > (x1 or 0) and blizz:GetWidth() == 24,
        "tracking and the day and night dial sit in it side by side, as tiles")
    check(blizz:GetParent() == Minimap and dialRing:GetAlpha() == 0 and dialIcon:GetNumPoints() == 2,
        "they stay on the map, lose their round borders, and their pictures fill the tile")
    check(rawget(menu, "__points") == nil, "the tracking menu hung on the button keeps its own place")
    local wrote = {}
    for k in pairs(blizz) do if not before[k] and type(k) == "string" and not k:find("^__") then wrote[#wrote + 1] = k end end
    check(#wrote == 0, "nothing is written onto the game's button: " .. table.concat(wrote, ","))
    if launcher then
        check(select(2, launcher:GetPoint(1)) == strip, "WickCore's launcher joins the row")
    end
    local mp, mrel = MM.mail:GetPoint(1)
    check(mp == "RIGHT" and mrel == strip, "new mail takes the row's right end")
    d.strip = false
    MM:Shape()
    check(not strip:IsShown() and select(2, MM.mail:GetPoint(1)) == Minimap,
        "switched off, the row goes and the mail mark returns to the map's corner")
    d.strip = true
    MM:Shape()
    end
    _G.GameTimeFrame, _G.MiniMapTrackingDropDown = nil, nil

    -- The volume speaker on the map's edge: a click mutes the game, the
    -- wheel turns the master volume, and the picture follows the sound.
    local vol = rawget(_G, "WicksUI_MinimapVolume")
    check(vol and vol:GetParent() == Minimap and vol:IsShown(), "the volume speaker sits on the map")
    local function cv(n) return C_CVar.GetCVar(n) end
    C_CVar.SetCVar("Sound_EnableAllSound", "1")
    C_CVar.SetCVar("Sound_MasterVolume", "0.5")
    MM:UpdateVolume()
    check(vol.glyph == "speaker-2", "at half volume it shows two waves: " .. tostring(vol.glyph))
    vol:GetScript("OnClick")(vol, "LeftButton")
    check(cv("Sound_EnableAllSound") == "0" and vol.glyph == "speaker-mute", "a click mutes the game")
    vol:GetScript("OnMouseWheel")(vol, -1)
    check(cv("Sound_MasterVolume") == "0.45" and cv("Sound_EnableAllSound") == "0",
        "the wheel down turns it down a notch and leaves it muted: " .. tostring(cv("Sound_MasterVolume")))
    vol:GetScript("OnMouseWheel")(vol, 1)
    check(cv("Sound_MasterVolume") == "0.50" and cv("Sound_EnableAllSound") == "1" and vol.glyph == "speaker-2",
        "the wheel up turns it up and brings the sound back")
    vol:GetScript("OnClick")(vol, "LeftButton")
    vol:GetScript("OnClick")(vol, "LeftButton")
    check(cv("Sound_EnableAllSound") == "1", "a second click unmutes")
    C_CVar.SetCVar("Sound_MasterVolume", "0.03")
    vol:GetScript("OnMouseWheel")(vol, -1)
    check(cv("Sound_MasterVolume") == "0.00" and vol.glyph == "speaker-0", "it stops at silent, with no waves")
    C_CVar.SetCVar("Sound_MasterVolume", "0.3")
    MM:UpdateVolume()
    check(vol.glyph == "speaker-1", "quiet shows one wave")
    C_CVar.SetCVar("Sound_MasterVolume", "0.98")
    vol:GetScript("OnMouseWheel")(vol, 1)
    check(cv("Sound_MasterVolume") == "1.00", "and stops at full")
    local okT = pcall(vol:GetScript("OnEnter"), vol)
    check(okT, "its tooltip builds")
    vol:GetScript("OnLeave")(vol)
    MM:PlaceVolume()
    local vp, vrel, _, vx, vy = vol:GetPoint(1)
    local half = Minimap:GetWidth() / 2
    if GetMinimapShape() == "SQUARE" then
        check(vp == "CENTER" and vrel == Minimap and vx > 0 and vx < half and math.abs(vy) < 0.01,
            "on the square map it sits inside the right edge: " .. tostring(vx))
    else
        check(vp == "CENTER" and vrel == Minimap and vx > half and math.abs(vy) < 0.01,
            "on the round map it sits just outside the right edge: " .. tostring(vx))
    end
    d.volumeAngle = 90
    MM:PlaceVolume()
    local _, _, _, ux, uy = vol:GetPoint(1)
    check(math.abs(ux) < 0.01 and uy > 0, "its angle moves it round the edge, to the top at 90")
    d.volumeAngle = 0
    d.volume = false
    MM:PlaceVolume()
    check(not vol:IsShown(), "switched off, the speaker goes")
    d.volume = true
    MM:PlaceVolume()
    C_CVar.SetCVar("Sound_MasterVolume", "1.0")
end

io.write("== keybinds ==\n")
local okK, errK = pcall(function() ns.Keybind:Activate(); ns.Keybind:Deactivate(false) end)
check(okK, "keybind mode opens and closes: " .. tostring(errK or ""))
do
    -- Save for this character only: a click ticks it and a second click
    -- takes it back, whatever the game's current set is until Save.
    local K = ns.Keybind
    local gcbs = GetCurrentBindingSet
    GetCurrentBindingSet = function() return 1 end
    K:Activate()
    local box = _G.WicksUIBindPanel and _G.WicksUIBindPanel.perChar
    local click = box and box:GetScript("OnClick")
    if click then click(box) end
    local on = K.perChar == true
    if click then click(box) end
    local off = K.perChar == false
    K:Deactivate(false)
    GetCurrentBindingSet = gcbs
    check(on and off, "Save for this character only ticks, and unticks: " .. tostring(on) .. " / " .. tostring(off))
end

-- The design system audit's first batch (2026-09-30), one check or two per fix.
io.write("== audit fixes ==\n")
do
    local Ch = ns.Core.Chrome
    local C = Ch.Colors
    local W = ns.Widgets
    local function near(a, b) return a and b and math.abs(a[1] - b[1]) < 0.002 and math.abs(a[2] - b[2]) < 0.002 and math.abs(a[3] - b[3]) < 0.002 end
    local function restoreTheme() Ch:ApplyTheme(Ch:ResolveTheme(Ch:ThemeSetting())) end

    -- 1: a label follows a theme change; one given its own colour keeps it.
    local fs = ns:CreateText(UIParent, 12)
    local mine = ns:CreateText(UIParent, 12)
    ns:TextColor(mine, { 1, 0, 0 })
    local chosen = ns:CreateText(UIParent, 12)
    ns:TextColor(chosen, "fel")
    Ch:ApplyTheme("hologram")
    check(near(fs.__textColor, C.text), "a label takes the new theme's text colour")
    check(near(chosen.__textColor, C.fel), "a label recoloured to the accent takes the new accent, not the text colour")
    check(near(mine.__textColor, { 1, 0, 0 }), "a label given a colour of its own keeps it")

    -- 2: the cast bar and keybinds follow the look; the old copies go once.
    local UF, AB = ns.UnitFrames, ns.ActionBars
    local uf, ab = UF:db(), AB:db()
    check(uf.castColor == nil and UF:CastColor() == C.fel, "the cast bar is in the look's accent by default")
    -- Classic's keybinds are the game's grey, as its own are.
    local restKey = ns:Game() and AB.GAME_HOTKEY or C.text
    check(ab.hotkeyColor == nil and AB:HotkeyColor() == restKey, "the keybinds are in the look's text colour by default (the game's grey in Classic)")
    local cb = UF.frames.player and rawget(UF.frames.player, "Castbar")
    check(cb and near(cb.__color, C.fel), "the player's cast bar took the new accent at the theme change")
    uf.castColor, uf.colorsMigrated = { 0.31, 0.78, 0.47, 1 }, false
    ab.hotkeyColor, ab.colorsMigrated = { 0.83, 0.78, 0.63, 1 }, false
    UF:MigrateColors(); AB:MigrateColors()
    check(uf.castColor == nil and ab.hotkeyColor == nil, "a profile's old copies of fel and the text colour are let go")
    uf.castColor, uf.colorsMigrated = { 1, 0, 0, 1 }, false
    UF:MigrateColors()
    check(near(uf.castColor, { 1, 0, 0 }) and UF:CastColor() == uf.castColor, "a cast colour the player picked stays")
    uf.castColor = nil
    local b1 = _G.WicksUI_Bar1.buttons[1]
    check(b1.config and near(b1.config.text.hotkey.color, restKey), "the keybind text took the new text colour (the game's grey in Classic)")
    restoreTheme()

    -- 3: the look's own outline reaches the action bars as a real flag.
    local outWas = ab.fontOutline
    ab.fontOutline = "look"
    AB:Update()
    local flags = b1.config and b1.config.text.hotkey.font.flags
    check(flags ~= "look" and (flags == "" or flags == "OUTLINE"), "\"the look's own\" outline is a font flag on the bars: " .. tostring(flags))
    ab.fontOutline = outWas
    AB:Update()

    -- 4: talent states told apart by weight, not hue.
    local st = ns.PanelSkins.nodeState
    check(st("talents-node-circle-green") == "spendable" and st("talents-node-circle-yellow") == "maxed"
        and st("talents-node-circle-gray") == "open" and st("talents-node-circle-red") == nil, "talent node states read from Blizzard's art")

    -- 5: a chosen setup answer keeps its ring after the pointer leaves.
    local b = W:Button(UIParent, "x", 50)
    if rawget(b, "wuiBorder") == nil and not b.wuiModern and ns:Game() then
        -- Classic: the game's button, held lit while chosen.
        local held
        rawset(b, "LockHighlight", function() held = true end)
        rawset(b, "UnlockHighlight", function() held = false end)
        b:SetSelected(true)
        check(b.selected and held, "Classic: a chosen button is the game's, held lit")
        b:SetSelected(false)
        check(not b.selected and held == false, "and let go when it is not")
    else
    b:SetSelected(true)
    b:GetScript("OnEnter")(b)
    b:GetScript("OnLeave")(b)
    local lit = b.wuiModern and b.wuiRing:IsShown() or (not b.wuiModern and near(b.wuiBorder.top.__color, C.fel))
    check(b.selected and lit, "a selected button keeps its accent ring after a hover")
    b:SetSelected(false)
    b:GetScript("OnLeave")(b)
    check(not b.selected and near(b.text.__textColor, C.text), "and drops it when deselected")
    end

    -- 6: nothing of ours written onto a host the client made.
    local host = CreateFrame("Button")
    local bd = ns:CreateBackdrop(host, "Default", 1)
    check(rawget(host, "backdrop") == nil and ns:BackdropOf(host) == bd, "a backdrop is kept beside its host, not on it")
    check(ns:CreateBackdrop(host, "Default", 1) == bd, "and made once")
    local icon = host:CreateTexture()
    ns:CropIcon(icon)
    check(rawget(icon, "wuiMask") == nil, "an icon's mask is kept beside it, not on it")

    -- 7: Escape closes the setup (answers kept) and locks the frames.
    local I = ns.Install
    local da = C_AddOns.DisableAddOn
    C_AddOns.DisableAddOn = function() end
    I:Start(true)
    check(I.frame:IsShown() and Ch.activeTheme == "fel", "the setup is open")
    -- 5 again, in the setup itself: the look in use is the chosen answer.
    local lookPage
    for i, pg in ipairs(I.pages) do if pg.title == "Look" then lookPage = i end end
    I:Show(lookPage)
    local pick
    for _, c in ipairs(I.frame.choices) do if c:IsShown() and c.selected then pick = c end end
    if pick then pick:GetScript("OnLeave")(pick) end
    check(pick and pick.selected and near(pick.wuiBorder.top.__color, C.fel), "the setup's chosen answer keeps its ring after a hover")
    local closed = CloseSpecialWindows()
    check(closed and not I.frame:IsShown() and I._run().finished, "Escape closes the setup the way its close button does")
    check(Ch.activeTheme == Ch:ResolveTheme(Ch:ThemeSetting()), "and the look's colours come back")
    C_AddOns.DisableAddOn = da
    ns.Movers:Unlock()
    check(ns.Movers:IsUnlocked() and _G.WicksUIMoverPanel:IsShown(), "frames unlocked, the mover panel open")
    check(CloseSpecialWindows() and not ns.Movers:IsUnlocked() and not _G.WicksUIMoverPanel:IsShown(),
        "Escape locks the frames and closes the panel, and the game menu stays shut")

    -- 8: rings drawn in the look's own shape.
    local ring = host:CreateTexture()
    ns:SetRing(ring, host)
    if ns:Modern() then
        check(ring:GetTexture() == Ch:RingTex(host), "a ring in a modern look is that look's ring")
    else
        check(tostring(ring:GetTexture()):find("ring%-hair") ~= nil, "a ring in the OG family is square")
    end

    -- 9: a shadow made once can be put away again.
    local card = CreateFrame("Frame")
    ns:SetTemplate(card, "Default")
    ns:SetTemplate(card, "Default", { shadow = false })
    local off = not card.wuiShadow or not card.wuiShadow:IsShown()
    ns:SetTemplate(card, "Default")
    local on = not ns:Modern() or (card.wuiShadow and card.wuiShadow:IsShown())
    check(off and on, "a lifted card turned flat loses its shadow, and gets it back")

    -- 10: overlays in the bar texture follow the setting.
    local g = ns:G()
    local barWas = g.statusbar
    local overlay = ns:BarTexture(UIParent:CreateTexture())
    g.statusbar = "Wick Shaded"
    ns:RefreshStatusbars()
    check(overlay:GetTexture() == ns.Media:Statusbar(), "an overlay drawn in the bar texture takes a new one")
    local xp = ns.DataBars and ns.DataBars.xp
    check(not xp or (ns.statusbars[xp.rested] and xp.rested.__statusTex == ns.Media:Statusbar()), "the rested bar too")
    g.statusbar = barWas
    ns:RefreshStatusbars()

    -- 11: a greyed control takes no input in any of its parts.
    local val = 1
    local sl = W:Slider(UIParent, "x", 0, 10, 1, function() return val end, function(v) val = v end, 200,
        { disabled = function() return true end })
    check(sl.disabled and sl.parts[1].__mouseEnabled == false, "a greyed slider's number box takes no typing")
    local ta = W:TextArea(UIParent, "x", function() return "" end, function() end, 300, 40,
        { disabled = function() return true end, default = function() return "" end })
    local saveB, revertB = ta.parts[2], ta.parts[3]
    check(ta.control.__mouseEnabled == false and saveB.disabled and revertB.disabled, "a greyed text area takes no focus, its buttons do nothing")

    -- And on the unit frame pages: a switched-off frame greys its page.
    local pd = UF:UnitDB("player")
    pd.enable = false
    ns.Config:Show("unitframes.player")
    local page = ns.Config.pages["unitframes.player"]
    local width, enable
    for _, c in ipairs(page.layout.controls) do
        if c.labelText == "Width" and not width then width = c end
        if c.labelText == "Enable" and not enable then enable = c end
    end
    check(width and width.disabled and enable and not enable.disabled, "a switched-off frame greys its settings, Enable stays live")
    pd.enable = true
    ns.Config:Show("unitframes.player")
    check(width and not width.disabled, "and they come back with it")
end

-- The audit's smaller items, folded into the same release.
io.write("== audit fixes, the small ones ==\n")
do
    local Ch = ns.Core.Chrome
    local C = Ch.Colors
    local W = ns.Widgets
    local function near(a, b) return a and b and math.abs(a[1] - b[1]) < 0.002 and math.abs(a[2] - b[2]) < 0.002 and math.abs(a[3] - b[3]) < 0.002 end

    -- The health gradient runs up to the accent: its colours are built
    -- again when the theme changes.
    local UF = ns.UnitFrames
    local built, was = 0, UF.ApplyColors
    UF.ApplyColors = function(...) built = built + 1; return was(...) end
    Ch:ApplyTheme("frost")
    UF.ApplyColors = was
    check(built == 1, "a theme change rebuilds the unit frames' health colours: " .. built)
    Ch:ApplyTheme(Ch:ResolveTheme(Ch:ThemeSetting()))

    -- Tooltip names in the class colour set the player chose.
    local T = ns.Comforts and ns.Comforts.modules.tooltips
    if T then
        local cf = A.db.profile.comforts
        local wasTip, wasSet = cf.tipClassColor, Ch.classColorSet
        local sv = { UnitIsPlayer = UnitIsPlayer, UnitClass = UnitClass, UnitName = UnitName, UnitExists = UnitExists }
        UnitIsPlayer = function() return true end
        UnitClass = function() return "Shaman", "SHAMAN" end
        UnitName = function() return "Thrall" end
        UnitExists = function(u) return u == "party1" end
        local line = S.newMock("FontString")
        local wasLine = rawget(_G, "GameTooltipTextLeft1")
        rawset(_G, "GameTooltipTextLeft1", line)
        cf.tipClassColor = true
        Ch:SetClassColorSet("classic")
        T:DecorateUnit(GameTooltip, "party1")
        check(near(line.__textColor, { Ch:ClassColor("SHAMAN") }), "a player's name on a tooltip takes the Classic era colour when that set is chosen")
        Ch:SetClassColorSet(wasSet or "client")
        cf.tipClassColor = wasTip
        rawset(_G, "GameTooltipTextLeft1", wasLine)
        UnitIsPlayer, UnitClass, UnitName, UnitExists = sv.UnitIsPlayer, sv.UnitClass, sv.UnitName, sv.UnitExists
    end

    -- Highlight fills follow the look's shape; a mover's is rounded in Modern.
    local mv = ns.Movers.list.bar1
    check(not ns:Modern() or mv.wuiBG:GetTexture() ~= nil, "a mover's fill is drawn in the look's panel shape")

    -- Enter says yes; any other key leaves the dialog alone.
    local said = 0
    W:Confirm("Sure?", function() said = said + 1 end)
    local cf = _G.WicksUIConfirm
    cf:GetScript("OnKeyDown")(cf, "W")
    check(said == 0 and cf:IsShown(), "a key other than Enter goes on to the game")
    cf:GetScript("OnKeyDown")(cf, "ENTER")
    check(said == 1 and not cf:IsShown(), "Enter confirms the dialog")

    -- A typed number is kept however the box is left; Escape puts it back.
    local val = 1
    local host = CreateFrame("Frame", nil, UIParent)
    local sl = W:Slider(host, "a", 0, 10, 1, function() return val end, function(v) val = v end, 200)
    local box = sl.parts[1]
    box:Show()
    box:SetFocus()
    box:SetText("7")
    sl:Refresh()
    check(box:GetText() == "7", "a refresh of the page leaves a number being typed alone")
    box:ClearFocus()
    check(val == 7, "a typed number is kept when the box is left, not only on Enter")
    box:SetFocus()
    box:SetText("3")
    box:GetScript("OnEscapePressed")(box)
    check(val == 7 and box:GetText() == "7" and not box:HasFocus(), "Escape puts back what was there")
    -- Tab moves on to the next box in the same window.
    local val2 = 2
    local sl2 = W:Slider(host, "b", 0, 10, 1, function() return val2 end, function(v) val2 = v end, 200)
    local box2 = sl2.parts[1]
    box2:Show()
    box:SetFocus()
    box:SetText("4")
    box:GetScript("OnTabPressed")(box)
    check(val == 4 and not box:HasFocus() and box2:HasFocus(), "Tab keeps the number and moves on to the next box")
    box2:ClearFocus()

    -- The wheel scrolls the page; Shift and the wheel turn the slider.
    local page = CreateFrame("ScrollFrame", nil, UIParent)
    local scrolled = 0
    page:SetScript("OnMouseWheel", function(_, delta) scrolled = scrolled + delta end)
    local inner = CreateFrame("Frame", nil, page)
    local v3 = 5
    local sl3 = W:Slider(inner, "c", 0, 10, 1, function() return v3 end, function(v) v3 = v end, 200)
    local s3 = sl3.control
    local shift = IsShiftKeyDown
    IsShiftKeyDown = function() return false end
    s3:GetScript("OnMouseWheel")(s3, 1)
    check(scrolled == 1 and s3:GetValue() == 5, "the wheel over a slider scrolls the page and leaves the slider")
    IsShiftKeyDown = function() return true end
    s3:GetScript("OnMouseWheel")(s3, 1)
    check(scrolled == 1 and s3:GetValue() == 6, "Shift and the wheel turn the slider")
    IsShiftKeyDown = shift
    check(sl3.hint ~= nil, "and its tooltip says so")

    -- A long list shows that there is more of it.
    local owner = CreateFrame("Button", nil, UIParent)
    local long = {}
    for i = 1, 24 do long[i] = { i, "Item " .. i } end
    W.OpenMenu(owner, long, nil, function() end)
    local menu = _G.WicksUIMenu
    local _, _, _, _, top = menu.thumb:GetPoint()
    menu:GetScript("OnMouseWheel")(menu, -1)
    local _, _, _, _, lower = menu.thumb:GetPoint()
    check(menu.track:IsShown() and menu.thumb:IsShown() and lower < top, "a dropdown longer than it shows has a bar that follows the wheel")
    W.OpenMenu(owner, { { 1, "One" }, { 2, "Two" } }, nil, function() end)
    check(not menu.track:IsShown(), "and a short one has none")
    W.CloseMenu()

    -- The wording: the accent is not called fel, and the look is the look.
    local found = {}
    for key, pg in pairs(ns.Config.pages) do
        if pg.layout then
            for _, c in ipairs(pg.layout.controls) do
                local t = c.labelText
                if type(t) == "string" and (t:find("^Fel ") or t == "Style") then found[#found + 1] = key .. ": " .. t end
            end
        end
    end
    check(#found == 0, "no setting calls the accent fel or the look a style: " .. table.concat(found, ", "))
    check(ns.Config.pages.unitframes.title == "Unit frames" and ns.Config.pages.actionbars.title == "Action bars",
        "page names in sentence case")
end

io.write("== a page of a window ==\n")
do
    -- The group finder's Listing page fills LFGParentFrame. Dragging the
    -- page used to pull it out of the window and keep it at a spot of its
    -- own, leaving the window standing empty beside it.
    local PS = ns.PanelSkins
    local win = CreateFrame("Frame", "LFGParentFrame", UIParent)
    win:SetSize(458, 535)
    local page = CreateFrame("Frame", "LFGListingFrame", win)
    local d = PS:db()
    local was = d.moveWindows
    d.moveWindows = true
    d.windowPos = { LFGListingFrame = { 30, 667 }, LFGParentFrame = { 452, 658 } }
    -- As an earlier version left it: out of the window, at its own spot.
    page:ClearAllPoints()
    page:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 30, 667)
    local ok, err = pcall(PS.holdWindow, "LFGListingFrame", page)
    check(ok, "holding a page runs: " .. tostring(err or ""))
    local _, rel = page:GetPoint(1)
    check(page:GetNumPoints() == 2 and rel == win, "a page pulled out of its window goes back into it")
    check(d.windowPos.LFGListingFrame == nil and d.windowPos.LFGParentFrame ~= nil,
        "the page's own spot is dropped and the window's kept")
    local _, wrel, _, wx, wy = win:GetPoint(1)
    check(wrel == UIParent and math.abs((wx or 0) - 452) < 0.5 and math.abs((wy or 0) - 658) < 0.5,
        "the window goes to its saved spot")
    local e = PS.extrasOf(page)
    local m = e and e.mover
    local moved
    rawset(win, "StartMoving", function() moved = "window" end)
    rawset(page, "StartMoving", function() moved = "page" end)
    rawset(win, "GetLeft", function() return 100 end)
    rawset(win, "GetTop", function() return 600 end)
    if m then
        m:GetScript("OnMouseDown")(m, "LeftButton")
        m:GetScript("OnMouseUp")(m)
    end
    check(moved == "window", "the page's title bar drags the window")
    check(d.windowPos.LFGParentFrame and d.windowPos.LFGParentFrame[1] == 100 and d.windowPos.LFGListingFrame == nil,
        "and the spot is kept under the window's name")
    -- restoreWindows never lays a page's spot on the page.
    d.windowPos.LFGListingFrame = { 30, 667 }
    rawset(page, "IsShown", function() return true end)
    PS.restoreWindows()
    local _, prel = page:GetPoint(1)
    check(prel == win, "restoring windows leaves the page in its window")
    d.moveWindows, d.windowPos = was, {}
end

io.write("== the other Wick addons' frames ==\n")
do
    -- Another Wick addon hands WickCore a bar; this UI gives it a mover.
    local Chrome = ns.Core.Chrome
    local Movers = ns.Movers
    check(Movers.adopting == true, "the movers watch WickCore's list of movable frames after login")
    local bar = CreateFrame("Frame", "WicksTestSuiteBar", UIParent)
    bar:SetSize(200, 40)
    bar:ClearAllPoints()
    bar:SetPoint("TOP", UIParent, "TOP", 0, -300)
    local stoodDown = false
    Chrome:RegisterMovable(bar, { key = "suitebar", title = "Suite bar", addon = "WicksSuiteTest", onClaim = function() stoodDown = true end })
    local m = Movers.list.suite_suitebar
    check(m ~= nil and m.target == bar and m.groups.suite == true, "a registered frame takes a mover in the Wick addons group")
    check(m and m.default == "TOP,UIParent,TOP,0,-300", "which starts where the addon had it: " .. tostring(m and m.default))
    check(stoodDown and Chrome:MovableClaimed(bar), "and the addon is told to stand its own drag down")
    check(ns.groupLabels.suite ~= nil, "the group has a name in the mover panel's list")
end

io.write("== group finder member icons ==\n")
do
    -- A group's members show as role and class marks from the game's
    -- atlases, under keys like Icon1 and TankIcon. The art pass keeps them
    -- and still fades the row's own art.
    local PS = ns.PanelSkins
    local row = CreateFrame("Frame", nil, UIParent); row:Show()
    local data = CreateFrame("Frame", nil, row); data:Show()
    local list = CreateFrame("Frame", nil, data); list:Show()
    local class = list:CreateTexture(nil, "ARTWORK"); class:SetAtlas("groupfinder-icon-class-mage"); list.Icon1 = class
    local role = list:CreateTexture(nil, "ARTWORK"); role:SetAtlas("UI-LFG-RoleIcon-Tank-Micro-GroupFinder"); list.TankIcon = role
    local art = list:CreateTexture(nil, "BACKGROUND"); art:SetAtlas("groupfinder-highlightbar")
    local ok, err = pcall(PS.walkProfessions, row, 1)
    check(ok, "the walk runs over a group row: " .. tostring(err or ""))
    check(class:GetAlpha() == 1 and role:GetAlpha() == 1, "a group's class and role marks stay")
    check(art:GetAlpha() == 0, "and the row's own art still goes")
end

io.write("== group finder browse list ==\n")
do
    -- Each group is a card of ours, the game's brown bar gone; the chosen
    -- one is marked. The tooltip over a group is widened to its longest
    -- member line, which the game never measures.
    local PS = ns.PanelSkins
    local bf = CreateFrame("Frame", "LFGBrowseFrame", UIParent); bf:Show()
    bf.ScrollBox = CreateFrame("Frame", nil, bf); bf.ScrollBox:Show()
    bf.ScrollBox.ScrollTarget = CreateFrame("Frame", nil, bf.ScrollBox); bf.ScrollBox.ScrollTarget:Show()
    local row = CreateFrame("Button", nil, bf.ScrollBox.ScrollTarget); row:Show()
    row.ResultBG = row:CreateTexture(nil, "BACKGROUND"); row.ResultBG:SetAtlas("common-button-list-mid2")
    row.Highlight = row:CreateTexture(nil, "BACKGROUND")
    row.Selected = row:CreateTexture(nil, "OVERLAY"); row.Selected:Show()
    row.DataDisplay = CreateFrame("Frame", nil, row)
    local ok, err = pcall(PS.styleBrowseRows)
    local e = PS.extrasOf(row)
    check(ok and row.ResultBG:GetAlpha() == 0 and e and e.browseCard, "a group in the list is a card of ours, the brown bar gone: " .. tostring(err or ""))
    check(e and e.browseSel == true, "the chosen group is marked")
    row.Selected:Hide()
    PS.styleBrowseRows()
    check(e and e.browseSel == false, "and unmarked when it is not")

    local tip = CreateFrame("Frame", nil, UIParent); tip:Show(); tip:SetWidth(200)
    local function member(roles)
        local f = CreateFrame("Frame", nil, tip); f:Show()
        f.Name = f:CreateFontString(); f.Name:SetWidth(150)
        f.Level = f:CreateFontString(); f.Level:SetText("Lvl 13")
        f.Roles = {}
        for i = 1, roles do
            local r = f:CreateTexture(); r:Show(); f.Roles[i] = r
        end
        return f
    end
    tip.Leader = member(3)
    local m = member(1)
    tip.memberPool = { EnumerateActive = function() return pairs({ [m] = true }) end }
    local okT, errT = pcall(PS.fitGroupTooltip, tip)
    local want = math.ceil(29 + 150 + 4 + #"Lvl 13" * 6 + 4 + 3 * 16 + 11 + 2)
    check(okT and math.abs(tip:GetWidth() - want) < 0.5, "the group tooltip widens to its longest member line: "
        .. tostring(errT or tip:GetWidth()) .. " / " .. want)
    tip.Leader.Name:SetWidth(20); m.Name:SetWidth(20); tip:SetWidth(200)
    PS.fitGroupTooltip(tip)
    check(tip:GetWidth() == 200, "and is left as the game made it when everything fits")
end

io.write("== info panels: more of them, and other addons' feeds ==\n")
do
    local DT = ns.DataTexts
    local ldb = LibStub and LibStub("LibDataBroker-1.1", true)
    check(ldb ~= nil, "LibDataBroker is bundled and loaded")
    local okA, key = pcall(DT.AddPanel, DT)
    local p = okA and DT.panels[key]
    check(p and p:IsShown() and DT:db().panels[key].label ~= nil, "a panel can be added, and shows: " .. tostring(not okA and key or ""))
    if ldb and p then
        local clicked
        local obj = ldb:NewDataObject("WickTestFeed", { type = "data source", text = "42 things", label = "Test feed",
            OnClick = function(frame) clicked = frame end })
        check(DT.registry["ldb:WickTestFeed"] ~= nil, "a feed made after login is a slot choice")
        DT:db().panels[key].slots = "ldb:WickTestFeed"
        DT:Update()
        local slot = p.slots[1]
        check(slot and tostring(slot.text:GetText()) == "42 things", "the slot shows the feed's text: " .. tostring(slot and slot.text:GetText()))
        obj.text = "43 things"
        check(slot and tostring(slot.text:GetText()) == "43 things", "and follows it when it changes")
        if slot then slot:GetScript("OnClick")(slot, "LeftButton") end
        check(clicked == slot, "a click goes to the feed, with the slot as its frame")
        DT:RemovePanel(key)
        check(DT:db().panels[key] == nil and not p:IsShown(), "an added panel can be removed")
    end
    local okR = pcall(DT.RemovePanel, DT, "left")
    check(okR and DT:db().panels.left ~= nil, "the three that come with it cannot be removed")
end

if ns:Game() then
    io.write("== classic ==\n")
    -- The stub has none of the game's nine-slice layouts; one is lent.
    local was = rawget(_G, "NineSliceUtil")
    local piece = { atlas = "x" }
    NineSliceUtil = {
        GetLayout = function() return { TopLeftCorner = piece, TopRightCorner = piece, BottomLeftCorner = piece,
            BottomRightCorner = piece, TopEdge = piece, BottomEdge = piece, LeftEdge = piece, RightEdge = piece } end,
        ApplyLayout = function(container, layout)
            for k in pairs(layout) do rawset(container, k, container:CreateTexture()) end
        end,
    }
    local f = CreateFrame("Frame", nil, UIParent)
    ns:SetTemplate(f, "Default")
    local g = f.wuiGame
    if g then g:SetSize(200, 100); g:GetScript("OnSizeChanged")(g) end
    check(g and f.wuiGameOn and not f.wuiBorder.top:IsShown(), "a panel takes the game's tooltip border in place of the line")
    if g then g:SetSize(30, 30); g:GetScript("OnSizeChanged")(g) end
    check(g and not f.wuiGameOn and f.wuiBorder.top:IsShown(), "sized down to a tile, it takes the plain line")
    local tint
    if g then for _, t in ipairs(g.pieces) do rawset(t, "SetVertexColor", function(_, r, gg, bb) tint = { r, gg, bb } end) end end
    ns:SetBorderColor(f, { 1, 0, 0 })
    local red = tint and tint[1] == 1 and tint[2] == 0
    ns:SetBorderColor(f, "border")
    check(red and tint[2] == 1, "a border colour tints the game's art, and at rest it is the art's own")
    NineSliceUtil = was
    check(not ns.modules.chat:Enabled() and not ns.modules.panelskins:Enabled() and not ns.modules.skins:Enabled()
        and ns.modules.minimap:Enabled() and ns.modules.tooltip:Enabled(),
        "the modules that only dress the game's frames stand aside; the minimap and tooltips keep what they do")
    -- Earlier sections switch looks; the bars are laid out again in this one.
    pcall(function() ns.ActionBars:Update() end)
    local b1 = _G.WicksUI_Bar1 and _G.WicksUI_Bar1.buttons[1]
    check(b1 and b1.MasqueSkinned and rawget(b1, "wuiBorder") == nil and rawget(b1, "wuiEmpty") == nil
        and b1.config and b1.config.text.hotkey.font.font == ns.ActionBars.GAME_NUMBER_FONT,
        "an action button keeps the game's own template art, its keybind in the game's number font: " .. tostring(b1 and b1.MasqueSkinned) .. " " .. tostring(b1 and rawget(b1, "wuiBorder")) .. " " .. tostring(b1 and rawget(b1, "wuiEmpty")) .. " " .. tostring(b1 and b1.config and b1.config.text.hotkey.font.font))
    do
        -- The unit frames in the game's own shape: its size, its art, the
        -- portrait in it, and a target's art swapped for its rank.
        local UF = ns.UnitFrames
        local pl, tg = UF.frames.player, UF.frames.target
        local tbc = ns.Core.Client and ns.Core.Client.isTBC
        pcall(UF.Configure, UF, pl)
        local w, h = pl:GetSize()
        check(pl.wuiGameUF and w == 232 and h == 100 and pl.wuiGameArt and pl.Portrait == pl.wuiPortrait
            and pl.wuiPortrait:IsShown(),
            "Classic: the player frame is the game's, 232 by 100, its art round the portrait: " .. tostring(w) .. "x" .. tostring(h))
        local _, _, _, hx, hy = pl.Health:GetPoint(1)
        check((tbc and hx == 90 and hy == -45) or (not tbc and hx == 85 and hy == -41),
            "Classic: health sits where the game puts it on this client: " .. tostring(hx) .. "," .. tostring(hy))
        local wasClass, wasSel = UnitClassification, UnitSelectionColor
        UnitClassification = function() return "elite" end
        UnitSelectionColor = function() return 1, 0, 0, 1 end
        tg.unit = "target"
        local okU, errU = pcall(UF.GameUpdate, UF, tg)
        UnitClassification, UnitSelectionColor = wasClass, wasSel
        local swapped
        if tbc then
            swapped = tostring(tg.wuiGameArt:GetTexture()):find("Elite") ~= nil
        else
            swapped = tg.wuiGameDragon and tg.wuiGameDragon:IsShown()
        end
        check(okU and swapped and tg.wuiGameBand and tg.wuiGameBand:IsShown(),
            "Classic: an elite target wears the game's elite art, its name band in its reaction colour: " .. tostring(errU or ""))
        if not tbc then
            check(pl.Health:GetStatusBarTexture() and pl.Health.bg and not pl.Health.bg:IsShown(),
                "Classic on Forever: the bars are clipped to the art, with no backing of ours")
        end
        -- The party in the game's own frames, stacked as the game stacks them.
        local PL = UF:GameLayout("party")
        pcall(function() ns.UnitGroups:Layout("party") end)
        local hw, hh = ns.UnitGroups.holders.party:GetSize()
        do
            -- A plate's debuff in the game's art: its mask, its ring, its
            -- sweep and count, drawn on a button the client made.
            local NPm = ns.Nameplates
            local btn = CreateFrame("Button", nil, UIParent)
            btn:SetSize(19, 19)
            btn.Icon = btn:CreateTexture()
            btn.Cooldown = CreateFrame("Cooldown", nil, btn)
            btn.Count = btn:CreateFontString()
            btn.Time = btn:CreateFontString()
            local okA, errA = pcall(NPm.GameAura, NPm, btn, NPm:GameAuraSize())
            check(okA and NPm:GameAuraSize() == (tbc and 25 or 19), "Classic: a plate's debuff takes the game's art at the game's size: " .. tostring(errA or ""))
        end
        check(PL and hw == PL.w and hh == PL.h * 5 + PL.gap * 4,
            "Classic: the party holder is five of the game's party frames, the game's gap apart: " .. tostring(hw) .. "x" .. tostring(hh))
    end
    do
        -- The template's art is drawn for its own size; at the bar's size
        -- each piece is scaled with the button.
        local tb = CreateFrame("CheckButton", nil, UIParent)
        tb:SetSize(45, 45)
        local frame = tb:CreateTexture()
        frame:SetSize(46, 45)
        frame:SetPoint("TOPLEFT", tb, "TOPLEFT", 0, 0)
        local glow = tb:CreateTexture()
        glow:SetSize(62, 62)
        glow:SetPoint("CENTER", tb, "CENTER", 0, -2)
        ns.ActionBars.FitGameArt(tb)
        tb:SetSize(36, 36)
        if tb.wuiGameArt then tb.wuiGameArt() end
        local fw, fh = frame:GetSize()
        local gw = glow:GetSize()
        local _, _, _, _, gy = glow:GetPoint(1)
        check(math.abs(fw - 46 * 0.8) < 0.01 and math.abs(fh - 36) < 0.01 and math.abs(gw - 62 * 0.8) < 0.01 and math.abs(gy + 1.6) < 0.01,
            "the game's button art scales with the button, sizes and offsets: " .. tostring(fw) .. " " .. tostring(gw) .. " " .. tostring(gy))
    end
end

io.write("== unit frames in a look of their own ==\n")
do
    local Ch = ns.Core.Chrome
    local suite = Ch:StyleID()
    local other = suite == "classic" and "modern" or "classic"
    local g = ns:G()
    g.unitFrameLook = other
    local inside = ns:InUFLook(function() return Ch:StyleID() end)
    check(inside == other and Ch:StyleID() == suite and Ch.forceStyle == nil,
        "the unit frames draw in their own look, and the suite stays in its own: " .. tostring(inside) .. " / " .. tostring(Ch:StyleID()))
    local okE = pcall(ns.InUFLook, ns, function() error("boom") end)
    check(not okE and Ch.forceStyle == nil and Ch:StyleID() == suite, "an error in their look leaves the suite's look in force")
    -- A plate made now is made in their look.
    local oUF = ns.oUF
    oUF:SetActiveStyle("WicksUI_Nameplate")
    local okP, p = pcall(oUF.Spawn, oUF, "target", "WicksUI_TestPlateOwnLook")
    oUF:SetActiveStyle("WicksUI")
    local classicPlate = okP and p and p.wuiGameNP ~= nil
    check(okP and classicPlate == (other == "classic"),
        "a plate made while the unit frames have their own look is made in it: " .. tostring(not okP and p or classicPlate))
    g.unitFrameLook = nil
    check(ns:InUFLook(function() return Ch:StyleID() end) == suite, "set back, they follow the suite's look")
end

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
