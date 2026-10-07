"""Build test PWADs whose E1M1 uses ZDoom extended node formats, converted from
Freedoom's vanilla E1M1 nodes, to exercise DoomMap.LoadExtendedNodes.

XNOD/ZNOD: vanilla segs re-encoded; every seg's v1 is replaced by a NEW
fixed-point copy of the vertex (tests the new-vertex path and index mapping).
XGLN/ZGL2/XGL3/ZGL3: real GL nodes (closed subsectors with minisegs) computed
by clipping the BSP like DoomMap.BuildSubsectorPolygons, stored in SSECTORS
with NODES and SEGS empty, as ZDBSP does for Doom-format maps."""
import struct, zlib, sys

import os
src = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'data', 'wads', 'freedoom1.wad')
d = open(src, 'rb').read()
ident, n, off = struct.unpack('<4sii', d[:12])
lumps = []
for i in range(n):
    p, s, name = struct.unpack('<ii8s', d[off+16*i:off+16*i+16])
    lumps.append((name.rstrip(b'\0').decode(), p, s))
names = [l[0] for l in lumps]
mi = names.index('E1M1')
maplumps = lumps[mi:mi+11]
def lump(nm):
    for (x, p, s) in maplumps:
        if x == nm: return d[p:p+s]
V = lump('VERTEXES'); verts = [struct.unpack('<hh', V[k*4:k*4+4]) for k in range(len(V)//4)]
S = lump('SEGS'); segs = [struct.unpack('<HHhHhh', S[k*12:k*12+12]) for k in range(len(S)//12)]
SS = lump('SSECTORS'); subs = [struct.unpack('<HH', SS[k*4:k*4+4]) for k in range(len(SS)//4)]
N = lump('NODES'); nodes = [struct.unpack('<hhhh8hHH', N[k*28:k*28+28]) for k in range(len(N)//28)]

def fx(v): return int(round(v * 65536))

def child32(c):
    return (c & 0x7FFF) | 0x80000000 if c & 0x8000 else c

def nodes_blob(fixed):
    out = struct.pack('<I', len(nodes))
    for nd in nodes:
        x, y, dx, dy = nd[0:4]
        if fixed: out += struct.pack('<iiii', fx(x), fx(y), fx(dx), fx(dy))
        else: out += struct.pack('<hhhh', x, y, dx, dy)
        out += struct.pack('<8h', *nd[4:12])
        out += struct.pack('<II', child32(nd[12]), child32(nd[13]))
    return out

def xnod():
    newv = []; out_segs = []
    for (v1, v2, ang, line, side, ofs) in segs:
        newv.append(verts[v1])
        out_segs.append((len(verts) + len(newv) - 1, v2, line, side))
    b = struct.pack('<II', len(verts), len(newv))
    for (x, y) in newv: b += struct.pack('<ii', fx(x), fx(y))
    b += struct.pack('<I', len(subs))
    for (cnt, first) in subs: b += struct.pack('<I', cnt)
    b += struct.pack('<I', len(out_segs))
    for (a, bb, line, side) in out_segs: b += struct.pack('<IIHB', a, bb, line, side)
    b += nodes_blob(False)
    return b

# --- GL nodes: subsector polygons by BSP clipping (same as the Pascal code) ---
def clip(poly, px, py, dx, dy, keep_pos):
    eps = 1e-4; res = []
    def side(p):
        r = (p[0]-px)*dy - (p[1]-py)*dx
        return r if keep_pos else -r
    for i in range(len(poly)):
        a = poly[i]; b = poly[(i+1) % len(poly)]
        sa = side(a); sb = side(b)
        ina = sa >= -eps; inb = sb >= -eps
        if ina: res.append(a)
        if ina != inb:
            t = sa / (sa - sb); res.append((a[0]+(b[0]-a[0])*t, a[1]+(b[1]-a[1])*t))
    return res

polys = {}
def walk(child, poly):
    if len(poly) < 3: return
    if child & 0x8000:
        sub = child & 0x7FFF
        cnt, first = subs[sub]
        p = poly
        for k in range(cnt):
            v1, v2, ang, line, side, ofs = segs[first+k]
            a = verts[v1]; b = verts[v2]
            if a == b: continue
            p = clip(p, a[0], a[1], b[0]-a[0], b[1]-a[1], True)
            if len(p) < 3: return
        # drop near-duplicate points
        q = []
        for pt in p:
            if not q or abs(pt[0]-q[-1][0]) + abs(pt[1]-q[-1][1]) > 1e-3: q.append(pt)
        if len(q) > 1 and abs(q[0][0]-q[-1][0]) + abs(q[0][1]-q[-1][1]) <= 1e-3: q.pop()
        polys[sub] = q
        return
    nd = nodes[child]
    x, y, dx, dy = nd[0:4]
    walk(nd[12], clip(poly, x, y, dx, dy, True))
    walk(nd[13], clip(poly, x, y, dx, dy, False))

xs = [v[0] for v in verts]; ys = [v[1] for v in verts]
M = 128
walk(len(nodes)-1, [(min(xs)-M, min(ys)-M), (max(xs)+M, min(ys)-M), (max(xs)+M, max(ys)+M), (min(xs)-M, max(ys)+M)])

def gl(long_lines, fixed_nodes):
    newv = []; subcounts = []; out_segs = []; minisegs = 0
    for si, (cnt, first) in enumerate(subs):
        poly = polys.get(si)
        if not poly or len(poly) < 3:
            # degenerate: keep the vanilla segs' v1 (still gives the sector)
            for k in range(cnt):
                v1, v2, ang, line, side, ofs = segs[first+k]
                out_segs.append((v1, line, side))
            subcounts.append(cnt); continue
        cw = list(reversed(poly))  # subsector lies right of its segs: clockwise
        for i in range(len(cw)):
            a = cw[i]; b = cw[(i+1) % len(cw)]
            line = 0xFFFFFFFF; side = 0
            for k in range(cnt):
                v1, v2, ang, ln, sd, ofs = segs[first+k]
                p1 = verts[v1]; p2 = verts[v2]
                ex, ey = p2[0]-p1[0], p2[1]-p1[1]
                L = (ex*ex+ey*ey) ** 0.5
                if L == 0: continue
                ca = ((a[0]-p1[0])*ey - (a[1]-p1[1])*ex) / L
                cb = ((b[0]-p1[0])*ey - (b[1]-p1[1])*ex) / L
                dot = (b[0]-a[0])*ex + (b[1]-a[1])*ey
                if abs(ca) < 0.01 and abs(cb) < 0.01 and dot > 0:
                    line = ln; side = sd; break
            if line == 0xFFFFFFFF: minisegs += 1
            newv.append(a)
            out_segs.append((len(verts) + len(newv) - 1, line, side))
        subcounts.append(len(cw))
    b = struct.pack('<II', len(verts), len(newv))
    for (x, y) in newv: b += struct.pack('<ii', fx(x), fx(y))
    b += struct.pack('<I', len(subcounts))
    for c in subcounts: b += struct.pack('<I', c)
    b += struct.pack('<I', len(out_segs))
    for (v1, line, side) in out_segs:
        if long_lines: b += struct.pack('<IIIB', v1, 0xFFFFFFFF, line, side)
        else: b += struct.pack('<IIHB', v1, 0xFFFFFFFF, 0xFFFF if line == 0xFFFFFFFF else line, side)
    b += nodes_blob(fixed_nodes)
    print('  GL: %d new vertices, %d segs (%d minisegs), %d subsectors' % (len(newv), len(out_segs), minisegs, len(subcounts)))
    return b

def write_pwad(path, nodes_data, segs_data, subs_data):
    out = bytearray(b'PWAD' + struct.pack('<ii', 0, 0)); ents = []
    for (nm, p, s) in maplumps:
        if nm == 'NODES': data = nodes_data
        elif nm == 'SEGS': data = segs_data
        elif nm == 'SSECTORS': data = subs_data
        else: data = d[p:p+s]
        ents.append((len(out), len(data), nm)); out += data
    diroff = len(out)
    for (p, s, nm) in ents: out += struct.pack('<ii8s', p, s, nm.encode().ljust(8, b'\0'))
    out[4:12] = struct.pack('<ii', len(ents), diroff)
    open(path, 'wb').write(out)
    print('wrote', path, len(out))

outdir = (sys.argv[1] if len(sys.argv) > 1 else '.') + '/'
x = xnod()
write_pwad(outdir + 'e1m1_xnod.wad', b'XNOD' + x, b'', b'')
write_pwad(outdir + 'e1m1_znod.wad', b'ZNOD' + zlib.compress(x), b'', b'')
g16 = gl(False, False)
write_pwad(outdir + 'e1m1_xgln.wad', b'', b'', b'XGLN' + g16)
g2 = gl(True, False)
write_pwad(outdir + 'e1m1_zgl2.wad', b'', b'', b'ZGL2' + zlib.compress(g2))
g3 = gl(True, True)
write_pwad(outdir + 'e1m1_xgl3.wad', b'', b'', b'XGL3' + g3)
write_pwad(outdir + 'e1m1_zgl3.wad', b'', b'', b'ZGL3' + zlib.compress(g3))
area = 0
for poly in polys.values():
    a = 0
    for i in range(len(poly)):
        a += poly[i][0]*poly[(i+1) % len(poly)][1] - poly[(i+1) % len(poly)][0]*poly[i][1]
    area += a/2
print('python total subsector area %.0f in %d polygons' % (area, len(polys)))
