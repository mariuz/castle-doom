#!/usr/bin/env python3
"""Write tools/testdata/wiscript.wad: visible intermission patches and a
ZDoom intermission script, for the unit test (TestWiScript) and the
wiscript autotests, played over Freedoom Phase 1 (whose WISPLAT, WIURH0,
WIURH1 and WIA* patches are blank 1x1 pictures: it has no episode maps).

- WISPLAT (a red cross), WIURH0 / WIURH1 (yellow arrows pointing right /
  left, offset so their tip is on the spot) and WIA00000..02 (E1's first
  animation: green, blue, white squares): Doom's built-in E1 script then
  shows them after E1M1 (the animation at 224,104; on "Entering" the
  splat on E1M1 at 185,164 and the pointer on E1M2 at 148,143).
- IN_TEST: a script MAPINFO gives E1M2's statistics and E1M3's entering
  screen: spots E1M1 40 40, E1M2 100 100, E1M3 10 100 (WIURH0, left of
  its spot, would leave the screen there, so WIURH1 is drawn), a looping animation of
  WIBOX0..2 at 160,150 and, only when leaving E1M2, WIBOX2 at 20,170
  (IfLeaving); IfEntering E1M9 shows nothing.

Usage: make_wiscript_wad.py [OUTFILE]
"""
import os
import struct
import sys


def patch(width, height, pixels, left=0, top=0):
    """A Doom patch; pixels(x, y) gives a palette index or None."""
    columns = []
    for x in range(width):
        col = b''
        y = 0
        while y < height:
            if pixels(x, y) is None:
                y += 1
                continue
            start = y
            run = []
            while y < height and pixels(x, y) is not None and len(run) < 128:
                run.append(pixels(x, y))
                y += 1
            col += bytes([start, len(run), 0]) + bytes(run) + b'\0'
        columns.append(col + b'\xff')
    header = struct.pack('<hhhh', width, height, left, top)
    offset = len(header) + 4 * width
    table = b''
    data = b''
    for col in columns:
        table += struct.pack('<i', offset + len(data))
        data += col
    return header + table + data


RED, YELLOW, GREEN, BLUE, WHITE = 176, 231, 112, 200, 4


def cross(x, y):
    return RED if abs(x - y) <= 1 or abs(x + y - 15) <= 1 else None


def arrow_right(x, y):
    # Tip at the right middle (the offset puts the tip on the spot).
    return YELLOW if abs(y - 8) <= ((23 - x) // 2) else None


def arrow_left(x, y):
    # Tip at the left middle.
    return YELLOW if abs(y - 8) <= (x // 2) else None


def square(colour):
    return lambda x, y: colour


SCRIPT = '''// Castle DOOM test intermission script (tools/make_wiscript_wad.py)
NoAutostartMap
Background WIMAP0
Splat WISPLAT
Pointer WIURH0 WIURH1
Spots
{
  E1M1 40 40
  E1M2 100 100
  E1M3 10 100
}
Animation 160 150 5
{
  WIBOX0
  WIBOX1
  WIBOX2
}
IfLeaving E1M2 Pic 20 170 WIBOX2
IfEntering E1M9 Pic 250 20 WIBOX0
'''

MAPINFO = '''map E1M2 lookup "HUSTR_E1M2"
{
  next = "E1M3"
  exitpic = "$IN_TEST"
}

map E1M3 lookup "HUSTR_E1M3"
{
  enterpic = "$IN_TEST"
}
'''


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), 'testdata', 'wiscript.wad')
    lumps = [
        (b'WISPLAT', patch(16, 16, cross, 8, 8)),
        (b'WIURH0', patch(24, 17, arrow_right, 24, 8)),
        (b'WIURH1', patch(24, 17, arrow_left, 0, 8)),
        (b'WIA00000', patch(12, 12, square(GREEN))),
        (b'WIA00001', patch(12, 12, square(BLUE))),
        (b'WIA00002', patch(12, 12, square(WHITE))),
        (b'WIBOX0', patch(20, 20, square(GREEN))),
        (b'WIBOX1', patch(20, 20, square(BLUE))),
        (b'WIBOX2', patch(20, 20, square(RED))),
        (b'IN_TEST', SCRIPT.encode('ascii')),
        (b'MAPINFO', MAPINFO.encode('ascii')),
    ]
    data = b''
    directory = b''
    for name, body in lumps:
        directory += struct.pack('<ii8s', 12 + len(data), len(body), name)
        data += body
    with open(out, 'wb') as f:
        f.write(b'PWAD' + struct.pack('<ii', len(lumps), 12 + len(data)) + data + directory)
    print('%s: %d lumps, %d bytes' % (out, len(lumps), len(data)))


if __name__ == '__main__':
    main()
