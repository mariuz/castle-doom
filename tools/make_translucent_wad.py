#!/usr/bin/env python3
"""Write tools/testdata/translucent.wad: Freedoom's E1M1 with Boom's
translucent middle textures (special 260), for the translucency autotest
and unit test:

- line 1052 (the grate in the start room's west window): 260 with no tag,
  so its own grate is drawn with the default map (Boom's 66%: no TRANMAP
  lump here);
- line 832 (a grate at the east end of the start corridor): 260 with tag
  13 and its middle texture set to TRANSL25, a 64 KB translucency map in
  this WAD that mixes a quarter of the foreground into the background:
  line 832 then draws no middle texture and line 837 (tag 13, the other
  grate there) is a quarter opaque.

Usage: make_translucent_wad.py [IWAD] [OUTFILE]   (needs numpy)
"""
import os
import struct
import sys

import numpy

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')

LINES = {1052: (260, 0), 832: (260, 13), 837: (0, 13)}
MIDDLE_OF_LINE = {832: 'TRANSL25'}
OPACITY = 0.25


def tranmap(palette):
    """Boom's map: for each foreground and background colour the palette
    colour nearest to their mix."""
    pal = numpy.array(palette, dtype=numpy.float64)
    mix = OPACITY * pal[:, None, :] + (1 - OPACITY) * pal[None, :, :]
    dist = ((mix[:, :, None, :] - pal[None, None, :, :]) ** 2).sum(axis=3)
    return dist.argmin(axis=2).astype(numpy.uint8).tobytes()


def main():
    iwad = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'data', 'wads', 'freedoom1.wad')
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), 'testdata', 'translucent.wad')
    with open(iwad, 'rb') as f:
        data = f.read()
    count, offset = struct.unpack('<ii', data[4:12])
    entries = [struct.unpack('<ii8s', data[offset + 16 * i:offset + 16 * i + 16]) for i in range(count)]
    names = [e[2].rstrip(b'\0').decode('ascii') for e in entries]
    pos, size, _ = entries[names.index('PLAYPAL')]
    palette = [tuple(data[pos + 3 * i:pos + 3 * i + 3]) for i in range(256)]
    start = names.index('E1M1')
    bodies = {}
    for i in range(start + 1, start + 11):
        pos, size, _ = entries[i]
        bodies[names[i]] = bytearray(data[pos:pos + size])
    lines, sides = bodies['LINEDEFS'], bodies['SIDEDEFS']
    for line, (special, tag) in LINES.items():
        struct.pack_into('<hh', lines, 14 * line + 6, special, tag)
    for line, texture in MIDDLE_OF_LINE.items():
        side = struct.unpack_from('<h', lines, 14 * line + 10)[0]
        sides[30 * side + 20:30 * side + 28] = texture.encode('ascii').ljust(8, b'\0')
    lumps = [('E1M1', b'')] + [(names[i], bytes(bodies[names[i]])) for i in range(start + 1, start + 11)]
    lumps.append(('TRANSL25', tranmap(palette)))
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
