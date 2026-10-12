#!/usr/bin/env python3
"""Write tools/testdata/friction.wad: Freedoom's E1M1 with Boom friction
and pushers, for the friction autotest:

- the start room (sector 140) is ice: type 256 (friction bit), tag 9,
  line 169 (192 long) is a 223 friction line with tag 9;
- the corridor east of it (sector 141) is mud: type 256, tag 10, line
  829 (64 long) is a 223 line with tag 10;
- sector 144 (south of the map's middle) has a current: type 512 (push
  bit), tag 11, line 63 (128 long, pointing west) is a 225 line;
- sector 106 has a point pusher: type 512, tag 12, a 5001 push thing at
  (1000, -900) and line 83 (128 long) as its 226 line.

Usage: make_friction_wad.py [IWAD] [OUTFILE]
"""
import os
import struct
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')

LINES = {169: (223, 9), 829: (223, 10), 63: (225, 11), 83: (226, 12)}
SECTORS = {140: (256, 9), 141: (256, 10), 144: (512, 11), 106: (512, 12)}
NEW_THINGS = [(1000, -900, 0, 5001, 7)]


def main():
    iwad = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'data', 'wads', 'freedoom1.wad')
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), 'testdata', 'friction.wad')
    with open(iwad, 'rb') as f:
        data = f.read()
    count, offset = struct.unpack('<ii', data[4:12])
    entries = [struct.unpack('<ii8s', data[offset + 16 * i:offset + 16 * i + 16]) for i in range(count)]
    names = [e[2].rstrip(b'\0').decode('ascii') for e in entries]
    start = names.index('E1M1')
    lumps = [('E1M1', b'')]
    for i in range(start + 1, start + 11):
        pos, size, _ = entries[i]
        body = bytearray(data[pos:pos + size])
        if names[i] == 'LINEDEFS':
            for line, (special, tag) in LINES.items():
                struct.pack_into('<hh', body, 14 * line + 6, special, tag)
        elif names[i] == 'SECTORS':
            for sector, (special, tag) in SECTORS.items():
                struct.pack_into('<hh', body, 26 * sector + 22, special, tag)
        elif names[i] == 'THINGS':
            for thing in NEW_THINGS:
                body += struct.pack('<hhhhh', *thing)
        lumps.append((names[i], bytes(body)))
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
