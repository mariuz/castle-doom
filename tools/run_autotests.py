#!/usr/bin/env python3
"""Run Castle DOOM's --autotest scripts and check what they log.

Usage (Linux, needs an X display; CI wraps it in xvfb-run):
    xvfb-run -a -s "-screen 0 1280x800x24" python3 tools/run_autotests.py ./castle-doom out

Every test runs the game with its own config directory (XDG_CONFIG_HOME), so
saves and settings never leak between tests or into the developer's own.
A test fails when the game exits with an error, logs an exception, misses an
expected log line, or a check on its saved game fails. Logs and screenshots
end up in the output directory (CI keeps them as an artifact).
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
     [r'Save: E1M1: restored \d+ actors', r'Gib: '], [], None),
    ('knockback', 'E1M1', 'K,SHOTS,C:5,W:1,A:180,W:0.3,X,W:1.5,S,Q',
     [r'Push: player by \d+ damage'], [], None),
    ('door-crush', 'E1M1', 'Y,G:480:712,A:0,U,W:1.5,CORPSE:3004:72,W:7,S,Q',
     [r'Crush: POSS .* crushed to gibs'], [], None),
    ('melee-turn', 'E1M1', 'Y,K,SHOTS,C:1,W:1,A:0,P:3001:55,T:12,W:0.1,X,W:0.3,S,Q',
     [r'Turn: from'], [], None),
    ('arch-vile', 'E1M1', 'Y,P:3001:250,D,W:2,P:64:200,W:4,S,Q',
     [r'Raise: Arch-vile raised TROO'], [], None),
    ('texture-memory', 'E1M1', 'W:0.5,N,W:2,S,Q',
     [r'Graphics: Freed [1-9]\d* textures'], [], None),
    ('donut', 'MAP05', 'Y,G:-64:408,A:-90,W:0.3,U,W:9,SAVE:2,S,Q',
     [r'Donut: pillar 54 and ring 53'], [], check_donut),
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
     [r'AutoTest: Inspector toggled', r'AutoTest: Saved screenshot 1'], [], None),
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
     [r'Spawn: SARG', r'Saved screenshot 2'], [], None),
    # A -deh patch: a 1 HP imp dies to one bullet, Freedoom's DEHACKED lump
    # is read too, the patch's par time (999 s) is what the intermission uses.
    ('dehacked', 'E1M1', 'Y,W:0.3,SAVE:1,SHOTS,P:3001:300,W:0.3,X,W:0.5,Q',
     [r'DeHackEd: DEHACKED lump: \d+ values applied', r'DeHackEd: test\.deh: 14 values applied',
      r'Shot: .* hit TROO \(-\d+ health left\)'],
     ['-deh', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'testdata', 'test.deh')],
     check_dehacked),
    # The thing under the crosshair selected in the inspector, and CGE's
    # profiler with the map load stages (--profile).
    ('select-thing', 'E1M1', 'Y,P:3001:300,W:0.5,SELECT,W:0.5,S,PROFILE,Q',
     [r'Select: TROO_\d+: TROO, state \w+, 60 health, action \w*, \d+ tics left, target player',
      r'- Load E1M1 \(DoomWorld\)', r'- Build geometry', r'- Spawn things'],
     ['--profile'], None),
    ('icon-of-sin', 'MAP30', 'Y,G:-2208:3000,A:90,W:12,S,D,W:4,Q',
     [r'BrainAwake:', r'BrainDeath: Level exit'], [], None),
]


def run_game(exe, out, name, mapname, demo, extra, config):
    args = [exe, '--autotest', mapname, os.path.join(out, name)]
    if demo:
        args += ['--demo', demo]
    args += extra
    env = dict(os.environ, XDG_CONFIG_HOME=config)
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
    only = sys.argv[3:]
    os.makedirs(out, exist_ok=True)
    results = []
    for test in TESTS:
        if only and test[0] not in only:
            continue
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
    if not only or 'settings' in only:
        problems, secs = settings_test(exe, out)
        results.append(('settings', problems, secs))
        print('%-16s %s (%.0f s)%s' % ('settings', 'FAIL' if problems else 'ok', secs,
                                        ''.join('\n    ' + p for p in problems)), flush=True)
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
