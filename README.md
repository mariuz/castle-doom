# Castle DOOM

[![Build](https://github.com/mariuz/castle-doom/actions/workflows/build.yml/badge.svg)](https://github.com/mariuz/castle-doom/actions/workflows/build.yml)
[![Web](https://github.com/mariuz/castle-doom/actions/workflows/web.yml/badge.svg)](https://github.com/mariuz/castle-doom/actions/workflows/web.yml)

**Play in the browser: https://mariuz.github.io/castle-doom/** (WebAssembly build)
&middot; **Downloads: [Releases](https://github.com/mariuz/castle-doom/releases)** (Windows, Linux)

Doom levels, rendered and played with [Castle Game Engine](https://castle-engine.io/)
(Object Pascal). It reads the original WAD format directly: Freedoom Phase 1 and
Phase 2 (BSD licensed, bundled in `data/wads/`) work out of the box, and any
vanilla-format Doom 1 / Doom 2 IWAD or PWAD can be dropped in next to them.

This project is deliberately written as a *tour of the engine*: every Doom subsystem
is mapped onto a Castle Game Engine feature.

![E1M1 start](docs/screenshot-e1m1-start.png)

| | |
|---|---|
| ![Door opened to the outside](docs/screenshot-e1m1-door.png) | ![Lift and a zombieman](docs/screenshot-e1m1-lift.png) |
| ![MAP04 with a cacodemon](docs/screenshot-map04.png) | ![Title screen](docs/screenshot-menu.png) |

| Doom | Castle Game Engine |
|---|---|
| WAD lumps (`VERTEXES`, `LINEDEFS`, `SECTORS`, BSP `NODES`...) | `DoomWad` / `DoomMap` units, plain Pascal records |
| Walls, floors, ceilings | X3D nodes built in code: `TIndexedTriangleSetNode`, `TUnlitMaterialNode`, per-vertex `TColorNode` for sector light, one `TCastleScene` per movable sector |
| Textures (`TEXTURE1` + `PNAMES` patch composition, flats, sprites) | decoded to `TRGBAlphaImage`, served through a custom URL protocol `doomgfx:/tex/STARTAN3.png` (`RegisterUrlProtocol`) so the engine's texture cache shares them between scenes |
| Animated flats/walls (NUKAGE, BFALL...) | `TImageTextureNode.SetUrl` swapped every 8 tics |
| Sky | a textured cylinder scene that follows the camera, with `LocalFog.enabled=false` so the fog never touches it |
| Light diminishing | `TCastleFog` on the viewport (toggle with `F`) |
| Player | `TCastleWalkNavigation`: gravity, `PreferredHeight` 41, `ClimbHeight` 24 (stairs), `Radius`, mouse look, head bobbing; collisions via `PreciseCollisions` on the map scenes |
| Things / monsters | one `TCastleTransform` per thing with a `TCastleBillboard` behavior and a quad `TCastleScene`; sprite rotations picked like `R_ProjectSprite` |
| Shooting | `Items.WorldRay` ray casts against walls and sprite billboards |
| Doors, lifts, floors, ceilings, stairs, crushers | sector height changes regenerate the affected `TCastleScene` coordinates in place |
| Sounds (`DS*` DMX lumps) | converted to WAV on the fly via `doomsfx:/DSPISTOL` URL protocol, positional audio with `TCastleSoundSource` |
| Music (`D_*` MUS or MIDI lumps + `GENMIDI` OPL patches) | a small OPL2-style FM synthesizer in `DoomMusic` renders the song to WAV (`doommus:/D_E1M1.wav`), looped on `SoundEngine.LoopingChannel[0]` |
| Status bar | `STBAR` + digit patches composed into one image shown by a pixel-perfect `TCastleImageControl` |
| Weapon sprites, flashes, screen flashes, messages | `TCastleImageControl`, `TCastleRectangleControl`, `TCastleLabel` |
| Title / intermission | `TCastleView`s |

## What works

- Freedoom Phase 1 (36 ExMy maps) and Phase 2 (32 MAPxx maps), map selection in the menu.
- Textured walls with Doom's pegging rules and offsets, masked middle textures (grates),
  floors and ceilings from BSP subsectors, sky, sector light levels with "fake contrast".
- Doors (manual, switch, walk-over, locked, blazing), lifts, floors, ceilings, crushers,
  stairs, teleporters, light changes, scrolling walls, switch textures, secret sectors,
  damaging floors, exits (normal and secret) with an intermission screen.
- Pickups: health, armor, ammo, keys, weapons, powerups, with Doom's messages.
- Monsters wake up on sight or noise, chase (2D Doom-style movement with step/drop-off
  rules, they open doors), attack with melee, hitscan or projectiles, take pain, die,
  drop items. Barrels explode with splash damage.
- Weapons: fist, chainsaw, pistol, shotgun, super shotgun, chaingun, rocket launcher,
  plasma, BFG (projectile weapons are approximated as instant hits with splash).
- Status bar with face, keys, arms, ammo table; weapon bobbing; damage and bonus flashes.
- Music: MUS and MIDI lumps played through an FM synthesizer driven by the WAD's GENMIDI
  instrument bank (the AdLib / Sound Blaster sound of the original), title, level and
  intermission tracks.

## Not (yet) done

- Monster infighting, Arch-vile resurrection, Pain Elemental spawning, boss triggers.
- Extended node formats (ZDoom XNOD/ZNOD); Freedoom uses vanilla nodes.

## Build and run

Install Castle Game Engine 7 (its Windows download bundles Free Pascal), then
(on Windows, copy `OpenAL32.dll` and `wrap_oal.dll` from the engine's `bin/` next to the
executable for sound; `castle-engine package` does that automatically):

```bash
castle-engine compile --mode=release
castle-engine run
```

or open `CastleEngineManifest.xml` in the Castle Game Engine editor.

Keys: `WASD`/arrows move, `Shift` run, mouse look, left mouse / `Ctrl` fire,
`E`/`Space` use, `1`-`7` and mouse wheel weapons, `F` fog, `M` mouse look on/off,
`J` music on/off, `N`/`P` next/previous map, `F5` screenshot, `F8` engine inspector,
`H` help, `Esc` menu.

Automated smoke test (loads a map, runs a script, saves screenshots, quits):

```bash
castle-doom --autotest E1M1 shots/e1m1 --demo "S,F:3,S,T:90,U,W:2,S,X,S,Q"
```

## Continuous integration

- `.github/workflows/build.yml`: packages Windows x86_64 and Linux x86_64 builds on every
  push using the [Castle Game Engine Docker image](https://castle-engine.io/docker); pushing a
  tag `vX.Y.Z` attaches them to a GitHub Release.
- `.github/workflows/web.yml`: builds the WebAssembly version (FPC main branch with the
  wasm32 cross-compiler and Pas2js are built from source and cached, since the Docker image
  does not ship them yet) and deploys `pages/` + the game to GitHub Pages.

## Source layout

```
code/doomwad.pas        WAD directory and palette
code/doomgraphics.pas   patches, textures, flats, sprites, animations, doomgfx: protocol
code/doommap.pas        map lumps, BSP queries, subsector polygons
code/doomgeometry.pas   map -> X3D scenes (chunks that can be regenerated)
code/doomthings.pas     thing type table (info.c reduced)
code/doomactors.pas     sprite billboards with frame animation
code/doomworld.pas      game logic: movers, specials, pickups, AI, weapons
code/doomsound.pas      DMX -> WAV, doomsfx: protocol
code/doommusic.pas      MUS/MIDI parsing, GENMIDI FM synthesizer, doommus: protocol
code/doomhud.pas        status bar composition
code/gameviewmenu.pas   title screen
code/gameviewplay.pas   viewport, navigation, HUD, input
```

Freedoom is Copyright (c) 2001-2024 Contributors to the Freedoom project, BSD licence
(see `data/wads/COPYING.txt`). Castle Game Engine is LGPL with static linking exception.
