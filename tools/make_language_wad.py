#!/usr/bin/env python3
"""Write tools/testdata/language.wad: a PWAD with a ZDoom LANGUAGE lump
and a MAPINFO lump that looks its strings up, for the unit test
(TestLanguage) and the language autotest, played over Freedoom Phase 1.

LANGUAGE ([enu default] beats the later [default] and [fr] sections, and
the $ifgame(heretic) line is skipped) names E1M1 "E1M1: Language Hangar",
writes a two-line story, an episode name, MUSIC_LNG = "e1m5" and replaces
Freedoom's shotgun shells message (GOTSHELLS, a BEX string name).
MAPINFO: E1M1 is `lookup "LNG_E1M1"` with music "$MUSIC_LNG" (D_E1M5)
and leads to E1M2 ("$HUSTR_E1M2": its own vanilla title stays) in another
cluster, so cluster 1's looked-up exit text follows E1M1; a fifth episode
"$LNG_EPISODE" starts E1M1.

Usage: make_language_wad.py [OUTFILE]
"""
import os
import struct
import sys

LANGUAGE = r'''// Castle DOOM test LANGUAGE (tools/make_language_wad.py)
[enu default]
LNG_E1M1 = "E1M1: Language Hangar";
LNG_STORY = "The LANGUAGE lump wrote this,\n"
            "over two lines.";
LNG_EPISODE = "Language Episode";
MUSIC_LNG = "e1m5";
GOTSHELLS = "Picked up language shells.";
$ifgame(heretic) LNG_E1M1 = "Heretic only";
/* Other languages and the fallback lose to English. */
[fr]
LNG_E1M1 = "E1M1: Hangar des langues";
GOTSHELLS = "Des cartouches.";
[default]
LNG_E1M1 = "E1M1: default loses";
LNG_DEFAULT_ONLY = "From the default section";
'''

MAPINFO = r'''// Castle DOOM test MAPINFO with LANGUAGE lookups
map E1M1 lookup "LNG_E1M1"
{
  next = "E1M2"
  music = "$MUSIC_LNG"
  cluster = 1
}

map E1M2 "$HUSTR_E1M2"
{
  cluster = 2
}

cluster 1
{
  exittext = lookup, "LNG_STORY"
  flat = "FLOOR7_2"
}

cluster 2
{
}

episode E1M1
{
  name = "$LNG_EPISODE"
  key = "l"
}
'''


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), 'testdata', 'language.wad')
    lumps = [(b'LANGUAGE', LANGUAGE.encode('ascii')), (b'MAPINFO', MAPINFO.encode('ascii'))]
    data = b''
    directory = b''
    for name, body in lumps:
        directory += struct.pack('<ii8s', 12 + len(data), len(body), name)
        data += body
    with open(out, 'wb') as f:
        f.write(b'PWAD' + struct.pack('<ii', len(lumps), 12 + len(data)) + data + directory)
    print('%s: LANGUAGE and MAPINFO, %d bytes' % (out, len(data)))


if __name__ == '__main__':
    main()
