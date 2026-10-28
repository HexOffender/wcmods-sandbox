# Sandbox mode

A Sandbox Mode for *Warrior Cats: Clans of the Forest*, made with
[wcmods](https://github.com/HexOffender/warrior-cats-mods) (Clan Mod Studio). It puts a **Sandbox Mode**
button on the game's main menu, under Prophecy Mode. A cat you make from it lives in the normal forest
with everything the game has (hunting, fights with roaming animals, the fresh-kill pile, dens, moves,
climbing, the clan cats in camp), but with no story and no quests. It's a clean slate for other mods to
fill with their own cats and quests.

## Playing it

1. On the main menu, choose **Sandbox Mode**. The cat choice opens as it does for Prophecy Mode, titled
   "Sandbox: Select Your Cat".
2. Choose an empty slot and make your cat as usual: its Clan, its looks, its name.
3. It starts in its Clan's camp as an apprentice. The prophecy's opening and the apprentice ceremony are
   skipped for you, and there are no quests to follow: the pause screen's Quest tab is empty.

**Coming back:** Sandbox Mode or Prophecy Mode both list all your cats. A sandbox cat says **Sandbox**
under its name, where a story cat shows how far its Clan's prophecy has got. A cat stays what it was made
as, whichever button you came in by: a sandbox cat is always played without the story, and a story cat
always has its story.

**Leaving:** the pause screen's Main Menu, as always. Prophecy Mode is the way back to the story, with a
story cat or a new one.

**Your sandbox cats** are listed in `sandbox.json` in `%LOCALAPPDATA%\Wrc\Saved\WCMods`, beside the game's
saves. The game's save has no place of a cat's own for a mod to mark it, so that list is what makes a cat
a sandbox cat. Remove a sandbox cat in the game and the list forgets it.
- **Steam Cloud** carries the game's saves to another computer but not that list, so there a sandbox
  cat would play as a story cat until the list is copied over too.
- **Without this mod** a sandbox cat plays as a story cat from the start of its Clan's story, since the
  game keeps its own record of the story's quests in the save and this mod clears them as the cat loads.

## Getting it

It's an in-game Lua script, so like any script it runs only with **mods that run code allowed** (Options,
on Clan Mod Studio's Settings and repair page), and it needs UE4SS (Clan Mod Studio's Get set up installs
it).

- **From a release:** download `sandbox-<version>.zip` from [Releases](../../releases) and drop it on
  Clan Mod Studio's Mods page, or `python wcmods.py add sandbox-<version>.zip`. Then Apply to game (or
  press Play).
- **From this repository:** `python wcmods.py add path\to\wcmods-sandbox\sandbox`.

The mod's folder must be called `sandbox`: that's its id, and the name other mods give in `"requires"`.

## Cats and questlines from Clan Mod Studio

You don't need to write code to fill the sandbox. Clan Mod Studio (a wcmods with its Characters and Questlines pages) has pages for
it under **Make mods**:

- **Characters:** cats of your own, with their name, a title over it ("Elder"), a look (one the game makes
  up each time they appear, or a fixed one: their shape, pattern and colour slots), colours, eyes, size,
  where they stand and what they say.
- **Questlines:** quests with those cats, step by step: talk to a cat, pick things up, go somewhere (a spot
  you stand on in the game, or your Clan's medicine cat). A quest can wait for others to be done first, so
  quests make a story, and it ends with a reward dropped at your cat's paws.
- **Items:** herbs and materials of your own, for recipes and rewards. They're real items, in story games
  too.

Save them to a mod, then Apply (or Play). This mod brings the cats into the forest with a sandbox cat and
runs the quests:

- A cat without a spot of its own turns up beside your sandbox cat the first time it comes into the
  forest, and stays there for that cat. They wear the game's own label over their heads, with the game's
  quest marks, and the game's own **Talk** prompt: its Interact key or button (E, or A on a controller)
  talks to them and goes on with the talk. (With an older wcmods, without these, the names are drawn and
  **G**, or the d-pad's up, talks instead.)
- The step you're on shows in the game's objective panel on the left, with a marker on the map where to
  go (with an older wcmods, without them, the quests going on are drawn at the top right). The mod menu's
  **Questlines** page (under Story) lists them, with each quest's "About it" under its title, can start
  one or every questline over, says where each cat is ("In the world", "Waiting for the forest", "No room
  beside you yet") and can bring a cat beside you again; the Quests page (with Menu pages) lists them with
  the game's.
- A cat placed at a spot of its own with no facing turns to face your cat the first time it's there.
- How far each sandbox cat has got is kept in `sandbox-story.json` beside the game's saves: one record per
  save slot, with when the sandbox cat in it was made, so a new sandbox cat made in the slot of one you
  deleted starts every questline from the beginning. Each quest's record keeps its shape (its steps' kinds,
  and what a Pick up step wants): a quest a cat hasn't finished starts over by itself, with the game's
  banner saying so, when you add or take out a step in Clan Mod Studio, change a step's kind (moving steps
  can do that), or change what or how many a Pick up step wants. New lines, objectives or a new title don't
  restart it, and a quest the cat has finished stays finished (its reward isn't dropped again). Clan Mod
  Studio's Questlines page has **Start every questline over** too (from the wcmods release that carries
  it), for every mod's questlines while the game is closed.
- **Versions that go together:** the game's own labels and *Talk* prompt need a wcmods with
  `Game.npcs.onInteract`; the objective panel and the map markers need one with `Game.hud` and
  `Game.mapMarker`; a character's fixed look (Same look every time) needs Sandbox mode 0.5; progress per
  cat and quests that start over when changed are 0.5's too. A `sandbox-story.json` written by 0.4 is kept
  as it is and takes the new records from its next save. Clan Mod Studio's Characters and Questlines pages
  say which version you have and what it can show.

To share what you made, use **Share** on any of those pages: **Save as .zip** gives the whole mod, which
anyone adds on their Mods page. It works with this mod (`"uses": ["sandbox"]`, which the studio writes):
turning it on turns this one on when it's there, and without it the rest of the mod still goes in.
[`examples/sandbox-story`](examples/sandbox-story) is one made that way: two cats, two quests one after
the other, and a herb of its own for the reward.

## For mod makers

Sandbox mode does nothing with the world but take the story out. What goes in is up to other mods: cats of
their own (`Game.npcs`), talk (`Game.dialogue`), quests of their own (`Game.quests.report` lists them on
the mod menu's Quests page), items as pickups (`Game.items.drop`), the time of day and so on, all from
wcmods' `WCModsGame` ([docs/scripting.md](https://github.com/HexOffender/warrior-cats-mods/blob/main/docs/scripting.md)).

**Knowing when it's on:** copy [`api/sandbox_api.lua`](api/sandbox_api.lua) into your mod's `scripts/`
folder, and add `"requires": ["sandbox"]` to your `mod.json` so turning your mod on turns this one on.

```lua
local Sandbox = require("sandbox_api")

Sandbox.onEnter(function(info)        -- a sandbox cat is in the forest, and your script can add to it
    -- info.slot (0 to 8), info.clan ("ThunderClan"), info.new (made this time), info.session
    local at, yaw = Game.npcs.spot(250)
    myCat = Game.npcs.spawn({ at = at, yaw = yaw, colours = { fur = "#7a6a58" } })
end)

Sandbox.onLeave(function()            -- back to the main menu: take it all away
    if myCat then myCat:remove() end
end)
```

| `Sandbox.` | Gives |
|---|---|
| `onEnter(fn)`, `onLeave(fn)` | `fn(info)` each time a sandbox cat is in the forest and ready (below), `{slot, clan, new, session}`; `fn()` when it goes. Checked twice a second |
| `active()` | Whether a sandbox cat is in the forest (or loading into it) |
| `ready()` | Whether it's being played: the game has begun, with no story scene on. A new cat's opening scenes play (and are skipped) after it's already in the forest, so wait for this before putting anything beside it |
| `slot()`, `clan()` | Its save slot (0 to 8) and Clan, or nil |
| `isNew()` | Whether it was made this time, for what happens once per cat |
| `session()` | A number that goes up each time a sandbox cat comes into the forest |
| `installed()`, `version()` | Whether Sandbox mode is running, and its version |

Each UE4SS mod has a Lua state of its own, so `sandbox_api.lua` doesn't call this mod: it reads what this
mod shares through UE4SS's shared variables, which any UE4SS Lua mod can read itself with
`ModRef:GetSharedVariable(name)`:

| Variable | |
|---|---|
| `Sandbox.active` | `true` while a sandbox cat is in the forest (or loading into it) |
| `Sandbox.ready` | `true` once it's being played, with no story scene on |
| `Sandbox.slot` | Its save slot, `-1` when there's none |
| `Sandbox.clan` | Its Clan, `""` when there's none |
| `Sandbox.new` | `true` when it was made this time |
| `Sandbox.session` | Goes up by one each time a sandbox cat comes into the forest |
| `Sandbox.version` | This mod's version |

Keep what your mod remembers per cat by its slot, in a file of your own in `Game.save.folder()`, as the
example does.

**The example,** [`examples/sandbox-welcome`](examples/sandbox-welcome): Mossfoot turns up beside your
sandbox cat with a small quest, three dandelions, and herbs for a reward. G (or the d-pad's up) talks to
them. It shows a cat, its talk, a quest listed on the mod menu's Quests page, counting pickups with the
`itemPickedUp` event, a reward, and remembering each cat's progress.

**What's left out with the story:**
- **Rank:** the game promotes a cat through its quests, so a sandbox cat stays an apprentice. Nothing in
  wcmods sets the rank yet.
- **The game's own quest system:** the quests are cleared rather than turned off, so a mod can't hand out
  one of the game's quests (`Game.quests.give`) on a sandbox cat; the next check clears it again. A mod's
  quests are its own, as in the example.

## How it works

`sandbox/` is the mod as it goes in your mods folder:

```
sandbox/
  mod.json              its name, version and the game builds it was tried on
  scripts/main.lua      starts the parts below
  scripts/frontend.lua  the main menu's button and the cat choice
  scripts/world.lua     the forest with a sandbox cat, and the shared variables
  scripts/registry.lua  the list of sandbox cats (sandbox.json)
  scripts/story.lua     the cats and questlines from Clan Mod Studio (wcmods shares them as WCMods.story),
                        with the game's own labels and Talk prompt (npc:label, npc:prompt)
```

- **The button** is one more of the main menu's own buttons (`WBP_GuiButtonMenu_C`), put in its column
  under Prophecy Mode and in its keyboard and controller navigation. The game only tells a screen about
  presses on buttons it made, so the script reads the press itself: Enter or the controller's A while the
  button has the focus, or a click. It then opens the cat choice the way Prophecy Mode does.
- **The quests:** the game builds a cat's 40 quests from its quest line while the forest loads. When the
  game state leaves its first phase, they're cleared with the quest manager's own `ResetQuests`, before
  play begins, and again whenever any come back. (Clearing them in the middle of play instead left the
  quest givers' marks on the map.)
- **The story's scenes** (the prophecy's opening and the apprentice ceremony, played the first time a cat
  is in the forest) are skipped with the game's own hold-to-skip. The save then records them as played,
  as it would have.
- **Tried in game** on build 26184573:
  - the button and its navigation, with the keyboard;
  - new ThunderClan, RiverClan and WindClan sandbox cats: the opening and the ceremony skipped, the 40
    quests cleared, an empty Quest tab, an apprentice in its camp;
  - a sandbox cat loaded again, from Sandbox Mode and from Prophecy Mode;
  - a story cat left with its quests, and the cat choice's labels in both modes;
  - the shared variables, read from another mod;
  - `ready` coming after the skipped scenes;
  - the example's whole quest: talk, pickups, hand-in, reward, and progress kept per cat.

  Not tried yet: a ShadowClan cat, the controller and the mouse on the button, and removing a sandbox cat
  (the list should forget it the next time the cat choice opens).

## Tests

`python tests/run.py` checks that every Lua file loads, then runs `tests/story_spec.lua`: the story part
(`scripts/story.lua`) with the game stubbed, driven through what it registers (its half-second keeper, the
`itemPickedUp` event, the Talk prompt, its drawing and its mod menu page). It needs Lua 5.4, the version
UE4SS embeds (`lua5.4`, or a `lua` that is 5.4, on the PATH); without one it says so and skips. CI runs it
on every pull request, and packs the .zips.

## Releasing

1. Raise `"version"` in `sandbox/mod.json` (and `VERSION` in `scripts/world.lua`, which other mods see).
   After a game update, try it on the new build and add the build's number to `"game_builds"`.
2. `python tools/pack.py` makes `dist/sandbox-<version>.zip`, `dist/sandbox-welcome-<version>.zip` and
   `dist/sandbox-story-<version>.zip`.
3. Make a GitHub release tagged `v<version>` with them attached.

Release a new version before, or together with, the wcmods release whose Clan Mod Studio names it: the
studio's Characters and Questlines pages tell creators to download `sandbox-<version>.zip`, which has to be
on the Releases page by then.
