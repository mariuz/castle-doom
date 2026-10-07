# Roadmap: what is still missing

Status as of October 2026. Each item says what is missing, why it matters,
where it would go in the code, and a rough size (S = hours, M = a day,
L = several days). Items inside a section are in suggested order.

## Done since the first release

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
| **Donut (special 9)**, **perpetual platforms stop/start**, **raise by shortest lower texture (30/96 are approximated as +64)**, **crusher return speed when blocked**. | Correctness of a few maps. | `ApplySpecial`, `TSectorMover` | S each |
| **Spectres** are drawn like demons; add the fuzz/translucency effect (shader or `AlphaMode = amBlend` with low alpha). | Visual fidelity. | `DoomActors` material | S |
| **3D sight checks**: `SightClear` is 2D (one-sided and closed two-sided lines block); Doom's `P_CheckSight` also uses the heights of openings and the `REJECT` table, so a monster below a high ledge can "see" too much here. | Fewer early wake-ups and shots through ledges. | `SightClear`, `DoomMap` (`REJECT`) | S-M |
| **Blockmap-free 2D queries** scan every linedef (`SightClear`, `TryMove2D`, `TicMissile`, `CheckCrossings`). Add a simple grid (or read `BLOCKMAP`) for very large maps. | Performance on big PWADs. | `DoomMap` | M |
| **Teleport monsters** (specials 125/126) and monsters using teleporters. | Some Doom 2 maps rely on it. | `DoTeleport` for actors | S |
| **Falling damage / knockback**: hitscans and explosions should push things. | Feel. | `DamageActor`, `DamagePlayer` | S |
| **Item respawn / deathmatch starts**: not applicable to single player, but the flags are parsed. | Only if multiplayer ever happens. | - | - |

## 2. Presentation

| Item | Why | Where | Size |
|---|---|---|---|
| **Finales**: the end-of-episode text screens (`E1TEXT`.. / `C1TEXT`..) over a flat, Doom 2's cast call after MAP30 and the bunny scroller after E3M8; now the game goes on to the next map (MAP30 wraps to MAP01). | The games actually end. | new `DoomFinale` view, `GameViewPlay.FinishIntermission` | M |
| **Title/credits cycle** (`TITLEPIC`, `CREDIT`, `HELP1` pages and demos) and the rest of Doom's menu (Options with volume sliders, Read This, Save Game, quit confirmation) in `M_*` graphics; the in-game menu still uses the slot lists from `GameViewPlay`. | Menus look like Doom everywhere. | `DoomMenu`, `GameViewPlay` | M |
| **Sky**: match Doom's vertical stretch exactly and use the per-episode skies (`SKY1..4`, `RSKY1..3` already mapped), sky-floor hack for pits. | Fidelity. | `DoomGeometry.BuildSky` | S |
| **Light diminishing** as a shader (Doom's `COLORMAP`, darker with distance per light level) instead of fog; optional palette-mapped rendering for the real 8-bit look. | The authentic look; shows CGE shader effects (`TEffectNode`). | `DoomGeometry` appearance, a GLSL effect | M |
| **Weapon sprite bobbing and raise/lower animation** when switching weapons; **screen melt** wipe between levels. | Doom feel. | `GameViewPlay` | S |
| **Palette flashes** done through the real `PLAYPAL` palettes (red/yellow/green tints) instead of a translucent rectangle. | Fidelity. | `GameViewPlay` | S |
| **Hanging/floating things** bob (cacodemons hover), **gibs** for excessive damage (`XDEATH` frames). | Fidelity. | `DoomThings` frames, `KillActor` | S |

## 3. Audio

| Item | Why | Where | Size |
|---|---|---|---|
| **Register-accurate OPL3 emulation** (port Nuked OPL3 or DBOPL) instead of the approximate FM model; or at least tune envelope shapes against recordings. | The music is recognisable but not exact. | `DoomMusic` synth core (keep the MUS/MIDI/GENMIDI front end) | L |
| **Background rendering of music** on desktop (thread) and chunked rendering on the web so the level does not pause for the synth; or stream through a custom sound backend. | Removes the few-second pause per track. | `DoomMusic`, `GameViewPlay` | M |
| **Music volume slider**, sound volume, settings persistence (`CastleConfig`). | Usability. | menu | S |
| **Stereo panning** for positional sounds is done by the engine, but Doom's `S_CLIPPING_DIST` falloff curve could be matched more closely. | Minor. | `DoomSound` | S |
| **PC speaker** sounds (`DP*`) are ignored on purpose; no change planned. | - | - | - |

## 4. Content and formats

| Item | Why | Where | Size |
|---|---|---|---|
| **glBSP `GL_` lumps** (`GL_VERT`, `GL_SEGS`, `GL_SSECT`, `GL_NODES` after a `GL_MAPxx` marker) and **UDMF** (`TEXTMAP`) maps. | Remaining community map formats. | `DoomMap` | M (glBSP), L (UDMF) |
| **Boom/MBF specials** (generalized linedefs, scrolling floors, friction, translucency) and **DeHackEd** patches. | Big community map support; large job. | `DoomWorld.ApplySpecial`, `DoomThings` | L |
| **Export / import saves on the web** (download the JSON, upload it back) so a save can move between browsers or to the desktop build. | Saves are tied to one browser profile. | `GameSaveStorage`, a file input via JOB | S |
| **Demo playback** of `DEMO1..3` lumps (needs tic-exact movement; the player is driven by CGE's navigation, so this would need a Doom-style player physics mode). | Attract mode; hard. | large | L |
| **Hexen/Heretic** map formats: out of scope unless someone wants them. | - | - | - |

## 5. Engine and tooling

| Item | Why | Where | Size |
|---|---|---|---|
| **Replace the in-code UI with editor designs** (`.castle-user-interface`) for the HUD and menu so they can be edited in the CGE editor; keep the generated map geometry in code. | Demonstrates the editor workflow. | `data/*.castle-user-interface`, views | M |
| **Unit tests** (`castle-tester`/FPCUnit) for `DoomWad`, `DoomMap` polygon clipping, MUS/MIDI parsing, the synth envelope timings; a CI job that runs `--autotest` on a few maps with a software GL (Xvfb + Mesa) and keeps the screenshots as artifacts. | Catch regressions without a human. | `tests/`, `build.yml` | M |
| **Android / iOS builds** via `castle-engine package --target=android`: touch controls would be needed (`TCastleTouchNavigation`). | CGE's mobile support is a selling point. | `GameViewPlay` input | M |
| **Web**: smaller download (ship only one WAD by default or load WADs on demand with `TCastleDownload`), progress UI during level load, pointer-lock prompt, gamepad. | Faster first play on the Pages site. | web build, `GameViewPlay` | M |
| **Performance**: build a static-sector blockmap; merge per-sector dynamic chunks that never actually move; profile `TicActors` on 300+ thing maps. | Headroom on big maps. | `DoomGeometry`, `DoomWorld` | S-M |
| **Memory**: free decoded textures of unloaded maps; the `TDoomGraphics` caches grow with every map visited in one session. | Long sessions. | `DoomGraphics` | S |

## Suggested next three

1. Finales (M): end-of-episode text screens and the Doom 2 cast call, now
   that every boss level can be finished.
2. Teleporting monsters (specials 125/126, monsters walking over
   teleporters) (S): several Doom 2 maps send monsters through teleporters.
3. Weapon raise / lower when switching and the screen melt between levels
   (S): two small things that make it feel like Doom.
