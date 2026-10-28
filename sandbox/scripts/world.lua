-- In the forest with a sandbox cat: the normal map and everything in it, with no story. The game builds a
-- cat's quests from its quest line while the level loads; they're cleared before the game starts (when
-- the game state leaves its first phase), and again if anything brings them back. The story's scenes
-- (the prophecy's opening and the apprentice ceremony, the first time a cat plays) are skipped the way
-- the player would, with the game's own hold-to-skip.
--
-- Other mods see it through UE4SS's shared variables (README, "For mod makers"):
--   Sandbox.active   true while a sandbox cat is in the forest (or loading into it)
--   Sandbox.ready    true once it's being played: the game has begun and no story scene is on
--   Sandbox.slot     its save slot (0 to 8), -1 when none
--   Sandbox.clan     its Clan ("ThunderClan"), "" when none
--   Sandbox.session  goes up by one each time a sandbox cat comes into the forest
--   Sandbox.new      true when that cat was made this time
--   Sandbox.version  this mod's version
local WORLD = "L_WorldMap_01_P"
local NARRATIVE = "Gameplay.Narrative."
local SKIP_HOLD = 2.5   -- seconds the skip is held: long enough for the game's hold to fill (seen in game)
local VERSION = "0.5"    -- mod.json's

return function(state, Reg)
    local session = 0

    local function share(name, value)
        pcall(function() ModRef:SetSharedVariable("Sandbox." .. name, value) end)
    end
    share("version", VERSION)

    local function publish()
        share("active", state.active == true)
        share("ready", state.active == true and state.ready == true)
        share("slot", state.active and state.slot or -1)
        share("clan", state.active and state.clan or "")
        share("new", state.active and state.new == true)
        share("session", session)
    end
    publish()

    local function questCount()
        local q = Game.manager("quests")
        return q and #Game.list(Game.get(q, "Quests")) or 0
    end

    local function clearQuests(why)
        local q = Game.manager("quests")
        local n = questCount()
        if n == 0 then return end
        local ok, err = Game.call(q, "ResetQuests", false)
        MOD.log("cleared the story's %d quests (%s)%s", n, why, ok and "" or (": " .. tostring(err)))
    end

    -- Whether the cat that's loading is a sandbox cat: a new one made from Sandbox Mode, or one the list has.
    local function decide()
        local slot = state.slot
        if slot == nil then
            local ok, s = pcall(Game.save.slot)
            slot = ok and s or nil
        end
        state.slot = slot
        if slot == nil then return false end
        if state.mode == "sandbox" and state.slotEmpty then
            state.new = true
            return true
        end
        state.new = false
        local e = Reg.find(slot)
        if e then state.clan = e.clan end
        return e ~= nil
    end

    local function enter()
        session = session + 1
        MOD.log("a sandbox cat (slot %s) is coming into the forest%s", tostring(state.slot), state.new and ", for the first time" or "")
        publish()
    end

    local function leave()
        if not state.active then return end
        state.active, state.ready, state.new, state.clan = false, false, false, nil
        MOD.log("left sandbox mode")
        publish()
    end

    -- The game state's phases: 1 while the level loads, then 2 (the opening), 3 and 4 (playing). The quests
    -- are there by phase 2, and the game hands them out on the way to 4.
    Game.hook("/Script/SwtQuest.SwtQuestGameplayGameState:Server_SetPhase", function(_, phase)
        if Game.levelName() ~= WORLD then return end
        if phase == 1 then
            state.ready = false
            state.active = decide()
            if state.active then enter() end
        elseif state.active then
            clearQuests("phase " .. tostring(phase))
        end
    end)

    Game.on("level", function(new)
        if new ~= WORLD then leave() end
    end)

    -- Once the cat is here: a new one goes on the list, with its Clan and name.
    Game.on("player", function(p)
        if not (p and state.active) then return end
        local cat = Game.cat()
        if not cat then return end
        local look = cat:customization() or {}
        state.clan = cat:clan() or state.clan
        if state.new then
            Reg.add(state.slot, { clan = state.clan, prefix = look.PrefixNameId and Game.str(look.PrefixNameId) or nil })
        end
        clearQuests("arrived")
        publish()
    end)

    -- Anything that brings quests back (a save loading them, a scene) is undone.
    Game.every(1, function()
        if state.active and Game.levelName() == WORLD then clearQuests("they came back") end
    end)

    -- The story's scenes: hold the game's own skip while one plays. Once the game is in its last phase
    -- (playing) with no scene on and the cat there for a second (the opening and the ceremony are two
    -- scenes, one after the other), it's ready for other mods to add to.
    local holding, calmSince
    Game.every(0.25, function()
        if not state.active then return end
        local seq = Game.manager("sequencer")
        local active = Game.get(seq, "ActiveSequences")
        local story
        if active then
            pcall(function()
                active:ForEach(function(k)
                    local tag = Game.tagName(k:get())
                    if tag and tag:sub(1, #NARRATIVE) == NARRATIVE then story = tag end
                end)
            end)
        end
        local calm = story == nil and Game.player() ~= nil and Game.get(Game.gameState(), "CurrentPhase") == 4
        if not calm then calmSince = nil elseif not calmSince then calmSince = os.clock() end
        local ready = calmSince ~= nil and os.clock() - calmSince >= 1
        if ready ~= (state.ready == true) then
            state.ready = ready
            if ready then MOD.log("ready for other mods") end
            publish()
        end
        local popup = Game.find("GuiPopupSkipQuest")
        local shown = Game.valid(popup) and popup:IsVisible()
        if holding then
            if not (story and shown) or os.clock() - holding.at >= SKIP_HOLD then
                if Game.valid(holding.popup) then
                    Game.call(holding.popup, "OnListenCommand", holding.command, 1, Game.controller())
                end
                holding = nil
            end
            return
        end
        if not (story and shown) then return end
        local b = Game.get(popup, "mcGuiHoldButtonSkip")
        local command = Game.valid(b) and Game.get(b, "ButtonCommand")
        if not command then return end
        MOD.log("skipping the story's %s", story)
        Game.call(popup, "OnListenCommand", command, 0, Game.controller())
        holding = { popup = popup, command = command, at = os.clock() }
    end)
end
