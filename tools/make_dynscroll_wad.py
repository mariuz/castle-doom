#!/usr/bin/env python3
"""Write tools/testdata/dynscroll.wad: Freedoom's E1M1 with Boom's
displacement and accelerative scrollers driven by the lift (sector 98,
the WR lift of tag 1), for the dynscrollers autotest:

- lines 596 and 595 (lift edges, the lift behind them) are flipped
  (vertices and sidedefs swapped) so the lift is their front sector, the
  control sector of these scrollers;
- line 596: 248 (displacement: floor scroll and carry) with tag 7 on
  sector 141, the corridor east of the start room: its floor moves, and
  carries what stands on it, only while the lift moves;
- line 595: 218 (accelerative wall scroller) with tag 8, so line 911
  (the start room's south wall, tag 8) speeds up while the lift goes
  down, keeps scrolling while it is down and stops when it is back up.

Usage: make_dynscroll_wad.py [IWAD] [OUTFILE]
"""
import os
import struct
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')

FLIP = [596, 595]
LINES = {596: (248, 7), 595: (218, 8), 911: (0, 8)}
SECTOR_TAGS = {141: 7}


def main():
    iwad = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'data', 'wads', 'freedoom1.wad')
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), 'testdata', 'dynscroll.wad')
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
    lines, sectors = bodies['LINEDEFS'], bodies['SECTORS']
    for line in FLIP:
        v1, v2, flags, special, tag, s0, s1 = struct.unpack_from('<hhhhhhh', lines, 14 * line)
        struct.pack_into('<hhhhhhh', lines, 14 * line, v2, v1, flags, special, tag, s1, s0)
    for line, (special, tag) in LINES.items():
        struct.pack_into('<hh', lines, 14 * line + 6, special, tag)
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
