-- Which of the save's cats are sandbox cats. The game's save has nowhere of a cat's own for a mod to
-- write to (the save manager's own stores are shared by every cat), so the list is a file of this mod's:
-- sandbox.json in Game.save.folder() (%LOCALAPPDATA%\Wrc\Saved\WCMods, beside the game's saves), with the
-- slot and, to know it's still the same cat, its Clan and the first part of its name (which doesn't
-- change with its rank, as the -paw/-star part does).
local R = {}

local PATH = Game.save.folder() .. "\\sandbox.json"
local data

local function load()
    if data then return data end
    data = { cats = {} }
    local f = io.open(PATH, "rb")
    if f then
        local text = f:read("a")
        f:close()
        local ok, d = pcall(Game.json.decode, text)
        if ok and type(d) == "table" and type(d.cats) == "table" then data = d end
    end
    return data
end

local function save()
    local f, err = io.open(PATH, "wb")
    if not f then
        MOD.log("couldn't write %s: %s", PATH, tostring(err))
        return false
    end
    f:write(Game.json.encode({ _help = "The sandbox cats, by save slot (0 is the first). Written by the Sandbox mode mod.",
                               cats = Game.json.list(data.cats) }))
    f:close()
    return true
end

-- A cat as the save file has it: { clan = "ThunderClan", prefix = "STR_CAT_NAME6" }, or nil for an empty slot.
function R.saved(slot)
    local file = Game.save.file()
    if type(file) ~= "table" then return nil end
    -- The file's one top-level key is the player's account; the cats are its "0" to "8".
    for _, account in pairs(file) do
        local s = type(account) == "table" and account[tostring(slot)]
        if type(s) == "table" then
            local gp = s.GameplayProgression
            local player = type(gp) == "table" and gp["Gameplay.Combat.Character.Cat.Player"]
            local look = type(player) == "table" and player.Customization
            if type(look) ~= "string" or look == "" then return nil end
            return { clan = look:match("ClanType=(%w+)"), prefix = look:match('PrefixNameId="([^"]*)"') }
        end
    end
    return nil
end

local function same(entry, cat)
    return cat ~= nil and entry.clan == cat.clan and entry.prefix == cat.prefix
end

-- The list's entry for a slot, when the cat in it now is the one that was made there in sandbox mode.
-- `cat` is the cat to compare with (the save's by default).
function R.find(slot, cat)
    for _, e in ipairs(load().cats) do
        if e.slot == slot then
            if same(e, cat or R.saved(slot)) then return e end
            return nil
        end
    end
    return nil
end

function R.add(slot, cat)
    local list = load().cats
    for i = #list, 1, -1 do
        if list[i].slot == slot then table.remove(list, i) end
    end
    list[#list + 1] = { slot = slot, clan = cat.clan, prefix = cat.prefix, made = os.date("!%Y-%m-%dT%H:%M:%SZ") }
    MOD.log("slot %d is a sandbox cat now (%s, %s)", slot, tostring(cat.clan), tostring(cat.prefix))
    return save()
end

-- Forget the cats that aren't there any more: a slot that's empty, or holds another cat, in the save.
function R.prune()
    local list, changed = load().cats, false
    for i = #list, 1, -1 do
        if not same(list[i], R.saved(list[i].slot)) then
            MOD.log("slot %d no longer holds its sandbox cat; forgetting it", list[i].slot)
            table.remove(list, i)
            changed = true
        end
    end
    if changed then save() end
end

function R.all() return load().cats end

return R
