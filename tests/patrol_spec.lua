-- Sandbox mode's patrol part (sandbox/scripts/patrol.lua) under Lua 5.4, with the game stubbed the way
-- story_spec.lua does it. The story part runs for real (it owns the cats, the quests and the talk), a clock
-- the test moves stands in for time, npc:walkTo is a stub the test finishes by hand ("arrived", "blocked"...),
-- and Sandbox.raise / Sandbox.patrol.release are the real api/sandbox_api.lua over a stubbed shared variable.
--
--     lua tests/patrol_spec.lua         (or python tests/run.py)
local here = (arg and arg[0] or ""):match("^(.*)[/\\][^/\\]*$") or "."
local ROOT = here .. "/.."
local STORY, PATROL, API = ROOT .. "/sandbox/scripts/story.lua", ROOT .. "/sandbox/scripts/patrol.lua", ROOT .. "/api/sandbox_api.lua"

local tests = {}
local function test(name, fn) tests[#tests + 1] = { name, fn } end
local function eq(got, want, what)
    if got ~= want then error(string.format("%s: expected %s, got %s", what or "value", tostring(want), tostring(got)), 2) end
end
local function ok(v, what) if not v then error(what or "expected something true", 2) end end

-- ------------------------------------------------------------------ JSON, files
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
local function folder()
    local f = os.tmpname()
    os.remove(f)
    return f
end

-- ------------------------------------------------------------------ the game
local function pts(...)
    local list = {}
    for i, x in ipairs({ ... }) do list[i] = { x = x, y = 0, z = 0 } end
    return list
end

-- A world with the story and patrol parts started in it. o.npcs: the cats' defs (each with at, so it stands
-- at once); o.quests.
local function world(o)
    local f = folder()
    local w = { everys = {}, logs = {}, spawned = {}, shared = {}, t = 100, level = "L_WorldMap_01_P" }
    local Npc = {}
    Npc.__index = Npc
    function Npc:valid() return not self.removed and (self.level == nil or self.level == w.level) end
    function Npc:remove() self.removed = true end
    function Npc:label() end
    function Npc:prompt() end
    function Npc:mapMarker() end
    function Npc:face() end
    function Npc:location() return { X = 0, Y = 0, Z = 0 } end
    function Npc:distance() return 100 end
    function Npc:near() return true end
    function Npc:moveTo(at) self.at = at end
    function Npc:walking() return self.walk ~= nil end
    function Npc:walkTo(x, y, z, opts)
        if self.walkError then error(self.walkError) end
        self.walks = self.walks + 1
        self.walk = { x = x, y = y, z = z, opts = opts }
    end
    function Npc:stop()
        local walk = self.walk
        self.walk = nil
        if walk and walk.opts.done then walk.opts.done(self, "cancelled") end
    end
    -- The walk ends: the engine's done callback.
    function Npc:finish(result)
        local walk = assert(self.walk, "no walk to finish")
        self.walk = nil
        if walk.opts.done then walk.opts.done(self, result) end
    end
    Game = {
        save = { folder = function() return f end },
        json = json,
        npcs = {
            onInteract = function(fn) w.interact = fn end,
            spawn = function(spec)
                local n = setmetatable({ at = spec.at, level = spec.level, walks = 0,
                                         walkError = o.walkError and o.walkError[#w.spawned + 1] }, Npc)
                w.spawned[#w.spawned + 1] = n
                return n
            end,
            spot = function(d, side) return { X = d, Y = side, Z = 0 }, 90 end,
        },
        hud = { objective = function() end, banner = function() end },
        mapMarker = function() return { remove = function() end } end,
        quests = { report = function() end },
        items = { drop = function() return true end },
        dialogue = { busy = function() return false end, claim = function() return true end,
                     hide = function() end, say = function() end },
        every = function(_, fn) w.everys[#w.everys + 1] = fn end,
        on = function() end,
        onPress = function() end,
        player = function() return {} end,
        cat = function() return { location = function() return { X = 0, Y = 0, Z = 0 } end } end,
        levelName = function() return w.level end,
        screens = function() return {} end,
        findAll = function() return {} end,
        valid = function(x) return x ~= nil end,
    }
    MOD = { log = function(fmt, ...) w.logs[#w.logs + 1] = string.format(fmt, ...) end, page = function() end }
    local text = json.encode({ format = 1, icons = {}, mods = { { id = "mine", name = "Mine",
        npcs = o.npcs, quests = o.quests or {} } } })
    ModRef = {
        GetSharedVariable = function(_, name)
            if name == "WCMods.story" then return text end
            return w.shared[name]
        end,
        SetSharedVariable = function(_, name, v) w.shared[name] = v end,
    }
    package.loaded.WCModsDraw = { onFrame = function(fn) w.frame = fn end }
    package.loaded.WCModsView = { worldToScreen = function() return nil end }
    w.state = { active = true, ready = true, slot = 3, new = true, clock = function() return w.t end }
    dofile(STORY)(w.state, { all = function() return {} end })
    dofile(PATROL)(w.state, {})
    w.Sandbox = dofile(API)
    function w.tick(n) for _ = 1, n or 1 do for _, fn in ipairs(w.everys) do fn() end end end
    function w.wait(seconds)   -- time passes, a quarter second at a time as the game's ticks would
        local to = w.t + seconds
        while w.t < to do w.t = w.t + 0.25; w.tick() end
    end
    function w.logged(text)
        for _, l in ipairs(w.logs) do if l:find(text, 1, true) then return true end end
        return false
    end
    function w.cleanup() os.remove(f .. "\\sandbox-story.json") end
    w.tick()   -- the story part starts and stands the cats; the patrol part sends them off
    return w
end

-- The points the cat is sent to, in order, answering each walk with `result` (default "arrived").
local function route(w, npc, n, result)
    local xs = {}
    for i = 1, n do
        w.tick()
        ok(npc.walk, "the cat should be walking (step " .. i .. ")")
        xs[i] = npc.walk.x
        npc:finish(result or "arrived")
    end
    return xs
end
local function same(got, want, what)
    eq(table.concat(got, ","), table.concat(want, ","), what)
end

local function scout(patrol) return { id = "scout", name = "Scout", lines = { "Hm." }, at = { 0, 0, 0 }, patrol = patrol } end

-- ------------------------------------------------------------------ routes
test("test_pingpong_goes_ABCD_then_back_DCBA", function()
    local w = world({ npcs = { scout({ points = pts(100, 200, 300, 400) }) } })   -- pingpong is the default
    same(route(w, w.spawned[1], 10), { 100, 200, 300, 400, 300, 200, 100, 200, 300, 400 }, "route")
    w.cleanup()
end)

test("test_two_points_go_A_B_A_B", function()
    local w = world({ npcs = { scout({ points = pts(100, 200), mode = "pingpong" }) } })
    same(route(w, w.spawned[1], 5), { 100, 200, 100, 200, 100 }, "route")
    w.cleanup()
end)

test("test_a_single_point_is_walked_to_over_and_over", function()
    local w = world({ npcs = { scout({ points = pts(100) }) } })
    same(route(w, w.spawned[1], 3), { 100, 100, 100 }, "route")
    w.cleanup()
end)

test("test_loop_goes_ABCD_ABCD", function()
    local w = world({ npcs = { scout({ points = pts(100, 200, 300, 400), mode = "loop" }) } })
    same(route(w, w.spawned[1], 9), { 100, 200, 300, 400, 100, 200, 300, 400, 100 }, "route")
    w.cleanup()
end)

test("test_once_stops_at_the_last_point", function()
    local w = world({ npcs = { scout({ points = pts(100, 200, 300), mode = "once" }) } })
    local npc = w.spawned[1]
    same(route(w, npc, 3), { 100, 200, 300 }, "route")
    w.wait(5)
    eq(npc.walk, nil, "no more walking")
    eq(npc.walks, 3)
    ok(w.logged("patrol finished"), "the log says so")
    w.cleanup()
end)

test("test_speed_and_coordinates_reach_walkTo", function()
    local w = world({ npcs = { scout({ points = { { x = 1, y = 2, z = 3 }, { 4, 5, 6 } }, speed = 90 }) } })
    local npc = w.spawned[1]
    w.tick()
    eq(npc.walk.opts.speed, 90, "speed")
    eq(npc.walk.y, 2, "y")
    eq(npc.walk.z, 3, "z")
    npc:finish("arrived")
    w.tick()
    eq(npc.walk.x, 4, "the second point, written as a list")
    w.cleanup()
end)

test("test_a_walk_in_progress_is_not_reissued_each_tick", function()
    local w = world({ npcs = { scout({ points = pts(100, 200) }) } })
    local npc = w.spawned[1]
    w.wait(10)
    eq(npc.walks, 1, "walkTo calls while it walks")
    w.cleanup()
end)

test("test_disabled_patrol_does_nothing", function()
    local w = world({ npcs = { scout({ points = pts(100, 200), enabled = false }) } })
    w.wait(3)
    eq(w.spawned[1].walks, 0)
    w.cleanup()
end)

-- ------------------------------------------------------------------ timed waits
test("test_timed_wait_at_a_point_and_as_the_default", function()
    local w = world({ npcs = { scout({ points = { { x = 100, y = 0, z = 0, wait = 5 }, { x = 200, y = 0, z = 0 } }, wait = 2 }) } })
    local npc = w.spawned[1]
    w.tick()
    npc:finish("arrived")               -- at A: waits 5 s
    w.wait(4.5)
    eq(npc.walk, nil, "still waiting at A")
    w.wait(1)
    eq(npc.walk and npc.walk.x, 200, "off to B after 5 s")
    npc:finish("arrived")               -- at B: the default, 2 s
    w.wait(1.5)
    eq(npc.walk, nil, "still waiting at B")
    w.wait(1)
    eq(npc.walk and npc.walk.x, 100, "back to A after 2 s")
    w.cleanup()
end)

test("test_random_wait_stays_inside_min_and_max", function()
    for _ = 1, 5 do
        local w = world({ npcs = { scout({ points = pts(100, 200), wait = { min = 2, max = 4 } }) } })
        local npc = w.spawned[1]
        w.tick()
        npc:finish("arrived")
        w.wait(1.75)
        eq(npc.walk, nil, "not before min")
        w.wait(2.5)
        ok(npc.walk, "gone by max")
        w.cleanup()
    end
end)

test("test_wait_none_passes_through", function()
    local w = world({ npcs = { scout({ points = { { x = 100, y = 0, z = 0, wait = "none" }, { x = 200, y = 0, z = 0 } }, wait = 9 }) } })
    local npc = w.spawned[1]
    w.tick()
    npc:finish("arrived")
    w.tick()
    eq(npc.walk and npc.walk.x, 200, "straight on from A")
    w.cleanup()
end)

-- ------------------------------------------------------------------ triggered waits
test("test_release_wait_holds_until_released", function()
    local w = world({ npcs = { scout({ points = { { x = 100, y = 0, z = 0, wait = "release" }, { x = 200, y = 0, z = 0 } } }) } })
    local npc = w.spawned[1]
    w.tick()
    npc:finish("arrived")
    w.wait(60)
    eq(npc.walk, nil, "a minute later it's still there")
    w.Sandbox.patrol.release("mine/other")
    w.wait(1)
    eq(npc.walk, nil, "another cat's release isn't its own")
    w.Sandbox.patrol.release("mine/scout")
    w.wait(0.5)
    eq(npc.walk and npc.walk.x, 200, "released")
    w.cleanup()
end)

test("test_named_release_and_event_wait", function()
    local w = world({ npcs = { scout({ points = { { x = 100, y = 0, z = 0, wait = { ["until"] = { release = "go", event = "gate-open" } } },
                                                  { x = 200, y = 0, z = 0 } } }) } })
    local npc = w.spawned[1]
    w.Sandbox.raise("gate-open")        -- before it's waiting: missed
    w.tick()
    npc:finish("arrived")
    w.wait(1)
    eq(npc.walk, nil, "an event from before the wait doesn't count")
    w.Sandbox.patrol.release("mine/scout")   -- the unnamed release isn't "go"
    w.wait(1)
    eq(npc.walk, nil, "wrong release name")
    w.Sandbox.raise("gate-open")
    w.wait(0.5)
    eq(npc.walk and npc.walk.x, 200, "the event it waits for")
    npc:finish("arrived")
    w.tick()
    npc:finish("arrived")               -- back at A, waiting again
    w.Sandbox.patrol.release("mine/scout", "go")
    w.wait(0.5)
    eq(npc.walk and npc.walk.x, 200, "the named release")
    w.cleanup()
end)

test("test_trigger_timeout_lets_it_go", function()
    local w = world({ npcs = { scout({ points = { { x = 100, y = 0, z = 0, wait = { ["until"] = { event = "never" }, timeout = 30 } },
                                                  { x = 200, y = 0, z = 0 } } }) } })
    local npc = w.spawned[1]
    w.tick()
    npc:finish("arrived")
    w.wait(29)
    eq(npc.walk, nil, "still waiting")
    w.wait(2)
    eq(npc.walk and npc.walk.x, 200, "timed out")
    w.cleanup()
end)

-- A quest of one cat's: talk to the guide, then talk to the guide again. Two scouts wait at A, one for the
-- quest's second step, one for it to be done.
local function questWorld()
    local function waits(cond)
        return scout({ points = { { x = 100, y = 0, z = 0, wait = { ["until"] = cond } }, { x = 200, y = 0, z = 0 } } })
    end
    local stepper, doner = waits({ quest = "errand", step = 2 }), waits({ quest = "mine/errand" })
    stepper.id, doner.id = "stepper", "doner"
    local w = world({
        npcs = { { id = "guide", name = "Guide", at = { 0, 0, 0 } }, stepper, doner },
        quests = { { id = "errand", title = "Errand", giver = "guide", after = {}, steps = {
            { ["do"] = "talk", npc = "guide", lines = { "Go on." } },
            { ["do"] = "talk", npc = "guide", lines = { "Well done." } } } } },
    })
    local function talk() w.interact(w.spawned[1]); w.frame({ view = {}, width = 1920 }); w.interact(nil) end
    return w, talk
end

test("test_quest_step_and_quest_done_release_the_wait", function()
    local w, talk = questWorld()
    local step, done = w.spawned[2], w.spawned[3]
    w.tick(); step:finish("arrived"); done:finish("arrived")
    w.wait(5)
    eq(step.walk, nil, "nothing's happened in the quest")
    eq(done.walk, nil)
    talk()                              -- step 1 done: the quest is on its step 2
    w.wait(0.5)
    eq(step.walk and step.walk.x, 200, "step 2 reached")
    eq(done.walk, nil, "not done yet")
    talk()                              -- the last step
    w.wait(0.5)
    eq(done.walk and done.walk.x, 200, "the quest is done")
    w.cleanup()
end)

test("test_a_quest_that_isnt_there_lets_the_cat_go_and_says_so", function()
    local w = world({ npcs = { scout({ points = { { x = 100, y = 0, z = 0, wait = { ["until"] = { quest = "nope" } } },
                                                  { x = 200, y = 0, z = 0 } } }) } })
    local npc = w.spawned[1]
    w.tick()
    npc:finish("arrived")
    w.wait(0.5)
    eq(npc.walk and npc.walk.x, 200, "not held for good")
    ok(w.logged("nope"), "the log names the quest")
    w.cleanup()
end)

-- ------------------------------------------------------------------ talking, blocked, respawn, stopping
test("test_it_stops_while_talked_to_and_goes_on_after", function()
    local w = world({ npcs = { scout({ points = pts(100, 200) }) } })
    local npc = w.spawned[1]
    w.tick()
    eq(npc.walk.x, 100)
    w.interact(npc)                     -- the player talks to it
    w.tick()
    eq(npc.walk, nil, "stopped for the talk")
    w.wait(20)
    eq(npc.walk, nil, "and stays stopped")
    w.interact(nil)                     -- the talk ends (its one line is said)
    w.wait(0.5)
    eq(npc.walk and npc.walk.x, 100, "on to the same point")
    w.cleanup()
end)

test("test_a_timed_wait_does_not_run_down_during_a_talk", function()
    local w = world({ npcs = { scout({ points = pts(100, 200), wait = 5 }) } })
    local npc = w.spawned[1]
    w.tick()
    npc:finish("arrived")
    w.wait(3)
    w.interact(npc)
    w.wait(30)
    w.interact(nil)
    w.wait(1)
    eq(npc.walk, nil, "2 s of its wait are left")
    w.wait(2)
    eq(npc.walk and npc.walk.x, 200)
    w.cleanup()
end)

test("test_blocked_is_retried_then_skipped_and_logged", function()
    local w = world({ npcs = { scout({ points = pts(100, 200, 300), retries = 2 }) } })
    local npc = w.spawned[1]
    w.tick()
    eq(npc.walk.x, 100)
    npc:finish("arrived")
    w.tick()
    eq(npc.walk.x, 200)
    npc:finish("blocked")
    w.tick()
    eq(npc.walk, nil, "a moment before it tries again")
    w.wait(1.25)
    eq(npc.walk.x, 200, "retry 1")
    npc:finish("blocked")
    w.wait(1.25)
    eq(npc.walk.x, 200, "retry 2")
    npc:finish("blocked")               -- the third block: skip
    w.tick()
    eq(npc.walk.x, 300, "skipped to the next point")
    ok(w.logged("blocked on the way to point 2"), "the log says so")
    w.cleanup()
end)

test("test_a_cancelled_walk_is_taken_up_again_after_respawn", function()
    local w = world({ npcs = { scout({ points = pts(100, 200) }) } })
    local npc = w.spawned[1]
    w.tick()
    eq(npc.walk.x, 100)
    npc:finish("cancelled")             -- wcmods cancels the walk when the cat is respawned
    w.tick()
    eq(npc.walk, nil, "not at once")
    w.wait(1.25)
    eq(npc.walk and npc.walk.x, 100, "the same target again")
    w.cleanup()
end)

test("test_it_waits_out_a_level_change_and_resumes", function()
    local w = world({ npcs = { scout({ points = pts(100, 200) }) } })
    local npc = w.spawned[1]
    npc.level = "L_WorldMap_01_P"       -- a cat that belongs to a level
    w.tick()
    w.level = "L_Other_P"               -- the cat's level isn't loaded: it isn't valid
    w.wait(2)
    eq(npc.walk, nil, "walk stopped")
    w.level = "L_WorldMap_01_P"
    w.wait(0.5)
    eq(npc.walk and npc.walk.x, 100, "walking again")
    w.cleanup()
end)

test("test_a_point_in_another_level_is_skipped", function()
    local w = world({ npcs = { scout({ points = { { x = 100, y = 0, z = 0, level = "L_Elsewhere" }, { x = 200, y = 0, z = 0 } } }) } })
    w.tick()
    eq(w.spawned[1].walk.x, 200)
    ok(w.logged("L_Elsewhere"), "the log says why")
    w.cleanup()
end)

test("test_it_stops_when_sandbox_mode_ends", function()
    local w = world({ npcs = { scout({ points = pts(100, 200) }) } })
    local npc = w.spawned[1]
    w.tick()
    ok(npc.walk, "walking")
    w.state.active = false
    w.tick()
    eq(npc.walk, nil, "its walk was stopped")
    eq(npc.walks, 1)
    w.tick(5)
    eq(npc.walks, 1, "and nothing starts it again")
    w.cleanup()
end)

-- ------------------------------------------------------------------ bad data
test("test_bad_patrol_data_never_breaks_the_cat", function()
    local bad = {
        "oops", 7, {}, { points = "x" }, { points = {} }, { points = { "a", {}, { x = "1", y = 2, z = 3 } } },
    }
    local npcs = {}
    for i, patrol in ipairs(bad) do
        local c = scout(patrol)
        c.id = "bad" .. i
        npcs[#npcs + 1] = c
    end
    local w = world({ npcs = npcs })
    w.wait(2)
    eq(#w.spawned, #bad, "every cat is in the world")
    for _, npc in ipairs(w.spawned) do eq(npc.walks, 0, "and none walks") end
    ok(w.logged("mine/bad1: patrol"), "the log names the cat")
    w.cleanup()
end)

test("test_bad_parts_are_dropped_and_the_rest_used", function()
    local w = world({ npcs = { scout({
        points = { { x = 100, y = 0, z = 0, wait = "banana" }, "x", { x = 200, y = 0, z = 0, wait = { ["until"] = 5 } }, { x = 300, y = 0, z = 0 } },
        mode = "zigzag", speed = -5, retries = "many", wait = { min = "a" } }) } })
    local npc = w.spawned[1]
    same(route(w, npc, 5), { 100, 200, 300, 200, 100 }, "good points, in pingpong")
    eq(npc.walk == nil, true)
    ok(w.logged("unknown mode"), "mode said")
    ok(w.logged("point 2"), "the bad point said")
    ok(w.logged("speed"), "speed said")
    w.cleanup()
end)

test("test_walkTo_failing_turns_that_patrol_off_only", function()
    local w = world({ npcs = { scout({ points = pts(100, 200) }), scout({ points = pts(100, 200) }) }, walkError = { "boom" } })
    w.tick()
    eq(w.spawned[1].walks, 0)
    ok(w.logged("walkTo failed"), "said")
    ok(w.spawned[2].walk, "the other cat walks on")
    w.cleanup()
end)

test("test_parse_is_exposed_and_tolerant", function()
    local w = world({ npcs = { { id = "a", name = "A", at = { 0, 0, 0 } } } })
    local p = w.state.patrol.parse({ points = pts(1, 2), wait = { 3, 6 } }, "mine/a")
    eq(p.mode, "pingpong")
    eq(p.wait.kind, "timed")
    eq(p.wait.max, 6)
    eq(w.state.patrol.parse(nil, "x"), nil)
    w.cleanup()
end)

-- ------------------------------------------------------------------ run
local failed = 0
for _, t in ipairs(tests) do
    local passed, err = pcall(t[2])
    if passed then print("ok    " .. t[1]) else failed = failed + 1; print("FAIL  " .. t[1] .. ": " .. tostring(err)) end
end
print(string.format("%d tests, %d failed", #tests, failed))
os.exit(failed == 0 and 0 or 1)
