#!/usr/bin/env python3
"""Generate code/doomstates_table.inc from Doom's info.c / info.h / sounds.h.

The include holds vanilla Doom's data tables as Pascal constants: the
sprite names, the state table (sprite, frame, tics, action, next state),
the mobjinfo rows' state and sound fields, and the sound names. DeHackEd
patches edit copies of them (DoomStates); the thing table (DoomThings)
derives its frame sequences from them.

Usage: make_states.py SRCDIR [OUTFILE]
  SRCDIR holds info.c, info.h and sounds.h from linuxdoom-1.10 (the
  released Doom source, https://github.com/id-Software/DOOM); OUTFILE
  defaults to code/doomstates_table.inc next to this tools/ directory.
"""
import os
import re
import sys


def read(path):
    with open(path, encoding='latin-1') as f:
        return f.read()


def enum_names(header, first, last):
    """The identifiers of an enum, from the line holding `first` to `last`."""
    lines = header.splitlines()
    names = []
    on = False
    for line in lines:
        s = re.sub(r'//.*', '', line).strip().rstrip(',').strip()
        if s == first:
            on = True
        if on:
            if re.match(r'^[A-Za-z_][A-Za-z0-9_]*$', s):
                names.append(s)
            if s == last:
                break
    return names


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    src = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), '..', 'code', 'doomstates_table.inc')
    info_c = read(os.path.join(src, 'info.c'))
    info_h = read(os.path.join(src, 'info.h'))
    sounds_h = read(os.path.join(src, 'sounds.h'))

    # Sprite names: char *sprnames[NUMSPRITES] = { "TROO", ... };
    m = re.search(r'sprnames\[NUMSPRITES\]\s*=\s*\{(.*?)\};', info_c, re.S)
    sprites = re.findall(r'"([A-Z0-9]{4})"', m.group(1))
    state_names = enum_names(info_h, 'S_NULL', 'S_TECH2LAMP4')
    mobj_names = enum_names(info_h, 'MT_PLAYER', 'MT_MISC86')
    sfx_names = enum_names(sounds_h, 'sfx_None', 'sfx_radio')
    sprite_index = {name: i for i, name in enumerate(sprites)}
    state_index = {name: i for i, name in enumerate(state_names)}
    sfx_index = {name: i for i, name in enumerate(sfx_names)}

    # States: {SPR_TROO,0,-1,{NULL},S_NULL,0,0},   // S_NULL
    m = re.search(r'states\[NUMSTATES\]\s*=\s*\{(.*?)\n\};', info_c, re.S)
    rows = re.findall(r'\{SPR_([A-Z0-9]{4})\s*,\s*(\d+)\s*,\s*(-?\d+)\s*,\s*\{(\w+)\}\s*,\s*(S_\w+)\s*,\s*(-?\d+)\s*,\s*(-?\d+)\s*\}',
                      m.group(1))
    assert len(rows) == len(state_names), (len(rows), len(state_names))
    actions = ['NULL']
    for r in rows:
        if r[3] not in actions:
            actions.append(r[3])

    # mobjinfo: 23 fields per row in a fixed order.
    m = re.search(r'mobjinfo\[NUMMOBJTYPES\]\s*=\s*\{(.*)\n\};', info_c, re.S)
    body = re.sub(r'//[^\n]*', '', m.group(1))
    entries = re.findall(r'\{([^{}]*)\}', body)
    assert len(entries) == len(mobj_names), (len(entries), len(mobj_names))
    fields = ['doomednum', 'spawnstate', 'spawnhealth', 'seestate', 'seesound', 'reactiontime',
              'attacksound', 'painstate', 'painchance', 'painsound', 'meleestate', 'missilestate',
              'deathstate', 'xdeathstate', 'deathsound', 'speed', 'radius', 'height', 'mass',
              'damage', 'activesound', 'flags', 'raisestate']
    flag_bits = {
        'MF_SPECIAL': 1, 'MF_SOLID': 2, 'MF_SHOOTABLE': 4, 'MF_NOSECTOR': 8, 'MF_NOBLOCKMAP': 16,
        'MF_AMBUSH': 32, 'MF_JUSTHIT': 64, 'MF_JUSTATTACKED': 128, 'MF_SPAWNCEILING': 256,
        'MF_NOGRAVITY': 512, 'MF_DROPOFF': 1024, 'MF_PICKUP': 2048, 'MF_NOCLIP': 4096,
        'MF_SLIDE': 8192, 'MF_FLOAT': 16384, 'MF_TELEPORT': 32768, 'MF_MISSILE': 65536,
        'MF_DROPPED': 131072, 'MF_SHADOW': 262144, 'MF_NOBLOOD': 524288, 'MF_CORPSE': 1048576,
        'MF_INFLOAT': 2097152, 'MF_COUNTKILL': 4194304, 'MF_COUNTITEM': 8388608,
        'MF_SKULLFLY': 16777216, 'MF_NOTDMATCH': 33554432, 'MF_TRANSLATION': 67108864,
    }

    def state(s):
        s = s.strip()
        return state_index[s] if s.startswith('S_') else int(s)

    def sfx(s):
        s = s.strip()
        return sfx_index[s] if s.startswith('sfx_') else int(s)

    def flags(s):
        v = 0
        for part in s.split('|'):
            part = part.strip()
            if part and part != '0':
                v |= flag_bits[part]
        return v

    def number(s):
        s = s.strip().replace('*FRACUNIT', '')
        return int(s)

    mobjs = []
    for name, entry in zip(mobj_names, entries):
        vals = [v.strip() for v in entry.split(',')]
        vals = [v for v in vals if v != '']
        assert len(vals) == len(fields), (name, vals)
        d = dict(zip(fields, vals))
        mobjs.append({
            'name': name,
            'doomednum': int(d['doomednum']),
            'spawn': state(d['spawnstate']), 'see': state(d['seestate']),
            'pain': state(d['painstate']), 'melee': state(d['meleestate']),
            'missile': state(d['missilestate']), 'death': state(d['deathstate']),
            'xdeath': state(d['xdeathstate']), 'raise': state(d['raisestate']),
            'seesound': sfx(d['seesound']), 'attacksound': sfx(d['attacksound']),
            'painsound': sfx(d['painsound']), 'deathsound': sfx(d['deathsound']),
            'activesound': sfx(d['activesound']),
            'health': number(d['spawnhealth']), 'speed': number(d['speed']),
            'radius': number(d['radius']), 'height': number(d['height']),
            'mass': number(d['mass']), 'damage': number(d['damage']),
            'painchance': number(d['painchance']), 'flags': flags(d['flags']),
        })

    def action_id(a):
        return 'sa' + (a[2:] if a.startswith('A_') else 'None')

    w = []
    w.append('{ Generated by tools/make_states.py from Doom\'s info.c, info.h and')
    w.append('  sounds.h (linuxdoom-1.10): vanilla Doom\'s sprite names, state table,')
    w.append('  the state and sound fields of its thing types, and the sound names.')
    w.append('  Do not edit: regenerate. }')
    w.append('')
    w.append('const')
    w.append('  VanillaSpriteCount = %d;' % len(sprites))
    w.append('  VanillaStateCount = %d;' % len(rows))
    w.append('  VanillaMobjCount = %d;' % len(mobjs))
    w.append('  VanillaSoundCount = %d;' % len(sfx_names))
    w.append('')
    w.append('type')
    w.append('  { Every action (code pointer) of the state table, in order of first use. }')
    w.append('  TStateAction = (')
    ids = [action_id(a) for a in actions]
    for i in range(0, len(ids), 6):
        w.append('    ' + ', '.join(ids[i:i + 6]) + (',' if i + 6 < len(ids) else ');'))
    w.append('')
    w.append('  TStateDef = record')
    w.append('    Sprite, Frame, Tics: Integer;')
    w.append('    Action: TStateAction;')
    w.append('    Next: Integer;')
    w.append('  end;')
    w.append('')
    w.append('  TMobjDef = record')
    w.append('    DoomedNum, Spawn, See, Pain, Melee, Missile, Death, XDeath, RaiseState: Integer;')
    w.append('    SeeSound, AttackSound, PainSound, DeathSound, ActiveSound: Integer;')
    w.append('    Health, Speed, Radius, Height, Mass, Damage, PainChance, Flags: Integer;')
    w.append('  end;')
    w.append('')
    w.append('const')
    w.append('  ActionNames: array [TStateAction] of String = (')
    names = ["'%s'" % (a if a != 'NULL' else '') for a in actions]
    for i in range(0, len(names), 6):
        w.append('    ' + ', '.join(names[i:i + 6]) + (',' if i + 6 < len(names) else ');'))
    w.append('')
    w.append('  VanillaSprites: array [0..VanillaSpriteCount - 1] of String[4] = (')
    for i in range(0, len(sprites), 10):
        w.append('    ' + ', '.join("'%s'" % s for s in sprites[i:i + 10]) +
                 (',' if i + 10 < len(sprites) else ');'))
    w.append('')
    w.append('  VanillaSounds: array [0..VanillaSoundCount - 1] of String[8] = (')
    names = ['' if n == 'sfx_None' else 'DS' + n[4:].upper() for n in sfx_names]
    for i in range(0, len(names), 8):
        w.append('    ' + ', '.join("'%s'" % s for s in names[i:i + 8]) +
                 (',' if i + 8 < len(names) else ');'))
    w.append('')
    w.append('  { Sprite index, frame (bit 15 = full bright), tics (-1 = forever), action, next state. }')
    w.append('  VanillaStates: array [0..VanillaStateCount - 1] of TStateDef = (')
    for i, (spr, frame, tics, action, nxt, m1, m2) in enumerate(rows):
        w.append('    (Sprite: %d; Frame: %d; Tics: %d; Action: %s; Next: %d)%s { %d S_%s }' % (
            sprite_index[spr], int(frame), int(tics), action_id(action), state_index[nxt],
            ',' if i + 1 < len(rows) else ');', i, state_names[i][2:]))
    w.append('')
    w.append('  { State names (for DeHackEd logs), without the S_ prefix. }')
    w.append('  VanillaStateNames: array [0..VanillaStateCount - 1] of String[20] = (')
    for i in range(0, len(state_names), 6):
        w.append('    ' + ', '.join("'%s'" % s[2:] for s in state_names[i:i + 6]) +
                 (',' if i + 6 < len(state_names) else ');'))
    w.append('')
    w.append('  { info.c\'s mobjinfo rows (DeHackEd "Thing N" is row N - 1). }')
    w.append('  VanillaMobjs: array [0..VanillaMobjCount - 1] of TMobjDef = (')
    for i, mo in enumerate(mobjs):
        w.append('    (DoomedNum: %d; Spawn: %d; See: %d; Pain: %d; Melee: %d; Missile: %d; Death: %d; XDeath: %d; RaiseState: %d;' % (
            mo['doomednum'], mo['spawn'], mo['see'], mo['pain'], mo['melee'], mo['missile'],
            mo['death'], mo['xdeath'], mo['raise']))
        w.append('     SeeSound: %d; AttackSound: %d; PainSound: %d; DeathSound: %d; ActiveSound: %d;' % (
            mo['seesound'], mo['attacksound'], mo['painsound'], mo['deathsound'], mo['activesound']))
        w.append('     Health: %d; Speed: %d; Radius: %d; Height: %d; Mass: %d; Damage: %d; PainChance: %d; Flags: %d)%s { %d %s }' % (
            mo['health'], mo['speed'], mo['radius'], mo['height'], mo['mass'], mo['damage'],
            mo['painchance'], mo['flags'], ',' if i + 1 < len(mobjs) else ');', i, mo['name']))
    w.append('')
    with open(out, 'w', newline='\n') as f:
        f.write('\n'.join(w))
    print('%s: %d sprites, %d states, %d actions, %d things, %d sounds' % (
        out, len(sprites), len(rows), len(actions), len(mobjs), len(sfx_names)))


if __name__ == '__main__':
    main()
