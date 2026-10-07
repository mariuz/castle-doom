# Roadmap: what is still missing

Status as of October 2026. Each item says what is missing, why it matters,
where it would go in the code, and a rough size (S = hours, M = a day,
L = several days). Items inside a section are in suggested order.

## 1. Gameplay fidelity (vanilla behaviour not yet reproduced)

| Item | Why | Where | Size |
|---|---|---|---|
| **Player projectiles**: rocket launcher, plasma gun and BFG are instant hits with splash damage. Make them real `TDoomActor` missiles like the monsters' (`ekRocket` already exists), with the BFG's tracer spray. | Rockets you can dodge and see fly are a big part of the feel. | `DoomWorld.FireWeapon`, reuse `SpawnMissile`/`TicMissile` with the player as source | M |
| **Monster infighting**: monsters hit by another monster's projectile or hitscan should retarget it. | Classic Doom tactic. | `DamageActor` needs an attacker parameter; `TicMonster` needs a target other than the player | M |
| **Boss triggers**: E1M8 (barons dead opens tag 666 floor), E2M8/E3M8 level end, MAP07 (mancubi 666, arachnotrons 667), Keen (MAP32 doors). | Those levels cannot be finished properly without them. | `KillActor` counts per type; a per-map check in `TicActors` | S |
| **Pain Elemental** should spawn lost souls instead of firing fireballs; lost souls should charge. | Doom 2 levels play differently without it. | `MonsterAttack`, a charge state in `TicMonster` | M |
| **Arch-vile**: resurrection of corpses and the fire attack with line-of-sight jump. | Doom 2 signature monster. | `TicMonster` special case, corpses are still actors (`asDead`) | M |
| **Donut (special 9)**, **perpetual platforms stop/start**, **raise by shortest lower texture (30/96 are approximated as +64)**, **crusher return speed when blocked**. | Correctness of a few maps. | `ApplySpecial`, `TSectorMover` | S each |
| **Spectres** are drawn like demons; add the fuzz/translucency effect (shader or `AlphaMode = amBlend` with low alpha). | Visual fidelity. | `DoomActors` material | S |
| **Difficulty selection** (currently "Hurt me plenty" thing flags only) and the **`MTF_AMBUSH`** (deaf) flag. | Replayability. | `SpawnThings`, menu | S |
| **Sector sound propagation**: monsters currently wake on a 2D line-of-sight or any shot within 1200 units; Doom floods sound through sector neighbours with `ML_SOUNDBLOCK`. | Monsters wake more faithfully. | `NoiseAlert` | M |
| **Blockmap-free 2D queries** scan every linedef (`SightClear`, `TryMove2D`, `TicMissile`, `CheckCrossings`). Add a simple grid (or read `BLOCKMAP`) for very large maps. | Performance on big PWADs. | `DoomMap` | M |
| **Teleport monsters** (specials 125/126) and monsters using teleporters. | Some Doom 2 maps rely on it. | `DoTeleport` for actors | S |
| **Falling damage / knockback**: hitscans and explosions should push things. | Feel. | `DamageActor`, `DamagePlayer` | S |
| **Item respawn / deathmatch starts**: not applicable to single player, but the flags are parsed. | Only if multiplayer ever happens. | - | - |

## 2. Presentation

| Item | Why | Where | Size |
|---|---|---|---|
| **Automap** (Tab): draw linedefs from `DoomMap` in a 2D `TCastleViewport` or with `DrawPrimitive2D`, colour by one/two-sided and secret, player arrow, map markers. | Expected Doom feature, nice showcase of CGE 2D drawing. | new `DoomAutomap` unit, `GameViewPlay` | M |
| **Doom text font** (`STCFN*` patches) for messages and the intermission instead of the engine's default font; CGE `TCastleFont` from an image, or compose labels from patches like the status bar. | Looks right. | `DoomHud` | S |
| **Intermission screen** with the `WIMAP0`/`INTERPIC` background and animated level-stats count-up and sound; **title/credits cycle**, **episode/skill menu** using `M_*` graphics. | Polish, menus look like Doom. | `GameViewMenu`, `GameViewPlay` | M |
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
| **Load external WADs**: command line `-iwad`/`-file`, PWAD merging (later lumps override earlier ones), a file picker in the menu (`castle-config:` for the last path). | Play the original IWADs and community maps. | `DoomWad` (lump directory merge), menu | M |
| **Extended node formats** (`XNOD`, `ZNOD`, `XGLN`, `ZGLN`) used by modern maps; the subsector polygon code already works from any node tree. | Modern PWADs. | `DoomMap.LoadLumps` | M |
| **Boom/MBF specials** (generalized linedefs, scrolling floors, friction, translucency) and **DeHackEd** patches. | Big community map support; large job. | `DoomWorld.ApplySpecial`, `DoomThings` | L |
| **Save / load game** (serialize sector heights, specials state, actors, player) with `CastleConfig` or JSON; **quick save**. | Longer sessions. | `DoomWorld` | M |
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

1. Real player projectiles (M): most visible gameplay gap, small code since the
   missile machinery exists.
2. Automap (M): expected by everyone who plays Doom, and a nice CGE 2D demo.
3. External WAD loading (M): turns the demo into something people can use with
   their own IWADs and PWADs.
