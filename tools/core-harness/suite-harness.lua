-- The TBC addons on WickCore. Loads WickCore, then each adopter from the
-- TBC Anniversary AddOns folder under the TBC-shaped stub, and checks what
-- adoption promises: the addon loads, is listed with its TOC version, has
-- a page under Wick's Mods and a line in the launcher, registers its
-- draggable frames with Chrome and stands its own drag down when they are
-- claimed, and repaints when the theme changes.
--   args: coreDir, addonsDir, mode, stubPath
local CORE_DIR, ADDONS_DIR, MODE, STUB = ...
local S = assert(loadfile(STUB))(MODE)

local passes, fails = 0, 0
local function check(cond, label)
    if cond then passes = passes + 1; io.write("  ok    ", label, "\n")
    else fails = fails + 1; io.write("  FAIL  ", label, "\n") end
end

-- Chat lines the addons print, kept to read back.
local said = {}
local realPrint = print
local function quiet()
    print = function(...)
        local t = {}
        for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
        said[#said + 1] = table.concat(t, " ")
    end
end
-- WickCore prints through DEFAULT_CHAT_FRAME, which the stub keeps in
-- S.CHAT; colour codes are stripped so a needle reads as the player does.
local function plain(s) return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local chatMark = 0
local function saidAbout(needle)
    for _, s in ipairs(said) do if plain(s):find(needle, 1, true) then return true end end
    for i = chatMark + 1, #S.CHAT do if plain(S.CHAT[i]):find(needle, 1, true) then return true end end
    return false
end
local function clearSaid() said = {}; chatMark = #S.CHAT end
quiet()

-- The stub answers nil for every API it does not model; the addons call
-- a few at load that must exist for the files to run at all.
local function noop() end
local function stubGlobal(name, v) if rawget(_G, name) == nil then rawset(_G, name, v) end end
-- The shared stub has a class of its own; the warlock kit only builds
-- its bars for a warlock, so the answer is forced here.
rawset(_G, "UnitClass", function() return "Warlock", "WARLOCK" end)
stubGlobal("GetBindingKey", function() return nil end)
stubGlobal("SetBindingClick", function() return true end)
stubGlobal("GetQuestLogSpecialItemInfo", function() return nil end)
stubGlobal("GetNumQuestLogEntries", function() return 0, 0 end)
stubGlobal("GetQuestLogTitle", function() return nil end)
stubGlobal("GetItemCount", function() return 0 end)
stubGlobal("GetInventoryItemID", function() return nil end)
stubGlobal("GetSpellInfo", function() return nil end)
stubGlobal("IsSpellKnown", function() return false end)
stubGlobal("IsUsableItem", function() return false end)
stubGlobal("GetItemCooldown", function() return 0, 0 end)
stubGlobal("GetItemSpell", function() return nil end)
stubGlobal("UnitBuff", function() return nil end)
stubGlobal("UnitLevel", function() return 70 end)
stubGlobal("GetTalentTabInfo", function() return nil end)
stubGlobal("GetNumTalentTabs", function() return 3 end)
stubGlobal("GetNumTalents", function() return 0 end)
stubGlobal("GetTalentInfo", function() return nil end)
stubGlobal("IsShiftKeyDown", function() return false end)
stubGlobal("InCombatLockdown", function() return false end)
stubGlobal("GetMacroInfo", function() return nil end)
stubGlobal("GetNumMacros", function() return 0, 0 end)
stubGlobal("GetSpellTexture", function() return 136116 end)
stubGlobal("HasPetUI", function() return false end)
stubGlobal("GetPetActionInfo", function() return nil end)
stubGlobal("UnitExists", function() return false end)
stubGlobal("UnitCreatureFamily", function() return nil end)
stubGlobal("GetSpellCooldown", function() return 0, 0, 1 end)
stubGlobal("GetTime", function() return 0 end)
stubGlobal("C_Container", { GetContainerNumSlots = function() return 0 end, GetContainerItemInfo = function() return nil end,
    GetContainerItemID = function() return nil end, GetContainerItemCooldown = function() return 0, 0 end,
    GetContainerItemLink = function() return nil end, GetItemCooldown = function() return 0, 0 end })
stubGlobal("GetContainerNumSlots", function() return 0 end)
stubGlobal("GetContainerItemInfo", function() return nil end)
stubGlobal("GetContainerItemID", function() return nil end)
stubGlobal("GetContainerItemCooldown", function() return 0, 0 end)
stubGlobal("CooldownFrame_Set", noop)
stubGlobal("GameTooltip_Hide", noop)
stubGlobal("GetInventorySlotInfo", function() return 16 end)
stubGlobal("GetInventoryItemLink", function() return nil end)
stubGlobal("GetInventoryItemTexture", function() return nil end)
stubGlobal("UnitAffectingCombat", function() return false end)
stubGlobal("GetShapeshiftForm", function() return 0 end)
stubGlobal("GetMoney", function() return 123456 end)
stubGlobal("IsInInstance", function() return false, "none" end)
stubGlobal("GetRealZoneText", function() return "Shattrath City" end)
stubGlobal("GetZoneText", function() return "Shattrath City" end)
stubGlobal("UnitXP", function() return 0 end)
stubGlobal("UnitXPMax", function() return 1 end)
stubGlobal("GetNumFactions", function() return 0 end)
stubGlobal("GetFactionInfo", function() return nil end)
stubGlobal("GetCursorPosition", function() return 0, 0 end)
stubGlobal("GetNumBankSlots", function() return 0, false end)
stubGlobal("GetBagName", function() return nil end)
stubGlobal("GetInventoryItemQuality", function() return nil end)
stubGlobal("date", os.date)
stubGlobal("time", os.time)

io.write("== load WickCore (", MODE, ") ==\n")
S.loadAddon(CORE_DIR, "WickCore")
S.fire("ADDON_LOADED", "WickCore")
local Core = WickCore
local Chrome = Core.Chrome
check(type(Chrome.RegisterMovable) == "function", "WickCore has the movable registry")
check(type(Core.Options.Register) == "function" and type(Core.Launcher.Register) == "function", "and the options and launcher registries")

local ADOPTERS = {
    { folder = "WicksQuestKey",        title = "Wick's Quest Key" },
    { folder = "WicksConcessionStand", title = "Wick's Concession Stand" },
    { folder = "WicksDemonsAndThings", title = "Wick's Demons and Things" },
    { folder = "WicksLedger",          title = "Wick's Ledger" },
    { folder = "WicksBags",            title = "Wick's Bags" },
}

-- Saved variables as a player who has used each addon would have them.
WicksQuestKeyDB = { point = "BOTTOM", relativePoint = "BOTTOM", x = 0, y = 180 }
WicksCSDB = { point = "RIGHT", relativePoint = "RIGHT", x = -40, y = 100, trayPoint = "RIGHT", trayRelPoint = "RIGHT", trayX = -40, trayY = 60,
    extrasPoint = "RIGHT", extrasRelPoint = "RIGHT", extrasX = -40, extrasY = 20, locked = true }
WicksDemonsDB, WicksDemonsCharDB = nil, nil
WicksLedgerDB, WicksLedgerCharDB = nil, nil
WicksBagsDB, WicksBagsAlts, WicksBagsCharDB = nil, nil, nil

io.write("== load the adopters ==\n")
local loaded = {}
for _, a in ipairs(ADOPTERS) do
    local ok, err = pcall(S.loadAddon, ADDONS_DIR .. "/" .. a.folder, a.folder)
    check(ok, a.folder .. " loads: " .. tostring(err or ""))
    loaded[a.folder] = ok
    if ok then
        local okL, errL = pcall(S.fire, "ADDON_LOADED", a.folder)
        check(okL, a.folder .. " takes ADDON_LOADED: " .. tostring(errL or ""))
    end
end
check(rawget(_G, "WicksNeedCore") == nil, "no adopter thought WickCore was missing")

io.write("== login ==\n")
local okLogin, errLogin = pcall(S.fire, "PLAYER_LOGIN")
check(okLogin, "PLAYER_LOGIN runs for the lot: " .. tostring(errLogin or ""))
local okWorld, errWorld = pcall(S.fire, "PLAYER_ENTERING_WORLD")
check(okWorld, "PLAYER_ENTERING_WORLD runs for the lot: " .. tostring(errWorld or ""))

io.write("== listed, with a page and a launcher line ==\n")
for _, a in ipairs(ADOPTERS) do
    if loaded[a.folder] then
        local A = Core.addons[a.folder]
        check(A ~= nil and A.title == a.title, a.folder .. " is a WickCore addon titled " .. a.title)
        check(A and type(A.version) == "string" and A.version:match("^%d+%.%d+"), a.folder .. " carries its TOC version: " .. tostring(A and A.version))
        check(A and A.db == nil, a.folder .. " keeps its own saved variables (no WickCore db)")
        check(A and A.enabled, a.folder .. " enabled at login")
        check(Core.Options.pages[a.folder] ~= nil, a.folder .. " has a page under Wick's Mods")
        check(Core.Launcher.entries[a.folder] ~= nil, a.folder .. " has a line in the launcher")
    end
end

-- Open what builds lazily, so there is chrome to look at.
io.write("== windows build ==\n")
if loaded.WicksLedger and WicksLedger.UI then
    local okT, errT = pcall(WicksLedger.UI.Toggle, WicksLedger.UI)
    check(okT, "the ledger opens: " .. tostring(errT or ""))
end
if loaded.WicksBags and WicksBags.Bag then
    local okT, errT = pcall(WicksBags.Bag.Toggle, WicksBags.Bag)
    check(okT, "the bags open: " .. tostring(errT or ""))
end
if loaded.WicksDemonsAndThings and WicksDemons.UI then
    local okT, errT = pcall(WicksDemons.UI.Toggle, WicksDemons.UI)
    check(okT, "the warlock panel opens: " .. tostring(errT or ""))
end

-- A frame's background region: the first BACKGROUND texture painted on
-- it, or on one of its children (the Ledger keeps its backgrounds on a
-- child frame).
local function bgOf(frame)
    if not frame then return nil end
    for _, r in ipairs({ frame:GetRegions() }) do
        if r.__layer == "BACKGROUND" and r.__color then return r end
    end
    for _, c in ipairs({ frame:GetChildren() }) do
        local r = bgOf(c)
        if r then return r end
    end
    return nil
end
local function near(a, b) return a and b and math.abs(a - b) < 0.002 end

io.write("== the theme repaints them ==\n")
local SAMPLES = {
    { "WicksQuestKey", "WicksQuestKeyButton" },
    { "WicksConcessionStand", "WicksCSQuickPanel" },
    { "WicksDemonsAndThings", "WicksDemonsShardCounter", "WicksDemonsSoulBar", "WicksDemonsOptionsFrame" },
    { "WicksLedger", "WicksLedgerBar", "WicksLedgerPanel" },
    { "WicksBags", "WicksBagsPanel" },
}
local regions = {}
for _, s in ipairs(SAMPLES) do
    if loaded[s[1]] then
        local frame, name
        for i = 2, #s do
            frame = rawget(_G, s[i])
            if frame then name = s[i] break end
        end
        local r = frame and bgOf(frame)
        check(r ~= nil, s[1] .. ": a background painted through Chrome on " .. tostring(name or s[2]))
        if r then regions[s[1]] = r end
    end
end
local was = Chrome.activeTheme or "fel"
local before = { Chrome.Colors.voidBG[1], Chrome.Colors.voidBG[2], Chrome.Colors.voidBG[3] }
Chrome:ApplyTheme("hologram")
local v = Chrome.Colors.voidBG
check(not (near(before[1], v[1]) and near(before[2], v[2]) and near(before[3], v[3])), "the Hologram theme has another background colour")
for _, s in ipairs(SAMPLES) do
    local r = regions[s[1]]
    if r then
        check(near(r.__color[1], v[1]) and near(r.__color[2], v[2]) and near(r.__color[3], v[3]),
            s[1] .. "'s background follows the theme")
    end
end
Chrome:ApplyTheme(was)

io.write("== movable frames ==\n")
if loaded.WicksQuestKey then
    local e = Chrome.movables.list.questkey
    check(e and e.frame == rawget(_G, "WicksQuestKeyButton"), "Quest Key registers its button at login")
    check(e and e.default == "BOTTOM,UIParent,BOTTOM,0,180", "starting where its settings had it: " .. tostring(e and e.default))
    Chrome:ClaimMovable("questkey")
    clearSaid()
    SlashCmdList.WICKSQUESTKEY("unlock")
    check(saidAbout("/wui move"), "/wqk unlock points at /wui move once claimed")
    clearSaid()
    SlashCmdList.WICKSQUESTKEY("reset")
    check(saidAbout("/wui move") and WicksQuestKeyDB.y == 180, "/wqk reset leaves the place to Wick's UI")
end
if loaded.WicksConcessionStand then
    local q = Chrome.movables.list.concession_quick
    check(q and q.frame == rawget(_G, "WicksCSQuickPanel") and Chrome.movables.list.concession_tray and Chrome.movables.list.concession_extras,
        "the stand registers its three bars when it builds")
    check(q and q.default == "RIGHT,UIParent,RIGHT,-40,100", "each starting where its settings had it: " .. tostring(q and q.default))
    for _, k in ipairs({ "concession_quick", "concession_tray", "concession_extras" }) do Chrome:ClaimMovable(k) end
    clearSaid()
    SlashCmdList.WICKSCS("unlock")
    check(saidAbout("/wui move"), "/wcs unlock points at /wui move once claimed")
    local okE, errE = pcall(S.fire, "PLAYER_ENTERING_WORLD")
    check(okE, "entering the world runs with the bars claimed: " .. tostring(errE or ""))
end
if loaded.WicksDemonsAndThings then
    local keys = { "demons_cooldowns", "demons_pets", "demons_soul", "demons_shards" }
    local have = {}
    for _, k in ipairs(keys) do if Chrome.movables.list[k] then have[#have + 1] = k end end
    check(#have > 0, "the warlock bars register as they build: " .. table.concat(have, ", "))
    for _, k in ipairs(have) do Chrome:ClaimMovable(k) end
    clearSaid()
    SlashCmdList.WICKSDEMONS("unlock")
    check(#have == 0 or saidAbout("/wui move"), "/wdt unlock points at /wui move once claimed")
    clearSaid()
    SlashCmdList.WICKSDEMONS("reset")
    check(#have == 0 or saidAbout("/wui move"), "/wdt reset leaves a claimed bar to Wick's UI")
end

io.write("== chat lines ==\n")
if loaded.WicksQuestKey then
    clearSaid()
    SlashCmdList.WICKSQUESTKEY("lock")
    check(saidAbout("Wick's Quest Key: locked."), "Quest Key speaks through WickCore: " .. tostring(said[1]))
end
if loaded.WicksDemonsAndThings then
    clearSaid()
    SlashCmdList.WICKSDEMONS("lock")
    check(saidAbout("Wick's Demons and Things: bars locked."), "Demons and Things speaks through WickCore: " .. tostring(said[1]))
end
if loaded.WicksBags then
    clearSaid()
    SlashCmdList.WICKSBAGS("nonsense")
    check(saidAbout("Wick's Bags: unknown command"), "Bags speaks through WickCore: " .. tostring(said[1]))
end

print = realPrint
local missing = S.missingReport()
io.write("\nAPI the stub answered with nil: ", table.concat(missing, ", "), "\n")
io.write(("\n%s: %d passed, %d failed\n"):format(MODE, passes, fails))
if fails > 0 then error(("%d check(s) failed"):format(fails), 0) end
print("PASS")
