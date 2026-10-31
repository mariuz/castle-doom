# Rendering roadmap: toward UZDoom's look

UZDoom (the continuation of GZDoom) is the reference for how modern Doom maps
are meant to look: slopes, 3D floors, coloured and fogged sectors, dynamic
lights with shadows, materials, models, portals and post-processing. Maps made
for it (UDMF, which Castle DOOM now loads; see ROADMAP "UDMF maps") use those
features, so each step here makes more of them look right.

This document lists those steps in a suggested order. For each one it says
what UZDoom does, what Castle DOOM has today, how it would map onto Castle
Game Engine (CGE), where the code goes, how to test it, and a rough size
(S = hours, M = a day, L = several days).

## Where we start

The current renderer (`DoomGeometry`, `DoomActors`, `DoomLighting`, ARCHITECTURE
sections 6 and 7) does the following:

- Walls and flats are X3D triangles per sector chunk, from the subsector
  polygons. Static chunks are merged; moving sectors get their own chunks.
- Textures come from the WAD through `doomgfx:`. They are packed into an
  atlas (mipmapped with `textureGrad` on GLSL 1.40 / 3.00 es) and wrapped
  with `fract` in the shader.
- Lighting is Doom's own: the sector light picks a row of the real `COLORMAP`
  in a shader effect, with light diminishing by distance (walls by scale,
  flats by depth) and fake contrast. Powerups use fixed colormaps, gamma has
  five steps, and up to 8 dynamic point lights are added (lamps, shots,
  explosions).
- Sprites are billboards merged per texture and light group
  (`TSpriteBatch`); spectres get fuzz specks.
- Effects:
  - one sky cylinder, plus per-sector skies drawn as sky-textured ceilings;
  - Boom deep water as a screen tint;
  - Boom translucency (66%, or a custom map's estimate);
  - MBF translucent things.
- Missing:
  - slopes, 3D floors, portals, mirrors;
  - coloured light, fog;
  - texture scaling and rotation;
  - long texture names and PK3s;
  - models, materials, shadows, post-processing.

Two constraints shape every item below:

- **The web build.** WebGL 2 in WebAssembly is slow per draw call (each call
  crosses wasm to JS), and exceptions abort the program. Colour read-back
  needs CGE `master` (the `snapshot` tag predates PR #738), and depth
  read-back is CGE PR #739 (open). Screen-space effects that need the depth
  buffer stay desktop-only until those land.
- **Doom fidelity first.** UZDoom's own default keeps Doom's banded light
  (its "software" light mode). Every item here must be an option, so the
  vanilla look stays the default and the existing golden screenshots stay
  valid.

## Stage 1: map data UZDoom draws (UDMF fields)

The UDMF loader (`DoomUdmf`, `TDoomMap.LoadUdmf`) parses these fields but does
not use them yet. These items are mostly geometry and shader work.

| # | Item | UZDoom | CGE mapping and where | Test | Size |
|---|---|---|---|---|---|
| 1 | **Per-part offsets, scaling and rotation** (done: walls' `offsetx_*` / `offsety_*` / `scalex_*` / `scaley_*`, flats' panning, scale and rotation; autotest `udmf-look`) | UDMF sidedef `offsetx_top/mid/bottom`, `offsety_*`, `scalex_*`, `scaley_*`; sector `xpanningfloor`, `ypanningfloor`, `xscalefloor`, `yscalefloor`, `rotationfloor` (and the ceiling ones) | Keep them in `TDoomSidedef` / `TDoomSector`. `DoomGeometry`'s wall UVs add the part's offset and divide by its scale; flat UVs are rotated about the origin. These are the atlas UVs, so `fract` wrapping is unchanged. | A UDMF test map with a scaled, rotated floor; golden screenshot; unit test on the UVs of one wall | S |
| 2 | **Per-wall and per-flat light** (done for the side's `light` / `lightabsolute` and `lightfloor` / `lightceiling`; per-part side lights left) | `light`, `lightabsolute` (sidedef, also per part); `lightfloor`, `lightceiling`, `lightfloorabsolute`... (sector) | The light already goes per vertex (`doom_light.x`); add the offsets when building the chunk. | Golden screenshot | S |
| 3 | **Coloured light and fog** (done for walls and flats: `lightcolor`, `fadecolor` as the `doom_color` / `doom_fade` vertex attributes; sprites too, through `TSpriteBatch`'s looks; left: `desaturation`, `Sector_SetColor` / `Sector_SetFade` and MAPINFO fog) | Sector `lightcolor`, `fadecolor`, `desaturation`; `Sector_SetColor` (212), `Sector_SetFade` (213); per-map `fade` / `outsidefog` in MAPINFO | Add `doom_color` (a second vertex attribute, or a per-chunk uniform) and a fog colour in the `DoomLighting` effect: multiply the colormapped texel by the colour, mix towards the fade colour by the same distance light diminishing uses (UZDoom's "Doom" fog density). Sprites take their sector's colour in `TSpriteBatch`'s light groups (the group key grows a colour). | Golden screenshots of a red-lit, blue-fogged room; check the web build's shader count stays flat | M |
| 4 | **Slopes** | `Plane_Align` (181), `Plane_Copy`, UDMF `floorplane_a..d` / `ceilingplane_a..d`, vertex heights (`zfloor`, `zceiling`), slope things (9500-9503, 9510, 9511) | Store a plane per sector. Flats become triangles with per-vertex Z; walls are cut along the plane (four Z values per wall part instead of two). The simulation needs `FloorZAt(Sector, X, Y)` wherever it reads `FloorHeight` (movement, actors, hitscans, sight), and the walk navigation gets the floor from it. Movers move the plane's D. | Unit tests of the plane maths; an autotest walking up a ramp (the player's Z in saves) | L |
| 5 | **3D floors** | `Sector_Set3dFloor` (160): solid, swimmable, translucent or invisible slabs taken from a control sector; light under them; vertex-height and sloped variants | Draw each slab as extra flats and side walls in the tagged sectors. Collision is a list of floors and ceilings per sector, which touches `TDoomWorld`'s movement, sight, hitscans and sound, and the player's step-up logic. Start with solid and translucent slabs. | An autotest standing on a bridge and walking under it; goldens | L |
| 6 | **Polyobjects** | Polyobj things 9300-9302, `Polyobj_Move`/`Rotate`/`Door*` (1-8) | Wall segments in their own `TCastleTransform` (rotation and translation per tic); collision against moving lines. The BSP is built around them (UZDoom splits polyobject segs per subsector; a simpler port can test them as separate lines). | An autotest opening a sliding door | M |
| 7 | **Long texture names, TEXTURES, PK3** | UDMF texture names like `textures/wall/brick.png`; the `TEXTURES` lump; PK3 / PK7 archives with `textures/`, `flats/`, `sprites/` and `hires/` folders | `DoomWad` reads zip directories (CGE has `CastleZip`; `freedoom2-zip:` already reads one). Names longer than 8 characters are looked up in the archive; `TEXTURES` composes like `TEXTURE1`. PNG decoding stays off the per-frame path (web: decode once, cache as TGA like `doomgfx:`). | Unit tests of the TEXTURES parser; a PK3 test map | M |

## Stage 2: lighting like UZDoom

| # | Item | UZDoom | CGE mapping and where | Test | Size |
|---|---|---|---|---|---|
| 8 | **GLDEFS dynamic lights and light things** (GLDEFS done: `DoomGldefs` parses point, pulse, flicker, flicker2 and sector lights, `object ... frame ... light` bindings by sprite and frame letters, `brightmap` entries and `#include`; bound lights replace the built-in tables in the 8 slots, autotest `gldefs`. Light things 9800-9804, 9810-9814, 9825 and 9830 done too (`TDoomMap.MapLights`). Left: spot lights (9840-9844), subtractive lights, more than 8 lights) | `GLDEFS` point, spot, pulse, flicker and sector lights bound to sprite frames (the lamps, torches, shots in `lights.pk3`); light things 9800-9830 (UDMF `arg0`... colour and radius); additive and subtractive lights | `DoomLighting` has 8 point lights chosen by distance. Grow it to a light list per chunk, or clustered (a small 3D grid of light indices in a texture) for many lights; parse GLDEFS into the light table `DynamicLights` uses today (lamps). Spotlights add a direction and a cone. | Golden screenshots of a lit corridor; `Lights:` log counts | M |
| 9 | **Light modes** (the smooth mode done: Options -> Video -> LIGHT MODE, `Settings.SmoothLight`, the shader's `doom_smooth`; left: "bright" and Build modes) | Standard, bright, Doom, "software" (banded, the default look), Build | The current shader is the software mode. Add the smooth "Doom" mode (no 32-step bands, the same curve) and a "bright" mode as `Settings.LightMode`; Options -> Video. | Golden screenshot per mode | S |
| 10 | **Shadows for dynamic lights** | Shadowmaps traced against the level's lines (a 1D shadow map per light over a line BVH) | Two routes. (a) CGE's own shadow maps (`TCastleSpotLight` / directional lights cast shadows; point lights need six faces), costly in draw calls. (b) UZDoom's approach: the map's lines in a texture, a ray-march per light in the fragment shader. (b) fits the web better: one texture, no extra passes. | Golden screenshot of a lamp behind a pillar | L |
| 11 | **Ambient occlusion** | SSAO post-process; baked lightmaps (ZDRay) in recent versions | SSAO as a CGE screen effect (`TCastleScreenEffects` with depth): desktop now, web after depth read-back lands in CGE. Baked lightmaps: an offline tool (Python, or a `--bake-lightmaps` mode) writing a lightmap atlas per map, applied as a second texture; L, best after slopes and 3D floors. | Golden screenshots (desktop only for SSAO) | M (SSAO), L (baked) |

## Stage 3: materials and models

| # | Item | UZDoom | CGE mapping and where | Test | Size |
|---|---|---|---|---|---|
| 12 | **Brightmaps** (done for textures and flats: the brightmap, a PNG or Doom patch lump, is coded into the opaque texels' alpha (`BrightmapAlpha`), surfaces drawing such an image add `BrightmapLightFlag` to their light, and the shader moves those texels toward colormap 0; autotest `gldefs`. Left: sprite brightmaps) | `brightmap` entries in GLDEFS: texels of a texture or sprite that ignore the sector light | A second atlas page (or an alpha channel) sampled by the light shader: `mix(colormapped, fullbright, brightmap)`. Small change, big visual gain on lamps and computer panels. | Golden screenshot of a dark room with a lit panel | S |
| 13 | **Materials (normal, specular, PBR)** | GLDEFS `material`: normal, specular, metallic, roughness and AO maps with dynamic lights | CGE's `PhysicalMaterial` / `Material` nodes do this already, but the atlas and the colormap shader replace CGE's lighting. Add normal and roughness pages to the atlas and evaluate them in `DoomLighting` for the dynamic lights only (sector light stays banded). | Golden screenshots of a bumped wall under a moving light | M |
| 14 | **Hi-res texture packs and filtering** | `hires/` replacements at any resolution; nearest, linear, trilinear and anisotropic filtering; texture upscaling (xBRZ, hqNx) | Texture size is independent of world size: scale UVs by the original size. Filtering is an option on the atlas (`TextureProperties`; nearest stays the default). Upscaling is a decode-time pass in `DoomGraphics` (cached; desktop first, it costs CPU in wasm). | Golden screenshots per filter | M |
| 15 | **3D models** | `MODELDEF` with MD2, MD3, OBJ, IQM, voxels (KVX), frames bound to sprite frames | CGE loads MD3, OBJ and glTF natively (`TCastleScene`); MD2 and IQM would need converters (or a glTF route). A model replaces a thing's billboard: `TDoomActor` gets an optional model scene whose animation follows `PlayStates`' frames. Lighting: the colormap effect on the model's material. | An autotest with a model pickup; golden | L |
| 16 | **Decals and particles** | `DECALDEF` (bullet holes, scorch marks, blood splats on walls); particle fountains (9027-9033); the software particle system | Decals as small textured quads offset from the wall, kept in a ring buffer in a batch scene like `TSpriteBatch`. Particles as a points batch with a size attribute. | Golden screenshot after firing at a wall | M |

## Stage 4: views through other views

| # | Item | UZDoom | CGE mapping and where | Test | Size |
|---|---|---|---|---|---|
| 17 | **Skyboxes** | Skybox viewpoints (9080, 9081, `SkyViewpoint`), 6-sided skyboxes in `SKYBOXES` / ANIMDEFS, `MAPINFO` `sky1` with skybox names | 6-sided: CGE's `TCastleBackground` with six textures (instead of the cylinder). Viewpoint skyboxes: render the scene from the viewpoint into a cube map or the background, with the same rotation as the player's view (no translation). | Golden screenshot looking up | M |
| 18 | **Line and sector portals, stacked sectors** | `Line_SetPortal` (156), `Sector_SetPortal` (57), linked portals (seamless room-over-room) | Render the other side through a stencil mask per portal (CGE: a second viewport or `TCastleTransformReference` of the map moved by the portal's offset, clipped by the portal polygon), with a recursion limit. Linked portals also need movement and sight through them. | An autotest walking through a portal; golden screenshots | L |
| 19 | **Mirrors and reflective floors** | `Line_Mirror` (182); reflective flats (`floor reflection`, ice / water shine) | CGE's `ViewpointMirror` generated textures (`GeneratedCubeMapTexture` / `RenderedTexture`) for the mirror line; floors as a reflected render blended in. Desktop first (an extra scene render per mirror). | Golden screenshot | M |

## Stage 5: post-processing

| # | Item | UZDoom | CGE mapping and where | Test | Size |
|---|---|---|---|---|---|
| 20 | **Bloom, tonemapping, HDR** | Bloom, exposure, tonemap (Uncharted 2, Hejl-Dawson, Reinhard, palette), banded "palette" tonemap that keeps the Doom palette | CGE screen effects (`TCastleScreenEffects`, custom GLSL) on a floating-point buffer; the "palette" tonemap is a lookup through `PLAYPAL` and fits the current colormap pipeline. Options -> Video. Web: one fullscreen pass is cheap. | Golden screenshots, effect on and off | M |
| 21 | **Anti-aliasing** | MSAA, FXAA | `Window.AntiAliasing` (MSAA) on the desktop; FXAA as a screen effect (the web too). | Golden screenshots | S |
| 22 | **Lens and screen effects** | Lens distortion, film grain, dither, colour blindness filters, the underwater / invulnerability screen tints as shaders | Screen effects; the deep-water tint becomes a real colormap remap (ROADMAP "Boom/MBF specials"). | Goldens | S each |

## Stage 6: what keeps it fast

| # | Item | Why | Where | Size |
|---|---|---|---|---|
| 23 | **Visibility from the BSP** | UZDoom clips walls front to back with an angle clipper. Here CGE culls per chunk by frustum only; slopes, 3D floors and portals multiply the geometry. A portal-and-BSP visibility pass (or GPU occlusion queries on the desktop) would skip hidden chunks. | `DoomGeometry`, a new `DoomVisibility` | M |
| 24 | **Fewer draw calls on the web** | Every feature above adds shapes. CGE's web renderer would gain from vertex array objects and cached uniform locations (ROADMAP "Browser frame rate"), best done upstream in CGE. | CGE | M |

## Suggested order

1. Items 1, 2, 3 and 12: offsets and scaling, per-surface light, coloured
   light and fog, brightmaps. They are small and touch only `DoomGeometry` and
   `DoomLighting`, and they make the most visible difference on UDMF maps.
   Items 1 to 3 are done (see their rows), the sprites' colour and fog
   too; item 12 is next.
2. Item 8 (GLDEFS lights) and item 9 (light modes), which give the
   "UZDoom look" without new geometry.
3. Item 4 (slopes), then item 5 (3D floors). These are the big gameplay and
   geometry items, and many UZDoom maps need them to be playable at all.
4. Item 7 (PK3 and long names), so that complete UZDoom mods load.
5. Then models, portals and post-processing, as options.

## How to check against UZDoom

- Run UZDoom on the same test map and save screenshots at the same spot,
  angle and field of view.
- Keep those references outside the repository (UZDoom is GPL), and compare
  them by eye. Our own golden screenshots in `tools/golden/` are what CI
  checks.
- Each item's UDMF test map belongs in `tools/make_*_wad.py`, like
  `make_udmf_wad.py`, so the maps are generated rather than hand-edited.

## Not rendering, but needed for UZDoom maps

These are gameplay items, tracked in ROADMAP "UDMF, the rest":

- **ACS** (`BEHAVIOR`): the script virtual machine behind most UZDoom map
  logic.
- **ZScript / DECORATE**: new actors.
- **The Hexen actions** not yet translated (logged as "not supported").
