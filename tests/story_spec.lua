-- Sandbox mode's story part (sandbox/scripts/story.lua) under Lua 5.4, with the game stubbed: WCModsGame
-- (Game), the mod (MOD, ModRef), WCModsDraw and WCModsView. A test makes a world, the story part starts in it
-- as it does in the game (the half-second keeper, once a sandbox cat is in the forest and ready), and is
-- driven through what it registers: the keeper, itemPickedUp, the Talk prompt (onInteract), the drawing
-- and the mod menu's page. Nothing is exported from story.lua for these.
--
--     lua tests/story_spec.lua         (or python tests/run.py)
local here = (arg and arg[0] or ""):match("^(.*)[/\\][^/\\]*$") or "."
local STORY = here .. "/../sandbox/scripts/story.lua"
local MOSS, MINT = "Gameplay.Inventory.Materials.Moss", "Gameplay.Inventory.Consumable.Mint"

local tests = {}
local function test(name, fn) tests[#tests + 1] = { name, fn } end
local function eq(got, want, what)
    if got ~= want then error(string.format("%s: expected %s, got %s", what or "value", tostring(want), tostring(got)), 2) end
end
local function ok(v, what) if not v then error(what or "expected something true", 2) end end

-- ------------------------------------------------------------------ JSON, files
-- Game.json's stand-in: encode keeps a copy and gives its key, decode gives a copy back. story.lua only ever
-- decodes what was encoded (the shared variable, its own file), so the text itself doesn't matter.
local store, made = {}, 0
local function copy(v)
    if type(v) ~= "table" then return v end
    local o = {}
    for k, x in pairs(v) do o[k] = copy(x) end
    return o
end
local json = {
    encode = function(v) made = made + 1; local key = "json#" .. made; store[key] = copy(v); return key end,
    decode = function(text)
        if store[text] == nil then error("not JSON: " .. tostring(text)) end
        return copy(store[text])
    end,
}

-- A folder of the test's own for sandbox-story.json (story.lua names it Game.save.folder() .. "\\...").
local function folder()
    local f = os.tmpname()
    os.remove(f)
    return f
end
local function progressPath(f) return f .. "\\sandbox-story.json" end
local function writeProgress(f, data)
    local h = assert(io.open(progressPath(f), "wb"))
    h:write(json.encode(data))
    h:close()
end
local function readProgress(f)
    local h = io.open(progressPath(f), "rb")
    if not h then return nil end
    local text = h:read("a")
    h:close()
    return json.decode(text)
end

-- ------------------------------------------------------------------ the game
-- The cats and questlines wcmods shares (WCMods.story), as JSON text.
local function story(quests, npcs, format)
    return json.encode({ format = format or 1, icons = {}, mods = { { id = "mine", name = "Mine",
        npcs = npcs or { { id = "mossfoot", name = "Mossfoot", lines = { "Good hunting." } },
                         { id = "sparrowpaw", name = "Sparrowpaw", lines = {} } },
        quests = quests } } })
end
local function mossQuest(over)
    local q = { id = "moss", title = "Moss for Mossfoot", giver = "mossfoot", after = {}, steps = {
        { ["do"] = "talk", npc = "mossfoot", lines = { "Bring me moss?" } },
        { ["do"] = "collect", item = MOSS, count = 2 },
        { ["do"] = "talk", npc = "mossfoot", lines = { "Thank you!" } } },
        reward = { [MINT] = 2 } }
    for k, v in pairs(over or {}) do q[k] = v end
    return q
end
local MOSS_SHAPE = "talk|collect:" .. MOSS .. ":2|talk"

-- A world with the story part started in it. o: shared (the story), folder, slot, new, registry
-- ({ {slot, made} }), level.
local function world(o)
    o = o or {}
    local w = { everys = {}, on = {}, logs = {}, drops = {}, banners = {}, reports = {}, said = {}, spawned = {},
                level = o.level or "L_WorldMap_01_P", me = { X = 0, Y = 0, Z = 0 } }
    local Npc = {}
    Npc.__index = Npc
    function Npc:valid() return not self.removed and (self.level == nil or self.level == w.level) end
    function Npc:remove() self.removed = true end
    function Npc:label(spec) self.labelSpec = spec end
    function Npc:prompt(text) self.promptText = text end
    function Npc:mapMarker(icon) self.marker = icon end
    function Npc:face() self.faced = (self.faced or 0) + 1; return true end
    function Npc:location() return { X = self.at[1] or self.at.X, Y = self.at[2] or self.at.Y, Z = self.at[3] or self.at.Z } end
    function Npc:distance() return 100 end
    function Npc:near() return true end
    function Npc:moveTo(at) self.at = at end
    Game = {
        save = { folder = function() return o.folder end },
        json = json,
        npcs = {
            onInteract = function(fn) w.interact = fn end,
            spawn = function(spec)
                local n = setmetatable({ at = spec.at, yaw = spec.yaw, level = spec.level, spec = spec }, Npc)
                w.spawned[#w.spawned + 1] = n
                return n
            end,
            spot = function(distance, side)
                if w.noRoom then return nil end
                return { X = distance, Y = side, Z = 0 }, 90
            end,
        },
        hud = {
            objective = function(spec) w.objective = spec end,
            banner = function(kind, opts) w.banners[#w.banners + 1] = { kind = kind, title = opts.title, text = opts.text } end,
        },
        mapMarker = function() return { remove = function() end } end,
        quests = { report = function(key, q) w.reports[key] = q end },
        items = { drop = function(tag, n) w.drops[#w.drops + 1] = tag .. " x" .. n; return true end },
        dialogue = {
            busy = function() return false end, claim = function() return true end,
            hide = function() w.hidden = true end, say = function(_, line) w.said[#w.said + 1] = line end,
        },
        every = function(_, fn) w.everys[#w.everys + 1] = fn end,
        on = function(event, fn) w.on[event] = fn end,
        onPress = function() end,
        player = function() return {} end,
        cat = function() return { location = function() return w.me end } end,
        levelName = function() return w.level end,
        screens = function() return {} end,
        findAll = function() return {} end,
        valid = function(x) return x ~= nil end,
    }
    MOD = { log = function(fmt, ...) w.logs[#w.logs + 1] = string.format(fmt, ...) end,
            page = function(fn, opts) w.page, w.pageOpts = fn, opts end }
    ModRef = { GetSharedVariable = function(_, name) if name == "WCMods.story" then return o.shared end end }
    package.loaded.WCModsDraw = { onFrame = function(fn) w.frame = fn end }
    package.loaded.WCModsView = { worldToScreen = function() return nil end }
    local Reg = { all = function() return o.registry or {} end }
    w.state = { active = true, ready = true, slot = o.slot or 3, new = o.new == true }
    dofile(STORY)(w.state, Reg)
    function w.tick(times) for _ = 1, times or 1 do for _, fn in ipairs(w.everys) do fn() end end end
    -- The cat a spawned npc is, by its place in the list of cats (1 = Mossfoot).
    function w.npc(i) return w.spawned[i] end
    -- Walk up and press Interact (the game's Talk prompt), then Interact again for each line.
    function w.talk(i)
        w.interact(w.npc(i))
        w.frame({ view = {}, width = 1920 })   -- the line is said while it's drawn
    end
    function w.next() w.interact(nil) end
    function w.logged(text)
        for _, l in ipairs(w.logs) do if l:find(text, 1, true) then return true end end
        return false
    end
    return w
end

local function ui(press)
    local seen = { fields = {}, notes = {}, buttons = {}, switches = {} }
    return {
        heading = function() end, space = function() end, text = function(t) seen.text = t end,
        note = function(t) seen.notes[#seen.notes + 1] = t end,
        field = function(label, value) seen.fields[label] = value end,
        button = function(label) seen.buttons[#seen.buttons + 1] = label; return label == press end,
        switch = function(label, value) seen.switches[#seen.switches + 1] = label; return value end,
    }, seen
end

-- ------------------------------------------------------------------ progress per cat
test("test_new_cat_starts_clean", function()
    local f = folder()
    writeProgress(f, { ["3"] = { quests = { ["mine/moss"] = { step = 4, got = 0, done = true } },
                                 cats = { ["mine/mossfoot"] = { at = { 1, 2, 3 }, yaw = 0 } } } })
    local w = world({ shared = story({ mossQuest() }), folder = f, new = true, registry = { { slot = 3, made = "B" } } })
    w.tick()
    local p = readProgress(f)["3"]
    eq(p.made, "B", "the new cat's stamp")
    eq(p.quests["mine/moss"].step, 1, "its quest from the start")
    eq(p.quests["mine/moss"].done, nil, "not done")
    eq(p.cats["mine/mossfoot"].at[1], 220, "Mossfoot beside the new cat, not where the old one met them")
    eq(w.reports["mine/moss"].status, "active", "the quest is going on")
    ok(w.logged("holds a new sandbox cat"), "the log says why")
    os.remove(progressPath(f))
end)

test("test_replaced_cat_starts_clean", function()
    local f = folder()
    writeProgress(f, { ["3"] = { made = "A", quests = { ["mine/moss"] = { step = 2, got = 1, shape = MOSS_SHAPE } }, cats = {} },
                       ["5"] = { made = "C", quests = { ["mine/moss"] = { step = 3, got = 0, shape = MOSS_SHAPE } }, cats = {} } })
    local w = world({ shared = story({ mossQuest() }), folder = f, registry = { { slot = 3, made = "B" }, { slot = 5, made = "C" } } })
    w.tick()
    local all = readProgress(f)
    eq(all["3"].made, "B")
    eq(all["3"].quests["mine/moss"].step, 1, "a cat made after the record was written starts afresh")
    eq(all["5"].quests["mine/moss"].step, 3, "another slot's cat is left as it was")
    os.remove(progressPath(f))
end)

test("test_a_04_progress_file_is_kept_and_stamped", function()
    local f = folder()
    writeProgress(f, { ["3"] = { quests = { ["mine/moss"] = { step = 2, got = 1 } }, cats = { ["mine/mossfoot"] = { at = { 1, 2, 3 }, yaw = 45 } } } })
    local w = world({ shared = story({ mossQuest() }), folder = f, registry = { { slot = 3, made = "B" } } })
    w.tick()
    local p = readProgress(f)["3"]
    eq(p.made, "B", "stamped")
    eq(p.quests["mine/moss"].step, 2, "progress kept")
    eq(p.quests["mine/moss"].got, 1, "pickups kept")
    eq(p.quests["mine/moss"].shape, MOSS_SHAPE, "shape written")
    eq(w.npc(1).at[1], 1, "Mossfoot where they were")
    os.remove(progressPath(f))
end)

test("test_changed_quest_starts_over", function()
    local f = folder()
    local other = { id = "herbs", title = "Herbs", giver = "sparrowpaw", after = {}, steps = {
        { ["do"] = "talk", npc = "sparrowpaw", lines = { "Hi" } }, { ["do"] = "talk", npc = "sparrowpaw", lines = { "Bye" } } } }
    writeProgress(f, { ["3"] = { made = "B", cats = {}, quests = {
        ["mine/moss"] = { step = 3, got = 0, shape = "talk|talk" },             -- a Pick up step went in since
        ["mine/herbs"] = { step = 2, got = 0, shape = "talk|talk" } } } })      -- unchanged (new lines don't count)
    local w = world({ shared = story({ mossQuest(), other }), folder = f, registry = { { slot = 3, made = "B" } } })
    w.tick()
    local p = readProgress(f)["3"]
    eq(p.quests["mine/moss"].step, 1, "the changed quest starts over")
    eq(p.quests["mine/moss"].shape, MOSS_SHAPE)
    eq(p.quests["mine/herbs"].step, 2, "the other goes on")
    eq(#w.banners, 1, "one banner")
    eq(w.banners[1].kind, "update")
    eq(w.banners[1].text, "Moss for Mossfoot changed in Clan Mod Studio, so it starts again")
    ok(w.logged("mine/moss changed in Clan Mod Studio, so it starts again"))
    os.remove(progressPath(f))
end)

-- ------------------------------------------------------------------ the steps
test("test_reward_dropped_once", function()
    local f = folder()
    local w = world({ shared = story({ mossQuest() }), folder = f, registry = { { slot = 3, made = "B" } } })
    w.tick()
    w.talk(1); w.next()                       -- step 1, the talk
    eq(w.reports["mine/moss"].progress, "0/2")
    w.on.itemPickedUp(MOSS, 2)                -- step 2, the moss
    w.talk(1); w.next()                       -- step 3, the hand-in
    eq(w.reports["mine/moss"].status, "done")
    eq(#w.drops, 1)
    eq(w.drops[1], MINT .. " x2")
    w.tick(3)
    w.talk(1); w.next()
    eq(#w.drops, 1, "not again")
    -- Back in the forest later: it's remembered as done.
    local again = world({ shared = story({ mossQuest() }), folder = f, registry = { { slot = 3, made = "B" } } })
    again.tick()
    eq(again.reports["mine/moss"].status, "done")
    eq(#again.drops, 0)
    os.remove(progressPath(f))
end)

test("test_two_quests_collect_one_tag", function()
    local f = folder()
    local function collect(id) return { id = id, title = id, after = {}, steps = {
        { ["do"] = "collect", item = MOSS, count = 2 }, { ["do"] = "talk", npc = "mossfoot", lines = { "Thanks" } } } } end
    local w = world({ shared = story({ collect("a"), collect("b") }), folder = f, registry = { { slot = 3, made = "B" } } })
    w.tick()
    w.on.itemPickedUp(MOSS, 1)
    eq(w.reports["mine/a"].progress, "1/2")
    eq(w.reports["mine/b"].progress, "1/2")
    w.on.itemPickedUp(MOSS, 3)
    local p = readProgress(f)["3"].quests
    eq(p["mine/a"].step, 2, "a moved on")
    eq(p["mine/b"].step, 2, "b moved on")
    eq(p["mine/a"].got, 0, "counting starts again for the next step")
    w.on.itemPickedUp("Gameplay.Inventory.Materials.Stick", 5)
    eq(readProgress(f)["3"].quests["mine/a"].step, 2, "another item counts for nothing")
    os.remove(progressPath(f))
end)

test("test_visit_waits_for_its_level", function()
    local f = folder()
    local q = { id = "go", title = "Go", after = {}, steps = { { ["do"] = "visit", at = { 0, 0, 0 }, radius = 400, level = "L_Other" } } }
    local w = world({ shared = story({ q }), folder = f, registry = { { slot = 3, made = "B" } } })
    w.tick(2)
    eq(readProgress(f)["3"].quests["mine/go"].step, 1, "standing on the spot in another level does nothing")
    w.level = "L_Other"
    w.tick()
    eq(w.reports["mine/go"].status, "done", "in its level, it's reached")
    os.remove(progressPath(f))
end)

test("test_quest_lines_first_then_own_then_reminder", function()
    local f = folder()
    local herbs = { id = "herbs", title = "Herbs", giver = "sparrowpaw", after = {}, steps = {
        { ["do"] = "collect", item = MOSS, count = 1 } } }
    local w = world({ shared = story({ mossQuest(), herbs }), folder = f, registry = { { slot = 3, made = "B" } } })
    w.tick()
    w.talk(1)
    eq(w.said[#w.said], "Bring me moss?", "the quest's own lines first")
    w.next()
    w.talk(1)
    eq(w.said[#w.said], "Good hunting.", "then the cat's own")
    w.next()
    w.talk(2)
    eq(w.said[#w.said], "Don't forget: Find Moss.", "a giver with no lines of its own reminds you")
    os.remove(progressPath(f))
end)

test("test_newer_format_is_refused", function()
    local f = folder()
    local w = world({ shared = story({ mossQuest() }, nil, 2), folder = f, registry = { { slot = 3, made = "B" } } })
    w.tick(2)
    eq(#w.spawned, 0, "nothing put in the forest")
    ok(w.logged("newer format"), "the log says to update Sandbox mode")
    eq(readProgress(f), nil, "nothing written")
end)

-- ------------------------------------------------------------------ cats and the mod menu
test("test_a_spot_without_facing_turns_to_your_cat_once", function()
    local f = folder()
    local npcs = { { id = "mossfoot", name = "Mossfoot", at = { 5, 6, 7 } }, { id = "oak", name = "Oak", at = { 1, 1, 1 }, yaw = 30 } }
    local w = world({ shared = story({}, npcs), folder = f, registry = { { slot = 3, made = "B" } } })
    w.tick(3)
    eq(w.npc(1).faced, 1, "once")
    eq(w.npc(2).faced, nil, "a cat with a facing of its own keeps it")
    os.remove(progressPath(f))
end)

test("test_menu_page_is_under_story_says_about_it_and_starts_every_questline_over", function()
    local f = folder()
    local herbs = { id = "herbs", title = "Herbs", description = "Sparrowpaw's herbs.", after = {}, steps = {
        { ["do"] = "talk", npc = "sparrowpaw", lines = { "Hi" } }, { ["do"] = "talk", npc = "sparrowpaw", lines = { "Bye" } } } }
    writeProgress(f, { ["3"] = { made = "B", cats = { ["mine/mossfoot"] = { at = { 9, 9, 9 }, yaw = 0 } }, quests = {
        ["mine/moss"] = { step = 4, got = 0, done = true, shape = MOSS_SHAPE },
        ["mine/herbs"] = { step = 2, got = 0, shape = "talk|talk" },
        ["gone/old"] = { step = 2, got = 0 } } } })
    local w = world({ shared = story({ mossQuest(), herbs }), folder = f, registry = { { slot = 3, made = "B" } } })
    w.tick()
    eq(w.pageOpts.group, "story")
    local u, seen = ui()
    w.page(u)
    eq(seen.notes[1], "Sparrowpaw's herbs.", "About it under its title")
    eq(seen.fields["Moss for Mossfoot"], "Done")
    eq(seen.fields["Mossfoot"], "In the world")
    eq(#seen.switches, 0, "no drawn quest panel to switch with the game's own")
    u = ui("Start every questline over")
    w.page(u)
    local p = readProgress(f)["3"]
    eq(p.quests["mine/moss"].step, 1)
    eq(p.quests["mine/herbs"].step, 1)
    eq(p.quests["gone/old"], nil, "a quest that's gone is forgotten")
    eq(p.cats["mine/mossfoot"].at[1], 9, "where the cats stand is kept")
    os.remove(progressPath(f))
end)

-- ------------------------------------------------------------------ run them
local failed = 0
for _, t in ipairs(tests) do
    local passed, err = xpcall(t[2], debug.traceback)
    print((passed and "ok    " or "FAIL  ") .. t[1])
    if not passed then
        failed = failed + 1
        print(err)
    end
end
print(string.format("%d tests, %d failed", #tests, failed))
os.exit(failed == 0 and 0 or 1)
