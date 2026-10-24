# Changelog

## v0.51.0 (2026-10-24)

- Map editor: `E` opens a properties panel to type values (sector heights, light, special,
  tag; line special, tag and texture offsets; thing angle, type and position; vertex
  position) for the whole selection; `F` flips two-sided lines; Ctrl+C / Ctrl+V copy and
  paste sectors too.

## v0.50.0 (2026-10-24)

- Android: naming a save brings up the phone's on-screen keyboard (tap the name to bring it
  back after closing it); the release also has an Android App Bundle (.aab) for app stores.

## v0.49.0 (2026-10-23)

- Demos in the browser: Options -> Record demo... records the next game in the browser,
  keeps it with your saves and downloads it when the game ends; Play demo... plays a demo
  file from your computer, and the home page's "Your saves" plays or downloads the last one.
- Demo-script cheats (god mode, all weapons, spawned monsters, kill all...) are recorded in
  demos, so such a recording plays back in sync.

## v0.48.0 (2026-10-23)

- Map editor: a path drawn from wall to wall across a sector (N, the points, Enter) cuts it
  in two; Delete removes lines, sectors (neighbours keep the wall) and vertices (two lines
  through one join); number keys toggle line and thing flags, shown in a panel.

## v0.47.0 (2026-10-23)

- Custom game page: Enter on GAME opens an IWAD file, PWADS opens a page to add, reorder
  and remove PWADs, and a RECENT row brings back the last sets of WADs you played. In the
  browser, IWADs and PWADs can be opened from your computer.

## v0.46.0 (2026-10-23)

- Map editor: Space opens a picker with pictures of the wall textures or flats (type to
  filter); Shift+click and box selection (drag on nothing, or Ctrl+drag) select several
  things, lines or sectors to move and change together; Ctrl+C / Ctrl+V copy things; rooms
  drawn with corners on existing walls split them and attach to them.

## v0.45.0 (2026-10-20)

- Map editor: `F7` in a game, Custom game -> Edit map or `--edit MAP` shows the map from
  above; move vertices, lines, sectors and things, draw rooms, change heights, light,
  textures, specials and tags, make doors, add things, undo. `F9` play-tests, `F2` exports a
  PWAD that other Doom ports play (`--export-map MAP FILE` without the editor).
- Levels as 3D models: `F3` / `F4` in the editor (or `--export-gltf` / `--export-x3d MAP
  FILE`) write the walls and floors as glTF or X3D with their textures.
- The "Doom Map" Castle Game Engine component gets PWADs, skill, monsters and extra light
  properties and glTF / X3D export.

- Photo mode on the gamepad (Y) and touch screens (PHOTO); inside it,
  E lets the game run behind the free camera, + / - zoom and [ / ] tilt.

## v0.44.0 (2026-10-20)

- Dynamic lights: lamps, torches and candles glow too, explosions fade,
  up to eight lights at once, and a switch on the title screen's Options.

## v0.43.0 (2026-10-19)

- New Game -> Custom game: pick the game, PWADs, map, skill and a random
  seed on one page of Doom's menu, then Start.

## v0.42.0 (2026-10-19)

- Dynamic lights (Options -> Video): rockets, fireballs, plasma, explosions
  and muzzle flashes light up their surroundings.

## v0.41.0 (2026-10-19)

- Photo mode: `O` pauses the game, hides the HUD and lets the camera fly
  freely (through walls) for screenshots; `O` or Esc returns.

## v0.40.0 (2026-10-19)

- Closed captions (Options -> Sound Volume -> Captions, or F4): a line for each sound you hear,
  like "Door opens, ahead" or "Serpentipede sees you, left".

## v0.39.0 (2026-10-18)

- Gamma correction: `F11` steps through Doom's five brightness levels
  (also Options -> Brightness in the menu); the choice is remembered.

## v0.38.0 (2026-10-18)

- Level statistics: `L` shows kills, items, secrets and the time on
  screen, and each level's best time is kept and shown after it
  ("NEW BEST TIME!").

## v0.37.0 (2026-10-18)

- Demos go on through the following levels (the playback skips through
  the intermissions), and the title screen's Options panel has "Record
  demo..." and "Play demo..." buttons.

## v0.36.0 (2026-10-18)

- Random maps get stairs between rooms at different heights, windows
  you can see and shoot through, and a secret closet or two behind a
  wall that opens (with a prize inside).

## v0.35.0 (2026-10-18)

- Demos: `--record FILE` records a level as you play it and
  `--playdemo FILE` plays it back, the same at any frame rate, saying
  whether it stayed in sync (handy for bug reports).

## v0.34.0 (2026-10-18)

- Random maps have doors, and from the second map on a locked door
  (blue, yellow or red) stands between you and the exit, with its key
  somewhere before it.

## v0.33.0 (2026-10-18)

- Random maps: New Game -> RANDOM MAPS (or `-random [SEED]`, or
  `?random=SEED` in the browser) generates eight levels from a seed,
  growing in size and danger, with their own names; the same seed gives
  the same maps (saves keep it), and `--random-wad FILE` writes them as
  a PWAD that other Doom ports play too.

## v0.32.0 (2026-10-18)

- Smoother frames when many monsters first appear: new sprite shapes
  join their scene once a frame instead of one at a time.

## v0.31.0 (2026-10-18)

- Debug drawing: subsectors, blocking lines, actor boxes and the
  player's shots as wireframes, switched in the engine inspector (F8).

## v0.30.0 (2026-10-18)

- The browser version no longer stops when opened with only a `map=` in
  its address (it starts that map).
- The engine inspector (F8) frees the mouse while it is open, also in
  the browser.

## v0.29.0 (2026-10-18)

- The intermission's episode maps animate, mark the levels you have
  finished and point at the next one, as in Doom (with PWAD art: Freedoom
  leaves them blank), and PWADs' ZDoom intermission scripts work the
  same way.

## v0.28.0 (2026-10-18)

- Touch layout editor: drag each touch button where your thumbs want it
  (Options -> Controls... -> Touch -> Edit...), and an opacity setting.

## v0.27.0 (2026-10-17)

- ZDoom MAPINFO's `include`, and intermission scripts as exit / enter
  pictures (their background is shown).
- Longer crash reports: the last 100 log lines, saved to
  `crash-report.txt` and copied to the clipboard on the desktop; 200
  lines and a "Copy report" button in the browser.

## v0.26.0 (2026-10-17)

- Rebindable mouse buttons and wheel: every action can take a mouse
  button or wheel direction besides its two keys (a third column on the
  Controls page).
- Touch controls for the left hand (the stick on the right) and in four
  sizes, on the Controls page's new Touch mode.

## v0.25.0 (2026-10-17)

- Rebindable weapon keys, next / previous weapon keys and hotkeys (light
  diminishing, mouse look, music, help, automap grid and reveal, map
  skipping, screenshot, quick save / load): the Controls page now has
  Movement, Weapons and Hotkeys pages.

## v0.24.0 (2026-10-17)

- ZDoom's LANGUAGE lumps: MAPINFO's `lookup` / `$NAME` level names,
  story texts, episode names and music now resolve, and a PWAD's
  LANGUAGE strings replace the game's messages and texts.

## v0.23.0 (2026-10-17)

- Per-sector skies: a map can give some outdoor areas a different sky
  (MBF's 271 / 272 on part of the sky).
- Monsters walk slower through Boom mud, like in MBF.

## v0.22.0 (2026-10-17)

- ZDoom's MAPINFO and ZMAPINFO lumps: PWADs made for ZDoom-family ports
  get their level names, music, skies, par times, map order, cluster
  story texts, episodes and endings.
- UMAPINFO's `exitpic` / `enterpic` (intermission pictures) and story
  backdrops that are pictures rather than flats.

## v0.21.0 (2026-10-16)

- Android: an APK for 64-bit ARM phones and tablets on the Releases page,
  with both Freedoom WADs and the touch controls.
- The app icon on Linux, macOS and Android.

## v0.20.0 (2026-10-16)

- Boom's displacement and accelerative scrollers (214-218, 245-249):
  walls, floors and conveyors driven by a moving sector, such as a lift.
- Boom's deep water (242): swimmable pools drawn at another sector's
  heights, with their own look and colour tint under the surface.

## v0.19.0 (2026-10-16)

- Touch controls for phones and tablets in the browser: a stick to move,
  drag to look, and buttons to fire, use, change weapons, open the
  automap and the menu (`--touch` tries them on the desktop).
- Gamepad buttons can be rebound: Options -> Controls... -> Gamepad.
- Walking off a high ledge no longer turns the view a little.
- Boom line-to-line teleports (243, 244 and MBF's 262-269): walk through
  one line and come out of another, keeping your direction relative to it.
- Boom light transfers (213, 261): floors and ceilings lit like another
  sector, and sky transfers (271, 272): a map's own sky texture.

## v0.18.0 (2026-10-12)

- Boom elevators: floor and ceiling moving together (227-238), and
  platforms that jump between floor and ceiling (211, 212).
- MBF's translucent things: a DeHackEd patch's TRANSLUCENT bit draws a
  thing see-through.
- Boom translucency: windows, grates and force fields drawn see-through
  (special 260), with the WAD's own translucency maps.

## v0.17.0 (2026-10-12)

- Boom friction: icy floors that are slow to start and slide, muddy
  floors that slow you down.
- Boom pushers: wind, water currents and point pushers / pullers move
  the player, monsters and barrels.

## v0.16.0 (2026-10-12)

- Boom's numbered line types (142-210, 219-222, 239-241): more floors,
  ceilings, crushers, lights (strobing too), texture changes, silent
  teleports that keep the view's direction, and gun-triggered exits.
- Boom's sector types: damaging floors and secrets combined with any
  light effect.

## v0.15.0 (2026-10-12)

- Boom scrollers: scrolling walls, floors and ceilings, and conveyor
  floors that carry the player and monsters.
- Fixed: walls with Doom's scrolling special (48) moved right instead of
  left.

## v0.14.0 (2026-10-12)

- Boom generalized linedefs: PWADs made for Boom can use their custom
  doors, locked doors, lifts, floors, ceilings, stairs and crushers.
- Big maps run faster: walls are found through a grid instead of
  checking every line (Freedoom Phase 2's MAP12: the monsters cost a
  seventh of the time they did).
- UMAPINFO maps without a level name picture show their name as text on
  the intermission screen.

## v0.13.0 (2026-10-10)

- V-sync and a frame rate cap (35, 60, 120, 144 FPS or none) on the
  desktop, in the title screen's Options and the in-game Video page.

## v0.12.0 (2026-10-10)

- The web version can be installed as an app (a web app manifest and an
  icon with Freedoom's face), with its own window and start menu entry.
- Autotests can run with a fixed time step (`--fixed-step`), so the
  screenshots of moving scenes are compared with references too (35 in
  all).

## v0.11.0 (2026-10-10)

- Crash reports: an unexpected error now shows what happened, where the
  log is and its last lines (a dialog on the desktop, an overlay in the
  browser), ready for a bug report.
- The web version works offline after one visit: a service worker keeps
  the page, the game and its data (and Freedoom Phase 2 once played).

## v0.10.0 (2026-10-10)

- UMAPINFO episodes and boss actions: a PWAD can add episodes to the
  New Game menu (or replace them) and say what the death of the last
  monster of a type does on a map.
- CI compares 28 of the autotests' screenshots with stored references,
  so a rendering change in the menus, the palette effects or a map view
  fails the build.

## v0.9.0 (2026-10-10)

- Video options in the game: Esc -> Options -> Video sets the field of
  view, the UI scale and fullscreen (or, in the browser, the render
  resolution) without leaving the level.

## v0.8.0 (2026-10-10)

- UMAPINFO: PWADs with a UMAPINFO lump get their own level names,
  music, skies, par times, map order and secret exits, story texts after
  a map and endings (a picture, the bunny or the cast call).

## v0.7.0 (2026-10-10)

- Rebindable keys: Options -> Controls... on the title screen sets two
  keys for moving, strafing, turning, running, firing, using and the
  automap; they are saved with the other settings and the help panel
  shows them.
- `CASTLE_DOOM_LOG=Load,Music` writes a second, filtered log
  (`castle-doom-filtered.log`) with only those categories and warnings.
- Boom's `ANIMATED` and `SWITCHES` lumps: PWADs can define their own
  animated textures and flats (with their own speeds) and switch
  textures.

## v0.6.0 (2026-10-10)

- Video options on the title screen's Options panel, remembered between
  sessions: field of view, UI scale, fullscreen (desktop) and, in the
  browser, a render resolution for slow machines (25-100 % of the
  canvas' pixels).

- The inspector (F8) finds the thing you look at: its F9 auto-select
  ("Transform") picks the monster or barrel under the crosshair, and
  things also show their code pointer, tics left, target and reaction
  time. `--profile` turns on Castle Game Engine's profiler, with each
  map load's stages (parse, geometry, things) in the log.

- DeHackEd weapons and projectiles: the player's weapons animate and
  fire from the state table (the shot falls on the frame with
  A_FirePistol and the like), so a patch's "Weapon N" frames and code
  pointers change what a weapon does, and the projectiles' speed, size,
  damage, sounds and frames come from their thing rows ("Speed",
  "Width", "Height", "Missile damage"). The chaingun now fires on both
  of its frames, as in Doom.

- Map textures are mipmapped again, now inside the atlas: far floors and
  walls shimmer less, without seams at the texture repeats (OpenGL 3.1+
  and WebGL 2; `--no-atlas-mipmaps` turns it off).
- A Doom level as a Castle Game Engine component: `TDoomMapTransform`
  ("Doom Map" in the editor) builds a map from a WAD inside any design
  (its geometry, lighting and things), so the CGE editor's 3D view can
  show a Freedoom level; `data/mapcomponent.castle-user-interface` is
  such a design and `--autotest MAPCOMPONENT` screenshots it.
- The play view's 2D layer (status bar, weapon, messages, help, the
  intermission and finale screens, Doom's menu, the melt) and the title
  screen with its Options panel are Castle Game Engine designs
  (`data/play.castle-user-interface`, `data/menu.castle-user-interface`),
  and the game's own controls are registered as editor components, so
  the project opens in the CGE editor with them ("Restart Editor (With
  Custom Components)").
- The engine's inspector (F8) works in every build, not only debug ones,
  and shows a named tree: the map chunks, every thing with its type,
  sprite, frame, state, hit points and position, the sprite batches,
  the views' controls and a `DoomWorldStatus` entry with the map, tic,
  player and kill counts.
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
  their real sizes (`--no-atlas` restores the old per-texture shapes).
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
