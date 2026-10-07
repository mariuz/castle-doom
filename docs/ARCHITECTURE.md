# Castle DOOM: how it works

This document explains how a Doom WAD becomes a playable Castle Game Engine
(CGE) game, unit by unit, and which engine features each part relies on. It is
written for someone who knows Doom's data formats or CGE, but not necessarily
both. Everything is Object Pascal (FPC), compiled with the CGE build tool.

Contents

1. [Big picture](#1-big-picture)
2. [Coordinates and units](#2-coordinates-and-units)
3. [DoomWad: the archive](#3-doomwad-the-archive)
4. [DoomGraphics: patches, textures, flats, sprites](#4-doomgraphics-patches-textures-flats-sprites)
5. [DoomMap: map lumps and the BSP](#5-doommap-map-lumps-and-the-bsp)
6. [DoomGeometry: from sectors to X3D scenes](#6-doomgeometry-from-sectors-to-x3d-scenes)
7. [DoomThings and DoomActors: sprites as billboards](#7-doomthings-and-doomactors-sprites-as-billboards)
8. [DoomWorld: the game simulation](#8-doomworld-the-game-simulation)
9. [DoomSound: DMX sound effects](#9-doomsound-dmx-sound-effects)
10. [DoomMusic: MUS/MIDI through an FM synthesizer](#10-doommusic-musmidi-through-an-fm-synthesizer)
11. [DoomHud: the status bar](#11-doomhud-the-status-bar)
12. [Views: menu and play](#12-views-menu-and-play)
13. [The player: TCastleWalkNavigation](#13-the-player-tcastlewalknavigation)
14. [Custom URL protocols: the glue that makes the engine cache work](#14-custom-url-protocols)
15. [Testing without a human: --autotest and --demo](#15-testing-without-a-human)
16. [Platforms: desktop, WebAssembly, CI](#16-platforms-desktop-webassembly-ci)
17. [Performance notes](#17-performance-notes)
18. [Known gaps and ideas](#18-known-gaps-and-ideas)
19. [CGE API index](#19-cge-api-index)

---

## 1. Big picture

```
freedoom1.wad ──► DoomWad ──► DoomGraphics ─────────────┐ (textures, flats, sprites,
    (lumps)          │              │                    │  HUD graphics, GENMIDI)
                     │              ▼                    │
                     │        doomgfx: URLs ──► TImageTextureNode (CGE texture cache)
                     ▼                                   │
                 DoomMap ──► DoomGeometry ──► TCastleScene per chunk ──► TCastleViewport
              (vertices,       (X3D nodes                 ▲
               lines, sectors,  built in code)            │
               BSP, things)                               │
                     │                                    │
                     └──► DoomWorld ──► DoomActors (TCastleTransform + TCastleBillboard)
                            (35 Hz tic:   │
                             doors, lifts,└──► DoomSound (doomsfx: URLs, TCastleSoundSource)
                             monsters,         DoomMusic (doommus: URLs, LoopingChannel)
                             pickups,
                             weapons)
                                  ▲
                 GameViewPlay ────┘ (TCastleView: navigation, HUD, input)
                 GameViewMenu       (TCastleView: title screen, WAD/map choice)
```

Three ideas carry the whole design:

1. **Doom data stays in Doom's own structures.** `DoomMap` keeps vertices,
   linedefs, sidedefs, sectors, things and the BSP as plain records in Doom
   units. The game logic in `DoomWorld` works on those records, exactly like
   the original `p_*.c` files did, and only the *presentation* is CGE.
2. **Geometry is generated, not loaded.** There is no model file. `DoomGeometry`
   builds X3D node graphs (`TIndexedTriangleSetNode`, `TUnlitMaterialNode`,
   `TColorNode`...) in Pascal and hands them to `TCastleScene.Load(RootNode)`.
   Movable sectors get their own scene and are regenerated in place.
3. **Everything the engine loads goes through URLs.** Textures, sound effects
   and music are served by custom URL protocols (`doomgfx:`, `doomsfx:`,
   `doommus:`) registered with `RegisterUrlProtocol`. That lets us use the
   engine's normal loaders and caches (one GL texture per URL, shared by all
   scenes) without ever writing a file to disk.

Sizes, for orientation (lines of Pascal):

| Unit | Lines | Role |
|---|---:|---|
| `doomworld.pas` | 2763 | game logic: movers, specials, AI, weapons, pickups |
| `doommusic.pas` | 1029 | MUS/MIDI parsing and the FM synthesizer |
| `doomgeometry.pas` | 930 | map to X3D scenes |
| `doomgraphics.pas` | 765 | WAD graphics decoding, texture URLs |
| `gameviewplay.pas` | 688 | viewport, navigation, HUD, input, test harness |
| `doommap.pas` | 677 | map lumps, BSP queries, subsector polygons |
| `doomthings.pas` | 363 | thing type table (info.c reduced) |
| `gameviewmenu.pas` | 279 | title screen |
| `doomintermission.pas` | 330 | intermission screen |
| `doomautomap.pas` | 210 | automap drawn with 2D primitives |
| `doomfont.pas` | 130 | STCFN text |
| `doomactors.pas` | 248 | sprite billboards with animation |
| `doomwad.pas` | 225 | WAD directory and palette |
| `doomhud.pas` | 193 | status bar composition |
| `doomsound.pas` | 173 | DMX to WAV, positional sound |
| `gameinitialize.pas` | 47 | window, views, command line |

---

## 2. Coordinates and units

Doom maps are 2D (X right, Y up on the automap) with heights as a separate Z.
CGE is Y-up. The conversion, used everywhere through `DoomToCge` /
`CgeToDoom` in `DoomGeometry`:

```
CGE.X =  Doom.X
CGE.Y =  Doom.Z   (height)
CGE.Z = -Doom.Y
```

This is a proper rotation (determinant +1), so winding order and texture
orientation survive. One Doom map unit is one CGE unit; nothing is scaled. The
player is 56 units tall with the eye at 41, exactly Doom's numbers, so
`TCastleWalkNavigation.PreferredHeight = 41` and `ClimbHeight = 24` (Doom's
maximum step) carry over directly.

Angles: Doom angles are degrees counter-clockwise from east. The view converts
the camera direction with `atan2(-Dir.Z, Dir.X)` and back with
`DoomToCge(cos a, sin a, 0)`.

Time: the simulation runs at Doom's 35 tics per second (`TicRate`), driven from
the view's `Update` by accumulating `SecondsPassed`, so door speeds, monster
reaction times and animation durations use the original tic counts.

---

## 3. DoomWad: the archive

A WAD is a 12-byte header (`IWAD`/`PWAD`, lump count, directory offset),
lump data, and a directory of 16-byte entries (offset, size, 8-char name).
`TDoomWad` reads the whole file into a `TMemoryStream` (29 MB for Freedoom)
and keeps a `TWadLump` array. `LumpPointer` returns a pointer straight into
that memory, so decoding never copies.

The file is fetched with CGE's `Download('castle-data:/wads/freedoom1.wad')`.
`castle-data:` is the engine's URL scheme for the project's `data/` folder;
it works identically on desktop (a directory) and on the web (the build tool
packs `data/` into a zip the browser downloads before start).

Several files can be stacked (`AddFile`): the IWAD first, then PWADs, exactly
like Doom's `-file`. The merged directory keeps a file index per lump and
`FindLump` searches from the last file backwards, so a PWAD's `E1M1`,
`TEXTURE1`, sprites, flats, sounds or music replace the IWAD's. Sprite and
flat ranges (`S_START`/`SS_START`, `F_START`/`FF_START`) are scanned across
all files in `DoomGraphics`. Plain file paths from the command line are
turned into `file://` URLs with `FilenameToUriSafe`.

Also here: the 256-colour `PLAYPAL` palette (as `TVector4Byte`), the list of map
marker lumps (`E1M1`... or `MAP01`...), and a flag for Doom 2 style naming.

---

## 4. DoomGraphics: patches, textures, flats, sprites

Doom has three picture formats:

- **Patches** (sprites, HUD graphics, texture building blocks): column-based
  with transparent gaps ("posts"). `DrawPatchInto` decodes them into a CGE
  `TRGBAlphaImage`, converting rows because CGE images store the bottom row
  first (OpenGL convention) while Doom counts from the top.
- **Wall textures**: not stored as images at all. `TEXTURE1`/`TEXTURE2` list
  textures as compositions of patches (named through `PNAMES`) at offsets.
  `ComposeTexture` blits the patches into a fresh image.
- **Flats** (floors, ceilings): raw 64x64 palette indices.

Every decoded picture is a `TDoomImage`: the image, its size, the sprite
offsets (`LeftOffset`, `TopOffset`), whether it has transparent pixels, and a
URL like `doomgfx:/tex/STARTAN3.tga`. When something needs a texture node it
calls `TDoomImage.MakeTextureNode(Clamp)` which returns a *new*
`TImageTextureNode` pointing at that URL, plus a `TTexturePropertiesNode` with
`magNearest` magnification (crisp Doom texels), trilinear minification,
anisotropy, and repeat or clamp wrapping. New node per use is deliberate: CGE
does not allow one X3D node inside several `TCastleScene`s, but it does share
the GPU texture between nodes with the same URL through its texture cache.

The `doomgfx:` protocol's read handler writes the image as uncompressed 32-bit
TGA into a `TMemoryStream` (`WriteTga`). It was PNG at first; PNG encoding and
decoding in pure Pascal was so slow under WebAssembly that loading a level
triggered Chrome's "page unresponsive" dialog. TGA is a header and a memcpy.

Sprite lookup follows Doom's naming: `TROOA2A8` is sprite `TROO`, frame `A`,
rotation 2, and the same lump mirrored for rotation 8. `IndexSprites` builds a
dictionary from `prefix+frame+rotation` to lump and mirror flag; `Sprite()`
falls back to rotation 0 (all angles) when needed.

Animated flats and walls use Doom's fixed table (`NUKAGE1..3`, `BFALL1..4`...).
Each `TAnimGroup` keeps the list of `TImageTextureNode`s that show one of its
frames; every 8 tics `AnimationTic` sets a new URL on each of them, which the
engine picks up from the cache.

---

## 5. DoomMap: map lumps and the BSP

`TDoomMap.Create(Wad, 'E1M1')` reads the lumps that follow the map marker:
`THINGS`, `LINEDEFS`, `SIDEDEFS`, `VERTEXES`, `SEGS`, `SSECTORS`, `NODES`,
`SECTORS`.

The BSP comes in several formats, all loaded into the same structures
(`Nodes`, `Segs`, `Subsectors`, extra `Vertices`), so nothing downstream
cares which one a map used (`TDoomMap.NodesFormat` tells):

| Format | Where | Notes |
|---|---|---|
| vanilla | `NODES` (28-byte), `SEGS`, `SSECTORS` | 16-bit indices, child bit 15 = subsector |
| `XNOD` / `ZNOD` | `NODES` | ZDoom extended: 32-bit indices, extra fixed-point vertices, child bit 31; `Z` = zlib-compressed |
| `XGLN` / `ZGLN` | `NODES` or `SSECTORS` | GL nodes: closed subsectors with minisegs (linedef `FFFF`), only v1 stored per seg |
| `XGL2` / `ZGL2` | same | as XGLN with 32-bit linedef numbers |
| `XGL3` / `ZGL3` | same | as XGL2 with 16.16 fixed-point partition lines |

`LoadExtendedNodes` reads them with a bounds-checked cursor, decompresses
`Z*` variants with FPC's `zstream` (the same unit CGE's Tiled loader uses, so
it works in WebAssembly), maps seg vertex numbers (original `VERTEXES` first,
new vertices appended) and closes GL segs (`v2` = next seg's `v1` around the
subsector). Node children are normalized to a `NodeSubsector` flag
(`$40000000`) regardless of format. Minisegs have `Linedef = -1`;
`SideSector` returns -1 for them. Sidedef numbers are read unsigned with
`$FFFF` meaning "none", so maps with more than 32767 sidedefs work.
`tools/make_znodes.py` converts Freedoom's E1M1 into all six formats; each
must log the same "682 subsector polygons, total area 6712683" as vanilla.

Two things are derived that Doom's renderer never needed:

**Subsector polygons.** Doom draws floors as screen-space spans, so a subsector
is just a list of segs. For a 3D mesh we need the actual convex polygon. The
classic trick (also used by GL ports) is in `BuildSubsectorPolygons`: start
from the map's bounding rectangle, walk the BSP from the root to each
subsector, and at every node clip the polygon by the node's partition line
(keeping the right side for child 0, the left for child 1, matching
`R_PointOnSide`); at the leaf clip by each seg's line. The result is the
subsector's convex polygon, counter-clockwise in Doom coordinates. Floors are
fanned from it directly; ceilings use the reversed order.

**Per-sector lists** of linedefs and subsectors, plus the neighbour searches
from `p_spec.c` (`LowestFloorSurrounding`, `NextHighestFloor`,
`LowestCeilingSurrounding`...) that door, lift and floor specials need.

`SubsectorAt`/`SectorAt` walk the BSP (`R_PointInSubsector`) and are used for
the player's sector, monster positions and teleport destinations.

---

## 6. DoomGeometry: from sectors to X3D scenes

### Chunks

A `TMapChunk` owns two `TCastleScene`s, one with `Collides = true` for solid
geometry and one with `Collides = false` for things you can walk through
(masked middle textures such as grates), both with `PreciseCollisions = true`
so the walk navigation and ray casts hit actual triangles.

The level is split into one **static chunk** plus one chunk per **dynamic
sector**. `DoomWorld.ComputeDynamicSectors` marks a sector dynamic when any
linedef special can move it or change its light: tagged sectors of every
special, back sectors of manual doors, sectors reached by stair builders,
donut neighbours, and sectors with light effects. A wall between a static and a
dynamic sector lives in the dynamic sector's chunk. `FSectorDependents` records
which chunks must be rebuilt when a sector changes; `SectorChanged` marks
them, `FlushDirty` regenerates them once per frame.

### Batches and nodes

Inside a chunk, triangles are grouped per texture into `TGeomBatch`es. Each
batch becomes one `TShapeNode` with:

- `TIndexedTriangleSetNode` geometry, `Solid = true` (back-face culling),
- `TCoordinateNode`, `TTextureCoordinateNode`, `TColorNode` (per-vertex),
- `TAppearanceNode` with `TUnlitMaterialNode` (Doom has no lighting model; the
  per-vertex `Color` multiplies the texture) and `AlphaMode = amMask` when the
  texture has transparent pixels (alpha test, no sorting problems),
- a `TTextureTransformNode` for scrolling walls (linedef special 48).

`Generate` fills the batch lists and either builds nodes and calls
`Scene.Load(Root, true)` (first time, or when vertex counts changed) or just
calls `CoordinateNode.SetPoint`, `TextureCoordinateNode.SetPoint`,
`ColorNode.SetColor` on the existing nodes. That in-place path is what a door
uses every tic while moving: a few hundred vertices, no scene reload.

### Walls

For each side of each linedef `EmitLineSide` emits up to three quads following
`r_segs.c`:

- one-sided: the middle texture from floor to ceiling,
- two-sided: a lower part (our floor to the neighbour's higher floor), an upper
  part (neighbour's lower ceiling to our ceiling, skipped when both ceilings
  are sky), and the masked middle texture clipped to one texture height.

Texture pegging follows the original rules. With `TexTopZ` the world height of
texture row 0, v coordinates are `1 - (TexTopZ - z) / TextureHeight`:

| part | default | with the unpegged flag |
|---|---|---|
| one-sided middle | top at ceiling | bottom at floor (`ML_DONTPEGBOTTOM`) |
| upper | bottom at the neighbour's ceiling | top at our ceiling (`ML_DONTPEGTOP`) |
| lower | top at the neighbour's floor | top at our ceiling (`ML_DONTPEGBOTTOM`) |
| masked middle | top at the lower ceiling | bottom at the higher floor |

plus the sidedef's x/y offsets. Horizontal u runs from the side's start vertex
(v1 for the front side, v2 for the back side, as Doom does).

Dynamic chunks always emit upper and lower parts even when their height is
zero, so the vertex count never changes while a door moves.

Light: the sector's light level becomes a grey vertex colour
(`LightColor`), with Doom's "fake contrast" (north-south walls +16, east-west
-16). Light diminishing with distance is approximated by a `TCastleFog` on the
viewport (exponential, 4500 units, toggle with F).

### Sky, collisions, switches

The sky is a textured cylinder scene that follows the camera (updated every
frame in `Update`). Doom maps 1024 sky columns around a full turn, so the
256-wide texture repeats 4 times; row 100 of 128 sits at the horizon. A
`TLocalFogNode` with `Enabled = false` in that scene keeps the viewport fog
from darkening it. Sky ceilings are simply not drawn.

Two-sided lines flagged impassable (fences, ledges) get invisible quads in a
dedicated collision scene (`Visible = false`, `Pickable = false`,
`Collides = true`).

Switch textures (`SW1xxx`/`SW2xxx`) get a private batch per line, so
`FlipSwitch` can change just that wall's node URL.

---

## 7. DoomThings and DoomActors: sprites as billboards

`DoomThings` is Doom's `info.c` reduced to what the port needs: for each
`THINGS` type number, the sprite prefix, radius, height, whether it blocks,
hangs from the ceiling or floats, idle/move/attack/pain/death frame letters,
health, speed, pain chance, attack kind, damage dice, pickup kind and sounds.
`PickupMessage` has the original messages.

A `TDoomActor` is a `TCastleTransform` with a child `TCastleScene` holding one
textured quad, and a `TCastleBillboard` behavior (`AxisOfRotation = (0,1,0)`)
that turns the quad toward the camera every frame. The quad's size and
position come from the patch's width, height and offsets (Doom's origin is at
the feet). `UpdateRotation` picks one of the 8 rotation sprites with Doom's
formula `(angle_to_thing - thing_angle + 202.5°) / 45°`, and `ApplySprite`
sets the quad's coordinates (mirrored if needed) and the texture node's URL.

Animation is a frame sequence (`PlaySequence('ABCD', tics, loop)`) advanced by
`AnimateTic`; `SequenceDone` tells the world when a one-shot sequence (pain,
death, explosion, bullet puff) finished.

`Collides` is set for solid things so the walk navigation bumps into barrels
and monsters; `Pickable` only for monsters and barrels so bullets pass through
decorations. Brightness comes from the sector light through the material's
`EmissiveColor` (fullbright for explosions, projectiles, some powerups).

---

## 8. DoomWorld: the game simulation

`TDoomWorld` owns the map, geometry, actors and movers, and runs `RunTic` 35
times per second. The view calls `Update` every frame with the player's feet
position (camera minus 41) and facing.

**Sector movers** (`TSectorMover`) move a sector's floor or ceiling toward a
target at a speed in units per tic, optionally wait and return, or cycle
forever (crushers, perpetual lifts). Every move calls `SetHeight`, which writes
the sector record and calls `Geometry.SectorChanged`. Doors coming down on the
player or a monster reverse like in Doom; crushers hurt instead. Each mover
has a `TCastleTransform` emitter in the sector's middle so door and lift sounds
are positional.

**Linedef specials** are handled in `ApplySpecial` by activation kind (use,
walk-over, shoot) with the vanilla special numbers: manual and locked doors
(1, 26-28, 31-34, 117, 118), switch and walk-over doors (2-4, 16, 29, 42, 46,
50, 61, 63, 75, 76, 86, 90, 99, 103, 105-116, 133-137), lifts (10, 21, 53, 54,
62, 87-89, 120-123), floors (5, 14, 15, 18-20, 22, 23, 30, 36-38, 45, 55-60,
64-71, 82-84, 91-98, 101, 102, 119, 128-132, 140), ceilings and crushers (6,
25, 40, 41, 43, 44, 49, 72-74, 77, 141), stairs (7, 8, 100, 127), lights (12,
13, 17, 35, 79-81, 104, 138, 139), teleporters (39, 97), exits (11, 51, 52,
124) and gun triggers (24, 46, 47). One-time specials are cleared after use;
switch textures flip, repeatable ones flip back after a second.

Sector specials give damaging floors (5, 7, 16, 4, 11), secrets (9) and light
effects (blink, strobe, glow, flicker) animated in `TicLights`.

**Using** (E/Space) traces 64 units ahead and picks the closest crossing line,
continuing through passable lines without specials, with the "oof" sound on a
blocked wall, following `P_UseLines`. **Walk-over** triggers compare the
player's position between tics against special lines (segment intersection).

**Pickups** check the 2D box overlap used by Doom and apply Doom's amounts:
health and armour caps, ammo per weapon, backpack, keys, powerups, weapon
auto-switch.

**Monsters** have a `Target` (nil means the player). `TicMonster`,
`MonsterAttack`, `MonsterHitscan` and `SpawnMissile` all aim at
`TargetPosition`. `DamageActor` takes the attacker: damage from a monster
makes the victim turn on it (`P_DamageMobj`), damage from the player turns it
back on the player, environmental damage (crushers, barrels) retargets nobody.
Monster missiles carry their `Shooter` and hit any other monster except the
shooter's own species (passed through, as in `PIT_CheckThing`); zombie
hitscans hit the first monster standing in the line of fire; splash damage is
blamed on the rocket's shooter and ignored by cyberdemons and spider
masterminds. Dead targets drop the monster back to the player. When the last
monster of a boss type dies, `BossDeath` runs Doom's `A_BossDeath` table:
E1M8 barons / E4M8 spiders / MAP07 mancubi lower the tag 666 floors, MAP07
arachnotrons raise tag 667 by the shortest lower texture, E4M6 cyberdemons
blaze-open tag 666, Keen opens tag 666 doors, E2M8 and E3M8 end the level.

Monsters sleep until they see the player (`SightClear`: a 2D line-of-sight
test against one-sided lines and closed two-sided lines) or hear a shot
(`NoiseAlert`). Awake, they chase with Doom-style 2D movement (`TryMove2D`:
one-sided and blocking lines, openings too low, steps higher than 24, drop-offs
unless floating, other solid things, the player), try other directions when
blocked, open doors in their way, and attack when close (melee), when they
have line of sight (hitscan with a distance-based hit chance), or by spawning
a projectile actor (`SpawnMissile`: imp, cacodemon, baron, cyberdemon,
revenant, mancubus, arachnotron). Projectiles fly as actors (`TicMissile`),
explode on walls, floors, ceilings or the player, with splash damage for
rockets. Damage applies pain (chance from the table) or death (death
sequence, then a corpse that no longer collides); zombies drop ammo; barrels
explode with radius damage.

**Weapons** fire from the view's camera ray. Hitscan weapons (`HitscanAttack`)
use `Items.WorldRay`, which returns the first `TCastleTransform` hit and the
distance; a hit `TDoomActor` takes damage and bleeds, a wall gets a bullet
puff and may trigger a gun-activated line. The shotgun fires 7 pellets with
horizontal spread, the super shotgun 20 with vertical spread too. The rocket
launcher, plasma gun and BFG spawn real projectile actors
(`SpawnPlayerMissile`: `MISL`, `PLSS`, `BFS1` sprites) that fly along the
camera ray including its pitch, hit monsters and barrels (`FromPlayer`
missiles never hit the player), and explode on walls, floors and ceilings;
rockets add 128-unit splash damage, the BFG ball launches after Doom's 40-tic
charge and on impact sprays 40 tracers over 90° from the player (`BfgSpray`,
15d7 each, with the green `BFE2` flash on every target). Weapon animation
frames and muzzle flashes are small per-weapon state tables in
`UpdateWeaponAnimation`.

The player record (`TPlayerState`) holds health, armour, ammo, weapons, keys,
powerup timers, messages, screen-flash intensities and the status-bar face
state.

---

## 9. DoomSound: DMX sound effects

Doom sound lumps (`DS*`) are DMX format: a small header (format 3, sample rate,
sample count) and 8-bit unsigned PCM with 16 padding bytes on each side.
`DmxToWav` wraps that into a WAV in memory. The `doomsfx:` protocol serves
`doomsfx:/DSPISTOL` that way, so a `TCastleSound` with that `Url` loads like
any WAV.

`TDoomSounds.Play` uses `SoundEngine.Play` (non-positional: the player's
weapon, pickups, UI). `PlayAt(Lump, Transform)` attaches a `TCastleSoundSource`
behavior to the given transform (an actor, a mover's emitter) and plays
through it, so monsters and doors are heard where they are. The sounds'
`ReferenceDistance`/`MaxDistance` are set to Doom-like 200/1800 units.

On Windows the engine needs `OpenAL32.dll` next to the executable;
`castle-engine package` adds it, for a local run copy it from the engine's
`bin` folder. On the web the engine uses Web Audio automatically.

---

## 10. DoomMusic: MUS/MIDI through an FM synthesizer

The engine has no MIDI playback, and Doom music was never recorded audio: it is
note data (MUS, or plain MIDI in Freedoom) played on the sound card's Yamaha
OPL2 FM chip using the instrument bank in the `GENMIDI` lump. `DoomMusic`
recreates that pipeline in software:

1. `ParseMus` / `ParseMidi` turn the lump into a time-stamped event list
   (note on/off, program, volume, expression, pitch bend). MUS runs at 140 Hz
   with channel 15 as percussion; MIDI tracks are merged by tick and converted
   to seconds through the tempo map. The merge uses a hand-written stable
   merge sort because `Generics.Defaults` comparer types differ between FPC
   3.2 and the main branch used for WebAssembly.
2. `LoadGenMidi` reads the 175 instruments (128 melodic, 47 percussion), each
   with up to two voices of modulator/carrier parameters, feedback/connection,
   note offset, fine tuning, fixed pitch.
3. `RenderDoomSong` runs the synthesizer: up to 36 voices, each two operators
   with 32-bit fixed-point phase accumulators, 2048-entry wave tables for the
   four OPL waveforms, ADSR envelopes with YM3812 timings and rate scaling,
   key-scale level, total level, feedback (up to 2 cycles of phase), FM
   modulation (up to 4 cycles), vibrato and tremolo LFOs updated every 32
   samples. Output is 22050 Hz mono, normalized to -1 dBFS, written as WAV.
4. The `doommus:` protocol serves `doommus:/D_E1M1.wav`; a `TCastleSound` with
   that URL is assigned to `SoundEngine.LoopingChannel[0]`, the engine's
   music channel, which loops it.

Rendering a 2-minute track takes about a second natively and a few seconds in
WebAssembly, once per track (sounds are cached). Set the environment variable
`CASTLE_DOOM_DUMP_MUSIC` to a folder to get the WAV files for listening.

---

## 11. DoomHud: the status bar

`TDoomStatusBar` is a `TCastleImageControl` (`SmoothScaling = false`,
`Stretch = true`) showing a 320x32 image composed from the WAD's HUD patches:
`STBAR`, `STARMS`, big red digits `STTNUM*` and the percent sign, small yellow
digits `STYSNUM*` and grey `STGNUM*` for the arms panel, the key icons
`STKEYS*`, and the face (`STFST*` idle variants, `STFKILL*` pain, `STFOUCH*`
big hits, `STFEVL*` grin, `STFGOD0`, `STFDEAD0`), at the pixel positions from
`st_stuff.c`. The image is rebuilt only when a signature string of the shown
values changes. The view stretches it to the viewport width (10:1).

Player messages use Doom's own font: `TDoomFontText` (`doomfont.pas`)
composes the `STCFN033..095` glyph patches (upper case, 4-pixel spaces,
8-pixel lines) into an image and shows it scaled to the viewport's 200-line
grid. The intermission (`doomintermission.pas`) is the same idea at full
screen: a 320x200 image rebuilt every tic from `WIMAP0..2` or `INTERPIC`, the
`WILVxx`/`CWILVxx` level-name graphics, `WIF`/`WIENTER`, `WIOSTK`/`WIOSTI`/
`WIOSTS`/`WITIME`/`WIPAR` and the `WINUM` digits at `wi_stuff.c` positions,
with Doom's count-up (2% per tic, pistol click every 4 tics, explosion at the
end, one-second pauses), par times, the ENTERING screen, and use/fire to skip.
The control is kept 4:3 and centred on the viewport.

The weapon sprite and muzzle flash are two more `TCastleImageControl`s placed
with Doom's formula (`x1 = centerx + (1 - 160 - leftoffset) * scale`,
`WEAPONTOP = 32`) and bobbed with the camera speed. Screen flashes are
full-size `TCastleRectangleControl`s with animated alpha; messages and the
help panel are `TCastleLabel`s.

---

### The automap

`TDoomAutomap` (`doomautomap.pas`) is a `TCastleUserInterface` whose `Render`
override draws straight with CGE's immediate 2D primitives: `DrawRectangle`
for the black background and one `DrawPrimitive2D(pmLines, ...)` call per
colour group (red one-sided and secret lines, brown floor-height changes,
yellow ceiling-height changes, grey two-sided lines and dimmed unseen lines
when the reveal cheat is on), plus the player arrow from Doom's
`player_arrow` line list rotated by the player angle. It is inserted above the
viewport and below the HUD, follows the player, zooms with +/- or the wheel
and can show a 128-unit grid. Lines become visible when the player's sector or
a neighbouring sector has been visited (`DoomWorld.RevealAutomap` sets
`ML_MAPPED`, a cheap stand-in for Doom marking rendered segs).

## 12. Views: menu and play

CGE structures an application as `TCastleView`s pushed on the window's
container. `GameInitialize` creates the window (`TCastleWindow`), parses the
command line, creates both views and shows the menu.

`TViewMenu` loads a WAD set (`TDoomWad`, `TDoomGraphics`, `TDoomSounds`,
`TDoomMusic`), shows `TITLEPIC` in an image control, buttons
(`TCastleButton` in `TCastleHorizontalGroup`/`TCastleVerticalGroup`) to pick
Freedoom Phase 1 or 2 and the map, "Open IWAD..." and "Add PWAD..." using the
window's native `FileDialog` (desktop only), a "Last WADs" shortcut backed by
`UserConfig` (`castle-config:`), and plays the title track. The command line
accepts Doom's `-iwad FILE`, `-file PWAD...` and `-warp MAP`. Starting hands
the WAD objects to `TViewPlay` and sets `Container.View`. (A view cannot
change the container's view from inside its own `Start`; the autotest path
uses `WaitForRenderAndCall` for that.)

`TViewPlay.Start` builds the UI in code (no `.castle-user-interface` design
file, to keep everything visible in Pascal): `TCastleViewport` with a
`TCastleCamera` (90° horizontal field of view, near plane 4 units) and
`TCastleFog`, the `TCastleWalkNavigation`, the HUD controls and a
`TCastleCrosshair`. It then calls `StartMap`, which shows a "Loading" overlay
for one frame (`WaitForRenderAndCall`) before the synchronous
`DoomWorld.LoadMap`, places the camera at the player start, and starts the
level music. `Update` converts the camera to Doom coordinates, runs the world,
applies teleports, auto-fire, flashes, messages and the weapon sprite. The
intermission is a text overlay with Doom's kills/items/secrets/time;
continuing loads the next map from `NextMapName` (Doom 1 episodes and secret
levels, Doom 2's MAP31/32 detours) keeping the inventory.

---

## 13. The player: TCastleWalkNavigation

The player is not a `TCastleTransform`; it is the viewport's camera moved by
`TCastleWalkNavigation` with:

- `Gravity = true`, `PreferredHeight = 41`, `Radius = 14` (Doom's 16 minus a
  margin so 56-unit-high openings stay passable with the collision sphere),
- `ClimbHeight = 24` (Doom's step), `MoveSpeed = 290` units/s (Doom's walk;
  Shift doubles it through `Input_Run`),
- `FallSpeedStart`/`FallSpeedIncrease`/`GrowSpeed` tuned for Doom units so
  lifts carry the player and drops feel right,
- `HeadBobbing = 0.03`, `MouseLook = true`, WASD bound through
  `Input_Forward.Assign(keyW, keyArrowUp)` etc., jump/crouch/fly inputs
  cleared.

Collisions use the map chunks' `PreciseCollisions` triangles, the invisible
blocking-line scene, and the actors' bounding boxes (`Collides`). The
navigation itself is what blocks walking through walls, steps the player up
stairs and drops them off ledges; the world only needs the resulting
position.

---

## 14. Custom URL protocols

`RegisterUrlProtocol(Protocol, ReadEvent, WriteEvent)` from `CastleDownload`
lets any URL scheme be answered by a Pascal callback returning a `TStream`
and a MIME type. The port registers three:

| Scheme | Example | Content | Consumer |
|---|---|---|---|
| `doomgfx:` | `doomgfx:/tex/STARTAN3.tga`, `/flat/FLOOR4_8.tga`, `/patch/STBAR.tga` | 32-bit TGA | `TImageTextureNode.SetUrl` |
| `doomsfx:` | `doomsfx:/DSPISTOL` | WAV, 8-bit mono | `TCastleSound.Url` |
| `doommus:` | `doommus:/D_E1M1.wav` | WAV, 16-bit mono 22050 Hz | `TCastleSound.Url` on the looping channel |

Why not write files? The engine's texture cache (`TTexturesVideosCache`) and
sound buffer cache key on the URL, so one GPU texture or one OpenAL buffer
serves every node that uses it, including the hundreds of sprite scenes; the
WAD stays the single source of truth; and it works the same on the web where
there is no writable file system.

---

## 15. Testing without a human

The game can drive itself for smoke tests and screenshots:

```
castle-doom --autotest E1M1 out/e1m1 --demo "G:480:712,A:0,U,W:1.5,F:1.5,S,T:180,S,X,S,E,W:1,S,U,W:1,S,Q"
```

`--autotest MAP PREFIX` starts that map directly (`MENU` screenshots the title
screen instead); without `--demo` it saves four screenshots turning 90° each
and quits. `--demo` runs a comma-separated script: `F:sec`/`B:sec`/`L:sec`/
`R:sec` hold a movement key (through `Container.Pressed.KeyDown`, so the real
navigation and collisions are exercised), `T:deg` turn, `A:deg` absolute
angle, `G:x:y` teleport to Doom coordinates, `U` use, `X` fire, `E` exit the
level, `N` next map, `K` give all weapons/ammo/keys, `C:n` select weapon n,
`M` toggle automap, `I` reveal all map lines, `Z:f` zoom the automap by f,
`V` make every monster fight the nearest other species, `D` kill all monsters
(boss triggers), `S` screenshot (`PREFIX_n.png`), `W:sec` wait, `Q` quit.
The log (`%LOCALAPPDATA%\castle-doom\castle-doom.log` on Windows) records
map/geometry/thing load times, music render times, and every screenshot with
the player position.

---

## 16. Platforms: desktop, WebAssembly, CI

The same code builds for Windows, Linux and the browser. `castle-engine
compile --target=web` compiles the Pascal to WebAssembly with FPC's `wasm32`
cross-compiler and a small Pas2js glue program, and packs `data/` into
`castle-doom_data.zip`; `castle-engine-output/web/dist/` is a static site.
Things that differ on the web and shaped the code:

- All loading is synchronous from the in-memory data zip, so `Download()` of
  `castle-data:` and the custom protocols work unchanged.
- Sound uses Web Audio; it needs a user gesture, which the START click is.
- No threads, so music is rendered on the main thread (a few seconds per
  track); the "Loading" overlay is drawn first.
- Heavy pure-Pascal work is slower: PNG was replaced by TGA for textures.
- The web target needs the generated `castleautogenerated.pas` in the project
  (`castle-engine generate-program`), committed to the repository.

`.github/workflows/build.yml` packages Windows and Linux inside the CGE Docker
image (`kambi/castle-engine-cloud-builds-tools:cge-unstable`) and attaches
them to a GitHub Release on `v*` tags. `.github/workflows/web.yml` builds FPC's
main branch with the `wasm32-wasip1` cross-compiler and Pas2js from source
(cached by FPC commit), compiles the web target with `wasm-opt` optimization,
and deploys `pages/index.html` plus the game to GitHub Pages.

---

## 17. Performance notes

- Level load is dominated by texture decoding the first time a texture is
  seen; E1M1 loads in about 100 ms natively (map 2 ms, geometry 70 ms, things
  20 ms).
- Static geometry is one scene with one shape per texture; dynamic sectors
  are small scenes. `TCastleViewport.DynamicBatching = true` lets the engine
  merge small shapes into fewer draw calls. Release builds run at 100+ FPS at
  1600x900.
- Monster line-of-sight and movement loop over all linedefs with a bounding
  box rejection; cheap for vanilla-sized maps, but a blockmap would be the
  next step for huge maps.
- Music rendering is the slowest single step (about 1 s per track natively,
  4x more on the web). Options if needed: lower `SampleRate`, render only the
  first minute, or cache rendered WAVs.

---

## 18. Known gaps and ideas

- No Arch-vile resurrection, Pain Elemental shoots cacodemon fireballs
  instead of spawning lost souls, no Icon of Sin.
- Doom's "donut" (special 9) only lowers the pillar.
- No demo playback, no save games, no difficulty selection
  (things are spawned for "Hurt me plenty").
- Vanilla node format only. A blockmap-free design means all 2D queries scan
  all lines.
- The FM synth approximates the OPL2 (envelope shapes and the modulation index
  are estimates, not a register-accurate emulation).

---

## 19. CGE API index

Where each engine feature is used, as a map for learning the engine:

| CGE feature | Unit | Used for |
|---|---|---|
| `TCastleWindow`, `Application`, `Window.ParseParameters` | GameInitialize | window and command line |
| `TCastleView`, `Container.View`, `WaitForRenderAndCall` | GameViewMenu, GameViewPlay | screens, deferred work |
| `Container.LoadSettings('castle-data:/CastleSettings.xml')` | GameInitialize | UI scaling |
| `Download`, `castle-data:`, `FilenameToUriSafe` | DoomWad | reading WADs from data or user files |
| `TCastleWindow.FileDialog`, `UserConfig` (`CastleConfig`) | GameViewMenu | picking and remembering user WADs |
| `RegisterUrlProtocol`, `TUrlReadEvent` | DoomGraphics, DoomSound, DoomMusic | in-memory assets |
| `TRGBAlphaImage`, `PixelPtr`, `RawPixels` | DoomGraphics, DoomHud | decoding and composing pictures |
| `TImageTextureNode`, `TTexturePropertiesNode`, `magNearest`, `bmClampToEdge` | DoomGraphics | texture nodes |
| `TX3DRootNode`, `TShapeNode`, `TAppearanceNode`, `TUnlitMaterialNode`, `TIndexedTriangleSetNode`, `TCoordinateNode`, `TTextureCoordinateNode`, `TColorNode`, `TTextureTransformNode`, `TLocalFogNode`, `AlphaMode` | DoomGeometry, DoomActors | building geometry in code |
| `TCastleScene.Load(RootNode, true)`, `PreciseCollisions`, `Collides`, `Pickable`, `Visible` | DoomGeometry, DoomActors | scenes and collision flags |
| `SetPoint`/`SetColor` on coordinate/colour nodes | DoomGeometry | updating moving sectors in place |
| `TCastleTransform`, `Translation`, `AddBehavior`, `FindBehavior` | DoomActors, DoomSound | things and sound emitters |
| `TCastleBillboard` | DoomActors | sprites facing the camera |
| `TCastleViewport`, `Items`, `Camera`, `Fog`, `DynamicBatching` | GameViewPlay | rendering |
| `TCastleCamera.SetView`, `Direction`, `Perspective.FieldOfView/FieldOfViewAxis`, `ProjectionNear` | GameViewPlay | the player's eye |
| `TCastleFog` (`ftExponential`, `VisibilityRange`) | GameViewPlay | light diminishing |
| `TCastleWalkNavigation` and its properties, `Input_*.Assign/MakeClear` | GameViewPlay | player movement |
| `Items.WorldRay`, `TRayCollision.Distance` | DoomWorld | shooting |
| `TCastleSound`, `SoundEngine.Play`, `TCastleSoundSource`, `SoundEngine.LoopingChannel[0]` | DoomSound, DoomMusic | effects and music |
| `TCastleImageControl` (`Image`, `SmoothScaling`, `Stretch`), `TCastleLabel`, `TCastleRectangleControl`, `TCastleCrosshair`, `TCastleButton`, layout groups, `Anchor` | DoomHud, GameViewPlay, GameViewMenu | 2D UI |
| `Container.Pressed`, `Container.MousePressed`, `TInputPressRelease.IsKey/IsMouseButton/MouseWheelScroll` | GameViewPlay | input |
| `TCastleUserInterface.Render`, `DrawPrimitive2D`, `DrawRectangle`, `RenderRect` | DoomAutomap | immediate-mode 2D drawing |
| `Container.Fps`, `WritelnLog`, `WritelnWarning`, `Application.MainWindow.SaveScreen` | GameViewPlay, everywhere | diagnostics and screenshots |
| `castle-engine compile/package/generate-program`, `--target=web` | CI | builds |
