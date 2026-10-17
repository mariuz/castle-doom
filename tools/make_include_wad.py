#!/usr/bin/env python3
"""Write tools/testdata/include.wad: a PWAD whose MAPINFO only includes
another lump (MAPINF2), for the unit test (TestZMapInfo) and the
mapinfo-include autotest, played over Freedoom Phase 1.

MAPINF2 names E1M1 "Included Hangar", sends it to E1M2 and gives its
statistics an intermission script ("$IN_EXIT", the vanilla episode maps'
format) whose background is CREDIT; E1M2 is entered on IN_ENTER's
TITLEPIC. LOOPINF includes itself (the unit test checks that the
parser stops).

Usage: make_include_wad.py [OUTFILE]
"""
import os
import struct
import sys

LUMPS = [
    ('MAPINFO', '''// Castle DOOM test MAPINFO (tools/make_include_wad.py)
include "MAPINF2"
'''),
    ('MAPINF2', '''map E1M1 "Included Hangar"
{
  next = "E1M2"
  exitpic = "$IN_EXIT"
}

map E1M2 lookup "HUSTR_E1M2"
{
  enterpic = "$IN_ENTER"
}
'''),
    ('IN_EXIT', '''NOAUTOSTARTMAP
Background CREDIT
Splat WISPLAT
Pointer WIURH0 WIURH1
Spots
{
	E1M1 185 164
}
'''),
    ('IN_ENTER', '''Background TITLEPIC
'''),
    ('LOOPINF', '''include "LOOPINF"
map E1M5 "Loop"
'''),
]


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), 'testdata', 'include.wad')
    data = b''
    directory = b''
    for name, text in LUMPS:
        body = text.encode('ascii')
        directory += struct.pack('<ii8s', 12 + len(data), len(body), name.encode('ascii'))
        data += body
    with open(out, 'wb') as f:
        f.write(b'PWAD' + struct.pack('<ii', len(LUMPS), 12 + len(data)) + data + directory)
    print('%s: %d lumps, %d bytes' % (out, len(LUMPS), len(data)))


if __name__ == '__main__':
    main()
