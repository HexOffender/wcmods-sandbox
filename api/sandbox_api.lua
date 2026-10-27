-- sandbox_api.lua: what a script mod needs to fill Sandbox mode (github.com/HexOffender/wcmods-sandbox).
-- Copy this file into your mod's scripts/ folder, then:
--
--   local Sandbox = require("sandbox_api")
--   Sandbox.onEnter(function(info) ... end)   -- a sandbox cat is in the forest: put your cats and quests in
--   Sandbox.onLeave(function() ... end)       -- it's gone (the main menu, or the game is closing)
--
-- Each UE4SS mod has a Lua state of its own, so this reads what the Sandbox mode mod shares through UE4SS's
-- shared variables (Sandbox.active, .ready, .slot, .clan, .new, .session, .version) rather than calling it.
-- Without the Sandbox mode mod, Sandbox.installed() is false and nothing here ever fires.
local Sandbox = {}

local function get(name)
    local ok, v = pcall(function() return ModRef:GetSharedVariable("Sandbox." .. name) end)
    if ok then return v end
    return nil
end

-- Whether the Sandbox mode mod is running, and its version ("0.2").
function Sandbox.installed() return get("version") ~= nil end
function Sandbox.version() return get("version") end

-- Whether a sandbox cat is in the forest (or loading into it). False in menus and with a story cat.
function Sandbox.active() return get("active") == true end

-- Whether it's being played: the game has begun, with no story scene on (the first time a cat comes into
-- the forest, its opening scenes play first, and Sandbox mode skips them).
function Sandbox.ready()
    local r = get("ready")
    if r == nil then return Sandbox.active() end
    return r == true
end

-- The sandbox cat's save slot (0 to 8) and Clan ("ThunderClan", "RiverClan", "WindClan", "ShadowClan"),
-- or nil when there's none.
function Sandbox.slot()
    local s = get("slot")
    if type(s) == "number" and s >= 0 then return math.floor(s) end
    return nil
end
function Sandbox.clan()
    local c = get("clan")
    if type(c) == "string" and c ~= "" then return c end
    return nil
end

-- Whether this cat was made this time (its first time in the forest), for things to do only once per cat.
function Sandbox.isNew() return Sandbox.active() and get("new") == true end

-- A number that goes up by one each time a sandbox cat comes into the forest.
function Sandbox.session()
    local n = get("session")
    if type(n) == "number" then return math.floor(n) end
    return 0
end

-- fn({slot, clan, new, session}) once each time a sandbox cat is in the forest and ready (above), with the
-- player's cat there to stand beside; fn() for onLeave when it goes. Checked twice a second, on the game
-- thread.
local enterFns, leaveFns, seen = {}, {}, nil
local watching = false
local function watch()
    if watching then return end
    watching = true
    Game.every(0.5, function()
        local on = Sandbox.ready() and Game.player() ~= nil
        local session = Sandbox.session()
        if on and seen ~= session then
            seen = session
            local info = { slot = Sandbox.slot(), clan = Sandbox.clan(), new = Sandbox.isNew(), session = session }
            for _, fn in ipairs(enterFns) do
                local ok, err = pcall(fn, info)
                if not ok then print("[sandbox_api] onEnter: " .. tostring(err) .. "\n") end
            end
        elseif not Sandbox.active() and seen ~= nil then
            seen = nil
            for _, fn in ipairs(leaveFns) do
                local ok, err = pcall(fn)
                if not ok then print("[sandbox_api] onLeave: " .. tostring(err) .. "\n") end
            end
        end
    end)
end

function Sandbox.onEnter(fn)
    enterFns[#enterFns + 1] = fn
    watch()
end

function Sandbox.onLeave(fn)
    leaveFns[#leaveFns + 1] = fn
    watch()
end

return Sandbox
