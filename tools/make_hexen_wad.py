#!/usr/bin/env python3
"""Write tools/testdata/hexen.wad: Freedoom's E1M1 in Hexen's binary map
format (16-byte linedefs with an action and five arguments, 20-byte
things with ids, heights and actions, a BEHAVIOR lump), the format of
ZDoom maps from before UDMF, for the hexen autotests and the unit test
TestHexenFormat.

The maps are udmf-things.wad's and udmf-poly.wad's TEXTMAPs (see
make_udmf_wad.py) written as binary lumps:

- E1M1: E1M1's geometry with its own nodes, REJECT and BLOCKMAP; the
  Doom specials as Hexen actions, the map spots, thing actions (the imp
  81 lights sector 141 to 64 when it dies) and line actions of
  udmf-things.wad (line 829 spawns an imp at map spot 20, 1045 kills it,
  830 builds a pillar...), and its BEHAVIOR (the open script spawns a
  shotgun guy and a medikit: "Spawned 2"). Arguments are bytes here:
  1045's Thing_Damage of 1000 becomes 232, 1047's named script is gone.
  Line 1049 names itself 50 with Line_SetIdentification.
- E1M2: udmf-poly.wad's polyobjects (a slab drawn in the void, placed in
  the start room), with no nodes: the game builds them. SNDINFO and
  SNDSEQ give polyobject 1 its sounds.

Usage: make_hexen_wad.py [OUTDIR]
"""
import os
import re
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import make_udmf_wad as mu  # noqa: E402
import make_acs  # noqa: E402

LINE_FLAGS = {'blocking': 1, 'blockmonsters': 2, 'twosided': 4, 'dontpegtop': 8, 'dontpegbottom': 16,
              'secret': 32, 'blocksound': 64, 'dontdraw': 128, 'mapped': 256}
# The SPAC (bits 10..12) of a UDMF activation.
SPAC = [('playercross', 0), ('playeruse', 1), ('monstercross', 2), ('impact', 3), ('playerpush', 4),
        ('missilecross', 5)]
SET_ID_LINE = 1049


def parse(text):
    """UDMF blocks as (kind, {key: value}) in order; values as written."""
    blocks = []
    for m in re.finditer(r'(\w+)\s*(?://[^\n]*)?\s*\{([^}]*)\}', text):
        fields = {}
        for k, v in re.findall(r'(\w+)\s*=\s*([^;]*);', m.group(2)):
            fields[k.lower()] = v.strip()
        blocks.append((m.group(1).lower(), fields))
    return blocks


def num(f, key, default=0):
    v = f.get(key)
    if v is None:
        return default
    return int(float(v))


def true(f, key):
    return f.get(key) == 'true'


def tex(f, key):
    return f.get(key, '"-"').strip('"').encode().ljust(8, b'\0')[:8]


def hexen_lumps(text):
    verts, lines, sides, sectors, things = [], [], [], [], []
    for kind, f in parse(text.decode('ascii')):
        if kind == 'vertex':
            verts.append(struct.pack('<hh', num(f, 'x'), num(f, 'y')))
        elif kind == 'linedef':
            flags = sum(bit for key, bit in LINE_FLAGS.items() if true(f, key))
            for key, spac in SPAC:
                if true(f, key):
                    flags |= spac << 10
                    break
            if true(f, 'repeatspecial'):
                flags |= 0x200
            if true(f, 'monstercross') and true(f, 'playercross') or \
               true(f, 'monsteruse') and true(f, 'playeruse'):
                flags |= 0x2000
            special = num(f, 'special')
            args = [num(f, 'arg%d' % i) & 255 for i in range(5)]
            if len(lines) == SET_ID_LINE and special == 0:
                special, args = 121, [50, 0, 0, 0, 0]
            lines.append(struct.pack('<HHHB5BHH', num(f, 'v1'), num(f, 'v2'), flags, special, *args,
                                     num(f, 'sidefront', 0xFFFF), num(f, 'sideback', 0xFFFF)))
        elif kind == 'sidedef':
            sides.append(struct.pack('<hh8s8s8sH', num(f, 'offsetx'), num(f, 'offsety'), tex(f, 'texturetop'),
                                     tex(f, 'texturebottom'), tex(f, 'texturemiddle'), num(f, 'sector')))
        elif kind == 'sector':
            sectors.append(struct.pack('<hh8s8shHh', num(f, 'heightfloor'), num(f, 'heightceiling'),
                                       tex(f, 'texturefloor'), tex(f, 'textureceiling'), num(f, 'lightlevel', 160),
                                       num(f, 'special'), num(f, 'id')))
        elif kind == 'thing':
            flags = 0
            if true(f, 'skill1') or true(f, 'skill2'):
                flags |= 1
            if true(f, 'skill3'):
                flags |= 2
            if true(f, 'skill4') or true(f, 'skill5'):
                flags |= 4
            if true(f, 'ambush'):
                flags |= 8
            for key, bit in (('single', 256), ('coop', 512), ('dm', 1024)):
                if true(f, key):
                    flags |= bit
            args = [num(f, 'arg%d' % i) & 255 for i in range(5)]
            things.append(struct.pack('<hhhhhhHB5B', num(f, 'id'), num(f, 'x'), num(f, 'y'), num(f, 'height'),
                                      num(f, 'angle'), num(f, 'type'), flags, num(f, 'special'), *args))
    return {'THINGS': b''.join(things), 'LINEDEFS': b''.join(lines), 'SIDEDEFS': b''.join(sides),
            'VERTEXES': b''.join(verts), 'SECTORS': b''.join(sectors)}


def map_lumps(name, text, behavior, nodes):
    lumps = hexen_lumps(text)
    out = [(name, b'')]
    for lump_name in ('THINGS', 'LINEDEFS', 'SIDEDEFS', 'VERTEXES', 'SEGS', 'SSECTORS', 'NODES', 'SECTORS',
                      'REJECT', 'BLOCKMAP'):
        if lump_name in lumps:
            out.append((lump_name, lumps[lump_name]))
        elif nodes:
            out.append((lump_name, mu.lump(lump_name)))
        else:
            out.append((lump_name, b''))
    out.append(('BEHAVIOR', behavior))
    return out


def main():
    outdir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, 'testdata')
    os.makedirs(outdir, exist_ok=True)
    lumps = map_lumps('E1M1', mu.textmap(True, things=True),
                      make_acs.behavior('compat', make_acs.spawn_program('compat')), True)
    lumps += map_lumps('E1M2', mu.textmap(True, polys=True), b'', False)
    lumps += [('SNDINFO', mu.POLY_SNDINFO), ('SNDSEQ', mu.POLY_SNDSEQ)]
    mu.write_wad(os.path.join(outdir, 'hexen.wad'), lumps)


if __name__ == '__main__':
    main()
