#!/usr/bin/env python3
"""Write tools/testdata/skies.wad: Freedoom's E1M1 with a per-sector sky
(MBF's 271 on some of the sky sectors) for the sector-skies autotest and
unit test:

- sector 29, the sky area behind the start room's west window, gets tag
  14;
- line 829 (the start room's west wall, one-sided) becomes a 271 with
  tag 14 and SKY3 as its upper texture: sector 29 shows SKY3 while the
  other 18 sky sectors keep the map's SKY1 (the one sky cylinder).

It also writes skies-offset.wad beside it, the same with offsets on
line 829's front side (Boom's sky offsets): x 4096 turns SKY3 by a
sixteenth of a turn (a quarter of its width), y 60 puts its row 32 at
the horizon (texturemid y - 28, against 100 for the plain sky); and
line 1046 (one-sided, north of the window) a 271 giving the other 18
sky sectors SKY1 turned by an eighth of a turn, its row 32 at the
horizon too: the sky cylinder's offsets.

Usage: make_skies_wad.py [IWAD] [OUTFILE]
"""
import os
import struct
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')


def name8(s):
    return s.encode('ascii').ljust(8, b'\0')


def write(path, lumps):
    blob = b''
    directory = b''
    pos = 12
    for name, body in lumps:
        directory += struct.pack('<ii8s', pos, len(body), name.encode('ascii'))
        blob += body
        pos += len(body)
    with open(path, 'wb') as f:
        f.write(b'PWAD' + struct.pack('<ii', len(lumps), pos) + blob + directory)
    print('%s: %d lumps' % (path, len(lumps)))


def main():
    iwad = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'data', 'wads', 'freedoom1.wad')
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), 'testdata', 'skies.wad')
    with open(iwad, 'rb') as f:
        data = f.read()
    count, offset = struct.unpack('<ii', data[4:12])
    entries = [struct.unpack('<ii8s', data[offset + 16 * i:offset + 16 * i + 16]) for i in range(count)]
    names = [e[2].rstrip(b'\0').decode('ascii') for e in entries]
    start = names.index('E1M1')
    bodies = {}
    for i in range(start + 1, start + 11):
        pos, size, _ = entries[i]
        bodies[names[i]] = bytearray(data[pos:pos + size])
    lines, sides, sectors = bodies['LINEDEFS'], bodies['SIDEDEFS'], bodies['SECTORS']
    struct.pack_into('<h', sectors, 26 * 29 + 24, 14)
    struct.pack_into('<hh', lines, 14 * 829 + 6, 271, 14)
    side = struct.unpack_from('<h', lines, 14 * 829 + 10)[0]
    struct.pack_into('<8s', sides, 30 * side + 4, name8('SKY3'))
    lumps = [('E1M1', b'')] + [(names[i], bytes(bodies[names[i]])) for i in range(start + 1, start + 11)]
    write(out, lumps)
    struct.pack_into('<hh', sides, 30 * side, 4096, 60)
    # The other sky sectors (F_SKY1 ceilings) get tag 15 and line 1046 (the
    # west wall north of the window, one-sided) a 271 with SKY1 and
    # offsets 8192 (an eighth of a turn) and 60: the sky cylinder's sky.
    for k in range(len(sectors) // 26):
        if k != 29 and sectors[26 * k + 12:26 * k + 20].rstrip(b'\0') == b'F_SKY1':
            struct.pack_into('<h', sectors, 26 * k + 24, 15)
    struct.pack_into('<hh', lines, 14 * 1046 + 6, 271, 15)
    side2 = struct.unpack_from('<h', lines, 14 * 1046 + 10)[0]
    struct.pack_into('<8s', sides, 30 * side2 + 4, name8('SKY1'))
    struct.pack_into('<hh', sides, 30 * side2, 8192, 60)
    lumps = [('E1M1', b'')] + [(names[i], bytes(bodies[names[i]])) for i in range(start + 1, start + 11)]
    write(os.path.join(os.path.dirname(out), 'skies-offset.wad'), lumps)

if __name__ == '__main__':
    main()
