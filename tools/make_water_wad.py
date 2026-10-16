#!/usr/bin/env python3
"""Write tools/testdata/water.wad: Freedoom's E1M1 with Boom's deep water
(242) in the corridor east of the start room, for the deep-water autotest
and unit test:

- sector 141 (the corridor, floor 0, ceiling 128) gets tag 9, its real
  floor 96 units lower (-96) and the water flat FWATER1; its sides get
  the lower texture STARTAN3 for the pool's walls (the original map needs
  none: the floors were level);
- line 829 (the start room's west wall, front sector 140, floor 0,
  ceiling 128) becomes a 242 with tag 9: the start room is the control
  sector, so the corridor is drawn with its floor at 0 (the water
  surface) and, seen from below (the player's eye under 0), with its
  real floor in the start room's flat AQF054 and the surface's underside
  at -1 in its ceiling flat;
- its front side's lower texture names WATERMAP, a colormap lump added
  here (Freedoom has none): palette colours pulled 40% towards a
  blue-green, the screen tint under water.

Usage: make_water_wad.py [IWAD] [OUTFILE]
"""
import os
import struct
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')

TINT = (0.1, 0.35, 0.55)
AMOUNT = 0.4


def name8(s):
    return s.encode('ascii').ljust(8, b'\0')


def make_colormap(playpal):
    pal = [tuple(playpal[3 * i:3 * i + 3]) for i in range(256)]
    row = bytearray()
    for r, g, b in pal:
        want = [c * (1 - AMOUNT) + t * 255 * AMOUNT for c, t in zip((r, g, b), TINT)]
        best = min(range(256), key=lambda j: sum((pal[j][k] - want[k]) ** 2 for k in range(3)))
        row.append(best)
    return bytes(row) * 34


def main():
    iwad = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'data', 'wads', 'freedoom1.wad')
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), 'testdata', 'water.wad')
    with open(iwad, 'rb') as f:
        data = f.read()
    count, offset = struct.unpack('<ii', data[4:12])
    entries = [struct.unpack('<ii8s', data[offset + 16 * i:offset + 16 * i + 16]) for i in range(count)]
    names = [e[2].rstrip(b'\0').decode('ascii') for e in entries]
    pp = entries[names.index('PLAYPAL')]
    playpal = data[pp[0]:pp[0] + 768]
    start = names.index('E1M1')
    bodies = {}
    for i in range(start + 1, start + 11):
        pos, size, _ = entries[i]
        bodies[names[i]] = bytearray(data[pos:pos + size])
    lines, sides, sectors = bodies['LINEDEFS'], bodies['SIDEDEFS'], bodies['SECTORS']
    struct.pack_into('<h', sectors, 26 * 141, -96)
    struct.pack_into('<8s', sectors, 26 * 141 + 4, name8('FWATER1'))
    struct.pack_into('<h', sectors, 26 * 141 + 24, 9)
    for sd in range(len(sides) // 30):
        if struct.unpack_from('<h', sides, 30 * sd + 28)[0] == 141:
            struct.pack_into('<8s', sides, 30 * sd + 12, name8('STARTAN3'))
    struct.pack_into('<hh', lines, 14 * 829 + 6, 242, 9)
    side = struct.unpack_from('<h', lines, 14 * 829 + 10)[0]
    struct.pack_into('<8s', sides, 30 * side + 12, name8('WATERMAP'))
    lumps = [('E1M1', b'')] + [(names[i], bytes(bodies[names[i]])) for i in range(start + 1, start + 11)]
    lumps.append(('WATERMAP', make_colormap(playpal)))
    blob = b''
    directory = b''
    pos = 12
    for name, body in lumps:
        directory += struct.pack('<ii8s', pos, len(body), name.encode('ascii'))
        blob += body
        pos += len(body)
    with open(out, 'wb') as f:
        f.write(b'PWAD' + struct.pack('<ii', len(lumps), pos) + blob + directory)
    print('%s: %d lumps' % (out, len(lumps)))


if __name__ == '__main__':
    main()
