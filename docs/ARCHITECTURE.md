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
10. [DoomMusic: MUS/MIDI on an OPL3](#10-doommusic-musmidi-on-an-opl3)
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
                     └──► DoomWorld ──► DoomActors (TCastleTransform + TSpriteBatch quads)
                            (35 Hz tic:   │
                             doors, lifts,└──► DoomSound (doomsfx: URLs, TCastleSoundSource)
                             monsters,         DoomMusic (doommus: URLs, LoopingChannel)
                             pickups,
                             weapons)
                                  ▲
                 GameViewPlay ────┘ (TCastleView: navigation, HUD, input)
                 GameViewMenu       (TCastleView: Doom menu (DoomMenu), options)
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
| `doommusic.pas` | 1700 | MUS/MIDI parsing, the OPL3 driver and the FM synthesizer |
| `doomopl3.pas` | 170 | Nuked OPL3 as a runtime-loaded shared library |
| `doomgeometry.pas` | 930 | map to X3D scenes |
| `doomgraphics.pas` | 765 | WAD graphics decoding, texture URLs |
| `gameviewplay.pas` | 2000 | viewport, navigation, the 2D layer from `data/play.castle-user-interface`, input, test harness |
| `doomworldstatus.pas` | 130 | `TDoomWorldStatus`: the game's state as published properties for the inspector |
| `doommaptransform.pas` | 300 | `TDoomMapTransform`: a level from a WAD as a transform in any design ("Doom Map" in the editor) |
| `gameviewdesign.pas` | 80 | `--autotest MAPCOMPONENT`: shows `data/mapcomponent.castle-user-interface` and screenshots it |
| `doommap.pas` | 677 | map lumps, BSP queries, subsector polygons |
| `doomthings.pas` | 363 | thing type table (info.c reduced) |
| `gameviewmenu.pas` | 780 | title screen: Doom menu and options |
| `doommenu.pas` | 420 | Doom's menu from `M_*` graphics |
| `doomintermission.pas` | 330 | intermission screen |
| `doomfinale.pas` | 520 | finale text, end pictures, bunny scroller, cast call |
| `doommapinfo.pas` | 380 | UMAPINFO: per-map names, music, sky, par, next maps, story texts, endings |
| `doomstates.pas` | 230 | vanilla's state table and mobjinfo rows (`doomstates_table.inc`, generated from info.c): what DeHackEd edits and the things' sequences come from |
| `doomdehacked.pas` | 560 | DeHackEd patches (`DEHACKED` lumps, `-deh` files): BEX strings, things, frames, code pointers, Misc, Ammo, par times |
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

Animated flats and walls use Doom's fixed table (`NUKAGE1..3`, `BFALL1..4`...)
at 8 tics a frame, or a PWAD's Boom `ANIMATED` lump instead (`ParseAnimatedLump`:
ranges with their own speed, `TAnimGroup.Speed`).
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
| glBSP V1, V2, V3, V5 | `GL_VERT`, `GL_SEGS`, `GL_SSECT`, `GL_NODES` after a `GL_<map>` marker (in the WAD or a `.gwa` given with `-file`) | used when `NODES` and `SSECTORS` are empty (glBSP `-xn`); GL vertices (V1 16-bit, V2+ fixed) appended after `VERTEXES`, seg vertex flag bit 15 / 30 (V3) / 31 (V5), V3 headers `gNd3`, V5 32-bit subsectors and node children (`LoadGlNodes`) |

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

Inside a chunk, triangles are grouped into `TGeomBatch`es: one per atlas
page (`UseTextureAtlas`, the default) plus one per texture that stays out of
the atlas (switches, whose texture is swapped in place; scrolling walls,
with their texture transform; animated textures, whose URL changes), or
one per texture with `--no-atlas`. Each batch becomes one `TShapeNode` with:

- `TIndexedTriangleSetNode` geometry, `Solid = true` (back-face culling),
- `TCoordinateNode`, `TTextureCoordinateNode` (in texture repeats, as if
  each wall had its own texture), the `doom_light` and `doom_tile` vertex
  attributes (`TFloatVertexAttributeNode`: the light, and the texture's
  rectangle in the atlas page, (0, 0, 1, 1) with an own texture),
- `TAppearanceNode` with `TUnlitMaterialNode` (Doom has no lighting model)
  and `AlphaMode = amMask` when the texture has transparent pixels (alpha
  test, no sorting problems),
- a `TTextureTransformNode` for scrolling walls (linedef special 48).

The atlas (`TDoomGraphics.BuildAtlas`, called by `TDoomGeometry.Create`
with every texture and flat the map's sidedefs and sectors name): pages
2048 wide, shelves of decreasing image height, each image in a block
whose origin and size are multiples of 8 texels, the image 4 texels in
and the rest of the block its wrapped continuation (so filtering at a
tile's edge sees the wrapped neighbour, and the page's mipmaps up to
level 3 never average two tiles), trimmed to a power-of-two height, a new
page when one is full (Freedoom's largest map needs about 3 M texels, one
page); served as `doomgfx:/atlas/<map>_<n>.tga`. The page's
`TImageTextureNode` clamps, magnifies with nearest (Doom's unfiltered
look up close) and carries `TDoomLighting.AtlasTextureEffect`, a
`PLUG_texture_color` that samples at `tile.xy + fract(uv) * tile.zw` (a
texture-level effect: group effects are plugged before CGE adds the
texture code). When CGE upgrades the shaders to GLSL 1.40 / 3.00 es
(OpenGL 3.1+, OpenGL ES 3, WebGL 2: `AtlasMipmapsAvailable`) the page
has mipmaps with trilinear minification and the effect samples with
`textureGrad`, the gradients taken from the unwrapped coordinate
(`uv * tile.zw`) so `fract`'s jump does not select the smallest mipmap
along every seam, clamped to level 3; otherwise (and with
`--no-atlas-mipmaps`) there are no mipmaps and plain `texture2D`
samples, linear when minified. E1M1 at the door: 21 map draw
calls instead of 151, geometry built in 63 ms instead of 96-244.

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

Light: every vertex carries a `doom_light` vertex attribute (an X3D
`FloatVertexAttribute`, two floats): the sector's light level and a kind,
`DoomLightWall` plus Doom's "fake contrast" (-1 for east-west walls, +1 for
north-south ones), `DoomLightPlane` for floors and ceilings, or
`DoomLightFullBright` (the sky). The colour comes from `DoomLighting`, see
"Light diminishing" below.

### Sky, collisions, switches

The sky is a textured cylinder scene that follows the camera (updated every
frame in `Update`). Doom maps 1024 sky columns around a full turn, so the
256-wide texture repeats 4 times. Vertically texture row R sits at the slope
(100 - R) / 160 from the eye (Doom's `skytexturemid` 100 and 160-pixel focal
length), the texture repeats downwards (Doom wraps it below the horizon) and
row 0 is stretched upwards. It is full bright (only the invulnerability
colormap changes it). Sky ceilings and sky floors are simply not drawn; sky
floors get collision triangles in the invisible collision scene.

### Light diminishing (`DoomLighting`)

Doom lights a pixel by choosing one of 32 colormaps from `COLORMAP`
(r_main.c): the sector light gives `lightnum = light / 16` (+1 / -1 fake
contrast on walls, + the gun flash's `extralight`), the start colormap is
`(15 - lightnum) * 4`, and the nearer the pixel the brighter the colormap:

- walls and sprites by their projected scale: index `min(2560 / depth, 47)`
  (2560 = 160, the projection of a 320-pixel view, << 4), colormap
  `start - index / 2`;
- floors and ceilings by distance: index `min(depth / 16, 127)`, colormap
  `start - (160 / (index + 1)) / 2`;
- full-bright frames and the sky: colormap 0.

`DoomLighting` does this per pixel as a CGE shader effect (`TEffectNode` with
a vertex and a fragment `TEffectPartNode`). The vertex part writes the eye
depth (`-vertex_eye.z`, in Doom units since the world is not scaled; the
camera's 90 degree horizontal field of view is Doom's) and the light into a
varying; `PLUG_fragment_modify` computes the colormap with Doom's integer
steps and then looks the colour up in the real `COLORMAP`: the lit pixel is
rounded to 6 bits per channel and finds its `PLAYPAL` index in a 512x512
lookup image (`doom_index_lut`; cell (r + 64 (b mod 8), g + 64 (b div 8)),
exact palette colours first, the nearest palette colour elsewhere), and that
index and the colormap pick the colour from a 256x34 image of the
`COLORMAP` rows through `PLAYPAL` (`doom_colormap_lut`). `TDoomGraphics`
builds both from the WAD (`MakeLuts`) and serves them as
`doomgfx:/lut/index<n>.tga` / `colormap<n>.tga`; each effect gets fresh
nearest-filtered texture nodes with those URLs. `PaletteMapped := false`
(demo command `PALMAP`) goes back to multiplying the colour by
`(32 - colormap) / 32`, the old approximation. Map geometry gets a `GeometryEffect` in each scene root and reads
the `doom_light` attribute; each `TSpriteBatch` scene has one `SpriteEffect`
whose `doom_sprite` uniform holds the scene's light group and kind (normal,
full bright, or fuzz, which leaves the spectre's black alone), and
`TSpriteGroup.ShapeFor` sets it on each shape's `Appearance.effects`
(a group effect in the root would do as well now that the quads are merged
by the game itself).

Uniforms shared by all effects (`doom_extra_light`, `doom_fixed_colormap`,
`doom_diminish`) live on every effect node; `DoomLightingInstance` keeps a
list of them (removed again through `AddDestructionNotification`) and sends
a changed value to all. `TViewPlay.Update` sets `ExtraLight` from
`Player.ExtraLight` (A_Light1 / A_Light2 of the flash frames) and
`FixedColormap` from `TDoomWorld.FixedColormap` (R_SetupFrame: the inverted
greys of invulnerability, `COLORMAP` row 32, colormap 1 for the light amplification visor, both
blinking in the last 4 seconds). `F` switches diminishing off (each sector
then gets colormap `start / 2`). The player's weapon is a 2D image control,
lit with `WeaponColormap` (`spritelights[MAXLIGHTSCALE - 1]` of the player's
sector), or the fixed colormap: `TDoomGraphics.ColormapCopy` maps the patch
through that `COLORMAP` row on the CPU (a new copy only when the frame or the
level changes); the flash image uses row 0 (full bright) or the fixed one.
Without the palette mapping (`PALMAP`) the image's colour is multiplied
instead.

Two-sided lines flagged impassable (fences, ledges) get invisible quads in a
dedicated collision scene (`Visible = false`, `Pickable = false`,
`Collides = true`).

Switch textures get a private batch per line, so `FlipSwitch` can change
just that wall's node URL (log `Switch: line N: A -> B`).
`TDoomGraphics.SwitchPartner` names the other texture: vanilla's
`SW1xxx` / `SW2xxx` pairs, or the pairs of a Boom `SWITCHES` lump
(`ParseSwitchesLump`, up to the game's episode number: 2 for Doom 1,
3 for Doom 2), which then replaces the rule.

---

## 7. DoomThings and DoomActors: sprites as billboards

`DoomThings` is Doom's `info.c` reduced to what the port needs: for each
`THINGS` type number, the sprite prefix, radius, height, whether it blocks,
hangs from the ceiling or floats, idle/move/attack/pain/death frame letters,
health, speed, pain chance, attack kind, damage dice, pickup kind and sounds.
`PickupMessage` has the original messages.

A `TDoomActor` is a `TCastleTransform`; its quad is not drawn by a scene
of its own but by a `TSpriteBatch`: one `TCastleScene` per light group
(sector light div 16, what the shader rounds to) and kind (normal, full
bright, fuzz), and in it one `TSpriteShape` per sprite texture holding the
quads of every thing showing that texture (four vertices and six indices a
quad; the `TTexturePropertiesNode` has `GuiTexture`: no power-of-two resize
and no mipmaps, nearest filtering, since resizing hundreds of odd-sized
sprites on the CPU made the web build crawl). So a draw call is a texture in
a light: E1M1 at the door draws 35 sprite draw calls in 9 scenes instead of
104 scenes of one quad each. The shapes persist: `UpdateMembership` moves a
thing's quad between shapes when its frame, light group or visibility
changes (the last quad of a shape takes the freed slot), only a texture new
to a light group adds a shape to the scene (`ShapeFor`, a `ChangedAll`;
it calls `BeforeNodesFree` first because CGE's `ChangedAll` leaves its
`TransformationDirty` list pointing at the freed shape tree, which crashed
the next frame), and `TSpriteBatch.Flush` sends the frame's coordinate and
index changes once per world update. The actor's own child `TCastleScene`
holds an invisible copy of the quad for collisions and picking
(`FScene.Visible := false`, a `TCastleBillboard` turns it); the drawn quad
is written in world space each tic (`WriteCorners`, skipped when nothing
moved) along `TSpriteBatch.Right`, the horizontal axis for the view angle
the world sets each tic, like Doom's screen-aligned sprites. CGE's dynamic
batching was tried first and dropped: it merges 8 textures a pass, and its
pool shapes switching appearances every frame relinked the per-scene
sprite shaders continuously (the program cache frees a program at its last
reference), 40 ms a frame in the browser. The quad's size and position
come from the patch's width, height and offsets (Doom's origin is at the
feet). `UpdateRotation` picks one of the 8 rotation sprites with Doom's
formula `(angle_to_thing - thing_angle + 202.5°) / 45°`, and `ApplySprite`
sets the quad's coordinates (mirrored if needed) and the texture node's URL.
Spectres (`Fuzz`, Doom's `MF_SHADOW`) get `AlphaMode = amBlend` and the
fuzz kind in `doom_sprite`: the `DoomLighting` shader replaces each opaque
texel with black whose opacity follows `R_DrawFuzzColumn`'s `fuzzoffset`
table (`FuzzOffsets`, 50 entries; 0.7 where Doom would copy the pixel from
below, 0.3 from above), indexed by the screen pixel in Doom's 320x200 grain
(`doom_fuzz_scale` = view height / 200) and a start (`doom_fuzz_phase`) that
changes every tic, like Doom's never-reset `fuzzpos`. Doom itself darkens
the shifted background with colormap 6; a shader cannot read the pixels
behind, so the shift shows up as dark and light specks. The view draws the
player's weapon (and flash) the same way during partial invisibility:
`FuzzCopy` makes a black copy of the image with the same pattern, column by
column from the top, every tic (normal again in the blinking last seconds).

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

Three monsters have their own attack code, following `p_enemy.c`:

- **Lost soul** (`StartSkullCharge`, `TicCharge`): `A_SkullAttack` sends it
  at the target's middle at 20 units per tic (`Charging`, a 3 s safety
  limit). Each tic it checks the player and every solid monster in its path
  and slams the first one for 3d8 (`PIT_CheckThing` with `MF_SKULLFLY`); a
  wall stops it (`TryMove2D` fails); floors and ceilings bounce it
  (`P_ZMovement`); any damage taken stops the charge. It charges from range
  like a missile attacker, with half the distance in the range check.
- **Pain Elemental** (`PainShootSkull`): `A_PainAttack` spawns a lost soul
  `4 + 3 * (31 + 16) / 2` units ahead and starts its charge at once; nothing
  spawns when more than 20 souls are alive, and a soul whose spot is blocked
  dies immediately. `A_PainDie` releases three souls at +90, +180 and +270
  degrees. (Vanilla can spawn souls through walls; a sight check refuses it.)
- **Arch-vile** (`VileTryRaise`, `VileStartAttack`, `FollowVileFire`,
  `VileAttack`): while chasing, a corpse within reach (radii + speed) whose
  spot is free is raised: the vile plays its heal frames `[`, `\`, `]` with
  `DSSLOP`, and the corpse plays its death frames backwards (as `asPain`)
  and returns at full health. Cyberdemons, spiders, lost souls, viles, Keen
  and the boss brain cannot be raised. The attack (frames G to P, 9 tics
  each, only within 14x64 units) lights a `FIRE` effect that stays 24 units
  in front of the target; on frame O, if the vile still sees the target, the
  target takes 20 damage, the fire jumps between them and explodes for 70
  (`RadiusDamage` blamed on the vile), and the player is thrown about 50
  units up (`PlayerKnockUp`, applied by the view under the ceiling).
- **Icon of Sin** (`BrainAwake`, `TicBrainShooter`, `BrainSpit`,
  `TicSpawnCube`, `StartBrainDeath`, `TicBrainDeath`): the shooter (89) and
  the spawn spots (87) are `tkBossSpot` things, kept as hidden actors so the
  save code handles them like any other. The shooter wakes when it sees the
  player or on any shot (`NoiseAlert`; Doom's sound flood reaches it in
  practice), plays `DSBOSSIT`, waits 181 tics and then calls `A_BrainSpit`
  every 150 tics: on skills 1-2 only every other time, the next spot in
  THINGS order gets a `BOSF` cube (`ekSpawnShot`, speed 10, no clipping)
  whose `Target` is the spot and whose `ReactionTics` is the flight time.
  On arrival the cube becomes `FIRE` (`ekSpawnFire`, `DSTELEPT`) and a
  monster picked with `A_SpawnFly`'s table (imp 50/256, demon 40, spectre
  30, pain elemental 10, cacodemon 30, arch-vile 2, revenant 10,
  arachnotron 20, mancubus 30, hell knight 24, baron 10); `P_TeleportMove`
  on MAP30 telefrags whatever stands there, the player included. The brain
  (88) is a monster with speed 0, pain chance 255 (`BBRN` B for 36 tics,
  `DSBOSPN` at full volume) and no kill count; rockets reach it with splash
  damage through the opening in its wall. Its death (`A_BrainScream`)
  spawns a row of `MISL` explosions 320 units in front of it, more every
  other tic, `DSBOSDTH`, and 120 tics later requests the normal exit.

Monsters sleep until they notice the player. Every shot calls `NoiseAlert`
(`P_NoiseAlert` / `P_RecursiveSound`): starting at the player's sector, the
sound crosses every two-sided line whose opening is above zero (a closed
door stops it) and an `ML_SOUNDBLOCK` line only if it has not crossed one
yet; every sector reached is flagged in `FSectorSound` (Doom's
`soundtarget`) for the rest of the level, and the flags are saved. Doom
recurses; a work list with "revisit only with fewer blocks" gives the same
set without deep recursion. Idle monsters run `MonsterLook` (`A_Look`)
every 10 tics: a flagged sector wakes them at once, but an `MTF_AMBUSH`
monster also needs a line of sight; otherwise `P_LookForPlayers` applies:
the player must be within 90 degrees of the monster's facing (or within 64
units) and visible (`CheckSight`, `P_CheckSight`: the `REJECT` bit for
the two sectors, then every line crossed by the 2D segment: a one-sided or
closed line blocks, and a two-sided one narrows the vertical window seen
from the eye at 3/4 of the viewer's height, top and bottom slopes being
height differences per whole distance, until they meet; the lines can be
taken in any order, so there is no BSP walk). `SightClear` (2D only)
remains for the Pain Elemental's spawn spot. Awake, they chase with Doom-style 2D movement (`TryMove2D`:
one-sided and blocking lines, openings too low, steps higher than 24, drop-offs
unless floating, other solid things, the player), try other directions when
blocked, open doors in their way, set off the walk-over lines Doom allows
monsters (`MonsterCrossLines`: door raise 4, lifts 10 and 88, teleporters 39
and 97 and the monster-only 125 / 126, checked against a per-map list of
such lines after every step; `TeleportActor` moves them to the tagged
sector's teleport destination with fog at both ends and refuses while the
spot is occupied, except on MAP30 where monsters telefrag), and attack when close (melee), when they
have line of sight (hitscan: `MonsterHitscan` turns to the target, takes
the slope to its middle when `SightToTarget` passes, and traces every pellet
with Doom's random spread through `TraceLineAttack`, a Doom-units line
attack that stops at the first wall, opening edge or body, so monsters in
the way are hit and walls get puffs), or by spawning
a projectile actor (`SpawnMissile`: imp, cacodemon, baron, cyberdemon,
revenant, mancubus, arachnotron). Projectiles fly as actors (`TicMissile`),
explode on walls, floors, ceilings or the player, with splash damage for
rockets. Damage applies pain (chance from the table) or death (death
sequence, then a corpse that no longer collides); zombies drop ammo; barrels
explode with radius damage.

**Weapons** shoot like Doom's p_pspr.c, in Doom units, from 36 units above
the player's feet (`P_LineAttack`'s `z + height / 2 + 8`). `PlayerAim` is
`P_BulletSlope`: `AimLineAttack` (`P_AimLineAttack` / `PTR_AimTraverse`)
collects the lines and shootable bodies along the player's angle over 1024
units, sorts them by distance and walks them, narrowing the slope window
(-100/160 .. 100/160, Doom's view) at every floor or ceiling step of an
opening and stopping at one-sided lines and closed doors; the first body
whose visible part is in the window gives the slope to its middle. Doom
tries straight ahead, then 5.625 degrees to each side. Bullets keep the
player's angle with that slope; without a target the slope follows the
camera's pitch (0 without mouse look, as in Doom). `PlayerLineAttack` traces
the shot with `TraceLineAttack` (shared with the monsters), damages the
body or puffs the wall, and shoots every gun-activated line the shot
crossed (`PTR_ShootTraverse`). Pistol and chaingun are accurate on the first
shot and spread +-5.6 degrees when the trigger is held, the shotgun's 7
pellets spread +-5.6 degrees, the super shotgun's 20 +-11.2 degrees and in
slope; damage is 5, 10 or 15 per bullet. Fist and chainsaw aim and trace
over 64 / 65 units (2..20 damage, the fist x10 with berserk; the saw plays
its hit sound only when it hits). `DebugShots` (demo command `SHOTS`) logs
every shot. The rocket launcher, plasma gun and BFG spawn real projectile
actors (`SpawnPlayerMissile`: `MISL`, `PLSS`, `BFS1` sprites) with the same
autoaim (`P_SpawnPlayerMissile` turns the missile to the angle that found
the target), 32 units above the feet; they hit monsters and barrels
(`FromPlayer` missiles never hit the player), and explode on walls, floors
and ceilings;
rockets add 128-unit splash damage, the BFG ball launches after Doom's 40-tic
charge and on impact sprays 40 tracers over 90° from the player (`BfgSpray`,
15d7 each, with the green `BFE2` flash on every target). Weapon animation
runs from the state table: `BuildWeaponSeqs` walks each weapon's attack
and flash chains (`DoomStates.Weapons`, d_items.c's weaponinfo, which
DeHackEd's "Weapon N" edits) at map load; `FireWeapon` starts the attack
sequence and `AdvanceWeaponFrames` runs the action of each frame as it is
reached (`WeaponAction`: A_FirePistol, A_FireShotgun2, A_FireMissile,
A_FireBFG..., the SSG's open / load / close sounds, A_ReFire restarting
the attack while the trigger is held), so the shot falls on the frame
that carries the code pointer and a patched pointer changes what the
weapon fires. The flash sequence's A_Light1 / A_Light2 / A_Light0 set
the extra light. The projectiles' speed, size, damage dice, sounds and
frames come from their mobjinfo rows (`SyncProjectileInfos`).

The player record (`TPlayerState`) holds health, armour, ammo, weapons, keys,
powerup timers, messages, screen-flash intensities and the status-bar face
state.

---

### Save games

`TDoomWorld.SaveState` (`doomworld_save.inc`, included into `doomworld.pas`
so it can read private fields) returns the whole level as a `TJSONObject`
(FPC's `fpjson`, the same library CGE's component serializer uses, so it
compiles for the web too):

| Part | Saved as |
|---|---|
| map, tic, BFG countdown, player start | scalars |
| player | health, armour, ammo and max ammo, weapon and key bitmasks, stats, powerup timers, position, angle |
| sectors | parallel arrays: floor, ceiling, light, original light, special, floor and ceiling flats |
| linedefs | special (one-shot specials are cleared after use) and flags (`ML_MAPPED` automap reveal) |
| sidedefs | only the ones that differ from the WAD (flipped switches): `[index, upper, lower, middle]` |
| movers | every field of each active `TSectorMover` |
| switch and light timers | arrays |
| actors | type number or effect kind, sprite prefix, position, state, health, AI and missile fields, collision flags, animation (`TDoomActor.GetAnimation`), and `target` / `shooter` / `fire` as indexes into the saved list |

`LoadState` calls `LoadMapCore` with the JSON: the map is parsed from the
WAD, dynamic sectors are computed from the *original* specials (a cleared
one-shot special may still have a moving sector), the sector / line / side
state is applied **before** `TDoomGeometry` builds the scenes (so walls,
flats and switch textures come out right), `SpawnThings` is skipped, and
`RestoreDynamicState` recreates the player, movers, timers and actors and
then resolves the actor references. The view adds the camera (position,
direction including pitch, up), level time, the WAD list and a description,
and writes compact JSON through `GameSaveStorage` to `castle-config:/save1..6.json`
or `quicksave.json`; `ReadSaveFile` reads it back and parses with `GetJSON`.
Loading refuses a save made with a different IWAD / PWAD set. The title
screen's "Continue (quick save)" and `-loadgame N` load the save's WADs
first, then hand the URL to the play view (`PendingSaveUrl`).

On the desktop `castle-config:` is the user config directory (next to the
log) and `GameSaveStorage` uses `UrlSaveStream` / `Download`. In the browser
CGE maps `castle-config:` to an in-memory file system that disappears on
reload, so under `{$ifdef WASI}` the unit talks to JavaScript instead: JOB
(FPC's `job.js` WebAssembly-to-JS object bridge, which CGE's web target
already uses for WebGL and the DOM) gives `JSWindow` from
`CastleInternalJobWeb`; `ReadJSPropertyObject('localStorage', TJSObject)`
returns the `Storage`, `setItem` stores the JSON under
`castle-doom:` + the URL, and `getItem` is read with `InvokeJSValueResult`
because it returns `null` for a missing key (the typed string call raises
on `null`). If `localStorage` throws (blocked storage) the code falls back
to the in-memory `castle-config:` and logs a warning. Six slots plus the
quick save are under 1 MB, well inside the usual 5 MB per origin.

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

## 10. DoomMusic: MUS/MIDI on an OPL3

The engine has no MIDI playback, and Doom music was never recorded audio: it is
note data (MUS, or plain MIDI in Freedoom) played on the sound card's Yamaha
OPL2 FM chip using the instrument bank in the `GENMIDI` lump. `DoomMusic`
recreates that pipeline in software, with the chip itself emulated by Nuked
OPL3 when its shared library is there (`DoomOpl3`: `data/lib/libnukedopl3.so`
/ `nukedopl3.dll` / `libnukedopl3.dylib`, built from the LGPL sources by
`tools/build_nuked_opl3.sh` and never compiled into the MIT program; loaded
with `DynLibs`, three entry points: `OPL3_Reset`, `OPL3_WriteReg`,
`OPL3_GenerateStream`) and by the built-in FM model otherwise (the web build
always: no dynamic linking in WebAssembly; `--fm-synth` forces it):

1. `ParseMus` / `ParseMidi` turn the lump into a time-stamped event list
   (note on/off, program, volume, expression, pitch bend). MUS runs at 140 Hz
   with channel 15 as percussion; MIDI tracks are merged by tick and converted
   to seconds through the tempo map. The merge uses a hand-written stable
   merge sort because `Generics.Defaults` comparer types differ between FPC
   3.2 and the main branch used for WebAssembly.
2. `LoadGenMidi` reads the 175 instruments (128 melodic, 47 percussion), each
   with up to two voices of modulator/carrier parameters, feedback/connection,
   note offset, fine tuning, fixed pitch.
3. `TSongRenderer` owns the events, the channel state, the timeline and the
   WAV writer (`RenderDoomSong` renders a whole song at once;
   `NewSongRenderer` picks the subclass). `TOplSongRenderer` drives the
   emulated chip like Doom's DMX driver: OPL3 mode (register 0x105) for 18
   two-operator channels, one per GENMIDI voice (two for double-voice
   instruments, the second detuned by the fine tuning); a note writes the
   instrument's operator bytes to 0x20 / 0x40 / 0x60 / 0x80 / 0xE0 of both
   slots, feedback and connection to 0xC0 (with both output bits), the
   carrier's total level attenuated by velocity, channel volume and
   expression (0.75 dB per step; the modulator too when the operators add),
   and the F-number / block for the note's frequency (with the channel's
   pitch bend) to 0xA0 / 0xB0 with key on. Note off clears key on (the
   release runs on the chip) and frees the voice; the oldest voice is
   stolen when all 18 play. Samples come from `OPL3_GenerateStream` at the
   song's 22050 Hz (the chip resamples from its 49716 Hz), rendered between
   events. `TFmSongRenderer` is the built-in model: up to 36 voices, each two operators
   with 32-bit fixed-point phase accumulators, 2048-entry wave tables for the
   four OPL waveforms, ADSR envelopes with YM3812 timings and rate scaling,
   key-scale level, total level, feedback (up to 2 cycles of phase), FM
   modulation (up to 4 cycles), vibrato and tremolo LFOs updated every 32
   samples. Output is 22050 Hz mono with one fixed gain for every song
   (Freedoom's tracks peak at 3.4 .. 8 in synth units; 5.5 maps to 0.89)
   and a soft limiter above 0.7, written as WAV.
4. The `doommus:` protocol serves `doommus:/D_E1M1.wav`; a `TCastleSound` with
   that URL is assigned to `SoundEngine.LoopingChannel[0]`, the engine's
   music channel, which loops it.

Rendering a 2-minute track takes a few seconds natively (Nuked OPL3; about
a second with the FM model) and longer in WebAssembly, so it is not done in
one go: `TDoomMusic.Update` (called every frame by both views) renders 2048
samples at a time for at most `RenderBudget` (12 ms) per frame, 40 ms while
a song's first seconds are awaited (`StartIntro` asks for them, nothing
plays yet); `TryStartIntro` plays the first 8 seconds as `D_XXX_INTRO.wav`
as soon as they are rendered (about 10 frames, no stall; rendering them at
once in `Play` was 100-300 ms), and the finished song then takes over at
the same position
(`TCastlePlayingSound.InitialOffset` = time since the intro started, looping,
priority 1). The fixed gain is what makes the two identical where they
overlap; per-song normalization would need the whole song first. When a song is queued, the
intermission track is queued after it, so it is ready at the level's exit,
and `GameViewPlay` then queues the next map's song (`Prefetch`), so the next
level plays it at once with no intro to synthesize; a prefetch in progress
gives way to a song that is needed now. Finished songs stay in memory
(`FReady`, served by `ReadMusic`) while they are the current, the
intermission or the prefetched one; `ReleaseUnneeded` frees the others (and
their `TCastleSound`) on every `Play` / `Prefetch`. Set the environment variable
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

The finale (`doomfinale.pas`, `f_finale.c`) is a third such screen. Doom 1
goes to it straight from ExM8 (`G_DoCompleted` skips the intermission
there); Doom 2 after the intermission of MAP06, 11, 20, 30 and the secret
exits of MAP15 and MAP31 (`G_WorldDone`). Stages: the text typed over a
tiled flat from (10, 10) with 11-pixel lines at 3 tics per character (a key
completes it, a second key moves on; Doom 1 also moves on 250 tics after the
text); the end picture (`CREDIT` or `HELP2`, `VICTORY2`, `ENDPIC`); the
bunny scroller (`PFUB2` sliding off to `PFUB1` from tic 230 at half a pixel
per tic, then `END0`..`END6` from tic 1130 with pistol clicks; Freedoom's
END patches carry offsets that put "TO BE CONTINUED..." in the corner);
and the cast call on `BOSSBACK`: the 17 members in Doom's order, drawn
front-facing at (160, 170) with their walk frames, an attack every 12
frames, the death frames on a key, then the next one, the name centred at
y = 180. After a Doom 2 text the view loads the next map; after the end
picture, the bunny or the cast (Esc) it returns to the title.

A PWAD's UMAPINFO lump (`DoomMapInfo`, read by `LoadMapInfo` when the
play view starts, after DeHackEd) is asked first everywhere these tables
are: `NextMapName` (`next`, `nextsecret`, which falls back to `next`),
`TDoomStrings.LevelName` (`label: levelname`, `label = clear` for the
name alone), `ParTime`, `TDoomMusic.LumpForMap`, `SkyTextureName` and
the intermission's name picture (`levelpic`; a renamed level without
one shows none rather than the vanilla level's). When an entry sets a
story text (`intertext` / `intertextsecret`, `clear` removes a default
one) or `endgame = true`, `MapInfoDecidesFinale` is true: the text comes
after the intermission in Doom 1 too, on `interbackdrop` (a flat) with
`intermusic`, then the game ends with `endpic`, `endbunny` or `endcast`,
or goes on to the next map. `endgame = false` turns a Doom 1 ExM8 into
an ordinary exit, `nointermission` skips the stats screen. `episode`
entries extend (or, after `episode = clear`, replace) the New Game
episode list (`TDoomMenuScreen.SetupEpisodes`, built after vanilla's
ExM1 / `M_EPIn` episodes; a missing patch shows the name as text) and
`EpisodeMap` gives the start map. `bossaction` entries replace a map's
vanilla `BossDeath` table: the last monster of the type runs the line
special on the tag through line 0. Patch backdrops are not supported.

The texts are not in Doom's WADs but in the executable; Freedoom puts its
own (BSD-licensed) story, background flats and cast names in a `DEHACKED`
lump as Boom BEX strings (`E1TEXT`, `C1TEXT`, `BGFLATE1`, `BGFLAT06`,
`CC_ZOMBIE`...). `TDoomStrings` (`doomdehacked.pas`) reads every
`DEHACKED` lump in load order (a PWAD's override the IWAD's), keeps only the
`[STRINGS]` section, joins lines ending in a backslash and turns `\n` into
newlines. Without a text (an IWAD with no `DEHACKED`) the text stage is
skipped; flats fall back to vanilla's, cast names to Doom's.

The same `TDoomStrings` (one per WAD set, created by each view) feeds the
other texts: `TDoomWorld.Text(Key, Default)` for pickup messages
(`PickupMessageKey` maps every pickup to its `GOT*` name) and locked
doors / switches (`PD_BLUEK` / `PD_BLUEO`...), `LevelName` for the title
shown when a level starts and at the bottom left of the automap
(`HUSTR_E1M1`, Doom 2's `HUSTR_1`), the automap's `AMSTR_GRIDON/OFF`, and in
the title menu the `NIGHTMARE` question and the quit question (a random
`QUITMSG`..`QUITMSG14` plus `DOSY`, `M_QuitDOOM`). Every call passes the
vanilla text as the fallback. Player messages are also logged
(`Message:`), which the tests use.

The weapon sprite and muzzle flash are two more `TCastleImageControl`s placed
with Doom's formula (`x1 = centerx + (1 - 160 - leftoffset) * scale`,
`WEAPONTOP = 32`) and bobbed with the camera speed. A weapon change goes
through `TDoomWorld.ChangeWeapon`: `Player.WeaponSwitch` 1 lowers the sprite
by 6 Doom pixels per tic (`WeaponOffset`, added to `WEAPONTOP`) once the
current attack has finished, swaps in `PendingWeapon` at 96, then 2 raises
it back to 0 (`A_Lower` / `A_Raise`); `FireWeapon` refuses meanwhile and the
bob stops. Every level starts at 96 (raising).

The screen melt (`doomwipe.pas`, `f_wipe.c`): `TViewPlay.BeginWipe` renders
the old screen into a GPU texture and keeps it there: a `TDrawableImage` of
the window size, `RenderToImageBegin` (an FBO with the texture as colour and
a depth renderbuffer, so the 3D view renders correctly), `RenderContext.Clear`,
`Container.RenderControl(Self, ...)` for the whole view, `RenderToImageEnd`.
Nothing is read back to the CPU. That matters in the browser: CGE does not
implement pixel read-back for WebGL yet (`SaveScreen_NoFlush` has a "TODO:
web" where `glReadPixels` would be, so `SaveScreen` gives an empty image), and
an FBO with a colour renderbuffer (`TGLRenderToTexture.Buffer = tbNone`)
raised an exception there, which FPC's WebAssembly target cannot catch.
The texture goes to `TDoomWipe`, a full-size control in front of
everything whose `Render` draws it as 160 vertical strips with
`TDrawableImage.Draw(ScreenRect, ImageRect)`, each strip shifted down by its
own offset on the 200-line grid. `wipe_initMelt` gives every column a start
delay of 0..15 tics differing by at most one from its neighbour;
`wipe_doMelt` moves a column 1, 2, 4, 8, 16 pixels and then 8 per tic, so it
takes about a second. The level keeps running underneath (Doom freezes it).
Melts start at level → intermission (`StartIntermission`), into a finale
(`StartFinale`) and at a new map: `StartMap` captures the intermission or
finale screen before the "LOADING" frame and `LoadPendingMap` starts the
melt once the level is in. The frame that starts a melt does not advance it
(it can contain a whole level load), later frames follow real time with at
most 8 tics per frame, so a slow first second in the browser gives a short
melt rather than a long one. The screen tints follow
`ST_doPaletteStuff`: `TDoomWorld.PaletteIndex` picks PLAYPAL palette 1..8
(red, from `DamageCount` or the fading berserk), 9..12 (gold, `BonusCount`)
or 13 (radiation suit), and one full-size `TCastleRectangleControl` draws it.
Doom's palettes are palette 0 blended towards a single colour, so
`TDoomWad.PaletteTint` recovers that colour and the blend amount from the
black and white entries (Freedoom: red 1/9..8/9, gold 1/8..4/8, green 1/8),
and an alpha-blended rectangle reproduces the palette shift exactly. The
help panel is a `TCastleLabel`.

Key bindings: `GameSettings.Keys` holds two keys per `TGameAction`
(forward, backward, strafes, turns, run, fire, use, automap; JSON
`keys` with `KeyToStr` names). `TViewPlay.ApplyKeyBindings` assigns the
walk navigation's `Input_Forward`... from them and rewrites the help
panel's first lines when they differ from the defaults; `Press` fires,
uses and toggles the automap through `KeyIs`, and stops at any other
bound key, so a key taken by an action no longer runs the fixed hotkey
(F, M, the weapon digits) it shadows. The gamepad keeps its own layout
(A use, View automap). The title screen's Controls page
(`ControlsPanel`, a row per action built in `BuildControlsRows`) binds
the next key pressed through `BindKey`, which takes the key away from
any other action and refuses Escape and the function keys.

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
`TDoomMusic`), plays the title track and shows Doom's menu,
`TDoomMenuScreen` (`doommenu.pas`). Its screen is the design
`data/menu.castle-user-interface` (`DesignUrl`): the black background,
the menu screen, the Options panel (a `TCastleVerticalGroup` of rows of
`TCastleButton`s and `TCastleLabel`s named `ButtonPhase1`, `MapLabel`...)
and the Phase 2 download line; `Start` takes them by name and assigns
the click handlers and the run-time texts. Like the status bar and the intermission
it composes a 320x200 `TRGBAlphaImage` (dimmed `TITLEPIC`, then `M_*`
patches drawn with their offsets like `V_DrawPatch`) and shows it 4:3 with
`SmoothScaling := false`; it is recomposed only when something changes (the
skull blinks every 8 tics). Pages and positions are `m_menu.c`'s: main
(`M_NGAME`, `M_OPTION`, `M_LOADG`, `M_QUITG` at 97,64), episodes (only for
ExMy WADs that have `M_EPIn`), skill (`M_JKILL`..`M_NMARE`, Nightmare asks
"are you sure" in the STCFN font), and Load Game (the `M_LS*` border and
each save's description). Keys come from the view (`HandleKey`: arrows,
Enter, Escape / Backspace, Y / N); the control handles mouse hover and click
itself by mapping the pointer through its `RenderRect` into Doom pixels.
Chosen actions come back through `OnAction` (new game with episode and
skill, load slot, options, quit).

"Options" shows the CGE part: buttons (`TCastleButton` in
`TCastleHorizontalGroup`/`TCastleVerticalGroup` on a `TCastleRectangleControl`)
to pick Freedoom Phase 1 or 2, the map and the skill, "Open IWAD..." and "Add
PWAD..." using the window's native `FileDialog` (desktop only), a "Last WADs"
shortcut backed by `UserConfig` (`castle-config:`) and "Continue (quick
save)". The command line accepts Doom's `-iwad FILE`, `-file PWAD...`,
`-warp MAP` and `-skill 1..5`.

The skill reaches `TDoomWorld.Skill` (0..4 like `gameskill`) through
`TViewPlay.Skill`. `SpawnThings` picks the `MTF_EASY` / `MTF_NORMAL` /
`MTF_HARD` flag from it; `GiveAmmo` doubles ammo on skills 0 and 4,
`DamagePlayer` halves damage on 0; Nightmare makes imp / cacodemon / baron
balls fly at 20, demons walk twice as fast, removes the wake-up reaction
delay and the pause after an attack, and `NightmareRespawn` brings corpses
back at their map spot (`SpawnX`/`SpawnY` in `TDoomActor`) after 12 seconds
with a 4/256 chance every 32 tics, with teleport fog at both ends. The skill
and the spawn spots are part of the save. Starting hands
the WAD objects to `TViewPlay` and sets `Container.View`. (A view cannot
change the container's view from inside its own `Start`; the autotest path
uses `WaitForRenderAndCall` for that.)

`TViewPlay` has `DesignUrl = castle-data:/play.castle-user-interface`:
CGE loads that design before `Start` and inserts its root into the view.
The design is the whole 2D layer, in drawing order: the automap, the
palette flash rectangle, the weapon and its muzzle flash, the status bar
(`TDoomStatusBar`), the crosshair, the message / click prompt / automap
title texts (`TDoomFontText`), the info and help labels, the
`TDoomWorldStatus` entry for the inspector, the intermission and finale
screens, the loading text, Doom's in-game menu on its dark panel
(`TDoomMenuScreen`) and the screen melt (`TDoomWipe`). The game's own
controls are registered with `RegisterSerializableComponent` in their
units' `initialization` (needed to load the design, and what lets the CGE
editor place them; `editor_units` in `CastleEngineManifest.xml` lists the
units, so "Restart Editor (With Custom Components)" builds an editor that
knows them). `CreateUi` creates in code what is not layout: the
`TCastleViewport` with a `TCastleCamera` (90° horizontal field of view,
near plane 4 units), inserted behind the design, and the
`TCastleWalkNavigation`; it takes the design's controls by name
(`DesignedComponent`) and wires the run-time parts (the WAD graphics into
the status bar and texts, the menu's `OnAction`). A control that needs the
WAD renders nothing without it, so the design opens in the editor as
boxes. It then calls `StartMap`, which shows a "Loading" overlay
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
  cleared,
- `UseGameController` for the sticks. Gamepad buttons become the keys of
  the same actions in `GameGamepad` (`GamepadKey`: A use, View automap,
  Menu Esc; in menus the D-pad, A and B are the arrows, Enter and Esc),
  the bumpers step the weapon and the right trigger fires while held.
  CGE reads controllers on Windows and Linux; in the browser
  `GameGamepad` polls `navigator.getGamepads()` through JOB every frame
  (`ApplicationProperties.OnUpdate`) and feeds CGE's explicit controller
  backend (`TExplicitControllerManagerBackend`: count, axes, triggers,
  buttons of the Gamepad API's standard mapping, Y flipped so forward is
  positive), so the views see the same `TGameController` events.

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

`--fixed-step` (autotests of moving scenes) caps every frame at one tic
of game time, keeps frames at least that long and seeds `Random` at each
map load, so those runs are reproducible frame by frame.

`tools/run_autotests.py` also compares 35 screenshots with the
golden references in `tools/golden/` (320x180, from software GL;
`--update-golden` rewrites them from a run's output directory): more
than 1.5 % of the pixels off by more than 40 fails the `golden` row and
leaves `golden-diff-NAME.png`.

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
level, `N` next map, `SAVE:n` / `LOAD:n` save or load slot n (0 = quick
save), `MENU:n` open the save (1) or load (2) slot menu (0 closes it),
`K` give all weapons/ammo/keys, `Y` god mode,
`P:type:dist` spawn an awake monster of that THINGS type in front,
`C:n` select weapon n,
`M` toggle automap, `I` reveal all map lines, `Z:f` zoom the automap by f,
`V` make every monster fight the nearest other species, `D` kill all monsters
(boss triggers), `S` screenshot (`PREFIX_n.png`), `W:sec` wait, `Q` quit.
The log (`%LOCALAPPDATA%\castle-doom\castle-doom.log` on Windows) records
map/geometry/thing load times, music render times, and every screenshot with
the player position.

---

### A level as a component

`TDoomMapTransform` (`doommaptransform.pas`) is a `TCastleTransform` with
published `Wad`, `MapName` and `Things`. Setting them marks it dirty and
its next `Update` builds the level: `TDoomWad`, `TDoomGraphics`,
`TDoomMap`, a `TDoomGeometry` with every sector static (one chunk; the
atlas and the lighting effects as in the game) under a `Map` child, the
things as `TDoomActor`s in a `TSpriteBatch` under `Things` / `Sprites`.
Each `Update` turns the sprites to the viewport's `MainCamera` and
advances their idle frames at 35 tics a second. Errors are checked, not
raised (an absent WAD or map logs a warning and leaves the component
empty), so it works in the editor and on the web. `StartEye` /
`StartDirection` give a camera the player start. The design
`data/mapcomponent.castle-user-interface` (a viewport, a camera and the
component on E1M1) is what `--autotest MAPCOMPONENT` (`GameViewDesign`)
shows and screenshots, and what the editor shows for the same file.

### The engine's inspector

F8 opens Castle Game Engine's inspector in every build (`GameInitialize`
sets `TCastleContainer.InputInspector.Key`; the engine itself registers
the key only in debug builds). What it shows is arranged for it: the
viewport's items are grouped under `Map` (`Chunk<n>_Solid` /
`_Passable`, `LineCollision`, `Sky`), `Things` (each `TDoomActor` is
named `<SPRITE>_<serial>` and publishes `ThingType`, `SpriteName`,
`CurrentFrame`, `ActorState`, `HitPoints`, `IsAwake`, `DoomPositionX/Y/Z`,
`DoomSector`, `ActionName` (the frame's code pointer), `TicsLeft`,
`TargetName` (`player` or another thing's name) and `ReactionTime` for
the properties pane) and `Sprites` (the batch
scenes `SpritesLight<n>[_Bright|_Fuzz]`); the views and their controls
carry names, and `TDoomWorldStatus` (an invisible control in the play
view) publishes the map, tic, player health, armor, position, angle,
kills, items, secrets, thing and sector counts. The demo command
`INSPECTOR` sends F8, so an autotest can screenshot it.

The inspector's F9 "auto-select Transform" picks the monster or barrel
under the mouse (the screen's centre with mouse look): a thing's
invisible collision quad is pickable and transient, so the ray's path
yields the `TDoomActor` itself; the map chunks' `_Passable` scenes (no
precise collisions, so a ray would hit their whole bounding box) are not
pickable. The demo command `SELECT` does the same from the camera
(`TViewPlay.SelectInInspector`, opening the inspector and setting its
`SelectedComponent`), `SELECT:name` picks a thing by name; both log a
`Select:` line with the state, health, action, tics left and target.

`--profile` turns on CGE's `Profiler`: `LoadMapCore` measures `Load
<map> (DoomWorld)` with the stages `Parse map`, `Build geometry` and
`Spawn things` (the engine's own scene and octree work nests inside)
and logs the tree after each load; `PROFILE` in a demo logs the whole
summary. The per-tic costs stay in the `Perf:` / `PerfView:` lines.

`CASTLE_DOOM_LOG=Load,Music` (`GameLogFilter`, desktop) writes
`castle-doom-filtered.log` next to the saves with only those categories
(the word before the first `: `), every warning and the lines that
continue a kept one. It is a copy fed from
`ApplicationProperties.OnLog`: CGE has no log filter, and the generated
`CastleAutoGenerated` unit starts the log before any game unit could
hand `InitializeLog` a filtering stream.

## 16. Platforms: desktop, WebAssembly, CI

The same code builds for Windows, Linux and the browser. `castle-engine
compile --target=web` compiles the Pascal to WebAssembly with FPC's `wasm32`
cross-compiler and a small Pas2js glue program, and packs `data/` into
`castle-doom_data.zip`; `castle-engine-output/web/dist/` is a static site.
Things that differ on the web and shaped the code:

- All loading is synchronous from the in-memory data zip, so `Download()` of
  `castle-data:` and the custom protocols work unchanged.
- Sound uses Web Audio; it needs a user gesture, which the START click is.
- Crash report: the page patch also wraps `console.log` before the
  game's script loads (keeping the last 40 lines) and shows them in an
  overlay (`castle-doom-crash`) on the window's error event, which a
  stopped WebAssembly program raises. On the desktop `GameCrash` is the
  `Application.OnException` handler: the report in the log and a
  continue / quit dialog.
- Installable: `pages/manifest.webmanifest` and the icons
  (`tools/make_web_icons.py`) are linked from both pages (the play
  page's link comes from `tools/patch_web_page.py`).
- Offline: `pages/sw.js` is the site's service worker (registered by
  both pages; the play page's registration comes from
  `tools/patch_web_page.py`). It fetches the game's own files on install,
  then serves GETs network first and keeps a copy of each, which it
  returns when the network fails.
- The render resolution option: CGE's page sizes the canvas to the
  display's pixels in a ResizeObserver; `tools/patch_web_page.py` (run by
  the Web workflow on `dist/index.html`) multiplies that by
  `window.castleDoomScale` and adds `castleDoomSetScale(percent)`, which
  `GameSettings.ApplyWindowSettings` calls through JOB. CGE sees the
  smaller drawing buffer and resizes; CSS stretches the canvas back.
  On the desktop `GameSettings.ApplyWindowSettings` also sets the frame
  rate cap (`ApplicationProperties.LimitFPS`) and v-sync, through
  `wglSwapIntervalEXT` or `glXSwapIntervalMESA` / `EXT` (CGE does it only
  on macOS).
  The other video options (`GameSettings`): the camera's horizontal
  field of view, the UI scale (CastleSettings.xml's 1600x900 reference
  size divided by it) and fullscreen (desktop only; the page has its
  own button).
- No threads, so music is rendered on the main thread (a few seconds per
  track); the "Loading" overlay is drawn first.
- Heavy pure-Pascal work is slower: PNG was replaced by TGA for textures.
- The web target needs the generated `castleautogenerated.pas` in the project
  (`castle-engine generate-program`), committed to the repository.
- CGE has no game controller backend for the browser; `GameGamepad` polls
  the Gamepad API through JOB and feeds CGE's explicit backend (section 13).

`.github/workflows/build.yml` packages Windows and Linux inside the CGE Docker
image (`kambi/castle-engine-cloud-builds-tools:cge-unstable`) and attaches
them to a GitHub Release on `v*` tags. `.github/workflows/web.yml` builds FPC's
main branch with the `wasm32-wasip1` cross-compiler and Pas2js from source
(cached by FPC commit), compiles the web target with `wasm-opt` optimization,
and deploys `pages/index.html` plus the game to GitHub Pages. It runs on
every branch and uploads the site as the `web-site` artifact; only `main`
deploys.

---

## 17. Performance notes

- Level load is dominated by texture decoding the first time a texture is
  seen; E1M1 loads in about 100 ms natively (map 2 ms, geometry 70 ms, things
  20 ms).
- Static geometry is one scene with one shape per atlas page (plus the
  switch, scrolling and animated textures); dynamic sectors are small
  scenes. Release builds run at 100+ FPS at 1600x900.
- Monster line-of-sight and movement loop over all linedefs with a bounding
  box rejection; cheap for vanilla-sized maps, but a blockmap would be the
  next step for huge maps.
- Music rendering is the slowest single step (about 1 s per track natively,
  4x more on the web). Options if needed: lower `SampleRate`, render only the
  first minute, or cache rendered WAVs.

---

## 18. Known gaps and ideas

- DeHackEd (`ApplyDehacked`, before each game's world is made): the
  `DEHACKED` lumps, then `-deh` / `-bex` files, reset and then patch the
  state table (`DoomStates.ResetStates`: "Frame N" sprite, subnumber,
  duration and next; "Pointer N (Frame M)" and BEX `[CODEPTR]` the code
  pointer) and the thing table in place (`ResetThingInfos`; "Thing N" is
  mobjinfo row N - 1: its stats go to `TThingInfo`, its frames, sounds
  and bits to `DoomStates.Mobjs`), `DehMisc`, `DehMaxAmmo` /
  `DehClipAmmo` (pickups give a clip, boxes 5, weapons 2) and `[PARS]`
  (`DehackedParTime`, used by the intermission). Then
  `ApplyStateTable` derives every thing's sequences again. "Weapon N"
  sets a weapon's ammo type and entry frames; projectile rows (things
  this port has no thing for) also take "Speed", "Width", "Height" and
  "Missile damage" (any row). "Sprite" / "Sound" renumbering, cheats
  and "Text" sections are counted as not supported.
- The state table (`DoomStates`): `tools/make_states.py` turns
  linuxdoom-1.10's `info.c`, `info.h` and `sounds.h` into
  `doomstates_table.inc` (138 sprite names, 967 states with sprite,
  frame, tics, action and next, 137 mobjinfo rows with their entry
  states, sounds, stats and flags, 109 sound names; `TStateAction` is
  every code pointer). `WalkStates` follows a chain from an entry state
  until S_NULL, a state already seen (`Loop`), another entry state of the
  same thing or a forever state (`Forever`), giving a `TFrameSeq`: per
  frame the sprite, letter, tics, full-bright bit and action.
  `DoomThings.ApplyStateTable` fills each thing's `Seqs[skIdle..skRaise]`
  (and the legacy `IdleFrames`... strings), its sprite, sounds, flags
  (solid, float, ceiling, shadow) and, from the attack code pointer found
  in the missile or melee chain (`AttackAction`), the attack kind, damage
  dice, pellet count and attack sound (`AttackOf`). `TDoomActor.PlayStates`
  plays a sequence with each frame's own tics, sprite and brightness and
  exposes `CurrentAction`; `DoomWorld` dispatches `MonsterAttack`,
  `SpawnMissile`'s projectile, the hitscan pellets and the Arch-vile's
  blast frame on those actions instead of on thing numbers, so a patch
  giving a monster another's code pointer gives it that attack. Walking
  frames now play as vanilla's chains do (each image twice at 3-4 tics),
  the pain frames as the table has them, and muzzle flashes are
  full-bright where the table (or Freedoom's `DEHACKED` lump) marks them.
- No demo playback. The in-game menus (save / load slots) are still drawn by `GameViewPlay`, not by
  `DoomMenu`.
- Vanilla node format only. A blockmap-free design means all 2D queries scan
  all lines.
- The built-in FM synth (web, or without the library) approximates the OPL2
  (envelope shapes and the modulation index are estimates, not a
  register-accurate emulation); the OPL3 driver's volume curve is a
  logarithmic approximation of DMX's table.

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
| `TX3DRootNode`, `TShapeNode`, `TAppearanceNode`, `TUnlitMaterialNode`, `TIndexedTriangleSetNode`, `TCoordinateNode`, `TTextureCoordinateNode`, `TTextureTransformNode`, `AlphaMode` | DoomGeometry, DoomActors | building geometry in code |
| `TCastleScene.Load(RootNode, true)`, `PreciseCollisions`, `Collides`, `Pickable`, `Visible` | DoomGeometry, DoomActors | scenes and collision flags |
| `SetPoint`/`SetColor` on coordinate/colour nodes | DoomGeometry | updating moving sectors in place |
| `TCastleTransform`, `Translation`, `AddBehavior`, `FindBehavior` | DoomActors, DoomSound | things and sound emitters |
| `TCastleScene.BeforeNodesFree`, `KeepExistingBegin` / `FreeIfUnused`, `TAppearanceNode.SetEffects`, `TMFVec3f.Items` / `TMFInt32.Items` + `Changed` | DoomActors | the merged sprite shapes |
| `TCastleViewport`, `Items`, `Camera`, `DynamicBatching` | GameViewPlay | rendering |
| `TCastleCamera.SetView`, `Direction`, `Perspective.FieldOfView/FieldOfViewAxis`, `ProjectionNear` | GameViewPlay | the player's eye |
| `TEffectNode`, `TEffectPartNode` (`PLUG_vertex_eye_space`, `PLUG_fragment_modify`), custom `TSFFloat` / `TSFVec2f` uniform fields, `TFloatVertexAttributeNode`, `AddDestructionNotification` | DoomLighting, DoomGeometry, DoomActors | light diminishing |
| `TCastleWalkNavigation` and its properties, `Input_*.Assign/MakeClear` | GameViewPlay | player movement |
| `TCastleSound`, `SoundEngine.Play`, `TCastleSoundSource`, `SoundEngine.LoopingChannel[0]` | DoomSound, DoomMusic | effects and music |
| `TCastleImageControl` (`Image`, `SmoothScaling`, `Stretch`), `TCastleLabel`, `TCastleRectangleControl`, `TCastleCrosshair`, `TCastleButton`, layout groups, `Anchor` | DoomHud, DoomMenu, GameViewPlay, GameViewMenu | 2D UI |
| `TCastleUserInterface.Press` / `Motion` overrides, `RenderRect`, `InputKey` | DoomMenu, GameViewMenu | menu mouse input, scripted menu keys |
| `Container.Pressed`, `Container.MousePressed`, `TInputPressRelease.IsKey/IsMouseButton/MouseWheelScroll` | GameViewPlay | input |
| `UrlSaveStream`, `Download`, `castle-config:` | GameSaveStorage | writing and reading save games (desktop) |
| JOB (`Job.Js`, `CastleInternalJobWeb.JSWindow`, `ReadJSPropertyObject`, `InvokeJSValueResult`, `InvokeJSNoResult`) | GameSaveStorage | `localStorage` saves on the web |
| `Controllers`, `TGameController.AxisLeft/AxisRightTrigger/InternalPressedToReport`, `TExplicitControllerManagerBackend.SetCount/SetAxis*/SetButton`, `ApplicationProperties.OnUpdate`, JOB `ReadJSPropertyValue` / `InvokeJSTypeOf` | GameGamepad | gamepads; the browser's Gamepad API fed into CGE |
| FPC `fpjson` / `jsonparser` (`TJSONObject`, `GetJSON`) | doomworld_save.inc, GameViewPlay | save game format |
| `TCastleUserInterface.Render`, `DrawPrimitive2D`, `DrawRectangle`, `RenderRect` | DoomAutomap | immediate-mode 2D drawing |
| `Container.Fps`, `WritelnLog`, `WritelnWarning`, `Application.MainWindow.SaveScreen` | GameViewPlay, everywhere | diagnostics and screenshots |
| `TCastleContainer.InputInspector.Key`, `Container.EventPress(InputKey(...))`, component `Name`s, `published` properties on `TCastleTransform` / `TCastleUserInterface` descendants | GameInitialize, DoomWorld, DoomActors, GameViewPlay | the F8 inspector in every build and what it shows |
| `TGLRenderToTexture` (`tbNone`), `Container.RenderControl`, `SaveScreen_NoFlush`, `TDrawableImage.Draw(ScreenRect, ImageRect)`, `TCastleUserInterface.Render` / `RenderRect` | GameViewPlay, DoomWipe | the screen melt (off-screen capture works under WebGL) |
| `castle-engine compile/package/generate-program`, `--target=web` | CI | builds |
