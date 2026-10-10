#!/usr/bin/env python3
"""Write the web app icons pages/icon-192.png and pages/icon-512.png from
Freedoom Phase 1's status bar face (the STFST01 patch, BSD licensed like the
rest of Freedoom), enlarged with whole pixels on a dark rounded square.

Usage: make_web_icons.py [WAD] [OUTDIR]   (needs Pillow)
"""
import os
import struct
import sys

from PIL import Image, ImageDraw

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')


def lumps(data):
    count, offset = struct.unpack('<ii', data[4:12])
    for i in range(count):
        pos, size, name = struct.unpack('<ii8s', data[offset + 16 * i:offset + 16 * i + 16])
        yield name.rstrip(b'\0').decode('ascii', 'replace'), data[pos:pos + size]


def decode_patch(patch, palette):
    """Doom's column-based picture format to an RGBA image."""
    width, height = struct.unpack('<hh', patch[0:4])
    img = Image.new('RGBA', (width, height), (0, 0, 0, 0))
    px = img.load()
    for x in range(width):
        pos = struct.unpack('<I', patch[8 + 4 * x:12 + 4 * x])[0]
        while patch[pos] != 255:
            top, length = patch[pos], patch[pos + 1]
            for i in range(length):
                c = patch[pos + 3 + i]
                px[x, top + i] = palette[c] + (255,)
            pos += length + 4
    return img


def main():
    wad = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'data', 'wads', 'freedoom1.wad')
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, 'pages')
    with open(wad, 'rb') as f:
        data = f.read()
    found = dict(lumps(data))
    pal = found['PLAYPAL']
    palette = [tuple(pal[3 * i:3 * i + 3]) for i in range(256)]
    face = decode_patch(found['STFST01'], palette)
    for size in (192, 512):
        icon = Image.new('RGBA', (size, size), (0, 0, 0, 0))
        ImageDraw.Draw(icon).rounded_rectangle([0, 0, size - 1, size - 1], radius=size // 6,
                                               fill=(40, 8, 8, 255))
        scale = (size * 3 // 4) // max(face.size)
        big = face.resize((face.width * scale, face.height * scale), Image.NEAREST)
        icon.alpha_composite(big, ((size - big.width) // 2, (size - big.height) // 2))
        path = os.path.join(out, 'icon-%d.png' % size)
        icon.save(path, optimize=True)
        print(path)


if __name__ == '__main__':
    main()
