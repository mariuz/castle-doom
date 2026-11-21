#!/usr/bin/env python3
"""Write tools/testdata/dogs.wad: what MBF's helper dogs (thing 888) need
over Freedoom's E1M1, for the dogs autotest.

- DOGSA0..DOGSN0: a brown dog drawn from boxes (Freedoom has no DOGS
  sprites): walking frames A..D move its legs, E..G bite, H is pain and
  I..N fall over.
- DSDGSIT, DSDGATK, DSDGACT, DSDGPAIN, DSDGDTH: short tones (DMX sounds).
- E1M1's THINGS plus a sleeping zombieman at (-300, 256) facing east,
  away from the player start, and a friendly dog (flag 128) in the
  corridor east of it at (-224, 300): the zombieman cannot see the
  player, so it goes for the dog (MBF's P_LookForTargets).

Usage: make_dogs_wad.py [IWAD] [OUTFILE]
"""
import math
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from make_wiscript_wad import patch  # noqa: E402

ROOT = os.path.join(HERE, '..')
BROWN, DARK, RED = 131, 140, 176


def dog(frame):
    i = 'ABCDEFGHIJKLMN'.index(frame)
    lying = i >= 8
    w, h = (40, 28) if not lying else (40, 28)
    sink = 0 if not lying else min(i - 7, 5) * 3

    def pixels(x, y):
        y2 = y - sink
        if lying and i >= 12 and y > 22:
            return RED if 4 <= x < 36 else None
        # body
        if 8 <= x < 32 and 8 <= y2 < 18:
            return BROWN
        # head (open mouth when biting)
        if 30 <= x < 39 and 3 <= y2 < 12:
            if 4 <= i <= 6 and y2 >= 9 and x >= 34:
                return RED
            return DARK
        # legs
        step = (i % 2) * 2 if i < 4 else 0
        for lx in (10 + step, 27 - step):
            if lx <= x < lx + 3 and 18 <= y2 < 28 and not lying:
                return DARK
        # tail
        if 3 <= x < 8 and 6 <= y2 < 9:
            return BROWN
        return None
    return patch(w, h, pixels, w // 2, h - 1)


def tone(freq, length=0.15, rate=11025):
    n = int(rate * length)
    data = bytes(int(128 + 60 * math.sin(2 * math.pi * freq * k / rate) * (1 - k / n)) for k in range(n))
    return struct.pack('<HHI', 3, rate, n + 32) + b'\x80' * 16 + data + b'\x80' * 16


def main():
    iwad = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'data', 'wads', 'freedoom1.wad')
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, 'testdata', 'dogs.wad')
    with open(iwad, 'rb') as f:
        data = f.read()
    count, offset = struct.unpack('<ii', data[4:12])
    entries = [struct.unpack('<ii8s', data[offset + 16 * i:offset + 16 * i + 16]) for i in range(count)]
    names = [e[2].rstrip(b'\0').decode('ascii') for e in entries]
    start = names.index('E1M1')
    lumps = [('E1M1', b'')]
    for i in range(start + 1, start + 11):
        pos, size, _ = entries[i]
        body = data[pos:pos + size]
        if names[i] == 'THINGS':
            body += struct.pack('<hhhhh', -300, 256, 0, 3004, 7)
            body += struct.pack('<hhhhh', -224, 300, 180, 888, 7 | 128)
        lumps.append((names[i], body))
    lumps += [('DSDGSIT', tone(300)), ('DSDGATK', tone(500, 0.1)), ('DSDGACT', tone(250)),
              ('DSDGPAIN', tone(700, 0.1)), ('DSDGDTH', tone(200, 0.4))]
    lumps += [('S_START', b'')] + [('DOGS%s0' % f, dog(f)) for f in 'ABCDEFGHIJKLMN'] + [('S_END', b'')]
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
