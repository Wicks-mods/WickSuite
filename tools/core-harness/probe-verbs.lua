-- The other verbs still run after the raw/lowered split.
local PROBE_DIR, STUB = ...
local S = assert(loadfile(STUB))("modern")
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) S.CHAT[#S.CHAT + 1] = tostring(m) end }
S.loadAddon(PROBE_DIR, "WicksProbe", { "Surface.lua", "Persist.lua", "UI.lua", "Core.lua" })
S.fire("ADDON_LOADED", "WicksProbe")
local fails = 0
for _, v in ipairs({ "help", "show", "", "full", "threat watch", "threat report", "threat stop" }) do
    S.CHAT = {}
    local ok, err = pcall(function() SlashCmdList["WICKSPROBE"](v) end)
    io.write("/wp ", v == "" and "(sweep)" or v, ": ", ok and "ran" or ("THREW " .. tostring(err)), "\n")
    if not ok then fails = fails + 1 end
end
if fails > 0 then error(fails .. " verb(s) threw", 0) end
io.write("PASS\n")
