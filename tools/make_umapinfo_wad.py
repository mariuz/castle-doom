#!/usr/bin/env python3
"""Write tools/testdata/umapinfo.wad: a PWAD with a UMAPINFO lump for the
unit test (TestUMapInfo) and the umapinfo autotest, played over Freedoom
Phase 1.

E1M1 is renamed "T1: Test Hangar", leads to E1M3, has a par time of 123 s,
E1M5's music and SKY2, shows a story text after its intermission, and
lowers sector 98 (tag 1, special 23) when its last imp dies. E1M3 ("Third
Test", no label) starts a fifth New Game episode named in text (it has no
patch), skips the intermission and ends the game with the bunny.

Usage: make_umapinfo_wad.py [OUTFILE]
"""
import os
import struct
import sys

UMAPINFO = r'''// Castle DOOM test UMAPINFO (tools/make_umapinfo_wad.py)
MAP E1M1
{
  levelname = "Test Hangar"
  label = "T1"
  author = "Castle DOOM tests"
  next = "E1M3"
  partime = 123
  music = "D_E1M5"
  skytexture = "SKY2"
  intertext = "You left the test hangar.",
              "On to the third map."
  interbackdrop = "FLOOR4_8"
  bossaction = DoomImp, 23, 1
}

/* The third map ends the game with the bunny. */
MAP E1M3
{
  levelname = "Third Test"
  label = clear
  episode = "M_NOPATCH", "Test Episode", "t"
  nointermission = true
  endgame = true
  endbunny = true
}
'''


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), 'testdata', 'umapinfo.wad')
    body = UMAPINFO.encode('ascii')
    directory = struct.pack('<ii8s', 12, len(body), b'UMAPINFO')
    with open(out, 'wb') as f:
        f.write(b'PWAD' + struct.pack('<ii', 1, 12 + len(body)) + body + directory)
    print('%s: UMAPINFO, %d bytes' % (out, len(body)))


if __name__ == '__main__':
    main()
