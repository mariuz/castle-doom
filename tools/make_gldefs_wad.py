#!/usr/bin/env python3
"""Write tools/testdata/gldefs.wad: a GLDEFS lump (GZDoom / UZDoom light
definitions) for the gldefs autotest and the unit test TestGldefs:

- an #include of TESTLITE, which defines REDLAMP (a red point light,
  radius 256, 48 above the feet), IMPGLOW (a blue pulse light between
  160 and 320 every 2 seconds) and FLICK (a flicker light, unused);
- E1M1's floor lamps (COLU) carry REDLAMP instead of the built-in warm
  light, imps (TROO) IMPGLOW;
- brightmaps: flat AQF054 (the start room's floor, also beyond its west
  window) gets BMCHECK, a PNG checkerboard of 8-texel squares, and
  wall texture BASE2 BMSTRIPE, a Doom patch with bright rows 0-7,
  16-23...; COMPSTA1's brightmap names a missing lump (a warning);
- a glow block (not supported: logged).

Usage: make_gldefs_wad.py [OUTFILE]
"""
import os
import struct
import sys
import zlib

GLDEFS = b'''// Castle DOOM test lights
#include "TESTLITE"

object Column
{
    frame COLU { light REDLAMP }
}

object DoomImp
{
    frame TROO { light IMPGLOW }
}

brightmap texture COMPSTA1
{
    map BMCOMPST
}

brightmap flat AQF054
{
    map BMCHECK
}

brightmap texture BASE2
{
    map BMSTRIPE
    iwad
}

glow
{
    flats { NUKAGE1 }
}
'''

TESTLITE = b'''pointlight REDLAMP
{
    color 1.0 0.1 0.1
    size 256
    offset 0 48 0
}

pulselight IMPGLOW
{
    color 0.2 0.4 1.0
    size 160
    secondarysize 320
    interval 2.0
}

/* not bound to anything */
flickerlight FLICK { color 1 1 0 size 10 secondarysize 20 chance 0.5 }
'''


def png_checker():
    """A 64x64 RGB PNG: white and black squares of 8 texels."""
    rows = b''
    for y in range(64):
        rows += b'\0' + b''.join((b'\xff\xff\xff' if (x // 8 + y // 8) % 2 == 0 else b'\0\0\0')
                                 for x in range(64))

    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 64, 64, 8, 2, 0, 0, 0)) +
            chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b''))


def patch_stripes():
    """A 64x64 Doom patch: palette index 4 (white) on rows 0-7, 16-23...,
    nothing (transparent: no brightness) between."""
    w = h = 64
    cols = []
    for x in range(w):
        col = b''
        for top in range(0, h, 16):
            col += bytes([top, 8, 0]) + bytes([4] * 8) + b'\0'
        cols.append(col + b'\xff')
    header = struct.pack('<hhhh', w, h, 0, 0)
    offset = len(header) + 4 * w
    offsets = b''
    for c in cols:
        offsets += struct.pack('<I', offset)
        offset += len(c)
    return header + offsets + b''.join(cols)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), 'testdata', 'gldefs.wad')
    lumps = [('GLDEFS', GLDEFS), ('TESTLITE', TESTLITE), ('BMCHECK', png_checker()),
             ('BMSTRIPE', patch_stripes())]
    data = bytearray(b'PWAD' + struct.pack('<ii', 0, 0))
    ents = []
    for name, body in lumps:
        ents.append((len(data), len(body), name))
        data += body
    diroff = len(data)
    for (p, s, name) in ents:
        data += struct.pack('<ii8s', p, s, name.encode().ljust(8, b'\0'))
    data[4:12] = struct.pack('<ii', len(ents), diroff)
    with open(out, 'wb') as f:
        f.write(data)
    print('wrote', out, len(data))


if __name__ == '__main__':
    main()
