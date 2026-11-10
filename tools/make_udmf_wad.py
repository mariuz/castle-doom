#!/usr/bin/env python3
"""Write tools/testdata/udmf.wad and tools/testdata/udmf-doom.wad:
Freedoom's E1M1 as a UDMF map (TEXTMAP), the format of maps made for
UZDoom / GZDoom, for the udmf autotests and the unit test TestUdmf.

udmf.wad, namespace "zdoom", no nodes (the game builds them): E1M1's
Doom specials written as Hexen actions the way ZDoom's doom.xlat does
(1 -> Door_Raise(0, 16, 150) used and repeatable by players and
monsters, 62 -> Plat_DownWaitUpStay(tag, 32, 105) ...), its sector types
as ZDoom's (1 -> 65, 9 -> the secret bit 1024...), and a few actions
Doom has no number for, around the start room (sector 140) and the room
east of it (141, given id 9):

- line 829: Floor_RaiseByValue(9, 8, 40), used: sector 141's floor
  rises 40 (Doom has 24 and 32 only);
- line 1045: Light_ChangeToValue(9, 200), used: sector 141's light 200;
- line 898: Scroll_Texture_Left(32): half a texel a tic;
- line 1046: TranslucentLine(0, 128): itself half see-through;
- line 911: Teleport(5, 0), walked over: to the teleport destination
  with thing id 5 at (1000, -900) (no sector tag: found by its id);
- line 1052: ACS_Execute(1), used: there is no BEHAVIOR lump (logged).

udmf-acs.wad, as udmf.wad with ACS scripts: a BEHAVIOR lump (the test
program of tools/make_acs.py, in ACC's "ACS\0" + ACSe layout), the start
room (sector 140) given id 10 for its open script to raise, and line
1052 an ACS_Execute(2, 0, 7) (script 2 with x = 7: sector 141's light
200 and floor FLOOR7_2, "Seven").

udmf-slopes.wad, as udmf.wad with slopes: sector 141 (the corridor east
of the start room, x -256..-192, y 128..384) gets floorplane fields that
raise its floor from 0 at y 128 to 64 at y 384, and line 836 a
Plane_Align(0, 1) that slopes the ceiling of sector 99 (east of it) from
141's 128 at the line down to 99's own 92 at its far side; the walls
around them get lower and upper textures where they had none; the
triangular sector 165 (floor 16) slopes down to 0 at its corner
(-384, 64) by that vertex's zfloor; line 101 (Plane_Copy(9)) gives
sector 173 141's floor plane and a CopyCeilingPlane thing (9511) in
sector 130 gives it sector 99's (id 13) ceiling; a 9500 thing slopes
sector 29's floor from line 1049 (id 50) up to 32 at (-560, 240) and a
9502 the triangle 169's up eastward at 30 degrees.

udmf-things.wad, as udmf.wad with thing actions: a map spot (9001, id 20)
in the start room at (-320, 320); line 829 a Thing_Spawn(20, 5, 64, 21)
(an imp there), 1045 a Thing_Damage(21, 1000) (it dies), 1046 a
Thing_SpawnNoFog(20, 4, 0, 22) (a zombieman), 1052 a Thing_Remove(22),
all used; line 898 a Scroll_Floor(9, 64, 0, 2) (sector 141's floor
scrolls east and carries things); an open ACS script spawns a shotgun
guy at the spot (SpawnSpot, id 30) and a medikit at (-352, 192) (Spawn,
id 31), prints "Spawned 2", gives a shotgun and 20 shells and prints
"Shells 20"; sector 99 (id 12) gets a Pillar_Build(12, 16, 0) on line 830
(floor and ceiling meet at 46), Sector_SetFriction(12, 200) on line 831
and Sector_SetWind(12, 32, 64, 0) on line 833; line 900 is a
Thing_Move(31, 20) (the medikit to the map spot), line 1047 an
ACS_Execute of the named script "Greet" (arg0str) and line 1048 a
Plat_UpByValue(9, 16, 35, 4) (sector 141 up 32 and back after a
second); a second map spot (id 40) 32 above the floor at (-416, 320)
fires a rocket north from line 1050 (Thing_Projectile(40, 127, 64, 80))
and a falling imp ball from line 1051 (Thing_ProjectileGravity(40, 10,
64, 40, 48)); the imp 81 and the shells 110 have thing specials
(THING_SPECIALS) that light sectors 141 and 99 when it dies and they are
picked up.

udmf-3dfloor.wad, as udmf.wad with two 3D floors (Sector_Set3dFloor)
from control sectors added outside the map: a solid slab at 64..80, 160
opaque, over the start room (140, id 15), which the player stands under,
and a solid step at 0..24 filling the corridor east of it (141, id 9),
which the player walks onto.

udmf-acslib.wad, as udmf.wad with ACS libraries (tools/make_acs.py's
library programs): the map's BEHAVIOR LOADs TESTLIB, imports its map
variables libcount and libtext and its function LibAdd, and runs its
named script LibNamed; a LOADACS lump loads AUTOLIB, whose open script
runs on every map (E1M2 too, a Doom-format map of the IWAD). The
libraries sit between A_START and A_END like ZDoom's.

udmf-poly.wad, as udmf.wad with polyobject 1 (POLY_*): a 64 x 16 slab
drawn out in the void, placed in the start room by its start spot, and
three west-wall lines that move, turn and slide it; polyobject 2
mirrors it, line 1046 sends 1 to a map spot.

udmf-3dfloor2.wad, the same with stage 3's slabs (FLOOR3D_CONTROLS2):
water to swim in over the start room, a sloped slab that lights the
corridor under it.

udmf-doom.wad, namespace "doom": the same map with Doom's own specials
and ZDoom GL nodes (XGLN) in ZNODES.

udmf-3dfloor3.wad: green water in the start room drawn from inside
too, with udmf-things.wad's lines (see FLOOR3D_CONTROLS3).

udmf-look.wad, as udmf.wad plus UZDoom's look fields (rendering stage
1): the start room (sector 140) lit warm orange (lightcolor 0xFFA070)
with its floor turned 45 degrees and scaled 2x, the room east of it
(141) in blue fog (fadecolor 0x2040A0), the west wall's line 829
texture scaled 2x and line 1046's shifted 32 units and 64 brighter;
three light things (LOOK_LIGHTS) for the dynamic lights.

Usage: make_udmf_wad.py [OUTDIR]
"""
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import make_znodes as zn  # noqa: E402  (reads Freedoom's E1M1, computes its GL nodes)
import make_acs  # noqa: E402

# Doom special -> (Hexen action, args, activation flags); args with 'tag'
# take the line's tag. Activation: c cross, u use, m monsters, r repeat.
DOOM_TO_HEXEN = {
    1: (12, (0, 16, 150), 'umr'),
    117: (12, (0, 64, 150), 'ur'),
    26: (13, (0, 16, 150, 2), 'ur'),
    2: (11, ('tag', 16), 'c'),
    11: (243, (0,), 'u'),
    23: (21, ('tag', 8), 'u'),
    62: (62, ('tag', 32, 105), 'ur'),
    88: (62, ('tag', 32, 105), 'cmr'),
}
EXTRA_LINES = {
    829: (23, (9, 8, 40), 'u'),
    1045: (112, (9, 200), 'u'),
    898: (100, (32,), ''),
    1046: (208, (0, 128), ''),
    911: (70, (5, 0), 'c'),
    1052: (80, (1,), 'u'),
}
SECTOR_IDS = {141: 9}
ACS_SECTOR_IDS = {141: 9, 140: 10}
ACS_LINES = {1052: (80, (2, 0, 7), 'u')}
SLOPE_SECTORS = {141: {'floorplane_a': '0.0', 'floorplane_b': '-0.25', 'floorplane_c': '1.0',
                       'floorplane_d': '32.0'}}
SLOPE_LINES = {836: (181, (0, 1), ''), 101: (118, (9, 0, 0, 0), '')}
SLOPE_SECTOR_IDS = {141: 9, 99: 13}
# CopyCeilingPlane (9511) in sector 130 (the middle of the ring 173):
# sector 99's (id 13) ceiling.
SLOPE_THINGS = [(1670, 1080, 0, 9511, 0, (13,)),
                # SlopeFloorPointLine: sector 29 from line 1049 (id 50) up to
                # 32 above its floor at (-560, 240).
                (-560, 240, 0, 9500, 32, (50,)),
                # SetFloorSlope: the triangle 169 rising east at 30 degrees.
                (-373, 445, 0, 9502, 0, (30,))]
SLOPE_LINE_IDS = {1049: 50}
# Polyobject 1 (udmf-poly.wad): a 64 x 16 slab drawn in a container
# sector out in the void, anchored at its middle, placed in the start
# room at (-416, 384); the start room's west wall moves it north 32
# (line 829), turns it a quarter left (830) and slides it east 48 and
# back after a second (831).
# Polyobject 2, the same slab, mirrors every move of 1 (StartLine arg1)
# from (-416, 120); line 1046 sends 1 to the map spot 41 at (-480, 300)
# (Polyobj_MoveToSpot).
# Polyobject 1's sounds (StartLine arg2 = 1): SNDSEQ's door sequence 1,
# its logical names given lumps by SNDINFO.
POLY_SNDINFO = b'// polyobject sounds\npoly/start dsstnmov\npoly/stop dspstop\n'
POLY_SNDSEQ = b':PolyStone\n  door 1\n  playrepeat poly/start\n  stopsound poly/stop\nend\n'
POLY_CONTAINER = (-3000, -2000)
POLY_SHAPE = [(-2968, -1944), (-2904, -1944), (-2904, -1928), (-2968, -1928)]
POLY_SHAPE2 = [(-2968, -1904), (-2904, -1904), (-2904, -1888), (-2968, -1888)]
POLY_THINGS = [(-2936, -1936, 1, 9300, 7), (-416, 384, 1, 9301, 7), (-2936, -1896, 2, 9300, 7),
               (-416, 120, 2, 9301, 7), (-480, 300, 0, 9001, 7, 41)]
POLY_LINES = {829: (4, (1, 16, 64, 32), 'u'), 830: (2, (1, 32, 64), 'u'), 831: (8, (1, 16, 0, 48, 35), 'u'),
              1046: (86, (1, 32, 41), 'u')}
SLOPE_FILL = (99, 141)
FLOOR3D_IDS = {140: 15, 141: 9}
# Control sectors (x, y of the corner, floor, ceiling, Sector_Set3dFloor
# args): a 64-unit square each, far from the map.
FLOOR3D_CONTROLS = [(-3000, -3000, 64, 80, (15, 1, 0, 160)), (-2800, -3000, 0, 24, (9, 1, 0, 255))]
# udmf-3dfloor2.wad (3D floors, stage 3): swimmable water from 0 to 64 in
# the start room (140, type 2, alpha 128), and over the corridor east of
# it (141) a solid slab from 64 whose top slopes from 72 at y 128 to 96 at
# y 384 (the control's ceiling plane), in light 255: the corridor under it
# is lit 255.
FLOOR3D_CONTROLS2 = [(-3000, -3000, 0, 64, (15, 2, 0, 128), {'lightlevel': '96'}),
                     (-2800, -3000, 64, 72, (9, 1, 0, 255), {'lightlevel': '255', 'ceilingplane_a': '0.0',
                                                            'ceilingplane_b': '-0.09375', 'ceilingplane_c': '1.0',
                                                            'ceilingplane_d': '-60.0'})]
# udmf-3dfloor3.wad (3D floors, the rest): the start room's water (0..64)
# is green (the control sector's fadecolor) and drawn from inside too
# (type 2 + 4, render inside); udmf-things.wad's lines fire a falling
# imp ball (line 1051) from the map spot 40 inside it, which sinks slowly.
FLOOR3D_CONTROLS3 = [(-3000, -3000, 0, 64, (15, 6, 0, 128), {'lightlevel': '160', 'fadecolor': '0x30A040'})]
THING_LINES = {829: (135, (20, 5, 64, 21), 'u'), 1045: (119, (21, 1000), 'u'),
               1046: (137, (20, 4, 0, 22), 'u'), 1052: (132, (22,), 'u'), 898: (223, (9, 64, 0, 2), ''),
               830: (29, (12, 16, 0), 'u'), 831: (219, (12, 200), ''), 833: (218, (12, 32, 64, 0), ''),
               900: (125, (31, 20, 0), 'u'), 1047: (80, ('Greet',), 'u'), 1048: (65, (9, 16, 35, 4), 'u'),
               1050: (134, (40, 127, 64, 80, 0), 'u'), 1051: (136, (40, 10, 64, 40, 48), 'u')}
THING_SECTOR_IDS = {141: 9, 99: 12}
THING_SPOT = (-320, 320, 9001, 20)
# Thing specials (run when the thing dies or is picked up): E1M1's imp
# 81 at (848, 1056) sets sector 141's light to 64, the shells 110 at
# (416, 864) sector 99's to 220 (Light_ChangeToValue).
THING_SPECIALS = {81: (112, (9, 64)), 110: (112, (12, 220))}
# A second map spot, 32 above the floor, for the projectiles.
PROJECTILE_SPOT = (-416, 320, 9001, 40, 32)
# Vertex heights: the triangular sector 165 (floor 16) gets its corner
# (-384, 64) at 0.
SLOPE_VERTEX_Z = {(-384, 64): 0}
LOOK_SECTORS = {140: {'lightcolor': '0xFFA070', 'rotationfloor': '45.0', 'xscalefloor': '2.0',
                      'yscalefloor': '2.0'},
                141: {'fadecolor': '0x2040A0'}}
LOOK_FRONT_SIDES_OF_LINES = {829: {'scalex_mid': '2.0', 'scaley_mid': '2.0'},
                             1046: {'offsetx_mid': '32.0', 'light': '64'}}
TELEPORT_DEST = (1000, -900, 5)
# Light things (x, y, angle, type, height, args) in udmf-look.wad: a
# green point light (9800, radius 160) at the start room's east side,
# a magenta pulse (9801, 96..224 every 70 tics) in the room east of it,
# and a subtractive light (9820: counted, not drawn).
LOOK_LIGHTS = [(-300, 256, 0, 9800, 32, (0, 255, 64, 160)),
               (-150, 256, 70, 9801, 32, (255, 0, 255, 96, 224)),
               (-416, 400, 0, 9820, 0, (255, 255, 255, 64))]
ZDOOM_SECTOR = {1: 65, 2: 66, 3: 67, 4: 68, 5: 69, 7: 71, 8: 72, 9: 1024, 10: 74, 11: 75,
                12: 76, 13: 77, 14: 78, 16: 80, 17: 81}


def lump(name):
    return zn.lump(name)


def flag_names(flags):
    names = []
    for bit, name in ((1, 'blocking'), (2, 'blockmonsters'), (4, 'twosided'), (8, 'dontpegtop'),
                      (16, 'dontpegbottom'), (32, 'secret'), (64, 'blocksound'), (128, 'dontdraw'),
                      (256, 'mapped')):
        if flags & bit:
            names.append(name)
    return names


def textmap(hexen, look=False, acs=False, slopes=False, things=False, floors3d=False, polys=False):
    out = ['namespace = "%s";' % ('zdoom' if hexen else 'doom'), '']
    V = lump('VERTEXES')
    for k in range(len(V) // 4):
        x, y = struct.unpack('<hh', V[k * 4:k * 4 + 4])
        z = ('zfloor = %d.0;\n' % SLOPE_VERTEX_Z[(x, y)]) if slopes and (x, y) in SLOPE_VERTEX_Z else ''
        out.append('vertex // %d\n{\nx = %d.0;\ny = %d.0;\n%s}\n' % (k, x, y, z))
    L = lump('LINEDEFS')
    side_extra = {}
    if look:
        for k, extra in LOOK_FRONT_SIDES_OF_LINES.items():
            side_extra[struct.unpack('<H', L[k * 14 + 10:k * 14 + 12])[0]] = extra
    for k in range(len(L) // 14):
        v1, v2, fl, sp, tag, sf, sb = struct.unpack('<HHHhhHH', L[k * 14:k * 14 + 14])
        body = ['v1 = %d;' % v1, 'v2 = %d;' % v2, 'sidefront = %d;' % sf]
        if sb != 0xFFFF:
            body.append('sideback = %d;' % sb)
        body += ['%s = true;' % n for n in flag_names(fl)]
        if hexen and slopes and k in SLOPE_LINE_IDS:
            body.append('id = %d;' % SLOPE_LINE_IDS[k])
        if hexen:
            act = DOOM_TO_HEXEN.get(sp) if sp else None
            if k in EXTRA_LINES:
                act = EXTRA_LINES[k]
            if acs and k in ACS_LINES:
                act = ACS_LINES[k]
            if slopes and k in SLOPE_LINES:
                act = SLOPE_LINES[k]
            if things and k in THING_LINES:
                act = THING_LINES[k]
            if polys and k in POLY_LINES:
                act = POLY_LINES[k]
            if act:
                special, args, how = act
                body.append('special = %d;' % special)
                for i, a in enumerate(args):
                    v = tag if a == 'tag' else a
                    if isinstance(v, str):
                        body.append('arg%dstr = "%s";' % (i, v))
                    elif v:
                        body.append('arg%d = %d;' % (i, v))
                if 'c' in how:
                    body.append('playercross = true;')
                    if 'm' in how:
                        body.append('monstercross = true;')
                if 'u' in how:
                    body.append('playeruse = true;')
                    if 'm' in how:
                        body.append('monsteruse = true;')
                if 'r' in how:
                    body.append('repeatspecial = true;')
        else:
            if sp:
                body.append('special = %d;' % sp)
            if tag:
                body.append('id = %d;' % tag)
        out.append('linedef // %d\n{\n%s\n}\n' % (k, '\n'.join(body)))
    S = lump('SIDEDEFS')
    fill = set()
    if slopes:
        for k in range(len(L) // 14):
            v1, v2, fl, sp, tag, sf, sb = struct.unpack('<HHHhhHH', L[k * 14:k * 14 + 14])
            if sb == 0xFFFF:
                continue
            secs = {struct.unpack('<H', S[sd * 30 + 28:sd * 30 + 30])[0] for sd in (sf, sb)}
            if secs & set(SLOPE_FILL):
                fill |= {sf, sb}
    for k in range(len(S) // 30):
        xo, yo = struct.unpack('<hh', S[k * 30:k * 30 + 4])
        up, lo, mid = (S[k * 30 + o:k * 30 + o + 8].rstrip(b'\0').decode() for o in (4, 12, 20))
        sec, = struct.unpack('<H', S[k * 30 + 28:k * 30 + 30])
        body = ['sector = %d;' % sec]
        if xo:
            body.append('offsetx = %d;' % xo)
        if yo:
            body.append('offsety = %d;' % yo)
        if k in fill:
            up = up if up and up != '-' else 'STARTAN3'
            lo = lo if lo and lo != '-' else 'STARTAN3'
        for key, t in (('texturetop', up), ('texturebottom', lo), ('texturemiddle', mid)):
            if t and t != '-':
                body.append('%s = "%s";' % (key, t))
        body += ['%s = %s;' % kv for kv in side_extra.get(k, {}).items()]
        out.append('sidedef // %d\n{\n%s\n}\n' % (k, '\n'.join(body)))
    SE = lump('SECTORS')
    for k in range(len(SE) // 26):
        fh, ch = struct.unpack('<hh', SE[k * 26:k * 26 + 4])
        ft = SE[k * 26 + 4:k * 26 + 12].rstrip(b'\0').decode()
        ct = SE[k * 26 + 12:k * 26 + 20].rstrip(b'\0').decode()
        light, sp, tag = struct.unpack('<hhh', SE[k * 26 + 20:k * 26 + 26])
        body = ['heightfloor = %d;' % fh, 'heightceiling = %d;' % ch, 'texturefloor = "%s";' % ft,
                'textureceiling = "%s";' % ct, 'lightlevel = %d;' % light]
        if hexen:
            sp = ZDOOM_SECTOR.get(sp, 0)
            ids = SECTOR_IDS
            if acs:
                ids = ACS_SECTOR_IDS
            if things:
                ids = THING_SECTOR_IDS
            if slopes:
                ids = SLOPE_SECTOR_IDS
            if floors3d:
                ids = FLOOR3D_IDS
            tag = ids.get(k, tag)
        if sp:
            body.append('special = %d;' % sp)
        if tag:
            body.append('id = %d;' % tag)
        if look:
            body += ['%s = %s;' % kv for kv in LOOK_SECTORS.get(k, {}).items()]
        if slopes:
            body += ['%s = %s;' % kv for kv in SLOPE_SECTORS.get(k, {}).items()]
        out.append('sector // %d\n{\n%s\n}\n' % (k, '\n'.join(body)))
    things_on = things
    T = lump('THINGS')
    things = [struct.unpack('<hhhhh', T[k * 10:k * 10 + 10]) for k in range(len(T) // 10)]
    if hexen:
        things.append((TELEPORT_DEST[0], TELEPORT_DEST[1], 0, 14, 7, TELEPORT_DEST[2]))
    if polys:
        things += POLY_THINGS
    if things_on:
        things.append((THING_SPOT[0], THING_SPOT[1], 0, THING_SPOT[2], 7, THING_SPOT[3]))
        things.append((PROJECTILE_SPOT[0], PROJECTILE_SPOT[1], 0, PROJECTILE_SPOT[2], 7, PROJECTILE_SPOT[3],
                       PROJECTILE_SPOT[4]))
    extra = list(LOOK_LIGHTS) if look else []
    if slopes:
        extra += SLOPE_THINGS
    if extra:
        for (x, y, angle, typ, height, args) in extra:
            out.append('thing\n{\n%s\n}\n' % '\n'.join(
                ['x = %d.0;' % x, 'y = %d.0;' % y, 'angle = %d;' % angle, 'type = %d;' % typ,
                 'height = %d.0;' % height] + ['arg%d = %d;' % (i, a) for i, a in enumerate(args)] +
                ['skill%d = true;' % k for k in range(1, 6)] + ['single = true;']))
    for k, t in enumerate(things):
        x, y, angle, typ, fl = t[:5]
        body = ['x = %d.0;' % x, 'y = %d.0;' % y, 'angle = %d;' % angle, 'type = %d;' % typ]
        if things_on and k in THING_SPECIALS:
            special, args = THING_SPECIALS[k]
            body += ['special = %d;' % special] + ['arg%d = %d;' % (i, a) for i, a in enumerate(args)]
        if len(t) > 5:
            body.append('id = %d;' % t[5])
        if len(t) > 6:
            body.append('height = %d.0;' % t[6])
        if fl & 1:
            body += ['skill1 = true;', 'skill2 = true;']
        if fl & 2:
            body.append('skill3 = true;')
        if fl & 4:
            body += ['skill4 = true;', 'skill5 = true;']
        if fl & 8:
            body.append('ambush = true;')
        if not fl & 16:
            body.append('single = true;')
        body += ['coop = true;', 'dm = true;']
        out.append('thing\n{\n%s\n}\n' % '\n'.join(body))
    if floors3d:
        controls = FLOOR3D_CONTROLS if floors3d is True else floors3d
        nv, nl, ns, nsec = len(V) // 4, len(L) // 14, len(S) // 30, len(SE) // 26
        for control in controls:
            (x, y, fh, ch, args) = control[:5]
            fields = control[5] if len(control) > 5 else {}
            corners = [(x, y), (x, y + 64), (x + 64, y + 64), (x + 64, y)]
            for (cx, cy) in corners:
                out.append('vertex\n{\nx = %d.0;\ny = %d.0;\n}\n' % (cx, cy))
            for k in range(4):
                body = ['v1 = %d;' % (nv + k), 'v2 = %d;' % (nv + (k + 1) % 4), 'sidefront = %d;' % (ns + k),
                        'blocking = true;']
                if k == 0:
                    body.append('special = 160;')
                    body += ['arg%d = %d;' % (i, a) for i, a in enumerate(args) if a]
                out.append('linedef\n{\n%s\n}\n' % '\n'.join(body))
                out.append('sidedef\n{\nsector = %d;\ntexturemiddle = "STARTAN3";\n}\n' % nsec)
            body = ['heightfloor = %d;' % fh, 'heightceiling = %d;' % ch, 'texturefloor = "FLOOR7_2";',
                    'textureceiling = "FLOOR7_2";', 'lightlevel = %s;' % fields.get('lightlevel', '160')]
            body += ['%s = %s;' % kv for kv in fields.items() if kv[0] != 'lightlevel']
            out.append('sector\n{\n%s\n}\n' % '\n'.join(body))
            nv += 4
            nl += 4
            ns += 4
            nsec += 1
    if polys:
        nv, ns, nsec = len(V) // 4, len(S) // 30, len(SE) // 26
        if floors3d:
            nv += 4 * len(FLOOR3D_CONTROLS if floors3d is True else floors3d)
            ns += 4 * len(FLOOR3D_CONTROLS if floors3d is True else floors3d)
            nsec += len(FLOOR3D_CONTROLS if floors3d is True else floors3d)
        # The container: a 128-unit square facing in (clockwise), then the
        # polyobject inside it facing out (counter-clockwise), its first
        # line Polyobj_StartLine(1).
        x, y = POLY_CONTAINER
        loops = [([(x, y), (x, y + 128), (x + 128, y + 128), (x + 128, y)], 'STARTAN3', None),
                 (POLY_SHAPE, 'DOOR3', (1, 1, 2, 1)), (POLY_SHAPE2, 'DOOR3', (1, 2))]
        for corners, tex, start in loops:
            for (cx, cy) in corners:
                out.append('vertex\n{\nx = %d.0;\ny = %d.0;\n}\n' % (cx, cy))
            n = len(corners)
            for k in range(n):
                body = ['v1 = %d;' % (nv + k), 'v2 = %d;' % (nv + (k + 1) % n), 'sidefront = %d;' % (ns + k),
                        'blocking = true;']
                if start and k == 0:
                    body += ['special = %d;' % start[0]] + ['arg%d = %d;' % (i, a) for i, a in enumerate(start[1:])]
                out.append('linedef\n{\n%s\n}\n' % '\n'.join(body))
                out.append('sidedef\n{\nsector = %d;\ntexturemiddle = "%s";\n}\n' % (nsec, tex))
            nv += n
            ns += n
        out.append('sector\n{\nheightfloor = 0;\nheightceiling = 128;\ntexturefloor = "FLOOR7_2";\n'
                   'textureceiling = "FLOOR7_2";\nlightlevel = 160;\n}\n')
    return '\n'.join(out).encode('ascii')


def write_wad(path, lumps):
    out = bytearray(b'PWAD' + struct.pack('<ii', 0, 0))
    ents = []
    for name, data in lumps:
        ents.append((len(out), len(data), name))
        out += data
    diroff = len(out)
    for (p, s, name) in ents:
        out += struct.pack('<ii8s', p, s, name.encode().ljust(8, b'\0'))
    out[4:12] = struct.pack('<ii', len(ents), diroff)
    with open(path, 'wb') as f:
        f.write(out)
    print('wrote', path, len(out))


def main():
    outdir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, 'testdata')
    os.makedirs(outdir, exist_ok=True)
    write_wad(os.path.join(outdir, 'udmf.wad'),
              [('E1M1', b''), ('TEXTMAP', textmap(True)), ('ENDMAP', b'')])
    write_wad(os.path.join(outdir, 'udmf-look.wad'),
              [('E1M1', b''), ('TEXTMAP', textmap(True, True)), ('ENDMAP', b'')])
    write_wad(os.path.join(outdir, 'udmf-acs.wad'),
              [('E1M1', b''), ('TEXTMAP', textmap(True, acs=True)), ('BEHAVIOR', make_acs.behavior('compat')),
               ('ENDMAP', b'')])
    write_wad(os.path.join(outdir, 'udmf-slopes.wad'),
              [('E1M1', b''), ('TEXTMAP', textmap(True, slopes=True)), ('ENDMAP', b'')])
    write_wad(os.path.join(outdir, 'udmf-things.wad'),
              [('E1M1', b''), ('TEXTMAP', textmap(True, things=True)),
               ('BEHAVIOR', make_acs.behavior('compat', make_acs.spawn_program('compat'))), ('ENDMAP', b'')])
    write_wad(os.path.join(outdir, 'udmf-3dfloor.wad'),
              [('E1M1', b''), ('TEXTMAP', textmap(True, floors3d=True)), ('ENDMAP', b'')])
    write_wad(os.path.join(outdir, 'udmf-3dfloor2.wad'),
              [('E1M1', b''), ('TEXTMAP', textmap(True, floors3d=FLOOR3D_CONTROLS2)), ('ENDMAP', b'')])
    write_wad(os.path.join(outdir, 'udmf-3dfloor3.wad'),
              [('E1M1', b''), ('TEXTMAP', textmap(True, things=True, floors3d=FLOOR3D_CONTROLS3)), ('ENDMAP', b'')])
    write_wad(os.path.join(outdir, 'udmf-acslib.wad'),
              [('E1M1', b''), ('TEXTMAP', textmap(True)),
               ('BEHAVIOR', make_acs.behavior('compat', make_acs.libmap_program('compat'))), ('ENDMAP', b''),
               ('A_START', b''), ('TESTLIB', make_acs.behavior('e', make_acs.library_program('e'))),
               ('AUTOLIB', make_acs.behavior('E', make_acs.autolib_program('E'))), ('A_END', b''),
               ('LOADACS', b'// libraries for every map\nAUTOLIB\n')])
    write_wad(os.path.join(outdir, 'udmf-poly.wad'),
              [('E1M1', b''), ('TEXTMAP', textmap(True, polys=True)), ('ENDMAP', b''),
               ('SNDINFO', POLY_SNDINFO), ('SNDSEQ', POLY_SNDSEQ)])
    write_wad(os.path.join(outdir, 'udmf-doom.wad'),
              [('E1M1', b''), ('TEXTMAP', textmap(False)), ('ZNODES', b'XGLN' + zn.gl(False, False)),
               ('ENDMAP', b'')])


if __name__ == '__main__':
    main()
