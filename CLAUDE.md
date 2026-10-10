# CLAUDE.md

Working notes for agents (and humans) on Castle DOOM: a Doom WAD port to
Castle Game Engine (CGE) in Object Pascal (FPC). Read `docs/ARCHITECTURE.md`
for how the code works; this file is about *working on it*.

## What this is

- Freedoom Phase 1/2 WADs in `data/wads/` are read directly; textures,
  sprites, sounds and music are decoded from the WAD at runtime and served to
  the engine through custom URL protocols (`doomgfx:`, `doomsfx:`, `doommus:`).
- Map geometry is generated as X3D nodes (`DoomGeometry`), things are billboard
  sprites (`DoomActors`), gameplay runs at 35 tics/s in `DoomWorld`.
- Music is OPL3 emulation: Nuked OPL3 (LGPL) is **not in the repository**;
  `tools/build_nuked_opl3.sh` downloads it at a pinned commit and builds the
  shared library into `data/lib/` (gitignored; CI runs the script in every
  package job and the autotest job). Without it the built-in FM model plays
  (and always on the web). Keep it that way: no LGPL code compiled in.
- Published at https://github.com/mariuz/castle-doom (MIT), web build at
  https://mariuz.github.io/castle-doom/ (GitHub Pages), native packages on the
  Releases page (built by CI on `v*` tags).

## Build and run (Windows, this machine)

CGE 7.0-alpha.3 snapshot with bundled FPC 3.2.2 is installed at
`C:\castle-engine` but is **not on PATH**. Use PowerShell from the project
root (`C:\Users\User\castlegamedoom`; the path must stay short, see pitfalls):

```powershell
$env:PATH = "C:\castle-engine\bin;C:\castle-engine\tools\contrib\fpc\bin;" + $env:PATH
castle-engine compile --mode=release      # or --mode=debug (range checks, slow music)
.\castle-doom.exe
```

Local sound needs `OpenAL32.dll` and `wrap_oal.dll` from `C:\castle-engine\bin`
next to the exe (they are copied already, gitignored). `castle-engine package`
bundles them for distribution.

Linux/macOS: install CGE, then the same `castle-engine compile`. Web:
`castle-engine compile --target=web` needs FPC main branch with the
`wasm32-wasip1` cross-compiler and Pas2js; the CI workflow
`.github/workflows/web.yml` shows the exact recipe (it builds them from source).

## Build and test in a Linux cloud container

No CGE there by default, but it builds: `apt-get install -y fpc libgtk-3-dev
libgtk2.0-dev libopenal1 libpng-dev xvfb`, `git clone --depth 1 --branch
snapshot https://github.com/castle-engine/castle-engine.git <dir>` (keep it
outside the repo, e.g. the scratchpad), then from inside `<dir>` run
`./tools/build-tool/castle-engine_compile.sh` (it needs `castle-fpc.cfg` in the current directory),
then from the project root `CASTLE_ENGINE_PATH=<dir> <dir>/tools/build-tool/castle-engine
compile --mode=release` (delete the stray `link*.res` it leaves). Autotests
run under `xvfb-run -a -s "-screen 0 1280x800x24" ./castle-doom --autotest ...`
(software GL, about 12 FPS, no sound); the log goes to stdout.

## Testing without watching the window

`tools/run_autotests.py EXE OUTDIR [test...]` runs the regression suite
(the CI `autotest` job does exactly this under `xvfb-run`): each test in
its own `XDG_CONFIG_HOME`, failing on exceptions, missing log lines or
wrong save contents. Add a test there when a feature gets a demo recipe
below.

Unit tests (FPCUnit, no window, about 20 s, 18 cases) cover the parsers,
every node format and both music synthesizers:
`castle-engine simple-compile tests/castle_doom_tests.lpr` then
`tests/castle_doom_tests --all --format=plain` from the project root (exit
code 1 on a failure; CI runs them before the autotests). The node-format
cases read `tools/testdata/nodes/*.wad` (gitignored): generate them once
with `python3 tools/make_znodes.py tools/testdata/nodes/` and `python3
tools/make_glnodes.py tools/testdata/nodes` (needs `glbsp`), else they
print "skipped". A stale `castle-engine-output/compilation/.../*.ppu` can
make the test build miss a changed unit interface: delete it. Add a case
there when changing `DoomWad`, `DoomMap`, `DoomMusic`, `DoomStates` or `DoomDehacked`.

The autotest harness is the main verification tool; use it after every change:

```powershell
.\castle-doom.exe --autotest E1M1 C:\TMP\sp\shot --demo "G:480:712,A:0,U,W:1.5,F:1.5,S,T:180,S,X,S,Q"
.\castle-doom.exe --autotest MAP01 C:\TMP\sp\d2 --demo "W:0.5,S,E,W:1,S,U,W:1,S,N,W:1,S,Q"
.\castle-doom.exe --autotest MENU C:\TMP\sp\m          # title screen screenshot
.\castle-doom.exe --autotest MENUKEYS C:\TMP\sp\k --menukeys "E,E,D,E" --demo "W:1,S,Q"
.\castle-doom.exe --autotest E1M1 C:\TMP\sp\n -skill 5 --demo "Y,D,W:25,Q"   # grep Respawn:
```

Menu screenshots: `MENU`, `MENUEPISODE`, `MENUSKILL`, `MENUNIGHTMARE`,
`MENULOAD`, `MENUOPTIONS`, `MENUDOOM2` save `<prefix>_<name>.png`.
`MENUKEYS` drives the Doom menu with `--menukeys` (U up, D down, E enter,
X escape, Y / N, S screenshot); the game it starts then runs `--demo`. Mouse
hover is disabled in menu autotests (the real cursor over the window would
move the selection). `-skill N` is Doom's 1..5; the log prints `Skill: Skill N`
and `Things: ... N monsters` (E1M1: 17 / 29 / 46 for skills 1-2 / 3 / 4-5).

Script commands: `F/B/L/R:sec` move, `T:deg` turn, `A:deg` absolute angle,
`G:x:y` go to Doom coordinates, `U` use, `X` fire, `E` exit level, `N` next
map, `K` give all weapons/ammo/keys, `C:n` select weapon n (1 fist, 2 pistol,
3 shotgun, 4 chaingun, 5 rockets, 6 plasma, 7 BFG, 8 chainsaw, 9 SSG),
`M` toggle automap, `I` reveal all map lines, `Z:f` zoom automap by f,
`V` force infighting (nearest other species), `D` kill all monsters (boss
triggers; grep the log for `Infight:` and `BossDeath:`), `Y` god mode,
`P:type:dist` spawn an awake monster (THINGS type) dist units in front
(e.g. `Y,P:3001:250,D,W:2,P:64:200` raises an imp with an Arch-vile; grep
`PainSkull:`, `Raise:`, `VileAttack:`),
`S` screenshot, `W:sec` wait, `Q` quit. Then read the screenshots (PNG)
and the log at `%LOCALAPPDATA%\castle-doom\castle-doom.log` (grep for
`Warning|Exception|Load:|Music|AutoTest`). Useful E1M1 spots: player start
(-416, 256); door at x=544..560, y=680..744 (stand at 480,712 facing angle 0);
WR lift square 64..192 x 192..320 (stand at 0,256 facing 0 and walk).

Player messages are logged as `Message:`; E1M1 pickups for a quick check:
`Y,G:416:864,W:0.3,G:2192:576,W:0.3,Q` gives "Picked up some shotgun
shells." and "Blue passcard secured!" (Freedoom's BEX strings). Menu
screenshots also take `MENUQUIT` (the quit question).

Lighting (`DoomLighting`): `DIM` toggles light diminishing (the `F` key),
`INVUL[:tics]` gives invulnerability (inverted greys), `AMP[:tics]` the
light amplification visor (colormap 1); `INVUL:1` / `AMP:1` end them. `Y`
is a separate god mode flag now, so god-mode screenshots keep normal
colours. Fire (`X`) and screenshot after `W:0.03` to see the flash light.
The light goes through the real `COLORMAP` (log `Graphics: Palette lookup
images made`); `PALMAP` toggles back to the old multiply, so
`W:0.5,S,PALMAP,W:0.3,S` gives a before / after pair.
Comparing several screenshots is easier as one grid image (PIL in Python).

`SHOTS` in a demo logs every player shot (`Shot:` angle, slope, range,
what it hit). Autoaim checks on E1M1: `Y,SHOTS,P:3001:300,W:0.3,X` hits an
imp ahead (slope about -0.025); from the lift, `Y,SHOTS,G:160:256,A:0,W:0.3,
P:3001:300,W:0.1,X` aims down at slope -0.26; from (-200, 256) the same imp
is hidden by the lift's edge and nothing is aimed at (Doom does the same).
`SHOTS` also logs melee turns (`Turn:`): `Y,K,SHOTS,C:1,W:1,A:0,P:3001:55,T:12,X`
punches an imp 12 degrees aside and turns onto it; `C:8` saws instead.
It logs knockback too (`Push:`): `K,SHOTS,C:5,W:1,A:180,W:0.3,X,W:1.5,S`
fires a rocket into the wall behind the start and the player ends near
(-350, 256). Crushed corpses log `Crush:`; a zombie killed in the E1M1 door
is squashed when it closes: `Y,G:480:712,A:0,U,W:1.5,CORPSE:3004:72,W:7,Q`
(`CORPSE:type:dist` spawns and kills in one frame; `P` then `D` lets the
monster walk out of the doorway first when frames are slow).

`SIGHT` in a demo logs, for every monster within 2500 units, the 2D and
3D line of sight to the player and the REJECT bit (`Sight:` lines).
`INVIS` in a demo gives partial invisibility (the weapon turns to fuzz);
`P:58:180` spawns a spectre to look at (both use Doom's `fuzzoffset`
specks; the `fuzz` autotest takes one screenshot of each).

Gibs: `D` deals 100000 damage, so it gibs every zombie, sergeant, imp and
SS (grep `Gib:`); `Y,P:3005:350` from the lift top (`G:160:256,A:0`) shows a
cacodemon rising out of the pit, and `D` then drops its corpse.

Settings (`GameSettings`, `settings.json` next to the saves; the log
prints `Settings:` when one is loaded): `VOL:sfx:music` sets both volumes
like the F4 menu (and saves them), `SOUNDMENU` opens that menu for a
screenshot. Autotests load the settings too, so delete the file after
testing volumes.

Save transfer: `--export-saves FILE` / `--import-saves FILE` write or
read the bundle and quit (they still open a window, so use `xvfb-run` in
the cloud; `Save: Exported N files`). The home page's "Your saves" JS
(`pages/index.html`) is tested with the preinstalled Playwright
(`require($(npm root -g)/playwright)`, Chromium) against
`python -m http.server` in `pages/`: seed localStorage with keys
`castle-doom:castle-config:/save1.json`..., click export, `setInputFiles`
the import.

Texture memory: each map load logs `Graphics: Freed N textures and flats
of earlier levels (K KB); ... cached`; walk maps with `N` and come back
with `LOAD:n` to check that released textures (and animated flats) return.

Freedoom Phase 2 on demand (the web build has only Phase 1 in its data):
`--wad-base-url http://127.0.0.1:PORT/` makes the desktop fetch
`freedoom2.zip` from there like the browser does from the page's
directory (log `WAD: Downloading` / `Downloaded` / `Loaded
freedoom2-zip:/freedoom2.wad`); the `phase2-download` autotest serves it
from a local HTTP server.

Menus: `MENUTITLE` (title pages without the menu) and `MENUREADTHIS`
(F1) are menu screenshots too; the other `MENU*` open the menu first.
In a game, `KEY:name` presses UP / DOWN / LEFT / RIGHT / ENTER / ESCAPE /
BACKSPACE / F1..F4 through `Press`, e.g. `KEY:F2,KEY:DOWN,KEY:ENTER,KEY:ENTER`
saves slot 2 from Doom's save page (the first Enter starts editing the
name, the second keeps it); `TYPE:text` types characters (no commas).

Pause / pointer lock: `UNLOCK` does what the browser's Esc does (cancels
the pointer lock, so Doom's menu opens over the paused game; log
`PointerLock:`), `RESUME` closes it like Esc or a click beside it. The save's `tic` must not move while paused.

`CLICKPROMPT` shows the browser's "click to look around" prompt in an
autotest (it is hidden in autotests otherwise). Gamepads (`GameGamepad`)
log `Gamepad: Controller N: name` at startup (and on the web whenever the
pad list changes); there is no controller in the cloud container, so the
desktop mapping is only read, and the unit test `TestWebPadMapping` feeds
a fake browser pad through `ApplyWebPads`. The web build polls
`navigator.getGamepads()` itself (log `Gamepad: Browser Gamepad API`);
Playwright can fake a pad with `page.addInitScript` replacing
`navigator.getGamepads` by a function returning `[{id, connected: true,
mapping: 'standard', axes: [...], buttons: [{pressed, value}, ...]}]`
(a time-driven script: e.g. the right trigger pressed after 15 s with
demo `Y,SHOTS` logs `Shot:` lines, Start opens the menu). The Web
workflow builds every branch; download its `web-site` artifact
(`gh api repos/mariuz/castle-doom/actions/artifacts` works here, `gh run`
does not), unzip it into an empty directory, serve it with `python3 -m
http.server` and point Playwright at `play/?map=...`.

Profiling: `PERF` logs a `PerfView:` line at once (also every 10 s): our
per-frame costs, CGE's FPS (`only render` = without display waits) and the
last frame's render statistics (shapes, scenes, draw calls). `NOSPRITES`
and `NOMAP` toggle the things' batch scenes / the map geometry to see what
each costs, `PALMAP` the palette lookup. E1M1 at `G:480:712,A:0` draws
about 56 shapes: 21 map (one per chunk and atlas page; `--no-atlas` gives
the old 151, one per texture per chunk) and 35 sprites (the 104 visible
quads merged per texture and light group by `TSpriteBatch`; before it
they were 104 in 104 scenes). The log's `Atlas:` lines give the page
count and sizes (E1M1: 150 images, one 2048x1024 page). `SPRITESTATS` logs how many sprites are shown and how many
distinct texture|light group|kind combinations they have (the sprite
draw calls if all were in view: 208 and 87 on E1M1).
`CASTLE_DOOM_LOG_SHADERS=1` logs every shader compile and link; during
play the count must stay at the level's initial ~70 (it grew by 7 a
second with CGE's dynamic batching, which is why the sprites are merged
by the game). In the browser the same runs through the
page URL: `play/?map=E1M1&demo=G:480:712,A:0,W:30,PERF` (`S` only logs,
`Q` ends the demo; `warp=` and `skill=` work too). A headless Chromium with
SwiftShader (Playwright, `--use-angle=swiftshader`) loads the live page in
the cloud container; its software GL exaggerates fill cost, so trust the
draw-call counts and a CDP CPU profile (wasm vs JS glue time), not its FPS.

`LOOK:deg` pitches the view (negative looks down), for sky and floor
screenshots.

Sector specials: `LINE:n[:special]` activates linedef n (as another
special with the same tag if given; `Line:` log). MAP05's donut:
`Y,G:-64:408,A:-90,W:0.3,U,W:9,SAVE:2` (grep `Donut:`; sectors 54 and 53
end at floor 0, 53 in GRASS1). MAP04's slow crusher with a barrel under
it (`P:2035:192` from the south; a god-mode player under it is flaky: the
camera's collision with the ceiling depends on the frame rate), stopped
and resumed:
`Y,G:704:1600,A:90,W:0.2,P:2035:192,W:0.1,LINE:269,W:2,SAVE:3,LINE:269:74,W:2,SAVE:4,LINE:269,W:2,SAVE:5`
(sector 82's ceiling and mover speed 0.125 in the saves). Reading a save's
JSON (`sectorFloor`, `sectorCeiling`, `movers`) is the easy way to check
heights.

Monster wake-up: grep `Wake:` (sprite, position, `saw` / `heard` /
`heard and saw (ambush)`) and `Noise:` (sectors a new shot reached). On
E1M1, `Y,X,W:1,G:480:712,A:0,U,W:1.5,X,W:2,Q` gives 38 sectors from the
start (the two ambush zombies wake) and then 60 beyond the door.

Screen melt: the log says `Wipe: Melt started` / `Melt done`. Five `U`
presses already finish an intermission (and load the next map), so take
melt screenshots right after them: `E,W:2,U,U,U,U,U,W:0.2,S,W:0.2,S`.

Finales: `E` exits the level, `U` presses a key on the intermission /
finale. `--autotest E1M8 p --demo "E,W:4,S,U,W:0.5,S,U,W:0.5,S,Q"` shows
the typing, the full text and the CREDIT picture; E3M8 with `E,W:1,U,W:0.3,U,W:35,S,Q`
the bunny with THE END; MAP30 with `E,W:1` and five `U,W:0.3` reaches the
cast call. Do not press `U` on the last screen of a game-ending finale in a
script: it returns to the title and the demo (and `Q`) stops running.

Monster teleports: MAP07 has a room of monster-only 126 lines in open
space; `--autotest MAP07 p --demo "Y,G:-1089:1064,A:189,P:3001:150,W:3,S,Q"`
spawns an imp that walks over one; grep `Teleport:` (it lands at
(-1312, 256)).

Icon of Sin: `--autotest MAP30 prefix --demo "Y,G:-2208:3000,A:90,W:12,S,D,W:4,Q"`
puts the player in the arena facing the face; grep `BrainAwake:`,
`BrainSpit:`, `BrainSpawn:`, `BrainDeath:` (`D` kills the brain too, and the
level exits 120 tics later).

Save games: `SAVE:n` / `LOAD:n` (0 = quick save) and `MENU:1|2|0` in a demo
script, `-loadgame N` on the command line (works with `--autotest X prefix`
for screenshots). Files: `%LOCALAPPDATA%\castle-doom\save1..6.json`,
`quicksave.json`; log lines start with `Save:` ("restored N actors, M
movers"). A good round trip on E1M1:
`K,D,W:1.5,G:480:712,A:0,U,W:0.6,X,SAVE:1,S,E,W:0.5,U,U,U,W:2,X,S,LOAD:1,W:0.3,S`
(HUD values after the load must equal the ones at the save). When adding
state to `TDoomWorld`, `TDoomActor` or `TSectorMover`, add it to
`doomworld_save.inc` too.

External WADs: `-iwad FILE -file PWAD... -warp MAP` work together with
`--autotest`; a PWAD that replaces E1M1 with E1M2's lumps is an easy override
test (E1M1 must then log 2231 vertices). `-deh PATCH...` (or `-bex`) applies
DeHackEd patches after the WADs' `DEHACKED` lumps; the log prints `DeHackEd:
<source>: N values applied, M not supported` for each.
`tools/testdata/test.deh` makes the imp 1 HP, the start 50 health and 20
bullets, E1M1's par 999 s, the imp's first attack frame 1 tic, gives the
imp the demon's bite (`Pointer 1 (Frame 454)`, A_SargAttack) and the
zombieman the sergeant's three pellets (`[CODEPTR] FRAME 185 =
A_SPosAttack`). The state table behind frames and code pointers is
`code/doomstates_table.inc`, generated by `tools/make_states.py` from
linuxdoom-1.10's `info.c`, `info.h` and `sounds.h` (fetch them from
github.com/id-Software/DOOM into a scratch directory; only the numbers
are used): regenerate rather than edit, and note `Raise` is a reserved
word (the field is `RaiseState`). Freedoom's own `DEHACKED` lump makes
frames 185, 419, 685, 687, 689 full bright and trims the SSG flash, so
the log says `DEHACKED lump: 34 values applied`.

Music prefetch: `W:90,E,W:1,U,U,U,U,U,W:3,Q` on E1M1 (software GL renders
songs slowly, so wait long) logs `Rendered D_E1M2` during the level and
`Playing D_E1M2, rendered before` on the next one; `Music: Released` lines
show freed songs; the intro log line (`Playing the first 8.x s of ...
while the rest renders (ready after N ms)`) says how long after the
level start the music began: a few frames, it is rendered in slices.

Set `CASTLE_DOOM_DUMP_MUSIC=<dir>` to write rendered music WAVs for analysis
(a pitch-grid/level check script lived in the scratchpad as `analyze_wav.py`:
Goertzel on semitone vs quarter-tone frequencies). The log says which
synthesizer runs: `Music: Nuked OPL3 loaded from <path>` (or why not) at
startup and `Rendered D_E1M1 with Nuked OPL3 / the built-in FM synthesizer`
per song; `--fm-synth` forces the built-in one, `CASTLE_DOOM_OPL3=<file>`
points at another library build. Nuked renders about 1.6x slower than the FM
model (E1M1's 132 s song: 5 s of CPU, in 12 ms slices per frame), so a demo
waiting for `Rendered` under xvfb needs `W:80`. The unit test `TestOpl3Synth`
renders a song with both and expects them to differ; the `music-opl3`
autotest only checks the library loads.

## Pitfalls learned the hard way

- **Long paths break the build.** FPC/castle-engine fail silently-ish
  ("manifest not found", `EFCreateError`) when the project path is near Win32's
  260-char limit. Keep the project at a short path; do not build from inside
  the Claude scratch workspace. Git Bash resolves junctions to the long real
  path, so run the build tool from PowerShell.
- **Do not add `standalone_source` to `CastleEngineManifest.xml`**; the build
  tool generates the program file. `castleautogenerated.pas` and the
  `castle_doom_standalone.*` files *are* committed because the web target needs
  `CastleAutoGenerated` to exist.
- **One X3D node must not live in two `TCastleScene`s** (the engine warns).
  Create a fresh `TImageTextureNode` per use via `TDoomImage.MakeTextureNode`;
  sharing happens through the URL cache.
- **Moving X3D nodes between scenes**: `RemoveChildren` keeps `Node.Scene`
  (the next scene warns "already part of another TCastleScene"), so call
  `Node.UnregisterScene` after it; and `AddChildren` rebuilds the shape
  tree (`ChangedAll`) without clearing the scene's `TransformationDirty`
  list, so a transform changed earlier in the same frame leaves a dangling
  pointer and the next `Update` dies with a corrupt depth (`EOutOfMemory`
  from `FinishTransformationChanges`). Call `Scene.BeforeNodesFree` before
  adding (`TSpriteGroup.ShapeFor`). CGE's dynamic batching never merges
  shapes under a group `Effect` node (`State.Effects` is compared by
  pointer), keeps only 8 open texture groups per pass (`MergeSlots`), and
  its pool shapes, switching appearances every frame, make the renderer
  drop and relink shader programs (the cache frees a program at its last
  reference; effect nodes are hashed by pointer) -- unusable with
  per-shape effects on the web.
- **The walk navigation can drop the player through the floor** on a slow
  frame (CI's `icon-of-sin` once logged a feet Z of -1e23 and NaN
  transforms: a long frame stepped the fall through MAP30's floor and
  CGE's `FallSpeedIncrease` then grew it without bound). `TViewPlay.Update`
  puts the feet back on the sector floor and cancels the fall (log
  `Player: Below the floor`); a timeout of an autotest with a huge Z in
  its screenshot line is that.
- **GLSL in effects**: do not name a sampler parameter `texture`: CGE
  renames `texture2D` to `texture` on newer GLSL and the parameter shadows
  it ("no matching function for call to texture(sampler2D, vec2)"). A
  texture-level effect (`TImageTextureNode.SetEffects`) is what reaches
  `PLUG_texture_color`; group effects are plugged before the texture code
  exists. FPC refuses a `for` counter in a routine that has nested
  routines ("Illegal counter variable"): loop in a separate method.
- **`TCastleContainer.SetView` cannot be called inside `TCastleView.Start`**;
  use `WaitForRenderAndCall`.
- **`TCastleWalkNavigation.MoveForward` does not move by itself** (it needs the
  key's pressure value); the demo harness simulates keys with
  `Container.Pressed.KeyDown/KeyUp`.
- **`TKey` name clash**: CGE's `CastleKeysMouse.TKey` vs the project; Doom keys
  are `TDoomKey`.
- **Reserved words**: `Program` cannot be a field name (`Prog` is used).
- **Pascal evaluates every argument**: `BoolToStr(X = nil, 'a', X.Field)` or
  `IfThen(...)` still dereferences `X`; branch with `if` instead (this
  crashed the Arch-vile log line once).
- **Test windows open on the user's desktop**; a stray key press reaches the
  game (one run started MAP03 instead of MAP02 via the menu's arrow keys).
  Rerun before suspecting the code.
- **FPC main branch (web) differs from 3.2.2**: `Generics.Defaults`
  `TComparison<T>` is an anonymous-function type there, so `@Function`
  comparers fail; `DoomMusic` uses its own merge sort. Prefer plain code over
  generics tricks.
- **PNG is too slow in WebAssembly** for hundreds of textures per level
  (caused Chrome's "page unresponsive"); the `doomgfx:` protocol serves TGA.
- **Web build toolchain**: FPC's `make install` installs a bare `pas2js` into
  `fpc/bin` that shadows the real one (error `can't find unit "System"`);
  the workflow deletes it. The `actions/cache` post step does not run on
  failure, so the toolchain is saved explicitly with `actions/cache/save`.
- **Node formats**: vanilla and all ZDoom extended variants load (see
  ARCHITECTURE section 5). After touching `DoomMap`, run
  `python tools/make_znodes.py C:\TMP\sp` and load each generated
  `e1m1_*.wad` with `-file`; the log must show "682 subsector polygons, total
  area 6712683" for every format. glBSP GL nodes: `python tools/make_glnodes.py
  DIR` (needs `glbsp`, apt) writes `e1m1_gl_v1/2/3/5.wad`; glBSP builds its
  own BSP, so they log 717 subsector polygons, area 6713389 (V1 6691431: its
  GL vertices are whole units); the `glbsp-nodes` autotest checks them.
  UDMF is not supported.
- **`{$ifdef WASI}` code only compiles in CI** (the web toolchain is not
  installed here). Keep such blocks small, read FPC's
  `packages/wasm-job/src/job.js.pas` for the JOB API before writing them,
  and check the Web workflow log after pushing. JOB's typed calls raise on a
  JS `null` (use `InvokeJSValueResult` for `localStorage.getItem`;
  `InvokeJSObjectResult` / `ReadJSPropertyObject` return `nil` for it),
  and a `null` read as a value is a `TJOB_Object` whose `Value` is `nil`,
  so check that before using it (`navigator.getGamepads()` is mostly
  nulls). `InvokeJSTypeOf` is useless: the JavaScript side maps the
  typeof *text* through its result mapper, so it always says "string";
  test for a function with `ReadJSPropertyValue` being a non-nil
  `TJOB_Object` (`GameGamepad.HasFunction`). To test the deployed page,
  open https://mariuz.github.io/castle-doom/play/ in the browser pane;
  the browser console shows the CGE log; a branch's build is the Web
  workflow's `web-site` artifact (see Gamepads above).
- **WebGL read-back in CGE**: colour read-back (`SaveScreen_NoFlush`,
  `Container.SaveScreen`) was a "TODO: web" that gave an empty image in the
  browser. castle-engine/castle-engine PR #738 fixed it and is merged into
  CGE `master` (merge commit a7c126b, 2026-10-08), but the web build uses the
  `snapshot` **tag** (not a branch; `git ls-remote ... snapshot`), which
  still points at c463cb6 from before the merge. Until the tag moves, keep
  screen captures on the GPU (`TDrawableImage.RenderToImageBegin` +
  `Container.RenderControl`, as the melt does). Depth read-back
  (`SaveScreenDepth_NoFlush`) is PR #739 (open). `TGLRenderToTexture` with
  `tbNone` raised an exception in the browser.
- **JOB Variant casts can crash WebAssembly**: converting a non-null
  `glGetParameter(GL_FRAMEBUFFER_BINDING)` result with
  `TJSWebGLFramebuffer.Cast(Variant)` aborts the program with "function
  signature mismatch" (a `null` result through `VarIsNull` is fine). Track
  such state in Pascal instead of querying it back.
- **Testing an engine patch on the web**: a throwaway branch whose
  `web.yml` curls the patched CGE files over the snapshot (pin the fork
  commit SHA in the raw.githubusercontent.com URL: branch URLs are cached
  for minutes; curl every file the patch touches), uploads
  `castle-engine-output/web/dist` as an artifact (no deploy job, and a
  different `concurrency` group so it cannot cancel the Pages deploy), and
  runs on push to that branch; `gh run download` it and serve it with
  `python -m http.server` (a `.claude/launch.json` entry) to open in the
  browser pane. Focus the canvas with JS (`canvas.focus()`) instead of a
  click, which can hit a menu item. The pane renders slowly (about 2 FPS), so
  a hook that fires at frame N takes a while; read the result with the
  console tool. Its filter is a plain substring, not a regex. Delete the
  branch afterwards.
- **Exceptions abort the WebAssembly program**: FPC's wasm32 target has no
  setjmp/longjmp, so any raised exception (even inside `try`/`except`)
  stops the web build ("Runtime error 217", "LONGJMP not supported"). Code
  that runs on the web must check conditions instead of relying on
  exceptions; test new web paths on the live page and watch the console.
- **Web performance**: watch the `Perf:` / `PerfView:` lines in the browser
  console. Textures that are resized to powers of two or mipmapped are CPU
  work in WebAssembly; sprites use `GuiTexture`.
- **FPC on wasm32**: loop counters must be 32-bit (`Int64` loop variables do
  not compile there).
- **Pointer lock on the web**: the browser keeps Esc and only releases the
  mouse; the game learns it through
  `Container.PointerLock.AddUserCancelledListener` (then pauses), and may
  ask for the lock again only inside a user gesture (a click / key press
  handler), so mouse look is re-enabled from `Press`, never from `Update`.
- CGE log goes to `%LOCALAPPDATA%\castle-doom\castle-doom.log`; `WritelnLog`
  also reaches the browser console on the web.

## Conventions

- CGE style: 2-space indent, `begin`/`end` on their own lines, PascalCase
  identifiers (even `String`, `Boolean`), no `with`. Units are `Doom*` for
  engine-independent logic and `Game*` for CGE views.
- Doom coordinates everywhere in the simulation (X, Y map, Z height, degrees
  counter-clockwise from east, 35 tics/s); convert only at the CGE boundary
  with `DoomToCge`/`CgeToDoom`.
- Linedef/sector special numbers follow vanilla Doom; keep the big `case` in
  `TDoomWorld.ApplySpecial` grouped by activation (use / cross / shoot).
- When adding a feature that moves or re-lights a sector, make sure
  `ComputeDynamicSectors` marks it dynamic, otherwise the static chunk will not
  update.
- Keep the README feature list, `pages/index.html` controls and the help panel
  in `GameViewPlay` in sync when adding keys.

## Git / CI

- Jobs have `timeout-minutes`; if a run still hangs, `gh run cancel <id>`
  then `gh run rerun <id>` once the cancel has gone through.
- `main` is the only branch; every push builds Windows, Linux and macOS
  (x86_64 and aarch64) packages in `build.yml`, each on its own runner
  with FPC and the CGE snapshot from castle-build-ci (the CGE Docker image
  was dropped: Docker Hub's pull rate limit failed every third run), plus a Windows MSI (WiX 5 on `windows-latest`, source from
  `tools/make_msi_wxs.py`; WiX does not run on Linux, so only CI tests it),
  and deploys the web build (`web.yml`). Tags `vX.Y.Z` create a
  GitHub Release with the packages; when a session cannot push tags, run
  `Build` by hand (workflow_dispatch) with `release_tag=vX.Y.Z`, which
  creates the tag and the release (notes from `docs/CHANGELOG.md`). Check runs with
  `gh run list --repo mariuz/castle-doom` and `gh run view <id> --log-failed`.
- Commit messages: imperative summary, then what/why; end with the
  `Co-Authored-By` line when an agent wrote the change.

## What to work on next

`docs/ROADMAP.md` is the prioritized list of missing features with pointers
into the code and size estimates. Pick from its "Suggested next three" unless
the user asks for something specific, and update the roadmap when an item is
done.
