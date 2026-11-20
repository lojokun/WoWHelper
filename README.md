# WoWHelper

A step-by-step leveling guide addon for **WoW Forever** (client 1.60.1, TOC `Interface: 16001`).
Guides are written in JSON, packed into the addon, and shown in a small window above the chat frame.

## Install

1. Build the guides (only needed after editing JSON; the built files are already included):
   ```bash
   python tools/build_guides.py
   ```
2. Copy `addon/WoWHelper` into your WoW Forever `Interface/AddOns` folder, or let the script do it:
   ```bash
   python tools/build_guides.py --install "C:\path\to\World of Warcraft\_forever_\Interface\AddOns"
   ```
   (The folder name of the Forever install may differ on your machine.)

## In game

The window opens above the chat frame on the left. It shows the current step (highlighted) and the next few,
with coordinates, an arrow and the distance to the target.

- **Steps complete themselves** when you accept, finish or turn in the quest, reach the spot, set your hearthstone,
  open the flight master, close the trainer, or reach the level.
- `>` marks the current step done (for notes, or anything the addon can't detect). `<` goes back one step.
- Left-click a step to put a waypoint on it, right-click to mark it done or not done.
- `=` opens the guide list (and **Import...**, and **Restart current guide**).
- **Level-aware start:** on a character's first login the addon picks the guide for its race and level and skips
  past every quest it has already turned in (and every level checkpoint it has already passed).
- Each guide hands over to the next one. If you outlevel the current guide, a chat message points you to `/wh auto`,
  which jumps to the guide for your level the same way.
- Optional quests you never picked up are skipped on their own.

| Command | What it does |
|---|---|
| `/wh` | Show or hide the window |
| `/wh unlock` / `/wh lock` | Unlock to drag the window (and resize its width); lock it again |
| `/wh reset` | Put the window back above the chat frame |
| `/wh next` / `/wh prev` | Mark current step done / go back one step |
| `/wh guides` | Choose a guide |
| `/wh auto` | Jump to the guide for your level, skipping quests you have already done |
| `/wh import` | Paste a JSON guide in game (saved account-wide) |
| `/wh where [action] [quest]` | Print your map, coordinates and target as a JSON step, for writing or fixing guides |
| `/wh waypoint` | Waypoint the current step |
| `/wh options` | Options (Game Menu > Options > AddOns > WoWHelper) |

Waypoints use TomTom if it is installed, otherwise the built-in map pin.

## Guides included (Undead, all classes)

| File | Levels | Zones |
|---|---|---|
| `01_tirisfal_glades.json` | 1-12 | Deathknell, Brill, Undercity |
| `02_silverpine_forest.json` | 12-16 | The Sepulcher, Undead-only Sepulcher chain, Rogue Deathstalkers chain |
| `03_the_barrens.json` | 16-22 | Crossroads, Ratchet, Camp Taurajo, Stonetalon/Ashenvale trips, Warlock Succubus |
| `04_horde_22_30.json` | 22-30 | Stonetalon, Fenris Isle, Hillsbrad, southern Barrens, Ashenvale, Warlock Felhunter start |
| `05_horde_30_37.json` | 30-37 | Thousand Needles, Shimmering Flats, Desolace, Alterac, northern Stranglethorn |
| `06_horde_37_40.json` | 37-40 | Arathi Highlands, Alterac, Dustwallow Marsh |
| `07_horde_40_45.json` | 40-45 | Swamp of Sorrows, **The Riverglades** (Forever), Badlands |
| `08_horde_45_51.json` | 45-51 | Booty Bay, Dustwallow, Tanaris, Feralas, The Hinterlands |
| `09_horde_51_60.json` | 51-60 | Un'Goro, Burning Steppes, Winterspring, Felwood, Plaguelands, **Mount Hyjal** (Forever) |

Steps for one class only use `"classes": [...]`, so each class sees only its own steps.

**Accuracy:**
- Classic-era zones use quest IDs and coordinates from Classic Era data. WoW Forever changed some quests
  (new IDs, raised levels in Tirisfal), so the addon also matches quests by name.
- The Riverglades and Mount Hyjal quests have Forever quest IDs and quest givers, but no published coordinates yet.
- Felwood and the Western/Eastern Plaguelands use quest names without IDs and approximate coordinates.
- Fix anything that is off in game with `/wh where`, which prints a ready-to-paste JSON step.

## Guide format

```jsonc
{
  "schemaVersion": 1,
  "id": "undead-01-tirisfal",        // unique
  "title": "Tirisfal Glades",
  "faction": "Horde",                // optional filter
  "races": ["Scourge"],              // optional filter; "Undead" also works
  "classes": ["warlock"],            // optional filter
  "minLevel": 1, "maxLevel": 12,
  "next": "undead-02-silverpine",    // guide loaded after this one
  "zone": "Tirisfal Glades",         // default zone for steps
  "steps": [
    { "action": "accept", "quest": "Rude Awakening", "questId": 363,
      "npc": "Undertaker Mordo", "x": 30.21, "y": 71.64, "note": "Shown under the step" }
  ]
}
```

Step fields: `action`, `quest`, `questId`, `objective` (index, for `complete`), `npc`, `zone` (inherited by later
steps), `x`, `y` (0-100), `radius` (yards), `location`, `level`, `item`, `text` (replaces the generated text),
`note`, `classes`, `races`, `optional`.

| Action | Completes when |
|---|---|
| `accept` | The quest is in your log |
| `complete` | The quest (or `objective`) is complete, or turned in |
| `turnin` | The quest is turned in |
| `goto` | You are within `radius` yards (default 15), or, without coordinates, your zone/subzone name equals `location` |
| `fly` / `hearth` | You arrive near the target, or your zone/subzone name equals `location` |
| `flightpath` | You open the flight master's map |
| `sethearth` | You bind your hearthstone (or it is already bound to `location`) |
| `train` | You close the trainer window |
| `buy` | You close the vendor window |
| `level` | You reach `level` |
| `note` | You click `>` |

Zone names map to map IDs in `guides/zones.json`. New Forever zones (`null` there) are looked up by name in game.

## Development

- `tools/build_guides.py` validates every guide and writes `addon/WoWHelper/Guides/*.lua` plus `Guides.xml`.
- `tools/test/run_tests.py` runs the addon's Lua against a mocked WoW API (needs `pip install lupa`).
