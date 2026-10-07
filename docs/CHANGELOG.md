# Changelog

## v0.2.0 (2026-10-08)

The first release that plays all of Freedoom Phase 1 and Phase 2 from the
title screen to the end credits.

### Menus, saves and endings

- Doom's own menu drawn from the WAD's `M_*` graphics: New Game, episode and
  skill select (all five skills), Load Game, Options (WADs, map, skill), a
  quit question with Freedoom's quit messages. `-skill 1..5` on the command
  line.
- Save and load anywhere: F2 / F3 slot menus, F6 / F9 quick save / load,
  "Continue (quick save)", `-loadgame N`. Doors, lifts, switches, corpses,
  monsters mid-fight, inventory and the automap are all saved. In the
  browser saves are kept in `localStorage` and survive reloads.
- Finales: Freedoom's story texts, the end pictures, the bunny scroller after
  E3M8 and the Doom 2 cast call after MAP30.
- Freedoom's own wording from the WAD's `DEHACKED` strings: pickup and door
  messages, level titles (also on the automap), the Nightmare question.

### Monsters and gameplay

- Skill levels like vanilla: thing flags, double ammo and half damage on the
  easiest skill, Nightmare's fast monsters, faster projectiles and respawning.
- Icon of Sin (MAP30): the boss brain, the cube spawner and the monsters it
  spawns.
- Lost souls charge, Pain Elementals spit lost souls, Arch-viles raise the
  dead and burn you; monsters fight each other when hurt by another monster;
  boss deaths open the way on E1M8, E2M8, E3M8, E4M6, E4M8, MAP07 and MAP32.
- Monsters wake like in Doom: sound spreads through open doors and stops at
  closed ones, ambush monsters wait until they see you, and sight is checked
  in 3D with the map's REJECT table (no more seeing over ledges).
- Monsters use teleporters and monster-only teleport lines (monster closets
  and traps work).
- Real projectiles for the rocket launcher, plasma gun and BFG.

### Presentation

- Doom's text font for messages, the real intermission screen with counting
  stats and par times, the automap (Tab) in Doom's colours.
- Weapons lowered and raised when switching, the screen melt between levels
  (desktop), spectre fuzz and the fuzzy weapon with partial invisibility.
- Damage, pickup, berserk and radiation-suit screen tints taken from the
  WAD's `PLAYPAL` palettes.

### Content and formats

- Your own IWADs and PWADs: menu file dialogs or `-iwad` / `-file` / `-warp`,
  PWAD lumps override the IWAD's.
- ZDoom extended nodes (`XNOD`, `ZNOD`, `XGLN`, `ZGLN`, `XGL2`, `ZGL2`,
  `XGL3`, `ZGL3`), so maps built with ZDBSP load.
- Music: MUS and MIDI lumps played through an FM synthesizer driven by the
  WAD's GENMIDI instrument bank.

### Under the hood

- Architecture guide (`docs/ARCHITECTURE.md`), roadmap (`docs/ROADMAP.md`)
  and agent notes (`CLAUDE.md`); an autotest harness drives every feature
  from the command line (`--autotest`, `--demo`, `--menukeys`).
- Web build: faster texture loading (TGA), a loading screen, CI job
  timeouts.

## v0.1.0 (2026-10-07)

First playable version: Freedoom maps rendered with Castle Game Engine,
doors, lifts and specials, monsters, weapons, pickups, the status bar, sound
effects, and builds for Windows, Linux and the web.
