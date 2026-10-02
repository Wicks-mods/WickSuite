-- Wick's Gear, offline.
--   args: coreDir, addonsDir, mode, stubPath
--
-- The interesting parts are not that a list appears. They are that item
-- data is requested before anything is scored, that a class is never
-- offered gear it cannot wear, and that a piece is judged against what
-- is already on the character rather than in a vacuum.

local CORE_DIR, ADDONS_DIR, MODE, STUB = ...
local S = assert(loadfile(STUB))(MODE)

local failures, passes = 0, 0
local function check(cond, label)
    io.write(cond and "  ok    " or "  FAIL  ", label, "\n")
    if cond then passes = passes + 1 else failures = failures + 1 end
end

CLASS = "ROGUE"

S.loadAddon(CORE_DIR, "WickCore")   -- file list straight off WickCore.toc
S.fire("ADDON_LOADED", "WickCore")

io.write("== Wick's Gear ==\n")

-- Three pieces standing in for the real data: leather the rogue wants,
-- mail they cannot wear, and a two-hander they cannot wield.
S.ITEMS = {
    [7719] = { equipLoc = "INVTYPE_LEGS",  classID = 4, subClassID = 2,
               stats = { ITEM_MOD_AGILITY_SHORT = 9, ITEM_MOD_STAMINA_SHORT = 4 } },
    [6463] = { equipLoc = "INVTYPE_CHEST", classID = 4, subClassID = 3,
               stats = { ITEM_MOD_STRENGTH_SHORT = 8, ITEM_MOD_STAMINA_SHORT = 19 } },
    [7717] = { equipLoc = "INVTYPE_2HWEAPON", classID = 2, subClassID = 5,
               stats = { ITEM_MOD_STRENGTH_SHORT = 10 } },
}
S.UNCACHED = { [7719] = true, [6463] = true, [7717] = true }
S.REQUESTED = 0

local ns = S.loadAddon(ADDONS_DIR .. "/WicksGear", "WicksGear",
    { "Data.lua", "DataCrafted.lua", "DataQuests.lua", "DataSetBonus.lua", "Score.lua", "Core.lua", "Doll.lua", "UI.lua" })
S.fire("ADDON_LOADED", "WicksGear")
S.fire("PLAYER_LOGIN")

check(ns.DUNGEONS ~= nil and ns.DUNGEON_ORDER ~= nil, "the data file loaded")
check(#ns.DUNGEON_ORDER >= 10, #ns.DUNGEON_ORDER .. " dungeons carried")
local ids = ns.AllItemIDs()
check(#ids > 200, #ids .. " distinct items, deduplicated")
check(ns.WEIGHTS.ROGUE ~= nil and ns.PROFICIENCY.ROGUE ~= nil, "weights and proficiencies came with it")

-- The client answers item queries from the server and throttles hard,
-- so they leave in small batches rather than all at once. Asking for
-- everything the moment the window opened got most of them dropped.
S.UNCACHED = { [7719] = true, [6463] = true, [7717] = true }
S.REQUESTED = 0
local missing = ns.Score:Want({ 7719, 6463, 7717 })
check(missing == 3, "three unknown items are queued, got " .. missing)
check(S.REQUESTED > 0 and S.REQUESTED <= 12,
    "and they leave a batch at a time rather than in a flood: " .. S.REQUESTED)

-- The spacing itself cannot be seen here, because the stub runs timers
-- the instant they are set and the queue drains in one go. What can be
-- seen is that nothing is asked for twice, which is the other half of
-- not flooding the server.
S.REQUESTED = 0
S.UNCACHED = {}
local many = {}
for i = 1, 100 do many[i] = 900000 + i; S.UNCACHED[many[i]] = true end
ns.Score:Want(many)
check(S.REQUESTED == 100, "a hundred unknown items are each asked for: " .. S.REQUESTED)
S.REQUESTED = 0
ns.Score:Want(many)
check(S.REQUESTED == 0, "and asking again does not ask the server again: " .. S.REQUESTED)

-- Anything the client already knows is never asked for at all.
S.UNCACHED = {}
S.REQUESTED = 0
ns.Score:Want({ 7719, 6463 })
check(S.REQUESTED == 0, "known items are not requested, got " .. S.REQUESTED)

-- A name and a usable link without the server having answered, which is
-- the state a lot of items are actually in on this beta.
S.UNCACHED = { [7719] = true }
check(ns.Score:NameFor(7719) ~= nil, "a name comes from the client even when the item has not loaded")
check(ns.Score:LinkFor(7719) == "item:7719", "and a link can be built from the id: " .. ns.Score:LinkFor(7719))
check(ns.Score:Value("item:7719") > 0, "which is enough to read stats from")

-- The client cannot name an item the character has never met: of the
-- thirteen things in Gnomeregan it knew three. So the data file carries
-- a name and a stat line to fall back on, used only when the client has
-- nothing of its own to say.
S.UNCACHED = {}
S.UNKNOWN = { [9454] = true }   -- the client has never heard of this one
check(ns.ENTRY[9454] ~= nil, "the shipped entry is indexed by id")
check(ns.Score:NameFor(9454) == "Acidic Walkers",
    "an unknown item still has a name: " .. tostring(ns.Score:NameFor(9454)))
local fb = ns.Score:StatsOf(9454)
check(fb.int == 8 and fb.spi == 4, "and a stat line: int " .. tostring(fb.int))
check(ns.Score:Value(nil, 9454) > 0, "which is enough to score it")

-- The client's answer wins wherever it has one, because it is the one
-- this server is using.
S.UNKNOWN = {}
S.ITEMS[9454] = { equipLoc = "INVTYPE_FEET", classID = 4, subClassID = 2,
                  name = "Whatever The Client Says",
                  stats = { ITEM_MOD_AGILITY_SHORT = 99 } }
check(ns.Score:NameFor(9454) == "Whatever The Client Says",
    "the client overrides the shipped name")
local live = ns.Score:StatsOf(9454)
check(live.agi == 99 and live.int == nil, "and the shipped stats are not mixed in")

S.UNCACHED = {}   -- they have arrived now; the rest of the run assumes so

-- Proficiency. A rogue in mail, or holding a two-handed mace, is how you
-- can tell a gear list has never been used by anyone.
local leather = ns.Score:Info(7719)
local mail    = ns.Score:Info(6463)
local twoHand = ns.Score:Info(7717)
check(ns.Score:Usable(leather), "a rogue may wear leather")
check(not ns.Score:Usable(mail), "but not mail")
check(not ns.Score:Usable(twoHand), "and may not wield a two-handed mace")

-- Cloaks, rings and necks carry a negative subclass and no restriction.
S.ITEMS[9999] = { equipLoc = "INVTYPE_CLOAK", classID = 4, subClassID = -6 }
check(ns.Score:Usable(ns.Score:Info(9999)), "a cloak has no armour type to fail")

-- Scoring follows the weights: agility is a rogue's primary, stamina less.
S.LINK_TO_ID = { ["|Hitem:7719|h"] = 7719 }
local pts = ns.Score:Value("|Hitem:7719|h")
check(pts > 0, "leggings score something: " .. string.format("%.1f", pts))
local w = ns.WEIGHTS.ROGUE
check(math.abs(pts - (9 * w.agility + 4 * w.stamina)) < 0.01,
    "and score exactly agility and stamina by weight")

-- The same piece is worth less to someone who values agility less.
CLASS = "WARRIOR"
local warriorPts = ns.Score:Value("|Hitem:7719|h")
CLASS = "ROGUE"
check(warriorPts < pts, "a warrior values the same leggings lower: "
    .. string.format("%.1f vs %.1f", warriorPts, pts))

-- Judged against what is already worn, not in a vacuum.
S.EQUIPPED = { [7] = "|Hitem:7719|h" }
check(ns.Score:EquippedValue(7) > 0, "what you are wearing is read from the character")

-- The window.
ns.UI:Toggle()
local panel = _G.WicksGearPanel
check(panel ~= nil and panel:IsShown(), "the window opens")
check(ns.UI.tabs.upgrades ~= nil and ns.UI.tabs.browse ~= nil, "with both tabs")
ns.UI:Select("browse")
check(ns.UI.panes.browse:IsShown() and not ns.UI.panes.upgrades:IsShown(), "browse shows on its own")

-- The source strip belongs to Browse. It was parented to the panel, so
-- it stayed on screen over Upgrades and Compare: only the pane and its
-- head are shown and hidden when a tab changes.
local strip = ns.UI.panes.browse
check(strip.search:GetParent() == strip, "the search box belongs to the browse pane")
check(strip.equippable:GetParent() == strip, "so does the equippable toggle")
for key, b in pairs(strip.sourceBtns) do
    check(b:GetParent() == strip, "and the " .. key .. " button")
end
check(ns.UI.panes.upgrades.sourceBtns == nil, "upgrades never built a strip of its own")
check(ns.UI.panes.compare.sourceBtns == nil, "nor did compare")



local rows = 0
for _, r in ipairs(ns.UI.panes.browse.rows or {}) do if r:IsShown() then rows = rows + 1 end end
check(rows >= 10, "a row per dungeon, got " .. rows)

-- A dungeon opens to show what is in it.
local before = rows
ns.UI.panes.browse.open["The Deadmines"] = true
ns.UI:FillBrowse()
rows = 0
for _, r in ipairs(ns.UI.panes.browse.rows or {}) do if r:IsShown() then rows = rows + 1 end end
check(rows > before, "opening a dungeon lists its loot: " .. before .. " to " .. rows)

-- Twenty-eight dungeons and four hundred items, navigable only by opening
-- one dungeon at a time: there was no way to ask where boots drop or where
-- a named item comes from. Searching flattens the list, because a collapsed
-- dungeon hiding the match is the opposite of searching.
local function shownRows()
    local n = 0
    for _, r in ipairs(ns.UI.panes.browse.rows or {}) do if r:IsShown() then n = n + 1 end end
    return n
end
ns.UI.panes.browse.open["The Deadmines"] = false
ns.UI.search = "zzzznothing"
ns.UI:FillBrowse()
check(shownRows() == 0, "a search matching nothing shows nothing, got " .. shownRows())
check(ns.UI.panes.browse.empty:IsShown(), "and says so rather than going blank")

-- A dungeon name finds its loot without the dungeon being open.
ns.UI.search = "deadmines"
ns.UI:FillBrowse()
local byDungeon = shownRows()
check(byDungeon > 0, "searching a dungeon name finds its loot while it is collapsed: " .. byDungeon)

ns.UI.search = ""
ns.UI:FillBrowse()
check(shownRows() >= 10, "clearing the box puts the dungeon list back")

-- Four ways into the same pile of gear. Crafted has a skill where a
-- dungeon has a level bracket, a quest reward has a zone, and a set has
-- neither, so the group header stopped being dungeon shaped.
check(#(ns.CRAFTED_ORDER or {}) == 4, "four gear professions, got " .. #(ns.CRAFTED_ORDER or {}))
check(#(ns.QUESTS_ORDER or {}) > 10, "quest rewards across the zones, got " .. #(ns.QUESTS_ORDER or {}))

local order, groups = ns.UI:Groups("crafted")
check(#order == 4 and groups[order[1]] ~= nil, "the crafted source offers its professions")
check(groups[order[1]][1].skill ~= nil, "and a recipe carries the skill it is learned at")

order = ns.UI:Groups("sets")
check(#order > 10, "sets are built by walking the tables, got " .. #order)

-- Sets are not scraped as their own table; every entry carries the set
-- it belongs to and the view is assembled from that, so a crafted piece
-- joins its set with no emitter change.
local _, setGroups = ns.UI:Groups("sets")
local anySet, fromCrafted = nil, false
for name, rows in pairs(setGroups) do
    anySet = anySet or name
    for _, e in ipairs(rows) do if e.skill then fromCrafted = true end end
end
check(anySet ~= nil, "a set was found: " .. tostring(anySet))

ns.UI:SetSource("crafted")
check(ns.UI.source == "crafted", "switching source sticks")
check(shownRows() == 4, "and the list shows a row per profession, got " .. shownRows())
ns.UI.panes.browse.open["Blacksmithing"] = true
ns.UI:FillBrowse()
check(shownRows() > 4, "opening one lists what it makes")

ns.UI:SetSource("quests")
check(shownRows() == #ns.QUESTS_ORDER, "quests list a row per zone, got " .. shownRows())

-- The draw records what it produced, so an empty view can say whether
-- it had nothing to draw or drew nothing.
ns.UI:SetSource("crafted")
ns.UI:FillBrowse()
local f = ns.UI.lastFill
check(f and f.source == "crafted", "the last draw knows its source: " .. tostring(f and f.source))
check(f.groups == 4, "and how many groups it had: " .. tostring(f.groups))
check(f.rows == 4, "and how many rows it drew: " .. tostring(f.rows))

-- Put the source back: the next check measures quests first.
ns.UI:SetSource("quests")


-- Search spans whichever source is showing, which is why it was built
-- before the sources were. Matched on the slot rather than the item
-- name: the stub answers GetItemInfo for every id, so the shipped name
-- is never reached here, which is the one thing this harness cannot
-- exercise about searching.
ns.UI.search = "feet"
ns.UI:FillBrowse()
local inQuests = shownRows()
check(inQuests > 0, "a slot search finds quest rewards, got " .. inQuests)
ns.UI:SetSource("crafted")
ns.UI.search = "feet"
ns.UI:FillBrowse()
check(shownRows() > inQuests, "and the same search over crafted finds more: " .. shownRows() .. " against " .. inQuests)

-- Equippable. Dimming is enough for a dungeon's nine items and useless
-- against a profession's four hundred, most of which are the wrong
-- armour type for this class.
ns.UI:SetSource("crafted")
ns.UI.panes.browse.open["Leatherworking"] = true
ns.UI:FillBrowse()
local allRows = shownRows()

-- An item the client has not described yet is kept on purpose: hiding it
-- would make the list shrink as the answers arrive, which reads as the
-- addon losing things. So the stub has to actually know these three
-- before the filter has anything to act on. Plate, on a warrior who is
-- not high enough for it yet.
for _, id in ipairs({ 2302, 2303, 2307 }) do
    S.ITEMS[id] = { equipLoc = "INVTYPE_FEET", classID = 4, subClassID = 4 }
end
ns.db().onlyEquippable = true
ns.UI:FillBrowse()
local fitRows = shownRows()
check(fitRows == allRows - 3, "the toggle drops what this class cannot wear: " .. fitRows .. " of " .. allRows)
check(fitRows > 0, "and does not empty the list")

-- A group with nothing left for this class should not sit there as an
-- empty header inviting a click.
local names = {}
for _, r in ipairs(ns.UI.panes.browse.rows or {}) do
    if r:IsShown() then names[#names + 1] = tostring(r.left:GetText()) end
end
check(#names == fitRows, "every shown row accounted for")

ns.db().onlyEquippable = false
ns.UI.panes.browse.open["Leatherworking"] = false
for _, id in ipairs({ 2302, 2303, 2307 }) do S.ITEMS[id] = nil end

ns.UI:SetSource("dungeons")
ns.UI:FillBrowse()


-- Put the list back the way the next checks expect to find it.
ns.UI.panes.browse.open["The Deadmines"] = true
ns.UI:FillBrowse()


-- Gear the class cannot use has to be obvious at a glance. Muted grey
-- against off-white reads as the same colour at this size, so it is
-- darkened and the icon is desaturated too.
-- Both of these really do drop in the Deadmines, so they appear in the
-- list; the stub decides what they are made of.
S.ITEMS[10399] = { equipLoc = "INVTYPE_CHEST", classID = 4, subClassID = 2 }  -- leather
S.ITEMS[5202]  = { equipLoc = "INVTYPE_CHEST", classID = 4, subClassID = 3 }  -- call it mail
ns.UI:FillBrowse()
local dim, lit = 0, 0
for _, r in ipairs(ns.UI.panes.browse.rows or {}) do
    if r:IsShown() and r.itemID then
        if r.dimmed then dim = dim + 1 else lit = lit + 1 end
    end
end
check(lit > 0, "usable items stay lit, " .. lit .. " of them")
check(dim > 0, "and the ones a rogue cannot wear are dimmed, " .. dim .. " of them")

-- ---- the paperdoll ----------------------------------------------
-- Wearing leggings worth 4 agility, trying on a pair worth 9. The
-- interesting number is the difference, and what the difference does to
-- the character sheet.
S.EQUIPPED = { [7] = "|Hitem:old|h" }
S.LINK_TO_ID["|Hitem:old|h"] = 8888
S.ITEMS[8888] = { equipLoc = "INVTYPE_LEGS", classID = 4, subClassID = 2,
                  stats = { ITEM_MOD_AGILITY_SHORT = 4 } }

-- Trying something on has to work whether or not the doll has been
-- drawn yet. It is built on the first refresh now that the column is
-- always up, but a click can still arrive first.
local okEarly, errEarly = pcall(function() return ns.Doll:TryOn(7719) end)
check(okEarly, "trying a piece on does not error: " .. tostring(errEarly))
check(ns.Doll.pane ~= nil, "and the paperdoll exists to put it in")
ns.Doll:ClearAll()

ns.UI:Select("compare")
check(ns.Doll.pane ~= nil, "the paperdoll builds")
local slots = 0
for _ in pairs(ns.Doll.slots) do slots = slots + 1 end
check(slots == 15, "a button per equipment slot, got " .. slots)

check(ns.Doll:TryOn(7719), "a piece can be tried on")
check(ns.Doll.trying[7] ~= nil, "it lands in the slot it belongs to")
check(ns.Doll.slots[7].mark:IsShown(), "and the slot is marked as borrowed")


local d = ns.Doll:Deltas()
check(d.agi == 5, "agility delta is the difference, not the whole item: " .. tostring(d.agi))
check(d.sta == 4, "and stamina counts too, the old pair had none: " .. tostring(d.sta))

-- Derived numbers come from the client's own conversions rather than
-- formulas of ours, so they have to move with the stats.
ns.Doll:RefreshStats()
local function derived(label)
    for _, r in ipairs(ns.Doll:DerivedRows()) do
        if r.label == label then return r end
    end
end
local ap = derived("Attack power")
check(ap ~= nil, "attack power is derived")
check(ap and ap.delta == "+5",
    "five agility is five attack power at this stub's rate: " .. tostring(ap and ap.delta))
check(derived("Health") ~= nil, "and health, from the client's stamina conversion")
-- The total beside the change is the client's own reading. Ours would
-- be health from stamina, which is not the same number as your health.
check(ap and ap.value == "150",
    "the total beside it is what the unit says, in all three parts: " .. tostring(ap and ap.value))
check(derived("Health").value == "500", "and health reads the unit rather than our conversion")

-- This client hands some unit values back as secrets: they can be shown
-- but not added to, and the addition throws in our name. That is exactly
-- what UNIT_STATS did in game. With the totals out of reach the deltas
-- are still entirely ours, so the panel has to keep working on them.
local realStat, realArmor = UnitStat, UnitArmor
local secret = setmetatable({}, {
    __add = function() error("attempt to perform arithmetic on a secret number value") end,
    __sub = function() error("attempt to perform arithmetic on a secret number value") end,
})
UnitStat = function() return secret, secret, 0, 0 end
UnitArmor = function() return secret, secret, 0, 0, 0 end
-- A stat being withheld means the total built from it is withheld too.
S.AP_SECRET = true
local okSecret, errSecret = pcall(ns.Doll.RefreshStats, ns.Doll)
check(okSecret, "secret stats do not throw: " .. tostring(errSecret))
local sap = derived("Attack power")
check(sap ~= nil, "and the derived change still comes out, from the delta alone")
check(sap and sap.delta == "+5", "with the same answer the readable path gave: "
    .. tostring(sap and sap.delta))
check(sap and sap.value == "-", "while the total says so rather than guessing: "
    .. tostring(sap and sap.value))
S.AP_SECRET = nil
local shown
for i, key in ipairs(ns.Score.STAT_ORDER) do
    if key == "agi" then shown = ns.Doll.statRows[i] end
end
check(shown and shown.delta:GetText() == "+5",
    "the change is still shown even though the total cannot be")
check(shown and not (shown.value:GetText() or ""):find("table"),
    "and no raw table leaks into the total: " .. tostring(shown and shown.value:GetText()))
UnitStat, UnitArmor = realStat, realArmor
ns.Doll:RefreshStats()

io.write("== the wardrobe ==\n")
do
    ns.Doll:ClearAll()
    -- On the real client GetItemInfoInstant answers for any id, cached
    -- or not. The stub answers only for what a check has staged, so
    -- stage a whole set: a wardrobe holding one piece is not the thing
    -- being checked here.
    for id, loc in pairs({ [10399] = "INVTYPE_CHEST", [10402] = "INVTYPE_FEET",
                           [10401] = "INVTYPE_HAND",  [10400] = "INVTYPE_LEGS",
                           [10403] = "INVTYPE_WAIST" }) do
        S.ITEMS[id] = { equipLoc = loc, classID = 4, subClassID = 2 }
    end
    ns.Score:ForgetSetCache()
    local sets = ns.Score:WearableSets()
    local all = ns.Score:SetGroups()
    check(#sets > 0, "there are sets to page through, got " .. #sets)
    -- A rogue is not paging past plate. The list of sets the class can
    -- wear is shorter than the list of sets.
    check(#sets < #all, "and it is only the ones a rogue can wear: "
        .. #sets .. " of " .. #all)

    -- One redraw for the set, not one per piece: TryOn is called with
    -- the quiet flag and Changed comes after the loop.
    local redraws = 0
    local realRefresh = ns.UI.Refresh
    ns.UI.Refresh = function(self) redraws = redraws + 1 return realRefresh(self) end
    local worn = ns.Doll:WearSet(sets[1])
    ns.UI.Refresh = realRefresh
    check(worn > 1, "wearing a set puts several pieces on, got " .. worn)
    check(redraws == 1, "and redraws the window once, not once per piece: " .. redraws)

    local slots, pieces = {}, 0
    for slotId, t in pairs(ns.Doll.trying) do
        if not t.empty then
            pieces = pieces + 1
            check(slots[slotId] == nil, "one piece per slot")
            slots[slotId] = true
            local info = ns.Score:Info(t.id)
            check(info and ns.Score:Usable(info),
                "and nothing the class cannot wear: " .. tostring(t.id))
        end
    end
    check(pieces == worn, "every piece it counted is on the doll: "
        .. pieces .. " against " .. worn)

    check(ns.Doll.setOn == sets[1], "the column knows which set that was")
    local label = ns.Doll.setLabel:GetText() or ""
    check(label:find(sets[1], 1, true) ~= nil, "and says so over the model: " .. label)
    check(label:find("1 of " .. #sets, 1, true) ~= nil,
        "with where it sits in the list: " .. label)

    -- Stepping back from the first wraps to the last rather than
    -- stopping, so the arrows never do nothing.
    ns.Doll:StepSet(-1)
    check(ns.Doll.setOn == sets[#sets], "stepping back from the first wraps to the last: "
        .. tostring(ns.Doll.setOn))
    ns.Doll:StepSet(1)
    check(ns.Doll.setOn == sets[1], "and forward comes back round")

    -- The readings under the model are about the whole set now.
    local d = ns.Doll:Deltas()
    local moved = 0
    for _ in pairs(d) do moved = moved + 1 end
    check(moved > 0, "the readings move for a set, not just a piece: " .. moved .. " stats")

    -- Picking something by hand is no longer that set, and the label
    -- has to stop claiming it is.
    ns.Doll:TryOn(7719)
    check(ns.Doll.setOn == nil, "trying a piece on by hand drops the set name")
    ns.Doll:RefreshStats()
    check((ns.Doll.setLabel:GetText() or ""):find("Pick a set") ~= nil,
        "and the label says so: " .. tostring(ns.Doll.setLabel:GetText()))

    ns.Doll:ClearAll()
    check(next(ns.Doll.trying) == nil, "taking it all off clears the pieces")
    check(ns.Doll.setOn == nil, "and the set with them")
end

io.write("== turning the model ==\n")
do
    local m = ns.Doll.model
    ns.Doll:Face(0)

    -- Drag across the model. The cursor is read twice per step, so it
    -- is moved between the calls the way a hand would move it.
    local realCursor = GetCursorPosition
    local at = 100
    GetCursorPosition = function() return at, 0 end
    m.__scripts.OnMouseDown(m, "LeftButton")
    at = 160
    m.__scripts.OnUpdate(m)
    check(ns.Doll.facing > 0, "dragging right turns the character: " .. tostring(ns.Doll.facing))
    check(m.__facing == ns.Doll.facing, "and the model is the thing told, not just our own note")

    -- A drag the other way comes back, so the two are the same handle
    -- rather than one that only winds up.
    local wasAt = ns.Doll.facing
    at = 40
    m.__scripts.OnUpdate(m)
    check(ns.Doll.facing < wasAt, "and dragging back turns it the other way")

    -- Let go, and the model stops following the cursor.
    m.__scripts.OnMouseUp(m, "LeftButton")
    local held = ns.Doll.facing
    at = 900
    m.__scripts.OnUpdate(m)
    check(ns.Doll.facing == held, "letting go stops it following the cursor")

    -- The one that bites: redressing calls SetUnit, which puts the
    -- character back to front-on, and the column redresses every time
    -- you try a piece on.
    ns.Doll:Face(2.5)
    ns.Doll:TryOn(7719)
    check(ns.Doll.facing == 2.5, "trying a piece on does not straighten it")
    check(m.__facing == 2.5, "and the model is turned back after the redress: "
        .. tostring(m.__facing))
    ns.Doll:ClearAll()

    m.__scripts.OnMouseDown(m, "RightButton")
    check(ns.Doll.facing == 0, "right-click puts it back to front-on")

    -- A model is not a frame and will not take a click handler. Asking
    -- for one raises in the game, which is how this was found.
    local okDbl = pcall(m.SetScript, m, "OnDoubleClick", function() end)
    check(not okDbl, "and a model still refuses a double-click handler")
    GetCursorPosition = realCursor
end


-- On this beta the client only knows an item the character has actually
-- met. Asking it for a tooltip on any other one gives "Retrieving item
-- information" forever, because the data is never coming. So when the
-- client cannot answer, the tooltip is built from what we shipped.
do
    -- Pick one the client knows nothing about, the way the beta leaves
    -- most of this list.
    local uncached = nil
    for _, id in ipairs(ns.AllItemIDs()) do
        if ns.ENTRY[id] and ns.ENTRY[id].name ~= "" and ns.ENTRY[id].stats then
            uncached = id
            break
        end
    end
    -- Server data missing, client files still there: that is exactly
    -- the beta's state. GetItemInfo goes quiet, GetItemInfoInstant
    -- still answers with the slot.
    S.ITEMS = S.ITEMS or {}
    S.ITEMS[uncached] = { name = ns.ENTRY[uncached].name, type = "Armor",
                          equipLoc = "INVTYPE_CLOAK", classID = 4, subClassID = -6 }
    S.UNCACHED = S.UNCACHED or {}
    S.UNCACHED[uncached] = true
    S.UNKNOWN = S.UNKNOWN or {}
    S.UNKNOWN[uncached] = true
    check(uncached ~= nil and not ns.Score:Cached(uncached),
        "the stub has an item the client cannot describe")
    if uncached then
        local e = ns.ENTRY[uncached]
        GameTooltip:ClearLines()
        local fromGame = ns.Score:FillTooltip(GameTooltip, uncached, ns.Score:LinkFor(uncached))
        local text = GameTooltip:Text()
        check(not fromGame, "the game is not asked for one it cannot answer")
        check(text:find(e.name, 1, true) ~= nil,
            "the item is named from our own data: " .. text:sub(1, 48))
        check(text:find("Retrieving") == nil, "and never says Retrieving item information")
        check(text:find(e.dungeon, 1, true) ~= nil, "with where it drops")
        check(text:find("what you are wearing") ~= nil or text:find("No change") ~= nil,
            "and what it would change against what is worn")
    end

    -- Shift-click has to produce something chat will accept. An item link
    -- is a fixed shape on any given build, and "|Hitem:279899|h" is not
    -- it: that one field version carried everything a receiving client
    -- needs and still would not go in the chat box, which is what the
    -- player saw as "most of them will not link".
    --
    -- So the shape is learned off a link the client itself made, from the
    -- gear on the player's back, rather than guessed at.
    local worn = "|cff1eff00|Hitem:12345:0:0:0:0:0:0:0:60:0:0:0:0:0:0:0:0|h[Worn Thing]|h|r"
    S.EQUIPPED = { [1] = worn }
    ns.Score:LearnLinkShape()
    local fields = ns.Score:LinkFields()
    check(fields == 17, "the link shape is read off what the player is wearing, got " .. tostring(fields))

    local link, source = ns.Score:ChatLink(uncached)
    check(link ~= nil and link:find("|Hitem:" .. uncached, 1, true) ~= nil,
        "an uncached item still gets a chat link: " .. tostring(link))
    check(source == "built", "and it is ours, not the client's: " .. tostring(source))
    check(link:find("[" .. ns.ENTRY[uncached].name .. "]", 1, true) ~= nil and link:sub(-4) == "|h|r",
        "a well formed one, with the name in brackets")

    -- The part that was actually broken: ours has to have as many fields
    -- as the client's own, or the chat box will not take it.
    local function fieldsIn(l)
        local payload = l:match("|Hitem:([^|]*)|h")
        local n = 1
        for _ in payload:gmatch(":") do n = n + 1 end
        return n
    end
    check(fieldsIn(link) == fieldsIn(worn),
        ("ours carries the same field count as the client's, %d against %d")
            :format(fieldsIn(link), fieldsIn(worn)))

    -- A build that shapes links differently is followed, not argued with.
    S.EQUIPPED = { [1] = "|cffffffff|Hitem:99:0:0:0|h[Short]|h|r" }
    check(fieldsIn(ns.Score:ChatLink(uncached)) == 17,
        "a shape already learned is not thrown away by a later read")

    S.UNCACHED[uncached] = nil
    S.UNKNOWN[uncached] = nil

    -- An item the client does know is still the client's to describe.
    local known = ns.AllItemIDs()[2]
    if ns.Score:Cached(known) then
        GameTooltip:ClearLines()
        local fromGame = ns.Score:FillTooltip(GameTooltip, known, ns.Score:LinkFor(known))
        check(fromGame, "a cached item still goes to the game, whose answer is the real one")
    end

end

-- A class that cannot use it is refused rather than silently accepted.
check(not ns.Doll:TryOn(6463), "mail is refused for a rogue")

-- Mail and plate are trained at forty. A hunter is listed as wearing
-- mail, which was true of the character sheet and false of a level
-- twenty hunter, who was being told to go and find mail.
do
    local realClass, realLevel = CLASS, S.LEVEL
    CLASS = "HUNTER"
    local mail = { classID = 4, subClassID = 3 }
    local leather = { classID = 4, subClassID = 2 }
    S.LEVEL = 20
    check(not ns.Score:Usable(mail), "a level twenty hunter is not shown mail")
    check(ns.Score:Usable(leather), "but leather is still theirs")
    S.LEVEL = 40
    check(ns.Score:Usable(mail), "and at forty the mail appears")
    CLASS = "ROGUE"
    S.LEVEL = 60
    check(not ns.Score:Usable(mail), "a rogue never gets it, whatever the level")
    CLASS, S.LEVEL = realClass, realLevel
end

ns.Doll:Clear(7)
check(ns.Doll.trying[7] == nil, "right-click puts it back")
check(next(ns.Doll:Deltas()) == nil, "and the deltas go with it")

-- Item data arrives from the server a few at a time. Whatever had not
-- turned up when the list was drawn used to sit there reading "item
-- 9454" until you closed and reopened the window.
ns.UI:Select("browse")
ns.UI.panes.browse.open["The Deadmines"] = true
ns.UI:FillBrowse()
local before
for _, r in ipairs(ns.UI.panes.browse.rows or {}) do
    if r:IsShown() and r.itemID == 5202 then before = r.left:GetText() end
end
check(before ~= nil, "the row is on screen")

ns.UI.redrawQueued = nil
S.fire("ITEM_DATA_LOAD_RESULT", 5202, true)
check(ns.UI.redrawQueued == nil, "a late arrival triggers a redraw rather than being ignored")

-- Arrivals come in floods, so the redraw is coalesced behind a flag.
-- The stub runs timers the instant they are set, so the coalescing
-- itself cannot be observed here; what can is that the flag stops a
-- second redraw being queued while one is already waiting.
local drew = 0
local realFill = ns.UI.FillBrowse
ns.UI.FillBrowse = function(self) drew = drew + 1 return realFill(self) end
ns.UI.redrawQueued = true          -- pretend one is already pending
for i = 1, 20 do S.fire("ITEM_DATA_LOAD_RESULT", 5202, true) end
ns.UI.FillBrowse = realFill
check(drew == 0, "arrivals are ignored while a redraw is already queued, got " .. drew)
ns.UI.redrawQueued = nil

S.CHAT = {}
SlashCmdList.WICKSGEAR("browse")
check(true, "/wgear browse does not error")

-- What a click on a row does. Rows are pooled, and one used as a group
-- header carries the header's toggle, so an item row has to take its own
-- handler back or clicking the item reopens the group.
ns.UI:SetSource("dungeons")
ns.UI.panes.browse.open["The Deadmines"] = true
ns.UI:FillBrowse()
local itemRow, wearRow
for _, r in ipairs(ns.UI.panes.browse.rows) do
    if r:IsShown() and r.itemID then
        itemRow = itemRow or r
        -- Not every row in the data has an equip slot, and the doll
        -- rightly refuses what you cannot wear, so the try-on check
        -- needs a row that is actually a piece of gear.
        -- The doll refuses what you cannot wear and what your class
        -- cannot use, both rightly, so the try-on check needs a row
        -- that clears both.
        local info = ns.Score:Info(r.itemID)
        if info and info.slot and ns.Score:Usable(info) and not wearRow then wearRow = r end
    end
end
check(itemRow ~= nil, "found an item row to click")
check(wearRow ~= nil, "and one this class can actually wear")
check(itemRow.__scripts.OnClick == ns.UI.RowClick,
    "an item row carries the item handler, not a header toggle")

-- Rows are pooled, so one drawing a group header was an item a moment
-- ago. A font string is not clipped by its frame, so an item's stats
-- and source lines carried on drawing past the bottom of a 22 point
-- header and into the header below: every collapsed set had somebody
-- else's armour values stacked underneath it.
do
    ns.UI:SetSource("sets")
    ns.UI.panes.browse.open = {}
    ns.UI:FillBrowse()
    local heads, dirty = 0, nil
    for _, r in ipairs(ns.UI.panes.browse.rows) do
        if r:IsShown() and not r.itemID then
            heads = heads + 1
            local st = tostring(r.stats:GetText() or "")
            local md = tostring(r.mid:GetText() or "")
            if st ~= "" or md ~= "" then dirty = st .. " / " .. md end
        end
    end
    check(heads > 0, "collapsed groups draw headers, got " .. heads)
    check(dirty == nil, "and no header carries an item's lines: " .. tostring(dirty))

    -- What a header does have to say goes on its own line.
    local withNote
    for _, r in ipairs(ns.UI.panes.browse.rows) do
        if r:IsShown() and not r.itemID and tostring(r.note2:GetText() or "") ~= "" then
            withNote = r.note2:GetText()
        end
    end
    check(withNote ~= nil, "a set header still says what the next bonus needs: " .. tostring(withNote))

    -- A group has to look like a group, and an item like an item.
    ns.UI.panes.browse.open["Devilsaur Armor"] = nil
    ns.UI:SetSource("dungeons")
    ns.UI.panes.browse.open["The Deadmines"] = true
    ns.UI:FillBrowse()
    local head, item
    for _, r in ipairs(ns.UI.panes.browse.rows) do
        if r:IsShown() then
            if r.itemID then item = item or r else head = head or r end
        end
    end
    check(head ~= nil and item ~= nil, "the list has both a header and an item")
    check(head.headBg:IsShown() and head.headRule:IsShown(), "the header wears its bar")
    check(not head.iconEdge:IsShown(), "and no icon frame, having no icon")
    check(item.iconEdge:IsShown(), "the item wears the icon frame")
    check(not item.headBg:IsShown(), "and not the header bar")

    -- Banding is per item, so a header does not take a turn and leave
    -- two same-shaded rows touching underneath it.
    local seen, alt = 0, true
    for _, r in ipairs(ns.UI.panes.browse.rows) do
        if r:IsShown() and r.itemID then
            seen = seen + 1
            if r.stripe:IsShown() ~= (seen % 2 == 1) then alt = false end
        end
    end
    check(seen > 2, "enough item rows to band, got " .. seen)
    check(alt, "and they alternate")
end

-- Once the doll holds several pieces, nothing in the list said which.
do
    -- Through the real path: Refresh does nothing while the window is
    -- closed, so a check that fills the list by hand would never notice
    -- ClearAll failing to redraw it.
    ns.UI:Build()
    ns.UI.panel:Show()
    ns.UI:Select("browse")
    ns.UI:SetSource("dungeons")
    ns.UI.panes.browse.open["The Deadmines"] = true
    ns.Doll:ClearAll()
    ns.UI:FillBrowse()
    local target
    for _, r in ipairs(ns.UI.panes.browse.rows) do
        if r:IsShown() and r.itemID then
            local info = ns.Score:Info(r.itemID)
            if info and info.slot and ns.Score:Usable(info) and not target then target = r end
        end
    end
    check(target ~= nil, "found a wearable row to preview")
    check(target.previewed == false, "nothing is lit before anything is tried on")

    local id = target.itemID
    ns.Doll:TryOn(id)
    local lit
    for _, r in ipairs(ns.UI.panes.browse.rows) do
        if r:IsShown() and r.itemID == id then lit = r.previewed end
    end
    check(lit == true, "the previewed row is lit: " .. tostring(lit))

    -- Taking it off has to clear the list by itself. ClearAll redrew
    -- the doll and not the list, so "Take it all off" left every row
    -- still lit until something else happened to redraw it.
    ns.Doll:ClearAll()
    local still
    for _, r in ipairs(ns.UI.panes.browse.rows) do
        if r:IsShown() and r.itemID == id then still = r.previewed end
    end
    check(still == false, "and goes out when it comes off, with no extra redraw: "
        .. tostring(still))

    -- One slot at a time, the same way.
    ns.Doll:TryOn(id)
    local info = ns.Score:Info(id)
    ns.Doll:Clear(info.slot)
    local afterOne
    for _, r in ipairs(ns.UI.panes.browse.rows) do
        if r:IsShown() and r.itemID == id then afterOne = r.previewed end
    end
    check(afterOne == false, "clearing one slot clears its row too: " .. tostring(afterOne))

    -- The row lights to say the piece is on the doll, so clicking a lit
    -- row is how you take it off. It used to do nothing: TryOn put the
    -- same item in the same slot again and nothing changed.
    local row
    for _, r in ipairs(ns.UI.panes.browse.rows) do
        if r:IsShown() and r.itemID == id then row = r end
    end
    check(row ~= nil, "found the row again")
    row.__scripts.OnClick(row, "LeftButton")
    check(ns.Doll:IsTrying(id), "one click puts it on")
    row.__scripts.OnClick(row, "LeftButton")
    check(not ns.Doll:IsTrying(id), "and a second click takes it off")
    local after
    for _, r in ipairs(ns.UI.panes.browse.rows) do
        if r:IsShown() and r.itemID == id then after = r.previewed end
    end
    check(after == false, "with the highlight going out: " .. tostring(after))

    ns.Doll:ClearAll()
end

-- Plain click: our own viewer, which sits beside the list rather than
-- behind a tab. The point of the split is that the list does not move
-- under you while you work down it.
ns.UI:Select("browse")
S.DRESSED = nil
ns.Doll:ClearAll()
wearRow.__scripts.OnClick(wearRow, "LeftButton")
check(next(ns.Doll.trying) ~= nil, "clicking a row tries it on")
check(ns.UI.active == "browse",
    "and leaves you in the list: " .. tostring(ns.UI.active))
check(ns.UI.panes.compare:IsShown(), "the compare column is up regardless")

-- The stacked doll has to fit the column it now lives in. It ran eight
-- points past the bottom at the first height tried, straight through
-- the "Take it all off" button.
do
    local cmp = ns.UI.panes.compare
    local D = ns.Doll
    check(D.model ~= nil and D.summary ~= nil, "the doll is built in the column")
    local w = tonumber(cmp:GetWidth()) or 0
    local panelW = tonumber(ns.UI.panel:GetWidth()) or 0
    local share = panelW > 0 and (w / panelW) or 0
    check(share > 0.33 and share < 0.45,
        ("the column is the smaller share of the window: %d of %d"):format(w, panelW))

    -- Nothing may hang off the right edge: that was the whitespace
    -- complaint in reverse.
    local mw = tonumber(D.model:GetWidth()) or 0
    check(mw > 0 and mw <= w - 8, "the model fits the column: " .. tostring(mw) .. " in " .. tostring(w))

    -- The search box and the Equippable toggle belong to the list, not
    -- the window. Anchored to the panel they sat on top of the compare
    -- column, over the paperdoll's own slots.
    local br = ns.UI.panes.browse
    for _, part in ipairs({ { br.search, "the search box" },
                            { br.equippable, "the Equippable toggle" } }) do
        local fr, label = part[1], part[2]
        check(fr ~= nil, label .. " exists")
        if fr then
            local rel
            for _, pt in ipairs(fr.__points or {}) do rel = pt[2] or rel end
            check(rel == br, label .. " follows the list pane, not the window")
        end
    end
    for key, b in pairs(br.sourceBtns or {}) do
        local rel
        for _, pt in ipairs(b.__points or {}) do rel = pt[2] or rel end
        check(rel == br, "the " .. tostring(key) .. " button follows the list pane too")
    end

    -- And the bottom. The column's own height comes from anchors, which
    -- the stub does not resolve, so it is worked out from the window
    -- and the header the way the real frame will be. Everything above
    -- the set bonuses sits at a fixed offset; the bonuses take what is
    -- left and scroll inside it, so what has to hold is that there is
    -- something left worth having.
    local y = 0
    for _, pt in ipairs(D.summary.__points or {}) do
        if type(pt[5]) == "number" then y = pt[5] end
    end
    local panelH = tonumber(ns.UI.panel:GetHeight()) or 0
    local tabH = tonumber(ns.UI.tabs.browse:GetHeight()) or 0
    local avail = panelH - WickCore.Chrome.HEADER_H - tabH - 4 - 10
    -- The summary owns the 30 above the bonus scroll, and four lines of
    -- bonuses is the least worth drawing before it has to scroll.
    check(avail > 0 and (-y + 30 + 60) <= avail,
        "the bonuses have room under the readings: needs " .. tostring(-y + 90)
        .. " of " .. tostring(avail))
end
check(S.DRESSED == nil, "and does not open the dressing room")

-- Ctrl-click: the game's dressing room, and not our tab.
ns.UI:Select("browse")
S.CTRL = true
itemRow.__scripts.OnClick(itemRow, "LeftButton")
S.CTRL = false
check(S.DRESSED ~= nil, "ctrl-click sends it to the dressing room: " .. tostring(S.DRESSED))
check(ns.UI.active == "browse", "and leaves you where you were")

-- Set bonuses. The count comes off the equipped slots so it is right
-- for this build; the bonus text is Classic's, because Forever
-- publishes none, and the addon has to say so rather than pass it off.
local setName, setIds = nil, {}
for id, e in pairs(ns.ENTRY) do
    if e.set and (ns.SET_BONUS or {})[e.set] then
        setName = setName or e.set
        if e.set == setName then setIds[#setIds + 1] = id end
    end
end
check(setName ~= nil, "a set with bonuses is in the data: " .. tostring(setName))

S.EQUIPPED_IDS = {}
local prog = ns.Score:SetProgress(setName)
check(prog ~= nil and prog.worn == 0, "wearing none of it: " .. tostring(prog and prog.worn))
check(prog.total == #setIds, "and it knows how many pieces there are: " .. prog.total)
check(#prog.earned == 0, "so no bonus is earned")
check(prog.next ~= nil, "but it names the next one: " .. tostring(prog.next and prog.next.pieces))
check(prog.approximate == true, "and flags the bonuses as not this build's own")

-- Wear enough for the first bonus.
local need = prog.next.pieces
for i = 1, need do S.EQUIPPED_IDS[i] = setIds[i] end
prog = ns.Score:SetProgress(setName)
check(prog.worn == need, "wearing " .. need .. " of them: " .. prog.worn)
check(#prog.earned >= 1, "earns the bonus, got " .. #prog.earned)
check(prog.earned[1].pieces <= need, "and it is one the count actually reaches")

-- Where the bonus is shown. It used to be rows in the list, in a column
-- sized for one line of item name, carrying three lines of bonus text;
-- it wrapped into the row beneath and looked broken. An earned bonus is
-- a thing you are currently getting, so it reads with the stats.
do
    local got = ns.Score:EquippedSetBonuses()
    check(#got >= 1, "the gear on your back reports its earned bonuses, got " .. #got)
    check(got[1].set == setName and got[1].text ~= nil,
        "naming the set and what it gives: " .. tostring(got[1].set))
    check(got[1].worn == need, "with what you are wearing of it: " .. tostring(got[1].worn))

    -- Only the earned ones. What a set would give at four pieces when
    -- you have two is not a readout of your character.
    for _, g in ipairs(got) do
        check(g.pieces <= need, "nothing unearned is listed: " .. tostring(g.pieces))
    end

    -- And the list is out of the business.
    ns.UI:SetSource("sets")
    ns.UI.panes.browse.open[setName] = true
    ns.UI:FillBrowse()
    local leaked
    for _, r in ipairs(ns.UI.panes.browse.rows) do
        if r:IsShown() and tostring(r.left:GetText() or ""):find("pieces:", 1, true) then
            leaked = r.left:GetText()
        end
    end
    check(leaked == nil, "no bonus rows in the list: " .. tostring(leaked))

    -- The doll prints them beside the stats.
    if ns.Doll:Ensure() then ns.Doll:Refresh() end
    -- Read as rows rather than as one formatted string: the count and
    -- the sentence are separate columns now, so a wrapped sentence
    -- lands under the sentence instead of under the count.
    local shownRows = ns.Doll:BonusRows()
    local named
    for _, r in ipairs(shownRows) do if r.set == setName then named = true end end
    check(named == true, "the set reaches the column, rows: " .. #shownRows)

    -- The column exists to show what a change would do, so a bonus the
    -- change would earn is exactly what it should say. Two pieces tried
    -- on and no two-piece bonus shown was the whole complaint.
    S.EQUIPPED_IDS = {}
    ns.Doll:ClearAll()
    if ns.Doll:Ensure() then ns.Doll:Refresh() end
    check(#ns.Doll:BonusRows() == 0,
        "wearing none of the set and trying none on, nothing is claimed")

    -- The set pieces are ids out of the shipped data, which the stub
    -- client knows nothing about, so the doll cannot place them. Give
    -- them slots this class can wear, one each, so the preview has
    -- something real to hold.
    local LOCS = { "INVTYPE_CHEST", "INVTYPE_LEGS", "INVTYPE_HEAD",
                   "INVTYPE_FEET", "INVTYPE_HAND", "INVTYPE_WAIST" }
    for n, id in ipairs(setIds) do
        S.ITEMS[id] = { equipLoc = LOCS[n] or "INVTYPE_CHEST",
                        classID = 4, subClassID = 2, stats = {} }
    end
    ns.Score:ForgetSetCache()

    -- Distinct slots: two pieces of a set can be the same slot, and one
    -- would simply replace the other on the doll.
    local put = 0
    for _, id in ipairs(setIds) do
        if put < need then
            local info = ns.Score:Info(id)
            if info and info.slot and not ns.Doll.trying[info.slot] then
                ns.Doll.trying[info.slot] = { id = id, link = ns.Score:LinkFor(id) }
                put = put + 1
            end
        end
    end
    check(put == need, "put " .. need .. " pieces into the preview, got " .. put)
    ns.Doll:Refresh()
    local rows = ns.Doll:BonusRows()
    local header, bonus
    for _, r in ipairs(rows) do
        if r.kind == "set" and r.set == setName then header = r end
        if r.kind == "bonus" and r.set == setName then bonus = bonus or r end
    end
    check(header ~= nil, "the previewed pieces earn the bonus, rows: " .. #rows)
    check(bonus ~= nil, "with a bonus line under the set line")
    -- Each bonus carries the count it needs, not how much of the set is
    -- on: four bonuses of one set all read 4/8 before.
    check(bonus and bonus.pieces <= need and bonus.total == prog.total,
        "the line carries its own threshold over the set total: "
        .. tostring(bonus and bonus.pieces) .. "/" .. tostring(bonus and bonus.total))
    check(bonus and bonus.have == false,
        "and is flagged as one the preview would earn, not one you have")

    -- Drawn as two columns, so a sentence that wraps lands under the
    -- sentence and not under the count. One font string for both is
    -- what put the second line back at the left margin.
    ns.Doll:DrawBonuses()
    local drawn
    for _, r in ipairs(ns.Doll.setRows or {}) do
        if r:IsShown() and tostring(r.num:GetText() or "") ~= "" then drawn = r end
    end
    check(drawn ~= nil, "a bonus row is drawn")
    if drawn then
        check(tostring(drawn.num:GetText()):find("/", 1, true) ~= nil,
            "the count has its own field: " .. tostring(drawn.num:GetText()))
        check(tostring(drawn.text:GetText() or "") ~= "", "and the sentence its own")
        local tw = tonumber(drawn.text:GetWidth()) or 0
        local rw = tonumber(drawn:GetWidth()) or 0
        check(tw > 0 and tw < rw,
            "the sentence wraps inside its own column, not the whole row: "
            .. tostring(tw) .. " of " .. tostring(rw))
    end

    -- And SetProgress on its own counts what it is handed.
    local prev = ns.Score:SetProgress(setName, ns.Doll:Wearing())
    check(prev.worn == need, "progress counts the preview: " .. tostring(prev.worn))
    local bare = ns.Score:SetProgress(setName)
    check(bare.worn == 0, "while the equipped count is untouched: " .. tostring(bare.worn))
    ns.Doll:ClearAll()
end

-- An item the client has never seen gets our tooltip, which said
-- nothing about sets at all. Those are exactly the items it will draw.
do
    local id = setIds[1]
    S.CACHED = S.CACHED or {}
    local tt = S.newTooltip and S.newTooltip() or nil
    if tt == nil then
        tt = { lines = {} }
        function tt:SetText(t) self.lines = { tostring(t) } end
        function tt:AddLine(t) self.lines[#self.lines + 1] = tostring(t) end
        function tt:AddDoubleLine(a, b) self.lines[#self.lines + 1] = tostring(a) .. " " .. tostring(b) end
        function tt:SetHyperlink() self.hyper = true end
        function tt:Show() end
    end
    ns.Score:FillTooltip(tt, id, nil)
    local body = table.concat(tt.lines or {}, " | ")
    check(tt.hyper or body:find(setName, 1, true) ~= nil,
        "our own tooltip names the set: " .. body:sub(1, 90))
end

-- The client's own tooltip beats the scrape, because the tooltip is this
-- build and Classic's numbers are only a guess at it. Both wordings are
-- accepted, since the phrasing has moved across expansions.
S.TOOLTIP_LINES_FOR = { "Some Armour", "(2) Set: +10 Forever Bonus.",
                        "4 pieces: +20 Forever Bonus." }
-- What the client will say has just changed, which is the same thing
-- that happens in game when item data finally arrives.
ns.Score:ForgetSetCache()
local other
for _, e in pairs(ns.ENTRY) do
    if e.set and e.set ~= setName then other = e.set break end
end
local fromClient = ns.Score:ClientSetBonuses(other)
check(fromClient ~= nil and #fromClient == 2,
    "both tooltip wordings are read: " .. tostring(fromClient and #fromClient))
check(fromClient[1].pieces == 2 and fromClient[2].pieces == 4,
    "and come back in piece order")
check(fromClient[1].text:find("Forever") ~= nil, "with the client's own wording")

local p2 = ns.Score:SetProgress(other)
check(p2.fromClient == true, "SetProgress prefers the client")
check(p2.approximate == false,
    "and drops the Classic warning when the client answered")

S.TOOLTIP_LINES_FOR = nil
S.EQUIPPED_IDS = {}
S.EQUIPPED_IDS = {}

-- A piece you are already wearing is not an upgrade on itself. It can
-- still be the best thing in the data for its slot, which is exactly
-- how it came to be suggested back to you.
do
    S.EQUIPPED_IDS = {}
    ns.UI:Select("upgrades")
    ns.UI:FillUpgrades()
    local first, firstSlot
    for _, r in ipairs(ns.UI.panes.upgrades.rows or {}) do
        if r:IsShown() and r.itemID and not first then
            first = r.itemID
            firstSlot = (ns.Score:Info(r.itemID) or {}).slot
        end
    end
    check(first ~= nil, "Upgrades suggests something to start with")

    -- Put that very piece on. It should stop being a suggestion.
    S.EQUIPPED_IDS = { [firstSlot] = first }
    ns.UI:FillUpgrades()
    local stillThere, slotRow = false, nil
    for _, r in ipairs(ns.UI.panes.upgrades.rows or {}) do
        if r:IsShown() and r.itemID then
            if r.itemID == first then stillThere = true end
            if (ns.Score:Info(r.itemID) or {}).slot == firstSlot then slotRow = r.itemID end
        end
    end
    check(not stillThere, "wearing it takes it out of Upgrades")
    -- And the slot falls to the next best rather than going quiet: the
    -- point is what to chase, not what you already have.
    check(slotRow == nil or slotRow ~= first,
        "the slot offers something else, or nothing: " .. tostring(slotRow))

    -- A ring worn in the second ring slot is still a ring you own.
    S.EQUIPPED_IDS = { [12] = first }
    ns.UI:FillUpgrades()
    local viaOtherSlot = false
    for _, r in ipairs(ns.UI.panes.upgrades.rows or {}) do
        if r:IsShown() and r.itemID == first then viaOtherSlot = true end
    end
    check(not viaOtherSlot, "and it is asked of the character, not of one slot")
    S.EQUIPPED_IDS = {}
end

-- Every score in Upgrades carries a sign, and none of them is "-0".
-- "%+.0f" prints that for anything between minus a half and zero, which
-- reads as a downgrade that is not one.
ns.UI:Select("upgrades")
ns.UI:FillUpgrades()
local signed, bare, negZero = 0, 0, 0
for _, r in ipairs(ns.UI.panes.upgrades.rows or {}) do
    if r:IsShown() then
        local t = tostring(r.right:GetText() or "")
        if t ~= "" then
            if t == "-0" then negZero = negZero + 1
            elseif t:match("^[%+%-]%d") then signed = signed + 1
            else bare = bare + 1 end
        end
    end
end
check(negZero == 0, "no score reads as minus zero, got " .. negZero)
check(bare == 0, "every score carries a sign, unsigned ones: " .. bare)
check(signed > 0, "and there are scores to check, got " .. signed)
ns.UI:Select("browse")

-- Rows are pooled, so a group header has to undo every mark the dimming
-- leaves, not most of them. One that had been an unusable item kept its
-- grey on the name and the level range, and that dungeon looked
-- disabled for no reason.
ns.UI:SetSource("dungeons")
ns.UI.panes.browse.open["The Deadmines"] = true
ns.UI:FillBrowse()
local dimmedOne
for _, r in ipairs(ns.UI.panes.browse.rows) do
    if r:IsShown() and r.dimmed then dimmedOne = r break end
end
check(dimmedOne ~= nil, "the list has a dimmed item to reuse")
ns.UI.panes.browse.open["The Deadmines"] = false
ns.UI:FillBrowse()
local allHeadersLit = true
for _, r in ipairs(ns.UI.panes.browse.rows) do
    if r:IsShown() and r.dimmed then allHeadersLit = false end
end
check(allHeadersLit, "every header is lit again once the items are gone")

-- A two-hander takes the off hand with it. Without that the compare
-- counted a two-hander and a shield at once, which is not something you
-- can wear, so every number it produced was too high.
-- A rogue cannot hold a two-hander at all, and the addon is right to
-- refuse one, so this rule needs a character who can.
local wasClass = CLASS
CLASS = "WARRIOR"
S.ITEMS[91001] = { name = "Big Axe", equipLoc = "INVTYPE_2HWEAPON", classID = 2, subClassID = 1 }
S.ITEMS[91002] = { name = "A Shield", equipLoc = "INVTYPE_SHIELD", classID = 4, subClassID = 6 }
ns.Doll:ClearAll()
ns.Doll:TryOn(91001)
check(ns.Doll.trying[16] ~= nil and ns.Doll.trying[16].id == 91001, "the two-hander goes in the weapon slot")
check(ns.Doll.trying[17] ~= nil and ns.Doll.trying[17].empty == true,
    "and the off hand is emptied rather than left counted")

-- The emptied hand used to read `trying.link or <what you wear>`, so it
-- showed the real off hand, and hovering it sent a nil id to
-- IsItemDataCachedByID.
S.EQUIPPED = S.EQUIPPED or {}
local hadOff = S.EQUIPPED[17]
S.EQUIPPED[17] = "|cff1eff00|Hitem:2129::::::::1:::::::|h[Large Round Shield]|h|r"
ns.Doll:Refresh()
check(ns.Doll.slots[17].icon:GetTexture() == nil, "the emptied off hand draws empty, not the shield you wear")
local okHover, errHover = pcall(ns.Doll.slots[17].__scripts.OnEnter, ns.Doll.slots[17])
check(okHover, "hovering the emptied off hand " .. tostring(errHover or ""))
local okNil = pcall(function() ns.Score:FillTooltip(GameTooltip, nil, S.EQUIPPED[17]) end)
check(okNil, "the describer survives being handed no id")
S.EQUIPPED[17] = hadOff

-- An emptied slot gives nothing back, it only takes away.
local d = ns.Doll:Deltas()
check(type(d) == "table", "deltas still compute with an emptied slot")

-- And the other way round: an off hand takes a two-hander off.
ns.Doll:ClearAll()
ns.Doll:TryOn(91001)
ns.Doll:TryOn(91002)
check(ns.Doll.trying[17] ~= nil and ns.Doll.trying[17].id == 91002, "the off hand goes on")
check(ns.Doll.trying[16] ~= nil and ns.Doll.trying[16].empty == true,
    "and the two-hander comes off")

-- Taking a two-hander off gives the off hand back. Putting it on is
-- what emptied that slot, so leaving the slot bare afterwards would
-- have the compare counting a hand you are not actually missing.
ns.Doll:ClearAll()
ns.Doll:TryOn(91001)
check(ns.Doll.trying[17] ~= nil and ns.Doll.trying[17].empty == true,
    "the two-hander emptied the off hand")
check(ns.Doll:Untry(91001), "and it can be taken off again")
check(ns.Doll.trying[16] == nil, "the weapon slot is clear")
check(ns.Doll.trying[17] == nil, "and the off hand is given back, not left bare")

-- A one-hander leaves the off hand alone.
S.ITEMS[91003] = { name = "A Sword", equipLoc = "INVTYPE_WEAPON", classID = 2, subClassID = 7 }
ns.Doll:ClearAll()
ns.Doll:TryOn(91003)
check(ns.Doll.trying[17] == nil, "a one-hander leaves the off hand where it was")
ns.Doll:ClearAll()
CLASS = wasClass

local miss = S.missingReport()
if #miss > 0 then
    io.write("== missing globals reached during the run ==\n  ", table.concat(miss, " "), "\n")
end
io.write(("\n%s: %d passed, %d failed\n"):format(MODE, passes, failures))
return failures
