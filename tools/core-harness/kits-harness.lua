-- Offline load test for the Forever class kits on WickCore.
--   args: coreDir, addonsDir, mode, stubPath
-- Loads WickCore, then each kit as the matching class, and drives the kit
-- panel, checklist, talents, racials and the kit-specific bars.

local CORE_DIR, ADDONS_DIR, MODE, STUB = ...
local S = assert(loadfile(STUB))(MODE)
local MODERN = S.modern

local passes, fails = 0, 0
local function check(cond, label)
    if cond then passes = passes + 1; io.write("  ok    ", label, "\n")
    else fails = fails + 1; io.write("  FAIL  ", label, "\n") end
end
local function dumpErrors()
    for _, l in ipairs(S.CHAT) do if l:lower():find("error") then io.write("  chat: ", (l:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")), "\n") end end
    S.CHAT = {}
end
local function try(label, fn)
    local ok, err = pcall(fn)
    check(ok, label .. (ok and "" or (": " .. tostring(err))))
    return ok
end


io.write("== load WickCore (", MODE, ") ==\n")
S.loadAddon(CORE_DIR, "WickCore")   -- file list straight off WickCore.toc
S.fire("ADDON_LOADED", "WickCore")
check(WickCore.Kit and WickCore.Talents and WickCore.Checklist and WickCore.Racials, "kit layer present")

-- ---------- shared kit layer -------------------------------------------
io.write("== kit layer ==\n")
local T = WickCore.Talents
check(T:IsAvailable() == MODERN, "talents availability matches client")
if MODERN then
    local str = T:Export()
    check(type(str) == "string" and #str > 0, "Talents:Export returns a string")
    local ok, why = T:Import(str, "Harness")
    check(ok == true, "Talents:Import through Blizzard parser " .. tostring(why or ""))
    local s = T:Summary()
    check(s and s.name == "Loadout A" and #s.spent == 3, "Talents:Summary reads config + tree currencies")
else
    local str, why = T:Export()
    check(str == nil and why, "Talents:Export declines on legacy")
end

local Rc = WickCore.Racials
local data, token = Rc:ForPlayer()
check(data ~= nil and token == "Orc", "racial data for player race")
check(#Rc:KnownActives() == 2, "racial actives resolve to spells")

-- ---------- Totems and Things -------------------------------------------
io.write("== Totems and Things ==\n")
CLASS = "SHAMAN"
S.loadAddon(ADDONS_DIR .. "/WicksTotemsAndThings", "WicksTotemsAndThings", { "Core.lua", "Totems.lua", "TotemBar.lua", "UI.lua" })
S.fire("ADDON_LOADED", "WicksTotemsAndThings")
S.fire("PLAYER_LOGIN")
dumpErrors()
local WT = WicksTotems
check(WT.A.initialized and WT.A.enabled, "totems initialized + enabled")
check(WicksTotemsDB == WT.A.db.profile and WicksTotemsCharDB == WT.A.db.char, "legacy globals alias the profile/char tables")
check(WicksTotemsSaved and WicksTotemsSaved.profiles, "saved variable carries the profile structure")
check(WT.A.kit ~= nil, "kit attached")
check(#WicksTotemsCharDB.presets == 2 and WicksTotemsCharDB.presets[1].totems.fire == "Searing Totem", "default presets seeded")
check(WT.TotemBar.host ~= nil and WT.TotemBar.callElements ~= nil, "totem bar built with Call of the Elements button")
local m = WT.TotemBar.btn_fire:GetAttribute("macrotext1")
check(m and m:find("/cast Searing Totem"), "element button macro: " .. tostring(m))
if MODERN then
    check(S.MULTICAST[1] == 133 or S.MULTICAST[1] ~= nil, "preset pushed into multicast slots on rebuild")
    local ok, why = WT.TotemBar:ApplyToTotemBar()
    check(ok == true, "ApplyToTotemBar " .. tostring(why))
else
    local ok, why = WT.TotemBar:ApplyToTotemBar()
    check(ok == false, "ApplyToTotemBar declines without a totem bar")
end
local active = WT:ActiveTotems()
check(active[1] and active[1].name == "Strength of Earth Totem", "ActiveTotems reads slot 1 at rest")
COMBAT = true
active = WT:ActiveTotems()
if MODERN then check(next(active) == nil and WT.totemsRestricted, "ActiveTotems empty + restricted flag in combat")
else check(active[1] ~= nil, "ActiveTotems still reads in combat on legacy") end
COMBAT = false
try("totems UI Build + Show", function() WT.UI:Build(); WT.UI:Show() end)
try("totems UI options tab", function() WT.UI:SelectTab("options") end)
try("totems UI active tab", function() WT.UI:SelectTab("active") end)
try("totems kit toggle", function() WT.A.kit:Toggle() end)
check(WT.A.kit.panel and WT.A.kit.panel:IsShown(), "kit panel shown")
try("kit checklist tab", function() WT.A.kit:Select("checklist") end)
local rows = WT.A.kit.checklist:Evaluate()
check(#rows == 5, "checklist evaluates 5 rows")
check(rows[1].state == "ok", "shield row ok at rest (Lightning Shield present): " .. tostring(rows[1].state))
check(rows[4].state == "missing" and rows[4].detail == "0", "ankh row missing with count")
check(rows[5].state == "ok", "totems ready row ok")
COMBAT = true
rows = WT.A.kit.checklist:Evaluate()
if MODERN then check(rows[1].state == "unknown", "shield row unknown in combat") end
COMBAT = false
try("kit racials tab", function() WT.A.kit:Select("racials") end)
try("kit talents tab", function() WT.A.kit:Select("talents") end)
S.CHAT = {}
SlashCmdList.WICK_WICKSTOTEMSANDTHINGS("status")
check(#S.CHAT >= 3, "/wtt status prints")
SlashCmdList.WICK_WICKSTOTEMSANDTHINGS("twist air on")
check(WicksTotemsCharDB.twist.air and WicksTotemsCharDB.twist.air.enabled, "/wtt twist air on")
check(WT.TotemBar.btn_air:GetAttribute("macrotext1"):find("/castsequence"), "twist macro rebuilt")

-- ---------- Demons and Things --------------------------------------------
io.write("== Demons and Things ==\n")
CLASS = "WARLOCK"
S.loadAddon(ADDONS_DIR .. "/WicksDemonsAndThings", "WicksDemonsAndThings", { "Core.lua", "SoulBar.lua", "PetBar.lua", "ShardCounter.lua", "UI.lua" })
S.fire("ADDON_LOADED", "WicksDemonsAndThings")
S.fire("PLAYER_LOGIN")
dumpErrors()
local WD = WicksDemons
check(WD.A.initialized and WD.A.enabled, "demons initialized + enabled")
check(WicksDemonsDB == WD.A.db.profile, "demons legacy global aliases profile")
check(WD.isWarlock, "class detection")
check(WD.Cooldowns == nil, "cooldown tracker not loaded")
check(WD.ShardCounter and WD.ShardCounter.frame, "shard counter built")
check(WD.ShardCounter:Count() == 1, "shard count from bags")
try("pet bar refresh at rest", function() if WD.PetBar.Refresh then WD.PetBar:Refresh() end end)
try("soul bar refresh at rest", function() if WD.SoulBar.Refresh then WD.SoulBar:Refresh() end end)
COMBAT = true
try("pet bar refresh in combat (secret cooldowns)", function() if WD.PetBar.Refresh then WD.PetBar:Refresh() end end)
try("soul bar refresh in combat", function() if WD.SoulBar.Refresh then WD.SoulBar:Refresh() end end)
COMBAT = false
try("demons UI build + toggle", function() WD.UI:Build(); WD.UI:Toggle() end)
try("demons kit", function() WD.A.kit:Toggle(); WD.A.kit:Select("checklist") end)
local drows = WD.A.kit.checklist:Evaluate()
check(#drows == 6, "demons checklist 6 rows")
check(drows[6].state == "ok", "demon out (pet exists)")
S.CHAT = {}
SlashCmdList.WICK_WICKSDEMONSANDTHINGS("status")
check(#S.CHAT >= 3, "/wdt status prints")

-- ---------- Forms and Things ---------------------------------------------
io.write("== Forms and Things ==\n")
CLASS = "DRUID"
S.loadAddon(ADDONS_DIR .. "/WicksFormsAndThings", "WicksFormsAndThings", { "Core.lua", "TravelForm.lua", "TravelFormUI.lua" })
S.fire("ADDON_LOADED", "WicksFormsAndThings")
S.fire("PLAYER_LOGIN")
dumpErrors()
local F = WICKSTRAVELFORM
check(F.A.initialized and F.A.enabled, "forms initialized + enabled")
check(WicksTravelFormDB == F.A.db.profile, "forms legacy global aliases profile")
check(F.isDruid, "class detection")
local macro = F.buildMacro()
check(macro:find("%[swimming%] Aquatic Form") and macro:find("%[outdoors%] Travel Form") and macro:find("Cat Form"), "macro built: " .. macro)
check(not macro:find("Flight"), "no flight clause in a non-flyable zone")
if MODERN then check(F.bestFlightForm() == nil, "no flight form on Forever")
else check(F.bestFlightForm() == "Flight Form", "flight form found via spellbook on legacy") end
check(F.predictForm() == "Travel Form", "predicted form outdoors: " .. tostring(F.predictForm()))

-- The resource bars have to answer to a theme. Chrome remembers a
-- region by the identity of the colour table it was painted with, so a
-- file holding its own copies of the palette registers nothing and
-- repaints never. That is exactly what happened here: one bar stayed
-- blue on a green UI because its colour was a hardcoded mana blue that
-- no theme could reach.
do
    local Chrome = WickCore.Chrome
    local host = _G.WicksTravelFormBarHost
    check(host ~= nil and host.priTrack ~= nil and host.manaTrack ~= nil,
        "the bar host has both tracks")
    if host and host.priTrack then
        local fill = host.priTrack.__statusTex
        check(fill ~= nil, "the primary bar has a fill texture")
        if fill then
            -- Blue is more than half of what makes a bar read as mana,
            -- so the test is the channel that carries the meaning.
            local function bluest(t) return t and t.__color and t.__color[3] > t.__color[1] end
            local function reddest(t) return t and t.__color and t.__color[1] > t.__color[3] end
            local function yellowish(t)
                local c = t and t.__color
                return c and c[1] > 0.6 and c[2] > 0.6 and c[3] < 0.5
            end

            -- Out of form, the top bar is mana. The host has to be up
            -- for a redraw to reach it.
            host:Show()
            S.STANCE = 0
            F.UpdateResourceBar()
            check(bluest(fill), "out of form the top bar is mana blue")

            -- A theme must not touch it. This used to assert the
            -- opposite: both bars were palette tokens, which on a druid
            -- made the top bar orange for rage and orange for the theme
            -- with no way to tell which.
            local before = table.concat(fill.__color, ",")
            Chrome:SetTheme("shaman")
            check(table.concat(fill.__color, ",") == before,
                "and a theme leaves it alone: mana is blue under every one")
            Chrome:SetTheme("fel")

            -- And the colour says which resource it is.
            S.POWER_TYPE = 1
            F.UpdateResourceBar()
            check(reddest(fill), "rage reads red")
            S.POWER_TYPE = 3
            F.UpdateResourceBar()
            check(yellowish(fill), "energy reads yellow")
            S.POWER_TYPE = 0
            F.UpdateResourceBar()

            local mana = host.manaTrack.__statusTex
            check(bluest(mana), "and the bar underneath is always mana blue")
        end
    end
end
-- A fresh druid knows no forms at all: the key must offer nothing rather
-- than cast spells they do not have.
do
    S.ALL_UNKNOWN = true
    check(F.buildMacro() == "", "no forms learned yet: the macro is empty")
    check(F.predictForm() == nil, "no forms learned yet: nothing predicted")
    -- The button and its tooltip have to survive having nothing to predict.
    local okIcon = pcall(function() F.UI:Refresh() end)
    check(okIcon, "button refreshes with no forms learned")
    check(_G.WicksTravelFormHost and not _G.WicksTravelFormHost:IsShown(),
        "button hides itself while no form is known")
    local btn = _G.WicksTravelFormButton
    local okTip = btn and pcall(btn.__scripts.OnEnter, btn)
    check(okTip, "button tooltip survives having nothing to predict")
    S.ALL_UNKNOWN = false
    F.UI:Refresh()   -- put the real macro back on the button
    check(_G.WicksTravelFormHost and _G.WicksTravelFormHost:IsShown(),
        "button comes back once a form is learned")
    check(F.buildMacro() ~= "", "macro returns once the forms are known again")
end
local btn = _G.WicksTravelFormButton
check(btn and btn:GetAttribute("macrotext1") == macro, "secure button carries the macro")
try("resource bar draw at rest", function() F.UpdateResourceBar() end)
COMBAT = true
try("resource bar draw in combat (secret power)", function() F.UpdateResourceBar() end)
COMBAT = false
try("forms kit", function() F.A.kit:Toggle(); F.A.kit:Select("checklist") end)
local frows = F.A.kit.checklist:Evaluate()
check(#frows == 4, "forms checklist 4 rows")
check(frows[4].state == "ok", "rebirth ready at rest: " .. tostring(frows[4].state))
S.CHAT = {}
SlashCmdList.WICK_WICKSFORMSANDTHINGS("debug")
check(#S.CHAT >= 3, "/wft debug prints")

io.write("== Beasts and Things ==\n")
CLASS = "HUNTER"
S.PET_FAMILY = "Wolf"
S.PET_SPELLS = {
    { "Bite", "active", 132127, 17253 },
    { "Growl", "active", 132270, 2649 },
    { "Furious Howl", "active", 136168, 24604 },
    { "Avoidance", "passive", 132279, 24672 },
}
local BNS = S.loadAddon(ADDONS_DIR .. "/WicksBeastsAndThings", "WicksBeastsAndThings", { "Core.lua", "Pet.lua", "Ammo.lua", "Beasts.lua", "UI.lua" })
S.fire("ADDON_LOADED", "WicksBeastsAndThings")
S.fire("PLAYER_LOGIN")
dumpErrors()
local bns
for _, f in ipairs(S.frames) do if f.__name == "WicksBeastsEvents" then bns = true end end
check(bns, "beasts event frame created")
local kb = _G.WicksBeastsFeedButton
check(kb ~= nil, "feed keybind button exists")
S.CHAT = {}
SlashCmdList.WICK_WICKSBEASTSANDTHINGS("status")
check(#S.CHAT >= 3, "/wbt status prints")
local statusLine = table.concat(S.CHAT, " | ")
check(statusLine:find("happiness 2") ~= nil, "pet happiness read: " .. statusLine:sub(1, 120))
if MODERN then
    local mt = tostring(kb:GetAttribute("macrotext"))
    check(mt:find("/cast Feed Pet") and mt:find("/use item:6948"), "feed macro built from CanPetEatItem: " .. mt)
    check(statusLine:find("count 150") ~= nil, "ammo equipped count read")
else
    check(kb:GetAttribute("macrotext") == "", "no feed macro without CanPetEatItem on legacy")
end
local strip = _G.WicksBeastsStrip
check(strip ~= nil and strip:IsShown(), "compact strip built and shown for a hunter")
check(strip and strip.feed and strip.feed:GetAttribute("type") == "macro", "strip feed button is a secure macro button")
try("strip refresh", function() local U = strip and strip.__scripts.OnShow; if U then U(strip) end end)
S.CHAT = {}
SlashCmdList.WICK_WICKSBEASTSANDTHINGS("strip")
check(strip and not strip:IsShown() and S.CHAT[1] and S.CHAT[1]:find("hidden"), "/wbt strip hides the strip")
SlashCmdList.WICK_WICKSBEASTSANDTHINGS("strip")
check(strip and strip:IsShown(), "/wbt strip shows it again")
-- The strip reads shots over what the quiver holds, 1768/2000 style, when
-- a quiver or ammo pouch is equipped; without one it is the plain count.
-- Capacity is every slot of every such bag, by the family the client
-- reports, times the stack the ammo itself reports.
S.ITEMS = S.ITEMS or {}
S.ITEMS[2512] = { name = "Rough Arrow", type = "Projectile", sub = "Arrow", classID = 6, subClassID = 2, stack = 200 }
S.BAG_FAMILY[1] = 1                       -- bag 1 is a quiver, sixteen slots in the stub
BNS.UI:RefreshAmmo()
local ammoState = BNS.Ammo:State()
check(ammoState.capacity == 3200, "a sixteen slot quiver of two hundred stacks holds 3200: " .. tostring(ammoState.capacity))
-- The count carries a colour for how full the quiver is: under a fifth
-- red, up to three fifths amber, above that the brand green. The
-- capacity is abbreviated so the number that matters gets the room.
local function hex6(c) return ("%02x%02x%02x"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5)) end
local RED_HEX, AMBER_HEX, FEL_HEX = "cc4d4d", "d9a640", hex6(WickCore.Chrome.Colors.fel)
check(strip.ammoText.__text == ("|cff%s%d|r/3.2k"):format(RED_HEX, ammoState.total),
    "151 of 3200 is red over an abbreviated capacity: " .. tostring(strip.ammoText.__text))
local realCount = GetInventoryItemCount
GetInventoryItemCount = function(_, inv) return inv == 0 and 1300 or 1 end
BNS.UI:RefreshAmmo()
check(tostring(strip.ammoText.__text):find("|cff" .. AMBER_HEX .. "1301|r/3.2k", 1, true) ~= nil,
    "about forty percent is amber: " .. tostring(strip.ammoText.__text))
GetInventoryItemCount = function(_, inv) return inv == 0 and 2500 or 1 end
BNS.UI:RefreshAmmo()
check(tostring(strip.ammoText.__text):find("|cff" .. FEL_HEX .. "2501|r/3.2k", 1, true) ~= nil,
    "nearly full is green: " .. tostring(strip.ammoText.__text))
GetInventoryItemCount = realCount
S.ITEMS[2512].stack = 125                 -- sixteen slots of 125 is a round two thousand
BNS.UI:RefreshAmmo()
check(tostring(strip.ammoText.__text):find("/2k", 1, true) ~= nil, "a round capacity abbreviates without a decimal: " .. tostring(strip.ammoText.__text))
S.ITEMS[2512].stack = 200
BNS.UI:RefreshAmmo()
S.BAG_FAMILY[1] = nil
BNS.UI:RefreshAmmo()
ammoState = BNS.Ammo:State()
check(ammoState.capacity == nil, "no quiver, no capacity")
check(not tostring(strip.ammoText.__text):find("/"), "and the strip goes back to the plain count: " .. tostring(strip.ammoText.__text))
S.ITEMS[2512] = nil
SlashCmdList.WICK_WICKSBEASTSANDTHINGS("unlock")
SlashCmdList.WICK_WICKSBEASTSANDTHINGS("lock")
try("beasts panel", function() WicksBeastsAndThings_Toggle() end)
try("beasts panel refresh", function() WicksBeastsAndThings_Toggle(); WicksBeastsAndThings_Toggle() end)
S.CHAT = {}
SlashCmdList.WICK_WICKSBEASTSANDTHINGS("ammo 50")
SlashCmdList.WICK_WICKSBEASTSANDTHINGS("food 6948")
SlashCmdList.WICK_WICKSBEASTSANDTHINGS("food")
check(#S.CHAT >= 4, "/wbt ammo and food commands print")
SlashCmdList.WICK_WICKSBEASTSANDTHINGS("food clear")
try("beasts kit", function() SlashCmdList.WICK_WICKSBEASTSANDTHINGS("kit") end)
local bkit
for _, f in ipairs(S.frames) do if f.__name == "WickWicksBeastsAndThingsKit" then bkit = f end end
check(bkit ~= nil, "beasts kit panel built")
local BENTRY = WickCore.Launcher.entries.WicksBeastsAndThings
local BADDON = BENTRY and BENTRY.addon
check(BADDON ~= nil, "beasts launcher registered")
if BADDON then
    local rows = BADDON.kit.checklist:Evaluate()
    check(#rows == 5, "beasts checklist 5 rows")
    check(rows[2].state == "ok", "pet out at rest: " .. tostring(rows[2].state))
    check(rows[3].state == "missing", "content pet reads as not fed: " .. tostring(rows[3].state))
    check(rows[4].state == "ok", "ammo stocked above the 50 warn: " .. tostring(rows[4].state))
    if MODERN then
        COMBAT = true
        local crows = BADDON.kit.checklist:Evaluate()
        check(crows[3].state == "unknown", "pet fed unknown in combat (secret happiness): " .. tostring(crows[3].state))
        COMBAT = false
    end

    -- The beast atlas. Nothing in the client joins family to abilities,
    -- so it learns by reading the pet spell book whenever a pet is out.
    local function special(family)
        local list = BNS.beasts:Known(family)
        return list and table.concat(list, ", ") or "nothing"
    end
    local fams = BADDON.db.global.families
    check(fams and fams.Wolf ~= nil, "the wolf out at login was filed")
    check(fams.Wolf.abilities["Furious Howl"] == "active", "with its active abilities")
    check(fams.Wolf.abilities["Avoidance"] == "passive", "and its passive ones marked as passive")

    S.PET_FAMILY = "Hyena"
    S.PET_SPELLS = { { "Bite", "active" }, { "Growl", "active" }, { "Tendon Rip", "active" } }
    S.fire("UNIT_PET", "player")
    check(BADDON.db.global.families.Hyena ~= nil, "a second family files on its own")
    check(special("Hyena"):find("Tendon Rip") ~= nil, "hyena keeps Tendon Rip: " .. special("Hyena"))

    -- A third family makes Bite and Growl ordinary, three being the point
    -- at which an ability stops being a reason to tame anything.
    S.PET_FAMILY = "Boar"
    S.PET_SPELLS = { { "Bite", "active" }, { "Growl", "active" }, { "Charge", "active" } }
    S.fire("UNIT_PET", "player")
    check(special("Hyena") == "Tendon Rip",
        "with three families sharing Bite and Growl, only Tendon Rip stands out: " .. special("Hyena"))
    check(special("Boar") == "Charge", "and only Charge for the boar: " .. special("Boar"))

    S.CHAT = {}
    SlashCmdList.WICK_WICKSBEASTSANDTHINGS("beasts")
    local blist = table.concat(S.CHAT, " | ")
    check(blist:find("Hyena") ~= nil and blist:find("Tendon Rip") ~= nil and blist:find("Boar") ~= nil,
        "/wbt beasts lists them: " .. blist:sub(1, 80))

    -- The Beasts tab, contributed by the kit rather than built into the
    -- core, since WickCore has no business knowing what a hunter keeps.
    local kit = BADDON.kit
    check(kit.tabs.beasts ~= nil, "the kit grew a Beasts tab")
    check(kit.panes.beasts ~= nil, "with a pane behind it")
    kit:Select("beasts")
    check(kit.panes.beasts:IsShown(), "selecting it shows the pane")
    check(kit.panes.talents:IsShown() == false, "and puts the others away")
    local prows = BNS.beasts.pane.rows
    local shown = 0
    for _, r in ipairs(prows) do if r:IsShown() then shown = shown + 1 end end
    check(shown == 3, "a row per recorded family, got " .. shown)
    local texts = {}
    for _, r in ipairs(prows) do texts[#texts + 1] = r.family:GetText() .. "=" .. r.abilities:GetText() end
    local joined = table.concat(texts, " | ")
    check(joined:find("Hyena=Tendon Rip") ~= nil, "the pane leads with what sets a family apart: " .. joined:sub(1, 70))
    check(joined:find("%(") ~= nil, "and brackets the ones they all share")

    BNS.beasts:Forget()
    BNS.beasts:RefreshPane()
    shown = 0
    for _, r in ipairs(prows) do if r:IsShown() then shown = shown + 1 end end
    check(shown == 0, "forget all empties the pane")
    kit:Select("talents")
end

io.write("== Poisons and Things ==\n")
CLASS = "ROGUE"
local PNS = S.loadAddon(ADDONS_DIR .. "/WicksPoisonsAndThings", "WicksPoisonsAndThings", { "Core.lua", "Poisons.lua", "Combo.lua", "Swap.lua", "UI.lua" })
local ns = PNS
S.fire("ADDON_LOADED", "WicksPoisonsAndThings")
S.fire("PLAYER_LOGIN")
dumpErrors()
local PENTRY = WickCore.Launcher.entries.WicksPoisonsAndThings
local PA = PENTRY and PENTRY.addon
check(PA ~= nil, "poisons launcher registered")
local mainKey, offKey = _G.WicksPoisonsMainButton, _G.WicksPoisonsOffButton
check(mainKey ~= nil and offKey ~= nil, "a coating keybind button per hand")
local pstrip = _G.WicksPoisonsStrip
check(pstrip ~= nil and pstrip:IsShown(), "poison strip built and shown for a rogue")
if MODERN then
    local mt = tostring(mainKey:GetAttribute("macrotext"))
    check(mt:find("/use item:6948") and mt:find("/use 16"), "main hand macro uses the coating then the slot: " .. mt)
    check(tostring(offKey:GetAttribute("macrotext")):find("/use 17") ~= nil, "off hand macro targets the off hand slot")
else
    check(tostring(mainKey:GetAttribute("macrotext")) ~= "", "legacy still builds a coating macro")
end
S.CHAT = {}
SlashCmdList.WICK_WICKSPOISONSANDTHINGS("status")
local pline = table.concat(S.CHAT, " | ")
check(#S.CHAT >= 3, "/wpt status prints")
if MODERN then
    check(pline:find("coated true") ~= nil, "main hand reads as coated from the temporary enchantment")
    check(pline:find("minutes 30") ~= nil, "time left read: " .. pline:sub(1, 90))
end

-- Which call a client offers for reading a coating is not something an
-- addon can know from the inside, and asking only the one it was
-- written against is how two poisoned blades read as bare. Take them
-- away one at a time: the answer has to survive any two going missing.
if MODERN then
    local function coated()
        return ns.Poisons:Hand("main").coated == true, ns.Poisons:Hand("main").via
    end
    local ok, via = coated()
    check(ok, "the coating reads with every call present, via " .. tostring(via))

    S.TEMPENCH_API = { paperdoll = false, item = true, classic = true }
    ok, via = coated()
    check(ok, "and without C_PaperDollInfo, via " .. tostring(via))

    S.TEMPENCH_API = { paperdoll = false, item = false, classic = true }
    ok, via = coated()
    check(ok, "and on the classic global alone, via " .. tostring(via))
    local h30 = ns.Poisons:Hand("main")
    check(h30.msLeft == 1800000, "with the time still read off it: " .. tostring(h30.msLeft))
    check(h30.charges == 40, "and the charges: " .. tostring(h30.charges))

    S.TEMPENCH_API = { paperdoll = true, item = false, classic = false }
    ok = coated()
    check(ok, "and on C_PaperDollInfo alone")

    -- A bare weapon still has to read as bare through every path.
    S.TEMPENCH_API = { paperdoll = false, item = false, classic = true }
    check(ns.Poisons:Hand("off").coated == false,
        "an uncoated hand reads bare on the classic global, not coated")

    -- The live client: all three calls present, none of them answering,
    -- both blades poisoned and both reading bare. The game still writes
    -- it on the item, so that is where it reads it from.
    S.TEMPENCH_API = { paperdoll = false, item = false, classic = false, tooltip = true }
    S.TEMPENCH_NAME = "Instant Poison"
    local h = ns.Poisons:Hand("main")
    check(h.coated == true, "with every call silent it reads the weapon's tooltip instead")
    check(h.via == "tooltip", "and says so: " .. tostring(h.via))
    check(h.msLeft == 1800000, "the minutes come off the line: " .. tostring(h.msLeft))
    check(h.charges == 40, "and the charges: " .. tostring(h.charges))
    check(h.coating == "Instant Poison",
        "with the name, which no call ever gave: " .. tostring(h.coating))

    -- Only when even that is gone is there nothing to know.
    S.TEMPENCH_API = { paperdoll = false, item = false, classic = false, tooltip = false }
    check(ns.Poisons:Hand("main").coated == false,
        "with nothing at all it says bare rather than erroring")
    S.TEMPENCH_API = { paperdoll = true, item = true, classic = true, tooltip = true }
end

io.write("== which poison a hand reaches for ==" .. string.char(10))
do
    -- Crippling is the highest item level in the bag, which is the
    -- shape that used to win: the list was ranked on level alone and a
    -- poison that slows kept taking a slot meant for damage.
    local INSTANT, DEADLY, CRIPPLING, WOUND = 6947, 2892, 3775, 10918
    S.ITEMS[INSTANT]   = { name = "Instant Poison IV",   classID = 0, subClassID = 6, itemLevel = 42 }
    S.ITEMS[DEADLY]    = { name = "Deadly Poison III",   classID = 0, subClassID = 6, itemLevel = 44 }
    S.ITEMS[CRIPPLING] = { name = "Crippling Poison II", classID = 0, subClassID = 6, itemLevel = 60 }
    S.ITEMS[WOUND]     = { name = "Wound Poison II",     classID = 0, subClassID = 6, itemLevel = 46 }
    -- A staged bag holds only what is staged. The others are staged
    -- empty, or the stub hands out a default item in every free slot
    -- and the bag is not the one this check describes.
    for bag = 1, 4 do S.SLOT_ITEMS[bag] = {} end
    S.SLOT_ITEMS[0] = { { id = INSTANT, count = 5 }, { id = DEADLY, count = 5 },
                        { id = CRIPPLING, count = 5 }, { id = WOUND, count = 5 } }
    ns.Poisons:UpdateMacros()

    local m = ns.Poisons:ChoiceFor("main")
    local o = ns.Poisons:ChoiceFor("off")
    check(m and m.itemID == INSTANT,
        "the main hand takes Instant, not the highest level thing in the bag: "
        .. tostring(m and m.name))
    check(o and o.itemID == DEADLY, "and the off hand takes Deadly: " .. tostring(o and o.name))
    check(ns.Poisons:Rank({ name = "Crippling Poison II" }, "main")
          > ns.Poisons:Rank({ name = "Wound Poison II" }, "main"),
        "a poison that slows ranks below every damage one")
    check(ns.Poisons:Rank({ name = "Some New Coating" }, "main")
          > ns.Poisons:Rank({ name = "Instant Poison IV" }, "main"),
        "a coating it has never met loses to a damage poison")
    check(ns.Poisons:Rank({ name = "Some New Coating" }, "main")
          < ns.Poisons:Rank({ name = "Crippling Poison II" }, "main"),
        "and beats one it knows is utility")

    -- Carrying nothing but utility, it still puts something on rather
    -- than leaving the key empty.
    S.SLOT_ITEMS[0] = { { id = CRIPPLING, count = 5 } }
    ns.Poisons:UpdateMacros()
    m = ns.Poisons:ChoiceFor("main")
    check(m and m.itemID == CRIPPLING, "with only Crippling carried, that is what the key uses")

    -- Pinning still wins outright.
    S.SLOT_ITEMS[0] = { { id = INSTANT, count = 5 }, { id = CRIPPLING, count = 5 } }
    PA.db.profile.pinned.main = CRIPPLING
    ns.Poisons:UpdateMacros()
    m = ns.Poisons:ChoiceFor("main")
    check(m and m.itemID == CRIPPLING and m.pinned, "a pin beats the ranking")
    PA.db.profile.pinned.main = nil
    ns.Poisons:UpdateMacros()
    check(ns.Poisons:ChoiceFor("main").itemID == INSTANT, "and clearing it goes back to Instant")
end

-- Combo points over the target's nameplate. The point of the design is
-- that it never compares the value, so the same code has to survive the
-- number arriving secret. Run it both ways.
local combo = _G.WicksPoisonsComboRow
check(combo ~= nil, "combo row built for a rogue")
check(not combo:IsShown(), "and stays hidden with no target")
S.HAS_TARGET = true
S.COMBO = 3
S.fire("PLAYER_TARGET_CHANGED")
check(combo:IsShown(), "it appears once the target has a nameplate")
local plate = C_NamePlate.GetNamePlateForUnit("target")
check(combo:GetParent() == plate, "parented to the target's plate")
check(combo.anchoredToName == false, "sits under the health bar, off the name above it")
PA.db.profile.comboAbove = true
S.fire("PLAYER_TARGET_CHANGED")
check(combo.anchoredToName == true, "the option lifts it above the name, clear of the cast bar")
PA.db.profile.comboAbove = false
S.fire("PLAYER_TARGET_CHANGED")
check(combo.anchoredToName == false, "and back under the health bar")
check(combo.count == 5, "five pips")
check(combo.pips[1].__min == 0 and combo.pips[1].__max == 1, "each pip covers one point of the range")
check(combo.pips[4].__min == 3 and combo.pips[4].__max == 4, "the fourth pip covers three to four")
S.fire("UNIT_POWER_UPDATE", "player", "COMBO_POINTS")
check(combo.pips[1]:GetValue() == 3, "the raw count goes into every pip")

-- The energy to spend the points on. The pips answer how close the
-- finisher is; this answers whether you can pay for it.
S.ENERGY = 62
S.fire("UNIT_POWER_UPDATE", "player", "ENERGY")
check(combo.energy ~= nil, "there is an energy bar")
check(combo.energy:IsShown(), "on by default")
check(combo.energy:GetValue() == 62, "carrying the reading: " .. tostring(combo.energy:GetValue()))
check(combo.energy.__min == 0 and combo.energy.__max == 100,
    "over the whole pool rather than a point of it: "
    .. tostring(combo.energy.__min) .. " to " .. tostring(combo.energy.__max))

-- It owns the bottom of the row, not the underside of the pips. Above
-- the name the row grows upward from a fixed bottom edge, so a bar
-- pinned under the pips would be drawn over the name.
local ebottom
for _, pt in ipairs(combo.energy.__points or {}) do
    if pt[1] == "BOTTOMLEFT" then ebottom = pt[2] end
end
check(ebottom == combo, "anchored to the row's own bottom, whichever way it is placed")
local pipTop
for _, pt in ipairs(combo.pips[1].__points or {}) do
    if pt[1] == "TOPLEFT" then pipTop = pt[2] end
end
check(pipTop == combo, "and the pips to its top")
check(combo:GetHeight() > 9, "the row is taller for it, got " .. tostring(combo:GetHeight()))

-- A talent that moves the pool moves the bar with it.
S.ENERGY_MAX = 110
S.fire("UNIT_MAXPOWER", "player", "ENERGY")
check(combo.energy.__max == 110, "a bigger pool widens the range: " .. tostring(combo.energy.__max))
S.ENERGY_MAX = nil
S.fire("UNIT_MAXPOWER", "player", "ENERGY")

-- Switched off, the row goes back to the height of the pips alone.
PA.db.profile.comboEnergy = false
S.fire("UNIT_MAXPOWER", "player", "ENERGY")
check(not combo.energy:IsShown(), "the option hides it")
check(combo:GetHeight() == 9, "and gives the row its height back: " .. tostring(combo:GetHeight()))
PA.db.profile.comboEnergy = true
S.fire("UNIT_MAXPOWER", "player", "ENERGY")
check(combo.energy:IsShown(), "and back on without a reload")

-- Now with the client refusing to say. Nothing may compare, and nothing
-- may error; the pips just take the secret.
S.POWER_SECRET = true
local okSecret = pcall(function()
    S.fire("UNIT_MAXPOWER", "player", "COMBO_POINTS")
    S.fire("UNIT_POWER_UPDATE", "player", "COMBO_POINTS")
    S.fire("UNIT_POWER_UPDATE", "player", "ENERGY")
end)
check(okSecret, "a secret combo count does not throw")
check(combo.count == 5, "and falls back to five pips when the maximum is secret too")
check(combo.energy.__max == 100,
    "nor does a secret energy pool become a range: " .. tostring(combo.energy.__max))
check(combo.energy:IsShown(), "and the bar stays up rather than vanishing mid-fight")
S.POWER_SECRET = false

PA.db.profile.comboOnPlate = false
S.fire("PLAYER_TARGET_CHANGED")
check(not combo:IsShown(), "switching it off hides the row")
PA.db.profile.comboOnPlate = true
S.fire("PLAYER_TARGET_CHANGED")
S.HAS_TARGET = false
S.fire("PLAYER_TARGET_CHANGED")
check(not combo:IsShown(), "losing the target hides it again")
io.write("== the weapon swap keys ==\n")
do
    -- A slow main hand and a dagger off hand, which is the setup the
    -- keys exist for.
    local SWORD, DAGGER = 871, 13505
    S.ITEMS[SWORD]  = { equipLoc = "INVTYPE_WEAPONMAINHAND", classID = 2, subClassID = 7,
                        name = "Felstriker" }
    S.ITEMS[DAGGER] = { equipLoc = "INVTYPE_WEAPONOFFHAND",  classID = 2, subClassID = 15,
                        name = "Core Hound Tooth" }
    S.EQUIPPED_IDS = S.EQUIPPED_IDS or {}
    S.EQUIPPED_IDS[16], S.EQUIPPED_IDS[17] = SWORD, DAGGER
    ns.swap:Update()

    local pair = ns.swap.pair
    check(pair ~= nil, "a pair is read off your hands" .. (pair and "" or ": " .. tostring(ns.swap.why)))
    check(pair and pair.dagger == DAGGER, "the dagger is picked by subclass, not by slot")
    check(pair and pair.other == SWORD, "and the other hand is the one that comes back")
    check(pair and pair.daggerInMain == false, "it knows the dagger is in the off hand now")

    local stealth = ns.swap.macro.stealth
    local strike = ns.swap.macro.strike
    check(stealth:find("[nostealth,nocombat] 16 item:" .. DAGGER, 1, true) ~= nil,
        "stealth puts the dagger in the main hand on the way in: "
        .. stealth:gsub(string.char(10), " | "))
    check(stealth:find("[nostealth,nocombat] 17 item:" .. SWORD, 1, true) ~= nil,
        "and the slow one in the off hand")
    -- The reported bug: dropping stealth put the dagger back, because
    -- the key did not know you were on the way out.
    check(stealth:find("[stealth] 16 item:" .. SWORD, 1, true) ~= nil,
        "and pressed while stealthed it gives the slow weapon back instead")
    check(stealth:find("[stealth] 17 item:" .. DAGGER, 1, true) ~= nil,
        "putting the dagger in the off hand on the way out")
    check(strike:find("[nostealth] 16 item:" .. SWORD, 1, true) ~= nil,
        "the strike key puts the slow one back: " .. strike:gsub(string.char(10), " | "))
    check(strike:find("[nostealth] 17 item:" .. DAGGER, 1, true) ~= nil,
        "and the dagger back to the off hand")

    -- Nothing may move a weapon without asking where you are standing
    -- first. This is the check the bug would have failed.
    for _, m in ipairs({ stealth, strike }) do
        for line in m:gmatch("[^" .. string.char(10) .. "]+") do
            if line:find("/equipslot", 1, true) then
                check(line:find("%[") ~= nil,
                    "every equip asks about your stance first: " .. line)
            end
        end
    end
    -- The strike key must not touch your hands from stealth, or it
    -- strips the dagger you are opening with.
    check(strike:find("[stealth]", 1, true) == nil,
        "the strike key leaves your hands alone while stealthed")
    -- And the stealth key must not move anything in a fight, where
    -- Stealth will not cast anyway.
    check(select(2, stealth:gsub("nocombat", "")) == 2,
        "the stealth key holds off in combat, on both hands")

    -- Stealth has a cooldown and a macro cannot ask about one, so the
    -- lines that would put the dagger up have to be left out while it
    -- is down. Otherwise the weapons swap and the cast goes nowhere.
    S.ON_COOLDOWN = S.ON_COOLDOWN or {}
    S.ON_COOLDOWN[1784] = true
    S.fire("SPELL_UPDATE_COOLDOWN")
    local down = ns.swap.macro.stealth
    check(ns.swap.stealthReady == false, "it notices Stealth is on cooldown")
    check(down:find("nostealth", 1, true) == nil,
        "and stops putting the dagger up while it is: " .. down:gsub(string.char(10), " | "))
    check(down:find("[stealth] 16 item:" .. SWORD, 1, true) ~= nil,
        "while getting back out of stealth still works, which a cooldown should not block")
    check(down:find("/cast Stealth", 1, true) ~= nil,
        "and the cast is still attempted, so the key is not silently dead")
    -- The strike key has nothing to do with Stealth's cooldown.
    check(ns.swap.macro.strike:find("[nostealth] 16 item:" .. SWORD, 1, true) ~= nil,
        "the strike key is untouched by it")

    S.ON_COOLDOWN[1784] = false
    S.fire("SPELL_UPDATE_COOLDOWN")
    check(ns.swap.stealthReady == true, "and it comes back when the cooldown does")
    check(ns.swap.macro.stealth:find("[nostealth,nocombat] 16 item:" .. DAGGER, 1, true) ~= nil,
        "with the dagger lines back in: " .. ns.swap.macro.stealth:gsub(string.char(10), " | "))
    local stealth = ns.swap.macro.stealth
    check(stealth:find("/cast Stealth", 1, true) ~= nil,
        "the stealth key stealths, so it is one key rather than two")
    check(strike:find("/cast Sinister Strike", 1, true) ~= nil,
        "and the other strikes: " .. strike:gsub(string.char(10), " | "))

    -- Addressed by id, not name: two blades called the same thing are
    -- the reason.
    check(stealth:find("Core Hound Tooth", 1, true) == nil,
        "weapons are named by id rather than by name")

    -- The macro is on the button, not just in our own table.
    local sb = _G.WicksPoisonsStealthButton
    check(sb ~= nil, "the stealth key has a secure button")
    check(sb.__attr and sb.__attr.macrotext == stealth,
        "carrying the macro text")
    check(sb.__attr.type == "macro", "as a macro, which is what a secure button will run")

    -- Wearing it the other way round has to give the mirror image, or
    -- pressing stealth while already stealth-handed would undo itself.
    S.EQUIPPED_IDS[16], S.EQUIPPED_IDS[17] = DAGGER, SWORD
    S.fire("PLAYER_EQUIPMENT_CHANGED")
    check(ns.swap.pair.daggerInMain == true, "swapping the hands over is noticed")
    check(ns.swap.macro.stealth == stealth,
        "and the stealth macro is the same text, because it names where things go")
    check(ns.swap.macro.strike == strike, "as is the strike one")

    -- A new weapon needs nothing done to it.
    local NEWSWORD = 12784
    S.ITEMS[NEWSWORD] = { equipLoc = "INVTYPE_WEAPONMAINHAND", classID = 2, subClassID = 7,
                          name = "Arcanite Reaper" }
    S.EQUIPPED_IDS[16], S.EQUIPPED_IDS[17] = NEWSWORD, DAGGER
    S.fire("PLAYER_EQUIPMENT_CHANGED")
    check(ns.swap.macro.strike:find("item:" .. NEWSWORD, 1, true) ~= nil,
        "a new weapon rewrites the keys on its own: " .. ns.swap.macro.strike:gsub("\n", " | "))

    -- And the same for a new dagger, which is the half this had only
    -- covered from the other side.
    local NEWDAGGER = 19874
    S.ITEMS[NEWDAGGER] = { equipLoc = "INVTYPE_WEAPONOFFHAND", classID = 2, subClassID = 15,
                           name = "Perdition's Blade" }
    S.EQUIPPED_IDS[17] = NEWDAGGER
    S.fire("PLAYER_EQUIPMENT_CHANGED")
    check(ns.swap.pair.dagger == NEWDAGGER, "a new dagger is picked up the same way")
    check(ns.swap.macro.stealth:find("16 item:" .. NEWDAGGER, 1, true) ~= nil,
        "and it is the one the stealth key reaches for")
    check(ns.swap.macro.stealth:find("item:" .. DAGGER, 1, true) == nil,
        "with the old one gone from the macro entirely")
    S.EQUIPPED_IDS[17] = DAGGER
    S.fire("PLAYER_EQUIPMENT_CHANGED")

    -- Two daggers is already the stealth setup, and no dagger has
    -- nothing to open with. Neither should leave a macro that moves
    -- weapons around for no reason.
    S.EQUIPPED_IDS[16], S.EQUIPPED_IDS[17] = DAGGER, DAGGER
    S.fire("PLAYER_EQUIPMENT_CHANGED")
    check(ns.swap.pair == nil and ns.swap.macro.stealth == "",
        "two daggers leaves the keys empty: " .. tostring(ns.swap.why))
    S.EQUIPPED_IDS[16], S.EQUIPPED_IDS[17] = SWORD, NEWSWORD
    S.fire("PLAYER_EQUIPMENT_CHANGED")
    check(ns.swap.pair == nil and ns.swap.macro.strike == "",
        "and so does carrying no dagger at all: " .. tostring(ns.swap.why))

    -- Back to the real setup for the rest.
    S.EQUIPPED_IDS[16], S.EQUIPPED_IDS[17] = SWORD, DAGGER
    S.fire("PLAYER_EQUIPMENT_CHANGED")

    -- A secure attribute cannot be written in combat. The change has to
    -- wait rather than be dropped.
    COMBAT = true
    S.EQUIPPED_IDS[16] = NEWSWORD
    S.fire("PLAYER_EQUIPMENT_CHANGED")
    check(ns.swap.macro.strike:find("item:" .. SWORD, 1, true) ~= nil,
        "a weapon change in combat does not rewrite the key")
    COMBAT = false
    S.fire("PLAYER_REGEN_ENABLED")
    check(ns.swap.macro.strike:find("item:" .. NEWSWORD, 1, true) ~= nil,
        "and it catches up once combat drops: " .. ns.swap.macro.strike:gsub("\n", " | "))
    S.EQUIPPED_IDS[16] = SWORD
    S.fire("PLAYER_EQUIPMENT_CHANGED")

    -- The login order. At init the client cannot yet say what is in
    -- your hands, so the pair comes back empty and both macros are
    -- written as empty strings. Nothing re-ran until the gear changed,
    -- which meant equipping something by hand to wake the keys up.
    S.EQUIPPED_IDS[16], S.EQUIPPED_IDS[17] = nil, nil
    ns.swap:Update()
    check(ns.swap.pair == nil and ns.swap.macro.stealth == "",
        "with nothing readable in your hands the keys are empty")

    S.EQUIPPED_IDS[16], S.EQUIPPED_IDS[17] = SWORD, DAGGER
    -- Equipment arriving rather than changing: this is the event a
    -- login gives you, and the one the keys were not listening for.
    S.fire("UNIT_INVENTORY_CHANGED", "player")
    check(ns.swap.macro.stealth ~= "",
        "gear arriving fills them in without anything being equipped by hand: "
        .. ns.swap.macro.stealth:gsub(string.char(10), " | "))

    -- And the other half: the inventory is there but the item is not
    -- described yet, so which hand holds the dagger is unanswerable.
    S.EQUIPPED_IDS[16], S.EQUIPPED_IDS[17] = nil, nil
    ns.swap:Update()
    S.EQUIPPED_IDS[16], S.EQUIPPED_IDS[17] = SWORD, DAGGER
    S.fire("GET_ITEM_INFO_RECEIVED", SWORD)
    check(ns.swap.macro.stealth ~= "", "and so does the item description landing late")

    -- Riding a different ability, for a rogue who opens the second
    -- round with something else.
    S.CHAT = {}
    SlashCmdList.WICK_WICKSPOISONSANDTHINGS("swap strike Ghostly Strike")
    check(ns.swap.macro.strike:find("/cast Ghostly Strike", 1, true) ~= nil,
        "the ability the swap back rides on can be changed")
    SlashCmdList.WICK_WICKSPOISONSANDTHINGS("swap strike")
    check(ns.swap.macro.strike:find("Ghostly Strike", 1, true) == nil,
        "and put back to the default")

    -- Off means off: an empty macro rather than a key that still moves
    -- your weapons.
    SlashCmdList.WICK_WICKSPOISONSANDTHINGS("swap off")
    check(ns.swap.macro.stealth == "" and ns.swap.macro.strike == "",
        "switching them off empties both keys")
    check(sb.__attr.macrotext == "", "including the one on the button")
    SlashCmdList.WICK_WICKSPOISONSANDTHINGS("swap on")
    check(ns.swap.macro.stealth ~= "", "and on puts them back")

    S.CHAT = {}
    SlashCmdList.WICK_WICKSPOISONSANDTHINGS("swap")
    local rep = table.concat(S.CHAT, " | ")
    check(rep:find("Felstriker", 1, true) ~= nil and rep:find("equipslot", 1, true) ~= nil,
        "/wpt swap says what it worked out and what it wrote: " .. rep:sub(1, 80))
end

io.write("== the swap block on the strip ==" .. string.char(10))
do
    local SWORD, DAGGER = 871, 13505
    S.EQUIPPED_IDS[16], S.EQUIPPED_IDS[17] = SWORD, DAGGER
    S.fire("PLAYER_EQUIPMENT_CHANGED")
    ns.UI:RefreshStrip()

    local st, sk = pstrip.swapStealth, pstrip.swapStrike
    check(st ~= nil and sk ~= nil, "a button per key on the end of the strip")
    -- In a block of their own. Riding the hands put a secure button on
    -- top of a secure button and the press stopped swapping anything,
    -- so nothing here may overlap a blade.
    local function anchoredTo(b)
        for _, pt in ipairs(b.__points or {}) do if pt[2] then return pt[2] end end
    end
    check(anchoredTo(st) ~= pstrip.mainBtn and anchoredTo(st) ~= pstrip.offBtn,
        "the swap buttons sit clear of the blades rather than on top of them")
    check(pstrip:GetWidth() > 199, "and the strip is wider for them: "
        .. tostring(pstrip:GetWidth()))

    -- Clicking one has to do what the key does, which means the same
    -- macro rather than a second copy of the logic.
    check(st:GetAttribute("macrotext") == ns.swap.macro.stealth,
        "the stealth button carries the stealth key's own macro")
    check(sk:GetAttribute("macrotext") == ns.swap.macro.strike,
        "and the strike button the strike key's")

    -- The icon is what that key would put in your main hand, and the
    -- fel edge marks the one already there, which is the press that
    -- would do nothing.
    check(sk.live:IsShown(), "the slow weapon is marked as the one you are holding")
    check(not st.live:IsShown(), "and the dagger is not")
    S.EQUIPPED_IDS[16], S.EQUIPPED_IDS[17] = DAGGER, SWORD
    S.fire("PLAYER_EQUIPMENT_CHANGED")
    ns.UI:RefreshStrip()
    check(st.live:IsShown() and not sk.live:IsShown(),
        "swapping your hands over moves the mark")

    -- A pair it cannot read greys out. Hiding a protected frame in a
    -- fight is refused, and a strip that changes shape mid-pull is its
    -- own problem.
    S.EQUIPPED_IDS[16], S.EQUIPPED_IDS[17] = DAGGER, DAGGER
    S.fire("PLAYER_EQUIPMENT_CHANGED")
    ns.UI:RefreshStrip()
    check(ns.swap.pair == nil, "two daggers is a pair it cannot use")
    check(st:IsShown() and sk:IsShown(), "the buttons stay up rather than vanishing")
    check(st.icon.__desaturated == true, "greyed instead: " .. tostring(st.icon.__desaturated))
    check(not st.live:IsShown() and not sk.live:IsShown(), "and neither is marked live")

    -- Refreshing mid-fight touches nothing protected, which is what the
    -- twenty second ticker does.
    S.EQUIPPED_IDS[16], S.EQUIPPED_IDS[17] = SWORD, DAGGER
    S.fire("PLAYER_EQUIPMENT_CHANGED")
    COMBAT = true
    local okTick = pcall(function() ns.UI:RefreshSwap() end)
    check(okTick, "the strip can redraw the swap block in combat")

    -- And does it on its own. The swap keys work mid-fight, so the
    -- icons have to follow them mid-fight; they used to sit behind the
    -- same guard that stops the macro being rewritten.
    check(sk.live:IsShown(), "the slow weapon is marked before the swap")
    S.EQUIPPED_IDS[16], S.EQUIPPED_IDS[17] = DAGGER, SWORD
    S.fire("PLAYER_EQUIPMENT_CHANGED")
    check(st.live:IsShown() and not sk.live:IsShown(),
        "a swap made in combat moves the mark without waiting for the fight to end")
    S.EQUIPPED_IDS[16], S.EQUIPPED_IDS[17] = SWORD, DAGGER
    S.fire("PLAYER_EQUIPMENT_CHANGED")
    check(sk.live:IsShown(), "and back again")
    COMBAT = false
end


S.CHAT = {}
SlashCmdList.WICK_WICKSPOISONSANDTHINGS("combo")
local creport = table.concat(S.CHAT, " | ")
check(creport:find("power secret") ~= nil and creport:find("GetComboPoints") ~= nil,
    "/wpt combo says whether the client will answer: " .. creport:sub(1, 70))

try("poison panel", function() WicksPoisonsAndThings_Toggle() end)
S.CHAT = {}
SlashCmdList.WICK_WICKSPOISONSANDTHINGS("warn 12")
SlashCmdList.WICK_WICKSPOISONSANDTHINGS("pin main 6948")
SlashCmdList.WICK_WICKSPOISONSANDTHINGS("pin off clear")
check(#S.CHAT >= 3, "/wpt warn and pin print")
check(PA.db.profile.warnMinutes == 12 and PA.db.profile.pinned.main == 6948, "warn and pin stored")
try("poisons kit", function() SlashCmdList.WICK_WICKSPOISONSANDTHINGS("kit") end)
if PA then
    local prows = PA.kit.checklist:Evaluate()
    check(#prows == 4, "poisons checklist 4 rows")
    check(prows[1].state == "ok", "main hand coated reads ok: " .. tostring(prows[1].state))
    check(prows[3].state == "ok", "coatings carried: " .. tostring(prows[3].state))
end

io.write("== cooldown bar in every kit ==\n")
for _, name in ipairs({ "WicksTotemsAndThings", "WicksDemonsAndThings", "WicksFormsAndThings",
                        "WicksBeastsAndThings", "WicksPoisonsAndThings" }) do
    local entry = WickCore.Launcher.entries[name]
    local addon = entry and entry.addon
    check(addon ~= nil and addon.cooldowns ~= nil, name .. " has a cooldown bar")
    if addon and addon.cooldowns then
        local bar = addon.cooldowns
        check(bar:Store().shown == false, name .. " keeps it off until asked")
        local okCmd = pcall(function() bar:Command("list") end)
        check(okCmd, name .. " cd command runs")
        -- The kit window carries the same controls, so the bar can be
        -- built without knowing the slash command.
        addon.kit:Build()
        check(addon.kit.panes.cooldowns ~= nil, name .. " kit has a Cooldowns tab")
        local okTab = pcall(function() addon.kit:Select("cooldowns") end)
        check(okTab, name .. " Cooldowns tab opens")
    end
end

io.write("== the bar tracks rather than casts ==\n")
do
    local entry = WickCore.Launcher.entries["WicksTotemsAndThings"]
    local bar = entry and entry.addon and entry.addon.cooldowns
    -- The frame is built lazily, so ask for it rather than hoping
    -- something earlier in the run has opened the bar.
    bar:Build()
    bar:Reset()
    bar:Rebuild()
    local b = bar.buttons and bar.buttons[1]
    check(b ~= nil, "the bar built some icons")

    -- The point of dropping the secure template. A protected button
    -- cannot take an attribute in combat, so a bar built out of them
    -- could not be rebuilt during the fight it exists to help with.
    check(b and b.__template == nil, "icons are plain frames, not secure buttons")
    check(b and b.__attr == nil, "and carry no action attributes")

    -- So a rebuild mid-fight has to be uneventful.
    COMBAT = true
    local okCombat, whyCombat = pcall(function() bar:Add("Stormstrike"); bar:Rebuild() end)
    check(okCombat, "the bar rebuilds in combat: " .. tostring(whyCombat))
    COMBAT = false
end

io.write("== the row wraps and scales ==\n")
do
    local entry = WickCore.Launcher.entries["WicksTotemsAndThings"]
    local bar = entry and entry.addon and entry.addon.cooldowns
    bar:Build()
    bar:Reset()
    local n = #bar:List()
    check(n >= 4, "enough default spells to wrap, got " .. n)

    bar:SetPerRow(0)
    local oneRowH = bar.frame:GetHeight()
    bar:SetPerRow(2)
    check(bar.frame:GetHeight() > oneRowH, "wrapping to two per row makes it taller")
    local wide = bar.frame:GetWidth()
    bar:SetPerRow(0)
    check(bar.frame:GetWidth() > wide, "back to one row, back to wide")

    -- Out of range is a typo, not a reason to go silent.
    check(bar:SetScale(9) == 2.5, "an absurd scale is clamped, not refused")
    check(bar:SetScale(0.1) == 0.5, "and so is a tiny one")
    check(bar:SetScale("nonsense") == nil, "but a non-number says no")

    -- A frame's offsets are read in its own scale, so rescaling moves
    -- it unless the offsets are converted. The bar has to stay put.
    bar:SetScale(1)
    bar.frame:ClearAllPoints()
    bar.frame:SetPoint("CENTER", UIParent, "CENTER", 200, -100)
    bar:SetScale(2)
    local point, _, _, x, y = bar.frame:GetPoint()
    check(bar.frame:GetScale() == 2, "the scale took, got " .. tostring(bar.frame:GetScale()))
    check(point == "CENTER", "the anchor is unchanged: " .. tostring(point))
    check(math.abs(x * 2 - 200) < 0.01 and math.abs(y * 2 - -100) < 0.01,
        "and it sits where it did: " .. tostring(x) .. "," .. tostring(y))
    bar:SetScale(1)
    bar:Reset()
end

-- A lock is there to stop an accidental nudge while you click the bar,
-- not to stop you moving it on purpose. Hunting for the unlock checkbox
-- every time is worse than the accident, so shift always moves it. One
-- rule, asked of WickCore, rather than each bar deciding for itself.
io.write("== a lock yields to shift ==\n")
local Chrome = WickCore.Chrome
-- Both of these kept their own palette: the same numbers as WickCore's,
-- in their own tables. Chrome remembers a region by the identity of the
-- table it was painted with, so a copy never entered the registry and
-- nothing in either addon repainted on a theme change. They looked
-- right only because the numbers matched the default.
io.write("== the kits answer to a theme ==" .. string.char(10))
if MODERN then
    local Chrome = WickCore.Chrome
    local was = Chrome.activeTheme
    for _, name in ipairs({ "WicksDemonsAndThings", "WicksTotemsAndThings" }) do
        local entry = WickCore.Launcher.entries[name]
        local addon = entry and entry.addon
        if addon and addon.Toggle then pcall(function() addon:Toggle(); addon:Toggle() end) end
    end

    Chrome:SetTheme("fel")
    -- Asked per addon, by the file that painted the region. Both of
    -- these kept their own copy of the palette for a long time, which
    -- Chrome cannot recognise, so every bar and border in them sat out
    -- theme changes and looked right only while the theme was the
    -- default one.
    for _, name in ipairs({ "WicksDemonsAndThings", "WicksTotemsAndThings" }) do
        local watched = {}
        for _, r in ipairs(S.regions) do
            if r.__color and r.__src and r.__src:find(name, 1, true) then
                watched[#watched + 1] = r
            end
        end
        check(#watched > 0, name .. " paints regions of its own, got " .. #watched)

        local before = {}
        for i, r in ipairs(watched) do before[i] = table.concat(r.__color, ",") end
        Chrome:SetTheme("mage")
        local moved = 0
        for i, r in ipairs(watched) do
            if table.concat(r.__color, ",") ~= before[i] then moved = moved + 1 end
        end
        check(moved > 0, name .. " repaints on a theme change: " .. moved .. " of " .. #watched)
        Chrome:SetTheme("fel")
    end
    Chrome:SetTheme(was or "fel")
end


local realShift = IsShiftKeyDown
IsShiftKeyDown = function() return false end
check(Chrome:DragAllowed(false) == true, "an unlocked frame drags")
check(Chrome:DragAllowed(true) == false, "a locked one does not")
IsShiftKeyDown = function() return true end
check(Chrome:DragAllowed(true) == true, "until you hold shift")
check(Chrome:DragAllowed(false) == true, "and shift never gets in the way of an unlocked one")

-- Not just the helper: the bar people actually lock has to move.
do
    local entry = WickCore.Launcher.entries["WicksTotemsAndThings"]
    local bar = entry and entry.addon and entry.addon.cooldowns
    -- The frame is built lazily, so ask for it rather than waiting for
    -- something else in the run to have opened the bar.
    local frame = bar and bar:Build()
    local h = frame and frame.GetScript and frame:GetScript("OnDragStart")
    check(h ~= nil, "the cooldown bar has a drag handler to test")
    if h then
        bar:SetLocked(true)
        local started = false
        frame.StartMoving = function() started = true end
        IsShiftKeyDown = function() return false end
        h(frame)
        check(not started, "a locked cooldown bar ignores a plain drag")
        IsShiftKeyDown = function() return true end
        h(frame)
        check(started, "and moves when the drag is deliberate")
        bar:SetLocked(false)
    end
end
IsShiftKeyDown = realShift

io.write("== Conjures and Things ==\n")
CLASS = "MAGE"
-- A mage who has the first three teleports and only one portal: the
-- level 40 gap, which is the normal state for most of the levelling.
S.SPELLBOOK = {
    { "Fireball", "Rank 7", "Interface\\Icons\\Fireball", 133 },
    { "Conjure Water", "Rank 4", "Interface\\Icons\\Water", 5504 },
    { "Conjure Food", "Rank 3", "Interface\\Icons\\Food", 587 },
    { "Teleport: Stormwind", "", "Interface\\Icons\\TeleSW", 3561 },
    { "Teleport: Ironforge", "", "Interface\\Icons\\TeleIF", 3562 },
    { "Teleport: Darnassus", "", "Interface\\Icons\\TeleDN", 3565 },
    { "Portal: Stormwind", "", "Interface\\Icons\\PortSW", 10059 },
}
S.loadAddon(ADDONS_DIR .. "/WicksConjuresAndThings", "WicksConjuresAndThings", { "Core.lua", "Conjure.lua", "Portals.lua", "UI.lua" })
S.fire("ADDON_LOADED", "WicksConjuresAndThings")
S.fire("PLAYER_LOGIN")
dumpErrors()
local MENTRY = WickCore.Launcher.entries.WicksConjuresAndThings
local MA = MENTRY and MENTRY.addon
check(MA ~= nil, "conjures launcher registered")
check(_G.WicksConjuresWaterButton ~= nil and _G.WicksConjuresFoodButton ~= nil, "a conjure keybind per ration")
local cstrip = _G.WicksConjuresStrip
check(cstrip ~= nil and cstrip:IsShown(), "conjures strip shown for a mage")
local stock = WICKCONJ and nil
S.CHAT = {}
SlashCmdList.WICK_WICKSCONJURESANDTHINGS("status")
local cline = table.concat(S.CHAT, " | ")
check(#S.CHAT >= 3, "/wcj status prints")
if MODERN then
    check(cline:find("rations %d") ~= nil, "conjured rations counted from the bags: " .. cline:sub(1, 70))
    check(tostring(_G.WicksConjuresWaterButton:GetAttribute("spell")) ~= "", "the water key carries a spell")
    check(tostring(_G.WicksConjuresFoodButton:GetAttribute("spell")):find("Food") ~= nil,
        "and the food key carries the food one: " .. tostring(_G.WicksConjuresFoodButton:GetAttribute("spell")))

    -- The strip has one Rations segment standing for both halves of the
    -- job, and it used to conjure drink whichever half you were short of.
    local rations
    for _, fr in ipairs(S.frames) do
        local a = fr.__attr
        if a and a.spell2 and tostring(a.spell1):find("Water") then rations = fr end
    end
    check(rations ~= nil, "found the rations segment")
    if rations then
        check(tostring(rations:GetAttribute("spell1")):find("Water") ~= nil,
            "left-click conjures drink: " .. tostring(rations:GetAttribute("spell1")))
        check(tostring(rations:GetAttribute("spell2")):find("Food") ~= nil,
            "right-click conjures food: " .. tostring(rations:GetAttribute("spell2")))
    end
end
try("conjures panel", function() WicksConjuresAndThings_Toggle() end)
try("conjures kit", function() SlashCmdList.WICK_WICKSCONJURESANDTHINGS("kit") end)
if MA then
    local crows = MA.kit.checklist:Evaluate()
    -- Five base rows plus the two rune rows, which apply because this
    -- mage knows both a teleport and a portal.
    check(#crows == 7, "conjures checklist 7 rows, got " .. #crows)
    check(MA.cooldowns ~= nil, "conjures has a cooldown bar")
end

io.write("== portals and teleports ==\n")
do
    local P = WicksConjuresAndThings and nil
    local Portals = MA and MA.kit and nil
    -- The addon namespace is not exported, so reach it the way a player
    -- would: through the panel the command opens.
    SlashCmdList.WICK_WICKSCONJURESANDTHINGS("portals")
    local panel = _G.WicksConjuresPortals
    check(panel ~= nil and panel:IsShown(), "the portals panel opens")

    S.CHAT = {}
    SlashCmdList.WICK_WICKSCONJURESANDTHINGS("status")
    local line = table.concat(S.CHAT, " | ")
    -- Three destinations out of four spells: Stormwind has both halves.
    check(line:find("3 destinations", 1, true) ~= nil,
        "destinations come from the book, not a list: " .. line:sub(1, 90))
    check(line:find("Stormwind: teleport + portal", 1, true) ~= nil,
        "a destination with both halves reads as both")
    check(line:find("Darnassus: teleport", 1, true) ~= nil
        and line:find("Darnassus: teleport + portal", 1, true) == nil,
        "and one with only a teleport does not claim a portal")

    -- The rows are the secure buttons, so check what they would cast.
    local rows = panel.rows or {}
    check(#rows == 3, "a row per destination, got " .. #rows)
    if #rows == 3 then
        -- Alphabetical: Darnassus, Ironforge, Stormwind.
        check(rows[1]:GetAttribute("spell1") == "Teleport: Darnassus",
            "left-click teleports: " .. tostring(rows[1]:GetAttribute("spell1")))
        check(rows[1]:GetAttribute("spell2") == "",
            "and a city with no portal has nothing on right-click")
        check(rows[3]:GetAttribute("spell2") == "Portal: Stormwind",
            "right-click opens the portal: " .. tostring(rows[3]:GetAttribute("spell2")))
    end

    -- Learning a city mid-session reorders the list, and the rows are
    -- pooled, so row one has to end up pointed somewhere new.
    S.SPELLBOOK[#S.SPELLBOOK + 1] = { "Teleport: Amberfall", "", "Interface\\Icons\\X", 90001 }
    S.fire("SPELLS_CHANGED")
    check(#(panel.rows or {}) >= 4, "the new city gets a row")
    check(rows[1]:GetAttribute("spell1") == "Teleport: Amberfall",
        "and the pooled first row retargets: " .. tostring(rows[1]:GetAttribute("spell1")))

    -- A destination invented for this test proves the point: nothing
    -- here knows the name of a single city.
    table.remove(S.SPELLBOOK)
    S.fire("SPELLS_CHANGED")

    -- Rows are secure buttons, and a secure button's attributes are
    -- locked for the duration of a fight. Opening the panel mid-pull,
    -- or learning something while one is up, must not throw.
    panel:Hide()
    local before = #(panel.rows or {})
    COMBAT = true
    -- Sanity: the stub must refuse an attribute on a secure frame in
    -- combat, or the rest of this proves nothing.
    local okGuard = pcall(function() panel.rows[1]:SetAttribute("type1", "spell") end)
    check(not okGuard, "a secure row refuses an attribute in combat")
    -- Two, so the row pool genuinely runs out and a fresh secure
    -- button has to be built while the attributes are locked. One
    -- would reuse the row the Amberfall case left behind and prove
    -- nothing.
    S.SPELLBOOK[#S.SPELLBOOK + 1] = { "Teleport: Everlook", "", "Interface\\Icons\\X", 90002 }
    S.SPELLBOOK[#S.SPELLBOOK + 1] = { "Teleport: Booty Bay", "", "Interface\\Icons\\X", 90003 }
    -- The addon's event dispatcher pcalls each handler and prints what
    -- it caught, so a throw inside one never reaches this pcall. The
    -- chat is where the evidence lands, and checking only the pcall let
    -- a real break pass as green.
    S.CHAT = {}
    local okCombat, whyCombat = pcall(function()
        SlashCmdList.WICK_WICKSCONJURESANDTHINGS("portals")
        S.fire("SPELLS_CHANGED")
    end)
    local swallowed = table.concat(S.CHAT, " | ")
    check(swallowed:find("error in", 1, true) == nil,
        "and nothing was swallowed by the dispatcher: " .. swallowed:sub(1, 110))
    check(okCombat, "the portals panel survives combat: " .. tostring(whyCombat)
        .. " [shown=" .. tostring(panel:IsShown())
        .. " rows " .. tostring(before) .. "->" .. tostring(#(panel.rows or {})) .. "]")
    COMBAT = false

    -- And the city learned during the fight gets its row once it ends.
    S.fire("PLAYER_REGEN_ENABLED")
    local found = false
    for _, r in ipairs(panel.rows or {}) do
        if r:IsShown() and r:GetAttribute("spell1") == "Teleport: Everlook" then found = true end
    end
    check(found, "and the row it could not build arrives when the fight does")

    table.remove(S.SPELLBOOK)
    table.remove(S.SPELLBOOK)
    S.fire("SPELLS_CHANGED")
    panel:Hide()
end

io.write("== rune rows appear with the spells ==\n")
do
    local keep = S.SPELLBOOK
    -- A mage at nineteen: no teleports, so no rune rows at all. A grey
    -- row about reagents for a spell you cannot cast is clutter.
    S.SPELLBOOK = {
        { "Fireball", "Rank 7", "Interface\\Icons\\Fireball", 133 },
        { "Conjure Water", "Rank 4", "Interface\\Icons\\Water", 5504 },
    }
    S.fire("SPELLS_CHANGED")
    local rows = MA.kit.checklist:Evaluate()
    check(#rows == 5, "no teleports, no rune rows: " .. #rows)
    local labels = {}
    for _, r in ipairs(rows) do labels[r.label] = true end
    check(not labels["Teleport runes"] and not labels["Portal runes"],
        "neither rune row is drawn")

    -- At twenty the teleport row appears, and only that one.
    S.SPELLBOOK[#S.SPELLBOOK + 1] = { "Teleport: Stormwind", "", "Interface\\Icons\\T", 3561 }
    S.fire("SPELLS_CHANGED")
    rows = MA.kit.checklist:Evaluate()
    labels = {}
    for _, r in ipairs(rows) do labels[r.label] = true end
    check(labels["Teleport runes"] == true, "the teleport row arrives with the spell")
    check(labels["Portal runes"] == nil, "and the portal row waits for level forty")

    S.SPELLBOOK = keep
    S.fire("SPELLS_CHANGED")
end

io.write("== Stances and Things ==\n")
CLASS = "WARRIOR"
S.STANCE, S.STANCE_COUNT = 1, 3          -- a warrior past thirty, in Battle
S.loadAddon(ADDONS_DIR .. "/WicksStancesAndThings", "WicksStancesAndThings")
S.fire("ADDON_LOADED", "WicksStancesAndThings")
S.fire("PLAYER_LOGIN")
dumpErrors()
local SENTRY = WickCore.Launcher.entries.WicksStancesAndThings
local SA = SENTRY and SENTRY.addon
check(SA ~= nil, "stances launcher registered")
local sstrip = _G.WicksStancesStrip
check(sstrip ~= nil and sstrip:IsShown(), "stance strip shown for a warrior")
check(_G.WicksStancesButton1 and _G.WicksStancesButton2 and _G.WicksStancesButton3,
    "a keybindable button per stance")
check(_G.WicksStancesSmartButton ~= nil, "and one for the smart key")

-- The macro is the whole feature: it has to name the stance the ability
-- needs and only cast the ability once you are in it. Two lines, because
-- the game will not change stance and swing off the same press.
local Stances
for _, fr in ipairs(S.frames) do if fr.__name == "WicksStancesEvents" then Stances = true end end
check(Stances, "stances event frame created")

local smart = _G.WicksStancesSmartButton
local charge = tostring(smart:GetAttribute("macrotext"))
check(charge:find("/cast %[nostance:1%] Battle Stance") ~= nil,
    "the smart key swaps to Battle for Charge: " .. charge:gsub("\n", " | "))
check(charge:find("/cast %[stance:1%] Charge") ~= nil, "and casts Charge once there")
check(tostring(_G.WicksStancesButton3:GetAttribute("macrotext")):find("Berserker Stance") ~= nil,
    "the third button swaps to Berserker")

-- An ability in another stance re-routes.
S.CHAT = {}
SlashCmdList.WICK_WICKSSTANCESANDTHINGS("bind Shield Wall")
local sw = tostring(smart:GetAttribute("macrotext"))
check(sw:find("nostance:2") ~= nil and sw:find("%[stance:2%] Shield Wall") ~= nil,
    "Shield Wall routes to Defensive: " .. sw:gsub("\n", " | "))

-- One with no stance requirement is cast where you stand, not routed.
SlashCmdList.WICK_WICKSSTANCESANDTHINGS("bind Execute")
local ex = tostring(smart:GetAttribute("macrotext"))
check(ex:find("stance") == nil and ex:find("/cast Execute") ~= nil,
    "an ability needing no stance is cast where you stand: " .. ex:gsub("\n", " | "))
SlashCmdList.WICK_WICKSSTANCESANDTHINGS("bind Charge")

-- Secure attributes cannot be written in combat, and the strip has to
-- pick the change up the moment it clears rather than staying stale.
COMBAT = true
SlashCmdList.WICK_WICKSSTANCESANDTHINGS("bind Intercept")
check(tostring(smart:GetAttribute("macrotext")):find("Intercept") == nil,
    "nothing is written to a secure button in combat")
COMBAT = false
S.fire("PLAYER_REGEN_ENABLED")
check(tostring(smart:GetAttribute("macrotext")):find("%[stance:3%] Intercept") ~= nil,
    "and it catches up when combat ends: " .. tostring(smart:GetAttribute("macrotext")):gsub("\n", " | "))
SlashCmdList.WICK_WICKSSTANCESANDTHINGS("bind Charge")

-- A stance the character has not learned reads as unlearned, not missing.
S.STANCE_COUNT = 1
sstrip.__scripts.OnShow(sstrip)
check(SA.kit ~= nil, "stances has a kit")
S.STANCE_COUNT = 3

S.CHAT = {}
SlashCmdList.WICK_WICKSSTANCESANDTHINGS("status")
local sline = table.concat(S.CHAT, " | ")
check(#S.CHAT >= 3, "/wst status prints")
check(sline:find("Battle Stance") ~= nil, "and names the stance you are in: " .. sline:sub(1, 90))

try("stances strip toggle", function() WicksStancesAndThings_Toggle(); WicksStancesAndThings_Toggle() end)
try("stances kit", function() SlashCmdList.WICK_WICKSSTANCESANDTHINGS("kit") end)
if SA then
    local srows = SA.kit.checklist:Evaluate()
    check(#srows == 4, "stances checklist 4 rows, got " .. #srows)
    check(srows[2].state == "ok", "in a stance reads ok while in one: " .. tostring(srows[2].state))
    check(SA.cooldowns ~= nil, "stances has a cooldown bar")

    -- The shield row reads the Dialect table, not the client's bare
    -- returns, so a shield in the off hand has to read ok. A dagger
    -- there is not a tank, and the row says nothing.
    local BUCKLER, OFFDAGGER = 1203, 2092
    S.ITEMS = S.ITEMS or {}
    S.ITEMS[BUCKLER]   = { equipLoc = "INVTYPE_SHIELD",          classID = 4, subClassID = 6, name = "Aegis of the Scarlet Commander" }
    S.ITEMS[OFFDAGGER] = { equipLoc = "INVTYPE_WEAPONOFFHAND",   classID = 2, subClassID = 15, name = "Worn Dagger" }
    S.EQUIPPED_IDS = S.EQUIPPED_IDS or {}
    local keep16, keep17 = S.EQUIPPED_IDS[16], S.EQUIPPED_IDS[17]
    S.EQUIPPED_IDS[16], S.EQUIPPED_IDS[17] = 2092, BUCKLER
    srows = SA.kit.checklist:Evaluate()
    check(srows[4].label == "Shield for Defensive", "fourth row is the shield row: " .. tostring(srows[4].label))
    check(srows[4].state == "ok", "a shield in the off hand reads ok: " .. tostring(srows[4].state))
    S.EQUIPPED_IDS[17] = OFFDAGGER
    srows = SA.kit.checklist:Evaluate()
    check(srows[4].state == "unknown", "a dagger there does not apply: " .. tostring(srows[4].state))
    S.EQUIPPED_IDS[16], S.EQUIPPED_IDS[17] = keep16, keep17
    S.ITEMS[BUCKLER], S.ITEMS[OFFDAGGER] = nil, nil
end
S.STANCE, S.STANCE_COUNT = 0, 0

io.write("== Seals and Things ==\n")
CLASS = "PALADIN"
S.STANCE, S.STANCE_COUNT = 0, 0
local keepBook = S.SPELLBOOK
-- A paladin in the thirties: three seals, Judgement, one blessing, one
-- aura. The order is the book's order, which is learning order.
S.SPELLBOOK = {
    { "Holy Light", "Rank 4", "Interface\\Icons\\HolyLight", 1026 },
    { "Seal of Righteousness", "Rank 3", "Interface\\Icons\\SoR", 20154 },
    { "Seal of the Crusader", "Rank 2", "Interface\\Icons\\SotC", 21082 },
    { "Judgement", "", "Interface\\Icons\\Judgement", 20271 },
    { "Blessing of Might", "Rank 2", "Interface\\Icons\\BoM", 19835 },
    { "Devotion Aura", "Rank 3", "Interface\\Icons\\Devo", 10290 },
    { "Seal of Command", "Rank 1", "Interface\\Icons\\SoC", 20375 },
}
S.AURAS = { "Seal of Righteousness", "Blessing of Might", "Devotion Aura" }
-- A two-hander in hand, a mace and a shield in the first bag.
local HAMMER, MACE, SHIELD, BIG = 11684, 2080, 1203, 17182
S.ITEMS = S.ITEMS or {}
S.ITEMS[HAMMER] = { equipLoc = "INVTYPE_2HWEAPON", classID = 2, subClassID = 5, name = "Ironfoe" }
S.ITEMS[MACE]   = { equipLoc = "INVTYPE_WEAPON",   classID = 2, subClassID = 4, name = "Verigan's Fist" }
S.ITEMS[SHIELD] = { equipLoc = "INVTYPE_SHIELD",   classID = 4, subClassID = 6, name = "Aegis of the Scarlet Commander" }
S.ITEMS[BIG]    = { equipLoc = "INVTYPE_2HWEAPON", classID = 2, subClassID = 8, name = "Sulfuras" }
S.EQUIPPED_IDS = { [16] = HAMMER }
S.SLOT_ITEMS[1] = { { id = MACE, count = 1 }, { id = SHIELD, count = 1 } }

local SNS = S.loadAddon(ADDONS_DIR .. "/WicksSealsAndThings", "WicksSealsAndThings")
S.fire("ADDON_LOADED", "WicksSealsAndThings")
S.fire("PLAYER_LOGIN")
dumpErrors()
local LENTRY = WickCore.Launcher.entries.WicksSealsAndThings
local LA = LENTRY and LENTRY.addon
check(LA ~= nil, "seals launcher registered")
local lstrip = _G.WicksSealsStrip
check(lstrip ~= nil and lstrip:IsShown(), "seal strip shown for a paladin")
check(_G.WicksSealsButton1 == nil and _G.WicksSealsJudgeButton == nil, "no key per seal and no Judgement key: one seal key")
local function cycleText() return tostring(_G.WicksSealsCycleButton:GetAttribute("macrotext")) end
check(cycleText():find("/castsequence reset=27/combat Seal of the Crusader, Seal of Righteousness", 1, true) ~= nil,
    "the seal key goes Crusader, fighting seal, back to the Crusader after 27 quiet seconds or combat: " .. cycleText():gsub("\n", " | "))
SlashCmdList.WICK_WICKSSEALSANDTHINGS("seal command")
check(cycleText():find("Seal of the Crusader, Seal of Command", 1, true) ~= nil, "/wsl seal picks the fighting seal")
SlashCmdList.WICK_WICKSSEALSANDTHINGS("seal auto")
SlashCmdList.WICK_WICKSSEALSANDTHINGS("cycle Seal of Command, Seal of Righteousness")
check(cycleText():find("Seal of Command, Seal of Righteousness", 1, true) ~= nil, "a cycle of your own: " .. cycleText():gsub("\n", " | "))
SlashCmdList.WICK_WICKSSEALSANDTHINGS("cycle reset 20")
check(cycleText():find("reset=20/combat", 1, true) ~= nil, "and your own quiet time")
SlashCmdList.WICK_WICKSSEALSANDTHINGS("cycle reset 27")
SlashCmdList.WICK_WICKSSEALSANDTHINGS("cycle off")
check(cycleText() == "", "cycle off empties the key")
SlashCmdList.WICK_WICKSSEALSANDTHINGS("cycle auto")
check(cycleText():find("Seal of the Crusader, Seal of Righteousness", 1, true) ~= nil, "auto brings the default back")

local function blessText() return tostring(_G.WicksSealsBlessButton:GetAttribute("macrotext")) end
check(blessText():find("/cast [help,nodead][@player] Blessing of Might", 1, true) ~= nil,
    "the blessing key casts the blessing on you, friend first: " .. blessText():gsub("\n", " | "))
S.SPELLBOOK[#S.SPELLBOOK + 1] = { "Blessing of Wisdom", "Rank 1", "Interface\\Icons\\BoW", 19742 }
S.fire("SPELLS_CHANGED")
SlashCmdList.WICK_WICKSSEALSANDTHINGS("bless wisdom")
check(blessText():find("Blessing of Wisdom", 1, true) ~= nil, "/wsl bless picks a blessing by part of its name")
SlashCmdList.WICK_WICKSSEALSANDTHINGS("bless auto")
check(blessText():find("Blessing of Might", 1, true) ~= nil, "and auto follows the one on you again")

io.write("== the two swap keys ==\n")
local function twoText() return tostring(_G.WicksSealsTwoHandButton:GetAttribute("macrotext")) end
local function boardText() return tostring(_G.WicksSealsShieldButton:GetAttribute("macrotext")) end
check(twoText() == "/equipslot 16 item:" .. HAMMER, "the two-hander key names the hammer: " .. twoText())
check(boardText() == ("/equipslot 16 item:%d\n/equipslot 17 item:%d"):format(MACE, SHIELD),
    "the shield key names the mace then the shield: " .. boardText():gsub("\n", " | "))
local faces = SNS.swap:Faces()
check(faces.twoHand and faces.twoHand.live == true, "the two-hander is marked as on")
check(faces.shield and faces.shield.live == false, "and the shield set is not")

-- The shield key pressed: the hands change and the hammer goes to a bag.
S.EQUIPPED_IDS = { [16] = MACE, [17] = SHIELD }
S.SLOT_ITEMS[1] = { { id = HAMMER, count = 1 } }
S.fire("PLAYER_EQUIPMENT_CHANGED")
faces = SNS.swap:Faces()
check(faces.shield.live == true and faces.twoHand.live == false, "after the swap the shield set is the live one")
local sets = LA.db.char.sets
check(sets.oneHand == MACE and sets.shield == SHIELD and sets.twoHand == HAMMER, "every piece worn is remembered")

-- A bigger two-hander turns up in the bag. The one you chose by wearing
-- it still wins, until you pin the new one.
S.SLOT_ITEMS[1] = { { id = HAMMER, count = 1 }, { id = BIG, count = 1 } }
S.fire("BAG_UPDATE_DELAYED")
check(twoText():find("item:" .. HAMMER, 1, true) ~= nil, "the remembered two-hander wins over a stranger in the bag: " .. twoText())
SlashCmdList.WICK_WICKSSEALSANDTHINGS("pin 2h " .. BIG)
check(twoText():find("item:" .. BIG, 1, true) ~= nil, "a pin wins over the memory: " .. twoText())
SlashCmdList.WICK_WICKSSEALSANDTHINGS("pin 2h clear")
check(twoText():find("item:" .. HAMMER, 1, true) ~= nil, "and clearing the pin goes back to the memory")

-- Nothing is written to a secure button in combat, and the strip
-- catches up the moment the fight ends.
COMBAT = true
S.EQUIPPED_IDS = { [16] = HAMMER }
S.SLOT_ITEMS[1] = { { id = MACE, count = 1 }, { id = SHIELD, count = 1 }, { id = BIG, count = 1 } }
S.fire("PLAYER_EQUIPMENT_CHANGED")
check(SNS.swap:Faces().twoHand.live == true, "the mark follows your hands even in combat")
SlashCmdList.WICK_WICKSSEALSANDTHINGS("seal command")
check(cycleText():find("Seal of Command", 1, true) == nil, "nothing is written to a secure button in combat")
COMBAT = false
S.fire("PLAYER_REGEN_ENABLED")
check(cycleText():find("Seal of Command", 1, true) ~= nil, "and it catches up when combat ends: " .. cycleText():gsub("\n", " | "))
SlashCmdList.WICK_WICKSSEALSANDTHINGS("seal auto")

-- The checklist grows as the spells that need a row are learned.
local lrows = LA.kit.checklist:Evaluate()
check(#lrows == 3, "seals checklist: three rows before Greater Blessings and Divine Intervention, got " .. #lrows)
check(lrows[1].state == "ok" and lrows[2].state == "ok" and lrows[3].state == "ok",
    ("seal, blessing and aura read ok: %s %s %s"):format(lrows[1].state, lrows[2].state, lrows[3].state))
LA.db.profile.wantFury = true
S.SPELLBOOK[#S.SPELLBOOK + 1] = { "Righteous Fury", "", "Interface\\Icons\\RF", 25780 }
S.SPELLBOOK[#S.SPELLBOOK + 1] = { "Greater Blessing of Might", "Rank 1", "Interface\\Icons\\GBoM", 25782 }
S.fire("SPELLS_CHANGED")
lrows = LA.kit.checklist:Evaluate()
check(#lrows == 5, "Symbols of Kings and Righteous Fury join once their spells are known: " .. #lrows)
LA.db.profile.wantFury = false

S.CHAT = {}
SlashCmdList.WICK_WICKSSEALSANDTHINGS("status")
local lline = table.concat(S.CHAT, " | ")
check(#S.CHAT >= 5, "/wsl status prints")
check(lline:find("Seal of Righteousness", 1, true) ~= nil, "and names the seal on you: " .. lline:sub(1, 120))
try("seals strip toggle", function() WicksSealsAndThings_Toggle(); WicksSealsAndThings_Toggle() end)
try("seals kit", function() SlashCmdList.WICK_WICKSSEALSANDTHINGS("kit") end)
check(LA.cooldowns ~= nil, "seals has a cooldown bar")

S.AURAS = nil
S.SPELLBOOK = keepBook
S.EQUIPPED_IDS = nil
S.SLOT_ITEMS[1] = nil

io.write("== Trade Hall ==\n")
CLASS = "HUNTER"
local THNS = S.loadAddon(ADDONS_DIR .. "/WicksTradeHall", "WicksTradeHall")
S.fire("ADDON_LOADED", "WicksTradeHall")
S.fire("PLAYER_LOGIN")
dumpErrors()
local THENTRY = WickCore.Launcher.entries.WicksTradeHall
local THA = THENTRY and THENTRY.addon
check(THA ~= nil and THA.enabled, "trade hall registered and enabled")
check(_G.WicksTradeHallBar ~= nil and _G.WicksTradeHallBar:IsShown(), "the session bar is up")

local Lg, P = THNS.Ledger, THNS.Prices

-- Money is plain on this client, so the gold delta is ordinary
-- arithmetic. The purse is driven by hand here.
local realMoney = GetMoney
local purse = 100000
GetMoney = function() return purse end

check(Lg:Start(), "a session starts")
check(Lg.active and Lg.startMoney == 100000, "and takes the purse as its starting point")
check(not Lg:Start(), "starting twice does nothing")

purse = 112345
S.fire("PLAYER_MONEY")
check(Lg.goldDelta == 12345, "gold earned is the difference: " .. tostring(Lg.goldDelta))
check(Lg.totalCopper == 12345, "and the total follows it")

-- A grey collapses into one Junk row however many drop; anything else
-- is its own line.
S.ITEMS = S.ITEMS or {}
S.ITEMS[2589] = { name = "Linen Cloth", quality = 1, sellPrice = 15 }
S.ITEMS[3300] = { name = "Rabbit's Foot", quality = 0, sellPrice = 40 }
check(Lg:AddLoot("You receive loot: |cff9d9d9d|Hitem:3300::::::::20:::::::::|h[Rabbit's Foot]|h|r."), "a grey is taken")
Lg:AddLoot("You receive loot: |cff9d9d9d|Hitem:3300::::::::20:::::::::|h[Rabbit's Foot]|h|r x3.")
check(Lg.loot.junk ~= nil and Lg.loot.junk.count == 4, "greys collapse into one Junk row: " .. tostring(Lg.loot.junk and Lg.loot.junk.count))
check(Lg.loot.junk.copper == 160, "carrying the running total, not a unit price: " .. tostring(Lg.loot.junk.copper))
Lg:AddLoot("You receive loot: |cffffffff|Hitem:2589::::::::20:::::::::|h[Linen Cloth]|h|r x5.")
check(Lg.loot["2589"] ~= nil and Lg.loot["2589"].count == 5, "a white gets its own line")
check(Lg.totalCopper == 12345 + 160 + 15 * 5, "and the total counts each by its own rule: " .. tostring(Lg.totalCopper))

-- An item the client cannot price counts as nothing, and says so.
S.UNKNOWN = S.UNKNOWN or {}
S.UNKNOWN[11111] = true
Lg:AddLoot("You receive loot: |cffffffff|Hitem:11111::::::::20:::::::::|h[Something]|h|r.")
check(Lg.loot["11111"].source == "unknown", "an unpriceable item is marked, not guessed at")

local conf, known, total = P:Confidence(Lg.loot)
-- Three kinds, not four: the two greys merged into one junk row.
check(known == 2 and total == 3, "and the confidence says how much of the total is real: " .. known .. "/" .. total)

-- It has to put the question, not just wait for the answer. The ledger
-- listened for GET_ITEM_INFO_RECEIVED and repriced on it from the start,
-- but nothing ever asked the client to go and fetch the item, so for a
-- fresh drop the answer never came and the loot sat at zero all session.
S.UNCACHED = S.UNCACHED or {}
S.UNCACHED[22222] = true
S.ITEMS = S.ITEMS or {}
S.REQUESTED = 0
P:ForgetAsked()
Lg:AddLoot("You receive loot: |cffffffff|Hitem:22222::::::::20:::::::::|h[Unmet Thing]|h|r.")
if MODERN then
    check(S.REQUESTED >= 1, "an item the client has not met is asked for, got " .. tostring(S.REQUESTED))
else
    -- The older dialect has no request call: asking for the item info is
    -- itself what makes the client go and fetch it.
    check(S.REQUESTED == 0, "the older dialect has nothing to ask with, and does not pretend to")
end
local askedOnce = S.REQUESTED
P:Get(22222)
check(S.REQUESTED == askedOnce, "and asked once, not on every look")

-- When the answer arrives the ledger reprices off it, which is the half
-- that already worked.
S.ITEMS[22222] = { name = "Unmet Thing", sellPrice = 500, icon = 1, quality = 1 }
S.fire("GET_ITEM_INFO_RECEIVED", 22222)
check(Lg.loot["22222"] and Lg.loot["22222"].source == "vendor",
    "and it is priced once the client answers: " .. tostring(Lg.loot["22222"] and Lg.loot["22222"].source))

-- When the server answers late it is repriced, not left wrong.
S.UNKNOWN[11111] = nil
S.ITEMS[11111] = { name = "Something", quality = 2, sellPrice = 500 }
check(Lg:Reprice(), "a late arrival is repriced")
check(Lg.loot["11111"].copper == 500 and Lg.loot["11111"].source == "vendor", "with the real price")

-- A reload must not lose the run.
local carried = Lg.totalCopper
Lg.Persist()
Lg.active, Lg.totalCopper, Lg.loot = false, 0, {}
check(Lg:Resume(), "a saved session resumes")
check(Lg.totalCopper == carried, "with its total intact: " .. tostring(Lg.totalCopper))

check(Lg:Stop(), "the session stops")
check(#Lg:History() == 1, "and lands in history")
Lg:Start(); Lg:Stop()
check(#Lg:History() == 1, "a session that earned nothing is not filed")

-- A running total is not a setting: the macro store must not carry it,
-- or a long night of looting crowds out the settings that matter.
check(THA.opts.storeExclude ~= nil and THA.opts.storeExclude[1] == "char",
    "the session is excluded from the macro store")

-- The board reads the trade channel. Reading chat is not restricted on
-- this client, only sending, so this is the piece that ports whole.
local Bd = THNS.Board
S.CHANNELS = { [1] = "General", [2] = "Trade - City", [5] = "LookingForGroup" }
GetChannelList = function() return 1, "General", false, 2, "Trade - City", false, 5, "LookingForGroup", false end
Bd:RebuildChannels()
check(Bd:Watching(2) == true, "a channel named Trade is watched")
check(Bd:Watching(1) == false and Bd:Watching(5) == false, "General and LookingForGroup are not")

Bd:Clear()
check(Bd:Handle("WTS [Copper Bar] x20 cheap pst", "Seller-Realm", 2), "a sell advert is taken")

-- A chat payload reaches a tainted addon as a secret string while the
-- client's restrictions are up. This is what spammed the chat frame in
-- Wailing Caverns: the board compared the message to the empty string
-- and the client refused. Nothing here can read a secret, so the line
-- has to be dropped quietly rather than erroring on every word spoken.
--
-- Modern only. TBC has no issecretvalue and no secrets to guard
-- against, so firing one at it would be testing a state that cannot
-- happen rather than the addon's handling of one that can.
if MODERN then
    local before = #Bd.listings
    local okSecret, whySecret = pcall(function()
        Bd:Handle(S.SECRET, "Somebody", 2)
    end)
    check(okSecret, "a secret chat line does not raise: " .. tostring(whySecret))
    check(#Bd.listings == before, "and is not listed, since it cannot be read")

    -- The author can be secret on its own.
    local okAuthor = pcall(function() Bd:Handle("WTS something", S.SECRET, 2) end)
    check(okAuthor, "a secret author does not raise either")
    check(#Bd.listings == before, "and is not listed")

    -- The ledger reads loot lines the same way. It needs a running
    -- session or AddLoot returns before it touches the text, which
    -- would make this check say nothing.
    local wasActive = Lg.active
    Lg.active = true
    local okLoot, whyLoot = pcall(function() Lg:AddLoot(S.SECRET) end)
    check(okLoot, "a secret loot line does not raise: " .. tostring(whyLoot))
    Lg.active = wasActive
end
check(Bd.listings[1] and Bd.listings[1].category == "WTS", "and read as selling: " .. tostring(Bd.listings[1] and Bd.listings[1].category))
check(Bd.listings[1].name == "Seller", "with the realm stripped off the name")
check(not Bd:Handle("WTS [Copper Bar] x20 cheap pst", "Seller-Realm", 2), "the same person repeating it is one listing, not two")
check(#Bd.listings == 1, "so the board still has one: " .. #Bd.listings)

check(Bd:Handle("WTB arcanite bar paying well", "Buyer", 2), "a buy advert is taken")
check(Bd.listings[1].category == "WTB", "and read as buying: " .. tostring(Bd.listings[1].category))
check(Bd:Handle("Free enchants at the bank, tips welcome", "Enchanter", 2), "an enchanter is taken")
check(Bd.listings[1].category == "ENCHANT", "and read as enchanting: " .. tostring(Bd.listings[1].category))

-- Both of these landed in Misc on the live board, which is what sent me
-- back to the rule. An advert with no service word is still an advert,
-- and someone looking for an enchant belongs on the enchanting shelf
-- next to the person offering one.
check(Bd:Handle("Enchanting in Undercity", "Ench2", 2), "a bare enchant advert is taken")
check(Bd.listings[1].category == "ENCHANT", "and is enchanting, not misc: " .. tostring(Bd.listings[1].category))
check(Bd:Handle("LF agility to gloves enchant", "Ench3", 2), "someone looking for an enchant is taken")
check(Bd.listings[1].category == "ENCHANT", "and is enchanting too: " .. tostring(Bd.listings[1].category))

-- And the mistake in the other direction, which the fix nearly made: a
-- slot name on its own must not pull a sale into enchanting.
check(Bd:Handle("WTS gloves and boots cheap", "Vendor", 2), "a sale naming armour slots is taken")
check(Bd.listings[1].category == "WTS", "and stays selling: " .. tostring(Bd.listings[1].category))
check(Bd:Handle("Free crusader at the bank, tips welcome", "Ench4", 2), "an enchant named without the word is taken")
check(Bd.listings[1].category == "ENCHANT", "and reads as enchanting: " .. tostring(Bd.listings[1].category))
check(Bd:Handle("Portals to Stormwind, 5s, pst", "Mage", 2), "a portal advert is taken")
check(Bd.listings[1].category == "TRAVEL", "and read as travel: " .. tostring(Bd.listings[1].category))

-- Straight off the live board: this one landed in Misc, because a taxi
-- was pooled with the city names and the rule wanted a mage or a tip
-- alongside them.
check(Bd:Handle("< Taxi Service > Undercity , Thunder Bluff 50silver", "Taxi", 2), "a taxi advert is taken")
check(Bd.listings[1].category == "TRAVEL", "and is travel, not misc: " .. tostring(Bd.listings[1].category))
check(Bd:Handle("WTS Sum to ThunderBluff", "Summoner", 2), "a summon for sale is taken")
check(Bd.listings[1].category == "TRAVEL",
    "and shelved by what it is, not which way it points: " .. tostring(Bd.listings[1].category))

-- A city name on its own is not travel: half of trade chat says where it
-- is standing.
check(Bd:Handle("WTS Copper Ore in Orgrimmar, cheap", "Miner", 2), "a sale that mentions a city is taken")
check(Bd.listings[1].category == "WTS", "and stays selling: " .. tostring(Bd.listings[1].category))


-- A group advert is not trade, and the blacklist runs before the rules.
check(not Bd:Handle("LFM Deadmines need tank and healer", "Leader", 2), "a group advert is not a listing")
check(not Bd:Handle("Guild recruiting for raids, apply within", "Recruiter", 2), "nor is guild recruitment")
-- Unless it says outright that it is selling.
check(Bd:Handle("WTS Deadmines boost, raid geared", "Booster", 2), "but a boost being sold is")

-- Nothing from a channel we do not watch.
local before = #Bd.listings
check(not Bd:Handle("WTS everything cheap", "Spammer", 5), "a channel we do not watch is ignored")
check(#Bd.listings == before, "and nothing lands")

-- The board reads as a board, not a chat log. The TBC one gave a listing
-- a badge, the icon of the first item it named, the player, the message
-- and an age that faded; the port had two labels, which is why it was a
-- step down. Filtering and search came back with them.
Bd:Clear()
Bd:Handle("WTS |cffffffff|Hitem:2589::::::::20:::::::::|h[Linen Cloth]|h|r x20 cheap", "Seller-Realm", 2)
Bd:Handle("Enchanting in Undercity", "Ench-Realm", 2)
Bd:Handle("WTB arcanite bar paying well", "Buyer-Realm", 2)
check(#Bd.listings == 3, "three listings to sort through, got " .. #Bd.listings)

local link, itemID = Bd:FirstItem(Bd.listings[3].raw)
check(link ~= nil and itemID == 2589, "the item a listing names is found: " .. tostring(itemID))
check(Bd:FirstItem("no items here") == nil, "and a listing naming none says so")

check(#Bd:Filter("WTS") == 1, "filtering by category narrows it, got " .. #Bd:Filter("WTS"))
check(#Bd:Filter(nil) == 3, "and no category is everything")
check(#Bd:Filter(nil, "arcanite") == 1, "search finds it in the message")
check(#Bd:Filter(nil, "ench") == 1, "and in the player name or the message either way")
check(#Bd:Filter("WTS", "arcanite") == 0, "the two narrow together, not apart")
check(#Bd:Filter(nil, "") == 3, "an empty search is not a filter")

-- An item link reads as the item name, not the markup.
Bd:Clear()
Bd:Handle("WTS |cffffffff|Hitem:2589::::::::20:::::::::|h[Linen Cloth]|h|r x20", "Tailor", 2)
check(Bd.listings[1] and Bd.listings[1].message:find("Linen Cloth", 1, true) ~= nil,
    "a link reads as the item name: " .. tostring(Bd.listings[1] and Bd.listings[1].message))
check(Bd.listings[1].message:find("|c") == nil, "with no markup left in it")

-- A long advert ran off the panel and over whatever was behind it.
-- The text is bounded by where the age begins and never wraps.
THNS.UI:Build()
THNS.UI.panel:Show()
THNS.UI:Select("board")
local prow = THNS.UI.panel.rows[1]
check(prow ~= nil, "a board row was drawn")
if prow then
    check(prow.left.__wordWrap == false, "a listing is one line, never wrapped")
    local bounded = false
    for _, pt in ipairs(prow.left.__points or {}) do if pt[1] == "RIGHT" then bounded = true end end
    check(bounded, "and is bounded on the right so it cannot overflow")
end
THNS.UI.panel:Hide()

-- Anything nobody repeats ages off.
Bd.listings[1].lastSeen = time() - (25 * 60)
check(Bd:Prune() == 1, "a listing nobody repeated for twenty minutes drops off")
check(#Bd.listings == 0, "leaving the board empty")

-- The bar has a control. A tracker you cannot start is an ornament.
local bar = _G.WicksTradeHallBar
check(bar.go ~= nil, "the session bar has a start button")
-- Drawn, not typed: this client's font has no play or stop glyph and
-- the bar showed an empty box.
check(bar.go.rows ~= nil and #bar.go.rows == 8, "built from textures rather than a character")
bar.go:SetShape(false, { 0.31, 0.78, 0.47 })
local widths = {}
for i, t in ipairs(bar.go.rows) do widths[i] = t.__w end
check(widths[1] < widths[4] and widths[4] > widths[8], "stopped, it is a triangle: " .. table.concat(widths, ","))
bar.go:SetShape(true, { 0.88, 0.29, 0.29 })
local same = true
for _, t in ipairs(bar.go.rows) do if t.__w ~= bar.go.rows[1].__w then same = false end end
check(same, "running, it is a square")
local wasActive = Lg.active
bar.go.__scripts.OnClick(bar.go)
check(Lg.active ~= wasActive, "clicking it starts or stops the session")
if Lg.active then bar.go.__scripts.OnClick(bar.go) end
check(not Lg.active, "and clicking again stops it")

S.CHAT = {}
SlashCmdList.WICK_WICKSTRADEHALL("status")
check(#S.CHAT >= 2, "/wth status prints")
try("trade hall window", function() WicksTradeHall_Toggle(); WicksTradeHall_Toggle() end)
try("trade board tab", function() THNS.UI:Select("board"); THNS.UI:Select("ledger") end)
GetMoney = realMoney
S.ITEMS[2589], S.ITEMS[3300], S.ITEMS[11111] = nil, nil, nil

io.write("== Comforts ==\n")

-- Straight off the toc, so a module added to the addon is tested here
-- without anyone remembering to add it twice.
local CNS = S.loadAddon(ADDONS_DIR .. "/WicksComforts", "WicksComforts")
S.fire("ADDON_LOADED", "WicksComforts")
S.fire("PLAYER_LOGIN")
dumpErrors()
local CENTRY = WickCore.Launcher.entries.WicksComforts
local CA = CENTRY and CENTRY.addon
check(CA ~= nil, "comforts registered")
if CA then
    local db = CA.db.profile
    -- Nothing may change on a fresh install.
    local anyOn = false
    for _, v in pairs(db) do if v == true then anyOn = true end end
    local onCount = 0
    for k, v in pairs(db) do if v == true then onCount = onCount + 1 end end
    check(onCount == 1 and db.clientFixes == true, "only the client-error fix starts on")
    -- The group finder is load on demand. Claiming its frame name before
    -- it has loaded takes the name away from Blizzard, and the who panel
    -- then opens with its close button and side tabs drawn and nothing in
    -- the middle. So: nothing until their addon has actually loaded.
    check(_G.LFGWhoListFrame == nil, "no stub while the group finder has not loaded")
    S.LOADED["Blizzard_GroupFinder_VanillaStyle"] = true
    S.fire("ADDON_LOADED", "Blizzard_GroupFinder_VanillaStyle")
    check(_G.LFGWhoListFrame ~= nil and _G.LFGWhoListFrame.wicksStub,
        "once it has loaded and still has no frame, the stub stands in")

    -- And if Blizzard does build one, theirs is left alone.
    CNS.modules.fixes.stubbedWhoList = nil
    _G.LFGWhoListFrame = S.newMock("Frame")
    CNS.modules.fixes:Apply()
    check(not _G.LFGWhoListFrame.wicksStub, "a real frame from Blizzard is never replaced")
    local report = table.concat(CNS.modules.fixes:WhoReport(), " | ")
    check(report:find("Blizzard's") ~= nil, "and the report says whose it is: " .. report:sub(1, 80))
    _G.LFGWhoListFrame = nil
    S.LOADED["Blizzard_GroupFinder_VanillaStyle"] = nil
    CNS.modules.fixes.stubbedWhoList = nil

    local frames = CNS.modules.frames
    S.UNITS = { target = true, player = true }

    -- Health bars. Two earlier attempts are encoded here as things that
    -- must not happen again. Hooking UnitFrameHealthBar_Update never
    -- fired, because Blizzard reaches it through a local. Setting their
    -- lockColor did fire, and put a tainted value in their table, which
    -- made their own status text formatter illegal the next time it
    -- compared secret health: every target change threw, blaming us.
    --
    -- So the test is not "is the bar green or blue". It is "did we leave
    -- their frame exactly as we found it, and is there a bar of ours on
    -- top carrying the colour".
    CLASS = "PALADIN"
    _G.TargetFrame = S.newMock("Frame")
    local theirs = S.newMock("StatusBar")
    theirs.unit = "target"
    theirs:SetStatusBarColor(0, 1, 0)
    theirs:SetMinMaxValues(0, 100)
    theirs:SetValue(70)
    theirs:Show()
    _G.TargetFrame.healthbar = theirs

    -- Anything we write into their table is a tainted value waiting for
    -- their code to read it, so record what is in there to begin with.
    local before = {}
    for k, v in pairs(theirs) do before[k] = v end

    db.classColorHealth = false
    frames:Apply()
    check(theirs.__color[1] == 0 and theirs.__color[2] == 1,
        "off by default, their bar is left the green they painted it")

    db.classColorHealth = true
    frames:Apply()
    local pal = RAID_CLASS_COLORS.PALADIN
    local ov = frames.OverlayFor(theirs)
    check(ov ~= nil and ov:IsShown(), "switched on, a bar of ours appears over theirs")
    check(math.abs(ov.__color[1] - pal.r) < 0.01,
        "and it carries the class colour: " .. tostring(ov.__color[1]))
    check(theirs.__color[1] == 0 and theirs.__color[2] == 1,
        "while their own bar is still the green it always was")
    -- The hue follows the class colour set WickCore is on. Classic paladin
    -- pink is F58CBA where the client table says F48CBA: one step of red.
    check(tostring(ov.__statusTex or ""):find("UI%-StatusBar") ~= nil,
        "the overlay draws with Blizzard's shaded bar texture, not a flat fill")
    WickCore.Chrome.classColorSet = "classic"
    frames:Apply()
    check(math.abs(ov.__color[1] - 0xF5 / 255) < 0.002, "switching WickCore to the Classic-era set changes the bar: " .. tostring(ov.__color[1]))
    WickCore.Chrome.classColorSet = "client"
    frames:Apply()
    check(math.abs(ov.__color[1] - pal.r) < 0.01, "and back to the client set restores it")

    -- The whole point. One new field on their frame is enough to throw
    -- inside TextStatusBar the next time it formats secret health.
    -- Looking a method up on the mock leaves a stand-in behind, which a
    -- real widget does not do, so those do not count. Anything else
    -- appearing is a value of ours sitting in their table waiting to
    -- taint the next thing that reads it.
    local function lookupArtifact(k, v)
        if type(v) == "function" then return true end
        return type(v) == "table" and rawget(v, "__parent") == theirs
    end
    local added = {}
    for k, v in pairs(theirs) do
        if before[k] == nil and not lookupArtifact(k, v) then added[#added + 1] = tostring(k) end
    end
    check(#added == 0, "and nothing of ours was written into their table: "
        .. table.concat(added, ", "))

    -- Ours has to track theirs, and the numbers involved are secret, so
    -- they are passed across without ever being looked at.
    theirs:SetValue(30)
    frames:Tick()
    check(ov.__value == 30, "ours follows theirs when the health moves: " .. tostring(ov.__value))
    theirs:SetMinMaxValues(0, 250)
    frames:Tick()
    check(ov.__max == 250, "and follows the scale as well")

    -- A creature has no class, so there is nothing of ours to show.
    S.IS_PLAYER = { target = false }
    frames:Apply()
    check(not ov:IsShown(), "a creature gets no overlay")
    S.IS_PLAYER = nil

    db.classColorHealth = false
    frames:Apply()
    check(not ov:IsShown(), "and switching off takes ours away")
    check(theirs.__color[2] == 1, "leaving theirs exactly as it was")

    -- Nothing coloured means nothing to poll.
    check(frames.driver ~= nil and not frames.driver:IsShown(),
        "with nothing to follow, the ticker stops")
    db.classColorHealth = true
    frames:Apply()
    check(frames.driver:IsShown(), "and runs again when there is")
    db.classColorHealth = false
    frames:Apply()

    -- The party and raid setting is a console variable and only that.
    -- Asking CompactRaidFrameContainer to refresh from our execution
    -- leaves a tainted needsUpdate on every compact frame, and their
    -- OnUpdate then compares a secret colour in our name.
    local poked = false
    _G.CompactRaidFrameContainer = { TryUpdate = function() poked = true end }
    check(frames:SetRaidClassColor(true), "the raid frame class colour setting is written")
    check(S.CVARS["raidFramesDisplayClassColor"] == "1", "as the game's own variable")
    check(not poked, "and their container is never asked to refresh by us")
    _G.CompactRaidFrameContainer = nil

    -- Moving frames is Edit Mode's job, not ours.
    _G.EditModeManagerFrame = S.newMock("Frame")
    _G.EditModeManagerFrame.CanEnterEditMode = function() return true end
    _G.ShowUIPanel = function(f) S.SHOWN_PANEL = f end
    check(frames:OpenEditMode(), "the Edit Mode button opens Blizzard's own")
    check(S.SHOWN_PANEL == _G.EditModeManagerFrame, "and opens the right frame")

    -- Never their update. Health is secret and their formatter compares
    -- it, so asking them to redraw throws in our name.
    local called = 0
    local realUpdate = UnitFrameHealthBar_Update
    UnitFrameHealthBar_Update = function(...) called = called + 1 return realUpdate(...) end
    db.classColorHealth = true
    frames:Apply()
    frames:Tick()
    UnitFrameHealthBar_Update = realUpdate
    check(called == 0, "repainting never calls Blizzard's update, which would run tainted")
    db.classColorHealth = false
    frames:Apply()

    -- ---- Quests -------------------------------------------------
    local quests = CNS.modules.quests
    S.QUEST = {}
    quests:Accept()
    check((S.QUEST.accepted or 0) == 0, "a quest is not accepted for you until you ask")

    db.autoAcceptQuests = true
    quests:Accept()
    check(S.QUEST.accepted == 1, "switched on, the quest is accepted")

    -- Shift is the escape hatch: whatever is on, the dialogs come back.
    local realShift = IsShiftKeyDown
    IsShiftKeyDown = function() return true end
    quests:Accept()
    check(S.QUEST.accepted == 1, "holding shift hands the dialog back")
    IsShiftKeyDown = realShift

    db.autoTurnInQuests = true
    S.QUEST.completable = false
    quests:Progress()
    check((S.QUEST.completeAsked or 0) == 0, "a quest you have not finished is left alone")
    S.QUEST.completable = true
    quests:Progress()
    check(S.QUEST.completeAsked == 1, "one you have finished asks for the reward screen")

    -- The one thing that must never be automatic.
    S.QUEST.choices = 3
    quests:Complete()
    check(S.QUEST.rewarded == nil, "a choice of rewards is never picked for you")
    S.QUEST.choices = 1
    quests:Complete()
    check(S.QUEST.rewarded == 1, "a single reward is taken")
    S.QUEST.choices = 0
    S.QUEST.rewarded = nil
    quests:Complete()
    check(S.QUEST.rewarded == 0, "and no reward at all still hands the quest in")

    -- Gossip npcs hide the quest behind a line of dialogue.
    S.QUEST.available = { { questID = 4242 } }
    quests:Gossip()
    check(S.QUEST.pickedAvailable == 4242, "the one quest on offer is picked out of the gossip")
    S.QUEST.available = { { questID = 1 }, { questID = 2 } }
    S.QUEST.pickedAvailable = nil
    quests:Gossip()
    check(S.QUEST.pickedAvailable == nil, "but two on offer is a decision, so nothing is picked")
    S.QUEST.available = {}
    S.QUEST.active = { { questID = 7, isComplete = false }, { questID = 8, isComplete = true } }
    quests:Gossip()
    check(S.QUEST.pickedActive == 8, "and the finished one is the one handed in")
    db.autoAcceptQuests = false
    db.autoTurnInQuests = false

    -- ---- Camera and client settings -----------------------------
    local client = CNS.modules.client
    S.CVAR_CEILING["cameraDistanceMaxZoomFactor"] = 2.6
    S.CVARS["cameraDistanceMaxZoomFactor"] = "1"
    client:Apply()
    check(S.CVARS["cameraDistanceMaxZoomFactor"] == "1",
        "the camera is left where it was until asked")

    db.maxCameraZoom = true
    client:Apply()
    check(tonumber(S.CVARS["cameraDistanceMaxZoomFactor"]) == 2.6,
        "asked, it finds this build's ceiling rather than guessing: "
        .. tostring(S.CVARS["cameraDistanceMaxZoomFactor"]))

    db.maxCameraZoom = false
    client:Apply()
    check(S.CVARS["cameraDistanceMaxZoomFactor"] == "1", "and off puts it back")

    -- A miss must not be remembered. The console variables were not
    -- readable when this module first applied, and caching that meant
    -- the option did nothing for the rest of the session.
    client.zoomName, client.zoomWas, client.found, client.pushed = nil, nil, nil, nil
    S.CVARS["cameraDistanceMaxZoomFactor"] = nil
    check(client:ZoomCVar() == nil, "no camera variable, nothing to do")
    S.CVARS["cameraDistanceMaxZoomFactor"] = "1"
    check(client:ZoomCVar() == "cameraDistanceMaxZoomFactor",
        "and it is found once the client will answer")

    -- The other spelling, for the Classic side of this client's family.
    client.zoomName, client.zoomWas, client.found = nil, nil, nil
    S.CVARS["cameraDistanceMaxZoomFactor"] = nil
    S.CVARS["cameraDistanceMaxFactor"] = "1"
    S.CVAR_CEILING["cameraDistanceMaxFactor"] = 3.4
    db.maxCameraZoom = true
    client:Apply()
    check(tonumber(S.CVARS["cameraDistanceMaxFactor"]) == 3.4,
        "the Classic spelling works too, at its own ceiling: "
        .. tostring(S.CVARS["cameraDistanceMaxFactor"]))
    db.maxCameraZoom = false
    client:Apply()
    S.CVARS["cameraDistanceMaxFactor"] = nil
    S.CVARS["cameraDistanceMaxZoomFactor"] = "1"
    client.zoomName, client.zoomWas, client.found = nil, nil, nil

    check(S.CVARS["Sound_EnableSoundWhenGameIsInBG"] ~= "1", "background sound is off until asked")
    db.soundInBackground = true
    client:Apply()
    check(S.CVARS["Sound_EnableSoundWhenGameIsInBG"] == "1", "and on when it is")

    -- The chat boxes arrive in the old alt arrow mode: arrows steer the
    -- character, Alt and an arrow moves the cursor and walks the history.
    -- Confirmed on the live client 2026-09-23.
    check(ChatFrame1EditBox.__altArrow == true, "the chat box starts in the client's alt arrow mode")
    db.chatArrowKeys = true
    client:Apply()
    check(ChatFrame1EditBox.__altArrow == false, "asked, the arrows go to the text box")
    check(ChatFrame7EditBox.__altArrow == false, "every chat window, not just the first")
    db.chatArrowKeys = false
    client:Apply()
    check(ChatFrame1EditBox.__altArrow == true,
        "and switching it off puts the client default back rather than leaving ours")

    db.soundInBackground = false

    -- ---- Proc glow ----------------------------------------------
    local glow = CNS.modules.glow
    local button = {}
    glow:Apply()
    ActionButton_ShowOverlayGlow(button)
    check(S.GLOW[button] == true, "the proc glow still works until asked to go")

    db.hideProcGlow = true
    glow:Apply()
    ActionButton_ShowOverlayGlow(button)
    check(S.GLOW[button] == false, "switched on, a glow is hidden instead of shown")

    -- Off has to give the game back exactly what it had.
    db.hideProcGlow = false
    glow:Apply()
    ActionButton_ShowOverlayGlow(button)
    check(S.GLOW[button] == true, "and off gives the game its own glow back")
    check(next(glow.wrapped) == nil, "with nothing of ours left wrapped around it")

    -- Repair on arrival. This shipped broken: the cost was fetched as
    -- `local cost, canRepair = GetRepairAllCost and GetRepairAllCost()`,
    -- and `and` keeps only the first return, so canRepair was always nil
    -- and the guard on the next line sent it home every time.
    db.autoRepair = true
    db.guildRepair = false
    S.REPAIR_COST, S.REPAIRED, S.MONEY = 5000, nil, 100000
    S.fire("MERCHANT_SHOW")
    check(S.REPAIRED == "self", "arriving at a merchant repairs: " .. tostring(S.REPAIRED))

    -- Nothing to repair is not a failure, it is just quiet.
    S.REPAIR_COST, S.REPAIRED = 0, nil
    S.fire("MERCHANT_SHOW")
    check(S.REPAIRED == nil, "with nothing broken it does not pay to repair nothing")

    -- Guild funds first when they are offered and they cover it.
    db.guildRepair = true
    S.GUILD_REPAIR, S.GUILD_FUNDS = true, 10000
    S.REPAIR_COST, S.REPAIRED = 5000, nil
    S.fire("MERCHANT_SHOW")
    check(S.REPAIRED == "guild", "guild funds are used when they cover it: " .. tostring(S.REPAIRED))

    -- Guild funds that fall short fall back to the player's own.
    S.GUILD_FUNDS, S.REPAIRED = 100, nil
    S.fire("MERCHANT_SHOW")
    check(S.REPAIRED == "self", "and fall back to your own when they do not: " .. tostring(S.REPAIRED))

    -- Too poor to repair says so rather than failing silently.
    db.guildRepair = false
    S.GUILD_REPAIR = false
    S.MONEY, S.REPAIRED = 100, nil
    S.CHAT = {}
    S.fire("MERCHANT_SHOW")
    check(S.REPAIRED == nil, "too poor to repair does not try")
    check(table.concat(S.CHAT, " "):find("cannot afford") ~= nil, "and says why")
    S.MONEY = 100000

    -- Off means off.
    db.autoRepair = false
    S.REPAIR_COST, S.REPAIRED = 5000, nil
    S.fire("MERCHANT_SHOW")
    check(S.REPAIRED == nil, "and with the setting off it leaves the repair alone")
    db.autoRepair = true

    check(Minimap.__maskTex == nil, "the minimap is untouched until asked")

    db.squareMinimap = true
    db.autoLoot = true
    db.sellJunk = true
    db.autoRepair = true
    local okApply = pcall(function() WicksComfortsApply() end)
    check(okApply ~= false, "settings apply without error")
    check(Minimap.__maskTex == "Interface\\BUTTONS\\WHITE8X8", "the square mask is applied once asked")
    local ring = MODERN and MinimapCompassTexture or MinimapBorder
    check(ring and not ring:IsShown(), "the round ring art is hidden with it")
    local mmChrome = _G.WicksComfortsMinimapChrome
    check(mmChrome and mmChrome:IsShown(), "the Wick border replaces the ring")
    if MODERN then
        check(MinimapCluster.MinimapContainer:GetWidth() == Minimap:GetWidth(),
            "the container tightens to the map so the header sits flush")
    end
    db.squareMinimap = false
    WicksComfortsApply()
    check(Minimap.__maskTex ~= "Interface\\BUTTONS\\WHITE8X8", "turning it off restores the round mask")
    check(ring and ring:IsShown(), "and brings the ring art back")
    check(mmChrome and not mmChrome:IsShown(), "and takes the Wick border away again")
    if MODERN then
        check(MinimapCluster.MinimapContainer:GetWidth() == 240, "and gives the container its size back")
    end
end
S.CHAT = {}
SlashCmdList.WICK_WICKSCOMFORTS("status")
check(#S.CHAT >= 1, "/wcomfort status prints")

-- ============================================================
-- WickCore missing
-- ============================================================
--
-- Every addon used to declare WickCore with Dependencies, which is a hard
-- one: with WickCore absent the client refuses to load the addon at all, so
-- none of our code runs and the player gets a greyed line in the AddOns list
-- and nothing else. The assert each addon carried could never fire.
--
-- They ask with OptionalDeps now and say so themselves. This loads two of
-- them with no WickCore in sight and checks they come up quietly, then speak
-- once, together, with somewhere to go.
io.write("== WickCore missing ==\n")
do
    local keepCore, keepLib = WickCore, LibStub
    WickCore, _G.WickCore = nil, nil
    _G.WicksNeedCore = nil
    S.CHAT = {}

    local ok1 = pcall(S.loadAddon, ADDONS_DIR .. "/WicksBeastsAndThings", "WicksBeastsAndThings",
        { "Core.lua", "Pet.lua", "Ammo.lua", "Beasts.lua", "UI.lua" })
    check(ok1, "Wick's Beasts and Things loads with no WickCore rather than erroring")
    local ok2 = pcall(S.loadAddon, ADDONS_DIR .. "/WicksTradeHall", "WicksTradeHall",
        { "Core.lua", "Prices.lua", "Ledger.lua", "Board.lua", "UI.lua" })
    check(ok2, "so does Wick's Trade Hall")

    local need = _G.WicksNeedCore
    check(type(need) == "table" and #need == 2,
        "both put their name down, got " .. tostring(need and #need))

    -- Nothing is said at load: the chat frame is not up yet, and one line
    -- per addon would be a wall with the whole suite installed.
    check(#S.CHAT == 0, "and nothing is said before the player is in the world")

    S.fire("PLAYER_LOGIN")
    local said = table.concat(S.CHAT, " | ")
    check(#S.CHAT == 1, "one line for the lot of them, got " .. #S.CHAT)
    check(said:find("Wick's Beasts and Things", 1, true) and said:find("Wick's Trade Hall", 1, true),
        "naming each: " .. said:sub(1, 110))
    check(said:find("wicksmods.com", 1, true) ~= nil, "with somewhere to get it")
    check(said:find("need", 1, true) ~= nil, "and reading as plural for two of them")

    WickCore, _G.WickCore, LibStub = keepCore, keepCore, keepLib
    _G.WicksNeedCore = nil
end


io.write("== missing globals reached during the run ==\n")
io.write("  ", table.concat(S.missingReport(), " "), "\n")
io.write("\n", MODE, ": ", passes, " passed, ", fails, " failed\n")
if fails > 0 then error(MODE .. ": " .. fails .. " check(s) failed", 0) end
io.write("PASS\n")
