#!/usr/bin/env python3
"""Write tools/testdata/generalized.wad: Freedoom's E1M1 with some of its
line specials replaced by Boom generalized types (code/doomgeneralized.pas),
for the generalized autotest:

- the door at x = 544 / 560 (lines 537, 539): DR door, turbo, open, wait
  a second, close, monsters too (0x3C9F);
- the lift (lines 593, 595, 596 WR, 594 SR): generalized WR / SR lifts down
  to the lowest neighbour floor, normal speed, 3 s wait (0x3449, 0x344B);
- the switch at (2064, -221) (line 753): S1 floor down to the lowest
  neighbour floor, fast, taking the switch sector's floor texture
  (trigger model; 0x6892);
- the blue door (lines 421, 423): locked DR door, blue card or skull
  (0x3A8F);
- the W1 doors with tag 5 (lines 528, 1002, 1006): generalized W1 doors,
  open and stay, normal speed (0x3C28).

Usage: make_generalized_wad.py [IWAD] [OUTFILE]
"""
import os
import struct
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')

CHANGES = {
    537: 0x3C9F, 539: 0x3C9F,
    593: 0x3449, 595: 0x3449, 596: 0x3449, 594: 0x344B,
    753: 0x6892,
    421: 0x3A8F, 423: 0x3A8F,
    528: 0x3C28, 1002: 0x3C28, 1006: 0x3C28,
}


def main():
    iwad = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'data', 'wads', 'freedoom1.wad')
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), 'testdata', 'generalized.wad')
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
            for line, special in CHANGES.items():
                struct.pack_into('<h', body, 14 * line + 6, special - 0x10000 if special >= 0x8000 else special)
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
    print('%s: %d lumps, %d lines changed' % (out, len(lumps), len(CHANGES)))


if __name__ == '__main__':
    main()
