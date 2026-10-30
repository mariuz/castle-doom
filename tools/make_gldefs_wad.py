#!/usr/bin/env python3
"""Write tools/testdata/gldefs.wad: a GLDEFS lump (GZDoom / UZDoom light
definitions) for the gldefs autotest and the unit test TestGldefs:

- an #include of TESTLITE, which defines REDLAMP (a red point light,
  radius 256, 48 above the feet), IMPGLOW (a blue pulse light between
  160 and 320 every 2 seconds) and FLICK (a flicker light, unused);
- E1M1's floor lamps (COLU) carry REDLAMP instead of the built-in warm
  light, imps (TROO) IMPGLOW;
- a brightmap entry (parsed, not drawn yet) and a glow block (not
  supported: logged).

Usage: make_gldefs_wad.py [OUTFILE]
"""
import os
import struct
import sys

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


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), 'testdata', 'gldefs.wad')
    lumps = [('GLDEFS', GLDEFS), ('TESTLITE', TESTLITE)]
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
