#!/usr/bin/env python3
"""Write tools/testdata/mbf21.wad: Freedoom's E1M1 with a COMPLVL lump
saying mbf21 and line 834 (the start room's east edge, x -256) given
MBF21's binary-map bit 0x2000 (block players), for the mbf21-lines
autotest and the unit test TestMbf21.

Usage: make_mbf21_wad.py [OUTDIR]
"""
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import make_znodes as zn  # noqa: E402
import make_udmf_wad as mu  # noqa: E402

BLOCK_PLAYERS_LINE = 834


def main():
    outdir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, 'testdata')
    os.makedirs(outdir, exist_ok=True)
    lines = bytearray(zn.lump('LINEDEFS'))
    off = BLOCK_PLAYERS_LINE * 14 + 4
    flags, = struct.unpack_from('<H', lines, off)
    struct.pack_into('<H', lines, off, flags | 0x2000)
    lumps = [('E1M1', b'')]
    for name in ('THINGS', 'LINEDEFS', 'SIDEDEFS', 'VERTEXES', 'SEGS', 'SSECTORS', 'NODES', 'SECTORS', 'REJECT',
                 'BLOCKMAP'):
        lumps.append((name, bytes(lines) if name == 'LINEDEFS' else zn.lump(name)))
    lumps.append(('COMPLVL', b'mbf21\n'))
    mu.write_wad(os.path.join(outdir, 'mbf21.wad'), lumps)


if __name__ == '__main__':
    main()
