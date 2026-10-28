-- Cats and questlines made in Clan Mod Studio (its Characters and Questlines pages), with no code. wcmods
-- puts every enabled mod's npcs.json and quests.json into the game as one piece of JSON text, the shared
-- variable WCMods.story (wcmods/story.py has the format); this part brings them into the forest with a
-- sandbox cat and runs the quests.
--
-- A cat stands where its mod says, or beside your cat the first time it comes into the forest (and stays
-- there for that cat). It wears the game's own label (its name, its title, and the game's quest marks) and
-- takes the game's Talk prompt, so the game's Interact key or button talks to it, and goes on with the talk
-- (Enter too). With a wcmods older than Game.npcs.onInteract, the names are drawn and G (or the d-pad's up)
-- talks instead. A quest
-- starts once the quests it comes after are done, and its steps go in order: talk to a cat, pick things up,
-- go somewhere. The reward is dropped at your cat's paws. How far each sandbox cat has got, and where its
-- cats stand, is kept in sandbox-story.json beside the game's saves: one record per save slot, with when
-- the sandbox cat in it was made (the registry's stamp), so a new cat made in the slot of one that was
-- deleted starts afresh. Each quest's record keeps its shape (its steps' kinds, and what a collect step
-- wants), so a quest changed in Clan Mod Studio starts over instead of going on from a step that moved.
local Draw = require("WCModsDraw")
local View = require("WCModsView")

local VARIABLE = "WCMods.story"
local FORMAT = 1                -- the newest WCMods.story this reads (wcmods/story.py FORMAT)
local KEYS = { "G", "Gamepad_DPad_Up" }
local KEY_LABEL = "G"
local TALK_RANGE, WALK_AWAY, LABEL_RANGE = 300, 600, 2500   -- cm
local PANEL_QUESTS = 3          -- quests shown in the panel at once
local NATIVE_MARKER_FROM = 2000  -- cm: nearer than this, the game's own label marks a cat to talk to
local PATH = Game.save.folder() .. "\\sandbox-story.json"
local WAIT_SAID = 10            -- seconds a cat waits for its level before the log says so
local LEVEL_WORDS = { L_WorldMap_01_P = "the forest" }
local function levelWords(level) return LEVEL_WORDS[level] or tostring(level) end

return function(state, Reg)
    local native = Game.npcs.onInteract ~= nil   -- wcmods' own labels and prompts (npc:label, npc:prompt)
    local nativeHud = Game.hud ~= nil and Game.mapMarker ~= nil   -- the game's objective panel, banners, map markers
    local linesFor   -- what a cat says now (below)
    local mods = {}             -- the mods' cats and quests, as wcmods shares them
    local cats = {}             -- list of { key, def, mod, npc }
    local catByKey = {}
    local quests = {}           -- list of { key, def, mod, p } (p: this cat's progress on it)
    -- This sandbox cat's progress: { made = its registry stamp, quests = { [key] = {step, got, done, shape} },
    -- cats = { [key] = {at, yaw, level} } }
    local P
    local icons = {}            -- item tag -> its icon's texture, for the game's objective panel
    local focus                 -- the quest the game's objective panel shows: the one that moved last
    local places = {}           -- quest key -> the map marker on where its step goes
    local slot, running
    local talking               -- { cat, lines, n, quest } while a cat is talking
    local done = {}             -- { title, at }: quests just finished, said on screen for a while
    local showPanel = true

    -- ------------------------------------------------------------------ reading and remembering
    local function read()
        local ok, text = pcall(function() return ModRef:GetSharedVariable(VARIABLE) end)
        if not ok or type(text) ~= "string" or text == "" then return nil end
        local okJ, data = pcall(Game.json.decode, text)
        if okJ and type(data) == "table" and type(data.mods) == "table" then
            if type(data.format) == "number" and data.format > FORMAT then
                MOD.log("the cats and questlines are in a newer format (%s) than this Sandbox mode reads (%d); update Sandbox mode",
                        tostring(data.format), FORMAT)
                return nil
            end
            return data
        end
        MOD.log("couldn't read the cats and questlines: %s", tostring(data))
        return nil
    end

    local function readAll()
        local f = io.open(PATH, "rb")
        if not f then return {} end
        local text = f:read("a")
        f:close()
        local ok, data = pcall(Game.json.decode, text)
        return (ok and type(data) == "table") and data or {}
    end

    local function remember()
        if slot == nil or not P then return end
        local all = readAll()
        all._help = "How far each sandbox cat (by save slot, with when it was made) has got with the questlines from Clan Mod Studio, and where their cats stand. Written by the Sandbox mode mod."
        all[tostring(slot)] = P
        local f, err = io.open(PATH, "wb")
        if not f then
            MOD.log("couldn't write %s: %s", PATH, tostring(err))
            return
        end
        f:write(Game.json.encode(all))
        f:close()
    end

    local function xyz(at)
        if type(at) ~= "table" then return nil end
        if at.X then return { X = at.X, Y = at.Y, Z = at.Z } end
        if #at == 3 then return { X = at[1], Y = at[2], Z = at[3] } end
        return nil
    end

    local function distance(a, b)
        return math.sqrt((a.X - b.X) ^ 2 + (a.Y - b.Y) ^ 2 + (a.Z - b.Z) ^ 2)
    end

    -- ------------------------------------------------------------------ quests
    local function stepOf(q)
        if q.p.done then return nil end
        return q.def.steps[q.p.step]
    end

    local function started(q)
        for _, a in ipairs(q.def.after or {}) do
            local other = q.mod.byId[a]
            if not (other and other.p.done) then return false end
        end
        return true
    end

    local function active(q) return started(q) and not q.p.done end

    local function itemName(tag) return (tostring(tag):match("([^.]+)$") or tag):gsub("(%l)(%u)", "%1 %2") end

    local function objective(q, s)
        if s.objective then return s.objective end
        if s["do"] == "talk" then
            local c = catByKey[q.mod.id .. "/" .. tostring(s.npc)]
            return "Talk to " .. (c and c.def.name or "them")
        elseif s["do"] == "collect" then return "Find " .. itemName(s.item)
        end
        return "Go to the marked place"
    end

    local function progressText(q, s)
        if s["do"] == "collect" then return string.format("%d/%d", math.min(q.p.got or 0, s.count), s.count) end
        return string.format("Step %d of %d", q.p.step, #q.def.steps)
    end

    local function report(q)
        if not Game.quests.report then return end
        if not started(q) then
            Game.quests.report(q.key, nil)
            return
        end
        local s = stepOf(q)
        -- description: for a wcmods whose report carries it (an older one leaves it out).
        Game.quests.report(q.key, {
            title = q.def.title, by = q.mod.name, status = q.p.done and "done" or "active",
            objective = s and objective(q, s) or "Done", progress = s and progressText(q, s) or "",
            description = q.def.description,
        })
    end

    -- A quest's shape: its steps' kinds, with what a collect step wants ("talk|collect:<tag>:2|talk"). A quest
    -- whose shape changed since a cat's progress on it was saved starts over; new lines or a new title don't.
    local function shapeOf(def)
        local parts = {}
        for _, s in ipairs(def.steps or {}) do
            parts[#parts + 1] = s["do"] == "collect" and ("collect:" .. tostring(s.item) .. ":" .. tostring(s.count or 1))
                or tostring(s["do"])
        end
        return table.concat(parts, "|")
    end

    local function reportAll()
        for _, q in ipairs(quests) do report(q) end
    end

    -- On to the quest's next step; after the last, the reward. Quests waiting for this one may start.
    local function advance(q)
        q.p.step, q.p.got = q.p.step + 1, 0
        focus = q.key
        if nativeHud then
            -- The game's banners: a quest taken up (its first talk done), moved on, or completed.
            local kind = q.p.step > #q.def.steps and "done" or q.p.step == 2 and "begin" or "update"
            local upcoming = q.def.steps[q.p.step]
            Game.hud.banner(kind, { kind = kind == "begin" and "Quest" or nil, title = q.def.title,
                                    text = kind == "begin" and upcoming and objective(q, upcoming) or nil })
        end
        if q.p.step > #q.def.steps then
            q.p.done = true
            for tag, n in pairs(q.def.reward or {}) do
                local ok, why = Game.items.drop(tag, n)
                if not ok then MOD.log("%s: the reward %s wasn't dropped: %s", q.key, tag, tostring(why)) end
            end
            done[#done + 1] = { title = q.def.title, at = os.clock() }
            MOD.log("quest done: %s", q.key)
        end
        remember()
        reportAll()
    end

    -- ------------------------------------------------------------------ cats
    -- Where round your cat each one goes (degrees from where it faces), so they don't stand on each other.
    local SIDES = { -60, 60, -110, 110, -150, 150 }

    local function spawn(c, at, yaw, level)
        if c.npc then c.npc:remove() end
        c.shown, c.marked = nil, nil   -- its label, prompt and marker go on the new one
        -- A cat without a look of its own ("look" and "slots") gets one the game makes up, new each time.
        c.npc = Game.npcs.spawn({ at = at, yaw = yaw or 0, level = level, size = c.def.size, eyes = c.def.eyes,
                                  colours = c.def.colours or {}, look = c.def.look, slots = c.def.slots })
    end

    -- Where each cat goes: its mod's place, the place it was given for this sandbox cat, or (the first time)
    -- a spot beside your cat with room, each a little further round.
    local function place(c, i)
        if c.def.at then
            -- A spot typed in with no facing: the cat turns to your cat the first time it's there (below), and
            -- keeps that way.
            c.faceOnce = c.def.yaw == nil and not c.faced
            return spawn(c, c.def.at, c.def.yaw, c.def.level)
        end
        local mine = P.cats[c.key]
        if mine and mine.at then
            return spawn(c, mine.at, mine.yaw, mine.level)
        end
        local at, yaw = Game.npcs.spot(220 + 60 * math.floor((i - 1) / #SIDES), SIDES[(i - 1) % #SIDES + 1])
        if not at then return end   -- no room yet: tried again in a second
        local here = { math.floor(at.X), math.floor(at.Y), math.floor(at.Z) }
        P.cats[c.key] = { at = here, yaw = yaw, level = Game.levelName() }
        remember()
        spawn(c, here, yaw, Game.levelName())
    end

    -- A cat brought beside your cat again (the mod menu's page): the same cat moves, as a new one would get
    -- new patterns from the game.
    local function bring(c)
        local i = 1
        for n, other in ipairs(cats) do if other == c then i = n end end
        -- Each its own side and distance: a side that's blocked falls back to another, which may be taken.
        local at, yaw = Game.npcs.spot(200 + 90 * (i - 1), SIDES[(i - 1) % #SIDES + 1])
        if not at then return end
        local here = { math.floor(at.X), math.floor(at.Y), math.floor(at.Z) }
        P.cats[c.key] = { at = here, yaw = yaw, level = Game.levelName() }
        remember()
        if c.npc and c.npc.level == Game.levelName() then
            c.npc:moveTo(here)
            c.npc:face()
        else
            spawn(c, here, yaw, Game.levelName())
        end
    end

    local function waitingFor(c)
        -- The quest whose step now is talking to this cat, if there is one.
        for _, q in ipairs(quests) do
            local s = active(q) and stepOf(q)
            if s and s["do"] == "talk" and q.mod.id .. "/" .. s.npc == c.key then return q end
        end
        return nil
    end

    local function giverOf(c)
        for _, q in ipairs(quests) do
            if active(q) and q.def.giver and q.mod.id .. "/" .. q.def.giver == c.key then return q end
        end
        return nil
    end

    -- ------------------------------------------------------------------ starting and stopping
    -- When the sandbox cat in a slot was made, from the list of sandbox cats (registry.lua), or nil.
    local function madeOf(s)
        for _, e in ipairs(Reg and Reg.all() or {}) do
            if e.slot == s then return e.made end
        end
        return nil
    end

    -- This cat's own record: a cat made this time, or one made after the record was written (a deleted cat's
    -- slot used again), starts afresh. A record with no stamp (Sandbox mode 0.4 wrote those) is this cat's,
    -- unless the cat was made just now, and takes the stamp from here on.
    local function progressFor(s, new)
        local saved = readAll()[tostring(s)]
        if type(saved) ~= "table" then saved = nil end
        local made = madeOf(s)
        local other = saved and ((saved.made and made and saved.made ~= made) or (new and saved.made ~= made))
        if other then
            MOD.log("slot %s holds a new sandbox cat: its questlines start from the beginning", tostring(s))
            saved = nil
        end
        local p = saved or {}
        p.made = made or p.made
        p.quests = type(p.quests) == "table" and p.quests or {}
        p.cats = type(p.cats) == "table" and p.cats or {}
        return p, saved == nil
    end

    local function start(info)
        local data = read()
        if not data then
            MOD.log("no cats or questlines from Clan Mod Studio (the WCModsStory mod isn't installed, or Sandbox mode is too old for it)")
            return
        end
        slot = info.slot
        local fresh
        P, fresh = progressFor(slot, info.new)
        local restarted = {}
        cats, catByKey, quests, mods = {}, {}, {}, {}
        for _, m in ipairs(data.mods) do
            local mod = { id = m.id, name = m.name or m.id, byId = {} }
            mods[#mods + 1] = mod
            icons = data.icons or icons
            for _, def in ipairs(m.npcs or {}) do
                local c = { key = m.id .. "/" .. def.id, def = def, mod = mod }
                cats[#cats + 1] = c
                catByKey[c.key] = c
            end
            for _, def in ipairs(m.quests or {}) do
                local key, shape = m.id .. "/" .. def.id, shapeOf(def)
                local p = P.quests[key]
                if p and p.shape and p.shape ~= shape then
                    -- Its steps changed in Clan Mod Studio since this cat got as far as it did: from the start,
                    -- done or not.
                    MOD.log("%s changed in Clan Mod Studio, so it starts again", key)
                    restarted[#restarted + 1] = def.title
                    p = nil
                end
                p = p or { step = 1, got = 0 }
                p.shape = shape   -- one saved before shapes were kept takes today's and goes on
                P.quests[key] = p
                local q = { key = key, def = def, mod = mod, p = p }
                if q.p.step > #def.steps then q.p.done = true end
                quests[#quests + 1] = q
                mod.byId[def.id] = q
            end
        end
        running = true
        remember()   -- the stamp and the shapes, at once
        reportAll()
        if nativeHud then
            for _, title in ipairs(restarted) do
                Game.hud.banner("update", { title = title, text = title .. " changed in Clan Mod Studio, so it starts again" })
            end
        end
        MOD.log("%d cats and %d quests from Clan Mod Studio, for the sandbox cat in slot %s%s", #cats, #quests, tostring(slot),
                fresh and " (from the beginning)" or "")
    end

    local function stop()
        for _, c in ipairs(cats) do
            if c.npc then c.npc:remove() end
            c.npc = nil
        end
        if Game.quests.report then
            for _, q in ipairs(quests) do Game.quests.report(q.key, nil) end
        end
        if talking then Game.dialogue.hide() end
        if nativeHud then
            Game.hud.objective(nil)
            for _, m in pairs(places) do m:remove() end
            places = {}
        end
        talking, running, P, slot, focus = nil, false, nil, nil, nil
        cats, catByKey, quests, done = {}, {}, {}, {}
    end

    -- Started each time a sandbox cat is in the forest and being played (the story's scenes are over).
    local seen
    Game.every(0.5, function()
        local on = state.active and state.ready and Game.player() ~= nil
        if on and not running and seen ~= state.slot then
            seen = state.slot
            local ok, err = pcall(start, { slot = state.slot, new = state.new == true })
            if not ok then MOD.log("the cats and questlines didn't start: %s", tostring(err)) end
        elseif not state.active and (running or seen ~= nil) then
            seen = nil
            stop()
        end
        if not running then return end
        -- Cats not in the world yet (the first second, or no room beside you) are put there.
        for i, c in ipairs(cats) do
            if not c.npc then place(c, i) end
        end
        for _, c in ipairs(cats) do
            local there = c.npc and c.npc:valid()
            -- A cat at a spot with no facing turns to your cat once, the first time it's there.
            if there and c.faceOnce then
                c.npc:face()
                c.faceOnce, c.faced = false, true
            end
            -- A cat that waits a while for another level says so, once, in the log (the Mods card shows it).
            if there then
                c.waitingSince = nil
            else
                c.waitingSince = c.waitingSince or os.clock()
                if not c.waitSaid and os.clock() - c.waitingSince > WAIT_SAID then
                    c.waitSaid = true
                    local level = c.npc and c.npc.level
                    if level and level ~= Game.levelName() then
                        MOD.log("%s waits for %s; you're in %s", c.def.name, levelWords(level), levelWords(Game.levelName()))
                    elseif not c.npc then
                        MOD.log("%s has no room beside your cat yet", c.def.name)
                    end
                end
            end
        end
        if native then
            for _, c in ipairs(cats) do
                if c.npc then
                    local q, g = waitingFor(c), giverOf(c)
                    -- The game's marks: a quest to take up, to hand in (its last step), or going on.
                    local icon = q and (q.p.step == 1 and "available" or q.p.step == #q.def.steps and "done" or "ongoing")
                        or g and "ongoing" or nil
                    local extra = (q or g) and (q or g).def.title or nil
                    local talks = linesFor(c) ~= nil
                    local now = tostring(icon) .. "|" .. tostring(extra) .. "|" .. tostring(talks)
                    if c.shown ~= now then
                        c.npc:label({ name = c.def.name, title = c.def.title, extra = extra, icon = icon })
                        c.npc:prompt(talks and "Talk" or nil, TALK_RANGE)
                        c.shown = now
                    end
                end
            end
        end
        if nativeHud then
            -- The game's objective panel: the quest that moved last, or the first one going on.
            local q = focus and (function() for _, x in ipairs(quests) do if x.key == focus and active(x) then return x end end end)()
            if not q then for _, x in ipairs(quests) do if active(x) then q = x break end end end
            local s = q and stepOf(q)
            if s then
                local goals
                if s["do"] == "collect" then
                    goals = { { name = itemName(s.item), progress = progressText(q, s), icon = icons[s.item] } }
                end
                Game.hud.objective({ title = q.def.title, location = q.mod.name, activity = objective(q, s), goals = goals })
            else
                Game.hud.objective(nil)
            end
            -- Map markers: on each cat a quest wants you to talk to, and on each place a quest wants you to go
            -- (the game marks its medicine cat already).
            local want = {}
            for _, x in ipairs(quests) do
                local st = active(x) and stepOf(x)
                if st and st["do"] == "talk" then want[x.mod.id .. "/" .. st.npc] = true end
                local key = st and st["do"] == "visit" and st.at and (x.key .. "#" .. x.p.step) or nil
                if key and not places[key] then places[key] = Game.mapMarker(st.at, { icon = "search" }) or false end
            end
            for key, m in pairs(places) do
                local qkey, step = key:match("^(.*)#(%d+)$")
                local x
                for _, y in ipairs(quests) do if y.key == qkey then x = y end end
                if not (x and active(x) and x.p.step == tonumber(step)) then
                    if m then m:remove() end
                    places[key] = nil
                end
            end
            for _, c in ipairs(cats) do
                if c.npc and (c.marked == true) ~= (want[c.key] == true) then
                    c.npc:mapMarker(want[c.key] and "talk" or nil)
                    c.marked = want[c.key] == true
                end
            end
        end
        -- Walking away ends a talk.
        if talking and not (talking.cat.npc and talking.cat.npc:near(WALK_AWAY)) then
            talking = nil
            Game.dialogue.hide()
        end
    end)

    -- ------------------------------------------------------------------ the steps
    Game.on("itemPickedUp", function(tag, count)
        if not running then return end
        tag = tostring(tag)
        local hits = {}
        for _, q in ipairs(quests) do
            local s = active(q) and stepOf(q)
            if s and s["do"] == "collect" and s.item == tag then hits[#hits + 1] = { q, s } end
        end
        for _, h in ipairs(hits) do
            local q, s = h[1], h[2]
            q.p.got = (q.p.got or 0) + (tonumber(count) or 1)
            if q.p.got >= s.count then advance(q) else remember() report(q) end
        end
    end)

    -- Going somewhere: a place, or the nearest actor of a class (the medicine cat), looked up again every
    -- few seconds as the game loads and unloads them.
    local found = {}
    local function visitTarget(s)
        if s.at then return xyz(s.at) end
        if not s.class then return nil end
        local me = Game.cat()
        local here = me and me:location()
        local f = found[s.class]
        if here and not (f and Game.valid(f.actor) and os.clock() - f.at < 5) then
            local best, bestAway
            for _, a in ipairs(Game.findAll(s.class)) do
                local ok, l = pcall(function() return a:K2_GetActorLocation() end)
                local away = ok and l and distance(here, { X = l.X, Y = l.Y, Z = l.Z })
                if away and (not bestAway or away < bestAway) then best, bestAway = a, away end
            end
            f = best and { actor = best, at = os.clock() } or nil
            found[s.class] = f
        end
        if not (f and Game.valid(f.actor)) then return nil end
        local ok, l = pcall(function() return f.actor:K2_GetActorLocation() end)
        return ok and l and { X = l.X, Y = l.Y, Z = l.Z } or nil
    end

    Game.every(0.5, function()
        if not running then return end
        local me = Game.cat()
        local here = me and me:location()
        if not here then return end
        local arrived = {}
        for _, q in ipairs(quests) do
            local s = active(q) and stepOf(q)
            if s and s["do"] == "visit" and (not s.level or s.level == Game.levelName()) then
                local to = visitTarget(s)
                if to and distance(here, to) <= (s.radius or 400) then arrived[#arrived + 1] = q end
            end
        end
        for _, q in ipairs(arrived) do advance(q) end
    end)

    -- ------------------------------------------------------------------ talking
    local function nearest()
        local best, bestAway
        for _, c in ipairs(cats) do
            local away = c.npc and c.npc:valid() and c.npc:distance()
            if away and away <= TALK_RANGE and (not bestAway or away < bestAway) then best, bestAway = c, away end
        end
        return best
    end

    local function nextLine()
        talking.n = talking.n + 1
        if talking.n <= #talking.lines then return end
        local q, step = talking.quest, talking.step
        talking = nil
        Game.dialogue.hide()
        if q and not q.p.done and q.p.step == step then advance(q) end
    end

    -- What a cat says now: a quest's talk, its own lines, or a reminder of the quest it gave.
    linesFor = function(c)
        local q = waitingFor(c)
        if q then return stepOf(q).lines, q end
        if c.def.lines and #c.def.lines > 0 then return c.def.lines end
        local g = giverOf(c)
        local s = g and stepOf(g)
        return s and { "Don't forget: " .. objective(g, s) .. "." } or nil
    end

    local function startTalk(c)
        if not c or Game.dialogue.busy() or not Game.dialogue.claim() then return end
        local lines, q = linesFor(c)
        if not lines or #lines == 0 then return end
        talking = { cat = c, lines = lines, n = 1, quest = q, step = q and q.p.step }
        c.npc:face()
    end

    if native then
        -- The game's Interact at a cat's prompt starts a talk; while one is on, it goes on.
        Game.npcs.onInteract(function(npc)
            if not running then return end
            if npc == nil then
                if talking then nextLine() end
                return
            end
            for _, c in ipairs(cats) do
                if c.npc == npc then return startTalk(c) end
            end
        end)
    else
        Game.onPress(KEYS, function()
            if not running or #Game.screens() > 0 then return end
            if talking then return nextLine() end
            startTalk(nearest())
        end, "Talk to a cat from Clan Mod Studio")
    end

    -- Enter too, while talking: it's the key the game's dialogue box shows.
    Game.onPress("Enter", function()
        if talking and #Game.screens() == 0 then nextLine() end
    end)

    -- ------------------------------------------------------------------ on screen
    Draw.onFrame(function(d)
        if not running or not d.view or not Game.player() then return end
        if #Game.screens() > 0 then
            if talking then Game.dialogue.hide() end
            return
        end
        if talking then Game.dialogue.say(talking.cat.def.name, talking.lines[talking.n]) end

        -- Names over the cats' heads, a ! over one a quest wants you to talk to, and the talk prompt (the
        -- game's own, with a wcmods that has them).
        local close = not talking and nearest()
        for _, c in ipairs(native and {} or cats) do
            local away = c.npc and c.npc:valid() and c.npc:distance()
            if away and away <= LABEL_RANGE then
                local head = c.npc:location()
                local x, y = View.worldToScreen({ X = head.X, Y = head.Y, Z = head.Z + 30 * (c.def.size or 1) }, d.view)
                if x then
                    if c.def.title then d.text(x, y - 18, c.def.title, { size = 14, color = "#a8e6a1", align = "center", valign = "bottom" }) end
                    d.text(x, y, c.def.name, { size = 20, color = "#ffffff", align = "center", valign = "bottom" })
                    if waitingFor(c) and not (talking and talking.cat == c) then
                        d.text(x, y - (c.def.title and 40 or 22), "!", { size = 30, color = "#ffd166", align = "center", valign = "bottom" })
                    end
                    if close == c and not Game.dialogue.busy() then
                        d.text(x, y + 28, KEY_LABEL .. "   Talk", { size = 16, color = "#ffe9a8", align = "center" })
                    end
                end
            end
        end

        if not showPanel or nativeHud then return end
        -- The quests going on, at the top right, with a marker on where each wants you to go.
        local shown = {}
        for _, q in ipairs(quests) do
            if #shown < PANEL_QUESTS and active(q) then shown[#shown + 1] = q end
        end
        for i = #done, 1, -1 do
            if os.clock() - done[i].at > 8 then table.remove(done, i) end
        end
        local rows = #shown + #done
        if rows == 0 then return end
        local pw = 400
        local px = d.width - pw - 20
        local py = d.panel(px, 150, pw, 30 + rows * 46, "Quests")
        for _, q in ipairs(shown) do
            local s = stepOf(q)
            d.text(px + 14, py, q.def.title, { size = 15, color = "#ffffff" })
            d.text(px + 14, py + 20, objective(q, s) .. (s["do"] == "collect" and ("  " .. progressText(q, s)) or ""),
                { size = 13, color = "#ffe9a8" })
            py = py + 46
            local to
            if s["do"] == "talk" then
                local c = catByKey[q.mod.id .. "/" .. s.npc]
                to = c and c.npc and c.npc:valid() and c.npc:location()
                -- Close by, the game's label marks the cat already; the marker is for finding it.
                if to and native and (c.npc:distance() or 0) < NATIVE_MARKER_FROM then to = nil end
            elseif s["do"] == "visit" then
                to = visitTarget(s)
            end
            if to and not talking then
                d.marker({ X = to.X, Y = to.Y, Z = to.Z + 60 }, objective(q, s), { edge = true, color = "#ffd166" })
            end
        end
        for _, f in ipairs(done) do
            d.text(px + 14, py, f.title, { size = 15, color = "#ffffff" })
            d.text(px + 14, py + 20, "Quest complete!", { size = 13, color = "#9ef0a0" })
            py = py + 46
        end
    end)

    -- ------------------------------------------------------------------ the mod menu
    -- Where a cat is, in words, for the page below.
    local function catStatus(c)
        if c.npc and c.npc:valid() then return "In the world" end
        local level = c.npc and c.npc.level
        if level and level ~= Game.levelName() then return "Waiting for " .. levelWords(level) end
        if not c.npc then return "No room beside you yet" end
        return "On its way"
    end

    -- Every questline back to its first step for this sandbox cat; where its cats stand is kept.
    local function startAllOver()
        local keep = {}
        for _, q in ipairs(quests) do
            q.p.step, q.p.got, q.p.done = 1, 0, nil
            keep[q.key] = q.p
        end
        P.quests, focus, done = keep, nil, {}
        MOD.log("every questline starts over for the sandbox cat in slot %s", tostring(slot))
        remember()
        reportAll()
    end

    MOD.page(function(ui)
        ui.heading("Questlines")
        if not running then
            ui.text("They start when a sandbox cat is in the forest. Make them on Clan Mod Studio's Characters and Questlines pages.")
            return
        end
        if #quests == 0 then ui.text("No questlines yet: Clan Mod Studio's Questlines page makes them.") end
        for _, q in ipairs(quests) do
            local s = stepOf(q)
            ui.field(q.def.title, q.p.done and "Done" or not started(q) and "Not started yet" or (objective(q, s) .. " (" .. progressText(q, s) .. ")"))
            if q.def.description then ui.note(q.def.description) end
            if (q.p.done or q.p.step > 1) and ui.button("Start " .. q.def.title .. " over") then
                q.p.step, q.p.got, q.p.done = 1, 0, nil
                remember()
                reportAll()
            end
        end
        if #quests > 1 and ui.button("Start every questline over") then startAllOver() end
        -- The drawn panel is for a wcmods without the game's own objective panel.
        if not nativeHud then
            local show = ui.switch("Show the quest panel", showPanel)
            if show ~= showPanel then showPanel = show end
        end
        ui.space(8)
        ui.heading("Cats")
        for _, c in ipairs(cats) do
            ui.field(c.def.name, catStatus(c))
            if not c.def.at and ui.button("Bring " .. c.def.name .. " here") then bring(c) end
        end
    end, { title = "Questlines", group = "story" })
end
