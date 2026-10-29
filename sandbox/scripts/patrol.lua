-- Patrols: cats from Clan Mod Studio (story.lua) that walk a route of points on their own. A cat's npcs.json
-- entry may carry a "patrol" block (the cat's def, c.def.patrol); this part reads it and walks the cat with
-- npc:walkTo, one point after the next:
--
--   "patrol": {
--     "points": [ {"x": 0, "y": 0, "z": 0, "wait": 5}, {"x": 900, "y": 0, "z": 0}, ... ],   -- "level" per point is optional
--     "mode": "pingpong",     -- ABCD then CBA then BCD...; "loop": ABCDABCD; "once": ABCD and stop
--     "speed": 150,           -- cm/s, optional
--     "retries": 2,           -- tries again after a walk is blocked, then skips the point (default 2)
--     "enabled": true,        -- false: the cat doesn't patrol
--     "wait": 3               -- the wait at points with none of their own (below); none by default
--   }
--
-- A wait, per point ("wait" on the point) or as the default ("wait" on the patrol), is one of:
--   5                                  timed, in seconds        {"min": 3, "max": 8}  or  [3, 8]   a random time
--   "none"                             pass through
--   "release"                          until released: Sandbox.patrol.release(key) from any mod
--   {"until": {...}, "timeout": 60}    until a trigger fires (any one of them), or the timeout (seconds) runs out:
--       "quest": "id"                  the quest is done ("mod/id" for another mod's quest); with
--       "step": 2                      ...only that step reached (step n: the first n-1 steps are done)
--       "event": "name"                Sandbox.raise("name") from any mod, while it's waiting
--       "release": true | "name"       Sandbox.patrol.release(key) or Sandbox.patrol.release(key, name)
--
-- Things are shared with other mods through shared variables (see api/sandbox_api.lua): an event is a counter
-- in Sandbox.event.<name>, and a release is the event Sandbox.event.patrol.release.<key>.<name>, where key is
-- "<mod id>/<cat id>". A trigger fires when the counter has changed since the wait began.
--
-- The cat pauses while it's being talked to (and while its level isn't loaded) and carries on after, goes
-- on walking after a respawn, and stops when the cat is removed or Sandbox mode ends.
local TICK = 0.25               -- seconds between checks
local RETRY_AFTER = 1.0         -- seconds before a blocked walk is tried again
local DEFAULT_RETRIES = 2
local MAX_CANCELS = 5           -- walks cancelled by someone else in a row, before backing off
local BACKOFF = 10              -- seconds
local EVENT = "Sandbox.event."
local MODES = { pingpong = true, loop = true, once = true }

local NONE = { kind = "none" }

local function num(v)
    if type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then return v end
    return nil
end

local function str(v) return type(v) == "string" and v ~= "" and v or nil end

-- ------------------------------------------------------------------ reading the block
local function point(p)
    if type(p) ~= "table" then return nil end
    local x, y, z
    if p.x ~= nil or p.X ~= nil then
        x, y, z = num(p.x or p.X), num(p.y or p.Y), num(p.z or p.Z)
    else
        x, y, z = num(p[1]), num(p[2]), num(p[3])
    end
    if not (x and y and z) then return nil end
    return { x = x, y = y, z = z, level = str(p.level), rawWait = p.wait }
end

-- A wait from its JSON: nil for none given or one that makes no sense (warn says why).
local function parseWait(raw, warn)
    if raw == nil then return nil end
    if raw == "none" then return NONE end
    if raw == "release" or raw == "trigger" then return { kind = "trigger", conds = { release = true } } end
    local n = num(raw)
    if n then n = math.max(n, 0); return { kind = "timed", min = n, max = n } end
    if type(raw) ~= "table" then
        warn("a wait must be a number of seconds, [min, max], \"none\", \"release\" or an object, not " .. tostring(raw))
        return nil
    end

    local timeout = raw.timeout ~= nil and num(raw.timeout) or nil
    if raw.timeout ~= nil and not (timeout and timeout > 0) then
        warn("a wait's timeout must be a number of seconds above 0")
        timeout = nil
    end

    local u = raw["until"]
    if u ~= nil or (raw.timeout ~= nil and raw.min == nil and raw.max == nil and raw.seconds == nil) then
        if u ~= nil and type(u) ~= "table" then warn("a wait's \"until\" must be an object") return nil end
        u = u or {}
        local conds = {}
        if u.quest ~= nil then
            if str(u.quest) then
                conds.quest = u.quest
                if u.step ~= nil then
                    local s = num(u.step)
                    if s and s >= 1 then conds.step = math.floor(s) else warn("a wait's step must be 1 or more") end
                end
            else warn("a wait's quest must be a quest id") end
        end
        if u.event ~= nil then
            if str(u.event) then conds.event = u.event else warn("a wait's event must be a name") end
        end
        if u.release ~= nil then
            if u.release == true then conds.release = true
            elseif str(u.release) then conds.release = u.release
            else warn("a wait's release must be true or a name") end
        end
        if next(conds) == nil then
            if next(u) ~= nil then warn("a wait's \"until\" has nothing it understands") return nil end
            conds.release = true
        end
        return { kind = "trigger", conds = conds, timeout = timeout }
    end

    local lo, hi = num(raw.min or raw[1]), num(raw.max or raw[2])
    local secs = num(raw.seconds)
    if secs then lo, hi = secs, secs end
    if lo and not hi then hi = lo end
    if hi and not lo then lo = hi end
    if not lo then warn("a wait needs seconds, min and max, or an \"until\"") return nil end
    lo, hi = math.max(lo, 0), math.max(hi, 0)
    if lo > hi then lo, hi = hi, lo end
    return { kind = "timed", min = lo, max = hi }
end

-- A cat's patrol block as the runner uses it, or nil when it has none, is turned off or has no usable points.
-- Bad parts are dropped with a line in the log; the cat itself is never affected.
local function parsePatrol(raw, key, log)
    if raw == nil then return nil end
    local function warn(text) log("%s: patrol: %s", key, text) end
    if type(raw) ~= "table" then warn("expected an object, not " .. type(raw)) return nil end
    if raw.enabled == false then return nil end
    if type(raw.points) ~= "table" then warn("no list of points, so the cat stays put") return nil end
    local points = {}
    for i = 1, #raw.points do
        local p = point(raw.points[i])
        if p then
            points[#points + 1] = p
        else
            warn(string.format("point %d needs x, y and z (numbers); it's left out", i))
        end
    end
    if #points == 0 then warn("no usable points, so the cat stays put") return nil end

    local mode = raw.mode
    if mode == nil then mode = "pingpong"
    elseif not MODES[mode] then
        warn("unknown mode " .. tostring(mode) .. " (pingpong, loop or once); using pingpong")
        mode = "pingpong"
    end

    local speed
    if raw.speed ~= nil then
        speed = num(raw.speed)
        if not (speed and speed > 0) then warn("speed must be a number above 0; using the default") speed = nil end
    end
    local retries = DEFAULT_RETRIES
    if raw.retries ~= nil then
        local r = num(raw.retries)
        if r and r >= 0 then retries = math.min(math.floor(r), 10) else warn("retries must be 0 or more; using " .. DEFAULT_RETRIES) end
    end

    local default = parseWait(raw.wait, warn) or NONE
    for i, p in ipairs(points) do
        p.wait = parseWait(p.rawWait, function(t) warn(string.format("point %d: %s", i, t)) end)
        p.rawWait = nil
    end
    return { points = points, mode = mode, speed = speed, retries = retries, wait = default }
end

-- ------------------------------------------------------------------ the runner
return function(state, Reg)
    local runners = {}          -- cat key -> runner

    local function now() return (state.clock or os.clock)() end

    local function counter(name)
        local ok, v = pcall(function() return ModRef:GetSharedVariable(EVENT .. name) end)
        return ok and v or nil
    end

    -- A named event, raised from inside this mod (other mods use Sandbox.raise from api/sandbox_api.lua).
    local function raise(name)
        local n = tonumber(counter(name)) or 0
        pcall(function() ModRef:SetSharedVariable(EVENT .. name, n + 1) end)
    end

    local function releaseName(key, name) return "patrol.release." .. key .. "." .. (type(name) == "string" and name or "") end

    local function release(key, name) raise(releaseName(key, name)) end

    -- Which shared counters a trigger watches, as they are now.
    local function baselines(r, spec)
        local b = {}
        if spec.conds.event then b[spec.conds.event] = counter(spec.conds.event) end
        if spec.conds.release then
            local name = releaseName(r.c.key, spec.conds.release)
            b[name] = counter(name)
        end
        return b
    end

    local function triggered(r, spec)
        local conds = spec.conds
        if conds.event and counter(conds.event) ~= r.base[conds.event] then return true end
        if conds.release then
            local name = releaseName(r.c.key, conds.release)
            if counter(name) ~= r.base[name] then return true end
        end
        if conds.quest then
            local modId, id = r.c.mod and r.c.mod.id, conds.quest
            local m, q = conds.quest:match("^([^/]+)/(.+)$")
            if m then modId, id = m, q end
            local info = state.story and state.story.quest and state.story.quest(modId, id)
            if not info then
                -- A quest that isn't there would hold the cat for good: let it go, once said.
                if not r.said["q:" .. conds.quest] then
                    r.said["q:" .. conds.quest] = true
                    MOD.log("%s: patrol waits for the quest %s, which there isn't; carrying on", r.c.key, conds.quest)
                end
                return true
            end
            if info.started then
                if info.done then return true end
                if conds.step and info.step >= conds.step then return true end
            end
        end
        return false
    end

    local function newRunner(c)
        local r = { c = c, state = "idle", idx = 1, dir = 1, gen = 0, tries = 0, cancels = 0, skips = 0, said = {} }
        r.cfg = parsePatrol(c.def.patrol, c.key, MOD.log)
        return r
    end

    local function stopWalk(r)
        r.gen = r.gen + 1   -- the walk's own "cancelled" is then ignored
        if r.state == "walking" then
            local npc = r.npc
            if npc then pcall(function() npc:stop() end) end
            r.state = "idle"
        end
    end

    local function halt(r)
        stopWalk(r)
        r.cfg = nil
    end

    local function advance(r)
        local n, cfg = #r.cfg.points, r.cfg
        r.tries = 0
        r.state = "idle"
        if cfg.mode == "once" then
            if r.idx >= n then
                r.state = "done"
                MOD.log("%s: patrol finished", r.c.key)
            else r.idx = r.idx + 1 end
        elseif cfg.mode == "loop" then
            r.idx = r.idx % n + 1
        elseif n > 1 then
            if r.dir == 1 and r.idx == n then r.dir = -1 elseif r.dir == -1 and r.idx == 1 then r.dir = 1 end
            r.idx = r.idx + r.dir
        end
    end

    local function arrive(r)
        local p = r.cfg.points[r.idx]
        local spec = p.wait or r.cfg.wait
        r.tries, r.cancels, r.skips = 0, 0, 0
        r.spec, r.deadline, r.timeoutAt = nil, nil, nil
        if spec.kind == "timed" then
            local d = spec.max > spec.min and (spec.min + math.random() * (spec.max - spec.min)) or spec.min
            if d <= 0 then return advance(r) end
            r.state, r.deadline = "waiting", now() + d
        elseif spec.kind == "trigger" then
            r.state, r.spec = "waiting", spec
            r.base = baselines(r, spec)
            r.timeoutAt = spec.timeout and now() + spec.timeout or nil
        else
            advance(r)
        end
    end

    local function onDone(r, gen, result)
        if gen ~= r.gen or r.state ~= "walking" then return end
        if result == "arrived" then
            arrive(r)
        elseif result == "blocked" then
            r.tries = r.tries + 1
            if r.tries <= r.cfg.retries then
                r.state, r.deadline = "retry", now() + RETRY_AFTER
            else
                MOD.log("%s: patrol blocked on the way to point %d; skipping it", r.c.key, r.idx)
                advance(r)
            end
        else
            -- Cancelled by something else (another walkTo, a moveTo): try again, but not forever.
            r.cancels = r.cancels + 1
            if r.cancels > MAX_CANCELS then
                r.cancels = 0
                MOD.log("%s: patrol keeps being interrupted; waiting %d seconds", r.c.key, BACKOFF)
                r.state, r.deadline = "retry", now() + BACKOFF
            else
                r.state, r.deadline = "retry", now() + RETRY_AFTER
            end
        end
    end

    local function issue(r)
        local npc, cfg = r.npc, r.cfg
        local p = cfg.points[r.idx]
        local level = npc.level or Game.levelName()
        if p.level and p.level ~= level then
            -- A point in another level than the cat's: it can't walk there, so it's left out.
            if not r.said[r.idx] then
                r.said[r.idx] = true
                MOD.log("%s: patrol point %d is in %s, the cat is in %s; skipping it", r.c.key, r.idx, p.level, tostring(level))
            end
            r.skips = r.skips + 1
            if r.skips >= #cfg.points then
                r.skips = 0
                r.state, r.deadline = "retry", now() + BACKOFF
                return
            end
            return advance(r)
        end
        if type(npc.walkTo) ~= "function" then
            MOD.log("%s: this wcmods has no npc:walkTo, so the patrol is off", r.c.key)
            r.cfg = nil
            return
        end
        r.gen = r.gen + 1
        local gen = r.gen
        r.state, r.issuedAt = "walking", now()
        local opts = { speed = cfg.speed, done = function(_, result) onDone(r, gen, result) end }
        local ok, err = pcall(npc.walkTo, npc, p.x, p.y, p.z, opts)
        if not ok then
            MOD.log("%s: patrol: walkTo failed: %s; the patrol is off", r.c.key, tostring(err))
            r.cfg, r.state = nil, "idle"
        end
    end

    local function step(r)
        local c, story = r.c, state.story
        local npc = c.npc
        local here = npc ~= nil and npc:valid()
        local talked = story.talking and story.talking() == c
        if npc ~= r.npc then
            -- A new cat (placed, brought or respawned): its old walk went with it.
            r.npc = npc
            r.gen = r.gen + 1
            if r.state == "walking" then r.state = "idle" end
        end
        if not here or talked then
            if r.state == "walking" then stopWalk(r) end
            r.pausedAt = r.pausedAt or now()
            return
        end
        if r.pausedAt then
            -- Waits don't run down while the cat was away or talking.
            local gap = now() - r.pausedAt
            if r.deadline then r.deadline = r.deadline + gap end
            if r.timeoutAt then r.timeoutAt = r.timeoutAt + gap end
            r.pausedAt = nil
            if r.state == "walking" then r.state = "idle" end
        end

        local s = r.state
        if s == "walking" then
            -- Safety net for a walk that ended without saying so (its cat was respawned).
            if now() - r.issuedAt > 1 then
                local ok, walking = pcall(function() return npc:walking() end)
                if ok and not walking then onDone(r, r.gen, "cancelled") end
            end
        elseif s == "idle" then
            issue(r)
        elseif s == "retry" then
            if now() >= r.deadline then r.state = "idle" end
        elseif s == "waiting" then
            if r.deadline then
                if now() >= r.deadline then advance(r) end
            elseif triggered(r, r.spec) or (r.timeoutAt and now() >= r.timeoutAt) then
                advance(r)
            end
        end
    end

    local function clearAll()
        for key, r in pairs(runners) do
            halt(r)
            runners[key] = nil
        end
    end

    local function tick()
        local story = state.story
        if not (state.active and story and story.cats) then
            if next(runners) then clearAll() end
            return
        end
        local seen = {}
        for _, c in ipairs(story.cats()) do
            if type(c.def) == "table" and c.def.patrol ~= nil then
                seen[c.key] = true
                local r = runners[c.key]
                if not r or r.c ~= c then
                    if r then halt(r) end
                    r = newRunner(c)
                    runners[c.key] = r
                end
                if r.cfg then
                    local ok, err = pcall(step, r)
                    if not ok then
                        MOD.log("%s: patrol stopped: %s", c.key, tostring(err))
                        halt(r)
                    end
                end
            end
        end
        for key, r in pairs(runners) do
            if not seen[key] then
                halt(r)
                runners[key] = nil
            end
        end
    end

    Game.every(TICK, tick)

    state.patrol = { parse = function(raw, key) return parsePatrol(raw, key, MOD.log) end,
                     raise = raise, release = release, tick = tick, runners = runners }
end
