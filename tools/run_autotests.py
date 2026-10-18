#!/usr/bin/env python3
"""Run Castle DOOM's --autotest scripts and check what they log.

Usage (Linux, needs an X display; CI wraps it in xvfb-run):
    xvfb-run -a -s "-screen 0 1280x800x24" python3 tools/run_autotests.py ./castle-doom out

Every test runs the game with its own config directory (XDG_CONFIG_HOME), so
saves and settings never leak between tests or into the developer's own.
A test fails when the game exits with an error, logs an exception, misses an
expected log line, or a check on its saved game fails. Logs and screenshots
end up in the output directory (CI keeps them as an artifact).

Golden screenshots: the screenshots named in GOLDEN are compared with the
references in tools/golden/ (320x180 PNGs, scaled down from CI's own
1600x900 screenshots, so the comparison tolerates software GL's small
differences and the FPS text); a screenshot fails when more than
GOLDEN_MAX_CHANGED of its pixels differ by more than GOLDEN_PIXEL in some
channel, and writes golden-diff-NAME.png next to it. Needs Pillow (CI
installs python3-pil); without it the comparison is skipped.
    run_autotests.py EXE OUT --update-golden     # write OUT's screenshots as references
"""

import json
import os
import re
import shutil
import subprocess
import sys
import time

TIMEOUT = 300  # seconds per run; software GL runs at about 12 FPS


def save_json(config, slot):
    with open(os.path.join(config, 'castle-doom', 'save%d.json' % slot)) as f:
        return json.load(f)


def check_donut(config):
    """MAP05's donut: pillar 54 and ring 53 end at floor 0, the ring in GRASS1."""
    s = save_json(config, 2)
    floors, texs = s['sectorFloor'], s['sectorFloorTex']
    assert floors[54] == 0 and floors[53] == 0, 'donut floors %s %s' % (floors[54], floors[53])
    assert texs[53] == 'GRASS1', 'ring texture %s' % texs[53]


def check_crusher(config):
    """MAP04's slow crusher on a barrel: 1/8 speed, stopped, resumed."""
    c = [save_json(config, n)['sectorCeiling'][82] for n in (3, 4, 5)]
    speeds = [[m['speed'] for m in save_json(config, n)['movers'] if m['sector'] == 82] for n in (3, 4, 5)]
    phases = [[m['phase'] for m in save_json(config, n)['movers'] if m['sector'] == 82] for n in (3, 4, 5)]
    assert all(s == [0.125] for s in speeds), 'crusher speeds %s' % speeds
    assert phases[1] == [3], 'crusher not in stasis: %s' % phases
    assert c[0] < 56 and abs(c[1] - c[0]) <= 1 and c[2] < c[1] - 4, 'crusher ceilings %s' % c


def check_options(config):
    """Doom's options and sound pages change and remember the settings."""
    with open(os.path.join(config, 'castle-doom', 'settings.json')) as f:
        s = json.load(f)
    assert s['mouseSensitivity'] == 6 and s['sfxVolume'] == 14, 'settings %s' % s


def check_typed_name(config):
    """Doom's save page takes a typed name (digits type, they do not pick a slot)."""
    d = save_json(config, 1)['description']
    assert d == 'MY BASE 1', 'description %r' % d


def check_dehacked(config):
    """tools/testdata/test.deh: Misc initial health / bullets, Ammo 0 max ammo."""
    s = save_json(config, 1)
    p = s.get('player', s)
    assert p['health'] == 50 and p['ammo'][0] == 20 and p['maxAmmo'][0] == 100, \
        'player %s %s %s' % (p['health'], p['ammo'], p['maxAmmo'])


def check_pause(config):
    """The game stands still while paused (pointer lock cancelled), runs after resuming."""
    t = [save_json(config, n)['tic'] for n in (1, 2, 3)]
    assert t[1] - t[0] <= 10, 'tics while paused: %s' % t
    assert t[2] - t[1] >= 20, 'tics after resuming: %s' % t


# name, map, demo script, expected log regexes, extra arguments, check
TESTS = [
    ('menu', 'MENU', None, [r'AutoTest'], [], None),
    ('save-round-trip', 'E1M1',
     'K,D,W:1.5,G:480:712,A:0,U,W:0.6,X,SAVE:1,S,LOAD:1,W:0.3,S,Q',
     [r'Save: E1M1: restored \d+ actors', r'Gib: '], ['--fixed-step'], None),
    ('knockback', 'E1M1', 'K,SHOTS,C:5,W:1,A:180,W:0.3,X,W:1.5,S,Q',
     [r'Push: player by \d+ damage'], ['--fixed-step'], None),
    ('door-crush', 'E1M1', 'Y,G:480:712,A:0,U,W:1.5,CORPSE:3004:72,W:7,S,Q',
     [r'Crush: POSS .* crushed to gibs'], [], None),
    ('melee-turn', 'E1M1', 'Y,K,SHOTS,C:1,W:1,A:0,P:3001:55,T:12,W:0.1,X,W:0.3,S,Q',
     [r'Turn: from'], ['--fixed-step'], None),
    ('arch-vile', 'E1M1', 'Y,P:3001:250,D,W:2,P:64:200,W:4,S,Q',
     [r'Raise: Arch-vile raised TROO'], [], None),
    ('texture-memory', 'E1M1', 'W:0.5,N,W:2,S,Q',
     [r'Graphics: Freed [1-9]\d* textures'], [], None),
    ('donut', 'MAP05', 'Y,G:-64:408,A:-90,W:0.3,U,W:9,SAVE:2,S,Q',
     [r'Donut: pillar 54 and ring 53'], ['--fixed-step'], check_donut),
    ('crusher', 'MAP04',
     # A barrel under it (not the player: the camera's collision with a
     # descending ceiling depends on the frame rate).
     'Y,G:704:1600,A:90,W:0.2,P:2035:192,W:0.1,LINE:269,W:2,SAVE:3,LINE:269:74,W:2,SAVE:4,'
     'LINE:269,W:2,SAVE:5,Q',
     [r'Line: line 269 special 74'], [], check_crusher),
    # The Nuked OPL3 library (data/lib, built by tools/build_nuked_opl3.sh)
    # loads and renders the intro of the level's song.
    ('map-component', 'MAPCOMPONENT', None,
     [r'DoomMap: E1M1 from castle-data:/wads/freedoom1.wad: 182 sectors, \d+ things shown',
      r'AutoTest: Design shows E1M1: camera at the player start \(-416, 256\)', r'AutoTest: Design screenshot saved'], [], None),
    ('inspector', 'E1M1', 'W:1,INSPECTOR,W:1.5,S,INSPECTOR,W:0.3,Q',
     [r'AutoTest: Inspector toggled', r'Inspector: Opened', r'AutoTest: Saved screenshot 1',
      r'Inspector: Closed'], [], None),
    ('music-opl3', 'E1M1', 'W:6,Q',
     [r'Music: Nuked OPL3 loaded from', r'Playing the first \d+\.\d s of D_E1M1'], [], None),
    ('title-pages', 'MENUTITLE', None, [r'Menu screenshot MENUTITLE'], [], None),
    ('read-this', 'MENUREADTHIS', None, [r'Menu screenshot MENUREADTHIS'], [], None),
    ('ingame-save-load', 'E1M1',
     'W:0.3,KEY:F2,W:0.3,S,KEY:DOWN,KEY:DOWN,KEY:ENTER,KEY:ENTER,W:0.5,KEY:F3,W:0.3,S,KEY:ESCAPE,'
     'KEY:F3,KEY:DOWN,KEY:DOWN,KEY:ENTER,W:1,Q',
     [r'Save: Saved E1M1 to castle-config:/save3\.json', r'Save: Loading castle-config:/save3\.json',
      r'Save: E1M1: restored'], [], None),
    ('ingame-options', 'E1M1',
     'W:0.3,KEY:ESCAPE,KEY:DOWN,KEY:ENTER,KEY:DOWN,KEY:DOWN,KEY:RIGHT,KEY:DOWN,KEY:ENTER,'
     'KEY:LEFT,W:0.2,S,KEY:ESCAPE,KEY:ESCAPE,KEY:ESCAPE,KEY:ESCAPE,KEY:DOWN,KEY:DOWN,KEY:ENTER,'
     'KEY:DOWN,KEY:ENTER,W:0.3,S,KEY:ESCAPE,Q',
     [r'Saved screenshot 2'], [], check_options),
    ('typed-save-name', 'E1M1',
     'W:0.3,KEY:F2,KEY:ENTER,' + ','.join(['KEY:BACKSPACE'] * 16) +
     ',TYPE:MY BASE 1,KEY:ENTER,W:0.3,KEY:F3,W:0.3,S,KEY:ESCAPE,Q',
     [r'Save: Saved E1M1 to castle-config:/save1\.json'], [], check_typed_name),
    ('pointer-lock-pause', 'E1M1', 'W:0.5,SAVE:1,UNLOCK,W:2,S,SAVE:2,RESUME,W:1,SAVE:3,Q',
     [r'PointerLock: Cancelled by the user, pausing'], [], check_pause),
    # Doom's mouse sensitivity formula: 0.088 degrees a pixel at the default 5.
    ('mouse-sensitivity', 'E1M1', 'W:0.3,Q',
     [r'MouseLook: Sensitivity 5: 0\.0879 degrees a pixel'], [], None),
    ('click-prompt', 'E1M1', 'W:0.3,CLICKPROMPT,W:0.3,S,Q', [r'Saved screenshot 1'], [], None),
    ('palette', 'E1M1', 'W:0.5,S,INVUL,W:0.3,S,PALMAP,W:0.3,S,Q',
     [r'Graphics: Palette lookup images made', r'Saved screenshot 3'], [], None),
    ('fuzz', 'E1M1', 'Y,W:1,P:58:250,W:0.2,S,INVIS,W:0.3,S,Q',
     [r'Spawn: SARG', r'Saved screenshot 2'], ['--fixed-step'], None),
    # A -deh patch: a 1 HP imp dies to one bullet, Freedoom's DEHACKED lump
    # is read too, the patch's par time (999 s) is what the intermission uses.
    ('dehacked', 'E1M1', 'Y,W:0.3,SAVE:1,SHOTS,P:3001:300,W:0.3,X,W:0.5,Q',
     [r'DeHackEd: DEHACKED lump: \d+ values applied', r'DeHackEd: test\.deh: 14 values applied',
      r'Shot: .* hit TROO \(-\d+ health left\)'],
     ['-deh', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'testdata', 'test.deh')],
     check_dehacked),
    # The thing under the crosshair selected in the inspector, and CGE's
    # profiler with the map load stages (--profile).
    # Debug drawing (GameDebugDraw): every wireframe over E1M1, then
    # without the subsectors.
    ('debug-draw', 'E1M1', 'Y,W:0.3,P:3001:250,X,T:20,X,T:-40,DEBUG:all,W:0.2,S,DEBUG:subsectors,W:0.1,S,Q',
     [r'Debug: subsectors shown \(2817 segments\), blocking shown \(1094 segments\), actors shown, shots shown',
      r'Debug: subsectors hidden'], ['--fixed-step'], None),
    ('select-thing', 'E1M1', 'Y,P:3001:300,W:0.5,SELECT,W:0.5,S,PROFILE,Q',
     [r'Select: TROO_\d+: TROO, state \w+, 60 health, action \w*, \d+ tics left, target player',
      r'- Load E1M1 \(DoomWorld\)', r'- Build geometry', r'- Spawn things'],
     ['--profile', '--fixed-step'], None),
    # Video options: field of view, UI scale and render scale, saved.
    ('video-settings', 'E1M1', 'W:0.3,FOV:110,UISCALE:150,RENDERSCALE:50,W:0.3,S,Q',
     [r'Settings: Video: field of view 110, window, UI scale 150%, render scale 50%', r'Saved screenshot 1'],
     [], None),
    # Boom's ANIMATED and SWITCHES lumps from a PWAD (tools/make_boom_wad.py):
    # E1M1's line 753 switch turns into STARTAN3.
    ('boom-lumps', 'E1M1', 'Y,G:2064:-260,A:90,W:0.5,U,W:0.5,S,Q',
     [r'Graphics: ANIMATED lump: 2 animations, 2 of them in this WAD', r'Graphics: SWITCHES lump: 2 switches',
      r'Switch: line 753: SW1BRN1 -> STARTAN3'],
     ['-file', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'testdata', 'boom.wad')], None),
    # CASTLE_DOOM_LOG writes a log of only some categories (GameLogFilter).
    ('log-filter', 'E1M1', 'Y,SHOTS,W:0.3,X,W:0.3,Q',
     [r'Log: Categories Load,Shot \(CASTLE_DOOM_LOG\) also go to', r'Shot: '],
     ['ENV:CASTLE_DOOM_LOG=Load,Shot'], lambda config: check_log_filtered(config)),
    # Key rebinding: the Controls page binds Q to "Use" (saved), and in a
    # game BIND moves fire to F and forward to I.
    ('controls-page', 'MENUCONTROLS', None, [r'Settings: Keys: .*use Q / Space;', r'Settings: Mouse: .*use Right;'], [],
     lambda config: check_keys(config, 'use', ['Q', 'Space'])),
    ('key-bindings', 'E1M1', 'Y,SHOTS,BIND:fire:F,BIND:forward:I,W:0.3,F:1,KEY:F,W:0.3,S,Q',
     [r'Settings: Keys: forward I / Up;.* fire F;', r'Shot: ', r'Saved screenshot 1 at E1M1 \(player -[1-3]\d\d\.'],
     ['--fixed-step'], lambda config: check_keys(config, 'fire', ['F', 'None'])),
    # The Controls page's hotkeys page binds K to light diminishing; in a
    # game Q selects the rocket launcher, R the next weapon, L turns the
    # light diminishing off and F (no longer bound) does nothing.
    ('controls-hotkeys', 'MENUCONTROLSHOTKEYS', None, [r'Settings: Keys: .*lightDiminish K;'], [],
     lambda config: check_keys(config, 'lightDiminish', ['K', 'None'])),
    ('hotkey-bindings', 'E1M1',
     'Y,K,BIND:weapon5:Q,BIND:nextWeapon:R,BIND:lightDiminish:L,W:0.3,KEY:Q,W:1.5,SAVE:1,'
     'KEY:R,W:1.5,SAVE:2,KEY:L,KEY:F,W:0.3,Q',
     [r'Settings: Keys: .*weapon5 Q;.*nextWeapon R;.*lightDiminish L;'], [],
     lambda config: check_hotkeys(config)),
    # Mouse bindings: the right button fires and the left one uses, so a
    # left click spends no bullet and a right one does; the wheel still
    # changes weapons (pistol -> fist). The Controls page (MENUCONTROLS
    # above) also binds the right button to Use.
    ('mouse-bindings', 'E1M1',
     'Y,MBIND:fire:Right,MBIND:use:Left,W:0.5,MOUSE:Left,W:1,SAVE:1,MOUSE:Right,W:1,SAVE:2,'
     'MOUSE:WheelUp,W:1.5,SAVE:3,Q',
     [r'Settings: Mouse: fire Right; .*use Left;'], [],
     lambda config: check_mouse(config)),
    # Gamepad bindings (GameSettings.Pad): the right trigger fires, RB
    # changes weapon, then Y is bound to fire and LT to the automap.
    ('gamepad-bindings', 'E1M1',
     'Y,K,SHOTS,W:1,PADDOWN:RT,W:0.2,PADUP:RT,PADDOWN:RB,PADUP:RB,PADBIND:fire:Y,PADBIND:automap:LT,'
     'PADDOWN:Y,W:0.2,PADUP:Y,PADDOWN:LT,W:0.1,PADUP:LT,W:0.3,S,Q',
     [r'Gamepad: RT: fire', r'Gamepad: RB: nextWeapon', r'Settings: Gamepad: fire Y;.* automap LT;',
      r'Gamepad: Y: fire', r'Gamepad: LT: automap', r'Shot: '], [],
     lambda config: check_pad(config, 'fire', ['Y', 'None'])),
    ('controls-pad', 'MENUCONTROLSPAD', None, [r'Settings: Gamepad: fire RT / Y;'], [],
     lambda config: check_pad(config, 'fire', ['RT', 'Y'])),
    # Touch controls (GameTouch) with the mouse as fingers: the stick walks
    # forward, a drag turns right, FIRE shoots, MENU pauses.
    ('touch-controls', 'E1M1',
     'Y,W:0.3,S,SAVE:1,TDOWN:1:0.2:0.5,TMOVE:1:0.2:0.65,W:1,TUP:1,SAVE:2,'
     'TDOWN:2:0.6:0.5,TMOVE:2:0.65:0.5,TMOVE:2:0.7:0.5,TUP:2,W:0.1,SAVE:3,SHOTS,'
     'TDOWN:3:0.904:0.388,W:0.3,TUP:3,TDOWN:4:0.955:0.92,TUP:4,W:0.3,S,Q',
     [r'Touch: Finger 1 down', r'Shot: ', r'Touch: Button MENU'], ['--touch', '--fixed-step'],
     lambda config: check_touch(config)),
    # The left-handed touch layout at 125%: the stick takes the right side
    # (a finger at 80% of the width walks east), FIRE is on the left (at
    # 0.12:0.44 in a 16:9 window), MENU stays at the top right (0.944:0.9).
    ('touch-layout', 'E1M1',
     'Y,TOUCHLAYOUT:left,TOUCHSIZE:125,W:0.3,S,SAVE:1,TDOWN:1:0.8:0.5,TMOVE:1:0.8:0.65,W:1,TUP:1,SAVE:2,SHOTS,'
     'TDOWN:3:0.12:0.44,W:0.3,TUP:3,TDOWN:4:0.944:0.9,TUP:4,W:0.3,Q',
     [r'Settings: Touch: left-handed, size 125%', r'Shot: ', r'Touch: Button MENU'], ['--touch', '--fixed-step'],
     lambda config: check_touch_walk(config)),
    ('controls-touch', 'MENUCONTROLSTOUCH', None, [r'Settings: Touch: left-handed, size 125%'], [],
     lambda config: check_touch_settings(config)),
    # The touch layout editor (Controls -> Touch -> Edit...) drags FIRE to
    # the screen's middle; in a game FIRE placed at 0.5:0.3 at half
    # opacity shoots there.
    ('touch-edit', 'MENUTOUCHEDIT', None, [r'Settings: Touch: .*opacity 50%, fire at 0\.500 0\.500'], [],
     lambda config: check_touch_places(config)),
    ('touch-places', 'E1M1',
     'Y,TOUCHPOS:fire:0.5:0.3,TOUCHOPACITY:50,W:0.3,S,SHOTS,TDOWN:1:0.5:0.3,W:0.3,TUP:1,W:0.3,Q',
     [r'Settings: Touch: .*opacity 50%, fire at 0\.500 0\.300', r'Shot: '], ['--touch', '--fixed-step'], None),
    # UMAPINFO from a PWAD (tools/make_umapinfo_wad.py): E1M1 renamed with a
    # story text after its intermission, then E1M3 without intermission
    # ending the game with the bunny.
    ('umapinfo', 'E1M1', 'Y,W:0.5,E,W:2,U,U,U,U,U,W:1,U,W:0.5,U,W:3,E,W:2,S,Q',
     [r'MapInfo: UMAPINFO: 2 maps', r'Message: T1: Test Hangar', r'Finale: Finale after E1M1',
      r'Load: E1M3: map parsed', r'Message: Third Test', r'MapInfo: E1M3: no intermission',
      r'Finale: Finale after E1M3 \(stage 2\)'],
     ['-file', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'testdata', 'umapinfo.wad')], None),
    # The in-game Options -> Video page (drawn in the HU font): two steps
    # of field of view and one of UI scale, applied and saved.
    ('video-menu', 'E1M1',
     'W:0.5,KEY:ESCAPE,W:0.2,KEY:DOWN,KEY:ENTER,W:0.2,KEY:DOWN,KEY:DOWN,KEY:DOWN,KEY:DOWN,KEY:ENTER,'
     'W:0.2,KEY:RIGHT,KEY:RIGHT,KEY:DOWN,KEY:RIGHT,W:0.2,S,KEY:ESCAPE,KEY:ESCAPE,KEY:ESCAPE,W:0.3,Q',
     [r'Settings: Video: field of view 100, window, UI scale 110%'], [],
     lambda config: check_video(config, 100, 110)),
    # UMAPINFO episodes and boss actions: New Game's fifth (text) episode
    # starts E1M3; killing E1M1's imps lowers sector 98 (tag 1, special 23).
    ('umapinfo-episode', 'MENUKEYS', 'W:1,S,Q', [r'Load: E1M3: map parsed', r'Message: Third Test'],
     ['-file', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'testdata', 'umapinfo.wad'),
      '--menukeys', 'E,D,D,D,D,E,E'], None),
    # ZDoom MAPINFO (tools/make_mapinfo_wad.py, the new syntax): E1M1's
    # exit picture behind its statistics, E1M3's enter picture while
    # "Entering", cluster 1's exit text, then E1M3 ends with the bunny.
    ('mapinfo', 'E1M1', 'Y,W:0.5,E,W:3,S,U,W:0.5,S,U,W:1,U,W:0.5,U,W:3,E,W:2,Q',
     [r'MapInfo: MAPINFO: 2 maps', r'MapInfo: episode "MapInfo Episode"', r'Message: E1M1: MapInfo Hangar',
      r'Finale: Finale after E1M1', r'Load: E1M3: map parsed', r'Message: E1M3: Waste Disposal',
      r'MapInfo: E1M3: no intermission', r'Finale: Finale after E1M3 \(stage 2\)'],
     ['-file', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'testdata', 'mapinfo.wad'), '--fixed-step'],
     None),
    ('mapinfo-episode', 'MENUKEYS', 'W:1,S,Q', [r'Load: E1M3: map parsed'],
     ['-file', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'testdata', 'mapinfo.wad'),
      '--menukeys', 'E,E,E'], None),
    # LANGUAGE lump (tools/make_language_wad.py): MAPINFO's lookups name
    # E1M1, its music and cluster text, an episode; GOTSHELLS replaced.
    ('language', 'E1M1', 'Y,G:416:864,W:0.3,E,W:3,U,W:0.5,U,W:1,U,W:0.5,U,W:3,Q',
     [r'Strings: LANGUAGE lump: 6 strings', r'MapInfo: episode "Language Episode"',
      r'MapInfo: E1M1: "E1M1: Language Hangar" next E1M2, secret , music D_E1M5',
      r'Message: E1M1: Language Hangar', r'Message: Picked up language shells\.',
      r'Finale: Finale after E1M1', r'Load: E1M2: map parsed', r'Message: E1M2: Communications Center'],
     ['-file', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'testdata', 'language.wad')], None),
    # MAPINFO include and intermission scripts (tools/make_include_wad.py):
    # the maps come from an included lump, the pictures from "$LUMP"s.
    ('mapinfo-include', 'E1M1', 'Y,W:0.5,E,W:3,U,W:0.5,U,W:2,Q',
     [r'MapInfo: E1M1: "Included Hangar" next E1M2.*exit picture CREDIT',
      r'MapInfo: E1M2: .*enter picture TITLEPIC', r'Load: E1M2: map parsed'],
     ['-file', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'testdata', 'include.wad')], None),
    # Intermission scripts (tools/make_wiscript_wad.py: visible splat,
    # pointer and animation patches): Doom's built-in E1 map after E1M1,
    # and IN_TEST (MAPINFO exitpic / enterpic) after E1M2.
    ('wiscript-vanilla', 'E1M1', 'Y,W:0.5,E,W:3,S,U,W:0.2,S,Q',
     [r'Intermission: E1M1: exit script with 9 spots, 10 animations'],
     ['-file', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'testdata', 'wiscript.wad'), '--fixed-step'],
     None),
    ('wiscript', 'E1M2', 'Y,W:0.5,E,W:3,S,U,W:0.2,S,Q',
     [r'Intermission: E1M2: exit script with 3 spots, 3 animations',
      r'Intermission: E1M3: enter script with 3 spots, 3 animations'],
     ['-file', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'testdata', 'wiscript.wad'), '--fixed-step'],
     None),
    ('umapinfo-boss', 'E1M1', 'Y,W:0.5,D,W:4,SAVE:1,Q',
     [r'BossDeath: E1M1: all TROO dead, UMAPINFO special 23 on tag 1'],
     ['-file', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'testdata', 'umapinfo.wad')],
     lambda config: check_floor(config, 98, -124)),
    ('generalized', 'E1M1',
     'Y,G:480:712,A:0,U,W:0.5,SAVE:1,G:0:256,A:0,F:0.4,W:1,SAVE:2,G:2064:-260,A:90,U,W:2,SAVE:3,'
     'G:832:1440,A:90,U,W:0.5,K,U,W:1,SAVE:4,G:300:1400,A:90,F:1,W:1,SAVE:5,'
     'LINE:618:12168,LINE:997:14088,W:1,SAVE:6,Q',
     [r'Generalized: line 537: door open, wait, close, delay 35 tics, turbo, DR, monsters too',
      r'Generalized: line 593: lift to lowest neighbour floor, delay 105 tics, normal, WR',
      r'Generalized: line 753: floor down to lowest neighbour floor, change texture \(trigger model\), fast, S1',
      r'Message: Blue key needed for this door',
      r'Generalized: line 421: locked door',
      r'Generalized: line 1002: door open, delay 35 tics, normal, W1',
      r'Generalized: line 618: crusher', r'Generalized: line 997: lift to perpetual'],
     ['-file', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'testdata', 'generalized.wad')],
     lambda config: check_generalized(config)),
    ('scrollers', 'E1M1', 'Y,G:-240:256,A:0,W:0.1,SAVE:1,W:1,SAVE:2,G:-440:200,A:-90,W:0.3,S,Q',
     [r'Map: E1M1: scrollers: 2 walls, 1 floors, 1 ceilings, 1 carrying floors'],
     ['-file', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'testdata', 'scroll.wad')],
     lambda config: check_carry(config)),
    ('boom-extended', 'E1M1',
     'W:2,SAVE:1,Y,LINE:593:142,LINE:618:150,LINE:753:156,LINE:528:153,LINE:997:199,W:2,SAVE:2,Q',
     [r'Message: A secret is revealed!', r'Line: line 593 special 142 tag 1: activated',
      r'Line: line 997 special 199 tag 6: activated'],
     ['-file', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'testdata', 'boomext.wad')],
     lambda config: check_boom_extended(config)),
    ('boom-teleport', 'MAP07', 'Y,A:30,W:0.3,LINE:941:209,W:0.5,Q',
     [r'Teleport: player silently to \(1528, 536\), angle 75'], [], None),
    ('friction', 'E1M1',
     'Y,G:-480:256,A:0,W:0.2,F:1.5,SAVE:1,W:1.5,SAVE:2,G:-224:200,A:90,W:0.2,SAVE:3,F:1,SAVE:4,Q',
     [r'Map: E1M1: 2 friction lines, 2 pushers'],
     ['-file', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'testdata', 'friction.wad'), '--fixed-step'],
     lambda config: check_friction(config)),
    # MBF's monster friction: an imp in the mud corridor (141) walks at
    # half its speed (about 25 units in a second, 48 on a normal floor).
    ('monster-friction', 'E1M1', 'Y,G:-224:150,A:90,W:0.2,P:3001:200,SAVE:1,W:1,SAVE:2,Q',
     [r'Map: E1M1: 2 friction lines, 2 pushers'],
     ['-file', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'testdata', 'friction.wad'), '--fixed-step'],
     lambda config: check_monster_friction(config)),
    ('pushers', 'E1M1', 'Y,G:900:-500,A:0,W:0.2,SAVE:1,W:1,SAVE:2,G:1064:-900,A:0,W:0.2,SAVE:3,W:1,SAVE:4,Q',
     [r'Map: E1M1: 2 friction lines, 2 pushers'],
     ['-file', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'testdata', 'friction.wad'), '--fixed-step'],
     lambda config: check_pushers(config)),
    # Boom's displacement / accelerative scrollers driven by the lift
    # (tools/make_dynscroll_wad.py): the corridor floor carries the player
    # while the lift moves, the south wall speeds up while it goes down.
    ('dynscrollers', 'E1M1', 'Y,G:-240:256,A:0,W:0.3,SAVE:1,LINE:593,W:2,SAVE:2,W:5,SAVE:3,Q',
     [r'Map: E1M1: scrollers: .* \(2 displacement, 1 accelerative\)'],
     ['-file', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'testdata', 'dynscroll.wad'), '--fixed-step'],
     lambda config: check_dynscrollers(config)),
    # Boom's deep water (tools/make_water_wad.py): the corridor east of the
    # start room is a 96-unit pool drawn at the start room's heights; the
    # player sinks to its real floor, the view goes under water (WATERMAP
    # tint) and back.
    ('deep-water', 'E1M1', 'Y,G:-400:256,A:0,W:0.5,S,G:-240:256,A:0,W:1.5,SAVE:1,S,G:-400:256,A:0,W:0.5,Q',
     [r'Map: E1M1: 1 deep water lines for 1 sectors', r'Water: View under water \(sector 141, control 140\)',
      r'Water: Colormap WATERMAP: tint', r'Water: View normal'],
     ['-file', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'testdata', 'water.wad'), '--fixed-step'],
     lambda config: check_deep_water(config)),
    # Per-sector skies (tools/make_skies_wad.py): the sky behind the start
    # room's west window is SKY3, the rest of the map keeps SKY1.
    ('sector-skies', 'E1M1', 'Y,G:-450:256,A:180,LOOK:30,W:0.3,S,G:-600:240,A:90,LOOK:60,W:0.3,S,Q',
     [r'Map: E1M1: sky transfer of line 829 covers only 1 of 19 sky sectors',
      r'Geometry: E1M1: 1 sky sectors show their own sky'],
     ['-file', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'testdata', 'skies.wad'), '--fixed-step'],
     None),
    # Random maps (DoomRandomMap): seed 42's first map, its exit switch
    # (where the log line says to stand), the second map's locked door
    # without and with the key (K), a save of the first loaded back; then
    # New Game -> RANDOM MAPS on both IWADs.
    ('random-maps', 'E1M1',
     'Y,W:0.5,S,SAVE:1,G:-576:-688,A:270,W:0.3,S,U,W:3,U,U,U,U,U,W:2,'
     'G:592:392,A:90,W:0.3,U,W:0.5,K,U,W:1.5,S,G:64:-624,A:270,W:0.3,U,W:1.5,F:0.8,W:0.3,S,'
     'SAVE:2,LOAD:1,W:0.5,Q',
     [r'Random: seed 42: E1M1 "Iron Refinery": 1472 x 1472, 24 rooms .* 11 doors, 0 stairs, 0 windows, 1 secrets, '
      r'no locked door, .*switch line 1 at -576 -688 facing 270',
      r'Random: seed 42: E1M2 "Black Refinery": .* 5 stairs, 4 windows, 1 secrets, '
      r'locked door 26 at 592 392 facing 90 with its key \(type 5\)',
      r'MapInfo: UMAPINFO: 8 maps', r'Message: R1: Iron Refinery', r'Map: E1M1: VANILLA nodes, \d+ subsector polygons, total area 2166784',
      r'Intermission: E1M1: exit script', r'Load: E1M2: map parsed', r'Message: R2: Black Refinery',
      r'Message: Blue key needed for this door', r'Message: A secret is revealed!', r'Save: Loading .*save1\.json'],
     ['-random', '42', '--fixed-step'], lambda config: check_random(config)),
    # Level statistics (L) above the status bar and the automap's title;
    # the first exit is a new best time, the second (a save loaded, then
    # slower) is not.
    ('level-stats', 'E1M1',
     'W:0.3,KEY:L,W:0.5,S,M,W:0.3,S,M,SAVE:1,W:1,E,W:3,S,U,U,U,U,U,W:2,LOAD:1,W:3,E,W:3,S,Q',
     [r'Stats: Overlay shown', r'Stats: freedoom1\.wad E1M1 skill 3: time 0:0\d, a new best',
      r'Stats: freedoom1\.wad E1M1 skill 3: time 0:0\d, best 0:0\d'],
     ['--fixed-step'], lambda config: check_stats(config)),
    ('gamma', 'E1M1',
     'Y,G:480:712,A:0,W:0.5,S,KEY:F11,KEY:F11,W:0.3,S,KEY:F11,KEY:F11,W:0.3,S,KEY:F11,W:0.3,SAVE:1,Q',
     [r'Settings: Gamma 2 \(exponent 0\.625\)', r'Settings: Gamma 4', r'Message: Gamma correction OFF'],
     ['--fixed-step'], lambda config: check_gamma(config, 0)),
    ('gamma-menu', 'E1M1',
     'W:0.5,KEY:ESCAPE,KEY:DOWN,KEY:ENTER,KEY:DOWN,KEY:DOWN,KEY:DOWN,KEY:DOWN,KEY:DOWN,KEY:RIGHT,KEY:RIGHT,W:0.3,KEY:ESCAPE,KEY:ESCAPE,W:0.3,Q',
     [r'Settings: Gamma 2 \(exponent 0\.625\)'], [], lambda config: check_gamma(config, 2)),
    ('captions', 'E1M1',
     'Y,CAPTIONS,G:480:712,A:0,U,W:0.3,S,A:90,P:3001:200,A:0,W:0.3,X,W:0.5,S,Q',
     [r'Settings: Captions on', r'Caption: Door opens, ahead \(DSDOROPN\)',
      r'Caption: Serpentipede sees you, left \(DSBGSIT1\)'],
     ['--fixed-step'], lambda config: check_captions(config)),
    ('captions-menu', 'E1M1',
     'W:0.5,KEY:ESCAPE,KEY:DOWN,KEY:ENTER,KEY:DOWN,KEY:DOWN,KEY:DOWN,KEY:ENTER,KEY:DOWN,KEY:DOWN,KEY:ENTER,W:0.3,S,KEY:ESCAPE,KEY:ESCAPE,KEY:ESCAPE,W:0.3,G:480:712,A:0,U,W:0.3,Q',
     [r'Settings: Captions on', r'Caption: Door opens, ahead'], [], lambda config: check_captions(config)),
    ('random-menu', 'MENUKEYS', 'W:1,Q', [r'Random: seed \d+: E1M1', r'Load: E1M1: map parsed', r'Message: R1: '],
     ['--menukeys', 'E,D,D,D,D,E,E'], None),
    ('random-menu-doom2', 'MENUKEYS', 'W:1,Q', [r'Random: seed \d+: MAP01', r'Load: MAP01: map parsed', r'Message: R1: '],
     ['-iwad', 'castle-data:/wads/freedoom2.wad', '--menukeys', 'E,D,E,E'], None),
    ('boom-elevators', 'E1M1',
     'Y,W:0.3,LINE:618:232,LINE:753:236,LINE:593:212,W:4,SAVE:1,LINE:593:212,W:0.2,SAVE:2,Q',
     [r'Line: line 618 special 232 tag 2: activated', r'Line: line 593 special 212 tag 1: activated'],
     [], lambda config: check_elevators(config)),
    ('translucency', 'E1M1', 'Y,G:-450:256,A:180,LOOK:30,W:0.3,S,Q',
     [r'Map: E1M1: 3 translucent lines'],
     ['-file', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'testdata', 'translucent.wad'), '--fixed-step'],
     None),
    ('translucent-things', 'E1M1', 'Y,A:0,P:3001:120,W:0.1,S,Q',
     [r'DeHackEd: translucent.deh: 2 values applied'],
     ['-deh', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'testdata', 'translucent.deh'), '--fixed-step'],
     None),
    ('transfers', 'E1M1', 'Y,G:-300:256,A:0,W:0.2,F:1,W:0.3,SAVE:1,D,G:900:-500,A:90,LOOK:45,W:0.3,S,Q',
     [r'Map: E1M1: sky transfer: line 1016 gives STARTAN3 \(mirrored\) to 19 of 19 sky sectors',
      r'Map: E1M1: 2 light transfer lines',
      r'Teleport: player through line 834 to line 679 at \(728, -384\), angle 270'],
     ['-file', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'testdata', 'transfer.wad'), '--fixed-step'],
     lambda config: check_floor_y(config, -380)),
    ('icon-of-sin', 'MAP30', 'Y,G:-2208:3000,A:90,W:12,S,D,W:4,Q',
     [r'BrainAwake:', r'BrainDeath: Level exit'], [], None),
]


def check_generalized(config):
    """tools/testdata/generalized.wad: Boom's generalized doors, lifts, floor,
    locked door, crusher and perpetual lift moved E1M1's sectors."""
    s = [None] + [save_json(config, n) for n in range(1, 7)]
    assert s[1]['sectorCeiling'][48] > -60, 'turbo door 48 not open: %s' % s[1]['sectorCeiling'][48]
    assert s[2]['sectorFloor'][98] < 0, 'lift 98 not down: %s' % s[2]['sectorFloor'][98]
    assert [s[3]['sectorFloor'][i] for i in (76, 126, 129)] == [136, 144, 136], \
        'switch floors %s' % [s[3]['sectorFloor'][i] for i in (76, 126, 129)]
    assert s[3]['sectorFloorTex'][129] == 'CEIL5_1', 'texture change %s' % s[3]['sectorFloorTex'][129]
    assert s[4]['sectorCeiling'][71] > -100, 'blue door 71 not open: %s' % s[4]['sectorCeiling'][71]
    assert s[5]['sectorCeiling'][77] > -128, 'W1 door 77 not opening'
    kinds = sorted((m['sector'], m['kind'], m['perpetual']) for m in s[6]['movers'] if m['sector'] in (103, 145))
    assert kinds == [(103, 4, True), (145, 1, True)], 'crusher / perpetual lift %s' % kinds


def check_carry(config):
    """tools/testdata/scroll.wad: sector 141's 253 floor carries the player north."""
    a, b = save_json(config, 1)['player'], save_json(config, 2)['player']
    assert b['y'] - a['y'] > 50 and abs(b['x'] - a['x']) < 1, \
        'player not carried north: (%s, %s) -> (%s, %s)' % (a['x'], a['y'], b['x'], b['y'])


def check_boom_extended(config):
    """tools/testdata/boomext.wad: Boom's sector bits (secret 128, damage 64)
    and numbered line types 142, 150, 156, 153 and 199 on E1M1."""
    a, b = save_json(config, 1), save_json(config, 2)
    assert a['sectorSpecial'][140] == 64, 'secret bit not cleared: %s' % a['sectorSpecial'][140]
    assert a['player']['health'] < 100, 'no damage from the Boom sector: %s' % a['player']['health']
    assert b['sectorFloor'][98] > 12, '142 did not raise sector 98: %s' % b['sectorFloor'][98]
    crushers = [m for m in b['movers'] if m['sector'] == 103]
    assert crushers and crushers[0]['silent'], '150: no silent crusher on 103: %s' % crushers
    assert all(b['sectorSpecial'][i] & 31 == 3 for i in (76, 126, 129)), '156: no strobe'
    assert b['sectorFloorTex'][77] != a['sectorFloorTex'][77], '153: floor texture unchanged'
    assert b['sectorCeiling'][145] <= a['sectorCeiling'][145], '199 raised a ceiling'


def check_friction(config):
    """tools/testdata/friction.wad: on the ice of sector 140 the player starts
    slowly (a normal floor reaches x = -49) and slides on after the walk;
    in the mud of sector 141 a second's walk covers far less than 160."""
    p = [None] + [save_json(config, n)['player'] for n in range(1, 5)]
    assert p[1]['x'] < -200, 'ice: no slow start, x %s' % p[1]['x']
    assert p[2]['x'] - p[1]['x'] > 30, 'ice: no slide, %s -> %s' % (p[1]['x'], p[2]['x'])
    walked = p[4]['y'] - p[3]['y']
    assert 20 < walked < 120, 'mud: walked %s' % walked


def check_monster_friction(config):
    """The imp spawned last (at 350) walks south through the mud."""
    a = [save_json(config, n)['actors'] for n in (1, 2)]
    i = len(a[0]) - 1
    assert a[0][i]['sprite'] == 'TROO', 'not the imp: %s' % a[0][i]['sprite']
    walked = a[0][i]['y'] - a[1][i]['y']
    assert 15 < walked < 35, 'mud walk: %s units' % walked


def check_pushers(config):
    """tools/testdata/friction.wad: the current of sector 144 carries the
    player west, the point pusher in sector 106 pushes them east."""
    p = [None] + [save_json(config, n)['player'] for n in range(1, 5)]
    assert p[2]['x'] < p[1]['x'] - 30, 'current: %s -> %s' % (p[1]['x'], p[2]['x'])
    assert p[4]['x'] > p[3]['x'] + 30, 'point pusher: %s -> %s' % (p[3]['x'], p[4]['x'])


def check_dynscrollers(config):
    """tools/testdata/dynscroll.wad: nothing moves before the lift does;
    with the lift down the accelerative wall keeps a speed, the floor has
    moved and carried the player; with the lift back up the speed is gone
    and the wall has moved further."""
    s = [None] + [save_json(config, n) for n in range(1, 4)]
    sc = [None] + [x['scrollers'] for x in s[1:]]
    assert all(v == 0 for row in sc[1] for v in row[:2] + row[3:]), 'moved early: %s' % sc[1]
    assert s[2]['sectorFloor'][98] < 0, 'lift not down: %s' % s[2]['sectorFloor'][98]
    accel = [i for i in range(3) if abs(sc[2][i][0]) + abs(sc[2][i][1]) > 100]
    assert len(accel) == 1, 'no accelerative speed: %s' % sc[2]
    a = accel[0]
    assert any(abs(sc[2][i][3]) + abs(sc[2][i][4]) > 100 for i in range(3) if i != a), 'floor still: %s' % sc[2]
    assert abs(s[2]['player']['y'] - s[1]['player']['y']) > 30, 'not carried: %s' % s[2]['player']
    assert s[3]['sectorFloor'][98] == 12, 'lift not back: %s' % s[3]['sectorFloor'][98]
    assert abs(sc[3][a][0]) + abs(sc[3][a][1]) < 1e-3, 'speed kept: %s' % sc[3][a]
    assert abs(sc[3][a][3]) > abs(sc[2][a][3]), 'wall stopped early: %s -> %s' % (sc[2][a], sc[3][a])


def check_deep_water(config):
    """The player stands on the pool's real floor (-96), not on the water
    surface drawn at 0."""
    p = save_json(config, 1)['player']
    assert p['z'] < -90, 'not in the water: z %s' % p['z']


def check_elevators(config):
    """Boom's elevators keep the gap between floor and ceiling (sector 103
    down to the next lower floor, tag 3 to the switch sector's floor 160);
    the 212 toggle puts the lift's floor (98) at its ceiling and back."""
    a, b = save_json(config, 1), save_json(config, 2)
    f, c = a['sectorFloor'], a['sectorCeiling']
    assert (f[103], c[103]) == (8, 136), 'elevator down: %s %s' % (f[103], c[103])
    assert (f[76], c[76]) == (160, 160), 'elevator to the front floor: %s %s' % (f[76], c[76])
    assert f[98] == c[98] == 128, 'toggle up: %s' % f[98]
    assert b['sectorFloor'][98] == 12, 'toggle down: %s' % b['sectorFloor'][98]


def check_random(config):
    """Random maps: the saves name the generated PWAD like any other, on
    its first map and, after the exit switch, its second."""
    s1, s2 = save_json(config, 1), save_json(config, 2)
    assert s1['wads'][-1] == 'random:/42', 'wads: %s' % s1['wads']
    assert s1['map'] == 'E1M1' and s2['map'] == 'E1M2', 'maps: %s %s' % (s1['map'], s2['map'])


def check_stats(config):
    """The overlay stays on and E1M1's best time is the first, faster
    exit's."""
    with open(os.path.join(config, 'castle-doom', 'settings.json')) as f:
        s = json.load(f)
    assert s['showStats'] is True, 'showStats: %s' % s['showStats']
    best = s['bestTimes'].get('freedoom1.wad E1M1 skill 3')
    assert best is not None and best <= 3, 'bestTimes: %s' % s['bestTimes']


def check_captions(config):
    with open(os.path.join(config, 'castle-doom', 'settings.json')) as f:
        s = json.load(f)
    assert s['captions'] is True, 'captions: %s' % s['captions']


def check_gamma(config, level):
    """The gamma level saved: five F11 presses go around to 0, two steps
    of the Options page's slider give 2."""
    with open(os.path.join(config, 'castle-doom', 'settings.json')) as f:
        s = json.load(f)
    assert s['gamma'] == level, 'gamma: %s' % s['gamma']


def check_floor_y(config, below):
    """The player ended south of y = below (a line teleport moved them there)."""
    p = save_json(config, 1)['player']
    assert p['y'] < below, 'player at (%s, %s), not teleported' % (p['x'], p['y'])


def check_floor(config, sector, height):
    with open(os.path.join(config, 'castle-doom', 'save1.json')) as f:
        save = json.load(f)
    assert abs(save['sectorFloor'][sector] - height) < 0.5, \
        'sector %d floor %s, expected %s' % (sector, save['sectorFloor'][sector], height)


def check_video(config, fov, ui_scale):
    with open(os.path.join(config, 'castle-doom', 'settings.json')) as f:
        settings = json.load(f)
    assert settings['fieldOfView'] == fov and settings['uiScale'] == ui_scale, \
        'saved video settings %s, %s' % (settings['fieldOfView'], settings['uiScale'])


def check_keys(config, action, keys):
    with open(os.path.join(config, 'castle-doom', 'settings.json')) as f:
        settings = json.load(f)
    assert settings['keys'][action] == keys, 'keys.%s is %s' % (action, settings['keys'][action])


def check_hotkeys(config):
    """Q gave the rocket launcher (4), R the plasma rifle after it (5), L
    turned the light diminishing off and F, unbound, left it off."""
    weapons = [save_json(config, n)['player']['weapon'] for n in (1, 2)]
    assert weapons == [4, 5], 'weapons %s' % weapons
    with open(os.path.join(config, 'castle-doom', 'settings.json')) as f:
        settings = json.load(f)
    assert settings['diminish'] is False, 'diminish %s' % settings['diminish']


def check_mouse(config):
    """Bullets 50 after the left click (use), 49 after the right (fire),
    then the fist (0) after the wheel; settings.json keeps the buttons."""
    bullets = [save_json(config, n)['player']['ammo'][0] for n in (1, 2)]
    assert bullets == [50, 49], 'bullets %s' % bullets
    weapon = save_json(config, 3)['player']['weapon']
    assert weapon == 0, 'weapon %s' % weapon
    with open(os.path.join(config, 'castle-doom', 'settings.json')) as f:
        settings = json.load(f)
    assert settings['mouse'].get('fire') == 'Right' and settings['mouse'].get('use') == 'Left', \
        'mouse %s' % settings['mouse']


def check_touch_walk(config):
    """The stick on the right walked the player east."""
    p = [save_json(config, n)['player'] for n in (1, 2)]
    assert p[1]['x'] - p[0]['x'] > 300, 'stick: %s -> %s' % (p[0]['x'], p[1]['x'])


def check_touch_settings(config):
    with open(os.path.join(config, 'castle-doom', 'settings.json')) as f:
        settings = json.load(f)
    assert settings['touchLeftHanded'] is True and settings['touchSize'] == 125, \
        'touch %s %s' % (settings['touchLeftHanded'], settings['touchSize'])


def check_touch_places(config):
    with open(os.path.join(config, 'castle-doom', 'settings.json')) as f:
        settings = json.load(f)
    fire = settings['touchButtons'].get('fire')
    assert fire and abs(fire[0] - 0.5) < 0.01 and abs(fire[1] - 0.5) < 0.01, 'fire %s' % fire
    assert settings['touchOpacity'] == 50, 'opacity %s' % settings['touchOpacity']


def check_pad(config, action, buttons):
    with open(os.path.join(config, 'castle-doom', 'settings.json')) as f:
        settings = json.load(f)
    assert settings['pad'][action] == buttons, 'pad.%s is %s' % (action, settings['pad'][action])


def check_touch(config):
    """The touch stick moved the player east (the start faces east), the
    look finger's drag of a tenth of the width turned 18 degrees right."""
    p = [None] + [save_json(config, n)['player'] for n in range(1, 4)]
    assert p[2]['x'] - p[1]['x'] > 300, 'stick: %s -> %s' % (p[1]['x'], p[2]['x'])
    turned = p[2]['angle'] - p[3]['angle']
    assert 15 < turned < 21, 'look: turned %s' % turned


def check_log_filtered(config):
    with open(os.path.join(config, 'castle-doom', 'castle-doom-filtered.log')) as f:
        log = f.read()
    for rx in [r'^Load: E1M1: map parsed', r'^Shot: ']:
        assert re.search(rx, log, re.M), 'missing in the filtered log: %s' % rx
    for rx in [r'^Graphics: ', r'^Music: ', r'^Things: ']:
        assert not re.search(rx, log, re.M), 'filtered category still logged: %s' % rx


# Tests whose screenshots move (monsters, scrollers, the inspector's
# FPS) and whose entries do not say --fixed-step themselves: run one tic
# a frame so the screenshots can be golden ones too.
# icon-of-sin stays out: what the brain spawns depends on random numbers
# that other code (sounds, music) also draws, so CI and a local run see
# different monsters.
FIXED_STEP = {'inspector', 'gamepad-bindings', 'umapinfo-episode', 'mapinfo-episode',
              'scrollers'}

GOLDEN_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'golden')
GOLDEN_SIZE = (320, 180)
GOLDEN_PIXEL = 40
GOLDEN_MAX_CHANGED = 0.015
# Screenshots that come out the same on every run: menus, still views,
# map loads, and the moving scenes of the tests run with --fixed-step
# (one tic a frame, a fixed random seed).
GOLDEN = [
    'debug-draw_1.png', 'debug-draw_2.png',
    'wiscript-vanilla_1.png', 'wiscript-vanilla_2.png', 'wiscript_1.png', 'wiscript_2.png',
    'inspector_1.png', 'gamepad-bindings_1.png', 'touch-controls_2.png', 'umapinfo-episode_1.png',
    'mapinfo-episode_1.png', 'scrollers_1.png',
    'menu_menu.png', 'title-pages_menutitle.png', 'read-this_menureadthis.png',
    'controls-page_menucontrols.png', 'controls-hotkeys_menucontrolshotkeys.png',
    'controls-touch_menucontrolstouch.png', 'touch-layout_1.png', 'touch-edit_menutouchedit.png',
    'touch-places_1.png', 'map-component_design.png',
    'palette_1.png', 'palette_2.png', 'palette_3.png', 'fuzz_1.png', 'fuzz_2.png',
    'glbsp-v2_1.png', 'glbsp-v5_1.png', 'boom-lumps_1.png', 'umapinfo_1.png',
    'click-prompt_1.png', 'door-crush_1.png', 'ingame-options_1.png', 'ingame-options_2.png',
    'ingame-save-load_1.png', 'ingame-save-load_2.png', 'typed-save-name_1.png',
    'pointer-lock-pause_1.png', 'texture-memory_1.png', 'video-menu_1.png',
    'video-settings_1.png', 'settings-1_1.png', 'phase2-download_1.png', 'arch-vile_1.png',
    'save-round-trip_1.png', 'save-round-trip_2.png', 'knockback_1.png', 'melee-turn_1.png',
    'donut_1.png', 'select-thing_1.png', 'key-bindings_1.png', 'translucency_1.png',
    'translucent-things_1.png', 'transfers_1.png', 'touch-controls_1.png',
    'controls-pad_menucontrolspad.png', 'deep-water_1.png', 'deep-water_2.png',
    'mapinfo_1.png', 'mapinfo_2.png', 'sector-skies_1.png', 'sector-skies_2.png',
    'random-maps_1.png', 'random-maps_2.png', 'random-maps_3.png', 'random-maps_4.png',
    'level-stats_1.png', 'level-stats_2.png', 'level-stats_3.png', 'level-stats_4.png',
    'gamma_1.png', 'gamma_2.png', 'gamma_3.png', 'captions_1.png', 'captions_2.png', 'captions-menu_1.png',
]


def golden_compare(out, update=False):
    """Compare OUT's golden screenshots with tools/golden (or write them).
    Returns a list of (name, problem) for the ones that differ."""
    try:
        from PIL import Image, ImageChops
    except ImportError:
        print('golden screenshots skipped (no Pillow)')
        return []
    problems = []
    for name in GOLDEN:
        shot = os.path.join(out, name)
        ref = os.path.join(GOLDEN_DIR, name)
        if not os.path.exists(shot):
            continue  # its test did not run
        small = Image.open(shot).convert('RGB').resize(GOLDEN_SIZE, Image.BILINEAR)
        if update:
            os.makedirs(GOLDEN_DIR, exist_ok=True)
            small.save(ref, optimize=True)
            continue
        if not os.path.exists(ref):
            problems.append((name, 'no reference in tools/golden'))
            continue
        diff = ImageChops.difference(small, Image.open(ref).convert('RGB'))
        r, g, b = diff.split()
        worst = ImageChops.lighter(ImageChops.lighter(r, g), b)
        hist = worst.histogram()
        changed = sum(hist[GOLDEN_PIXEL + 1:]) / float(GOLDEN_SIZE[0] * GOLDEN_SIZE[1])
        if changed > GOLDEN_MAX_CHANGED:
            worst.point(lambda v: 255 if v > GOLDEN_PIXEL else 0).save(
                os.path.join(out, 'golden-diff-' + name))
            problems.append((name, '%.1f%% of the pixels changed (golden-diff-%s)' % (100 * changed, name)))
    return problems


def run_game(exe, out, name, mapname, demo, extra, config):
    args = [exe, '--autotest', mapname, os.path.join(out, name)]
    if demo:
        args += ['--demo', demo]
    env = dict(os.environ, XDG_CONFIG_HOME=config)
    # 'ENV:NAME=value' items of a test's extra arguments set the environment.
    for item in extra:
        if item.startswith('ENV:'):
            key, _, value = item[4:].partition('=')
            env[key] = value
        else:
            args.append(item)
    start = time.time()
    try:
        p = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           env=env, timeout=TIMEOUT)
        log, code = p.stdout.decode('utf-8', 'replace'), p.returncode
    except subprocess.TimeoutExpired as e:
        log, code = (e.stdout or b'').decode('utf-8', 'replace') + '\nTIMEOUT\n', -1
    with open(os.path.join(out, name + '.log'), 'w') as f:
        f.write(log)
    return log, code, time.time() - start


def run_test(exe, out, test):
    name, mapname, demo, expected, extra, check = test
    config = os.path.join(out, 'config-' + name)
    shutil.rmtree(config, ignore_errors=True)
    os.makedirs(config)
    log, code, secs = run_game(exe, out, name, mapname, demo, extra, config)
    problems = []
    if code != 0:
        problems.append('exit code %d' % code)
    for line in log.splitlines():
        if re.search(r'Exception|Runtime error|Access violation', line):
            problems.append(line.strip())
            break
    for rx in expected:
        if not re.search(rx, log):
            problems.append('missing log line /%s/' % rx)
    if check and not problems:
        try:
            check(config)
        except Exception as e:  # assertion or missing save
            problems.append('check: %s' % e)
    return problems, secs


def crash_test(exe, out):
    """The CRASH demo command raises: the report (GameCrash) is logged with
    the last log lines and the game exits with code 1."""
    config = os.path.join(out, 'config-crash-report')
    shutil.rmtree(config, ignore_errors=True)
    os.makedirs(config)
    log, code, secs = run_game(exe, out, 'crash-report', 'E1M1', 'W:0.3,CRASH,W:1,Q', [], config)
    problems = []
    if code != 1:
        problems.append('exit code %d, expected 1' % code)
    for rx in [r'Warning: Crash: Castle DOOM [\d.]+ stopped on an error:',
               r'Exception: Test crash from the CRASH demo command', r'its last lines:\n  ',
               r'Crash: Report saved to .*crash-report\.txt']:
        if not re.search(rx, log):
            problems.append('missing log line /%s/' % rx)
    # The saved report reaches back to the map's load (the ring buffer
    # keeps 100 lines; CGE's own memory only 10).
    report = os.path.join(config, 'castle-doom', 'crash-report.txt')
    if not os.path.exists(report):
        problems.append('no %s' % report)
    else:
        with open(report) as f:
            text = f.read()
        if not re.search(r'\n  Load: E1M1: map parsed', text):
            problems.append('crash-report.txt does not reach the map load (%d lines)' % len(text.splitlines()))
    return problems, secs


def demo_test(exe, out):
    """Demos (DoomDemo): a run on E1M1 recorded at the real frame rate
    (walking, shooting, a weapon change, the door; the zombies shoot back
    with the world's own random numbers) plays back in sync under
    --fixed-step, and a copy with one shot taken out is caught."""
    problems = []
    start = time.time()
    demo = os.path.join(out, 'demo-record.cdemo')
    if os.path.exists(demo):
        os.remove(demo)
    config = os.path.join(out, 'config-demo')
    shutil.rmtree(config, ignore_errors=True)
    os.makedirs(config)
    log, code, _ = run_game(exe, out, 'demo-record', 'E1M1',
                            'W:0.5,F:1.5,T:30,X,W:0.5,X,W:0.5,G:480:712,A:0,U,W:2,F:2,X,W:1,C:2,X,W:2,Q',
                            ['--record', demo], config)
    if code != 0:
        problems.append('recording: exit code %d' % code)
    m = re.search(r'Demo: Recorded .*: tic (\d+), (.*)', log)
    if not m:
        problems.append('recording: no "Demo: Recorded" line')
        return problems, time.time() - start
    log, code, _ = run_game(exe, out, 'demo-playback', 'E1M1', 'W:14,Q',
                            ['--playdemo', demo, '--fixed-step'], config)
    if code != 0:
        problems.append('playback: exit code %d' % code)
    if not re.search(r'Demo: Finished .* at tic %s, in sync: %s' % (m.group(1), re.escape(m.group(2))), log):
        problems.append('playback: not "in sync" at tic %s (%s)' % (m.group(1), m.group(2)))
    with open(demo) as f:
        lines = f.read().split('\n')
    del lines[lines.index('F')]
    bad = os.path.join(out, 'demo-tampered.cdemo')
    with open(bad, 'w') as f:
        f.write('\n'.join(lines))
    log, code, _ = run_game(exe, out, 'demo-tampered', 'E1M1', 'W:14,Q', ['--playdemo', bad], config)
    if not re.search(r'Warning: Demo: Out of sync at tic \d+', log):
        problems.append('tampered: no "Out of sync" warning')
    # Two levels of random maps: E1M1's exit switch, the intermission
    # (played back by itself), some of E1M2.
    demo2 = os.path.join(out, 'demo-levels.cdemo')
    if os.path.exists(demo2):
        os.remove(demo2)
    log, code, _ = run_game(exe, out, 'demo-levels-record', 'E1M1',
                            'W:0.5,X,W:0.5,G:-576:-688,A:270,W:0.3,U,W:3,U,U,U,U,U,W:2,F:1,X,W:0.5,T:90,X,W:1.5,Q',
                            ['-random', '42', '--record', demo2], config)
    ends = re.findall(r'Demo: Recorded (E1M\d) of .*: tic (\d+), (.*)', log)
    if [e[0] for e in ends] != ['E1M1', 'E1M2']:
        problems.append('levels: recorded %s, expected E1M1 and E1M2' % [e[0] for e in ends])
    else:
        log, code, _ = run_game(exe, out, 'demo-levels-playback', 'E1M1', 'W:40,Q',
                                ['--playdemo', demo2, '--fixed-step'], config)
        for name, tic, summary in ends:
            if not re.search(r'Demo: Finished %s of .* at tic %s, in sync: %s' % (name, tic, re.escape(summary)), log):
                problems.append('levels: %s not in sync at tic %s' % (name, tic))
    return problems, time.time() - start


def settings_test(exe, out):
    """Volumes set in one run are loaded by the next."""
    config = os.path.join(out, 'config-settings')
    shutil.rmtree(config, ignore_errors=True)
    os.makedirs(config)
    start = time.time()
    run_game(exe, out, 'settings-1', 'E1M1', 'VOL:5:12,SOUNDMENU,W:0.3,S,Q', [], config)
    log, code, _ = run_game(exe, out, 'settings-2', 'E1M1', 'W:0.3,Q', [], config)
    problems = []
    if not re.search(r'Settings: Sound 5, music 12', log):
        problems.append('second run did not load the saved volumes')
    if code != 0:
        problems.append('exit code %d' % code)
    return problems, time.time() - start


def phase2_download_test(exe, out):
    """Freedoom Phase 2 fetched as freedoom2.zip (what the web build does)."""
    import functools, http.server, threading, zipfile
    serve = os.path.join(out, 'serve')
    os.makedirs(serve, exist_ok=True)
    wad = os.path.join(os.path.dirname(exe), 'data', 'wads', 'freedoom2.wad')
    with zipfile.ZipFile(os.path.join(serve, 'freedoom2.zip'), 'w', zipfile.ZIP_DEFLATED) as z:
        z.write(wad, 'freedoom2.wad')
    handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=serve)
    httpd = http.server.ThreadingHTTPServer(('127.0.0.1', 0), handler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    config = os.path.join(out, 'config-phase2')
    shutil.rmtree(config, ignore_errors=True)
    os.makedirs(config)
    try:
        log, code, secs = run_game(exe, out, 'phase2-download', 'MAP01', 'W:1,S,Q',
                                   ['--wad-base-url', 'http://127.0.0.1:%d/' % httpd.server_port], config)
    finally:
        httpd.shutdown()
    problems = []
    if code != 0:
        problems.append('exit code %d' % code)
    for rx in (r'WAD: Downloaded http://127\.0\.0\.1:\d+/freedoom2\.zip',
               r'Loaded freedoom2-zip:/freedoom2\.wad', r'Saved screenshot 1 at MAP01'):
        if not re.search(rx, log):
            problems.append('missing log line /%s/' % rx)
    return problems, secs


def glbsp_nodes_test(exe, out):
    """E1M1 with only glBSP GL nodes (V1, V2, V3, V5; tools/make_glnodes.py).
    Skipped when glbsp is not installed."""
    if not shutil.which('glbsp'):
        return [], 0, True
    wads = os.path.join(out, 'glnodes')
    subprocess.run([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'make_glnodes.py'),
                    wads], check=True, stdout=subprocess.DEVNULL)
    problems = []
    secs = 0
    for v in (1, 2, 3, 5):
        config = os.path.join(out, 'config-glbsp-v%d' % v)
        shutil.rmtree(config, ignore_errors=True)
        os.makedirs(config)
        log, code, s = run_game(exe, out, 'glbsp-v%d' % v, 'E1M1', 'W:0.3,S,Q',
                                ['-file', os.path.join(wads, 'e1m1_gl_v%d.wad' % v)], config)
        secs += s
        if code != 0:
            problems.append('V%d: exit code %d' % (v, code))
        # V1 GL vertices are whole map units, so its area is a little off.
        for rx in (r'glBSP GL nodes V%d, \d+ GL vertices' % v,
                   r'GL_V%d nodes, 717 subsector polygons, total area 6[67]\d{5}' % v,
                   r'Saved screenshot 1 at E1M1'):
            if not re.search(rx, log):
                problems.append('V%d: missing log line /%s/' % (v, rx))
    return problems, secs, False


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    exe, out = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
    only = [a for a in sys.argv[3:] if not a.startswith('--')]
    update_golden = '--update-golden' in sys.argv[3:]
    os.makedirs(out, exist_ok=True)
    results = []
    for test in TESTS:
        if only and test[0] not in only:
            continue
        if test[0] in FIXED_STEP and '--fixed-step' not in test[4]:
            test = test[:4] + (list(test[4]) + ['--fixed-step'],) + test[5:]
        problems, secs = run_test(exe, out, test)
        results.append((test[0], problems, secs))
        print('%-16s %s (%.0f s)%s' % (test[0], 'FAIL' if problems else 'ok', secs,
                                        ''.join('\n    ' + p for p in problems)), flush=True)
    if not only or 'phase2-download' in only:
        problems, secs = phase2_download_test(exe, out)
        results.append(('phase2-download', problems, secs))
        print('%-16s %s (%.0f s)%s' % ('phase2-download', 'FAIL' if problems else 'ok', secs,
                                        ''.join('\n    ' + p for p in problems)), flush=True)
    if not only or 'glbsp-nodes' in only:
        problems, secs, skipped = glbsp_nodes_test(exe, out)
        if skipped:
            print('%-16s skipped (glbsp not installed)' % 'glbsp-nodes', flush=True)
        else:
            results.append(('glbsp-nodes', problems, secs))
            print('%-16s %s (%.0f s)%s' % ('glbsp-nodes', 'FAIL' if problems else 'ok', secs,
                                            ''.join('\n    ' + p for p in problems)), flush=True)
    if not only or 'crash-report' in only:
        problems, secs = crash_test(exe, out)
        results.append(('crash-report', problems, secs))
        print('%-16s %s (%.0f s)%s' % ('crash-report', 'FAIL' if problems else 'ok', secs,
                                        ''.join('\n    ' + p for p in problems)), flush=True)
    if not only or 'demo' in only:
        problems, secs = demo_test(exe, out)
        results.append(('demo', problems, secs))
        print('%-16s %s (%.0f s)%s' % ('demo', 'FAIL' if problems else 'ok', secs,
                                        ''.join('\n    ' + p for p in problems)), flush=True)
    if not only or 'settings' in only:
        problems, secs = settings_test(exe, out)
        results.append(('settings', problems, secs))
        print('%-16s %s (%.0f s)%s' % ('settings', 'FAIL' if problems else 'ok', secs,
                                        ''.join('\n    ' + p for p in problems)), flush=True)
    golden = golden_compare(out, update_golden)
    if update_golden:
        print('golden screenshots written to %s' % GOLDEN_DIR)
    else:
        results.append(('golden', ['%s: %s' % g for g in golden], 0))
        print('%-16s %s%s' % ('golden', 'FAIL' if golden else 'ok',
                              ''.join('\n    %s: %s' % g for g in golden)), flush=True)
    failed = [r for r in results if r[1]]
    summary = os.environ.get('GITHUB_STEP_SUMMARY')
    if summary:
        with open(summary, 'a') as f:
            f.write('## Autotests: %d of %d passed\n\n| Test | Result |\n|---|---|\n' %
                    (len(results) - len(failed), len(results)))
            for name, problems, secs in results:
                f.write('| %s | %s |\n' % (name, '; '.join(problems) if problems else 'ok (%.0f s)' % secs))
    print('%d of %d autotests passed' % (len(results) - len(failed), len(results)))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
