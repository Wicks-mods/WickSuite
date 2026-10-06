-- Wick's Reminders offline harness. Two phases, each a fresh Lua state, so
-- what persists between sessions is what the saved variable carries:
--   phase 1: a first session. Slash forms, the clock, every trigger, the
--            window and editor, theme repaint. Leaves reminders behind.
--   phase 2: the next login, two hours later. What came due while away
--            goes off once, marked as missed; what did not keeps counting.
-- args: coreDir, addonsDir, mode, stubPath, phase, svFile
local CORE_DIR, ADDONS_DIR, MODE, STUB, PHASE, SV_FILE = ...
local S = assert(loadfile(STUB))(MODE)

local passes, fails = 0, 0
local function check(cond, label)
    if cond then passes = passes + 1; io.write("  ok    ", label, "\n")
    else fails = fails + 1; io.write("  FAIL  ", label, "\n") end
end
local function plain(s) return (tostring(s):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local mark = 0
local function chatSince() local t = {} for i = mark + 1, #S.CHAT do t[#t + 1] = plain(S.CHAT[i]) end return table.concat(t, " | ") end
local function clearChat() mark = #S.CHAT end

-- ---------- a clock the harness owns ----------
local START = os.time({ year = 2026, month = 10, day = 6, hour = 12, min = 0, sec = 0 })
NOW = START
time = function(t) if t then return os.time(t) end return NOW end
GetTime = function() return 1000 + (NOW - START) end
local timers, ticker = {}, nil
C_Timer = {
    After = function(d, fn) timers[#timers + 1] = { at = NOW + (d or 0), fn = fn } end,
    NewTicker = function(_, fn) ticker = fn; return { Cancel = function() end } end,
}
local function flush()
    local again = true
    while again do
        again = false
        for i, t in ipairs(timers) do
            if t.at <= NOW then table.remove(timers, i); t.fn(); again = true; break end
        end
    end
end
local function advance(secs) NOW = NOW + secs; flush(); if ticker then ticker() end end

-- ---------- the world ----------
ZONE, SUB, RESTING, LEVEL = "Hellfire Peninsula", "", false, 70
GetRealZoneText = function() return ZONE end
GetZoneText = function() return ZONE end
GetSubZoneText = function() return SUB end
GetMinimapZoneText = function() return SUB ~= "" and SUB or ZONE end
IsResting = function() return RESTING end
UnitLevel = function() return LEVEL end
GetMaxPlayerLevel = function() return 70 end
UnitName = function() return "Tester" end
GetRealmName = function() return "Dreamscythe" end
REALM_SHIFT = 0
GetGameTime = function() local t = os.date("*t", NOW + REALM_SHIFT) return t.hour, t.min end
GetQuestResetTime = function() return 3600 end
C_DateAndTime = C_DateAndTime or {}
C_DateAndTime.GetSecondsUntilWeeklyReset = function() return 3 * 86400 end
GetCVar = function(k) if k == "timeMgrUseMilitaryTime" then return "1" end end
C_CVar = { GetCVar = GetCVar }
local sounds, notices, flashes = {}, {}, 0
PlaySound = function(id, ch) sounds[#sounds + 1] = { id = id, ch = ch } end
RaidWarningFrame = CreateFrame("Frame", "RaidWarningFrame")
RaidNotice_AddMessage = function(_, msg) notices[#notices + 1] = msg end
ChatTypeInfo = { RAID_WARNING = { r = 1, g = 0.3, b = 0.1 } }
FlashClientIcon = function() flashes = flashes + 1 end
IsShiftKeyDown = function() return false end
InCombatLockdown = function() return false end
GameTooltip = GameTooltip or CreateFrame("GameTooltip", "GameTooltip")

-- ---------- saved variables between the phases ----------
local function ser(v, ind)
    ind = ind or ""
    local t = type(v)
    if t == "string" then return string.format("%q", v) end
    if t ~= "table" then return tostring(v) end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local out = { "{\n" }
    for _, k in ipairs(keys) do
        local key = type(k) == "string" and string.format("[%q]", k) or ("[" .. tostring(k) .. "]")
        out[#out + 1] = ind .. "  " .. key .. " = " .. ser(v[k], ind .. "  ") .. ",\n"
    end
    out[#out + 1] = ind .. "}"
    return table.concat(out)
end

if PHASE == "2" then
    local chunk = assert(loadfile(SV_FILE))
    local saved = chunk()
    WicksRemindersDB = saved.db
    START = saved.now
    NOW = saved.now + 2 * 3600   -- two hours logged out
else
    WicksRemindersDB = nil
end

-- ---------- load ----------
io.write("== phase ", PHASE, " (", MODE, ") ==\n")
S.loadAddon(CORE_DIR, "WickCore")
S.fire("ADDON_LOADED", "WickCore")
local Core, Chrome = WickCore, WickCore.Chrome
local ok, err = pcall(S.loadAddon, ADDONS_DIR .. "/WicksReminders", "WicksReminders")
check(ok, "WicksReminders loads: " .. tostring(err or ""))
if not ok then error(err, 0) end
S.fire("ADDON_LOADED", "WicksReminders")
Core.debug = true   -- handler errors reach chat, where they are checked
S.fire("PLAYER_LOGIN")
S.fire("PLAYER_ENTERING_WORLD", true, false)
local ns = WicksReminders
local A = Core.addons.WicksReminders
local db = ns.DB()

local function cards() return ns.Alert.cards end
local function cardFor(id) for _, c in ipairs(ns.Alert.cards) do if c.rid == id then return c end end end
local function find(text)
    for _, r in ipairs(db.reminders) do if r.text == text then return r end end
end
local function slash(msg) SlashCmdList.WICK_WICKSREMINDERS(msg) end
local function noErrors(label)
    local c = chatSince()
    check(not c:find("handler:", 1, true) and not c:find("error:", 1, true), label .. " (no errors in chat)")
end

if PHASE == "1" then
    io.write("== login ==\n")
    check(A and A.title == "Wick's Reminders" and A.version == "0.1.0", "a WickCore addon, Wick's Reminders 0.1.0")
    check(A.enabled and A.db ~= nil, "enabled at login, with its saved variable")
    check(Core.Options.pages.WicksReminders ~= nil, "a page under Wick's Mods")
    check(Core.Launcher.entries.WicksReminders ~= nil, "a line in the launcher")
    local names = {}
    for i = 1, 4 do names[#names + 1] = tostring(_G["SLASH_WICK_WICKSREMINDERS" .. i]) end
    check(table.concat(names, " ") == "/remind /wrem /reminder /reminders", "answers to " .. table.concat(names, " "))
    check(not ns.ready, "nothing goes off during the loading screen")
    advance(3)
    check(ns.ready, "ready a few seconds after entering the world")
    check(type(ticker) == "function", "a one second ticker runs")
    noErrors("login")

    io.write("== parsing ==\n")
    check(ns.ParseDuration("1h30m") == 5400 and ns.ParseDuration("90s") == 90 and ns.ParseDuration("45") == 2700
        and ns.ParseDuration("1:30") == 5400 and ns.ParseDuration("2 hours") == 7200, "durations: 1h30m 90s 45 1:30 '2 hours'")
    check(ns.ParseDuration("soon") == nil and ns.ParseDuration("") == nil, "nonsense is not a duration")
    local h, m = ns.ParseClock("8:30pm"); check(h == 20 and m == 30, "8:30pm is 20:30")
    h, m = ns.ParseClock("12am"); check(h == 0 and m == 0, "12am is midnight")
    h, m = ns.ParseClock("12pm"); check(h == 12 and m == 0, "12pm is noon")
    check(ns.ParseClock("24:00") == nil and ns.ParseClock("7:5") == nil and ns.ParseClock("13pm") == nil, "24:00, 7:5 and 13pm are refused")
    check(ns.FormatLeft(59) == "59s" and ns.FormatLeft(754) == "12m 34s" and ns.FormatLeft(3 * 3600 + 300) == "3h 05m", "countdowns read naturally")
    check(ns.FormatSpan(5400) == "1h 30m" and ns.FormatSpan(600) == "10m", "lengths read naturally")

    io.write("== a timer ==\n")
    clearChat()
    slash("10m Check the AH")
    local t1 = find("Check the AH")
    check(t1 and t1.kind == "timer" and t1.due == NOW + 600, "/remind 10m makes a ten minute timer")
    check(chatSince():find("Timer set: Check the AH, in 10m 00s", 1, true), "and says so: " .. chatSince())
    advance(599)
    check(#cards() == 0 and not t1.done, "not a second early")
    local s0, n0, f0 = #sounds, #notices, flashes
    clearChat()
    advance(1)
    check(#cards() == 1 and cardFor(t1.id) and plain(cardFor(t1.id).msg:GetText()) == "Check the AH", "goes off on time with a card")
    check(#sounds == s0 + 1 and sounds[#sounds].id == 8959 and sounds[#sounds].ch == "Master", "raid warning sound on the master channel")
    local banner = ns.Alert.banner
    check(banner and banner:IsShown() and plain(banner.text:GetText()) == "Check the AH", "the words in large letters")
    check(#notices == n0, "and never through the game's raid warning frame")
    check(flashes == f0 + 1, "the taskbar flashes")
    check(chatSince():find("Wick's Reminders: Check the AH", 1, true), "a chat line")
    check(t1.done and not t1.enabled == false, "a one-off timer is done once it goes off")

    io.write("== snooze and done ==\n")
    local card = cardFor(t1.id)
    card.snooze:Click()
    check(t1.snoozeUntil == NOW + 600 and #cards() == 0, "Snooze puts it back for ten minutes and closes the card")
    check(ns.Describe(t1):find("^Snoozed"), "the list says snoozed: " .. ns.Describe(t1))
    advance(601)
    card = cardFor(t1.id)
    check(card and plain(card.note:GetText()) == "Snoozed, now back", "back after the snooze")
    check(t1.done and t1.snoozeUntil == nil, "and done again")
    card.done:Click()
    check(#cards() == 0, "Done puts the card away")

    io.write("== a repeating timer ==\n")
    slash("every 30m Stretch")
    local rep = find("Stretch")
    local firstDue = rep and rep.due
    check(rep and rep.repeats and rep.duration == 1800 and firstDue == NOW + 1800, "/remind every 30m repeats")
    advance(1800)
    check(cardFor(rep.id) and rep.due == firstDue + 1800 and not rep.done, "goes off and lines up the next one on the same beat")
    cardFor(rep.id).done:Click()

    io.write("== alarms ==\n")
    local function at(day, hh, mm) return os.time({ year = 2026, month = 10, day = day, hour = hh, min = mm, sec = 0 }) end
    local base = NOW
    local today = os.date("*t", NOW)
    slash("20:30 Raid invites")
    local a1 = find("Raid invites")
    check(a1 and a1.kind == "alarm" and a1.hour == 20 and a1.min == 30, "/remind 20:30 makes an alarm")
    check(a1 and a1.due == os.time({ year = today.year, month = today.month, day = today.day, hour = 20, min = 30, sec = 0 }), "set for 20:30 today")
    slash("8 pm Pet the cat")
    local a2 = find("Pet the cat")
    check(a2 and a2.hour == 20 and a2.min == 0, "/remind 8 pm reads the pm")
    slash("9:15 Morning one")
    local a3 = find("Morning one")
    local nextMorning = os.time({ year = today.year, month = today.month, day = today.day + 1, hour = 9, min = 15, sec = 0 })
    check(a3 and a3.due == nextMorning, "a time already gone today is tomorrow")
    slash("daily 21:00 Daily one")
    local a4 = find("Daily one")
    check(a4 and ns.DaysText(a4.days) == "every day", "/remind daily repeats every day")
    -- Monday and Wednesday at 09:00, found by walking forward day by day.
    local mw = ns:Add({ kind = "alarm", hour = 9, min = 0, days = { [2] = true, [4] = true }, text = "Mon Wed", enabled = true })
    local expect
    for d = 0, 8 do
        local c = os.time({ year = today.year, month = today.month, day = today.day + d, hour = 9, min = 0, sec = 0 })
        local w = os.date("*t", c).wday
        if c > NOW and (w == 2 or w == 4) then expect = c break end
    end
    check(mw.due == expect, "a Monday and Wednesday alarm finds the next of those: " .. os.date("%a %H:%M", mw.due))
    check(ns.DaysText(mw.days) == "Mo We", "and reads as Mo We")

    -- The realm an hour ahead: 20:30 on the realm is 19:30 here.
    REALM_SHIFT = 3600
    db.realmClock = true
    ns:RearmAlarms()
    check(a1.due == os.time({ year = today.year, month = today.month, day = today.day, hour = 19, min = 30, sec = 0 }), "on realm time, 20:30 realm is 19:30 local")
    db.realmClock = false
    ns:RearmAlarms()
    REALM_SHIFT = 0
    check(a1.due == os.time({ year = today.year, month = today.month, day = today.day, hour = 20, min = 30, sec = 0 }), "and back again")

    -- Run the clock to 21:00: three alarms go off together; the daily one moves to tomorrow.
    clearChat()
    advance(a4.due - NOW)
    check(cardFor(a1.id) and cardFor(a2.id) and cardFor(a4.id), "20:00, 20:30 and 21:00 all went off")
    check(a1.done and a2.done, "the one-off alarms are done")
    check(a4.due == a4.due and not a4.done and os.date("*t", a4.due).hour == 21 and a4.due > NOW and a4.due - NOW <= 86400, "the daily one is set for tomorrow")
    check(cardFor(a4.id).ringUntil ~= nil, "an alarm card keeps ringing")
    local before = #sounds
    advance(4)
    check(#sounds > before, "and rings again a few seconds later")
    for _, c in ipairs({ unpack(cards()) }) do c.done:Click() end
    before = #sounds
    advance(5)
    check(#sounds == before, "answered, it stops")
    noErrors("alarms")

    io.write("== events ==\n")
    local mail = ns:Add({ kind = "event", trigger = "mail", text = "Send the mats", enabled = true })
    local bank = ns:Add({ kind = "event", trigger = "bank", text = "Deposit", repeats = true, enabled = true })
    S.fire("MAIL_SHOW")
    check(cardFor(mail.id) and mail.done, "opening a mailbox: once, then done")
    S.fire("BANKFRAME_OPENED")
    local firstFired = bank.lastFired
    cardFor(bank.id).done:Click()
    advance(10)
    S.fire("BANKFRAME_OPENED")
    check(cardFor(bank.id) and not bank.done and bank.lastFired > firstFired, "the bank one, every time")
    local zone = ns:Add({ kind = "event", trigger = "zone", arg = "Shattrath City", text = "Train", repeats = true, enabled = true })
    S.fire("ZONE_CHANGED_NEW_AREA")
    check(not cardFor(zone.id), "not in Shattrath yet")
    ZONE = "Shattrath City"
    S.fire("ZONE_CHANGED_NEW_AREA")
    check(cardFor(zone.id) ~= nil, "entering Shattrath City")
    cardFor(zone.id).done:Click()
    SUB = "Terrace of Light"
    S.fire("ZONE_CHANGED")
    check(not cardFor(zone.id), "walking about inside it does not go off again")
    ZONE, SUB = "Terokkar Forest", ""
    S.fire("ZONE_CHANGED_NEW_AREA")
    ZONE = "Shattrath City"
    S.fire("ZONE_CHANGED_NEW_AREA")
    check(cardFor(zone.id) ~= nil, "leaving and coming back does")
    local lvl = ns:Add({ kind = "event", trigger = "level", arg = 70, text = "Talents", enabled = true })
    S.fire("PLAYER_LEVEL_UP", 69)
    check(not cardFor(lvl.id), "level 69 is not 70")
    S.fire("PLAYER_LEVEL_UP", 70)
    check(cardFor(lvl.id) ~= nil, "level 70 is")
    -- A full stack queues the fifth: its sound and chat line go out, its card waits.
    local fight = ns:Add({ kind = "event", trigger = "combat", text = "Repair", enabled = true })
    local nq = #ns.Alert.queue
    S.fire("PLAYER_REGEN_ENABLED")
    check(#cards() == 4 and #ns.Alert.queue == nq + 1 and fight.done, "after the next fight, queued behind a full stack")
    cards()[1].done:Click()
    check(cardFor(fight.id) ~= nil and #ns.Alert.queue == nq, "and shown when a card is answered")
    for _ = 1, 10 do local c = cards()[1]; if c then c.done:Click() end end
    local inn = ns:Add({ kind = "event", trigger = "rested", text = "Log out here", enabled = true })
    RESTING = true
    S.fire("PLAYER_UPDATE_RESTING")
    check(cardFor(inn.id) ~= nil, "reaching an inn")
    local daily = ns:Add({ kind = "event", trigger = "daily", text = "Dailies", repeats = true, enabled = true })
    check(daily.due == NOW + 3600, "the daily reset is an hour off, as the client says")
    local weekly = ns:Add({ kind = "event", trigger = "weekly", text = "Kara", enabled = true })
    check(weekly.due == NOW + 3 * 86400, "the raid reset in three days")
    local other = ns:Add({ kind = "timer", duration = 60, text = "Not mine", scope = "char", owner = "Someone - Elsewhere", enabled = true })
    for _, c in ipairs({ unpack(cards()) }) do c.done:Click() end
    advance(3600)
    check(cardFor(daily.id) and not daily.done and daily.due > NOW, "the daily one goes off and waits for the next reset")
    check(not cardFor(other.id) and not other.done, "a reminder made for another character stays quiet here")
    local stacked, queued = ns.Alert:Count()
    check(stacked <= 4, "never more than four cards on screen (" .. stacked .. " shown, " .. queued .. " waiting)")
    for _ = 1, 10 do local c = cards()[1]; if c then c.done:Click() end end
    noErrors("events")

    io.write("== the window ==\n")
    local okT, errT = pcall(ns.UI.Toggle, ns.UI)
    check(okT and WicksRemindersFrame and WicksRemindersFrame:IsShown(), "the window opens: " .. tostring(errT or ""))
    local shown = {}
    for _, row in ipairs(ns.UI.list.rows) do if row:IsShown() and row.rem then shown[#shown + 1] = row.rem end end
    check(#shown == 8, "eight rows on screen")
    check(not shown[1].done and shown[1].due, "soonest first: " .. tostring(shown[1].text))
    local bottomDone = true
    local all = ns:Sorted()
    for i = 1, #all - 1 do if all[i].done and not all[i + 1].done and not all[i + 1].snoozeUntil then bottomDone = false end end
    check(bottomDone, "finished ones at the bottom")
    check(plain(ns.UI.list.more:GetText()):find("Scroll for the rest", 1, true), "says there is more")
    check(ns.UI.list.rows[1]:GetWidth() == ns.UI.ContentWidth(WicksRemindersFrame) and ns.UI.ContentWidth({ wickGame = true }) == 446,
        "rows fill the content and no more: " .. ns.UI.list.rows[1]:GetWidth() .. " here, 446 inside the Classic frame")
    local _, _, cp = ns.UI.list.clock:GetPoint()
    check(cp == "BOTTOM" and plain(ns.UI.list.clock:GetText()):find("%d:%d%d"), "the clock is in the footer: " .. plain(ns.UI.list.clock:GetText()))
    ns.UI:Scroll(3)
    check(ns.UI.offset == 3, "the wheel scrolls")
    ns.UI:Scroll(-10)
    local row = ns.UI.list.rows[1]
    local victim = row.rem
    local okA = pcall(ns.UI.Tick, ns.UI, NOW)
    check(okA and plain(row.when:GetText()) == ns.Describe(victim), "rows count down: " .. plain(row.when:GetText()))
    row.toggle:Click()
    check(victim.enabled == false and victim.due == nil, "the tick switches it off")
    local function rowOf(r) for _, r2 in ipairs(ns.UI.list.rows) do if r2.rem == r and r2:IsShown() then return r2 end end end
    row = rowOf(victim)
    row.toggle:Click()
    check(victim.enabled and not victim.done, "and on again")
    -- Switching it on re-sorts the list, so find its row again.
    row = rowOf(victim)
    row.del:Click()
    check(ns:Get(victim.id) ~= nil and plain(row.when:GetText()):find("again to delete", 1, true), "one click on the cross asks again")
    row.del:Click()
    check(ns:Get(victim.id) == nil, "the second deletes it")

    io.write("== the editor ==\n")
    ns.UI:OpenEditor(nil, "alarm")
    local e = ns.UI.editor
    check(e:IsShown() and not ns.UI.list:IsShown(), "New alarm opens the editor")
    e.text:SetValue("Raid night")
    ns.UI.draft.hour, ns.UI.draft.min = 19, 0
    e.panes.alarm.days[1]:Click()   -- Mo
    e.panes.alarm.days[4]:Click()   -- Th
    check(ns.UI.draft.days[2] and ns.UI.draft.days[5], "day chips pick Monday and Thursday")
    e.panes.alarm.minute.Refresh()
    check(plain(e.panes.alarm.summary:GetText()):find("At 19:00, Mo Th", 1, true), "the summary reads it back: " .. plain(e.panes.alarm.summary:GetText()))
    e.save:Click()
    local raid = find("Raid night")
    check(raid and raid.kind == "alarm" and raid.days[2] and raid.days[5] and raid.hour == 19 and raid.due, "Save makes it")
    check(ns.UI.list:IsShown() and not e:IsShown(), "and goes back to the list")
    local dueBefore = raid.due
    ns.UI:OpenEditor(raid)
    e.text:SetValue("Raid night, Karazhan")
    e.save:Click()
    check(raid.text == "Raid night, Karazhan" and raid.due == dueBefore, "changing the words leaves the schedule alone")
    ns.UI:OpenEditor(nil, "timer")
    e.panes.timer.chips[4]:Click()   -- 30m
    e.text:SetValue("Tea")
    e.save:Click()
    local tea = find("Tea")
    check(tea and tea.duration == 1800 and tea.due == NOW + 1800 and tea.hour == nil and tea.trigger == nil, "a preset timer, tidy")
    ns.UI:OpenEditor(nil, "timer")
    e.panes.timer.custom:SetValue("1h 20m")
    e.panes.timer.custom.edit:GetScript("OnTextChanged")(e.panes.timer.custom.edit, true)
    check(ns.UI.draft.duration == 4800 and plain(e.panes.timer.parsed:GetText()) == "= 1h 20m", "a typed length")
    e.cancel:Click()
    check(ns.UI.list:IsShown(), "Cancel goes back")
    ns.UI:OpenEditor(nil, "event")
    check(ns.UI.draft.level == 70, "a level 70 character's level reminder starts at 70, not 71: " .. tostring(ns.UI.draft.level))
    ns.UI.draft.trigger = "level"; ns.UI:PaintEditor()
    check(plain(e.panes.event.levelNote:GetText()):find("already level 70", 1, true), "and says it is already there")
    e.panes.event.level.Refresh()
    ns.UI.draft.level = 70
    ns.UI.draft.trigger = "zone"
    e.save:Click()
    check(plain(e.err:GetText()):find("Which zone", 1, true) and e:IsShown(), "a zone reminder wants a zone")
    e.panes.event.here:Click()
    e.save:Click()
    local hz = nil
    for _, r in ipairs(db.reminders) do if r.trigger == "zone" and r.arg == "Shattrath City" and r.text == "When I enter Shattrath City" then hz = r end end
    check(hz ~= nil, "Where I am fills it, and a reminder with no words says what it waits for")
    ns.UI:OpenEditor(nil, "timer")
    e.panes.alarm.typed:SetValue("")
    local okTry = pcall(e.try.GetScript(e.try, "OnClick"))
    check(okTry and cardFor(0) ~= nil, "Try it shows the card")
    local np, nrel, nrp = cardFor(0).note:GetPoint()
    check(np == "RIGHT" and nrel == cardFor(0).content and nrp == "RIGHT", "a card's note has the card's whole width, clear of the buttons")
    cardFor(0).done:Click()
    e.cancel:Click()
    ns.UI:OpenEditor(nil, "alarm")
    ns.UI:SetKind("event")
    check(plain(WicksRemindersFrame.title:GetText()):find("new event", 1, true), "the title follows the tab: " .. plain(WicksRemindersFrame.title:GetText()))
    local ep = e.panes.event
    local _, _, _, _, y1 = ep.rep:GetPoint()
    ns.UI.draft.trigger = "zone"; ns.UI:PaintEditor()
    local _, _, _, _, y2 = ep.rep:GetPoint()
    check(y1 == ep.below and y2 == ep.below - 32, "Every time sits under the choices, and moves down for a zone box")
    e.cancel:Click()
    noErrors("window")

    io.write("== the theme repaints it ==\n")
    local function bgOf(frame)
        for _, r in ipairs({ frame:GetRegions() }) do if r.__layer == "BACKGROUND" and r.__color then return r end end
    end
    local bg = bgOf(WicksRemindersFrame)
    if Chrome:Modern() then
        -- The Modern look draws the window as glass, tinted by vertex
        -- colour, which the stub does not keep; the panel art is the tell.
        local glass
        for _, r in ipairs({ WicksRemindersFrame:GetRegions() }) do
            if r.__layer == "BACKGROUND" and r.__tex == Chrome:PanelTex(WicksRemindersFrame) then glass = r end
        end
        check(glass ~= nil, "the window is glass in the " .. Chrome:StyleID() .. " look")
    else
        local was = Chrome.activeTheme or "fel"
        Chrome:ApplyTheme("hologram")
        local v = Chrome.Colors.voidBG
        check(bg and math.abs(bg.__color[1] - v[1]) < 0.002 and math.abs(bg.__color[3] - v[3]) < 0.002, "the window background follows the theme")
        Chrome:ApplyTheme(was)
    end

    io.write("== the options page and the launcher ==\n")
    local page = Core.Options.pages.WicksReminders.frame
    local okP, errP = pcall(page.Show, page)
    flush()
    check(okP, "the options page builds: " .. tostring(errP or ""))
    local tt = { lines = {} }
    function tt:AddLine(s) self.lines[#self.lines + 1] = plain(s) end
    function tt:AddDoubleLine(a, b) self.lines[#self.lines + 1] = plain(a) .. " / " .. plain(b) end
    local okL = pcall(Core.Launcher.entries.WicksReminders.opts.tooltip, tt)
    check(okL and #tt.lines >= 3, "the launcher tooltip lists what is coming: " .. (tt.lines[2] or ""))
    slash("list")
    slash("help")
    slash("nonsense words")
    check(chatSince():find("not sure when you mean", 1, true), "an unreadable /remind says so")

    io.write("== leave some for next time ==\n")
    local cleared = ns:ClearDone()
    check(cleared > 0, "Clear finished sweeps " .. cleared)
    -- What the first build saved for a level 70 character.
    ns:Add({ kind = "event", trigger = "level", arg = 71, text = "Buy skills", repeats = true, enabled = true })
    slash("3h Long one")
    slash("login Check the mail")
    local oneHour = os.date("*t", NOW + 3600)
    slash(("%d:%02d Away alarm"):format(oneHour.hour, oneHour.min))
    local snz = ns:Add({ kind = "timer", duration = 60, text = "Snoozed away", enabled = true })
    advance(60)
    cardFor(snz.id).snooze:Click()
    for _ = 1, 10 do local c = cards()[1]; if c then c.done:Click() end end
    local out = assert(io.open(SV_FILE, "w"))
    out:write("return " .. ser({ db = WicksRemindersDB, now = NOW }) .. "\n")
    out:close()
    check(true, ("saved %d reminders for the next session"):format(#db.reminders))
else
    io.write("== two hours later ==\n")
    local long, mailr, away, snz, daily4 = find("Long one"), find("Check the mail"), find("Away alarm"), find("Snoozed away"), find("Daily one")
    check(long and mailr and away and snz, "the reminders came back with the saved variable")
    local longDue = long.due
    check(find("Buy skills") and find("Buy skills").arg == 70, "a level reminder saved past the cap is brought down to 70 at login")
    check(#cards() == 0, "nothing during the loading screen")
    advance(3)
    check(cardFor(away.id) and away.done, "the alarm that came due while away goes off")
    check(cardFor(away.id) and plain(cardFor(away.id).note:GetText()):find("while you were away", 1, true), "marked as missed: " .. plain(cardFor(away.id) and cardFor(away.id).note:GetText() or ""))
    check(snz.snoozeUntil == nil and (cardFor(snz.id) ~= nil or ns.Alert.queue[1] ~= nil), "the snooze that ran out while away goes off")
    check(mailr.done and (cardFor(mailr.id) ~= nil or #ns.Alert.queue > 0), "the login reminder goes off at login")
    check(long.due == longDue and not long.done and not cardFor(long.id), "the three hour timer is still counting")
    check(math.abs((long.due - NOW) - 3600) <= 3 + 60, "with about an hour left: " .. ns.FormatLeft(long.due - NOW))
    local stacked, queued = ns.Alert:Count()
    check(stacked <= 4, ("four at most on screen, the rest wait (%d shown, %d waiting)"):format(stacked, queued))
    for _ = 1, 12 do local c = cards()[1]; if c then c.done:Click() end end
    check(#cards() == 0 and #ns.Alert.queue == 0, "answering them works through the queue")

    io.write("== missed reminders switched off ==\n")
    db.missed = false
    local quiet = ns:Add({ kind = "timer", duration = 60, text = "Quiet one", enabled = true })
    quiet.due = ns.sessionStart - 100
    advance(1)
    check(quiet.done and not cardFor(quiet.id), "came due while away, moved on without a card")
    db.missed = true
    advance(long.due - NOW)
    check(cardFor(long.id) ~= nil, "the long timer goes off at its time")
    noErrors("phase 2")
end

local missing = S.missingReport()
io.write("\nAPI the stub answered with nil: ", table.concat(missing, ", "), "\n")
io.write(("\nphase %s %s: %d passed, %d failed\n"):format(PHASE, MODE, passes, fails))
if fails > 0 then error(("%d check(s) failed"):format(fails), 0) end
print("PASS")
