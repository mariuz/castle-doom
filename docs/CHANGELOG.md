# Changelog

## Unreleased

- DeHackEd frames and code pointers: vanilla's state table (generated
  from the Doom source's info.c into the game) is what `-deh` / `-bex`
  patches and the WADs' `DEHACKED` lumps edit ("Frame N", "Pointer N",
  BEX `[CODEPTR]`, a thing's frame, sound and bits fields), and every
  thing's animations, sounds and attack come from it, so a patch that
  changes a monster's frames, durations, sprite, brightness or attack
  code pointer takes effect. Monsters animate as in vanilla (walking
  frames at their original rate, pain frames, full-bright muzzle flashes,
  including the ones Freedoom's own lump marks).
- A level, a warp, a loaded game and the title no longer pause for the
  music's first seconds: they are rendered over the first frames and the
  song starts a few frames in.
- Music is played on a real OPL3 emulator: Nuked OPL3 (LGPL, a separate
  shared library in `data/lib`, built by `tools/build_nuked_opl3.sh` and
  packaged by CI) is programmed with the WAD's GENMIDI instruments like
  Doom's own sound driver did; the built-in FM model remains the fallback
  (`--fm-synth` forces it) and the browser's synthesizer.
- Things are drawn in a few batched scenes (one per light level and kind,
  one draw call per sprite texture in each) instead of one scene each,
  and each level's wall textures and flats go into one texture atlas, so
  a map chunk is one draw call: a frame at E1M1's first door went from 255
  to 56 draw calls, mainly for the browser's frame rate. Map textures keep
  their real sizes and are no longer mipmapped (`--no-atlas` restores the
  old per-texture shapes).
- Gamepad support (Windows, Linux and the browser): sticks to move and
  look, right trigger to fire, A to use, bumpers for weapons, and the
  D-pad, A and B in the menus. In the browser the game polls the Gamepad
  API itself (Castle Game Engine has no backend for it); the pad appears
  once a button is pressed on it, as browsers require.
- In the browser, a "click to look around" prompt shows when the mouse
  is not captured.
- Unit tests for the WAD, map (every node format), music (MUS and MIDI
  parsing, both synthesizers' envelopes) and DeHackEd code run in CI.
- Maps built with glBSP (GL nodes only, versions 1, 2, 3 and 5, also
  with a separate `.gwa` file) now load.
- The next level's music is synthesized while you play, so a new level
  starts without the short freeze of rendering its first seconds; songs
  no longer needed are freed from memory.

## v0.5.0 (2026-10-09)

- Mouse look is no longer far too fast: it follows Doom's sensitivity
  formula (the 0..9 Options slider, 5 by default), about 4 inches of a
  1000 DPI mouse for a full turn.
- DeHackEd patches: `-deh file.deh` (or `-bex`) and patches inside WADs
  change monster hit points, speed and size, ammo limits and clip sizes,
  starting health and bullets, armor and powerup values, and par times.
  Freedoom's own par times now show on the intermission.
- The weapon is lit through Doom's palette like the rest of the view.
- Spectres and the invisible weapon use Doom's fuzz pattern.
- Downloads for macOS (Intel and Apple Silicon) and a Windows installer
  (MSI).

## v0.4.0 (2026-10-09)

- Doom's own colours: the lighting now looks every pixel up in the real
  palette and colormap of the WAD, so light bands, dark areas and the
  invulnerability greys look like the original.
- Doom's menus: the title pages cycle like the original (title, credits,
  help), F1 shows Read This!, and Esc opens Doom's main menu over the
  paused game with New Game, Options, Load, Save and Quit. Options has End
  Game, Messages on / off, Mouse Sensitivity and Sound Volume (also F4),
  with Doom's thermometers. F2 / F3 open Doom's save and load pages, and
  saves get typed names.
- Settings are remembered: sound and music volume, music on / off, light
  diminishing, mouse look and sensitivity, messages.
- In the browser, Esc (which releases the mouse) pauses the game with the
  menu; a click or Esc resumes and captures the mouse again.
- Saves can be exported and imported (the home page's "Your saves", and
  Options on the desktop), to move them between browsers and computers.
- The browser version downloads Freedoom Phase 2 only when you pick it, so
  the first start is faster.
- Hits and explosions push the player and monsters back; overkill gibs
  zombies, sergeants, imps and SS; crushers squash corpses into gibs;
  melee attacks turn you onto the target; flying monsters keep Doom's
  heights.
- Donut floors, raise-to-shortest-texture floors, stopping and resuming
  crushers and lifts, and slow crushers slowing down on things.
- The sky has Doom's vertical scale and shows through sky floors.
- Textures of levels left behind are freed, so long sessions use less
  memory.

## v0.3.0 (2026-10-08)

- Doom's lighting instead of fog: every wall, floor, ceiling and sprite is
  darkened by distance with the original colormap arithmetic (walls and
  sprites by their projected size, floors and ceilings by distance, in
  Doom's 32 steps), so the light bands of the original are back. Brighter
  sectors fade less than dark ones, and walls keep Doom's fake contrast.
- Firing lights up the room for a moment, like Doom's gun flash.
- Invulnerability turns the view into inverted greys; the light
  amplification visor makes everything full bright, and now actually lasts
  its 120 seconds. Both blink before running out.
- The weapon is lit by the sector you stand in.
- `F` now switches light diminishing off and on (it used to toggle the fog).
- You shoot like in Doom: autoaim finds monsters above and below you (and a
  little to the side), hidden ones behind ledges are not aimed at; bullets
  and pellets are traced through the map with Doom's spreads, the pistol and
  chaingun are accurate on the first shot, the fist and chainsaw reach 64
  units, and rockets, plasma and the BFG are autoaimed too. Every
  shoot-activated line a bullet crosses is triggered.
- The status bar face is centred in its box.

## v0.2.4 (2026-10-08)

- The screen melt between levels works in the browser too: the old screen is
  rendered into a GPU texture and drawn from there, instead of read back to
  the CPU (Castle Game Engine has no WebGL pixel read-back yet).

## v0.2.3 (2026-10-08)

- Monster bullets are traced like Doom: aimed at you, with Doom's random
  spread per pellet, stopped by the first wall or body on the way. Monsters
  standing in the line of fire take the hit (and start fights), misses
  leave puffs on the walls, and ledges block shots. Partial invisibility
  throws their aim off like in Doom. Melee needs a line of sight.

## v0.2.2 (2026-10-08)

- No more freeze at a level start while the music is synthesized (in the
  browser E1M1 used to block for 4 seconds): the first seconds of a song are
  rendered at once and play while the rest is rendered a slice per frame,
  then the full song takes over seamlessly; the intermission track is
  prepared in the background. All songs share one gain with a soft limiter
  (like the original OPL, louder and quieter tracks keep their character).

## v0.2.1 (2026-10-08)

- Much faster in the browser: sprite textures are no longer resized and
  mipmapped on the CPU (hundreds per level); E1M1 went from about 2 to about
  22 FPS on the Pages site. Sprites are also drawn crisp (nearest filtering),
  like Doom.
- The screen melt captures the old screen off-screen and keeps its pace when
  the first frames of a level are slow (desktop; the browser still has no
  melt).
- `Perf:` / `PerfView:` log lines every 10 s with the time per game stage.

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
