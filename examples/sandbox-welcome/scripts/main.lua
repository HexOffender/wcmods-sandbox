-- Sandbox welcome (wcmods-sandbox/examples/sandbox-welcome): an example of filling Sandbox mode with a mod's
-- own cat and quest. When a sandbox cat comes into the forest, Mossfoot turns up beside it with a small
-- quest: bring three dandelions. G (or the d-pad's up) talks to them; not T, which opens the game's map
-- in keyboard mode. Their quest is listed on the mod menu's Quests page (with the Menu pages mod), and
-- how far each sandbox cat has got is kept in sandbox-welcome.json beside the game's saves.
--
-- What it uses: sandbox_api.lua (copied from wcmods-sandbox's api/) to know when a sandbox cat is in the
-- forest, and WCModsGame for the rest: Game.npcs for the cat, Game.dialogue for the talk, Game.quests.report
-- for the quest list, the itemPickedUp event, and Game.items.drop for the reward.
local Sandbox = require("sandbox_api")

local NAME = "Mossfoot"
local QUEST = "sandbox-welcome"
local ITEM, NEED = "Gameplay.Inventory.Materials.Dandelion", 3
local REWARD, REWARD_COUNT = "Gameplay.Inventory.Consumable.SmallHealingHerb", 2
local TALK_RANGE = 350   -- cm
local SAVE = Game.save.folder() .. "\\sandbox-welcome.json"

-- What each step's talk says. "offer": they haven't asked yet; "gather": you're looking; "back": you have
-- them; "done": it's over.
local LINES = {
    offer = { "A new face! There's no prophecy waiting for you here, and nobody giving orders.",
              "If you'd like something to do, bring me three dandelions. My old joints could use them." },
    gather = { "Three dandelions, young one. You've found %d so far." },
    back = { "Three dandelions! Thank you.", "Here, take these herbs. You've earned them." },
    done = { "The forest is yours. Go wherever your paws take you." },
}

local npc, step, got, talking, slot

-- Each sandbox cat's progress, by save slot: { ["4"] = { step = "gather", got = 1 } }.
local function readAll()
    local f = io.open(SAVE, "rb")
    if not f then return {} end
    local text = f:read("a")
    f:close()
    local ok, data = pcall(Game.json.decode, text)
    return (ok and type(data) == "table") and data or {}
end
local function remember()
    if slot == nil then return end
    local all = readAll()
    all[tostring(slot)] = { step = step, got = got }
    local f = io.open(SAVE, "wb")
    if f then
        f:write(Game.json.encode(all))
        f:close()
    end
end

local function report()
    if step == "offer" then
        Game.quests.report(QUEST, nil)
    else
        Game.quests.report(QUEST, {
            title = "Dandelions for " .. NAME,
            status = step == "done" and "done" or "active",
            objective = step == "done" and ("Brought " .. NAME .. " the dandelions")
                or step == "back" and ("Take the dandelions to " .. NAME) or ("Find " .. NEED .. " dandelions"),
            progress = math.min(got, NEED) .. "/" .. NEED,
            by = "Sandbox welcome",
        })
    end
end

Sandbox.onEnter(function(info)
    slot = info.slot
    local mine = readAll()[tostring(slot)] or {}
    step, got = mine.step or "offer", mine.got or 0
    local at, yaw = Game.npcs.spot(250)
    if at then
        npc = Game.npcs.spawn({ at = at, yaw = yaw, size = 0.8, eyes = 6,
                                colours = { fur = "#7a6a58", pattern = "#4a3f33", markings = "#d8cfc0" } })
    end
    report()
    MOD.log("%s is here for the sandbox cat in slot %s (%s)", NAME, tostring(slot), step)
end)

Sandbox.onLeave(function()
    if npc then npc:remove() end
    npc, talking, slot = nil, nil, nil
    Game.quests.report(QUEST, nil)
    Game.dialogue.hide()
end)

Game.on("itemPickedUp", function(tag, count)
    if step ~= "gather" or tostring(tag) ~= ITEM then return end
    got = got + (tonumber(count) or 1)
    if got >= NEED then step = "back" end
    remember()
    report()
end)

-- The talk: each press shows the next line, and the last one moves the quest on.
local function finish()
    talking = nil
    Game.dialogue.hide()
    if step == "offer" then
        step = "gather"
    elseif step == "back" then
        Game.items.drop(REWARD, REWARD_COUNT)
        step = "done"
    end
    remember()
    report()
end

Game.onPress({ "G", "Gamepad_DPad_Up" }, function()
    if not (npc and Sandbox.active()) or #Game.screens() > 0 then return end
    if not talking then
        if not npc:near(TALK_RANGE) or Game.dialogue.busy() then return end
        talking = 0
        npc:face()
    end
    talking = talking + 1
    local lines = LINES[step]
    if talking > #lines then return finish() end
    Game.dialogue.say(NAME, string.format(lines[talking], got))
end, "Talk to " .. NAME)

-- Walking away ends the talk.
Game.every(0.5, function()
    if talking and not (npc and npc:near(TALK_RANGE * 2)) then
        talking = nil
        Game.dialogue.hide()
    end
end)
