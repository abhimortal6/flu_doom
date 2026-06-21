#!/usr/bin/env python3
"""Generate faithful Dart info tables from reference/chocolate-doom/src/doom.

Parses info.h (enums), info.c (sprnames, states[], mobjinfo[]),
sounds.h (sfx enum), d_items.c/.h (weaponinfo[]) and emits:
  lib/game/play/info.dart        (SpriteNum enum + spriteNames + State/MobjInfo classes)
  lib/game/play/state_num.dart   (St.* statenum ordinals)
  lib/game/play/info_tables.dart (states[], mobjInfo[], Mt.*, weaponInfo[], doomedToMobjType)
  lib/game/play/sounds.dart      (Sfx.* sfx ordinals)

Faithful port: every value comes straight from the reference C.
"""
import re, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'reference', 'chocolate-doom', 'src', 'doom')

def read(name):
    with open(os.path.join(SRC, name)) as f:
        return f.read()

info_h = read('info.h')
info_c = read('info.c')
sounds_h = read('sounds.h')
ditems_c = read('d_items.c')
doomdef_h = read('doomdef.h')

# ---- parse a C enum body into ordered identifier list (excluding NUM* / markers we keep) ----
def parse_enum(text, start_token, terminator):
    i = text.index(start_token)
    body = text[i:]
    # take from first '{' after typedef enum to matching close used by terminator
    # We rely on the terminator name being the last real enum entry's sentinel.
    names = []
    for line in body.splitlines():
        s = line.strip()
        if not s or s.startswith('//') or s.startswith('/*') or s.startswith('*'):
            continue
        m = re.match(r'([A-Za-z_][A-Za-z0-9_]*)', s)
        if not m:
            continue
        name = m.group(1)
        if name in ('typedef', 'enum'):
            continue
        names.append(name)
        if name == terminator:
            break
    return names

# spritenum_t: SPR_* up to NUMSPRITES
spr_names = []
m = re.search(r'\{\s*\n((?:\s*SPR_[A-Z0-9]+,\s*\n)+)\s*NUMSPRITES', info_h)
spr_names = re.findall(r'SPR_([A-Z0-9]+)', m.group(1))

# statenum_t: S_* up to NUMSTATES
m = re.search(r'\{\s*\n((?:\s*S_[A-Z0-9_]+,\s*\n)+)\s*NUMSTATES', info_h)
state_names = re.findall(r'\b(S_[A-Z0-9_]+),', m.group(1))

# mobjtype_t: MT_* up to NUMMOBJTYPES
m = re.search(r'\{\s*\n((?:\s*MT_[A-Z0-9_]+,\s*\n)+)\s*NUMMOBJTYPES', info_h)
mt_names = re.findall(r'\b(MT_[A-Z0-9_]+),', m.group(1))

# sfx enum from sounds.h
m = re.search(r'sfx_None,(.*?)NUMSFX', sounds_h, re.S)
sfx_block = 'sfx_None,' + m.group(1)
sfx_names = re.findall(r'\b(sfx_[A-Za-z0-9_]+)\b', sfx_block)
# keep order, dedupe preserving first
seen=set(); sfx_order=[]
for s in sfx_names:
    if s not in seen:
        seen.add(s); sfx_order.append(s)
sfx_index = {n:i for i,n in enumerate(sfx_order)}

state_index = {n:i for i,n in enumerate(state_names)}
spr_index = {n:i for i,n in enumerate(spr_names)}
mt_index = {n:i for i,n in enumerate(mt_names)}

# ---- sprnames[] strings ----
m = re.search(r'const char \*sprnames\[\] = \{(.*?)NULL', info_c, re.S)
sprstrs = re.findall(r'"([A-Z0-9]+)"', m.group(1))
assert len(sprstrs) == len(spr_names), (len(sprstrs), len(spr_names))

# ---- states[] table ----
m = re.search(r'state_t\s+states\[NUMSTATES\] = \{(.*?)\n\};', info_c, re.S)
states_body = m.group(1)
# each entry: {SPR_X,frame,tics,{ACTION},S_NEXT,misc1,misc2}, // comment
state_rows = []
for em in re.finditer(r'\{\s*(SPR_[A-Z0-9]+)\s*,\s*([0-9]+)\s*,\s*(-?[0-9]+)\s*,\s*\{\s*([A-Za-z0-9_]+)\s*\}\s*,\s*(S_[A-Z0-9_]+)\s*,\s*(-?[0-9]+)\s*,\s*(-?[0-9]+)\s*\}', states_body):
    spr, frame, tics, action, nxt, m1, m2 = em.groups()
    state_rows.append((spr, int(frame), int(tics), action, nxt, int(m1), int(m2)))
assert len(state_rows) == len(state_names), (len(state_rows), len(state_names))

# collect action names (exclude NULL)
action_names = sorted({r[3] for r in state_rows if r[3] != 'NULL'})

# ---- mobjinfo[] table ----
m = re.search(r'mobjinfo_t mobjinfo\[NUMMOBJTYPES\] = \{(.*)\n\};', info_c, re.S)
mi_body = m.group(1)
# split by top-level entries: each begins with "{\t\t// MT_"
entries = re.split(r'\n\s*\{\s*//\s*MT_', mi_body)
# first split element is junk before first entry
mobj_rows = []
field_order = ['doomednum','spawnstate','spawnhealth','seestate','seesound',
               'reactiontime','attacksound','painstate','painchance','painsound',
               'meleestate','missilestate','deathstate','xdeathstate','deathsound',
               'speed','radius','height','mass','damage','activesound','flags','raisestate']
for chunk in entries[1:]:
    # strip values: each is "VALUE,\t// fieldname" or last "VALUE\t// raisestate"
    vals = re.findall(r'^\s*([^,\n][^\n]*?)\s*,?\s*//\s*\w+', chunk, re.M)
    # the regex above grabs value up to comma/comment. Clean trailing commas.
    cleaned = []
    for v in vals:
        v = v.strip().rstrip(',').strip()
        cleaned.append(v)
    assert len(cleaned) == 23, (len(cleaned), cleaned[:5], chunk[:80])
    mobj_rows.append(cleaned)
assert len(mobj_rows) == len(mt_names), (len(mobj_rows), len(mt_names))

# ---- weaponinfo[] ----
m = re.search(r'weaponinfo_t\s+weaponinfo\[NUMWEAPONS\] =\s*\{(.*)\n\};', ditems_c, re.S)
wi_body = m.group(1)
weap_entries = re.split(r'\n\s*\{', wi_body)
weap_rows = []
ammo_index = {'am_clip':0,'am_shell':1,'am_cell':2,'am_misl':3,'am_noammo':5}
for chunk in weap_entries[1:]:
    toks = re.findall(r'\b(am_[a-z]+|S_[A-Z0-9_]+)\b', chunk)
    if len(toks) < 6: continue
    weap_rows.append(toks[:6])
assert len(weap_rows) == 9, len(weap_rows)

# ============ value translation helpers ============
def spr_dart(tok):
    return 'SpriteNum.' + tok[len('SPR_'):].lower()

def frame_dart(f):
    if f >= 32768:
        base = f - 32768
        return f'{base} | _fb' if base else '_fb'
    return str(f)

def state_ord(tok):
    return state_index[tok]

def sfx_dart(tok):
    return str(sfx_index[tok])

def fixed_dart(expr):
    # forms: "0", "16*FRACUNIT", "20*FRACUNIT", "1000000"
    expr = expr.strip()
    m = re.match(r'(-?[0-9]+)\*FRACUNIT$', expr)
    if m:
        return f'{m.group(1)} << 16'
    m = re.match(r'(-?[0-9]+)\*FRACUNIT/2$', expr)
    if m:
        return f'({m.group(1)} << 16) ~/ 2'
    # plain int
    return expr

FLAG_MAP = {
 'MF_SPECIAL':'mfSpecial','MF_SOLID':'mfSolid','MF_SHOOTABLE':'mfShootable',
 'MF_NOSECTOR':'mfNoSector','MF_NOBLOCKMAP':'mfNoBlockmap','MF_AMBUSH':'mfAmbush',
 'MF_JUSTHIT':'mfJustHit','MF_JUSTATTACKED':'mfJustAttacked','MF_SPAWNCEILING':'mfSpawnCeiling',
 'MF_NOGRAVITY':'mfNoGravity','MF_DROPOFF':'mfDropOff','MF_PICKUP':'mfPickup',
 'MF_NOCLIP':'mfNoClip','MF_SLIDE':'mfSlide','MF_FLOAT':'mfFloat','MF_TELEPORT':'mfTeleport',
 'MF_MISSILE':'mfMissile','MF_DROPPED':'mfDropped','MF_SHADOW':'mfShadow','MF_NOBLOOD':'mfNoBlood',
 'MF_CORPSE':'mfCorpse','MF_INFLOAT':'mfInFloat','MF_COUNTKILL':'mfCountKill',
 'MF_COUNTITEM':'mfCountItem','MF_SKULLFLY':'mfSkullFly','MF_NOTDMATCH':'mfNotDeathmatch',
 'MF_TRANSLATION':'mfTranslation','MF_TRANSSHIFT':'mfTransShift',
}
def flags_dart(expr):
    expr = expr.strip()
    if expr == '0':
        return '0'
    parts = [p.strip() for p in expr.split('|')]
    out = []
    for p in parts:
        if p in FLAG_MAP:
            out.append(FLAG_MAP[p])
        else:
            out.append(p)  # numeric
    return ' | '.join(out)

# ============ EMIT info.dart ============
def gen_info_dart():
    L = []
    L.append('// GENERATED from reference/chocolate-doom/src/doom/info.{c,h} by')
    L.append('// tool/gen_info.py. DO NOT EDIT BY HAND. State/sprite/mobjtype enums and')
    L.append('// the State / MobjInfo struct definitions, faithful to vanilla.')
    L.append('//')
    L.append('// Frame encoding (vanilla): low bits are the sprite subframe; FF_FULLBRIGHT')
    L.append('// (0x8000) is OR\'d in for full-bright frames (kept in [State.frame] as info.c).')
    L.append('')
    L.append('/// FF_FULLBRIGHT bit on a state frame (info.h). Bit 15.')
    L.append('const int ffFullBright = 0x8000;')
    L.append('')
    L.append('/// Mask to recover the base subframe from a state frame (info.h FF_FRAMEMASK).')
    L.append('const int ffFrameMask = 0x7fff;')
    L.append('')
    L.append('/// Sprite numbers, vanilla `spritenum_t` (info.h). Order matches sprnames[].')
    L.append('enum SpriteNum {')
    # 8 per line
    ids = [n.lower() for n in spr_names]
    for i in range(0, len(ids), 10):
        L.append('  ' + ', '.join(ids[i:i+10]) + ',')
    L.append('}')
    L.append('')
    L.append('/// The 4-letter sprite name table, vanilla `sprnames[]` (info.c).')
    L.append('const List<String> spriteNames = <String>[')
    for i in range(0, len(sprstrs), 10):
        L.append('  ' + ', '.join(f"'{s}'" for s in sprstrs[i:i+10]) + ',')
    L.append('];')
    L.append('')
    L.append('''/// A single animation state, vanilla `state_t` (info.h). [action] is the name
/// of the A_* function to invoke on entry (null = no action). [nextState] is
/// an index into [states] (use [StateNum.sNull] = 0 = "remove me").
class State {
  const State(
    this.sprite,
    this.frame,
    this.tics,
    this.action,
    this.nextState, {
    this.misc1 = 0,
    this.misc2 = 0,
  });

  final SpriteNum sprite;
  final int frame;
  final int tics;
  final String? action;
  final int nextState;
  final int misc1;
  final int misc2;
}

/// Static info for one kind of thing, vanilla `mobjinfo_t` (info.h). State
/// fields are indices into [states]; radius/height are fixed_t; monster speed
/// is integer, missile speed is fixed_t — verbatim as in info.c.
class MobjInfo {
  const MobjInfo({
    required this.doomedNum,
    required this.spawnState,
    required this.spawnHealth,
    required this.seeState,
    required this.seeSound,
    required this.reactionTime,
    required this.attackSound,
    required this.painState,
    required this.painChance,
    required this.painSound,
    required this.meleeState,
    required this.missileState,
    required this.deathState,
    required this.xdeathState,
    required this.deathSound,
    required this.speed,
    required this.radius,
    required this.height,
    required this.mass,
    required this.damage,
    required this.activeSound,
    required this.flags,
    required this.raiseState,
  });

  final int doomedNum;
  final int spawnState;
  final int spawnHealth;
  final int seeState;
  final int seeSound;
  final int reactionTime;
  final int attackSound;
  final int painState;
  final int painChance;
  final int painSound;
  final int meleeState;
  final int missileState;
  final int deathState;
  final int xdeathState;
  final int deathSound;
  final int speed;
  final int radius;
  final int height;
  final int mass;
  final int damage;
  final int activeSound;
  final int flags;
  final int raiseState;
}''')
    return '\n'.join(L) + '\n'

# ============ EMIT sounds.dart ============
def gen_sounds_dart():
    L = []
    L.append('// GENERATED from reference/chocolate-doom/src/doom/sounds.h by')
    L.append('// tool/gen_info.py. sfxenum_t ordinals used by mobjinfo[] sound columns')
    L.append('// and combat S_StartSound call sites. DO NOT EDIT BY HAND.')
    L.append('')
    L.append('/// Sound effect ids, vanilla `sfxenum_t` (sounds.h). Index = ordinal.')
    L.append('abstract final class Sfx {')
    for i, n in enumerate(sfx_order):
        ident = n[len('sfx_'):]
        # lowerCamelCase: first char lower (sfx_None -> none, sfx_pistol -> pistol)
        ident = ident[0].lower() + ident[1:]
        L.append(f'  static const int {ident} = {i};')
    L.append('}')
    return '\n'.join(L) + '\n'

# ============ EMIT state_num.dart ============
def gen_state_num_dart():
    L = []
    L.append('// GENERATED from reference/chocolate-doom/src/doom/info.h by')
    L.append('// tool/gen_info.py. Named statenum_t ordinals (St.*) referenced by code.')
    L.append('// The full states[] table (info_tables.dart) is indexed by these ints.')
    L.append('// DO NOT EDIT BY HAND.')
    L.append('')
    L.append('/// Named state indices, vanilla `statenum_t` (info.h). Value = ordinal.')
    L.append('abstract final class St {')
    def cam(n):
        # S_PLAY_RUN1 -> sPlayRun1
        parts = n[2:].split('_')
        return 's' + ''.join(p.capitalize() if not p.isdigit() else p for p in parts)
    used = {}
    for i, n in enumerate(state_names):
        ident = cam(n)
        if ident in used:
            ident = ident + '_' + str(i)
        used[ident] = True
        L.append(f'  static const int {ident} = {i};')
    L.append('}')
    return '\n'.join(L) + '\n'

# ============ EMIT info_tables.dart ============
def gen_info_tables_dart():
    L = []
    L.append('// GENERATED from reference/chocolate-doom/src/doom/info.c + d_items.c by')
    L.append('// tool/gen_info.py. The full vanilla states[] / mobjinfo[] / weaponinfo[]')
    L.append('// tables, plus the Mt.* mobjtype ordinals and the DoomEd->type map.')
    L.append('// DO NOT EDIT BY HAND.')
    L.append('//')
    L.append('// Every A_* action is referenced BY NAME; ActionRegistry resolves names to')
    L.append('// implementations (or log-once no-op stubs). See actions.dart / combat_actions.dart.')
    L.append('')
    L.append("import 'info.dart';")
    L.append("import 'mobj_flags.dart';")
    L.append('')
    L.append('const int _fb = ffFullBright;')
    L.append('')
    # mobjtype ordinals
    L.append('/// mobjtype ordinals, vanilla `mobjtype_t` (info.h). Value = index into [mobjInfo].')
    L.append('abstract final class Mt {')
    def mtcam(n):
        # MT_POSSESSED -> possessed ; MT_MISC0 -> misc0
        return n[3:].lower()
    used={}
    for i,n in enumerate(mt_names):
        ident = mtcam(n)
        if ident in used: ident=ident+'_'+str(i)
        used[ident]=True
        L.append(f'  static const int {ident} = {i};')
    L.append('}')
    L.append('')
    # weapontype / ammotype helpers
    L.append('/// Ammo types, vanilla `ammotype_t` (doomdef.h).')
    L.append('abstract final class Am {')
    L.append('  static const int clip = 0;')
    L.append('  static const int shell = 1;')
    L.append('  static const int cell = 2;')
    L.append('  static const int misl = 3;')
    L.append('  static const int numAmmo = 4;')
    L.append('  static const int noAmmo = 5;')
    L.append('}')
    L.append('')
    L.append('/// Weapon slots, vanilla `weapontype_t` (doomdef.h).')
    L.append('abstract final class Wp {')
    for i,n in enumerate(['fist','pistol','shotgun','chaingun','missile','plasma','bfg','chainsaw','supershotgun']):
        L.append(f'  static const int {n} = {i};')
    L.append('  static const int numWeapons = 9;')
    L.append('  static const int noChange = 10;')
    L.append('}')
    L.append('')
    # weaponinfo
    L.append('/// One weapon\'s psprite states + ammo, vanilla `weaponinfo_t` (d_items.h).')
    L.append('class WeaponInfo {')
    L.append('  const WeaponInfo(this.ammo, this.upState, this.downState,')
    L.append('      this.readyState, this.atkState, this.flashState);')
    L.append('  final int ammo;')
    L.append('  final int upState;')
    L.append('  final int downState;')
    L.append('  final int readyState;')
    L.append('  final int atkState;')
    L.append('  final int flashState;')
    L.append('}')
    L.append('')
    L.append('/// weaponinfo[], vanilla d_items.c. Indexed by [Wp].')
    L.append('const List<WeaponInfo> weaponInfo = <WeaponInfo>[')
    wnames=['fist','pistol','shotgun','chaingun','missile launcher','plasma rifle','bfg 9000','chainsaw','super shotgun']
    for i,row in enumerate(weap_rows):
        ammo, up, dn, rdy, atk, fl = row
        L.append(f'  WeaponInfo(Am.{ {"am_clip":"clip","am_shell":"shell","am_cell":"cell","am_misl":"misl","am_noammo":"noAmmo"}[ammo] }, '
                 f'{state_ord(up)}, {state_ord(dn)}, {state_ord(rdy)}, {state_ord(atk)}, {state_ord(fl)}), // {wnames[i]}')
    L.append('];')
    L.append('')
    # states[]
    L.append('/// states[], vanilla info.c. Indexed by statenum_t ordinal (St.*).')
    L.append('const List<State> states = <State>[')
    for i,(spr,frame,tics,action,nxt,m1,m2) in enumerate(state_rows):
        act = 'null' if action=='NULL' else f"'{action}'"
        extra = ''
        if m1 or m2:
            extra = f', misc1: {m1}, misc2: {m2}'
        L.append(f'  State({spr_dart(spr)}, {frame_dart(frame)}, {tics}, {act}, {state_ord(nxt)}{extra}), // {i} {state_names[i]}')
    L.append('];')
    L.append('')
    # mobjinfo[]
    L.append('/// mobjinfo[], vanilla info.c. Indexed by mobjtype_t ordinal (Mt.*).')
    L.append('const List<MobjInfo> mobjInfo = <MobjInfo>[')
    fixed_fields = {'radius','height'}
    sound_fields = {'seesound','attacksound','painsound','deathsound','activesound'}
    state_fields = {'spawnstate','seestate','painstate','meleestate','missilestate','deathstate','xdeathstate','raisestate'}
    dart_fname = {'doomednum':'doomedNum','spawnstate':'spawnState','spawnhealth':'spawnHealth',
                  'seestate':'seeState','seesound':'seeSound','reactiontime':'reactionTime',
                  'attacksound':'attackSound','painstate':'painState','painchance':'painChance',
                  'painsound':'painSound','meleestate':'meleeState','missilestate':'missileState',
                  'deathstate':'deathState','xdeathstate':'xdeathState','deathsound':'deathSound',
                  'speed':'speed','radius':'radius','height':'height','mass':'mass','damage':'damage',
                  'activesound':'activeSound','flags':'flags','raisestate':'raiseState'}
    for idx,row in enumerate(mobj_rows):
        L.append(f'  MobjInfo( // {idx} {mt_names[idx]}')
        for fi,fname in enumerate(field_order):
            val = row[fi]
            if fname in sound_fields:
                dv = sfx_dart(val) if val.startswith('sfx_') else val
            elif fname in state_fields:
                dv = str(state_ord(val)) if val.startswith('S_') else val
            elif fname in fixed_fields:
                dv = fixed_dart(val)
            elif fname == 'flags':
                dv = flags_dart(val)
            elif fname == 'speed':
                dv = fixed_dart(val)  # missiles use *FRACUNIT
            else:
                dv = val
            L.append(f'    {dart_fname[fname]}: {dv},')
        L.append('  ),')
    L.append('];')
    L.append('')
    # doomed map
    L.append('/// DoomEd-number -> mobjtype index, built once from [mobjInfo].')
    L.append('final Map<int, int> doomedToMobjType = _buildDoomedMap();')
    L.append('')
    L.append('Map<int, int> _buildDoomedMap() {')
    L.append('  final Map<int, int> m = <int, int>{};')
    L.append('  for (int i = 0; i < mobjInfo.length; i++) {')
    L.append('    final int d = mobjInfo[i].doomedNum;')
    L.append('    if (d > 0) m.putIfAbsent(d, () => i);')
    L.append('  }')
    L.append('  return m;')
    L.append('}')
    L.append('')
    # action names list (for ActionRegistry registration)
    L.append('/// Every A_* action name referenced by states[] (for ActionRegistry no-op')
    L.append('/// registration so the tables compile before real implementations land).')
    L.append('const List<String> allActionNames = <String>[')
    for a in action_names:
        L.append(f"  '{a}',")
    L.append('];')
    return '\n'.join(L) + '\n'

OUT = os.path.join(ROOT, 'lib', 'game', 'play')
def w(fn, content):
    p = os.path.join(OUT, fn)
    with open(p, 'w') as f:
        f.write(content)
    print('wrote', p, len(content), 'bytes')

w('info.dart', gen_info_dart())
w('sounds.dart', gen_sounds_dart())
w('state_num.dart', gen_state_num_dart())
w('info_tables.dart', gen_info_tables_dart())

print('sprites:', len(spr_names), 'states:', len(state_names), 'mobjtypes:', len(mt_names),
      'sfx:', len(sfx_order), 'weapons:', len(weap_rows), 'actions:', len(action_names))
print('actions:', ', '.join(action_names))
