#!/usr/bin/env python3
"""Write tools/testdata/intermission.wad: a PWAD whose ZDoom MAPINFO ends
the game after E1M1 with a scripted finale (an "intermission" block), for
the unit test (TestIntermission) and the intermission autotest, played
over Freedoom Phase 1.

E1M1's cluster exit text comes first, then "TestEnd": TITLEPIC with
M_NGAME drawn over it for 2 seconds (D_VICTOR), a text screen typed from
the INTRTEXT lump at (20, 40) on the tiled FLOOR4_8 flat (until a key),
CREDIT scrolling left to HELP1 (after 10 tics, over 70, for 100 tics), a
fade of TITLEPIC to black (35 tics) and a wipe, then its Link
"TestEnd2": CREDIT until a key. E1M2 ends with Doom's own
"Inter_Bunny".

Usage: make_intermission_wad.py [OUTFILE]
"""
import os
import struct
import sys

MAPINFO = r'''// Castle DOOM test MAPINFO (tools/make_intermission_wad.py)
map E1M1 "Intermission Hangar"
{
  next = EndSequence, "TestEnd"
  cluster = 1
}

map E1M2 "Bunny Plant"
{
  next = EndSequence, "Inter_Bunny"
  cluster = 2
}

cluster 1
{
  exittext = "The hangar is clear."
  flat = "FLOOR7_2"
}

cluster 2
{
}

intermission TestEnd
{
  Image
  {
    Background = "TITLEPIC"
    Draw = "M_NGAME", 96, 150
    Music = "D_VICTOR"
    Time = 2
  }
  TextScreen
  {
    Background = "FLOOR4_8", 1
    Text = "INTRTEXT"
    TextSpeed = 2
    Position = 20, 40
  }
  Scroller
  {
    Background = "CREDIT"
    Background2 = "HELP1"
    ScrollDirection = Left
    InitialDelay = -10
    ScrollTime = -70
    Time = -100
  }
  Fader
  {
    Background = "TITLEPIC"
    FadeType = FadeOut
    Time = -35
  }
  Wiper
  {
    WipeType = Melt
  }
  Link = TestEnd2
}

intermission TestEnd2
{
  Image
  {
    Background = "CREDIT"
  }
}
'''

INTRTEXT = '''THE SCRIPTED FINALE BEGINS.
THIS TEXT CAME FROM A LUMP.'''


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), 'testdata', 'intermission.wad')
    lumps = [('MAPINFO', MAPINFO.encode('ascii')), ('INTRTEXT', INTRTEXT.encode('ascii'))]
    data = b''
    directory = b''
    offset = 12
    for name, body in lumps:
        directory += struct.pack('<ii8s', offset, len(body), name.encode('ascii'))
        data += body
        offset += len(body)
    with open(out, 'wb') as f:
        f.write(b'PWAD' + struct.pack('<ii', len(lumps), offset) + data + directory)
    print('%s: %d lumps' % (out, len(lumps)))


if __name__ == '__main__':
    main()
