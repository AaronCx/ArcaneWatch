# ArcaneWatch

A World of Warcraft (Vanilla / Turtle WoW) addon that combines a real-time threat meter with a spell timer tracker for group and raid content.

**Interface:** 11200 (Vanilla WoW) | **Version:** 1.1.1

## Features

### Threat Meter
- **Dual-mode detection** — uses the Turtle WoW extended API (`UnitDetailedThreatSituation`) when available, falls back to combat log parsing for vanilla clients
- Class-colored threat bars for up to 5 group members
- Player row highlighted with glow overlay
- Threat normalized to highest value (tank = 100%)
- Combat log fallback tracks melee hits, spell damage, DoTs, and healing (at 50% threat)
- Auto-shows on combat start, fades out 3 seconds after combat ends
- Polls at 0.2-second intervals

### Spell Timers
- Track cooldowns and DoT durations for configured spells
- Two states per spell: Ready (green, pulsing icon) and Active (draining bar with countdown)
- Color shifts from blue (>50%) to yellow (50%) to red (<50%)
- 21 spells defined (Warlock-focused defaults), 8 tracked by default
- Spell icons loaded from the spellbook
- Updates at 0.05-second intervals

### UI
- Draggable, lockable panels with position persistence
- Configurable opacity (default 0.85)
- Config panel with toggle buttons for each module
- WoW tooltip-style backdrop
- Positions saved per-character via SavedVariables

## Slash Commands

| Command | Action |
|---------|--------|
| `/aw` | Toggle config panel |
| `/aw threat` | Toggle threat meter |
| `/aw timers` | Toggle spell timers |
| `/aw lock` | Lock/unlock panel dragging |
| `/aw reset` | Reset panel positions |

## Installation

Copy the `ArcaneWatch/` folder into your WoW AddOns directory:

```
World of Warcraft/_retail_/Interface/AddOns/ArcaneWatch/
```

Or for Turtle WoW:

```
Turtle-WoW/Interface/AddOns/ArcaneWatch/
```

## File Structure

```
ArcaneWatch/
├── ArcaneWatch.toc             # Addon manifest
├── ArcaneWatch.lua             # Core namespace, utilities, class colors
├── ArcaneWatch_Config.lua      # SavedVariables, slash commands, defaults
├── ArcaneWatch_Threat.lua      # Threat tracking (API + combat log)
├── ArcaneWatch_Timers.lua      # Spell cooldown/DoT tracker
└── ArcaneWatch_UI.lua          # Panel layout, dragging, config UI
```

## Default Tracked Spells

Corruption, Curse of Agony, Unstable Affliction, Siphon Life, Shadow Bolt, Death Coil, Shadowburn, Fear

Additional spells (Immolate, Conflagrate, Drain Life, etc.) are defined and can be enabled in the config.

## License

MIT
