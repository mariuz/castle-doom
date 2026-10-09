"""Build test PWADs whose E1M1 has only glBSP GL nodes, to exercise
DoomMap.LoadGlNodes.

Freedoom's E1M1 lumps are copied into a PWAD with NODES, SEGS and SSECTORS
emptied, then glBSP (`apt-get install glbsp`) adds GL_E1M1 with GL_VERT,
GL_SEGS, GL_SSECT and GL_NODES in each GL-node version it writes (1, 2, 3
and 5), without rebuilding the normal nodes (-xn).

Usage: make_glnodes.py OUTDIR   ->  OUTDIR/e1m1_gl_v1.wad ... _v5.wad
Each must load with "-file" and log the same subsector polygon total area
as the vanilla map (6712683)."""
import os
import struct
import subprocess
import sys


def read_wad(path):
    d = open(path, 'rb').read()
    ident, n, off = struct.unpack('<4sii', d[:12])
    lumps = []
    for i in range(n):
        p, s, name = struct.unpack('<ii8s', d[off + 16 * i:off + 16 * i + 16])
        lumps.append((name.rstrip(b'\0').decode(), d[p:p + s]))
    return lumps


def write_wad(path, lumps):
    data = b''
    directory = b''
    pos = 12
    for name, blob in lumps:
        directory += struct.pack('<ii8s', pos, len(blob), name.encode())
        data += blob
        pos += len(blob)
    with open(path, 'wb') as f:
        f.write(struct.pack('<4sii', b'PWAD', len(lumps), pos) + data + directory)


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    src = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'data', 'wads', 'freedoom1.wad')
    lumps = read_wad(src)
    names = [l[0] for l in lumps]
    mi = names.index('E1M1')
    level = []
    for name, blob in lumps[mi:mi + 11]:
        if name in ('NODES', 'SEGS', 'SSECTORS'):
            blob = b''
        level.append((name, blob))
    plain = os.path.join(out, 'e1m1_nonodes.wad')
    write_wad(plain, level)
    for v in (1, 2, 3, 5):
        dest = os.path.join(out, 'e1m1_gl_v%d.wad' % v)
        subprocess.run(['glbsp', '-q', '-xn', '-xr', '-v%d' % v, plain, '-o', dest],
                       check=True, stdout=subprocess.DEVNULL)
        print(dest, [n for n, _ in read_wad(dest)])


if __name__ == '__main__':
    main()
