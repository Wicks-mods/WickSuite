-- Offline load test for WickCore.
-- Drives the library end to end against the shared stub client.
--   args: addonDir, mode ("modern" | "legacy"), stubPath

local ADDON_DIR, MODE, STUB = ...
MODE = MODE or "modern"
local S = assert(loadfile(STUB))(MODE)
local MODERN = S.modern
local fire, SECRET = S.fire, S.SECRET

local passes, fails = 0, 0
local function check(cond, label)
    if cond then passes = passes + 1; io.write("  ok    ", label, "\n")
    else fails = fails + 1; io.write("  FAIL  ", label, "\n") end
end

-- ---------- load the library -------------------------------------------
io.write("== load (", MODE, ") ==\n")
S.loadAddon(ADDON_DIR, "WickCore")   -- file list straight off WickCore.toc
check(type(WickCore) == "table", "WickCore global")
local Core = WickCore

-- ---------- client --------------------------------------------------------
io.write("== client ==\n")
check(Core.Client:Flavor() == (MODERN and "forever" or "tbc"), "flavor " .. Core.Client:Flavor())
check(Core.Client.isModern == MODERN, "dialect detection")
check(Core.Client.hasSecrets == MODERN, "secrets detection")
check(#Core.Client:Report() == 2, "client report")

-- ---------- lifecycle -----------------------------------------------------
io.write("== lifecycle ==\n")
fire("ADDON_LOADED", "WickCore")
fire("PLAYER_LOGIN")
check(Core.self.initialized and Core.self.enabled, "WickCore self addon initialized + enabled")
check(type(WickCoreDB) == "table" and WickCoreDB.global.minimap.angle == 220, "WickCoreDB defaults")
check(type(SlashCmdList.WICK_WICKCORE) == "function", "/wickcore registered")
S.CHAT = {}
SlashCmdList.WICK_WICKCORE("")
check(#S.CHAT >= 3, "/wickcore prints report")
SlashCmdList.WICK_WICKCORE("dialect")
check(#S.CHAT > 5, "/wickcore dialect prints paths")

local initFlag, enableFlag = false, false
local A = Core:NewAddon("WicksTest", {
    title = "Wick's Test", version = "1.2.3", savedVar = "WicksTestDB",
    defaults = { profile = { locked = false, nested = { a = 1 }, list = { "x" } }, global = { seen = 0 } },
})
function A:OnInitialize() initFlag = true end
function A:OnEnable() enableFlag = true end
fire("ADDON_LOADED", "WicksTest")
check(initFlag and enableFlag, "product OnInitialize + OnEnable (post-login init enables immediately)")
check(A.db and A.db.profile.locked == false and A.db.profile.nested.a == 1, "product db defaults applied")
check(A.db.global.seen == 0, "product global defaults")
check(Core:GetAddon("WicksTest") == A, "GetAddon")

-- ---------- dialect -------------------------------------------------------
io.write("== dialect ==\n")
local D = Core.Dialect
local item = D.GetItemInfo(6948)
check(item and item.name == "Hearthstone" and item.classID == 15, "GetItemInfo normalized")
check(D.GetItemInfoInstant(6948).itemID == 6948, "GetItemInfoInstant")
check(D.GetItemCount(6948) == 1, "GetItemCount")
check(D.GetItemIcon(6948) ~= nil, "GetItemIcon")
check(D.GetItemStats("link").ITEM_MOD_STAMINA_SHORT == 10, "GetItemStats")
check(D.GetItemSpell(6948).spellID == 8690, "GetItemSpell")
local sp = D.GetSpellInfo(133)
check(sp and sp.name == "Fireball" and sp.spellID == 133 and sp.castTime == 3500, "GetSpellInfo normalized")
check(D.GetSpellName(133) == "Fireball", "GetSpellName")
check(D.GetSpellTexture(133) ~= nil, "GetSpellTexture")
local cd = D.GetSpellCooldown(133)
check(cd and cd.duration == 0 and cd.enabled, "GetSpellCooldown normalized at rest")
check(D.IsSpellKnown(133), "IsSpellKnown")
check(D.GetContainerNumSlots(0) == (MODERN and 20 or 16), "GetContainerNumSlots")
check(D.GetContainerNumFreeSlots(0) == (MODERN and 17 or 13), "GetContainerNumFreeSlots")
local ci = D.GetContainerItemInfo(0, 1)
check(ci and ci.itemID == 6948 and ci.hyperlink and ci.stackCount == 1, "GetContainerItemInfo normalized")
check(D.GetContainerItemLink(0, 1) ~= nil and D.GetContainerItemID(0, 1) == 6948, "container link + id")
local aura = D.GetAura("player", 1)
check(aura and aura.name == "Lightning Shield" and aura.spellId == 324, "GetAura at rest")
local n = 0
for a in D.IterateAuras("player") do n = n + 1 end
check(n == 2, "IterateAuras yields 2 at rest")
check(D.GetAuraBySpellName("player", "Water Shield") ~= nil, "GetAuraBySpellName")
local q = D.GetQuestLogEntry(3)
check(q and q.title == "Quest 3" and q.questID == 103, "GetQuestLogEntry")
check(select(1, D.GetNumQuestLogEntries()) == 12, "GetNumQuestLogEntries")
check(D.GetNumGroupMembers() == 0, "GetNumGroupMembers solo")
IN_GROUP = true
check(D.GetNumGroupMembers() == 5, "GetNumGroupMembers grouped")
IN_GROUP = false
check(D.CoinString(12345) == "12345c", "CoinString")
check(D.SendAddonMessage("WICK", "hi", "PARTY") == true, "SendAddonMessage at rest")
local ts = D.GetTradeSkillLine()
check(ts and ts.name == "Alchemy" and ts.rank == 150, "GetTradeSkillLine")
local totem = D.GetTotemInfo(1)
check(totem and totem.haveTotem == true and not totem.secret, "GetTotemInfo at rest")
check(#D:Report() > 15, "Dialect report")
if MODERN then check(D.GetActiveTalentConfigID() == 4242, "talent config id (traits)")
else check(D.GetActiveTalentConfigID() == nil, "talent config id nil on legacy") end

-- ---------- restriction --------------------------------------------------
io.write("== restrict ==\n")
local R = Core.Restrict
check(R:IsCombat() == false, "not in combat")
local changes = {}
R:OnChange(function(kind, active) changes[#changes + 1] = kind .. "=" .. tostring(active) end)
COMBAT = true
if MODERN then fire("ADDON_RESTRICTION_STATE_CHANGED", 0, 2) else fire("PLAYER_REGEN_DISABLED") end
check(R:IsCombat() == true, "in combat detected")
check(changes[1] == "Combat=true", "OnChange fired: " .. tostring(changes[1]))
if MODERN then
    check(R:AurasBlocked(), "auras blocked in combat")
    local a, why = D.GetAura("player", 1)
    check(a == nil and why == "restricted", "GetAura returns nil,restricted in combat")
    local cnt = 0
    for _ in D.IterateAuras("player") do cnt = cnt + 1 end
    check(cnt == 0, "IterateAuras yields nothing in combat")
    check(R:IsSecret(SECRET) and not R:IsSecret(5), "IsSecret")
    check(R:Plain(SECRET, "n/a") == "n/a" and R:Plain(7, 0) == 7, "Plain fallback")
    check(R:CooldownsSecret(), "cooldowns secret in combat")
    local t2 = D.GetTotemInfo(1)
    check(t2 and t2.secret == true, "GetTotemInfo flags secret in combat")
    local cd2 = D.GetSpellCooldown(133)
    check(cd2 and R:IsSecret(cd2.duration), "cooldown duration secret in combat")
else
    check(not R:AurasBlocked(), "auras readable in combat on legacy")
    check(D.GetAura("player", 1) ~= nil, "GetAura works in combat on legacy")
end
COMBAT = false
if MODERN then fire("ADDON_RESTRICTION_STATE_CHANGED", 0, 0) else fire("PLAYER_REGEN_ENABLED") end
check(changes[2] == "Combat=false", "OnChange fired on clear")
check(D.GetAura("player", 1) ~= nil, "auras readable again")
check(type(R:Summary()) == "string", "Summary")

-- ---------- chrome --------------------------------------------------------
io.write("== chrome ==\n")
local Chrome = Core.Chrome
local win = {}
local panel = Chrome:NewPanel("WicksTestFrame", { title = "Wick's Test", width = 300, height = 200, resizable = true, db = win })
check(panel.content and panel.title and panel.close and panel.grip and panel.brackets.TOPLEFT, "panel parts")
check(Chrome:TitleMarkup("Wick's Test"):find(Chrome.Hex.fel) and Chrome:TitleMarkup("Wick's Test"):find(Chrome.Hex.text), "two-tone title")
panel:Show(); panel:Toggle()
check(panel:IsShown() == false, "Toggle")
-- Put it somewhere known and check the trip out and back, rather than
-- whatever the frame happened to be anchored at.
panel:ClearAllPoints()
panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -60)
Chrome:SavePosition(panel, win)
check(win.point == "TOPLEFT" and win.relPoint == "TOPLEFT" and win.x == 40 and win.y == -60
      and win.width == 300, "SavePosition records the anchor and the size")
panel:ClearAllPoints()
panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
Chrome:RestorePosition(panel, win)
local rp, _, rrp, rx, ry = panel:GetPoint()
check(rp == "TOPLEFT" and rrp == "TOPLEFT" and rx == 40 and ry == -60,
      "RestorePosition puts it back: " .. tostring(rp) .. " " .. tostring(rx) .. "," .. tostring(ry))

-- A size saved under an old layout must not outlive it. Where a window
-- is put is the player's; how big it is is only theirs when they can
-- drag it. Wick's Gear grew a second column and opened at its old width
-- with the paperdoll running through the button underneath, because the
-- saved size was believed over the code's.
do
    local fixedDB = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0,
                      width = 300, height = 200 }
    local fixed = Chrome:NewPanel("WicksSizeFixed", { title = "Fixed", width = 520, height = 420 })
    Chrome:RestorePosition(fixed, fixedDB)
    check(fixed:GetWidth() == 520 and fixed:GetHeight() == 420,
        "a panel sized in code ignores an old saved size: "
        .. tostring(fixed:GetWidth()) .. "x" .. tostring(fixed:GetHeight()))
    Chrome:SavePosition(fixed, fixedDB)
    check(fixedDB.width == nil and fixedDB.height == nil,
        "and stops storing one, so it cannot be believed later")
    check(fixedDB.point == "CENTER", "while its position is still kept")

    -- A panel with a grip is the opposite: the size is the player's.
    local gripDB = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0,
                     width = 640, height = 300 }
    local grip = Chrome:NewPanel("WicksSizeGrip", { title = "Grip", width = 400, height = 240,
                                                   resizable = true })
    Chrome:RestorePosition(grip, gripDB)
    check(grip:GetWidth() == 640 and grip:GetHeight() == 300,
        "a resizable panel keeps the size the player dragged it to: "
        .. tostring(grip:GetWidth()) .. "x" .. tostring(grip:GetHeight()))
    Chrome:SavePosition(grip, gripDB)
    check(gripDB.width == 640, "and goes on storing it")
end
local flag = false
local cb = Chrome:Check(panel.content, "Lock", function() return flag end, function(v) flag = v end)
cb.__scripts.OnClick()
check(flag == true, "Check toggles")
check(Chrome:Button(panel.content, "Go").label:GetText() == "Go", "Button label")


io.write("== what the client refused ==" .. string.char(10))
do
    -- Three attempts at the bag popup were each a guess about which call
    -- was refused. The popup does not name it and a forbidden action
    -- never reaches the taint log, so the event that does name it is the
    -- only source, and nothing was listening.
    S.CHAT = {}
    S.fire("ADDON_ACTION_FORBIDDEN", "WicksBags", "SortBags()")
    local said = table.concat(S.CHAT, " | ")
    check(said:find("SortBags()", 1, true) ~= nil,
        "a forbidden call is named in chat: " .. said:sub(1, 80))
    check(#Core.Restrict:Refusals() == 1, "and kept for later")

    -- Once per distinct call: a popup in a loop is not a wall of chat.
    S.CHAT = {}
    S.fire("ADDON_ACTION_FORBIDDEN", "WicksBags", "SortBags()")
    check(#S.CHAT == 0, "the same one again says nothing")
    check(Core.Restrict:Refusals()[1].count == 2, "but is counted: "
        .. tostring(Core.Restrict:Refusals()[1].count))

    -- A different call is worth saying.
    S.CHAT = {}
    S.fire("ADDON_ACTION_BLOCKED", "WicksBags", "UseContainerItem()")
    check(#S.CHAT > 0, "a different call is said")
    check(#Core.Restrict:Refusals() == 2, "and kept alongside the first")

    -- Somebody else's addon is not our business.
    S.CHAT = {}
    S.fire("ADDON_ACTION_FORBIDDEN", "SomeOtherAddon", "CastSpellByName()")
    check(#S.CHAT == 0, "another addon's refusal is not reported as ours")
    check(#Core.Restrict:Refusals() == 2, "nor recorded")
end

-- ---------- themes --------------------------------------------------------
io.write("== themes ==\n")
check(#Chrome.Themes == 16 and Chrome.ThemeByClass.WARLOCK.id == "fel" and Chrome.ThemeByID.custom, "nine class themes, six looks' palettes and custom, warlock is fel")
check(Chrome.ThemeByID.rebel and Chrome.ThemeByID.rebel.look, "a look's palette is a theme")
check(Chrome:ThemeSetting() == "auto" and (Chrome:CharStore().theme == nil or Chrome:CharStore().theme == "auto")
    and Chrome.activeTheme == Chrome.ThemeByClass[select(2, UnitClass("player"))].id, "a new install follows the class")
-- The rest of this section starts from Fel.
Chrome:SetTheme("fel")
local felBefore = Chrome.Colors.fel[3]
local bracket = panel.brackets.TOPLEFT[1]
local titleFS = Chrome:Text(panel.content, 11, Chrome.Colors.text)
Chrome:SetTheme("shaman")
check(Chrome.activeTheme == "shaman" and Chrome:CharStore().theme == "shaman", "SetTheme persists")
check(Chrome:SavedThemeSetting() == "shaman", "saved setting readable back")

-- A hover wash is the accent at a low alpha. Registering it against the
-- accent token would repaint it at the token's alpha, which turns a 6%
-- wash into a solid block, so these stayed literal and stayed green
-- under every theme.
do
    Chrome:SetTheme("fel")
    local wash = Chrome:Wash("fel", 0.06)
    check(wash[1] == Chrome.Colors.fel[1] and wash[4] == 0.06, "a wash is the token at its own alpha")

    local t = Chrome:Texture(panel.content, "ARTWORK", wash)
    check(t.__color[4] == 0.06, "and paints at that alpha, got " .. tostring(t.__color[4]))

    Chrome:SetTheme("mage")
    check(wash[1] == Chrome.Colors.fel[1] and wash[2] == Chrome.Colors.fel[2],
          "the wash follows the accent through a theme change")
    check(t.__color[1] == Chrome.Colors.fel[1], "the region painted with it follows too")
    check(t.__color[4] == 0.06, "still at 6%, not the token's alpha: " .. tostring(t.__color[4]))
    Chrome:SetTheme("shaman")
end

-- On this client the game writes saved variables and never reads them
-- back, so a setting survives only if the macro store writes it, and the
-- store writes when something marks it dirty. The options page marked
-- its own check boxes and nothing else did: a theme is picked from a
-- list somewhere else entirely, so the choice was gone at the next
-- login and the logout write was the only reason it ever came back.
do
    local Store = Core.Store
    check(Store ~= nil, "the store is there to be told")
    -- Put back whatever the run was using: the checks below this one
    -- read the client class colours, and switching the source is one of
    -- the things being checked here.
    local wasColours = Chrome.classColorSet
    Store.enabled = true
    Store.dirtyToken = 0
    Chrome:SetTheme("mage")
    check((Store.dirtyToken or 0) > 0, "picking a theme marks the store dirty")

    Store.dirtyToken = 0
    Chrome:SetClassColorSet("classic")
    check((Store.dirtyToken or 0) > 0, "and so does changing the class colour source")

    -- Where a window sits is a setting too.
    Store.dirtyToken = 0
    local win2 = {}
    local moved = Chrome:NewPanel("WicksDirtyFrame", { title = "Moved", width = 300, height = 200, db = win2 })
    Chrome:SavePosition(moved, win2)
    check((Store.dirtyToken or 0) > 0, "and so does moving a window")

    -- A store switched off is not woken up by any of it.
    Store.enabled = false
    Store.dirtyToken = 0
    Chrome:SetTheme("rogue")
    check((Store.dirtyToken or 0) == 0, "with the store off, nothing is scheduled")
    Store.enabled = true
    Chrome:SetClassColorSet(wasColours)
    Chrome:SetTheme("shaman")
end

-- The store stands in for a client that writes saved variables and
-- never reads them back. When the client starts handing them over it
-- has to stand down, and say so: a player who opted in is otherwise
-- left with macros that are no longer used and no word about why.
do
    local Store = Core.Store
    local db = Core.self.db
    local wasHanded, wasEnabled = db.handedOver, Store.enabled
    local wasAnnounced, wasReason = Store.announced, Store.reason

    db.handedOver = true
    Store.enabled = nil
    local needed, why = Store:Needed()
    check(needed == false, "with the client keeping settings, the store is not needed")
    check(tostring(why):find("handed", 1, true) ~= nil, "and says why: " .. tostring(why))
    check(Store:Decide() == false, "so it decides itself off")

    -- And it must not put macro contents back over settings the client
    -- has just handed over.
    check(Store:RestoreFor(Core.self) == false,
        "and restores nothing over what the client handed over")

    db.handedOver, Store.enabled = wasHanded, wasEnabled
    Store.announced, Store.reason = wasAnnounced, wasReason
end
Chrome:CharStore().theme = "wiped by something else"
Core.self.db = nil                                  -- profile unbound, as if init never ran
Chrome:SetTheme("druid")
check(Chrome:CharStore().theme == "druid", "SetTheme still writes with no profile bound")
S.fire("PLAYER_LOGOUT")
check(Chrome:CharStore().theme == "druid", "logout flush rewrites the live choice")

-- A read that comes too early must not become a choice lost for good.
--
-- On this client the settings arrive from the macro store, which can land
-- after login. ApplySavedTheme used to save unconditionally, so a login
-- that read nothing fell back to Fel and then wrote Fel over the real
-- setting. The user lost their theme to this twice.
Chrome:CharStore().theme = "shaman"
Chrome:ApplySavedTheme("login")
check(Chrome.activeTheme == "shaman", "a stored theme is applied at login")
check(Chrome:CharStore().theme == "shaman", "and left where it was")

Chrome:CharStore().theme = nil                       -- the store has not landed yet
Chrome:ApplySavedTheme("login")
check(Chrome.activeTheme == Chrome.ThemeByClass[select(2, UnitClass("player"))].id, "with nothing to read it follows the class")
check(Chrome:CharStore().theme == nil,
    "and writes nothing, so a late store still has something to restore: " ..
    tostring(Chrome:CharStore().theme))

-- Which is what the store does when it lands.
Chrome:CharStore().theme = "druid"
Chrome:ApplySavedTheme("store")
check(Chrome.activeTheme == "druid", "the store landing applies the real choice")
check(Chrome.applyLog:find("store=druid", 1, true) ~= nil,
    "and says so in the trace: " .. Chrome.applyLog:sub(-40))

Core.self.db = Core.Profiles:Init(Core.self, "WickCoreDB", Core.self.opts.defaults)
Chrome:SetTheme("shaman")
check(Chrome.Colors.fel[3] ~= felBefore and Chrome.Colors.fel[3] > 0.8, "palette mutated in place")
check(bracket.__color and math.abs(bracket.__color[1] - Chrome.Colors.fel[1]) < 0.001, "bracket re-tinted live")
check(titleFS.__textColor and math.abs(titleFS.__textColor[1] - Chrome.Colors.text[1]) < 0.001, "token text re-tinted live")
check(Chrome.ThemeByID.shaman.hex.fel == "0070DD", "shaman accent is the client class color")
check(Chrome:TitleMarkup("Wick's Test"):find("0070DD") ~= nil, "title markup follows theme")
check(Core.COLOR_ACCENT == "|cff0070DD", "chat accent follows theme")
check(Chrome.ThemeByID.priest.colors.void[1] < 0.12, "bright accents keep the darks dark")
Chrome:SetTheme("auto")
check(Chrome:CharStore().theme == "auto" and Chrome.activeTheme == "shaman", "auto resolves to the class theme")
check(Chrome:ResolveTheme("nonsense") == "fel", "unknown theme falls back to fel")
Chrome:SetClassColorSet("classic")
check(Chrome.ThemeByID.mage.hex.fel == "69CCF0" and WickCoreDB.global.classColors == "classic", "classic class color set swaps the mage accent")
Chrome:SetClassColorSet("client")
check(Chrome.ThemeByID.mage.hex.fel == "3FC7EB", "client set restored")
local ct = Chrome:SetCustomColors("2A4A2A", "FFAA00")
check(ct and ct.hex.fel == "FFAA00" and WickCoreDB.global.custom.main == "2A4A2A", "custom colors saved and accent applied verbatim")
check(ct.colors.void[2] > ct.colors.void[1] and ct.colors.border[2] > ct.colors.border[1], "custom darks derived from the main color's hue")
Chrome:SetTheme("custom")
check(Chrome.activeTheme == "custom" and Core.COLOR_ACCENT == "|cffFFAA00", "custom theme applies")
check(Chrome:SetCustomColors("zzz", nil).hex.void == ct.hex.void, "bad hex is ignored")
S.CHAT = {}
SlashCmdList.WICK_WICKCORE("theme custom 102040 ff00ff")
check(Chrome.customColors.main == "102040" and Chrome.customColors.accent == "FF00FF" and S.CHAT[1]:find("custom theme"), "/wickcore theme custom <main> <accent>")
Chrome:SetTheme("fel")
check(Chrome.Colors.fel[3] == felBefore and Core.COLOR_ACCENT == "|cff4FC778", "back to fel restores brand values")
S.CHAT = {}
SlashCmdList.WICK_WICKCORE("theme list")
check(#S.CHAT >= 3 and table.concat(S.CHAT, " "):find("shaman") ~= nil, "/wickcore theme list prints")

-- ---------- profiles ------------------------------------------------------
io.write("== cooldown bar ==\n")
do
    local prevClass = CLASS
    CLASS = "HUNTER"
    local bar = Core.Cooldowns:New(A, { key = "cdbar" })
    check(#bar:List() > 0, "seeded from the class default")
    bar:Build()
    bar:SetShown(true)
    check(bar.frame:IsShown(), "bar shows")
    -- An icon per spell, and nothing protected: the bar tracks, it does
    -- not cast, which is what lets it be rebuilt during a fight.
    check(#bar.buttons > 0, "an icon per spell")
    check(bar.buttons[1].__template == nil, "and none of them is a secure button")
    local before = #bar:List()
    check(bar:Add("Arcane Shot") and #bar:List() == before + 1, "add a spell by name")
    check(not bar:Add("Arcane Shot"), "the same spell is not added twice")
    check(bar:Remove("Arcane Shot") and #bar:List() == before, "remove a spell")
    local str = bar:Export()
    check(str:find("^WICKCD1:") ~= nil, "export string is tagged and readable")
    check(bar:Import("WICKCD1:Sprint;Evasion") and #bar:List() == 2, "import replaces the list")
    check(bar:Import("Vanish", true) and #bar:List() == 3, "import can append")
    COMBAT = true
    local okCD, errCD = pcall(function() bar:Refresh() end)
    check(okCD, "refresh in combat with secret cooldowns " .. tostring(errCD or ""))

    -- The one part of a cooldown combat leaves readable. The times come
    -- back secret, but isActive stays a plain boolean, so the bar can
    -- show what is ready without reading anything it should not.
    bar:Reset()
    bar:Rebuild()
    local first = bar.buttons[1]
    local id = first and first.spellID
    check(id ~= nil, "the first icon knows its spell id")
    S.ON_COOLDOWN = { [id] = true }
    bar:Refresh()
    check(first.ready == false, "a spell on cooldown reads as not ready in combat")
    check(first.icon.__desaturated == true, "and its icon is dimmed")
    S.ON_COOLDOWN = {}
    bar:Refresh()
    check(first.ready == true, "and comes back when it is off cooldown")
    check(first.icon.__desaturated == false, "with the colour back")
    COMBAT = false
    bar:SetShown(false)
    check(not bar.frame:IsShown(), "bar hides")
    CLASS = prevClass
end

io.write("== profiles ==\n")
local db = A.db
db.profile.locked = true
db.profile.nested.a = 42
db.profile.tricky = "pipes | and ~ tildes ~p and :colons: and\nnewlines"
local s = Core.Serialize({ a = 1, b = "two", c = { d = true, e = { 1, 2, 3 } }, f = -1.5 })
local back = Core.Deserialize(s)
check(back.a == 1 and back.b == "two" and back.c.d == true and back.c.e[3] == 3 and back.f == -1.5, "Serialize roundtrip")
local export = db:Export()
check(export:sub(1, 6) == "WICK1:", "Export prefix")
check(not export:find("|", 1, true), "Export has no raw pipes")
db:SetProfile("Alt")
check(db:GetCurrentProfile() == "Alt" and db.profile.locked == false, "SetProfile creates fresh profile with defaults")
local ok, payload = db:Import(export)
check(ok and db.profile.locked == true and db.profile.nested.a == 42, "Import restores values")
check(db.profile.tricky == "pipes | and ~ tildes ~p and :colons: and\nnewlines", "Import preserves tricky string")
check(payload.addon == "WicksTest" and payload.version == "1.2.3", "Import payload metadata")
local bad, why = db:Import("garbage")
check(bad == false and why, "Import rejects garbage")
check(#db:GetProfiles() == 2, "two profiles exist")
db:SetProfile("Default")
db:CopyProfile("Alt")
check(db.profile.nested.a == 42, "CopyProfile")
db:ResetProfile()
check(db.profile.nested.a == 1 and db.profile.locked == false, "ResetProfile")
db:SetKeyMode("spec")
check(db:GetKeyMode() == "spec" and db.key:find("^spec:SHAMAN"), "SetKeyMode spec -> " .. tostring(db.key))
db:SetKeyMode("mode")
check(db.key:find("^mode:"), "SetKeyMode mode -> " .. tostring(db.key))
db:SetKeyMode("char")
check(db.key == "Wick - Classic Beta PvP", "SetKeyMode char")
check(db:DeleteProfile("Alt") == true and #db:GetProfiles() == 1, "DeleteProfile")
check(db:DeleteProfile("Default") == false, "cannot delete Default")

-- ---------- options -------------------------------------------------------
io.write("== options ==\n")
local built = false
local page = A:RegisterOptions(function(body, addon)
    built = true
    local O = Core.Options
    local y = O:Heading(body, "General", 0)
    y = O:Check(body, "Lock", function() return addon.db.profile.locked end, function(v) addon.db.profile.locked = v end, y)
    -- A note long enough to wrap several times. Reporting one line of
    -- height here is what put the client-errors note underneath the
    -- Profiles heading in game.
    local LONG = string.rep("a note that has to wrap because it is long. ", 6)
    body:SetWidth(520)
    local beforeNote = y
    y = O:Note(body, LONG, y)
    local noteSpan = beforeNote - y
    y = O:ProfileSection(body, addon, y)
    check(y < -100, "layout helpers advance y")
    check(noteSpan > 40, "a wrapping note reports its real height, not one line")
    check(body.__extent ~= nil and body.__extent <= y, "the page records how far its content reached")
end)
check(page ~= nil and Core.Options.pages.WicksTest, "options page registered")
page:Show()
check(built, "options page builds on show")
Core.Options.root.frame:Show()
check(Core.Options.root.frame.built, "root page builds on show")
check(Core.Options.root.frame.themeNote ~= nil and Core.Options.root.frame.themeAuto == nil, "theme picker on the root page, no follow-my-class check")
A:OpenOptions()
check(OPENED ~= nil, "OpenOptions")
Core.Options:ShowExport(A, "WICK1:abc")
check(Core.Options.exportPanel and Core.Options.exportPanel.editBox:GetText() == "WICK1:abc", "ShowExport")

-- The page scrolls: content taller than the frame must not simply be cut off.
local sc = page.scroll
check(sc ~= nil and sc:GetScrollChild() == page.body, "the page body is a scroll child")
sc:SetHeight(200)
page.body:SetHeight(600)
sc:Refresh()
check(sc.thumb:IsShown() == true, "the scroll indicator appears when content overflows")
sc:GetScript("OnMouseWheel")(sc, -1)
check((sc:GetVerticalScroll() or 0) > 0, "the wheel scrolls down")
sc:GetScript("OnMouseWheel")(sc, 1)
check((sc:GetVerticalScroll() or 0) == 0, "and back up, clamped at the top")
page.body:SetHeight(50)
sc:Refresh()
check(sc:GetVerticalScroll() == 0, "short pages reset to the top")
check(sc.thumb:IsShown() == false, "and the indicator goes away again")

-- ---------- launcher ------------------------------------------------------
io.write("== launcher ==\n")
local clicked = false
A:RegisterLauncher({ onClick = function() clicked = true end })
check(Core.Launcher.entries.WicksTest ~= nil, "launcher registered")
check(Core.Launcher.button ~= nil, "minimap button exists")
Core.Launcher:ToggleHub()
check(Core.Launcher.hub and Core.Launcher.hub:IsShown() and #Core.Launcher.hub.rows == 1, "hub shows one product row")
Core.Launcher.hub.rows[1].__scripts.OnClick(nil, "LeftButton")
check(clicked, "hub row click routes to product")
Core.Launcher:SetMinimapHidden(true)
check(WickCoreDB.global.minimap.hidden == true, "minimap hidden persisted")

-- ---------- locale ---------------------------------------------------------
io.write("== locale ==\n")
local L = A:NewLocale("enUS", true)
L["Open"] = true
L["Close window"] = "Close window"
local Lde = A:NewLocale("deDE")
check(Lde == nil, "non-matching locale table skipped")
check(A.L["Open"] == "Open" and A.L["Close window"] == "Close window", "default locale strings")
check(A.L["Missing key"] == "Missing key", "unknown key falls back to itself")

-- ---------- version --------------------------------------------------------
io.write("== version ==\n")
check(Core.Version.registered.WicksTest == A, "product registered for version broadcast")
IN_GROUP = true
S.SENT = {}
Core.Version:Broadcast(true)
local sentTest = false
for _, m in ipairs(S.SENT) do if m[1] == "WICK" and tostring(m[2]):find("WicksTest") then sentTest = true end end
check(sentTest, "broadcast sends on WICK prefix")
IN_GROUP = false
S.CHAT = {}
fire("CHAT_MSG_ADDON", "WICK", "V\tWicksTest\t2.0.0", "PARTY", "Someone")
check(#S.CHAT == 1 and S.CHAT[1]:find("newer version"), "newer version notice")
S.CHAT = {}
fire("CHAT_MSG_ADDON", "WICK", "V\tWicksTest\t2.0.0", "PARTY", "Someone")
check(#S.CHAT == 0, "notice only once per session")
check(Core.compareVersions("1.2.10", "1.2.9") == 1 and Core.compareVersions("1.0", "1.0.0") == 0, "compareVersions")

-- ---------- slash -----------------------------------------------------------
io.write("== slash ==\n")
local got
A:RegisterSlash(function(self, msg) got = msg end, "/wtest", "/wt")
check(SLASH_WICK_WICKSTEST1 == "/wtest" and SLASH_WICK_WICKSTEST2 == "/wt", "slash globals")
SlashCmdList.WICK_WICKSTEST("  hello  ")
check(got == "hello", "slash handler trims and receives message")

-- ---------- escape ----------------------------------------------------------
io.write("== escape ==" .. string.char(10))
local esc = Core.Chrome:NewPanel("WicksTestEscPanel", { title = "Esc" })
local fixed = Core.Chrome:NewPanel("WicksTestFixedPanel", { title = "Fixed", closable = false })
local seen = {}
for _, n in ipairs(UISpecialFrames) do seen[n] = (seen[n] or 0) + 1 end
check(seen.WicksTestEscPanel == 1, "a closable panel is listed for Escape, once")
check(seen.WicksTestFixedPanel == nil, "a panel with no close glyph is not")
esc:Show()
check(CloseSpecialWindows() and not esc:IsShown(), "and Escape closes it")
-- ---------- store -----------------------------------------------------------
-- The Forever beta writes saved variables at logout and hands nothing back
-- at load. Everything below is that client: no saved variable was ever
-- handed over in this run, so the store is the only thing standing
-- between a setting and defaults.
io.write("== store ==\n")
local Store = Core.Store
check(type(Store) == "table", "Core.Store exists")
check(A.db.handedOver == false, "the client handed nothing over for the product")
-- The theme section above re-bound WickCore's own db against a global it
-- had already populated, to test "init never ran". On the real client
-- WickCoreDB is nil at binding; put the decision input back to that.
Core.self.db.handedOver = false
Store.enabled, Store.reason, Store.optedIn = nil, nil, nil

-- Off until asked. Macros are the player's screen space.
S.MACROS.acct = { { name = "ss", icon = 134400, body = "#showtooltip\n/cast Serpent Sting" } }
S.MACROS.char = {}
check(Store:Needed() == true, "the client needs a store: " .. select(2, Store:Needed()))
check(Store:Decide() == false, "but it is off until asked: " .. tostring(Store.reason))
local okOff, whyOff = Store:Save(true)
check(not okOff and #S.MACROS.acct == 1, "and writes nothing while off")

-- The encoding is a faithful round trip and always the same text for the
-- same table, because "did anything change" is a string compare.
local sample = { profiles = { Default = { locked = true, name = "Wick|s~", note = "two\nlines\r", tab = "a\tb", n = 3.5, list = { "x", "y" } } },
                 profileKeys = { ["A - R"] = "Default" }, keyMode = "char", global = { seen = 7 }, char = {} }
local enc1 = Store:Encode(sample)
check(enc1 == Store:Encode(sample), "encoding is deterministic")
local back = Store:Decode(enc1)
check(back and back.profiles.Default.name == "Wick|s~" and back.profiles.Default.note == "two\nlines\r"
    and back.profiles.Default.tab == "a\tb" and back.profiles.Default.n == 3.5
    and back.profiles.Default.list[2] == "y" and back.global.seen == 7,
    "and round-trips pipes, tildes, newlines, tabs, numbers, booleans, lists")
local esc = Store.escape(enc1)
check(not esc:find("[|\n\r\t]"), "the escaped body carries no pipe, newline or control character")
check(Store.unescape(esc) == enc1, "and unescapes to exactly the payload")
check(Store.b64dec(Store.b64enc(enc1)) == enc1, "the base64 pair still round-trips, for what older macros hold")

-- Only what differs from the defaults is kept. A saved variable is
-- mostly its own defaults written back on every load.
local slimmed = Store.withoutDefaults(
    { locked = false, nested = { a = 1, b = 2 }, list = { "x" }, extra = "mine", emptied = {} },
    { locked = false, nested = { a = 1 }, list = { "x" }, emptied = { "gone" } })
check(slimmed.locked == nil and slimmed.list == nil, "values equal to the default are dropped")
check(slimmed.nested and slimmed.nested.b == 2 and slimmed.nested.a == nil, "a keyed table keeps only its differing keys")
check(slimmed.extra == "mine", "a key with no default is kept")
check(type(slimmed.emptied) == "table" and next(slimmed.emptied) == nil, "a list the player emptied is kept empty, not refilled")

-- On.
A.db.profile.locked = true
A.db.profile.nested.a = 42
A.db.global.cache = { big = string.rep("z", 600) }     -- pretend a cache
A.opts.storeExclude = { "global.cache" }
local okOn, n = Store:TurnOn()
check(okOn and n >= 1, "turning on writes the settings into macros: " .. tostring(n))
check(S.MACROS.acct[1].name == "ss" and S.MACROS.acct[1].body:find("Serpent"), "the player's own macro is untouched and still first")
local mine = Store.Ours()
local count, joined = 0, {}
for i = 1, 200 do if mine[i] then count = count + 1; joined[#joined + 1] = mine[i].body end end
check(count == n, "and exactly that many WickCfg macros exist")
for _, m in pairs(mine) do
    check(#m.body <= 255, "no body over the client's limit: " .. #m.body)
    break
end
check(not table.concat(joined):find("zzzz"), "a declared cache path is not written")
check(A.db.global.cache.big:len() == 600, "while the live table still has it")
check(n <= 3, "a small addon's settings fit in a few macros, not dozens: " .. tostring(n))

-- Unchanged settings write nothing.
local before = S.MACRO_WRITES
local ok2, n2 = Store:Save()
check(ok2 and n2 == 0 and S.MACRO_WRITES == before, "saving again with nothing changed writes nothing")

A.db.profile.locked = false
Store:Dirty()          -- C_Timer.After runs at once in the stub
check(S.MACRO_WRITES > before, "a change marked dirty is written")

-- Combat: the client refuses, so the write waits for it to end.
A.db.profile.nested.a = 43
COMBAT = true
local okc, why = Store:Save()
check(not okc and why == "in combat", "nothing is written in combat")
COMBAT = false
before = S.MACRO_WRITES
fire("PLAYER_REGEN_ENABLED")
check(S.MACRO_WRITES > before, "and it is written when combat ends")

-- A relog. The global is gone, the macros are what the server hands
-- back, and a fresh addon reading the same saved variable has to come
-- up with the settings it left with, defaults filled back in.
WicksTestDB = nil
Store.cache, Store.cacheCount, Store.stamp = nil, nil, nil
Store.restored, Store.enabled, Store.optedIn = {}, nil, nil
local fired = false
local B = Core:NewAddon("WicksTestReborn", {
    title = "Wick's Test Reborn", savedVar = "WicksTestDB",
    defaults = { profile = { locked = false, nested = { a = 1 }, list = { "x" } }, global = { seen = 0 } },
})
function B:OnInitialize()
    check(self.db.profile.nested.a == 1, "before login the reborn addon sees defaults")
    self.db:On("OnProfileChanged", function() fired = true end)
end
local seenAtEnable
function B:OnEnable() seenAtEnable = self.db.profile.nested.a end
fire("ADDON_LOADED", "WicksTestReborn")
check(Store:Decide() == true, "our macros being there means on, without being asked again")
check(B.db.profile.locked == false and B.db.profile.nested.a == 43, "after enable it has the settings it logged out with")
check(B.db.profile.list[1] == "x" and B.db.global.seen == 0, "and the defaults that were not stored are back")
check(seenAtEnable == 43, "and OnEnable already saw them, not the defaults")
check(fired, "OnProfileChanged fired so a product re-applies")
check(WicksTestDB == B.db.sv, "the global points at the restored table, so logout writes it")
check(Store.restored.WicksTestReborn == "WicksTestDB", "the store records what it put back, per addon")

-- The macro window takes 255 and the client caches 255, but the server
-- hands back 254 after a restart. In game that decoded to "unexpected
-- byte at 514" and then the periodic save wrote this session's defaults
-- over the player's settings. Two rules came out of it: bodies are 240,
-- the size the Probe proved through a restart, and a store that is there
-- but will not read is never overwritten by anything but a deliberate
-- "store on".
do
    local mine = Store.Ours()
    local n = 0
    for _ in pairs(mine) do n = n + 1 end
    check(n >= 2, "enough macros to have a boundary: " .. n)
    local full = true
    for i = 1, n - 1 do if #mine[i].body ~= 240 then full = false end end
    check(full and #mine[n].body <= 240, "every body but the last is exactly 240, none over")

    -- The restart: every body comes back a newline longer. In game that
    -- read as "WickCfg01 holds 256 characters, expected 240". It has to
    -- read as if nothing happened.
    S.MACRO_SERVER_NEWLINE = true
    Store.cache, Store.readError = nil, nil
    check(Store:Read() ~= nil, "bodies that came back a newline longer still read: " .. tostring(Store.readError))
    check(Store.bodyLengths[1] == 240, "and are counted at their real length: " .. tostring(Store.bodyLengths[1]))
    S.MACRO_SERVER_NEWLINE = nil

    -- The server cuts one character from the first macro.
    local kept = S.MACROS.acct[mine[1].index].body
    S.MACROS.acct[mine[1].index].body = kept:sub(1, 239)
    Store.cache, Store.readError = nil, nil
    check(Store:Read() == nil, "a short body makes the read fail")
    -- With only two macros and the first one cut, lengths alone cannot say
    -- which was damaged, so the decoder's own error is the honest report.
    -- With three or more the odd one out is named (checked further down).
    check(Store.readError ~= nil, "and there is an error to show: " .. tostring(Store.readError))

    S.CHAT = {}
    local writesBefore = S.MACRO_WRITES
    A.db.profile.locked = not A.db.profile.locked
    local okS, why = Store:Save()
    check(not okS and why == "store unreadable, left alone", "the periodic save refuses to write over it: " .. tostring(why))
    check(S.MACRO_WRITES == writesBefore, "and touched nothing")
    check(#S.CHAT == 1 and S.CHAT[1]:find("could not be read"), "saying so once")
    S.CHAT = {}
    Store:Save()
    check(#S.CHAT == 0, "and not again")

    -- A deliberate store on is allowed to replace it.
    local okF = Store:Save(true)
    check(okF and S.MACRO_WRITES > writesBefore, "store on, the deliberate path, writes")
    Store.cache = nil
    check(Store:Read() ~= nil, "and the store reads cleanly again")
    Store.warnedUnreadable = nil
end

-- A WicksProfile bake is a deliberate recovery. What it put in place wins
-- over the macros this session, and the save then carries it into them.
do
    local bakedAddon = Core:NewAddon("WicksTestBaked", { savedVar = "WicksBakedDB", defaults = { profile = { v = 1 } } })
    WicksBakedDB = { profiles = { Default = { v = 7 } }, profileKeys = {}, global = {}, char = {}, keyMode = "char" }
    _G.WicksProfile = { restored = { "WicksBakedDB" } }
    fire("ADDON_LOADED", "WicksTestBaked")
    check(bakedAddon.db.baked == true and bakedAddon.db.handedOver == false,
        "a baked table is recognised as baked, and not as the client's")
    check(not Store:RestoreFor(bakedAddon) and bakedAddon.db.profile.v == 7, "and the store does not put macros over it")
    _G.WicksProfile = nil
end

-- A store written by the 255-character version reads under 240: the test
-- is that the chunks agree with each other, not with today's size.
do
    local enc = Store.escape(Store:Encode({ WicksTestDB = { profiles = { Default = { nested = { a = 55 }, note = string.rep("x", 600) } }, profileKeys = {}, keyMode = "char", global = {}, char = {} } }))
    S.MACROS.acct = { S.MACROS.acct[1] }
    for i = 1, math.ceil(#enc / 255) do
        S.MACROS.acct[#S.MACROS.acct + 1] = { name = ("WickCfg%02d"):format(i), icon = 134400, body = enc:sub((i - 1) * 255 + 1, i * 255) }
    end
    check(#S.MACROS.acct >= 3, "the old store spans more than one macro: " .. (#S.MACROS.acct - 1))
    Store.cache, Store.readError = nil, nil
    local old = Store:Read()
    check(old and old.WicksTestDB.profiles.Default.nested.a == 55, "a store in 255-character chunks reads under a 240 chunk: " .. tostring(Store.readError))
    -- Cut the middle one and the length check names it.
    S.MACROS.acct[3].body = S.MACROS.acct[3].body:sub(1, 254)
    Store.cache, Store.readError = nil, nil
    check(Store:Read() == nil and tostring(Store.readError):find("WickCfg02 holds 254 characters where the others hold 255", 1, true) ~= nil,
        "a cut middle macro is named with the shortfall: " .. tostring(Store.readError))
end

-- A store written by the base64 version is still readable.
local legacy = Store.b64enc(Store:Encode({ WicksTestDB = { profiles = { Default = { nested = { a = 77 } } }, profileKeys = {}, keyMode = "char", global = {}, char = {} } }))
S.MACROS.acct = { S.MACROS.acct[1] }
for i = 1, math.ceil(#legacy / 240) do
    S.MACROS.acct[#S.MACROS.acct + 1] = { name = ("WickCfg%02d"):format(i), icon = 134400, body = legacy:sub((i - 1) * 240 + 1, i * 240) }
end
Store.cache = nil
local old = Store:Read()
check(old and old.WicksTestDB.profiles.Default.nested.a == 77, "macros written by the base64 version still decode")

-- The macros were not there yet. On a slow login they arrive after the
-- addon enabled; the store has to notice and put things back then.
S.MACROS.acct = { S.MACROS.acct[1] }
Store.cache, Store.restored, Store.waiting, Store.enabled, Store.optedIn = nil, {}, nil, nil, true
Store:Save(true)
local held = S.MACROS.acct
WicksTestDB = nil
-- Nothing at all from the server yet: not the player's macros either.
-- And nobody has said "on" this session; the only sign it should be on
-- is the macros themselves, which have not arrived.
Store.cache, Store.restored, Store.waiting, Store.enabled, Store.optedIn, Store.announced = nil, {}, nil, nil, nil, nil
S.MACROS.acct = {}
local C2 = Core:NewAddon("WicksTestLate", {
    title = "Late", savedVar = "WicksTestDB",
    defaults = { profile = { locked = false, nested = { a = 1 } } },
})
fire("ADDON_LOADED", "WicksTestLate")
check(C2.db.profile.nested.a == 1, "with no macros yet the addon runs on defaults")
check(Store.waiting == true, "and the store knows it is waiting")
check(Store.enabled == nil, "without having decided off, which a slow login would then be stuck with")
S.MACROS.acct = held
check(Store:Poll() == true, "when they arrive the poll sees them")
check(Store.enabled == true, "and seeing ours among them settles the store as on")
check(C2.db.profile.nested.a == 43, "and the late addon gets its settings")

-- The batch arrives with none of ours in it: that settles off, once.
Store.cache, Store.restored, Store.waiting, Store.enabled, Store.optedIn, Store.announced = nil, {}, nil, nil, nil, nil
S.MACROS.acct = {}
check(Store:Decide() == false and Store.waiting == true and Store.enabled == nil, "empty macro list again leaves it undecided")
S.MACROS.acct = { held[1] }
S.CHAT = {}
check(Store:Poll() == true and Store.enabled == false, "the player's macros alone settle it off")
check(#S.CHAT == 1 and S.CHAT[1]:find("store on"), "and the offer is said once: " .. tostring(S.CHAT[1]))
S.MACROS.acct = held
Store.cache, Store.enabled, Store.optedIn, Store.announced = nil, nil, nil, nil

-- Addons can be enabled per character, so a session is only ever a
-- subset of the account. Rebuilding the store from the addons loaded
-- right now erased every other one: settings set up on a hunter came
-- back as defaults after an hour on a warrior with the hunter kit
-- switched off. What the store holds for an addon that is not here has
-- to survive a save.
do
    -- A character where both addons ran.
    Store.cache, Store.restored, Store.enabled, Store.optedIn = nil, {}, nil, true
    local other = Core:NewAddon("WicksTestAbsent", {
        savedVar = "WicksAbsentDB", defaults = { profile = { keep = false } },
    })
    fire("ADDON_LOADED", "WicksTestAbsent")
    other.db.profile.keep = true
    -- Its own saved variable: earlier blocks left three addons sharing
    -- WicksTestDB to test rebinding, and whichever iterates last would
    -- decide what this one saw.
    local here = Core:NewAddon("WicksTestPresent", {
        savedVar = "WicksPresentDB", defaults = { profile = { n = 0 } },
    })
    fire("ADDON_LOADED", "WicksTestPresent")
    here.db.profile.n = 91
    check(Store:Save(true), "both addons save together")
    local both = Store:Read()
    check(both and both.WicksAbsentDB and both.WicksPresentDB, "and the store holds both")

    -- The next character does not load that one at all. Forget it the
    -- way a session that never saw it would.
    Core.addons.WicksTestAbsent = nil
    for i, name in ipairs(Core.order) do
        if name == "WicksTestAbsent" then table.remove(Core.order, i) break end
    end
    Store.cache, Store.lastEncoded = nil, nil
    check(Store:Carried()[1] == "WicksAbsentDB",
        "the store knows it is carrying something nothing here owns: " .. tostring(Store:Carried()[1]))

    here.db.profile.n = 92
    check(Store:Save(true), "the second character saves")
    Store.cache = nil
    local after = Store:Read()
    check(after and after.WicksPresentDB.profiles.Default.n == 92, "its own settings are current")
    check(after and after.WicksAbsentDB and after.WicksAbsentDB.profiles.Default.keep == true,
        "and the absent addon's settings are still there, not erased")

    -- Back on the first character, the addon gets its own settings back.
    Store.restored = {}
    WicksAbsentDB = nil
    local back = Core:NewAddon("WicksTestAbsent", {
        savedVar = "WicksAbsentDB", defaults = { profile = { keep = false } },
    })
    fire("ADDON_LOADED", "WicksTestAbsent")
    check(back.db.profile.keep == true, "and it comes back with them when it next loads")
end

-- Off means off: when the client does hand the table over, the store
-- must not put an old copy on top of it.
local handed = Core:NewAddon("WicksTestHanded", { savedVar = "WicksHandedDB", defaults = { profile = { v = 1 } } })
WicksHandedDB = { profiles = { Default = { v = 99 } }, profileKeys = {}, global = {}, char = {}, keyMode = "char" }
fire("ADDON_LOADED", "WicksTestHanded")
check(handed.db.handedOver == true, "a table the client supplied is recognised as such")
check(not Store:RestoreFor(handed) and handed.db.profile.v == 99, "and the store leaves it alone")

-- Turning off removes ours and only ours, and stays off.
local removed = Store:TurnOff()
check(removed >= 1 and #S.MACROS.acct == 1 and S.MACROS.acct[1].name == "ss", "off removes every WickCfg macro and nothing else")
A.db.profile.locked = true
Store:Dirty()
fire("PLAYER_REGEN_ENABLED")
check(#S.MACROS.acct == 1, "and nothing comes back afterwards")

-- The slash command speaks.
S.CHAT = {}
SlashCmdList.WICK_WICKCORE("store")
check(#S.CHAT >= 3, "/wickcore store reports")



io.write("\n", MODE, ": ", passes, " passed, ", fails, " failed\n")
if fails > 0 then error(MODE .. ": " .. fails .. " check(s) failed", 0) end
io.write("PASS\n")
