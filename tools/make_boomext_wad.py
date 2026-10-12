#!/usr/bin/env python3
"""Write tools/testdata/boomext.wad: Freedoom's E1M1 whose start sector
(140) has a Boom sector type: 192 = the secret bit (128) and damage 2
(10 every 32 tics, bits 5-6). The boom-extended autotest stands there
without god mode (a secret at once, health going down, the special 64
left) and fires Boom's numbered line types (142-241) at E1M1's sectors
with LINE:n:special.

Usage: make_boomext_wad.py [IWAD] [OUTFILE]
"""
import os
import struct
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')

SECTOR_SPECIALS = {140: 192}


def main():
    iwad = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'data', 'wads', 'freedoom1.wad')
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), 'testdata', 'boomext.wad')
    with open(iwad, 'rb') as f:
        data = f.read()
    count, offset = struct.unpack('<ii', data[4:12])
    entries = [struct.unpack('<ii8s', data[offset + 16 * i:offset + 16 * i + 16]) for i in range(count)]
    names = [e[2].rstrip(b'\0').decode('ascii') for e in entries]
    start = names.index('E1M1')
    lumps = [('E1M1', b'')]
    for i in range(start + 1, start + 11):
        pos, size, _ = entries[i]
        body = bytearray(data[pos:pos + size])
        if names[i] == 'SECTORS':
            for sector, special in SECTOR_SPECIALS.items():
                struct.pack_into('<h', body, 26 * sector + 22, special)
        lumps.append((names[i], bytes(body)))
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
