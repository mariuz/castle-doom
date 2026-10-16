#!/usr/bin/env python3
"""Write tools/testdata/mapinfo.wad: a PWAD with a ZDoom MAPINFO lump (the
new syntax with braces) for the unit test (TestZMapInfo) and the mapinfo
autotest, played over Freedoom Phase 1.

A defaultmap gives every map SKY3. E1M1 is "MapInfo Hangar" in cluster 1,
leads to E1M3, has a par time of 77 s, E1M5's music, TITLEPIC behind its
statistics (exitpic); leaving cluster 1 shows cluster 1's two-line exit
text on FLOOR7_2. E1M3 keeps its vanilla name (a LANGUAGE lookup), is in
cluster 2, shows CREDIT while "Entering" it (enterpic) and ends the game
with the bunny (next = EndGame3). The episodes are replaced by one,
"MapInfo Episode", starting E1M3.

Usage: make_mapinfo_wad.py [OUTFILE]
"""
import os
import struct
import sys

MAPINFO = r'''// Castle DOOM test MAPINFO (tools/make_mapinfo_wad.py)
gameinfo
{
  titlemusic = "D_INTRO"
}

defaultmap
{
  sky1 = "SKY3", 0
}

map E1M1 "MapInfo Hangar"
{
  levelnum = 1
  next = "E1M3"
  par = 77
  music = "D_E1M5"
  cluster = 1
  exitpic = "TITLEPIC"
}

map E1M3 lookup "HUSTR_E1M3"
{
  cluster = 2
  next = "EndGame3"
  enterpic = "CREDIT"
  nointermission
}

cluster 1
{
  exittext = "You left the MAPINFO hangar.",
             "Cluster one is behind you."
  flat = "FLOOR7_2"
  music = "D_VICTOR"
}

cluster 2
{
}

clearepisodes
episode E1M3
{
  name = "MapInfo Episode"
  key = "m"
}
'''


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), 'testdata', 'mapinfo.wad')
    body = MAPINFO.encode('ascii')
    directory = struct.pack('<ii8s', 12, len(body), b'MAPINFO')
    with open(out, 'wb') as f:
        f.write(b'PWAD' + struct.pack('<ii', 1, 12 + len(body)) + body + directory)
    print('%s: MAPINFO, %d bytes' % (out, len(body)))


if __name__ == '__main__':
    main()
