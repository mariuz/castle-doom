#!/usr/bin/env python3
"""Write tools/testdata/boom.wad: a PWAD with Boom's ANIMATED and SWITCHES
lumps for the unit test (TestBoomLumps) and the boom-lumps autotest.

ANIMATED: NUKAGE1..NUKAGE3 (flats) at 4 tics a frame and BLODRIP1..BLODRIP4
(textures) at 16; with the lump, the vanilla table is not used, so E1M1's
other animations stop. SWITCHES: SW1BRN1 turns into STARTAN3 (E1M1's
line 753 switch shows it when used), SW1GRAY / SW2GRAY as usual, and a
commercial-only pair (episode 3) that a Doom 1 game leaves out.

Usage: make_boom_wad.py [OUTFILE]
"""
import os
import struct
import sys


def name9(s):
    return s.encode('ascii').ljust(9, b'\0')


def animated():
    out = b''
    for kind, first, last, speed in [(0, 'NUKAGE1', 'NUKAGE3', 4), (1, 'BLODRIP1', 'BLODRIP4', 16)]:
        out += struct.pack('<B', kind) + name9(last) + name9(first) + struct.pack('<i', speed)
    return out + b'\xff'


def switches():
    out = b''
    for off, on, episode in [('SW1BRN1', 'STARTAN3', 1), ('SW1GRAY', 'SW2GRAY', 1), ('SW1HOT', 'SW2HOT', 3)]:
        out += name9(off) + name9(on) + struct.pack('<h', episode)
    return out + name9('') + name9('') + struct.pack('<h', 0)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), 'testdata', 'boom.wad')
    lumps = [('ANIMATED', animated()), ('SWITCHES', switches())]
    data = b''
    directory = b''
    pos = 12
    for name, body in lumps:
        directory += struct.pack('<ii8s', pos, len(body), name.encode('ascii'))
        data += body
        pos += len(body)
    with open(out, 'wb') as f:
        f.write(b'PWAD' + struct.pack('<ii', len(lumps), pos) + data + directory)
    print('%s: %d lumps' % (out, len(lumps)))


if __name__ == '__main__':
    main()
