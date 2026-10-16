#!/usr/bin/env python3
"""Write tools/testdata/transfer.wad: Freedoom's E1M1 with Boom's last line
types, for the transfers autotest and unit test:

- line-to-line teleport: line 834 (the start room's east edge, pointing
  south) is a 243 with tag 14; line 679 (in sector 144, pointing east)
  has tag 14 too, so walking east through 834 at y = 256 comes out at
  (728, -385) facing south (the lines turned 90 degrees, plus 180);
- light transfers: lines 1014 (213, floor) and 1015 (261, ceiling) give
  the start room (sector 140, tag 15) the light of their front sector 133
  (100 instead of 192);
- sky transfer: every sky sector (tag 16) and line 1016, a 272 whose front
  side's upper texture is STARTAN3: the map's sky becomes that texture,
  mirrored (Freedoom Phase 1 has no other sky texture).

Usage: make_transfer_wad.py [IWAD] [OUTFILE]
"""
import os
import struct
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')

LINES = {834: (243, 14), 679: (0, 14), 1014: (213, 15), 1015: (261, 15), 1016: (272, 16)}
UPPER_OF_LINE = {1016: 'STARTAN3'}


def main():
    iwad = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'data', 'wads', 'freedoom1.wad')
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), 'testdata', 'transfer.wad')
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
    for line, (special, tag) in LINES.items():
        struct.pack_into('<hh', lines, 14 * line + 6, special, tag)
    for line, texture in UPPER_OF_LINE.items():
        side = struct.unpack_from('<h', lines, 14 * line + 10)[0]
        sides[30 * side + 4:30 * side + 12] = texture.encode('ascii').ljust(8, b'\0')
    struct.pack_into('<h', sectors, 26 * 140 + 24, 15)
    for sector in range(len(sectors) // 26):
        if sectors[26 * sector + 12:26 * sector + 20].rstrip(b'\0') == b'F_SKY1':
            struct.pack_into('<h', sectors, 26 * sector + 24, 16)
    lumps = [('E1M1', b'')] + [(names[i], bytes(bodies[names[i]])) for i in range(start + 1, start + 11)]
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
