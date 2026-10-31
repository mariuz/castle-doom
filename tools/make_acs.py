#!/usr/bin/env python3
"""A small ACS assembler and the test scripts of the ACS interpreter
(code/doomacs.pas).

ACC compiles ACS source into a BEHAVIOR lump; here the p-codes are written
by hand (numbers from code/doomacs_pcodes.inc) in each of the lump
layouts the game reads:

- 'old':    Hexen's "ACS\\0" with the script directory at its end;
- 'compat': "ACS\\0" whose directory offset points past ZDoom's chunks
            and an "ACSe" marker (what ACC writes), 8-byte SPTR entries;
- 'E':      "ACSE", 32-bit p-codes, chunks, the strings in STRE (the
            encrypted table);
- 'e':      "ACSe", byte p-codes and byte arguments.

tests_program() is the program of tools/testdata/acs.wad (one lump per
layout, for the unit test TestAcs) and of udmf-acs.wad's BEHAVIOR
(tools/make_udmf_wad.py):

- script 1 (open): prints "Hello from ACS", counts map variable 0 to 3
  with 10-tic delays, raises the sectors tagged 10 by 32
  (Floor_RaiseByValue), waits for them (TagWait), prints "Floor at 32"
  (GetSectorFloorZ) and "Imps: N" (ThingCount(T_IMP, 0));
- script 2 (closed, one argument x): Light_ChangeToValue(9, x * 20 + 60),
  ChangeFloor(9, "FLOOR7_2"), a switch printing "Seven" in bold for 7,
  world variable 0 + 1; with functions (not 'old'): prints "Twice 14"
  (a function), "Array 30" (a map array) and "Init 100" (MINI);
- script 3 (enter): HudMessage "Welcome" with its six arguments.

Usage: make_acs.py [OUTDIR]   (writes OUTDIR/acs.wad, default tools/testdata)
"""
import os
import re
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def pcodes():
    """PCD names -> numbers, from the generated Pascal include."""
    path = os.path.join(HERE, '..', 'code', 'doomacs_pcodes.inc')
    with open(path) as f:
        text = f.read()
    names = re.findall(r"^    '([A-Z0-9_]+)'", text, re.M)
    return {n: i for i, n in enumerate(names)}


P = pcodes()


class Asm:
    """P-code for one layout; addresses are absolute lump offsets."""

    def __init__(self, layout):
        self.layout = layout
        self.little = layout in ('e', 'compat')
        self.code = bytearray()
        self.labels = {}
        self.fixups = []

    def pos(self):
        return 8 + len(self.code)

    def op(self, name, *args):
        p = P[name]
        if self.little:
            if p < 240:
                self.code.append(p)
            else:
                self.code += bytes([240 + ((p - 240) >> 8), (p - 240) & 255])
        else:
            self.code += struct.pack('<i', p)
        for a in args:
            self.word(a)

    def word(self, v):
        if isinstance(v, str):
            self.fixups.append((len(self.code), v))
            v = 0
        self.code += struct.pack('<i', v)

    def nbyte(self, v):
        """NEXTBYTE: a byte in ACSe, else 32 bits."""
        if self.little:
            self.code.append(v & 255)
        else:
            self.code += struct.pack('<i', v)

    def raw(self, *bs):
        self.code += bytes(b & 255 for b in bs)

    def label(self, name):
        self.labels[name] = self.pos()

    def finish(self):
        for at, name in self.fixups:
            self.code[at:at + 4] = struct.pack('<i', self.labels[name])
        return bytes(self.code)

    # A few instructions with their inline arguments.
    def var(self, name, index):
        self.op(name)
        self.nbyte(index)

    def lspec(self, n, special):
        self.op('LSPEC%d' % n)
        self.nbyte(special)

    def lspec_direct(self, special, *args):
        self.op('LSPEC%dDIRECT' % len(args))
        self.nbyte(special)
        for a in args:
            self.word(a)

    def push(self, v):
        if self.little and 0 <= v < 256:
            self.op('PUSHBYTE')
            self.raw(v)
        else:
            self.op('PUSHNUMBER', v)

    def print_str(self, s, strings):
        self.push(strings.index(s))
        self.op('PRINTSTRING')


STRINGS = ['Hello from ACS', 'Floor at ', 'Imps: ', 'Seven', 'Eight', 'FLOOR7_2', 'Twice ', 'Array ', 'Init ',
           'Welcome']


def tests_program(layout):
    """The test scripts as (code, scripts, functions, strings, extras)."""
    a = Asm(layout)
    S = STRINGS
    enhanced = layout != 'old'
    # Script 1, open.
    a.label('s1')
    a.op('BEGINPRINT')
    a.print_str('Hello from ACS', S)
    a.op('ENDPRINT')
    a.label('loop')
    a.var('PUSHMAPVAR', 0)
    a.push(3)
    a.op('LT')
    a.op('IFNOTGOTO', 'done')
    a.var('INCMAPVAR', 0)
    if a.little:
        a.op('DELAYDIRECTB')
        a.raw(10)
    else:
        a.op('DELAYDIRECT', 10)
    a.op('GOTO', 'loop')
    a.label('done')
    a.lspec_direct(23, 10, 16, 32)  # Floor_RaiseByValue(10, 16, 32)
    a.op('TAGWAITDIRECT', 10)
    a.op('BEGINPRINT')
    a.print_str('Floor at ', S)
    a.push(10)
    a.push(0)
    a.push(0)
    a.op('GETSECTORFLOORZ')
    a.push(16)
    a.op('RSHIFT')
    a.op('PRINTNUMBER')
    a.op('ENDPRINT')
    a.push(5)  # T_IMP
    a.push(0)
    a.op('THINGCOUNT')
    a.var('ASSIGNMAPVAR', 3)
    a.op('BEGINPRINT')
    a.print_str('Imps: ', S)
    a.var('PUSHMAPVAR', 3)
    a.op('PRINTNUMBER')
    a.op('ENDPRINT')
    a.op('TERMINATE')
    # Script 2, closed, x = local 0.
    a.label('s2')
    a.var('PUSHSCRIPTVAR', 0)
    a.push(20)
    a.op('MULTIPLY')
    a.push(60)
    a.op('ADD')
    a.var('ASSIGNSCRIPTVAR', 1)
    a.push(9)
    a.var('PUSHSCRIPTVAR', 1)
    a.lspec(2, 112)  # Light_ChangeToValue(9, x * 20 + 60)
    a.op('CHANGEFLOORDIRECT', 9, S.index('FLOOR7_2'))
    a.var('PUSHSCRIPTVAR', 0)
    a.op('CASEGOTO', 7, 'seven')
    a.op('CASEGOTO', 8, 'eight')
    a.op('DROP')
    a.op('GOTO', 'end')
    a.label('seven')
    a.op('BEGINPRINT')
    a.print_str('Seven', S)
    a.op('ENDPRINTBOLD')
    a.op('GOTO', 'end')
    a.label('eight')
    a.op('BEGINPRINT')
    a.print_str('Eight', S)
    a.op('ENDPRINT')
    a.label('end')
    a.var('INCWORLDVAR', 0)
    if enhanced:
        a.op('BEGINPRINT')
        a.print_str('Twice ', S)
        a.var('PUSHSCRIPTVAR', 0)
        a.op('CALL')
        a.nbyte(0)
        a.op('PRINTNUMBER')
        a.op('ENDPRINT')
        a.op('BEGINPRINT')
        a.print_str('Array ', S)
        a.push(2)
        a.var('PUSHMAPARRAY', 2)
        a.op('PRINTNUMBER')
        a.op('ENDPRINT')
        a.op('BEGINPRINT')
        a.print_str('Init ', S)
        a.var('PUSHMAPVAR', 1)
        a.op('PRINTNUMBER')
        a.op('ENDPRINT')
    a.op('TERMINATE')
    # Script 3, enter: HudMessage(s:"Welcome"; HUDMSG_PLAIN, 1, CR_RED, 0.5, 0.5, 2.0).
    a.label('s3')
    a.op('BEGINPRINT')
    a.print_str('Welcome', S)
    a.op('MOREHUDMESSAGE')
    a.push(0)
    a.push(1)
    a.push(6)
    a.op('PUSHNUMBER', 32768)
    a.op('PUSHNUMBER', 32768)
    a.op('PUSHNUMBER', 2 << 16)
    a.op('ENDHUDMESSAGE')
    if a.little:
        a.op('RANDOMDIRECTB')
        a.raw(1, 1)
    else:
        a.op('RANDOMDIRECT', 1, 1)
    a.op('DROP')
    a.op('TERMINATE')
    funcs = []
    if enhanced:
        # function int Twice(int x) { return x * 2; }
        a.label('f0')
        a.var('PUSHSCRIPTVAR', 0)
        a.push(2)
        a.op('MULTIPLY')
        a.op('RETURNVAL')
        funcs = [(1, 0, 1, 'f0')]
    code = a.finish()
    scripts = [(1, 1, a.labels['s1'], 0), (2, 0, a.labels['s2'], 1), (3, 4, a.labels['s3'], 0)]
    funcs = [(argc, loc, ret, a.labels[l]) for (argc, loc, ret, l) in funcs]
    return code, scripts, funcs, S


def chunk(cid, data):
    return cid + struct.pack('<i', len(data)) + data


def string_table(strings, encrypted):
    """STRL / STRE: pad, count, pad, offsets (from the chunk data), text."""
    head = 12 + 4 * len(strings)
    offs, blob = [], bytearray()
    for s in strings:
        offs.append(head + len(blob))
        b = bytearray(s.encode('latin-1') + b'\0')
        if encrypted:
            key = (offs[-1] * 157135) & 255
            b = bytearray(c ^ ((key + (i >> 1)) & 255) for i, c in enumerate(b))
        blob += b
    data = struct.pack('<iii', 0, len(strings), 0) + b''.join(struct.pack('<i', o) for o in offs) + bytes(blob)
    return chunk(b'STRE' if encrypted else b'STRL', data)


def behavior(layout, program=None):
    """A BEHAVIOR lump of the test program in one layout."""
    code, scripts, funcs, strings = program or tests_program(layout)
    if layout == 'old':
        out = bytearray(b'ACS\0' + b'\0\0\0\0') + code
        str_offs = []
        for s in strings:
            str_offs.append(len(out))
            out += s.encode('latin-1') + b'\0'
        while len(out) % 4:
            out.append(0)
        dirofs = len(out)
        out += struct.pack('<i', len(scripts))
        for (num, typ, addr, argc) in scripts:
            out += struct.pack('<iii', typ * 1000 + num, addr, argc)
        out += struct.pack('<i', len(strings)) + b''.join(struct.pack('<i', o) for o in str_offs)
        out[4:8] = struct.pack('<i', dirofs)
        return bytes(out)
    chunks = bytearray()
    if layout == 'compat':
        chunks += chunk(b'SPTR', b''.join(struct.pack('<hBBi', num, typ, argc, addr)
                                          for (num, typ, addr, argc) in scripts))
    else:
        chunks += chunk(b'SPTR', b''.join(struct.pack('<hHii', num, typ, addr, argc)
                                          for (num, typ, addr, argc) in scripts))
    chunks += chunk(b'FUNC', b''.join(struct.pack('<BBBBi', argc, loc, ret, 0, addr)
                                      for (argc, loc, ret, addr) in funcs))
    chunks += string_table(strings, layout == 'E')
    # Map variable 1 starts at 100; map variable 2 is a 4-element array.
    chunks += chunk(b'MINI', struct.pack('<ii', 1, 100))
    chunks += chunk(b'ARAY', struct.pack('<ii', 2, 4))
    chunks += chunk(b'AINI', struct.pack('<iiiii', 2, 10, 20, 30, 40))
    if layout == 'compat':
        out = bytearray(b'ACS\0' + b'\0\0\0\0') + code
        while len(out) % 4:
            out.append(0)
        chunks_at = len(out)
        out += chunks + struct.pack('<i', chunks_at) + b'ACSe'
        dirofs = len(out)
        # The old directory Hexen would read: nothing.
        out += struct.pack('<ii', 0, 0)
        out[4:8] = struct.pack('<i', dirofs)
        return bytes(out)
    out = bytearray((b'ACSE' if layout == 'E' else b'ACSe') + b'\0\0\0\0') + code
    while len(out) % 4:
        out.append(0)
    out[4:8] = struct.pack('<i', len(out))
    out += chunks
    return bytes(out)


def write_wad(path, lumps):
    out = bytearray(b'PWAD' + struct.pack('<ii', 0, 0))
    ents = []
    for name, data in lumps:
        ents.append((len(out), len(data), name))
        out += data
    diroff = len(out)
    for (p, s, name) in ents:
        out += struct.pack('<ii8s', p, s, name.encode().ljust(8, b'\0'))
    out[4:12] = struct.pack('<ii', len(ents), diroff)
    with open(path, 'wb') as f:
        f.write(out)
    print('wrote', path, len(out))


def main():
    outdir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, 'testdata')
    os.makedirs(outdir, exist_ok=True)
    write_wad(os.path.join(outdir, 'acs.wad'), [('ACS_OLD', behavior('old')), ('ACS_COMP', behavior('compat')),
                                                ('ACS_E', behavior('E')), ('ACS_LE', behavior('e'))])


if __name__ == '__main__':
    main()
