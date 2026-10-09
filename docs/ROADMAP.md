# Roadmap: what is still missing

Status as of October 2026. Each item says what is missing, why it matters,
where it would go in the code, and a rough size (S = hours, M = a day,
L = several days). Items inside a section are in suggested order.

## Done since the first release

- Smaller first download on the web: the web workflow takes
  `freedoom2.wad` out of the data zip and publishes it as
  `play/freedoom2.zip` (10 MB instead of 28 MB uncompressed); choosing
  Freedoom Phase 2 (Options, a Phase 2 save, a MAPxx command line)
  downloads it with `TCastleDownload` (progress shown on the menu),
  mounts it with `TCastleZip.RegisterUrlProtocol` and carries on with
  what was asked. Saves keep naming `castle-data:/wads/freedoom2.wad`.
  The same path runs on the desktop with `--wad-base-url URL` (an
  autotest serves the zip locally). The level loading text was already
  there ("LOADING MAPxx..." for a frame before the synchronous build).
- Autotests in CI: `tools/run_autotests.py` runs 12 demo scripts (title
  menu, save round trip with gibs, knockback, door crushing a corpse,
  melee turn, Arch-vile raise, texture memory, MAP05 donut, MAP04 crusher
  stasis, pointer-lock pause, Icon of Sin death, settings persistence),
  each with its own `XDG_CONFIG_HOME`, and checks the log (no exception,
  the expected lines) and some saves' JSON. The `autotest` job in
  `build.yml` builds on Ubuntu with apt's FPC and the CGE snapshot, runs
  them under `xvfb-run` (Mesa), writes a summary table and keeps logs and
  screenshots as an artifact. About 1.5 minutes of tests.
- Esc and pointer lock like CGE's FPS examples (castle-engine.io/web
  "Pointer lock"): Esc pauses with a Doom-font PAUSED screen (click / Enter
  resume, Esc again goes to the title menu). In the browser Esc belongs to
  the browser and only releases the mouse, so the pointer lock's
  user-cancelled listener (`Container.PointerLock.AddUserCancelledListener`)
  opens the same pause; resuming with a click re-enables mouse look inside
  that user gesture, and a left click in the game while mouse look is
  wanted but lost takes the mouse back instead of firing. Before, Esc on
  the web left the game running with a free cursor and clicks never
  locked the mouse again.
- Memory: decoded wall textures and flats belong to the level that last
  asked for them (`TDoomGraphics.BeginLevel` / `ReleaseUnused`, a cache
  hit marks the whole animation group); once a new level's geometry is
  built, the rest are freed, and animation groups refill dropped frames
  when used again. E1M1 -> E1M2 -> E1M3 -> E1M1 frees 3-4.6 MB of
  decoded images at each change and ends with the same 120 textures and
  48 flats E1M1 started with (`Graphics: Freed ...` log line). Sprites
  and HUD patches stay cached (shared by all maps).
- Saves move between browsers and computers: a "Your saves" section on
  the home page lists the saves in this site's localStorage (same origin
  as `/play/`), exports them with the settings as one JSON bundle and
  imports one back (asking before it replaces slots); plain page
  JavaScript, no WebAssembly code. The desktop build reads and writes the
  same bundle (Options: *Export saves...* / *Import saves...*, or
  `--export-saves FILE` / `--import-saves FILE`; `GameSaveBundle`). Only
  the known file names are accepted.
- Settings that stay: sound effect and music volume on Doom's 0..15
  scales (F4 in the game opens a Doom-style sound volume menu with
  thermometer bars; the title Options panel has the same two rows), music
  on / off (`J`), light diminishing (`F`) and mouse look (`M`) are
  remembered in `settings.json` next to the saves (`GameSettings`, through
  `GameSaveStorage`: a castle-config: file on the desktop, localStorage on
  the web). The defaults keep the old mix (effects 15, music 8).
- The sky like Doom's: texture row 100 at eye height and one row per
  1/160 of slope (r_plane's `skytexturemid` with Doom's 160-pixel focal
  length; the sky used to be twice as tall), repeated downwards the way
  Doom wraps it below the horizon and row 0 stretched upwards for mouse
  look. Sky floors (`F_SKY1` as a floor flat, E2/E3 and a few Doom II
  maps) are not drawn, so the sky shows through like r_plane draws any
  sky plane; they still collide (the invisible collision scene). Demo
  command `LOOK:deg` pitches the view.
- The last vanilla sector specials: the donut (9, `EV_DoDonut`: the pillar
  lowers to the outer floor, the ring rises to it and takes its texture;
  MAP05), raise to the shortest lower texture (30 / 96, "-" ignored like
  Boom), perpetual platforms and crushers stopped by 54 / 89 / 57 / 74 go
  into stasis and resume where they were on the next start (53 / 87 and
  the crusher starts; `P_ActivateInStasis`), slow crushers drop to 1/8
  speed while something is under them until they reach the bottom
  (`T_MoveCeiling`; fast ones do not), the silent crusher (141) does not
  grind and clunks at both ends, and 57 (W1 crusher stop) exists. The
  demo command `LINE:n[:special]` activates any line for tests.
- Knockback and crushed corpses like Doom: every hit with an inflictor
  pushes by damage * 12.5 / mass (`P_DamageMobj`, info.c masses; a small
  killing hit from 64+ units below sometimes throws the target forward);
  monsters, corpses and barrels slide with `P_XYMovement`'s friction (none
  in the air, so a shot cacodemon drifts to the wall) and corpses slide off
  ledges; the player is pushed too (rocket blasts, demon bites; god mode
  and invulnerability still push), through the view's collision-checked
  move. The player's chainsaw and telefrags do not push. A ceiling coming
  down turns corpses (a quarter of their height) into `POL5` gibs that do
  not block doors, removes dropped items, and crushers hurt 10 every 4 tics
  (they hurt every tic before). Barrels block doors and get crushed; the
  Arch-vile does not raise crushed gibs (no "ghosts").
- Melee turns the player like Doom: a punch that finds a target faces it
  (`A_Punch`), the chainsaw pulls the view towards it 4.5 degrees a tic or
  jumps to 4.29 degrees short of it (`A_Saw`, the familiar jitter); the
  world asks the view to turn through `PlayerTurn`. During invulnerability
  the weapon and its flash are drawn in the inverted colormap too
  (inverted copies of the sprites; partial invisibility's fuzz still wins,
  as in `R_DrawPSprite`).
- Gibs and flying like Doom: a zombieman, shotgun guy, chaingunner, imp or
  SS killed with its health below minus its spawn health bursts
  (`XDEATH` frames, `DSSLOP`, `Gib:` log lines). Flyers follow
  `P_ZMovement`: they float 4 units a tic towards the target's height only
  when it is steeper than 1:3 away (far cacodemons keep their altitude),
  `P_Move`'s `floatok` lifts them over steps and under low ceilings in
  their way (`MF_INFLOAT`), they keep their height while in pain instead of
  dropping to the floor, and dead cacodemons and pain elementals fall under
  gravity (lost souls stay where they die). Hanging things do not bob in
  vanilla, so nothing to do there.
- The player shoots like Doom: `P_AimLineAttack` autoaim (straight ahead,
  then 5.625 degrees to each side, the slope window narrowed by the
  openings on the way), bullets and pellets traced in Doom units through
  `TraceLineAttack` with Doom's spreads (pistol and chaingun accurate on the
  first shot), melee over 64 units, missiles autoaimed too, and every
  gun-activated line the shot crosses is triggered. No more ray casts
  against the camera-facing sprite quads.
- The status bar face sits where Doom draws it (patch offsets applied).
- Doom's light diminishing as a shader instead of fog (`DoomLighting`):
  r_main.c's colormap arithmetic per pixel (walls and sprites by projected
  scale, floors and ceilings by distance, fake contrast, 32 integer
  colormap steps, so the light bands of the original show), the gun
  flash's extra light, the inverted colormap of invulnerability and the
  light amplification visor (which now lasts its 120 s). The weapon sprite
  is lit by the player's sector. `F` turns diminishing off (flat sector
  light).
- Monster bullets are traced like Doom (`P_AimLineAttack` / `P_LineAttack`):
  the monster faces its target, aims at its middle when in sight, and every
  pellet gets Doom's +-22.4 degree spread (+-45 degrees more against an
  invisible player); `TraceLineAttack` finds the first wall (one-sided, or
  above / below an opening) or body (monster, barrel, player) on the line,
  in Doom units. Monsters in the line of fire take the shot and fight back,
  misses leave puffs on the walls, and ledges block shots. Melee attacks also
  need a line of sight.
- The screen melt renders the old screen into a GPU texture
  (`TDrawableImage.RenderToImageBegin`, `Container.RenderControl`) and draws
  that, with no pixel read-back, so it works in the browser too (CGE has no
  WebGL `glReadPixels` yet); it skips the frame that started it, then follows
  real time.
- Music without the stall: the first 8 s of a song are rendered at once and
  played, the rest a slice per frame (12 ms budget, `TSongRenderer`), and the
  finished song takes over at the same position; the intermission track is
  prefetched. One fixed gain with a soft limiter for every song. No more seconds-long freeze at every level start in the
  browser (E1M1 used to block for 4 s there).
- Web performance: sprites are GUI textures (no power-of-two resize, no
  mipmaps on the CPU); the browser build went from about 2 to about 22 FPS
  on E1M1 with the world at full tic rate. `Perf:` / `PerfView:` log lines
  every 10 s show where the time goes.
- Palette flashes from `PLAYPAL` (`ST_doPaletteStuff`): `damagecount` /
  `bonuscount` like Doom, berserk red fading out, the radiation suit green.
  Each palette is palette 0 blended towards one colour, so
  `TDoomWad.PaletteTint` solves that colour and amount from the black and
  white entries and the view draws one full-screen rectangle with it.
- 3D sight checks (`CheckSight`, Doom's `P_CheckSight`): the `REJECT` table
  first, then the line from the viewer's eye (3/4 of its height) to the
  target with the vertical window narrowed at every opening crossed (higher
  floor, lower ceiling); monsters no longer see or shoot over ledges and
  out of pits. Used for waking (`MonsterLook`, ambush), attack decisions,
  the Arch-vile, the Icon of Sin shooter and the player's autoaim. On E1M1
  the two zombies in the pit below the start room no longer wake by sight.
- Fuzz: spectres are drawn as a dark translucent silhouette whose opacity
  changes every tic (`TDoomActor.Fuzz`: `AlphaMode = amBlend`, black
  unlit material, random `Transparency`), and with partial invisibility the
  player's weapon is drawn the same way, blinking back in the last seconds.
- BEX strings everywhere: pickup messages (`GOT*`), locked door / switch
  messages (`PD_*K` / `PD_*O`), the level title on entering a map and at the
  bottom of the automap (`HUSTR_E1M1`, `HUSTR_1`), the automap grid toggle
  (`AMSTR_GRIDON/OFF`), the Nightmare question (`NIGHTMARE`) and a quit
  question with a random quit message (`QUITMSG*` + `DOSY`, new in the
  title menu) come from the WAD's `DEHACKED`, so Freedoom's own wording is
  used; vanilla texts remain the fallback. The weapon is hidden on the
  automap. CI jobs have timeouts (a hung runner sat 2.5 hours once).
- Weapon raise / lower and the screen melt: switching weapons (keys,
  running out of ammo, a new weapon picked up, berserk) lowers the old one
  6 pixels per tic, swaps it out of view and raises the new one (`A_Lower` /
  `A_Raise`); no firing meanwhile; every level starts with the weapon coming
  up. Level → intermission, intermission → next level and the finales melt
  the old screen down in 160 columns like `f_wipe.c` (`DoomWipe`).
- Monsters use teleporters and walk-over lines like in Doom
  (`P_CrossSpecialLine` for non-players): crossing a 39 / 97 teleporter or a
  monster-only 125 / 126 from the front teleports them with fog at both
  ends (refused while something stands on the destination, except on MAP30
  where they telefrag), and they can trigger the walk-over door raise (4)
  and lifts (10, 88). Monster closets and teleport traps (MAP07's arena,
  many Freedoom maps) now work.
- Finales: the story text typed over a flat (3 tics per character, a key
  shows it all), then Doom 1's end picture (`CREDIT`, `VICTORY2`, `ENDPIC`)
  or the E3M8 bunny scroller with THE END, Doom 2's texts after MAP06, 11,
  20 and the MAP15 / MAP31 secret exits (the game then goes on), and the
  MAP30 cast call (each member walks, attacks now and then, dies on a key
  press). Texts, background flats and cast names come from the WAD's
  `DEHACKED` lump (BEX `[STRINGS]`, `DoomDehacked`), so Freedoom's own
  story is shown; music `D_VICTOR` / `D_READ_M` / `D_BUNNY` / `D_EVIL`.
- Sound propagation and ambush monsters: a player's shot floods from the
  player's sector through open two-sided lines (closed doors stop it,
  `ML_SOUNDBLOCK` lines let it through once) and marks the sectors it
  reaches (`NoiseAlert`, saved with the game). Idle monsters look every 10
  tics (`MonsterLook`, Doom's `A_Look`): a heard sector wakes them, except
  `MTF_AMBUSH` monsters, which also need a line of sight; otherwise they
  must see the player in their front half circle (or within melee range).
  The 3000-unit sight limit is gone. The log says why each one woke
  (`Wake:`) and how far each new noise went (`Noise:`).
- Persistent web saves: in the browser the save JSON goes to the page's
  `localStorage` (`GameSaveStorage`, through the JOB JavaScript bridge that
  CGE's web target already uses), keyed `castle-doom:castle-config:/saveN.json`,
  so saves on the Pages site survive reloads; the desktop still writes
  `castle-config:` files.
- Icon of Sin (MAP30): the boss shooter (89) wakes on sight or any shot,
  says `DSBOSSIT`, and after 181 tics spits a cube every 150 tics (every
  other one on the two easy skills) at the spawn spots (87) in turn; cubes
  fly through walls and become fire plus a random monster with Doom's odds,
  which telefrags anything in the spot (the player too). The brain (88)
  screams on pain, does not count as a kill, and its death sets off a row
  of explosions and ends the level 120 tics later. Cube flights, the target
  index and the death countdown are saved.
- Doom menu and skill levels: the title screen is Doom's own menu drawn from
  the WAD's `M_*` graphics over a dimmed `TITLEPIC` (`DoomMenu`): New Game,
  episode select (Doom 1 WADs), skill select with the Nightmare confirmation,
  Load Game with the six save slots, skull cursor, menu sounds, keyboard and
  mouse. The old engine-button screen is now the Options page (WADs, map,
  skill). Skills follow vanilla: thing flags (`MTF_EASY` / `NORMAL` / `HARD`),
  double ammo on 1 and 5, half damage on 1, and Nightmare's fast projectiles,
  fast demons, no reaction delay, attacks back to back and monster respawn
  (12 s, teleport fog). `-skill 1..5`; the skill is saved with the game.
- Save / load: F2 / F3 slot menus (6 slots, Doom font), F6 / F9 quick save /
  load, "Continue (quick save)" on the title screen, `-loadgame N`. The whole
  level state is JSON (`TDoomWorld.SaveState` / `LoadState` in
  `doomworld_save.inc`): player, sectors, lines, changed sidedefs, movers,
  switch timers, light timers, every actor with animation and references,
  camera and level time; saves record their WADs and refuse other WAD sets.
  Files are `castle-config:/save1..6.json` and `quicksave.json` (about
  120 KB for a map).
- Lost soul, Pain Elemental and Arch-vile behave like Doom: lost souls charge
  at 20 units/tic and slam whatever they hit (`StartSkullCharge`,
  `TicCharge`); Pain Elementals spit souls (refused above 20, killed at once
  when spawned into a blocked spot) and release three on death
  (`PainShootSkull`); Arch-viles raise corpses they touch with the heal
  frames and reversed death frames (`VileTryRaise`), and attack with a fire
  that tracks the target, then 20 damage + 70 splash + an upward throw if
  they still see it (`VileStartAttack`, `FollowVileFire`, `VileAttack`).
- ZDoom extended nodes: `XNOD`/`ZNOD` in NODES and the GL variants
  `XGLN`/`ZGLN`/`XGL2`/`ZGL2`/`XGL3`/`ZGL3` (in NODES or, as ZDBSP writes
  them, in SSECTORS), zlib via FPC's `zstream` (works on the web too); node
  children normalized to a format-independent flag; sidedef indices above
  32767 accepted. `tools/make_znodes.py` converts E1M1 to all six formats
  for testing; every format yields the same 682 polygons / 6,712,683 area.
- Doom's text font (`DoomFont`: STCFN patches composed into an image) for the
  player messages and the loading screen; the real intermission screen
  (`DoomIntermission`): WIMAP/INTERPIC background, WILV/CWILV level names,
  FINISHED, kills/items/secrets/time/par with Doom's count-up and sounds, the
  ENTERING screen, skip with use/fire.
- Monster infighting: monsters keep a `Target` (nil = player); damage from
  another monster retargets them, monster missiles hit other monsters (passing
  through the shooter's own species like Doom), zombie hitscans hit whoever
  stands in the line of fire, splash damage is attributed to the shooter,
  cyberdemons and spiders ignore splash.
- Boss-death triggers (`BossDeath`): E1M8 barons, E4M8 spiders and MAP07
  mancubi lower tag 666 floors; MAP07 arachnotrons raise tag 667 by the
  shortest lower texture; E4M6 cyberdemons blaze-open tag 666 doors; Keen
  opens tag 666 doors; E2M8 / E3M8 end the level.
- External WADs: `-iwad FILE`, `-file PWAD...`, `-warp MAP` on the command
  line, "Open IWAD..." / "Add PWAD..." / "Last WADs" in the menu (native file
  dialog, paths remembered in the user config). `TDoomWad` stacks files; lumps
  are looked up from the last file backwards so PWAD maps, textures, sprites
  (S_START/SS_START ranges), flats, sounds and music override the IWAD's.
- Automap (Tab): `DoomAutomap` draws seen linedefs with `DrawPrimitive2D` in
  Doom's colours, player arrow, zoom (+/-, wheel), 128-unit grid (G), reveal
  all (I). Lines are revealed per visited sector and its neighbours.
- Player projectiles: rockets, plasma balls and the BFG ball (40-tic charge,
  100d8 direct hit, 40-tracer spray over 90°) are real `TDoomActor` missiles
  (`SpawnPlayerMissile`, `BfgSpray`); rockets keep their splash damage.

## 1. Gameplay fidelity (vanilla behaviour not yet reproduced)

| Item | Why | Where | Size |
|---|---|---|---|
| **Column fuzz shader**: Doom's fuzz also shifts columns up and down by a pixel (`fuzzoffset`); a `TEffectNode` fragment shader could add that wobble to spectres and the invisible weapon. | Closer look. | `DoomActors` appearance | S |
| **Blockmap-free 2D queries** scan every linedef (`SightClear`, `TryMove2D`, `TicMissile`, `CheckCrossings`). Add a simple grid (or read `BLOCKMAP`) for very large maps. | Performance on big PWADs. | `DoomMap` | M |
| **Item respawn / deathmatch starts**: not applicable to single player, but the flags are parsed. | Only if multiplayer ever happens. | - | - |

## 2. Presentation

| Item | Why | Where | Size |
|---|---|---|---|
| **`-deh` / `.bex` files** and the other DeHackEd sections (things, frames, weapons, ammo, code pointers) for PWADs that change monsters. | Many classic PWADs ship a `.deh`. | `DoomDehacked`, `DoomThings` | M-L |
| **Title/credits cycle** (`TITLEPIC`, `CREDIT`, `HELP1` pages and demos) and the rest of Doom's menu (Options with volume sliders, Read This, Save Game, quit confirmation) in `M_*` graphics; the in-game menu still uses the slot lists from `GameViewPlay`. | Menus look like Doom everywhere. | `DoomMenu`, `GameViewPlay` | M |
| **Browser frame rate**: in the Claude browser pane the web build ran at 4-22 FPS with the game logic and music slices taking only ~25 ms per frame; profile rendering in a normal browser (Chrome Performance panel, CGE `FrameProfiler`) and batch the sprite scenes if draw calls dominate. | Playable speed on the Pages site. | web build, `DoomActors` | M |
| **Palette-mapped rendering** for the real 8-bit look: quantize each texel to the palette and look it up in the real `COLORMAP` rows (a 32x32x32 RGB-to-index texture and a 256x34 colormap texture in the `DoomLighting` effect), instead of multiplying by (32 - level) / 32. | Exact Doom colours, banding of the palette. | `DoomLighting` | M |

## 3. Audio

| Item | Why | Where | Size |
|---|---|---|---|
| **Register-accurate OPL3 emulation** (port Nuked OPL3 or DBOPL) instead of the approximate FM model; or at least tune envelope shapes against recordings. | The music is recognisable but not exact. | `DoomMusic` synth core (keep the MUS/MIDI/GENMIDI front end) | L |
| **Background rendering of music** on desktop (thread) and chunked rendering on the web so the level does not pause for the synth; or stream through a custom sound backend. | Removes the few-second pause per track. | `DoomMusic`, `GameViewPlay` | M |
| **Stereo panning** for positional sounds is done by the engine, but Doom's `S_CLIPPING_DIST` falloff curve could be matched more closely. | Minor. | `DoomSound` | S |
| **PC speaker** sounds (`DP*`) are ignored on purpose; no change planned. | - | - | - |

## 4. Content and formats

| Item | Why | Where | Size |
|---|---|---|---|
| **glBSP `GL_` lumps** (`GL_VERT`, `GL_SEGS`, `GL_SSECT`, `GL_NODES` after a `GL_MAPxx` marker) and **UDMF** (`TEXTMAP`) maps. | Remaining community map formats. | `DoomMap` | M (glBSP), L (UDMF) |
| **Boom/MBF specials** (generalized linedefs, scrolling floors, friction, translucency) and **DeHackEd** patches. | Big community map support; large job. | `DoomWorld.ApplySpecial`, `DoomThings` | L |
| **Demo playback** of `DEMO1..3` lumps (needs tic-exact movement; the player is driven by CGE's navigation, so this would need a Doom-style player physics mode). | Attract mode; hard. | large | L |
| **Hexen/Heretic** map formats: out of scope unless someone wants them. | - | - | - |

## 5. Engine and tooling

| Item | Why | Where | Size |
|---|---|---|---|
| **Replace the in-code UI with editor designs** (`.castle-user-interface`) for the HUD and menu so they can be edited in the CGE editor; keep the generated map geometry in code. | Demonstrates the editor workflow. | `data/*.castle-user-interface`, views | M |
| **Unit tests** (`castle-tester`/FPCUnit) for `DoomWad`, `DoomMap` polygon clipping, MUS/MIDI parsing, the synth envelope timings (the `--autotest` CI job covers gameplay; these would cover the parsers). | Catch regressions without a human. | `tests/`, `build.yml` | M |
| **Android / iOS builds** via `castle-engine package --target=android`: touch controls would be needed (`TCastleTouchNavigation`). | CGE's mobile support is a selling point. | `GameViewPlay` input | M |
| **Web**: pointer-lock prompt, gamepad, a progress bar during the first data download. | Friendlier first play. | web build | S |
| **Performance**: build a static-sector blockmap; merge per-sector dynamic chunks that never actually move; profile `TicActors` on 300+ thing maps. | Headroom on big maps. | `DoomGeometry`, `DoomWorld` | S-M |

## Suggested next three

1. Browser frame rate (M): profile rendering in a normal browser and batch
   the sprite scenes if draw calls dominate (each sprite now has its own
   light effect, which CGE's dynamic batching does not merge).
2. Title / credits cycle and the rest of Doom's menu (M): `TITLEPIC`,
   `CREDIT` and `HELP` pages cycling on the title screen, Read This, and
   the in-game save / load menus drawn by `DoomMenu` in `M_*` graphics.
3. Column fuzz shader (S): Doom's `fuzzoffset` wobble for spectres and
   the invisible weapon, the last step of the fuzz work.
