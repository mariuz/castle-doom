# Roadmap: what is still missing

Status as of October 2026. Each item says what is missing, why it matters,
where it would go in the code, and a rough size (S = hours, M = a day,
L = several days). Items inside a section are in suggested order.

## Done since the first release

- Installable web app: `pages/manifest.webmanifest` (name, start
  `play/`, standalone display, colours) with icons made from Freedoom's
  status bar face by `tools/make_web_icons.py`, linked from the home
  page and (through `tools/patch_web_page.py`) the play page, copied by
  the Web workflow and kept by the service worker. Chrome's own check
  (`Page.getInstallabilityErrors` over CDP) finds no errors on either
  page.

- Fixed-step autotests: `--fixed-step` caps CGE's `SecondsPassed` at one
  tic (`Fps.MaxSensibleSecondsPassed`), keeps every frame at least a
  tic long (`TViewPlay.Update` sleeps the rest) and seeds `Random` the
  same way at each map load, so the world, the walk navigation and the
  demo's waits advance exactly 1/35 s a frame and two runs give the same
  screenshots (apart from the FPS text). The save round trip, knockback,
  melee turn, donut, select-thing and key-bindings autotests use it, and
  their 7 screenshots joined the golden ones (35 now).

- Crash reporting in release builds: `GameCrash` sets
  `Application.OnException`, so an uncaught exception on the desktop is
  logged (`Warning: Crash: ...`) with the log file's place and its last
  lines and shown in a dialog that offers to continue or quit (autotests
  log it and exit with code 1). In the browser, where any exception stops
  the WebAssembly program, the page (patched by
  `tools/patch_web_page.py`) keeps the last 40 console lines and shows
  them over the page on the window's error event. The demo command
  `CRASH` raises a test exception; autotest `crash-report`.

- Offline web build: `pages/sw.js`, a service worker at the site root
  (the Web workflow copies it; the home page and the play page, through
  `tools/patch_web_page.py`, register it), fetches the game's files when
  it installs (the first visit's page loaded them before the worker saw
  the requests) and then answers every same-site and Bootstrap CDN GET
  network first, keeping a copy, and from the copy when the network
  fails (query strings ignored, a directory as its `index.html`). Tested
  with Playwright: after one online visit, E1M2 and the home page load
  with the browser offline.

- UMAPINFO episodes and boss actions: `episode = patch, name, key` adds
  a New Game episode starting at that map (its patch, or the name in
  the HU font when the patch is missing), `episode = clear` drops the
  ones before it, vanilla's included (`TDoomMenuScreen.SetupEpisodes`,
  `EpisodeMap`); `bossaction = ZDoomClass, special, tag` replaces the
  map's vanilla boss deaths: when the last monster of that type dies,
  the line special acts on the tag (run through line 0 like `LINE`).
  Class names map to THINGS types (`MapInfoThingType`); unlike ports
  that need A_BossDeath in the death frames, any monster type works.
  Autotests `umapinfo-episode` and `umapinfo-boss`.

- Golden screenshots in CI: `tools/run_autotests.py` compares 28 of the
  autotests' screenshots (the menus, the title and Read This! pages,
  the Controls page, the map component, the palette effects, fuzz, the
  node formats, the in-game menus, Boom and UMAPINFO maps...) with
  320x180 references in `tools/golden/`, made from CI's own screenshots
  (`--update-golden`). A screenshot fails when more than 1.5 % of its
  pixels differ by more than 40 in a channel, which software GL's small
  run-to-run differences (at most 0.6 %, the FPS text) stay under; the
  failure writes `golden-diff-NAME.png`, which CI uploads with the rest.

- Video options in the game: Doom's in-game Options page has a "Video"
  item (the HU font, as Doom has no patch for it) opening a Video page
  in the style of the sound page: field of view and UI scale
  thermometers with their values, and fullscreen on / off on the
  desktop or the render resolution thermometer in the browser. Changes
  apply at once and are saved (`maSettings`); autotest `video-menu`.

- UMAPINFO: `DoomMapInfo` parses a PWAD's UMAPINFO lump (`ParseUMapInfo`:
  quoted strings, numbers, identifiers, lists, comments; unknown keys
  skipped) and the game asks it first for the next and secret map, the
  level name and label, par time, music, sky, the intermission's name
  picture, the story text after a map (with its backdrop and music),
  the end of the game (picture, bunny, cast call), `endgame = false` and
  `nointermission`. `tools/make_umapinfo_wad.py` writes the test PWAD;
  unit test `TestUMapInfo`, autotest `umapinfo`.

- Key rebinding: `GameSettings` holds two keys for each action (move
  forward / backward, strafe, turn, run, fire, use, automap), saved in
  `settings.json`'s `keys`. The title screen's Options -> Controls...
  page (`ControlsPanel` in the menu design, rows built in code) binds
  the next key pressed (Backspace clears, Esc cancels, function keys and
  Esc cannot be bound; a key moves from the action that had it). The
  play view assigns the navigation's inputs from them, fires and uses
  with the bound keys, and a bound key no longer triggers the fixed
  hotkey it shadows (F, M, digits...); the help panel's first lines show
  the bindings. `BIND:action:key` and `RESETKEYS` in a demo; autotests
  `controls-page` (the `MENUCONTROLS` screenshot) and `key-bindings`.

- Log filtering: `CASTLE_DOOM_LOG=Load,Shot` (`GameLogFilter`, desktop)
  writes `castle-doom-filtered.log` next to the saves with only those
  categories, every warning and the continuation lines of kept messages
  (`CASTLE_DOOM_LOG_FILE` picks another path). The main log stays
  complete: CGE's generated `CastleAutoGenerated` starts it before game
  code runs, so the filter is a copy fed from `ApplicationProperties.OnLog`.
  Unit test `TestLogFilter`, autotest `log-filter`.

- Boom `ANIMATED` and `SWITCHES` lumps: a PWAD's `ANIMATED` replaces
  the vanilla animation table (flat and texture ranges, each with its
  own tics per frame), and its `SWITCHES` pairs (up to the game's
  episode number) replace the `SW1*` / `SW2*` rule for which textures
  are switches and what they turn into. `tools/make_boom_wad.py` writes
  the test PWAD (`tools/testdata/boom.wad`); unit test `TestBoomLumps`,
  autotest `boom-lumps`.

- Video options: the title screen's Options panel sets the field of
  view (60-120, Doom's 90 by default), the UI scale (50-200 %, the text
  and panels; CastleSettings.xml's reference size divided by it),
  fullscreen (desktop) and, in the browser, the render resolution
  (25-100 % of the canvas' pixels: the page's canvas sizing script,
  patched by `tools/patch_web_page.py` in the Web workflow, multiplies
  the size by it). They are saved in `settings.json`; `FOV`, `UISCALE`,
  `RENDERSCALE` and `FULLSCREEN` set them from a demo (autotest
  `video-settings`). At 50 % SwiftShader draws E1M1 at about three
  times the frame rate.

- Live thing inspection and profiler sections: the inspector's F9
  auto-select ("Transform") picks the monster or barrel under the
  crosshair (the collision quads are transient, so the actor is what is
  selected; the passable map chunks, which a ray hit by their bounding
  box, are no longer pickable), and `SELECT` / `SELECT:name` in a demo
  does it from the camera or by name (log `Select:`). Things publish
  `ActionName`, `TicsLeft`, `TargetName` and `ReactionTime` too.
  `--profile` turns on CGE's profiler: each map load logs `Load <map>
  (DoomWorld)` with `Parse map`, `Build geometry` and `Spawn things`
  and the engine's work inside them; `PROFILE` logs the summary
  (autotest `select-thing`).

- DeHackEd weapons and projectiles: `DoomStates.Weapons` (d_items.c's
  weaponinfo: ammo type and up / down / ready / attack / flash states)
  and the player's weapon animation runs on the state table:
  `BuildWeaponSeqs` walks the attack and flash chains at each map load,
  `AdvanceWeaponFrames` runs each frame's code pointer as it is reached
  (the shot on A_FirePistol's frame, the chaingun's two shots a cycle,
  the SSG's open / load / close sounds, A_ReFire while the trigger is
  held, A_Light1 / A_Light2 for the flash light), and the HUD shows the
  frame's sprite. "Weapon N" sets the ammo type and entry frames; the
  projectiles (imp, cacodemon, baron, revenant, mancubus, arachnotron
  and cyberdemon shots, the player's rocket, plasma and BFG ball) take
  speed, size, damage dice, sounds and frames from their mobjinfo rows,
  which "Thing N" edits ("Speed", "Width", "Height", "Missile damage").
  `tools/testdata/test.deh` makes the pistol fire the shotgun's seven
  pellets (`FRAME 14 = A_FireShotgun`) and the imp fireball fast and
  harmless.

- Atlas mipmaps: tiles sit in 8-aligned blocks padded with 4 texels of
  their wrapped content, so the page's mipmaps up to level 3 keep the
  tiles apart, and the atlas effect samples with `textureGrad` using the
  gradients of the unwrapped coordinate (clamped to level 3), so the
  repeat seam does not pick the smallest mipmap. On when CGE upgrades the
  shaders (OpenGL 3.1+, OpenGL ES 3, WebGL 2), log `Atlas: ... page(s),
  mipmapped`; `--no-atlas-mipmaps` turns it off. Far floors and gratings
  shimmer less (E1M1's start room grating), with no visible seams.
- A Doom level as a CGE component: `TDoomMapTransform`
  (`doommaptransform.pas`, registered as "Doom Map" for the editor) is a
  `TCastleTransform` with published `Wad` and `MapName` (and `Things`)
  that builds the level in its first `Update`: the WAD, its graphics,
  the map, `TDoomGeometry` with every sector static (one chunk, the
  atlas, the lighting effects) and the things as `TDoomActor` billboards
  that face the viewport's camera and play their idle frames at 35 tics
  a second. Bad URLs or map names log a warning instead of raising (the
  editor shows an empty component; the web build survives).
  `data/mapcomponent.castle-user-interface` is a design with a viewport,
  a camera and the component on E1M1; `--autotest MAPCOMPONENT prefix`
  (`GameViewDesign`) shows it with the camera at the player start and
  screenshots it (autotest `map-component`), which is what the editor's
  3D view shows for the same design.
- The menu view is a design too: `data/menu.castle-user-interface` holds
  the black background, Doom's menu (`TDoomMenuScreen`), the Options
  panel (the WAD / map / skill / volume rows of buttons and labels, the
  own-WADs and save-transfer rows, the WAD and licence lines) and the
  Phase 2 download line; `TViewMenu.Start` only assigns the handlers and
  the run-time texts. The title, menu and Options screenshots are
  pixel-identical to the code-built ones. Both views now come from
  designs; the viewport and navigation stay in code.
- The project opens in the CGE editor: the game's controls
  (`TDoomStatusBar`, `TDoomFontText`, `TDoomMenuScreen`, `TDoomAutomap`,
  `TDoomIntermission`, `TDoomFinale`, `TDoomWipe`, `TDoomWorldStatus`) are
  registered with `RegisterSerializableComponent` and listed as
  `editor_units` in the manifest, and the play view's whole 2D layer is
  `data/play.castle-user-interface` (loaded through `DesignUrl`, the
  viewport inserted behind it in code); `TDoomStatusBar` got a default
  constructor and a `Graphics` property for it. The screenshots are
  pixel-identical to the code-built layout. The menu view is still code.
- Inspectable in Castle Game Engine's tools: the F8 inspector works in
  every build (CGE registers its key only through `InitializeDebug`,
  which the generated program calls in debug builds alone, so the
  release packages had no inspector; `GameInitialize` sets
  `TCastleContainer.InputInspector.Key`). Its hierarchy is grouped and
  named: the viewport holds `Map` (`Chunk<n>_Solid` / `_Passable`,
  `LineCollision`, `Sky`), `Things` (every `TDoomActor` named
  `<SPRITE>_<n>`, with published `ThingType`, `SpriteName`,
  `CurrentFrame`, `ActorState`, `HitPoints`, `IsAwake`, `DoomPosition*`,
  `DoomSector` in the properties pane) and `Sprites`
  (`SpritesLight<n>[_Bright|_Fuzz]` batch scenes); the views and their
  controls (`Viewport`, `Camera`, `Navigation`, `StatusBar`, `Automap`,
  `HelpLabel`...) carry names, and the invisible `DoomWorldStatus`
  control publishes the map, tic, player health / armor / position,
  kills, items, secrets, thing and sector counts. Demo command
  `INSPECTOR` (sends F8), autotest `inspector` screenshots it.
- Map texture atlas: each level's wall textures and flats are packed into
  atlas pages (2048 wide, trimmed to a power-of-two height, more pages
  when full; E1M1: 150 images in one 2048x1024 page) with a 1-texel
  border of their wrapped edges, and a chunk draws all of them in one
  shape per page (`TDoomGraphics.BuildAtlas`, `doomgfx:/atlas/`,
  `TGeomBatch.AtlasPage`): the `doom_tile` vertex attribute carries each
  vertex's tile rectangle and a texture effect (`PLUG_texture_color`)
  samples at `tile.xy + fract(uv) * tile.zw`, so walls and flats repeat
  as before. Switches, scrolling walls and animated textures keep their
  own shapes; nearest up close and, since the atlas mipmaps (below),
  trilinear far away. E1M1 door spot: map 151
  -> 21 draw calls (12 with everything in view), the frame 186 -> 56,
  geometry built in 63 ms instead of 96-244 (fewer shapes), and the
  textures keep their real sizes (no power-of-two resize). `--no-atlas`
  returns to one shape per texture (with mipmaps).
- Unit tests for the node formats, the MIDI / MUS parsers and the
  synthesizers' envelope: `tests/castle_doom_tests.lpr` (18 cases, about
  20 s) loads E1M1 from every generated node-format PWAD (XNOD, ZNOD,
  XGLN, ZGL2, XGL3, ZGL3 and glBSP V1, V2, V3, V5: format, 682 / 717
  subsectors, the polygon areas, the start sector; the WADs come from
  `tools/make_znodes.py` and `tools/make_glnodes.py` into
  `tools/testdata/nodes/`, gitignored, CI generates them first), parses
  a hand-made MUS (program, note on with volume, delay, note off at 0.5
  s) and Freedoom's MIDI D_E1M1 (sorted times, several channels, a few
  minutes), rejects each as the other, and renders the MUS with both
  synthesizers: sound while the note is held, a tenth of it a second
  after the release. `ParseMus` / `ParseMidi` are in `DoomMusic`'s
  interface for that.
- Music without the start stall: the first 8 seconds of a song are no
  longer rendered at once when a level, a warp, a loaded game or the title
  starts (100-300 ms natively, more on the web); `TDoomMusic.Update`
  renders them in its per-frame slices (with a 40 ms budget while nothing
  plays) and `TryStartIntro` starts the intro as soon as they are there
  (log `ready after N ms`: about 10 frames), the rest as before.
- Sprites merged by texture in persistent shapes: within each
  `TSpriteBatch` scene (light group and kind) a `TSpriteShape` holds the
  quads of every thing showing one texture (four vertices and six indices
  per quad, written in world space each tic, flushed once a frame); a
  thing changing frame, light or visibility edits the lists, and only a
  texture new to a light group adds a shape (`ChangedAll`). This replaces
  CGE's dynamic batching for the sprites, which merged 8 textures a pass
  and whose pool shapes relinked the per-scene sprite shader programs
  about 7 times a second (the program cache frees a program at its last
  reference; `getShaderParameter` was 40 ms a frame in the browser). E1M1
  door spot: sprites 73 -> 35 draw calls (104 before any batching), the
  frame 224 -> 186, the world update 7 -> 2 ms, no relinks during play
  (`CASTLE_DOOM_LOG_SHADERS=1` counts them).
- Nuked OPL3 as a dynamically linked library (LGPL 2.1, kept out of the MIT
  code): `tools/build_nuked_opl3.sh` fetches `opl3.c` at a pinned commit and
  builds `data/lib/libnukedopl3.so` / `nukedopl3.dll` / `libnukedopl3.dylib`
  (CI does it in every package job, with the licence and a README next to
  the library); `DoomOpl3` loads it at runtime (`data/lib`, next to the exe,
  `CASTLE_DOOM_OPL3`), and `TOplSongRenderer` programs it the way DMX did
  (18 two-operator channels, the GENMIDI operator bytes written to the
  registers, F-number / block from the note, volume as total-level
  attenuation, pitch bend, double voices with fine tuning). The built-in
  model (`TFmSongRenderer`) stays as the fallback, `--fm-synth` forces it,
  and the web build keeps it (no dynamic linking there). The unit test
  renders a song with both, the `music-opl3` autotest checks the library
  loads in CI.
- Sprite batching: the things' quads are drawn from `TSpriteBatch` scenes,
  one per light group (sector light div 16) and kind (normal, full bright,
  fuzz), where CGE's dynamic batching merges the quads with the same
  texture; the light effect sits on each quad's appearance (a group effect
  gives every shape its own `State.Effects` list, compared by pointer, so
  nothing merged). Each actor keeps an invisible quad of its own for
  collisions and picking, and turns its drawn quad toward the view angle
  itself (`TDoomActor.UpdateTransform`). E1M1 at the door spot: 104 sprite
  draw calls in 104 scenes -> 73 draw calls in 9 scenes (CGE merges at
  most `MergeSlots` = 8 texture groups per pass, the next limit). Found on
  the way: CGE's `ChangedAll` leaves `TransformationDirty` pointing at the
  freed shape tree, so `TSpriteBatch.Attach` calls `BeforeNodesFree` first.
- Gamepads and a click prompt: on the desktop (CGE reads controllers on
  Windows and Linux) and in the browser (`GameGamepad` polls
  `navigator.getGamepads()` through JOB every frame, about 45 calls a
  pad, and feeds CGE's explicit controller backend with the standard
  mapping: sticks with Y flipped, trigger values, 16 buttons; pads show
  up after a button press, as the Gamepad API requires; a cross-origin
  iframe without `allow="gamepad"` is detected through
  `document.permissionsPolicy` because the call would throw and stop the
  WebAssembly program; unit test `TestWebPadMapping`, and the Web
  workflow now builds every branch and uploads the site as the
  `web-site` artifact so a branch can be tried in a browser before it
  deploys) the sticks move and look (`UseGameController`), the
  right trigger fires, A / X use, the bumpers switch weapons, View opens
  the automap and Menu Doom's menu; in menus and the intermission the
  D-pad, A and B act as arrows, Enter and Esc (`GameGamepad` turns
  buttons into the keys the views already handle). In the browser a
  "CLICK TO LOOK AROUND WITH THE MOUSE" prompt (Doom font) shows while
  mouse look is on but the pointer is not locked. The first download
  already had a progress bar (CGE's page) and the Phase 2 download its
  own progress line. Demo command `CLICKPROMPT`, autotest `click-prompt`.
- Unit tests: `tests/castle_doom_tests.lpr` (FPCUnit, console runner)
  checks the parsers without a window: both Freedoom WADs and PLAYPAL,
  E1M1's BSP (682 subsectors, polygon area 6712683, point-in-sector),
  MAP01, MUS to WAV rendering (header, rate, length) and rejecting junk,
  Freedoom's DEHACKED lump (par times, strings) and a `-deh` patch over
  it. Built with `castle-engine simple-compile`, run in the CI autotest
  job before the game autotests (about 3 s).
- glBSP GL nodes: maps whose BSP is only in glBSP's `GL_VERT` /
  `GL_SEGS` / `GL_SSECT` / `GL_NODES` lumps (after `GL_<map>`, in the
  WAD or a `.gwa` loaded with `-file`) load in all of glBSP's versions
  (V1, V2, V3, V5). `tools/make_glnodes.py` builds the test WADs with the
  real glBSP; autotest `glbsp-nodes` (CI installs glbsp).
- Music ahead of time: every level start queues the next map's song
  behind the intermission's (`TDoomMusic.Prefetch`), so it is rendered in
  frame slices while the level is played and the next level starts it at
  once ("Playing D_E1M2, rendered before") instead of synthesizing an
  8-second intro first (115-230 ms natively, more in WebAssembly). Songs
  no one will play soon are freed (`ReleaseUnneeded`; about 5 MB each);
  they used to stay in memory for the whole session.
- DeHackEd patches: `-deh` / `-bex` files and the WADs' `DEHACKED` lumps
  change the thing table ("Thing N": hit points, speed, width, height,
  mass, pain chance), the Misc values (initial health and bullets,
  bonus / armor / soulsphere / megasphere limits, armor classes, IDKFA
  armor, BFG cells per shot), "Ammo N" limits and clip sizes, and
  `[PARS]` par times, so Freedoom's own par times now show on the
  intermission. Autotest `dehacked` with `tools/testdata/test.deh`.
- DeHackEd frames and code pointers: `DoomStates` holds vanilla's state
  table (`tools/make_states.py` generates `doomstates_table.inc` from
  linuxdoom-1.10's info.c: 967 states, 137 mobjinfo rows, sprite and
  sound names, every code pointer as `TStateAction`); "Frame N" (sprite
  number, subnumber, duration, next frame), "Pointer N (Frame M)", BEX
  `[CODEPTR]` and a thing's frame, sound and bits fields edit it, and
  `ApplyStateTable` walks each thing's chains into per-frame sequences
  (sprite, tics, full bright, action) that `TDoomActor.PlayStates` plays.
  Attacks dispatch on the chain's code pointer (`AttackAction`:
  A_PosAttack one bullet, A_SPosAttack three, A_TroopAttack the imp
  fireball, A_SkullAttack the charge, A_VileAttack on the frame carrying
  it...), so a patch can give a monster another's attack. Side effects:
  walking animations at vanilla's rate (each frame twice), vanilla pain
  frames, full-bright muzzle flashes (Freedoom's lump marks the
  zombieman's and chaingunner's, which now show). Not covered: weapons'
  frames (the player's weapon animations are still the port's own),
  "Sprite" / "Sound" renumbering, thing fields of rows this port has no
  thing for (the player, projectiles), new monsters made from decoration
  rows (their AI stays the decoration's: none). Unit tests
  `TestVanillaTable`, `TestDerivedSequences` and the patched expectations
  in `TestPatchFile`; `test.deh` edits a frame, a pointer and a
  `[CODEPTR]` line.
- Windows installer: CI builds `castle-doom-<version>-win64-x86_64.msi`
  with WiX (`tools/make_msi_wxs.py`): Program Files, a Start menu
  shortcut, upgrades replace the older version.
- Mouse look sensitivity follows Doom's formula in radians per pixel
  (it was 0.15 radians, 8.6 degrees, per pixel: far too fast with a
  1000 DPI mouse); autotest `mouse-sensitivity`.
- macOS packages: CI builds `Castle DOOM.app` for Intel (x86_64) and
  Apple Silicon (aarch64) on GitHub's macOS runners and attaches both
  zips to releases (not signed or notarized: the first start needs
  right-click > Open).
- Palette-mapped weapon: the player's weapon and its flash go through
  the same `COLORMAP` rows as the world (`TDoomGraphics.ColormapCopy`,
  one copy per sprite frame and light level), so the light level,
  the visor and invulnerability's inverted row 32 match the walls exactly.
  Textures were already unfiltered up close (nearest magnification); far
  away they keep mipmaps, which Doom did not have, to avoid shimmer.
- Column fuzz: spectres and the weapon under partial invisibility are
  drawn as black specks in `R_DrawFuzzColumn`'s `fuzzoffset` pattern
  (50 entries of +1 / -1, at Doom's 320x200 grain, starting elsewhere
  every tic) instead of an evenly translucent silhouette. Spectres do it
  in the `DoomLighting` shader, the weapon with a fuzz copy of its
  image. Autotest `fuzz`.
- Palette-mapped lighting: the `DoomLighting` shader rounds each lit
  pixel to its `PLAYPAL` index (a 512x512 lookup image, 6 bits per
  channel, nearest palette colour for the rest) and takes the colour from
  the real `COLORMAP` row for its light level (a 256x34 image), so walls,
  flats and sprites show Doom's exact colours and banding, and
  invulnerability uses `COLORMAP` row 32 itself. Both images are made from
  the WAD and served as `doomgfx:/lut/...`. Demo command `PALMAP` switches
  back to the old multiply for comparison; autotest `palette`.
- Typed save names like `M_SaveSelect`: choosing a slot on Doom's save
  page edits its name with the `_` cursor (a new save starts with the
  map, kills and time, an old one with its name), letters / digits /
  punctuation in Doom's uppercase, 23 at most, Backspace, Enter saves,
  Esc cancels the edit; 1-6 do not pick slots while typing. Demo
  commands `TYPE:text` and `KEY:BACKSPACE`; autotest `typed-save-name`.
- Doom's menus in the game: Esc (and, in the browser, losing the pointer
  lock) opens Doom's main menu over the paused game (New Game, Options,
  Load, Save, Read This!, Quit), Esc again or a click beside the items
  resumes. Options (`M_OPTTTL`): End Game (asks `ENDGAME`), Messages on /
  off (`M_MSGON` / `M_MSGOFF`; off hides player messages but its own),
  Mouse Sensitivity (0..9 thermometer, a new setting) and Sound Volume
  (`M_SVOL`, effects and music on 16-step `M_THERM*` thermometers, also F4).
  Everything is remembered in the settings. In-game New Game goes through
  the title view's episode / skill start; Quit Game quits on the desktop
  and goes to the title in the browser. The text PAUSED and volume
  overlays are gone. Demo command `CORPSE:type:dist`; autotest
  `ingame-options`; the crusher and door tests no longer depend on the
  frame rate.
- Doom's title loop and menus: the title pages cycle like
  `D_DoAdvanceDemo` without the demos (Phase 1: TITLEPIC 170 tics,
  CREDIT 200, HELP2 200; Phase 2: TITLEPIC 11 s, CREDIT) and the menu
  appears with the first key or click, over the current page (Esc on the
  main menu closes it again; back from a game it is open at once). Read
  This! in the Phase 1 main menu and `F1` everywhere show HELP1 / HELP2
  (Phase 2: HELP). The in-game F2 / F3 menus are Doom's save and load
  pages (`M_SAVEG` / `M_LOADG`, slot borders, skull, arrows / Enter /
  Esc / mouse) drawn over the game by the same `TDoomMenuScreen` in
  overlay mode. Demo command `KEY:name`; autotests `title-pages`,
  `read-this`, `ingame-save-load`.
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
| **True fuzz from the background**: Doom's fuzz copies the pixel one row above or below, darkened by colormap 6; the shader cannot read the framebuffer, so the pattern is black specks instead. A screen-space pass (render the spectres into a mask, then shift and darken the scene there) would be exact. | Exact spectre look. | `DoomLighting`, `GameViewPlay` | M |
| **Blockmap-free 2D queries** scan every linedef (`SightClear`, `TryMove2D`, `TicMissile`, `CheckCrossings`). Add a simple grid (or read `BLOCKMAP`) for very large maps. | Performance on big PWADs. | `DoomMap` | M |
| **Item respawn / deathmatch starts**: not applicable to single player, but the flags are parsed. | Only if multiplayer ever happens. | - | - |

## 2. Presentation

| Item | Why | Where | Size |
|---|---|---|---|
| **DeHackEd sprite and sound renaming, new monsters**: frames, code pointers, weapons and projectiles are done (see above); BEX `[SPRITES]` / `[SOUNDS]` renaming, the weapons' bobbing / select / deselect chains (the raise and lower still move the ready sprite by code) and new monsters built from decoration rows (no AI for them) are not. | The rest of what mods change. | `DoomDehacked`, `DoomThings` | M |
| **Browser frame rate**, measured (headless Chromium + SwiftShader on the live page, Chrome CPU profile, `PerfView:` statistics): a frame on E1M1 at the door spot draws 255 shapes = 255 draw calls (map 151 of its 206 per-texture shapes, sprites 104, one scene each); per frame the CPU time is ~94 ms in wasm (game logic 13 ms, the rest CGE's per-shape rendering and the music synth slice) + ~66 ms in the JOB JS bridge (`HaveSharedArrayBuffer`, `decode`, `Invoke_*`, then the WebGL calls: `bindBuffer`, `enable/disableVertexAttribArray`, `activeTexture`, `uniform*`), i.e. about 0.6 ms per shape, so the frame rate is the number of draw calls. Tried and reverted: splitting the static map geometry into 1024-unit cells for frustum culling (151 -> 249 map draw calls: textures repeat per cell and a 90-degree view covers most cells of a flat level). Done: (1) sprites in one scene per (light group, kind), each texture's quads merged by us in one persistent shape (`TSpriteBatch` / `TSpriteShape`; E1M1 door spot: sprites 104 -> 35 draw calls, 104 -> 9 scenes, the whole frame 255 -> 186 draw calls; CGE's own dynamic batching was tried in between: 8 merge slots a pass and shader relinks every frame from its pool shapes); (2) the map in a texture atlas with `fract` wrapping in the shader, padded tiles and no mipmaps (one shape per chunk and page: the frame 186 -> 56 draw calls, 12 for the map alone). Left: in CGE for the web, vertex array objects and cached uniform locations to cut WebGL calls per shape (every call crosses wasm -> JS); the atlas mipmaps are done (see above). | Playable speed on the Pages site. | `DoomActors`, CGE web renderer, `DoomGeometry` | M each |

## 3. Audio

| Item | Why | Where | Size |
|---|---|---|---|
| **OPL3 details** after Nuked OPL3 (done, see above): DMX's exact volume curve (a 128-entry table; the port uses 0.75 dB per total-level step from the linear product of velocity, volume and expression), its voice-stealing order and the OPL2 vibrato / tremolo depth bits, compared by ear or against a recording of the original driver. | Closer to the original mix. | `TOplSongRenderer` | S |
| **Stereo panning** for positional sounds is done by the engine, but Doom's `S_CLIPPING_DIST` falloff curve could be matched more closely. | Minor. | `DoomSound` | S |
| **PC speaker** sounds (`DP*`) are ignored on purpose; no change planned. | - | - | - |

## 4. Content and formats

| Item | Why | Where | Size |
|---|---|---|---|
| **UDMF** (`TEXTMAP`) maps, and glBSP's `GL_LEVEL` markers for map names over 5 letters. | Remaining community map formats. | `DoomMap` | L (UDMF), S (`GL_LEVEL`) |
| **Boom/MBF specials** (generalized linedefs, scrolling floors, friction, translucency) and **DeHackEd** patches. | Big community map support; large job. | `DoomWorld.ApplySpecial`, `DoomThings` | L |
| **Demo playback** of `DEMO1..3` lumps (needs tic-exact movement; the player is driven by CGE's navigation, so this would need a Doom-style player physics mode). | Attract mode; hard. | large | L |
| **Hexen/Heretic** map formats: out of scope unless someone wants them. | - | - | - |

## 5. Engine and tooling

| Item | Why | Where | Size |
|---|---|---|---|
| **More unit tests**: `DoomGeometry`'s sector chunks (needs the graphics cache without a window), the automap and HUD composition, the save file's round trip through `doomworld_save.inc` on a world without a viewport. | Faster, finer regression checks. | `tests/castle_doom_tests.lpr` | S |
| **Android / iOS builds** via `castle-engine package --target=android`: touch controls would be needed (`TCastleTouchNavigation`). | CGE's mobile support is a selling point. | `GameViewPlay` input | M |
| **Web gamepads in CGE itself**: the game's `GameGamepad` polls the Gamepad API through JOB (done, see above); a real `CastleInternalGameControllersWeb` backend inside CGE (`gamepadconnected` events, `mapping` other than `standard`) would serve every CGE web game. Best contributed upstream. | One less game-side workaround. | CGE `castlegamecontrollers`, `castlewindow_webassembly.inc` | M |
| **Performance**: build a static-sector blockmap; merge per-sector dynamic chunks that never actually move; profile `TicActors` on 300+ thing maps. | Headroom on big maps. | `DoomGeometry`, `DoomWorld` | S-M |

## 6. Inspectability (Castle Game Engine's tools)

What the F8 inspector shows is done (see above). The rest makes the
project at home in the CGE editor and the inspector more useful during
play.

| Item | Why | Where | Size |
|---|---|---|---|
| **Try the designs in the CGE editor** on Windows (the editor is not built in CI): "Restart Editor (With Custom Components)", open `data/play.castle-user-interface` and `data/menu.castle-user-interface`, fix what the editor cannot show (the Doom controls render nothing without a WAD; a `Graphics`-less preview, e.g. a placeholder image, would help). | The editor workflow end to end. | the `Doom*` controls | S |
| **The map component in the editor**: `TDoomMapTransform` is done (see above); try it in the editor on Windows (it builds in the design's first `Update`), give it published skill and sector-light switches, a bounding box for the editor's camera framing, and gizmo-friendly names for the chunk scenes. | A Freedoom level in the editor's 3D view with nothing to run. | `DoomMapTransform` | S |
| **More profiler sections**: the map load stages are done (see above); the atlas build and the music intro inside them, and the save / load paths, would tell more. Per-tic phases do not fit CGE's profiler tree (one node per call), so they stay in the `Perf:` lines. | Finer load timings. | `DoomGraphics`, `DoomMusic`, `GameViewPlay` | S |
| **Debug drawing**: toggles that draw the subsector polygons, blocking lines, sector heights, actor radii and the player's line of fire as wireframe scenes under a `Debug` group, each one switched by the inspector's Exists checkbox. | See the simulation, not only the pixels. | new `DoomDebugDraw` | M |
| **Drop `DynamicBatching`**: the viewport still has it on from before the atlas and the sprite batches, and CGE warns "Consider increasing MergeSlots" on every level; measure the draw calls with it off and remove it if they match. | One warning less, maybe fewer relinks. | `GameViewPlay` | S |
| **Inspector in the browser**: it is plain CGE UI so it should work on the web; check F8 under pointer lock (the browser keeps Esc, F8 is free) and the inspector's own key handling against the game's. | Debug the live page in place. | `GameViewPlay` | S |
| **Filter the main log too**: the filtered log is a second file (see above); filtering the main log and the inspector's Log tab needs CGE to let a game choose the log stream before `CastleAutoGenerated` initializes it (an upstream change). | One readable log. | CGE `CastleLog` | S |

## 7. Other suggested improvements

| Item | Why | Where | Size |
|---|---|---|---|
| **V-sync and a frame rate cap**: the video options are on the title screen and in the game (see above); v-sync and a frame limit are not offered. | Smoother play on high refresh screens, less power. | `GameSettings` | S |
| **Gamepad button rebinding and more bindable actions**: keys are rebindable (see above); the gamepad layout is fixed, and weapon selection, the hotkeys (F, M, J...) and the mouse buttons are not bindable yet. `pages/index.html` lists the default keys. | Left-handed and non-QWERTY players. | `GameSettings`, `GameGamepad` | S-M |
| **The rest of UMAPINFO, and ZDoom MAPINFO**: UMAPINFO's keys are done (see above) except patch backdrops, `exitpic` / `enterpic` and the level name drawn as text on the intermission when there is no `levelpic`; ZDoom's MAPINFO syntax is not read. | Fuller PWAD support. | `DoomMapInfo`, `DoomIntermission`, `DoomFinale` | M |
| **Fixed step everywhere**: `--fixed-step` makes 7 moving-scene autotests reproducible (see above); running the whole suite with it would make every screenshot comparable but triples its real time (software GL draws about 12 frames a second, each now a single tic). | Every screenshot a regression check. | `tools/run_autotests.py` | S |
| **Longer crash reports**: the desktop dialog shows CGE's last 10 log lines (`CastleLog.LastLog`), the web overlay 40; a game-side ring buffer (fed by `ApplicationProperties.OnLog`) and a "copy to clipboard" button would make reports more complete. | Better bug reports. | `GameCrash`, `tools/patch_web_page.py` | S |

## Suggested next three

1. Gamepad button rebinding (S-M, see Other suggested improvements).
2. V-sync and a frame rate cap (S, see Other suggested improvements).
3. Fixed step for the whole autotest suite (S, see Other suggested
   improvements), so every screenshot is compared.

Still worth doing but out of this repository's hands: the browser frame
rate's remaining cost is in CGE's web renderer (vertex array objects,
cached uniform locations), best contributed upstream.
