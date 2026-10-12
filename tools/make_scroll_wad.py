#!/usr/bin/env python3
"""Write tools/testdata/scroll.wad: Freedoom's E1M1 with Boom scrollers
around the start room (sector 140), for the scrollers autotest and unit
test:

- line 829 (the start room's west wall, pointing north, 64 long): 253
  with tag 7 on sector 141, the room east of the start: its floor
  scrolls north 2 units a tic and carries what stands on it (the player
  drifts north at about 4 units a tic);
- line 1045 (west, pointing north): 250 with tag 7: sector 141's
  ceiling scrolls north too;
- line 898 (the north wall, pointing east, 48 long): 254 with tag 8, so
  line 911 (the south wall, tag 8, pointing west) scrolls its texture
  1.5 texels a tic (the texture offset grows: the texture moves left);
- line 1046 (west wall): 255 with its front sidedef's offsets set to
  (2, 0): its texture offset drops 2 texels a tic (it moves right).

Usage: make_scroll_wad.py [IWAD] [OUTFILE]
"""
import os
import struct
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')

LINES = {829: (253, 7), 1045: (250, 7), 898: (254, 8), 911: (0, 8), 1046: (255, 0)}
SECTOR_TAGS = {141: 7}
SIDE_OFFSETS_OF_LINE = {1046: (2, 0)}


def main():
    iwad = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'data', 'wads', 'freedoom1.wad')
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), 'testdata', 'scroll.wad')
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
    for line, (xoff, yoff) in SIDE_OFFSETS_OF_LINE.items():
        side = struct.unpack_from('<h', lines, 14 * line + 10)[0]
        struct.pack_into('<hh', sides, 30 * side, xoff, yoff)
    for sector, tag in SECTOR_TAGS.items():
        struct.pack_into('<h', sectors, 26 * sector + 24, tag)
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
