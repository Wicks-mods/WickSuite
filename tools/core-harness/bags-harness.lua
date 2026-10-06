-- Offline load test for Wick's Bags on WickCore.
-- Loads the real library and the real product against the stub client and
-- drives the panels: build, refresh, bank open/close, options, alt tooltips.
--   args: coreDir, bagsDir, mode, stubPath

local CORE_DIR, BAGS_DIR, MODE, STUB = ...
local S = assert(loadfile(STUB))(MODE)
local MODERN = S.modern

local passes, fails = 0, 0
local function check(cond, label)
    if cond then passes = passes + 1; io.write("  ok    ", label, "\n")
    else fails = fails + 1; io.write("  FAIL  ", label, "\n") end
end

io.write("== load WickCore + WicksBags (", MODE, ") ==\n")
S.loadAddon(CORE_DIR, "WickCore")   -- file list straight off WickCore.toc
S.fire("ADDON_LOADED", "WickCore")
-- run.py --bags --styles: the whole pass in one WickCore look.
local STYLE = os.getenv("WICK_STYLE")
if STYLE and STYLE ~= "" then WickCore.Chrome:CharStore().style = STYLE end

-- Pre-seed an old-layout saved file to exercise the migration.
WicksBagsDB = { options = { showJunk = false, sortMode = "name" }, bagPos = { posPoint = "CENTER", posRel = "CENTER", posX = 1, posY = 2, panelW = 500 } }
WicksBagsAlts = { ["Classic Beta PvP-Altchar"] = { bags = { { itemID = 6948, count = 2 } }, bank = { { itemID = 6948, count = 5 } }, bagsLastSeen = 1 } }

-- The game's own bag functions and one of its bag windows, there before
-- Wick's Bags loads so its post-hooks take. CloseAllBags counts its calls:
-- Wick's Bags must never make one.
ContainerFrame1 = CreateFrame("Frame", "ContainerFrame1", UIParent)
function OpenAllBags(frame) ContainerFrame1:Show() end
function CloseAllBags(frame) S.CLOSE_ALL_CALLS = (S.CLOSE_ALL_CALLS or 0) + 1; ContainerFrame1:Hide() end
function ToggleAllBags() if ContainerFrame1:IsShown() then ContainerFrame1:Hide() else ContainerFrame1:Show() end end

S.loadAddon(BAGS_DIR, "WicksBags", { "Core.lua", "Categories.lua", "UI.lua", "Options.lua", "Bag.lua", "Bank.lua", "GuildBank.lua", "AltViewer.lua" })
check(type(WicksBags) == "table" and WicksBags.A, "WicksBags namespace + WickCore addon object")

io.write("== lifecycle ==\n")
S.fire("ADDON_LOADED", "WicksBags")
S.fire("PLAYER_LOGIN")
local WB = WicksBags
local A = WB.A
check(A.initialized and A.enabled, "initialized + enabled")
check(WB.db == A.db.profile, "WB.db bound to profile")
check(WB.db.options.showJunk == false and WB.db.options.sortMode == "name", "old top-level options migrated into profile")
check(WB.db.options.showCurrencies == true and WB.db.options.altTooltips == true, "new defaults applied after migration")
check(WB.db.bagPos.panelW == 500, "bagPos migrated")
check(WicksBagsDB.options == nil and WicksBagsDB._migratedToProfile, "top-level keys removed after migration")
check(WB.altDB["Classic Beta PvP-Altchar"] ~= nil, "WicksBagsAlts folded into db.global.alts")
check(type(SlashCmdList.WICK_WICKSBAGS) == "function" and SLASH_WICK_WICKSBAGS1 == "/wbags", "slash registered")
check(WickCore.Launcher.entries.WicksBags ~= nil, "launcher registered")
check(WickCore.Options.pages.WicksBags ~= nil, "options page registered")

io.write("== dialect through ns ==\n")
local ns = WB.eventFrame and select(2, pcall(function() return nil end)) -- placeholder
local name, link, quality, ilvl = WicksBags.A and (function() local Core = WickCore; return Core.Dialect.GetItemInfo(6948).name end)()
check(name == "Hearthstone", "Dialect.GetItemInfo")
check(WB.Categories:GetCategory(6948, "|Hitem:6948|h[Hearthstone]|h") == "Misc", "category resolution via ns.GetItemInfo/Instant: " .. tostring(WB.Categories:GetCategory(6948, "x")))

io.write("== bag panel ==\n")
check(WB.Bag and WB.Bag.panel, "bag panel built on LOGIN")
local okShow, errShow = pcall(function() WB.Bag:Show() end)
check(okShow, "Bag:Show " .. tostring(errShow or ""))
local okRef, errRef = pcall(function() WB.Bag:Refresh() end)
check(okRef, "Bag:Refresh " .. tostring(errRef or ""))
if WickCore.Chrome.Game and WickCore.Chrome:Game() then
    -- Classic: the game's search box, sort button and close button.
    local p = WB.Bag.panel
    check(p._search and p._search.__template == "SearchBoxTemplate", "Classic: the bag searches with the game's search box")
    check(p._sortBtn == nil or p._sortBtn.__template == "UIPanelButtonTemplate", "Classic: Sort is the game's button")
end
check(WB.Bag.panel:IsShown(), "bag panel shown")
if MODERN then
    check((S.BAGS_SCANNED[5] or 0) > 0, "reagent bag scanned alongside the carry bags")
else
    check((S.BAGS_SCANNED[5] or 0) == 0, "no reagent bag on a legacy client")
end
local slotBtn = _G.WicksBagsSlot1
check(slotBtn ~= nil, "slot button 1 built")
check(slotBtn and slotBtn._iconTex ~= nil and slotBtn._countText ~= nil, "slot icon and count regions resolved")
if MODERN then
    check(slotBtn and slotBtn.__kind == "ItemButton", "slot created with the intrinsic ItemButton type")
    check(slotBtn and slotBtn._iconTex == slotBtn.icon, "slot icon is the template's own region")
    local wrong = 0
    for _, f in ipairs(S.ITEM_BUTTONS) do if f.__kind ~= "ItemButton" then wrong = wrong + 1 end end
    check(wrong == 0, "no item buttons created as plain Button: " .. wrong)
end
if MODERN then
    check(WB.Bag.panel._sortBtn ~= nil, "sort button present on modern client")
    WB.Bag.panel._sortBtn.__scripts.OnClick()
    check(S.SORTED == 1, "sort button calls C_Container.SortBags")
else
    check(WB.Bag.panel._sortBtn == nil, "no sort button on legacy client")
end
S.fire("BAG_UPDATE", 0)
check(true, "BAG_UPDATE handled")
WB.Bag:Hide()
check(not WB.Bag.panel:IsShown(), "Bag:Hide")

io.write("== bank ==\n")
check(WB.Bank.IsTabBank == MODERN, "bank model detection (tabs=" .. tostring(WB.Bank.IsTabBank) .. ")")
local ids = WB.Bank.ContainerIDs()
if MODERN then
    check(#ids == 2 and ids[1] == 6 and ids[2] == 7, "bank containers = purchased tabs 6,7")
else
    check(#ids == 8 and ids[1] == -1 and ids[8] == 11, "bank containers = -1 + bags 5..11")
end
BANK_OPEN = true
local okBank, errBank = pcall(function() S.fire("BANKFRAME_OPENED") end)
check(okBank, "BANKFRAME_OPENED " .. tostring(errBank or ""))
check(WB.Bank.panel and WB.Bank.panel:IsShown(), "bank panel shown on open")
local okBR, errBR = pcall(function() WB.Bank:Refresh() end)
check(okBR, "Bank:Refresh " .. tostring(errBR or ""))
check(WB.Bank.panel._buyBtn ~= nil, "buy button exists")
check(WB.Bank.panel._buyBtn:IsShown() ~= false, "buy button shown while tabs/slots remain")
-- The cooldown swirl covers the whole button. It never showed until the
-- duration was fixed, so whether it took mouse input had never mattered;
-- the moment it drew, a right-click on anything on cooldown would have
-- gone into the overlay instead of the item.
local slotWithCd
for _, b in ipairs(S.frames) do
    if b.__name and b.__name:find("WicksBagsSlot") and b._cd then slotWithCd = b break end
end
check(slotWithCd ~= nil, "a bag slot was built")
if slotWithCd then
    check(slotWithCd._cd.__mouseEnabled == false,
        "its cooldown overlay does not take the click meant for the item under it")
end
WB.Bank.panel._buyBtn.__scripts.OnClick()
if MODERN then
    check(S.PURCHASED_TAB == nil, "buy tab never calls the restricted C_Bank.PurchaseBankTab")
    check(BankFrame._wicksRevealed == true and BankFrame.__alpha ~= 0, "buy tab reveals Blizzard's bank window instead")
    BankFrame.__scripts.OnHide(BankFrame)
    check(BankFrame._wicksRevealed == nil, "closing Blizzard's bank clears the reveal")
    WB.Bank:Show()
    check(WB.Bank.panel._sortBtn ~= nil, "bank sort button present")
    WB.Bank.panel._sortBtn.__scripts.OnClick()
    check(S.SORTED_BANK == 1, "bank sort calls C_Container.SortBank")
else
    check(S.LAST_POPUP == "CONFIRM_BUY_BANK_SLOT", "buy slot opens Blizzard confirmation")
end

if MODERN then
    -- A character who has never been granted the free first tab. Blizzard
    -- grants it inside SetTab -> PurchaseFirstSlot -> PurchaseBankTab, and
    -- that call is restricted, so it only works while their frame is
    -- untainted. Touching it at all in this state costs the tab for good.
    S.fire("BANKFRAME_CLOSED")
    -- A fresh frame, because the earlier scenario left a hook on the old
    -- one and a new character would not have it.
    _G.BankFrame = S.newMock("Frame", "BankFrame")
    S.BANK_TABS = 0
    BankFrame:Show()   -- the real one is up while you stand at the banker
    S.NEXT_TAB_ASKED = 0
    S.fire("BANKFRAME_OPENED")
    check(BankFrame._wicksHooked == nil, "with no tabs yet, Blizzard's bank frame is not hooked")
    check(WB.Bank.panel and not WB.Bank.panel:IsShown(), "and our own bank panel stays hidden until the tab lands")
    check(BankFrame:GetAlpha() == 1, "and not hidden")
    check(BankFrame._wicksAnchor == nil, "and not moved")
    check(WB.Bank.GrantPending() == true, "the addon knows the grant is still pending")

    -- The grant lands. Now it is safe, and we take over without making
    -- them close and reopen the bank.
    S.BANK_TABS = 1
    S.fire("BANK_TABS_CHANGED")
    check(BankFrame._wicksHooked == true, "once the tab is granted the frame is taken over")
    check(BankFrame:GetAlpha() == 0, "and put out of the way")
    check(WB.Bank.GrantPending() == false, "and the grant is no longer pending")
    check(WB.Bank.panel:IsShown(), "and our panel opens")
    -- The next tab's cost is what the grant reads; hovering Buy must not ask for it.
    local buy = WB.Bank.panel._buyBtn
    local okBuy, errBuy = pcall(buy.__scripts.OnEnter, buy)
    check(okBuy and S.NEXT_TAB_ASKED == 0, "the next tab's cost is never asked for, not even for the Buy tooltip: " .. tostring(errBuy or ""))
    S.BANK_TABS = nil
end
-- Tab/bag slot tooltip
local botBar = WB.Bank.panel._botBar
local slot1 = botBar and botBar._slots and botBar._slots[1]
check(slot1 ~= nil, "bank slot button 1 exists")
if slot1 then
    local okTT, errTT = pcall(slot1.__scripts.OnEnter, slot1)
    check(okTT, "bank slot tooltip " .. tostring(errTT or ""))
end
S.fire("BANKFRAME_CLOSED")
check(not WB.Bank.panel:IsShown(), "bank panel hidden on close")
BANK_OPEN = false

io.write("== guild bank ==\n")
local GB = WB.GuildBank
-- Forever announces the vault only through the interaction manager, as
-- retail does; TBC sends GUILDBANKFRAME_OPENED. Each mode opens it its
-- client's way.
local function openVault()
    if MODERN then S.fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 10)
    else S.fire("GUILDBANKFRAME_OPENED") end
end
local function closeVault()
    if MODERN then S.fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 10)
    else S.fire("GUILDBANKFRAME_CLOSED") end
end
check(GB ~= nil, "guild bank module loaded")
-- Blizzard numbers a tab in columns of 14 drawn as two stacks of 7.
local cells, uniq = {}, true
for i = 1, 98 do
    local cx, cy = GB.SlotCell(i)
    local key = cx .. "," .. cy
    if cells[key] or cx < 0 or cx > 13 or cy < 0 or cy > 6 then uniq = false end
    cells[key] = true
end
local function cell(i) local x, y = GB.SlotCell(i) return x .. "," .. y end
check(uniq, "98 slots fill a 14 by 7 grid with no overlaps")
check(cell(1) == "0,0" and cell(7) == "0,6" and cell(8) == "1,0" and cell(14) == "1,6"
      and cell(15) == "2,0" and cell(98) == "13,6", "slot order matches Blizzard's frame")

local LINEN = "|cffffffff|Hitem:2589::::::::1:::::::|h[Linen Cloth]|h|r"
local HEARTH = "|cffffffff|Hitem:6948::::::::1:::::::|h[Hearthstone]|h|r"
S.GB.tabs = {
    { name = "Mats", icon = 134400, items = {
        [1] = { tex = 132889, count = 20, quality = 1, link = LINEN },
        [8] = { tex = 134414, count = 1, quality = 1, link = HEARTH } } },
    { name = "Officers", icon = 134401, viewable = false },
    { name = "Gear", icon = 134402, remaining = 2, items = {} },
}
S.GB.current = 2            -- left on a tab this rank cannot view
S.GB.money = 123456
S.GB.canWithdraw = false
-- Worst case for the first visit: Blizzard's frame does not exist yet when
-- our open handler runs, and loads and shows afterwards.
check(rawget(_G, "GuildBankFrame") == nil, "Blizzard's guild bank frame not loaded before the first visit")
S.CHAT = {}
openVault()
ShowGuildBankFrame()
local gp = GB.panel
check(gp and gp:IsShown(), "guild bank panel shown at the vault")
local errs = 0
for _, l in ipairs(S.CHAT) do if l:lower():find("error") then errs = errs + 1; io.write("    ", l, "\n") end end
check(errs == 0, "no errors while opening")
check(S.GB.current == 1, "moved off the unviewable tab to the first viewable one")
local queried1 = false
for _, q in ipairs(S.GB.queries) do if q == 1 then queried1 = true end end
check(queried1, "asked the server for that tab's items")
local s1, s8, s2 = gp._slots[1], gp._slots[8], gp._slots[2]
check(s1._iconTex:GetTexture() == 132889 and s1._countText:GetText() == "20", "slot 1 shows its icon and stack size")
check(s8._iconTex:GetTexture() == 134414 and s8._countText:GetText() == "", "slot 8 shows a single item with no count")
check(s2._iconTex:GetTexture() == nil, "empty slots stay empty")
check(gp._tabs[1]:IsShown() and gp._tabs[3]:IsShown() and not gp._tabs[4]:IsShown(), "one tab button per purchased tab")
check(gp._tabs[2]._icon.__desaturated == true, "the unviewable tab is greyed")
check(gp._tabs[1]._sel:IsShown() and not gp._tabs[3]._sel:IsShown(), "the current tab is marked")
check(gp._gold:GetText() == WB.UI:FormatMoney(123456), "guild gold shown")
check(not gp._withdraw:IsShown(), "withdraw hidden for a rank that cannot take gold")
check(WB.Bag.panel:IsShown(), "the bags open alongside")
check(GuildBankFrame:GetAlpha() == 0, "Blizzard's window is put out of the way even though it loaded late")
local wrote = {}
for k in pairs(GuildBankFrame) do if type(k) == "string" and not k:find("^__") then wrote[#wrote + 1] = k end end
check(#wrote == 0, "nothing written onto Blizzard's frame: " .. table.concat(wrote, ","))
check(GB:State().hooked, "its show and hide are hooked")

S.GB.picked, S.GB.stored = {}, {}
s1.__scripts.OnClick(s1, "LeftButton")
check(S.GB.picked[1] == "1:1", "left-click picks the item up")
s1.__scripts.OnClick(s1, "RightButton")
check(S.GB.stored[1] == "1:1", "right-click sends it to your bags")
s2.__scripts.OnReceiveDrag(s2)
check(S.GB.picked[2] == "1:2", "dropping on a slot puts the carried item there")
local realCursor = GetCursorInfo
GetCursorInfo = function() return "money", 5000 end
s2.__scripts.OnClick(s2, "LeftButton")
GetCursorInfo = realCursor
check(S.GB.deposited == 5000, "clicking with gold on the cursor deposits it")

gp._tabs[3].__scripts.OnClick(gp._tabs[3])
check(S.GB.current == 3 and S.GB.queries[#S.GB.queries] == 3, "clicking a tab selects and loads it")
check(gp._tabLabel:GetText():find("Gear") and gp._tabLabel:GetText():find("2 left"), "tab name and withdrawals left shown: " .. tostring(gp._tabLabel:GetText()))
check(s1._iconTex:GetTexture() == nil, "the grid now shows the new tab")
gp._tabs[2].__scripts.OnClick(gp._tabs[2])
check(S.GB.current == 3, "an unviewable tab cannot be selected")
gp._tabs[1].__scripts.OnClick(gp._tabs[1])

gp._search:SetText("linen")
gp._search.__scripts.OnTextChanged(gp._search)
check(s1:GetAlpha() == 1 and s8:GetAlpha() < 1, "search dims what does not match")
gp._search:SetText("")
gp._search.__scripts.OnTextChanged(gp._search)

S.GB.tabs[1].items[2] = { tex = 133971, count = 5, quality = 2, link = LINEN }
S.fire("GUILDBANKBAGSLOTS_CHANGED")
check(s2._iconTex:GetTexture() == 133971, "a slot change redraws the grid")

gp._blizzBtn.__scripts.OnClick(gp._blizzBtn)
check(GuildBankFrame:GetAlpha() == 1 and not gp:IsShown() and GB:State().revealed, "Log & tabs steps aside for Blizzard's window")
GuildBankFrame.__scripts.OnHide(GuildBankFrame)
check(not GB:State().revealed, "closing Blizzard's window clears that")

GB:Show()
local closeBefore = S.GB.closed or 0
closeVault()
check(not gp:IsShown(), "panel hidden when the session ends")
if MODERN then
    S.fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 5)   -- some other interaction
    check(not gp:IsShown(), "other interactions do not open it")
    local shows = 0
    local realShow = GB.Show
    GB.Show = function(...) shows = shows + 1 return realShow(...) end
    S.fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 10)
    S.fire("GUILDBANKFRAME_OPENED")
    GB.Show = realShow
    check(shows == 1, "both open events together open it once")
    closeVault()
    check(not gp:IsShown(), "and the interaction hide closes it")
end
check((S.GB.closed or 0) == closeBefore, "and does not end it a second time")

WB.db.options.hideDefaultGuildBank = false
openVault()
check(not gp:IsShown(), "with the option off, Blizzard's window is left in charge")
closeVault()
WB.db.options.hideDefaultGuildBank = true
SlashCmdList.WICK_WICKSBAGS("defaultguildbank")
check(WB.db.options.hideDefaultGuildBank == false, "/wbags defaultguildbank toggles it")
SlashCmdList.WICK_WICKSBAGS("defaultguildbank")
check(WB.db.options.hideDefaultGuildBank == true, "and back")

io.write("== alt viewer ==\n")
local okAV, errAV = pcall(function() WB.AltViewer:SnapshotBags() end)
check(okAV, "SnapshotBags " .. tostring(errAV or ""))
local me = WB.altDB["Classic Beta PvP-Wick"]
check(me and #me.bags > 0, "own snapshot stored with items")
local rows = WB.AltViewer.AltCountsFor(6948)
check(#rows == 1 and rows[1].name == "Altchar" and rows[1].bags == 2 and rows[1].bank == 5, "alt counts exclude self and sum bags/bank")
local tt = S.newMock("GameTooltip")
local lines = {}
tt.AddDoubleLine = function(_, l, r) lines[#lines + 1] = l .. "=" .. r end
WB.AltViewer.DecorateTooltip(tt, 6948)
check(#lines == 1 and lines[1]:find("Altchar") and lines[1]:find("2 in bags") and lines[1]:find("5 in bank"), "tooltip decoration: " .. tostring(lines[1]))
if MODERN then check(S.TOOLTIP_HOOK ~= nil, "TooltipDataProcessor hook installed") end
local okAVS, errAVS = pcall(function() WB.AltViewer:Show(); WB.AltViewer:Refresh(); WB.AltViewer:Hide() end)
check(okAVS, "AltViewer show/refresh/hide " .. tostring(errAVS or ""))

io.write("== options window ==\n")
local okOP, errOP = pcall(function() WB.Options:Build(); WB.Options:Toggle() end)
check(okOP, "Options:Build + Toggle " .. tostring(errOP or ""))

io.write("== slash ==\n")
S.CHAT = {}
SlashCmdList.WICK_WICKSBAGS("help")
check(#S.CHAT >= 5, "/wbags help prints")
SlashCmdList.WICK_WICKSBAGS("autoopen off")
check(WB.db.options.autoOpenBags == false, "/wbags autoopen off")
SlashCmdList.WICK_WICKSBAGS("sort")
if MODERN then check(S.SORTED == 2, "/wbags sort") end

io.write("== profile export ==\n")
local exp = A.db:Export()
check(exp:sub(1, 6) == "WICK1:", "profile export string")

io.write("== missing globals reached during the run ==\n")
local missing = S.missingReport()
io.write("  ", table.concat(missing, " "), "\n")

-- ---------- escape ----------------------------------------------------------
-- Escape closes the bags before it opens the game menu. The bank panel is
-- left out on purpose: the default BankFrame stays shown behind ours, so
-- Escape reaches it, ends the bank session, and its OnHide brings ours down.
io.write("== escape ==" .. string.char(10))
local listed = {}
for _, n in ipairs(UISpecialFrames) do listed[n] = true end
check(listed.WicksBagsPanel, "the bag panel is listed for Escape")
check(listed.WicksAltViewerPanel and listed.WicksBagsOptions, "so are the alt viewer and the options window")
check(not listed.WicksBankPanel, "the bank panel is not, so the bank session is not left open")
check(not listed.WicksGuildBankPanel, "nor the guild bank panel, for the same reason")
local dup = 0
for _, n in ipairs(UISpecialFrames) do if n == "WicksBagsPanel" then dup = dup + 1 end end
check(dup == 1, "listed once, however many times the panel is built")
WB.Bag:Show()
check(WB.Bag.panel:IsShown() and CloseSpecialWindows() == true, "Escape with the bags open closes them and stops there")
check(not WB.Bag.panel:IsShown(), "the bags are hidden")
check(CloseSpecialWindows() == false, "Escape with nothing of ours open falls through to the game menu")
io.write("== the game's own bags ==\n")
do
    -- Shutting them with CloseAllBags from here wrote the game's record of
    -- which window opened its bags as Wick's Bags; the bank then chose its
    -- tab tainted, and every bag item clicked after (a hearthstone) was a
    -- blocked action until a reload (taint.log 2026-10-04).
    local before = S.CLOSE_ALL_CALLS or 0
    S.fire("MERCHANT_SHOW")
    S.fire("MAIL_SHOW")
    check((S.CLOSE_ALL_CALLS or 0) == before, "Wick's Bags never shuts the game's bags itself")
    local merchant = CreateFrame("Frame", "MerchantFrame", UIParent)
    OpenAllBags(merchant)
    check(ContainerFrame1:IsShown() and ContainerFrame1:GetParent() ~= UIParent, "bags a window opens for itself are kept out of sight")
    CloseAllBags(merchant)
    check(ContainerFrame1:GetParent() == UIParent, "and given back to their own parent once the game shuts them")
    OpenAllBags(merchant)
    OpenAllBags()
    check(ContainerFrame1:IsShown() and ContainerFrame1:GetParent() == UIParent, "the player's own Open All Bags shows them")
    OpenAllBags(merchant)
    ToggleAllBags()
    check(ContainerFrame1:GetParent() == UIParent, "and so does toggling them")
    S.fire("MERCHANT_CLOSED")
    S.fire("MAIL_CLOSED")
end
io.write("\n", MODE, ": ", passes, " passed, ", fails, " failed\n")
if fails > 0 then error(MODE .. ": " .. fails .. " check(s) failed", 0) end
io.write("PASS\n")
