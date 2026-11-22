#!/usr/bin/env python3
"""Write tools/testdata/terrain.wad: a ZDoom TERRAIN lump over Freedoom's
E1M1, for the terrain autotest and the unit test TestTerrain.

- E1M1's corridor east of the start room (sector 141, floor 0) becomes
  a pool: floor -16 with the FWATER1 flat (the sides facing into it get
  lower textures, their middle or upper one, else BROWN1); TERRAIN makes FWATER1 "Water": liquid, footclip 10,
  2 damage of type Slime every 16 tics (a radiation suit protects),
  a step sound (world/drip) every 0.5 s walking, 0.3 s running, the
  "Water" splash
  (small: WaterSplashBase and world/drip; big: WaterSplashBase on the
  surface, WaterSplash chunks thrown up, world/watersplash).
- AQF054 (the start room's floor and nine other sectors) is "Slippery",
  friction 1.5 (ice), with left and right footsteps (world/stepl,
  world/stepr) every 0.4 s walking, 0.25 s running.
- SPSHA0..SPSHK0: blue drops (A..D, the chunks) and rings (E..K, the
  base), since Freedoom has none of ZDoom's splash sprites.
- SNDINFO names the splash and step sounds: world/watersplash DSSLOP,
  world/drip DSPLASMA, world/stepl DSPSTOP, world/stepr DSSWTCHN.
- The TERRAIN lump also has an ifheretic block (skipped), a floor line
  before its terrain, an optional floor and a default terrain (Solid,
  nothing special), which the unit test reads.

Usage: make_terrain_wad.py [IWAD] [OUTFILE]
"""
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from make_wiscript_wad import patch  # noqa: E402

ROOT = os.path.join(HERE, '..')
WATER_SECTOR = 141

TERRAIN = b"""// TERRAIN test lump (tools/make_terrain_wad.py)
floor FWATER1 Water

splash Water
{
    smallclass WaterSplashBase
    smallclip 12
    smallsound world/drip
    baseclass WaterSplashBase
    chunkclass WaterSplash
    chunkxvelshift 8
    chunkyvelshift 8
    chunkzvelshift 8
    chunkbasezvel 2
    sound world/watersplash
}

terrain Water
{
    splash Water
    footclip 10
    liquid
    damageamount 2
    damagetype Slime
    damagetimemask 15
    allowprotection
    stepsounds world/drip
    walkingsteptime 0.5
    runningsteptime 0.3
}

terrain Slippery
{
    friction 1.5
    leftstepsounds world/stepl
    rightstepsounds world/stepr
    stepvolume 0.6
    walkingsteptime 0.4
    runningsteptime 0.25
    stepdistance 32
}

terrain Solid
{
}

ifheretic
floor FLTWAWA1 Water
terrain Water { footclip 99 }
endif

floor AQF054 Slippery
floor optional NOSUCHFL Water
defaultterrain Solid
"""

SNDINFO = b"""world/watersplash DSSLOP
world/drip DSPLASMA
world/stepl DSPSTOP
world/stepr DSSWTCHN
"""

BLUE, LIGHT = 200, 196


def drop(x, y):
    return BLUE if (x - 3.5) ** 2 + (y - 5) ** 2 <= 10 or (abs(x - 3.5) < 1 and y < 3) else None


def ring(size):
    def pixels(x, y):
        d = ((x - size / 2 + 0.5) ** 2 + ((y - size / 4 + 0.5) * 2) ** 2) ** 0.5
        return LIGHT if size / 2 - 3 <= d <= size / 2 else None
    return pixels


def sprites():
    out = []
    for frame in 'ABCD':
        out.append(('SPSH%s0' % frame, patch(8, 10, drop, 4, 10)))
    for i, frame in enumerate('EFGHIJK'):
        size = 12 + 4 * i
        out.append(('SPSH%s0' % frame, patch(size, size // 2, ring(size), size // 2, size // 2 - 1)))
    return out


def main():
    iwad = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'data', 'wads', 'freedoom1.wad')
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, 'testdata', 'terrain.wad')
    with open(iwad, 'rb') as f:
        data = f.read()
    count, offset = struct.unpack('<ii', data[4:12])
    entries = [struct.unpack('<ii8s', data[offset + 16 * i:offset + 16 * i + 16]) for i in range(count)]
    names = [e[2].rstrip(b'\0').decode('ascii') for e in entries]
    start = names.index('E1M1')
    lumps = [('E1M1', b'')]
    raw = {}
    for i in range(start + 1, start + 11):
        pos, size, _ = entries[i]
        raw[names[i]] = bytearray(data[pos:pos + size])
    struct.pack_into('<h', raw['SECTORS'], 26 * WATER_SECTOR, -16)
    struct.pack_into('<8s', raw['SECTORS'], 26 * WATER_SECTOR + 4, b'FWATER1\0')
    sides = raw['SIDEDEFS']
    lines = raw['LINEDEFS']
    for k in range(len(lines) // 14):
        front, back = struct.unpack_from('<HH', lines, 14 * k + 10)
        if back == 0xFFFF:
            continue
        sec = [struct.unpack_from('<H', sides, 30 * s + 28)[0] for s in (front, back)]
        if (sec[0] == WATER_SECTOR) == (sec[1] == WATER_SECTOR):
            continue
        # The side of the other sector looks down into the pool.
        side = front if sec[1] == WATER_SECTOR else back
        upper, lower, middle = struct.unpack_from('<8s8s8s', sides, 30 * side + 4)
        if lower.rstrip(b'\0') in (b'', b'-'):
            tex = middle if middle.rstrip(b'\0') not in (b'', b'-') else upper
            if tex.rstrip(b'\0') in (b'', b'-'):
                tex = b'BROWN1\0\0'
            struct.pack_into('<8s', sides, 30 * side + 12, tex)
    for i in range(start + 1, start + 11):
        lumps.append((names[i], bytes(raw[names[i]])))
    lumps += [('TERRAIN', TERRAIN), ('SNDINFO', SNDINFO), ('SS_START', b'')] + sprites() + [('SS_END', b'')]
    blob = b''
    directory = b''
    pos = 12
    for name, body in lumps:
        directory += struct.pack('<ii8s', pos, len(body), name.encode('ascii'))
        blob += body
        pos += len(body)
    with open(out, 'wb') as f:
        f.write(b'PWAD' + struct.pack('<ii', len(lumps), pos) + blob + directory)
    print('%s: %d lumps' % (out, len(lumps)))


if __name__ == '__main__':
    main()
