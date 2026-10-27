-- Sandbox mode: a Sandbox Mode on the game's main menu. A cat made from it plays the normal forest with
-- no story and no quests, a clean slate for other mods to fill. frontend.lua is the main menu's button and
-- the cat choice; world.lua is the forest with a sandbox cat, and what other mods see of it;
-- registry.lua is the list of sandbox cats.
if not Game then
    MOD.log("WCModsGame didn't load, so there's no sandbox mode")
    return
end

local Reg = require("registry")

-- What the two halves share:
--   mode       "sandbox" after Sandbox Mode was pressed, "prophecy" after Prophecy Mode, nil before
--   slot       the save slot the cat choice is on (0 to 8), and slotEmpty, whether it was empty
--   active     a sandbox cat is in the forest (or loading into it); new, it was made this time; clan
local state = {}

for _, part in ipairs({ "frontend", "world" }) do
    local ok, err = pcall(function() require(part)(state, Reg) end)
    if not ok then MOD.log("the %s part didn't start: %s", part, tostring(err)) end
end
