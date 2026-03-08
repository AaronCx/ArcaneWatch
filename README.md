# ArcaneWatch

A combined threat meter and spell cooldown tracker for World of Warcraft 1.12 (Turtle WoW). Clean, minimal UI with no dependencies.

![Interface: 11200](https://img.shields.io/badge/Interface-11200-blue) ![Version: 1.10.0](https://img.shields.io/badge/Version-1.10.0-green) ![Lua 5.0](https://img.shields.io/badge/Lua-5.0-yellow)

## Features

### Threat Meter
- Tracks threat for all party and raid members (up to 40-man)
- Hybrid approach: uses Turtle WoW's `UnitDetailedThreatSituation` API when available, falls back to combat log parsing
- Per-target threat tables — switching targets shows that mob's threat data independently
- Class-colored bars normalized to the top threat holder (100%)
- Player's own row highlighted with a subtle glow
- Auto-shows on combat start, fades out after combat ends (configurable)
- Dynamic panel height — shrinks to fit only active rows
- High-threat warning: red flash overlay + sound when you reach 90% of the tank's threat
- Mob death clears its threat table automatically

### Spell Timers
- Auto-detects up to 9 spells from your spellbook — works for any class
- Each spell has a known type: cooldown (`cd`) or buff/debuff duration (`dur`)
- State flow: **Ready** (green bar, pulsing icon) → **Active** (countdown, blue→yellow→red) → **Ready**
- Filters out resist/immune/miss/dodge/parry so failed casts don't trigger timers
- Syncs with `GetSpellCooldown` on login and `/reload` to restore in-progress cooldowns
- Sound alert when a timer returns to Ready
- Re-scans spellbook on talent respec or level up
- Covers Warlock, Mage, Priest, Druid, Rogue, Warrior, Hunter, Paladin, and Shaman spells

### Config Panel
- Toggle threat meter on/off
- Toggle spell timers on/off
- Lock/unlock panel dragging
- Reset panel positions
- Auto-hide threat out of combat (checkbox)
- Threat warning sound toggle
- Timer ready sound toggle
- Opacity slider (20%–100%)

### Minimap Button
- Left-click: open config panel
- Right-click: toggle both panels on/off

### Tooltips
- Hover threat rows to see player name, threat %, and raw threat value
- Hover timer rows to see spell name, type (Cooldown/Duration), and total duration

## Installation

1. Download or clone this repo
2. Copy the `ArcaneWatch` folder into your `Interface/AddOns/` directory
3. Restart the WoW client or type `/console reloadui`

```
TurtleWoW/
  Interface/
    AddOns/
      ArcaneWatch/
        ArcaneWatch.toc
        ArcaneWatch.lua
        ArcaneWatch_Config.lua
        ArcaneWatch_UI.lua
        ArcaneWatch_Threat.lua
        ArcaneWatch_Timers.lua
```

## Slash Commands

| Command | Action |
|---------|--------|
| `/aw` | Open config panel |
| `/aw threat` | Toggle threat meter |
| `/aw timers` | Toggle spell timers |
| `/aw lock` | Lock/unlock panel dragging |
| `/aw reset` | Reset panel positions to default |

## Saved Variables

- **ArcaneWatchDB** (global) — shared settings: toggles, opacity, sound preferences, threat warning threshold
- **ArcaneWatchCharDB** (per-character) — panel positions, custom spell overrides

## File Structure

```
ArcaneWatch/
├── ArcaneWatch.toc             # Addon manifest, load order, saved variables
├── ArcaneWatch.lua             # Core namespace, class colors, utilities, init
├── ArcaneWatch_Config.lua      # SavedVariables, defaults, slash commands
├── ArcaneWatch_UI.lua          # All frames: threat, timers, config, minimap button
├── ArcaneWatch_Threat.lua      # Threat logic: combat log, API, per-target, warnings
└── ArcaneWatch_Timers.lua      # Timer logic: spellbook scan, cast detection, CD sync
```

## Compatibility

- **Client:** World of Warcraft 1.12 / Turtle WoW
- **Lua:** 5.0 (no `string.match`, no `#` operator — uses `string.find` and `table.getn`)
- **API:** Vanilla-only. Uses `GetNumRaidMembers()`, `GetNumPartyMembers()`, `GetSpellCooldown()`, `UnitThreatSituation()` (Turtle WoW extended)
- **Dependencies:** None — pure standalone Lua, no Ace libraries

## License

MIT
