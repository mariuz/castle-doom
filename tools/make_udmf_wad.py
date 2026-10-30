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
- line 1052: ACS_Execute(1), used: not supported (scripts), logged.

udmf-doom.wad, namespace "doom": the same map with Doom's own specials
and ZDoom GL nodes (XGLN) in ZNODES.

udmf-look.wad, as udmf.wad plus UZDoom's look fields (rendering stage
1): the start room (sector 140) lit warm orange (lightcolor 0xFFA070)
with its floor turned 45 degrees and scaled 2x, the room east of it
(141) in blue fog (fadecolor 0x2040A0), the west wall's line 829
texture scaled 2x and line 1046's shifted 32 units and 64 brighter.

Usage: make_udmf_wad.py [OUTDIR]
"""
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import make_znodes as zn  # noqa: E402  (reads Freedoom's E1M1, computes its GL nodes)

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
LOOK_SECTORS = {140: {'lightcolor': '0xFFA070', 'rotationfloor': '45.0', 'xscalefloor': '2.0',
                      'yscalefloor': '2.0'},
                141: {'fadecolor': '0x2040A0'}}
LOOK_FRONT_SIDES_OF_LINES = {829: {'scalex_mid': '2.0', 'scaley_mid': '2.0'},
                             1046: {'offsetx_mid': '32.0', 'light': '64'}}
TELEPORT_DEST = (1000, -900, 5)
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


def textmap(hexen, look=False):
    out = ['namespace = "%s";' % ('zdoom' if hexen else 'doom'), '']
    V = lump('VERTEXES')
    for k in range(len(V) // 4):
        x, y = struct.unpack('<hh', V[k * 4:k * 4 + 4])
        out.append('vertex // %d\n{\nx = %d.0;\ny = %d.0;\n}\n' % (k, x, y))
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
        if hexen:
            act = DOOM_TO_HEXEN.get(sp) if sp else None
            if k in EXTRA_LINES:
                act = EXTRA_LINES[k]
            if act:
                special, args, how = act
                body.append('special = %d;' % special)
                for i, a in enumerate(args):
                    v = tag if a == 'tag' else a
                    if v:
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
    for k in range(len(S) // 30):
        xo, yo = struct.unpack('<hh', S[k * 30:k * 30 + 4])
        up, lo, mid = (S[k * 30 + o:k * 30 + o + 8].rstrip(b'\0').decode() for o in (4, 12, 20))
        sec, = struct.unpack('<H', S[k * 30 + 28:k * 30 + 30])
        body = ['sector = %d;' % sec]
        if xo:
            body.append('offsetx = %d;' % xo)
        if yo:
            body.append('offsety = %d;' % yo)
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
            tag = SECTOR_IDS.get(k, tag)
        if sp:
            body.append('special = %d;' % sp)
        if tag:
            body.append('id = %d;' % tag)
        if look:
            body += ['%s = %s;' % kv for kv in LOOK_SECTORS.get(k, {}).items()]
        out.append('sector // %d\n{\n%s\n}\n' % (k, '\n'.join(body)))
    T = lump('THINGS')
    things = [struct.unpack('<hhhhh', T[k * 10:k * 10 + 10]) for k in range(len(T) // 10)]
    if hexen:
        things.append((TELEPORT_DEST[0], TELEPORT_DEST[1], 0, 14, 7, TELEPORT_DEST[2]))
    for t in things:
        x, y, angle, typ, fl = t[:5]
        body = ['x = %d.0;' % x, 'y = %d.0;' % y, 'angle = %d;' % angle, 'type = %d;' % typ]
        if len(t) > 5:
            body.append('id = %d;' % t[5])
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
    write_wad(os.path.join(outdir, 'udmf-doom.wad'),
              [('E1M1', b''), ('TEXTMAP', textmap(False)), ('ZNODES', b'XGLN' + zn.gl(False, False)),
               ('ENDMAP', b'')])


if __name__ == '__main__':
    main()
