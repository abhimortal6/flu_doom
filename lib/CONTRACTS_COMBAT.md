# flu_doom — Combat Contracts (Phase 3 / combat wave)

This document is the **frozen contract** for the COMBAT wave: a faithful 1:1
pure-Dart port of vanilla Doom's damage, hitscan/missile attacks, enemy AI,
weapon psprites and pickups, from Chocolate Doom
`src/doom/p_inter.c`, `p_pspr.c`, `p_enemy.c`, `p_map.c` (attack portion),
`p_maputl.c` (`P_PathTraverse`), `p_sight.c`, plus `info.c`/`d_items.c` data.

It builds strictly on the existing play-sim (`lib/CONTRACTS_PLAY.md`), the
renderer (`lib/CONTRACTS_RENDER.md` SpriteSource) and game-state
(`lib/CONTRACTS_STATE.md` PlayerStatus). **Faithfulness is mandatory: never
paraphrase vanilla; port.** All gameplay randomness goes through the
single shared `p_random.dart` (see §8).

This is the GATE deliverable. The data tables (§0) are DONE and compile; the
interfaces below (§1–§9) are FROZEN; the parallel fan-out partition is §10.

---

## 0. Data tables — DONE (this gate)

The full vanilla `info.c` / `d_items.c` data is now transcribed 1:1, generated
by `tool/gen_info.py` straight from `reference/.../info.{c,h}`, `sounds.h`,
`d_items.{c,h}`, `doomdef.h`:

| file | contents |
|------|----------|
| `lib/game/play/info.dart` | `SpriteNum` (138 entries, vanilla `spritenum_t` order incl. POL/GOR), `spriteNames[]`, `State` (`state_t`), `MobjInfo` (`mobjinfo_t`), `ffFullBright`/`ffFrameMask`. |
| `lib/game/play/state_num.dart` | `St.*` — all 967 `statenum_t` ordinals (e.g. `St.sPunch`, `St.sBfg1`, `St.sTrooAtk1`). |
| `lib/game/play/info_tables.dart` | `states[]` (967 rows, full enemy/weapon/missile/item/effect chains), `mobjInfo[]` (137 rows, `Mt.*`), `weaponInfo[]` (9 rows, `Wp.*`/`Am.*`), `doomedToMobjType`, `allActionNames` (74 distinct `A_*`). |
| `lib/game/play/sounds.dart` | `Sfx.*` — all 109 `sfxenum_t` ordinals (used by `mobjInfo` sound columns + `S_StartSound` call sites). |
| `lib/game/play/p_random.dart` | THE shared vanilla `rndtable[256]` + `pRandom`/`pSubRandom`/`mRandom`/`clearRandom` (see §8). |

`MobjInfo` sound columns hold raw `sfxenum_t` ordinals (= `Sfx.*` values).
State/missile/death columns hold `statenum_t` ordinals (= `St.*`). Flags use the
existing `mfXxx` constants in `mobj_flags.dart`. `radius`/`height` are `n << 16`
fixed_t; monster `speed` is integer, missile `speed` is fixed_t — verbatim.

**Every `A_*` name in `states[]` is registered as a log-once no-op stub** via
`ActionRegistry.instance.registerAllStubs()` (called in the `PlaySim`
constructor). The project compiles and runs the full state machine today; the
fan-out agents REPLACE stubs with real bodies via `ActionRegistry.register(...)`
(`putIfAbsent` semantics — registering a real action never clobbers another).

> **Faithfulness note / interface decision:** the previous hand-written slice
> set `states[S_PLAY].nextstate = S_PLAY`. Vanilla info.c sets it to `S_NULL`
> (the state has `tics == -1`, so it never advances). The generated table is
> faithful (`nextState == 0`); `test/play/playsim_test.dart` was corrected to
> assert the vanilla value.

---

## 1. Damage — `p_inter.c`

```dart
// lib/game/play/p_inter.dart  (owner: COMBAT-C)
class Interactions {
  Interactions(this.mobjSim, this.sound);   // MobjSim + SoundHook (§7)
  final MobjSim mobjSim;
  final SoundHook sound;

  /// P_DamageMobj. inflictor = the missile/puff doing damage (null for slime/
  /// telefrag); source = the mobj responsible for it (the shooter; gets the
  /// kill credit / becomes the target's new target). Faithful order:
  /// SKULLFLY clear, sk_baby halving, thrust (skip chainsaw source / NOCLIP /
  /// MISSILE-on-self), player armor absorb + damagecount, health subtract,
  /// P_KillMobj on <=0, painchance roll via pRandom() -> painState, JUSTHIT,
  /// retaliation target acquisition + reactiontime reset.
  void damageMobj(Mobj target, Mobj? inflictor, Mobj? source, int damage);

  /// P_KillMobj. Clears SHOOTABLE/FLOAT/SKULLFLY, sets CORPSE|DROPOFF, halves
  /// height, drops dropped-item for MT_POSSESSED/SHOTGUY/WOLFSS, counts the
  /// kill (killCount), picks deathState vs xdeathState (health < -spawnhealth
  /// => xdeath), and (if it has a deathState chain) sets a random extra tics
  /// offset. Sound via deathSound.
  void killMobj(Mobj? source, Mobj target);
}
```

**Pain/death transition rules (frozen, from `p_inter.c`):**
- `damage <= 0` only matters through the thrust path; health subtract always.
- Player damage: `sk_baby` halves; god/invuln returns early for `damage<1000`;
  armortype 1 absorbs `damage/3`, type 2 `damage/2`, capped at `armorpoints`;
  `damageCount += damage` (cap 100); mirror into `player.health` (floor 0).
- After `target.health -= damage`: if `<= 0` -> `killMobj`, return.
- Pain: `if (pRandom() < info.painChance && !(flags & MF_SKULLFLY))` set
  `MF_JUSTHIT` and `setMobjState(target, info.painState)`.
- Retaliation: `reactionTime = 0`; if `threshold == 0 && source != null &&
  source != target && source.type != MT_VILE` -> `target.target = source`,
  `threshold = BASETHRESHOLD (100)`, and if in spawn/idle state enter seeState.

`P_KillMobj` xdeath gib threshold uses `target.health < -info.spawnHealth`.

---

## 2. Hitscan / aim / missiles — `p_map.c` + `p_maputl.c` + `p_mobj.c`

### Intercept / divline types (new, in `p_maputl.dart` extension or `p_shoot.dart`)
```dart
class DivLine {                       // divline_t
  fixed_t x = 0, y = 0, dx = 0, dy = 0;
}
class Intercept {                     // intercept_t
  fixed_t frac = 0;                   // along the trace line (0..FRACUNIT)
  bool isALine = false;
  Mobj? thing;                        // d.thing  (isALine == false)
  Line? line;                         // d.line   (isALine == true)
}
```

### Path traversal — `P_PathTraverse` (`p_maputl.c`)
```dart
// owner: COMBAT-C (p_shoot.dart). traverser returns false to stop early.
typedef Traverser = bool Function(Intercept it);

/// P_PathTraverse: walk the blockmap cells the segment (x1,y1)->(x2,y2)
/// crosses, collecting line intercepts (PT_ADDLINES) and/or thing intercepts
/// (PT_ADDTHINGS), then call [trav] on each in increasing frac order. Sets the
/// shared `trace` divline. Returns true if it ran to the end (not stopped).
bool pathTraverse(fixed_t x1, fixed_t y1, fixed_t x2, fixed_t y2,
    int flags, Traverser trav);

const int ptAddLines  = 1;
const int ptAddThings = 2;
const int ptEarlyOut  = 4;
```
Helpers (port faithfully): `P_PointOnDivlineSide`, `P_MakeDivline`,
`P_InterceptVector`, `PIT_AddLineIntercepts`, `PIT_AddThingIntercepts`,
`P_TraverseIntercepts`. The `trace` divline + intercept buffer are instance
fields on the owner (no C statics).

### Aiming / line attack — `P_AimLineAttack` / `P_LineAttack` (`p_map.c`)
```dart
/// P_AimLineAttack: aim from t1 along angle for distance; sets linetarget
/// (out) and returns the vertical aim slope. Uses PTR_AimTraverse + the
/// top/bottom slope clamp; auto-aims to the first shootable thing in LOS.
fixed_t aimLineAttack(Mobj t1, angle_t angle, fixed_t distance);

/// P_LineAttack: fire a hitscan from t1 along angle for distance at the given
/// slope, dealing damage. PTR_ShootTraverse spawns a puff (P_SpawnPuff) on a
/// wall/no-bleed target and blood (P_SpawnBlood) + P_DamageMobj on a shootable
/// thing. linetarget is set as a side effect.
void lineAttack(Mobj t1, angle_t angle, fixed_t distance, fixed_t slope,
    int damage);

Mobj? linetarget;                     // extern mobj_t* linetarget
fixed_t attackRange = 0;              // extern fixed_t attackrange
fixed_t aimSlope = 0;                 // shotz/bulletslope helper
```
`MELEERANGE = 64<<16`, `MISSILERANGE = 32*64<<16` (define in `p_inter.dart` or
a shared consts file). `P_SpawnPuff` (Mt.puff) / `P_SpawnBlood` (Mt.blood) live
with the shooter code (COMBAT-C) and use `pRandom`/`pSubRandom` for tics/scatter
exactly as vanilla.

### Missiles — `p_mobj.c`
```dart
// owner: COMBAT-C (these extend p_mobj.dart's MobjSim or live in p_shoot.dart;
// to avoid two writers of p_mobj.dart, place them in p_shoot.dart and call
// mobjSim.spawnMobj/setMobjState — see §10 hazard note).
Mobj spawnMissile(Mobj source, Mobj dest, int type);     // P_SpawnMissile
void spawnPlayerMissile(Mobj source, int type);          // P_SpawnPlayerMissile
void explodeMissile(Mobj mo);                            // P_ExplodeMissile
void radiusAttack(Mobj spot, Mobj? source, int damage);  // P_RadiusAttack
```
`P_ExplodeMissile`: zero momentum, `setMobjState(mo, info.deathState)`, random
tic shave (`mo.tics -= pRandom()&3`, min 1), clear MF_MISSILE, deathSound.
`P_RadiusAttack` uses `PIT_RadiusAttack` over the blockmap (`P_DamageMobj` with
falloff). `P_SpawnMissile` aim/Z math and the `+= (P_Random()-P_Random())`
trooper-style spread (where applicable) must match vanilla exactly.

---

## 3. Enemy AI — `p_enemy.c` + `p_sight.c`

```dart
// lib/game/play/p_enemy.dart  (owner: COMBAT-A)
class EnemyAi {
  EnemyAi(this.mobjSim, this.move, this.sight, this.shoot, this.sound);
  // read-only deps: MobjSim, MapMove, Sight, the shooter facade, SoundHook.

  bool checkMeleeRange(Mobj actor);          // P_CheckMeleeRange
  bool checkMissileRange(Mobj actor);        // P_CheckMissileRange (pRandom)
  bool move(Mobj actor);                     // P_Move (try the moveDir step)
  bool tryWalk(Mobj actor);                  // P_TryWalk
  void newChaseDir(Mobj actor);              // P_NewChaseDir (DI_* table)
  bool lookForPlayers(Mobj actor, bool allAround); // P_LookForPlayers
  void noiseAlert(Mobj target, Mobj emitter);      // P_NoiseAlert (recursive
                                                   // sound flood; sets
                                                   // sector.soundTarget)
}
```
`P_NoiseAlert` writes `Sector.soundTarget` (the world layer left this `Object?`
for play-sim, per CONTRACTS_PLAY §1) and floods through two-sided lines with
`soundtraversed`/`validcount` — port faithfully.

### Sight — `p_sight.c`
```dart
// lib/game/play/p_sight.dart  (owner: COMBAT-A)
class Sight {
  Sight(this.level);
  bool checkSight(Mobj t1, Mobj t2);   // P_CheckSight
}
```
`P_CheckSight`: REJECT-matrix fast reject first (the world layer must expose the
`reject` lump bytes + sector indices — if absent, COMBAT-A skips the reject
early-out and goes straight to the BSP cross, a documented allowed degradation),
then `P_CrossBSPNode`/`P_CrossSubsector` LOS via the `sightcounts`/`strace`
divline. `validcount` is an instance field.

### Enemy `A_*` functions COMBAT-A registers (all from `p_enemy.c`):
`A_Look`, `A_Chase`, `A_FaceTarget`, `A_Pain`, `A_Scream`, `A_XScream`,
`A_Fall`, `A_Explode`, `A_BossDeath`, `A_PlayerScream`,
`A_PosAttack`, `A_SPosAttack`, `A_CPosAttack`, `A_CPosRefire`,
`A_SpidRefire`, `A_BspiAttack`, `A_TroopAttack`, `A_SargAttack`,
`A_HeadAttack`, `A_CyberAttack`, `A_BruisAttack`, `A_SkullAttack`,
`A_SkelMissile`, `A_SkelWhoosh`, `A_SkelFist`, `A_Tracer`,
`A_VileChase`, `A_VileStart`, `A_VileTarget`, `A_VileAttack`,
`A_StartFire`, `A_Fire`, `A_FireCrackle`,
`A_FatRaise`, `A_FatAttack1`, `A_FatAttack2`, `A_FatAttack3`,
`A_PainAttack`, `A_PainDie`, `A_KeenDie`,
`A_BrainAwake`, `A_BrainPain`, `A_BrainScream`, `A_BrainExplode`,
`A_BrainDie`, `A_BrainSpit`, `A_SpawnSound`, `A_SpawnFly`,
`A_Hoof`, `A_Metal`, `A_BabyMetal`.  (51 names.)

---

## 4. Weapons / psprites — `p_pspr.c` + `d_items.c`

```dart
// lib/game/play/p_pspr.dart  (owner: COMBAT-B)
class Pspr {
  Pspr(this.mobjSim, this.shoot, this.sound);  // read-only deps + shooter facade

  void setupPsprites(Player p);                // P_SetupPsprites (level start)
  void movePsprites(Player p);                 // P_MovePsprites (per tic)
  void setPsprite(Player p, int position, int stateNum);  // P_SetPsprite
  void bringUpWeapon(Player p);                // P_BringUpWeapon
  bool checkAmmo(Player p);                    // P_CheckAmmo
  void fireWeapon(Player p);                   // P_FireWeapon
  void dropWeapon(Player p);                   // P_DropWeapon
  void calcSwing(Player p);                    // P_CalcSwing
}
```
`pspdef_t` is the existing `Pspdef` (`stateIndex`/`tics`/`sx`/`sy`) in
`player.dart`. `P_SetPsprite` loops zero-tic states firing the action with
`(player, psp)`; the existing `ActionRegistry` `MobjAction` signature
`void Function(Mobj, {Player?, Pspdef?})` already carries both — weapon actions
read `player`/`psp`, ignore `mobj` (pass `player.mo!`).

Constants (port verbatim): `LOWERSPEED = 6<<16`, `RAISESPEED = 6<<16`,
`WEAPONBOTTOM = 128<<16`, `WEAPONTOP = 32<<16`.

**Ammo per shot:** `P_FireWeapon`/`A_FireXxx` subtract from
`player.ammo[weaponInfo[readyWeapon].ammo]`; `P_CheckAmmo` switches down when
empty (BFG/plasma need 40/1 cells; SSG needs 2 shells — vanilla branches in
`P_CheckAmmo`). `P_FireWeapon` calls `pspr` muzzle + `P_SetMobjState(mo,
S_PLAY_ATK1)`.

### Weapon `A_*` functions COMBAT-B registers (all from `p_pspr.c`):
`A_WeaponReady`, `A_ReFire`, `A_Lower`, `A_Raise`, `A_GunFlash`,
`A_Light0`, `A_Light1`, `A_Light2`,
`A_Punch`, `A_Saw`, `A_FirePistol`, `A_FireShotgun`, `A_FireShotgun2`,
`A_CheckReload`, `A_OpenShotgun2`, `A_LoadShotgun2`, `A_CloseShotgun2`,
`A_FireCGun`, `A_FireMissile`, `A_FirePlasma`,
`A_BFGsound`, `A_FireBFG`, `A_BFGSpray`.  (23 names.)

> `A_Explode` and `A_BFGSpray` straddle weapon/enemy code. **Assignment:**
> `A_BFGSpray` -> COMBAT-B (it's the BFG weapon effect); `A_Explode` ->
> COMBAT-A (it's a generic mobj/missile/barrel death action). Both call into
> COMBAT-C's `lineAttack`/`radiusAttack` facade (read-only dep). This split is
> the only action that crosses files; it is disjoint by name (no shared write).

---

## 5. Pickups / inventory — `p_inter.c`

```dart
// in p_inter.dart (owner: COMBAT-C)
void touchSpecialThing(Mobj special, Mobj toucher);  // P_TouchSpecialThing
bool giveBody(Player p, int num);                    // P_GiveBody (health)
bool giveArmor(Player p, int armortype);             // P_GiveArmor
bool giveAmmo(Player p, int ammo, int num);          // P_GiveAmmo
bool giveWeapon(Player p, int weapon, bool dropped); // P_GiveWeapon
bool giveCard(Player p, int card);                   // P_GiveCard (void in C;
                                                     //   return bool ok)
bool givePower(Player p, int power);                 // P_GivePower
```
`P_TouchSpecialThing` switches on `special.sprite` (the big vanilla switch),
gives the item, sets `player.bonusCount = BONUSADD (6)`, plays `Sfx.itemup`
(weapons `Sfx.wpnup`), counts items (`MF_COUNTITEM` -> `itemCount`), and removes
the pickup unless it is the in-place weapon-in-coop case. Constants:
`maxammo[] = {200,50,300,50}`, `clipammo[] = {10,4,20,1}`, `MAXHEALTH = 100`,
green armor class 1 / 100 pts, blue class 2 / 200 pts, soulsphere +100 (cap
200), megasphere 200/200.

### Player inventory fields — EXTEND `lib/game/play/player.dart` (owner: COMBAT-C)
Add the faithful `player_t` inventory fields (currently missing):
```dart
final List<int>  ammo        = List<int>.filled(Am.numAmmo, 0); // ammo[NUMAMMO]
final List<int>  maxAmmo     = <int>[200, 50, 300, 50];         // maxammo[NUMAMMO]
final List<int>  weaponOwned = List<int>.filled(Wp.numWeapons, 0);
final List<int>  powers      = List<int>.filled(6, 0);          // powers[NUMPOWERS]
final List<bool> cards       = List<bool>.filled(6, false);     // cards[NUMCARDS]
bool  backpack = false;
int   readyWeapon   = Wp.pistol;     // weapontype_t
int   pendingWeapon = Wp.noChange;   // wp_nochange == 10
int   extraLight = 0;                // muzzle-flash extralight (renderer reads)
final List<int> frags = <int>[0];    // single-player
```
Initial loadout (`G_PlayerReborn`, owner: COMBAT-C in spawn wiring):
`readyWeapon = pendingWeapon = wp_pistol`, `weaponOwned[fist]=weaponOwned[pistol]=1`,
`ammo[am_clip]=50`, `maxAmmo = {200,50,300,50}`, `health=100`.

### PlayerStatus HUD adapter — MUST be rewired to live fields (owner: COMBAT-D)
`lib/game/integration/player_status_adapter.dart` currently SYNTHESIZES a fixed
starting loadout (hard-coded fist+pistol+50 bullets, no keys, no powers). Once
the §5 fields exist it MUST read them live, so the HUD shows real inventory:
```dart
int     get readyWeapon       => player.readyWeapon;
bool    ownsWeapon(int slot)  => player.weaponOwned[slot] != 0;
int     ammo(AmmoType t)      => player.ammo[t.index];
int     maxAmmo(AmmoType t)   => player.maxAmmo[t.index];
AmmoType? get readyWeaponAmmo { final a = weaponInfo[player.readyWeapon].ammo;
                                return a == Am.noAmmo ? null : AmmoType.values[a]; }
bool    ownsCard(int index)   => player.cards[index];
int     powerTics(PowerType p)=> player.powers[_powerMap[p.index]];
```
`PowerType {invulnerability, strength, infrared}` maps to `pw_invulnerability(0)`,
`pw_strength(1)`, `pw_infrared(5)` (the HUD only surfaces those three).
This is assigned as integration step COMBAT-D (§10).

---

## 6. Renderer — NO CHANGE REQUIRED (frozen)

Combat only **spawns more Mobjs** (puffs, blood, missiles, dropped items,
corpses, gibs) and advances existing ones through `states[]`. They flow to the
screen through the EXISTING `PlaySpriteSource`/`MobjSprite` ->
`PlaySpriteAdapter` -> renderer `SpriteSource` path unchanged. The full
`SpriteNum`/`spriteNames` table already covers every combat sprite (BAL1, MISL,
PLSS, BFS1, blood, puff, all corpses).

**Fan-out agents MUST NOT touch `lib/engine/render/*` or
`lib/game/integration/sprite_adapter.dart`.** The one renderer-adjacent value
combat produces is `player.extraLight` (weapon muzzle flash); the renderer
already supports `extralight` (CONTRACTS_RENDER §4) — wiring it is a future
integration nicety, NOT part of this wave, and needs no renderer change.

---

## 7. SoundHook — injectable, no-op now (audio is a LATER wave)

Audio is not implemented this wave, but **every combat call site that vanilla
sounds at MUST call the hook** so wiring real audio later is a one-line swap.

```dart
// lib/game/play/sound_hook.dart  (owner: COMBAT-C creates; all agents call)
abstract interface class SoundHook {
  /// S_StartSound(origin, sfx). origin is the Mobj (or null for ui/global);
  /// kept as Object? so play-sim need not depend on an audio type.
  void startSound(Object? origin, int sfxId);
}

class NullSoundHook implements SoundHook {
  const NullSoundHook();
  @override
  void startSound(Object? origin, int sfxId) {}   // no-op
}
```
`PlaySim` constructs `const NullSoundHook()` and injects it into
`Interactions`/`EnemyAi`/`Pspr` (integration step COMBAT-D wires it). Sound ids
are `Sfx.*` from `sounds.dart`. Call sites: weapon fire, pain, death, sight,
active, pickup (`Sfx.itemup`/`wpnup`), barrel/missile explosion (`Sfx.barexp`),
telefog, etc. — exactly where vanilla calls `S_StartSound`.

---

## 8. P_Random — the ONE rng for ALL combat (frozen)

`lib/game/play/p_random.dart` holds THE vanilla `rndtable[256]` and the single
shared `prndindex`. **All gameplay randomness MUST use `pRandom()` /
`pSubRandom()`** (damage thrust/fall, pain chance, hitscan spread, missile
scatter/tics, AI `P_NewChaseDir`/`P_CheckMissileRange`/`A_Look` lastlook,
blood/puff counts, dropped-item, gib threshold, `A_BFGSpray`, etc.).

- **FORBIDDEN in gameplay:** `dart:math` `Random`, any LCG, any other table, or
  a second `prndindex`. Determinism (and future demo compat) depends on one
  stream.
- `mRandom()` is the **cosmetic** generator (separate `rndindex`) for HUD/menu
  only; it must NOT be called from combat. (Existing `status_bar.dart` keeps its
  own face rng; that is cosmetic and out of scope — combat agents do not touch
  it.)
- `clearRandom()` is called by `PlaySim.spawnLevel()` (already wired).
- `p_lights.dart` currently uses a local LCG for light flashes (cosmetic, not
  gameplay-deterministic in vanilla terms); it is **out of scope** for this
  wave — do not refactor it.

---

## 9. P_SetMobjState reentrancy (frozen)

The combat code drives state changes through the EXISTING
`MobjSim.setMobjState(mobj, stateNum)` (`p_mobj.dart`) — which already fires the
named action and removes the mobj on `S_NULL`. Weapon psprite states go through
COMBAT-B's `Pspr.setPsprite`. Neither COMBAT agent rewrites
`MobjSim.setMobjState`; they only call it. (See §10 hazard for `p_mobj.dart`.)

---

## 10. PARTITION PLAN — disjoint file ownership (the fan-out)

Four agents, no two writing the same file. Shared deps below are **read-only**.

### COMBAT-A — Enemy AI + sight
- **Owns (write):** `lib/game/play/p_enemy.dart` (new),
  `lib/game/play/p_sight.dart` (new).
- **Registers (`A_*`):** the 51 enemy names in §3 **plus `A_Explode`** (generic
  missile/barrel death) = 52.
- **Read-only deps:** `mobj.dart`, `info_tables.dart`, `state_num.dart`,
  `mobj_flags.dart`, `p_mobj.dart` (`MobjSim`), `p_map.dart` (`MapMove`),
  `p_maputl.dart`, `p_random.dart`, `sounds.dart`, `sound_hook.dart`, and
  COMBAT-C's `p_shoot.dart`/`p_inter.dart` facades (`lineAttack`,
  `spawnMissile`, `radiusAttack`, `damageMobj`).
- Reads/writes `Sector.soundTarget` (`Object?`, play-sim owned).

### COMBAT-B — Weapons / psprites
- **Owns (write):** `lib/game/play/p_pspr.dart` (new).
- **Registers (`A_*`):** the 23 weapon names in §4 (incl. `A_BFGSpray`).
- **Read-only deps:** `player.dart` (`Player`/`Pspdef`), `info_tables.dart`
  (`weaponInfo`, `Wp`, `Am`, `St`), `state_num.dart`, `p_mobj.dart`,
  `p_random.dart`, `sounds.dart`, `sound_hook.dart`, COMBAT-C's
  `p_shoot.dart`/`p_inter.dart` facades (`aimLineAttack`, `lineAttack`,
  `spawnPlayerMissile`, `bulletSlope`).

### COMBAT-C — Interactions + shooting + missiles + pickups
- **Owns (write):** `lib/game/play/p_inter.dart` (new),
  `lib/game/play/p_shoot.dart` (new), `lib/game/play/sound_hook.dart` (new),
  **and extends `lib/game/play/player.dart`** with the §5 inventory fields.
- **Provides facades** consumed by A & B: `Interactions` (`damageMobj`,
  `killMobj`, `touchSpecialThing`, `giveX`), `Shoot` (`aimLineAttack`,
  `lineAttack`, `pathTraverse`, `spawnMissile`, `spawnPlayerMissile`,
  `explodeMissile`, `radiusAttack`, `spawnPuff`, `spawnBlood`, `bulletSlope`).
- **Registers (`A_*`):** none required for itself (its functions are called
  directly), EXCEPT it may register nothing — all `A_*` belong to A/B.
- **Read-only deps:** `mobj.dart`, `info_tables.dart`, `state_num.dart`,
  `mobj_flags.dart`, `p_map.dart`, `p_maputl.dart`, `p_mobj.dart`,
  `p_random.dart`, `sounds.dart`.

### COMBAT-D — Integration (single serial step, runs AFTER A/B/C land)
- **Owns (write):** `lib/game/play/playsim.dart` (construct & inject
  `Interactions`/`EnemyAi`/`Pspr`/`Shoot`/`NullSoundHook`; call `setupPsprites`
  in `spawnLevel`; call `movePsprites`/`fireWeapon` from the player-think path;
  call `touchSpecialThing` from the `MapMove.onTouchSpecial` hook),
  `lib/game/play/spawn.dart` (give the reborn loadout via §5),
  `lib/game/play/p_user.dart` (wire BT_ATTACK -> `fireWeapon`, weapon switch),
  `lib/game/integration/player_status_adapter.dart` (read LIVE inventory, §5).
- **Read-only deps:** everything above.

### Shared-write hazards (flagged)
1. **`p_mobj.dart`** (`MobjSim`): A, B, C all CALL `setMobjState`/`spawnMobj`,
   none WRITE the file. Missile spawning lives in COMBAT-C's `p_shoot.dart`
   (calls `mobjSim.spawnMobj`), NOT inside `p_mobj.dart`, specifically to keep
   `p_mobj.dart` single-reader. **Do not add missile code to `p_mobj.dart`.**
2. **`player.dart`**: ONLY COMBAT-C edits it (adds inventory fields). A/B/D read
   the new fields. If B needs a field B does not add it — it is C's deliverable;
   coordinate the field list from §5 up front (it is frozen here, so no
   coordination is needed at runtime).
3. **`p_map.dart` / `p_maputl.dart`**: read-only for all combat agents. The
   intercept/divline/PathTraverse code goes in COMBAT-C's `p_shoot.dart`, NOT
   appended to `p_maputl.dart`, to keep those world-collision files untouched.
4. **`playsim.dart` / `spawn.dart` / `p_user.dart` / `player_status_adapter.dart`**:
   ONLY COMBAT-D edits these, and D runs as a serial step after A/B/C, so there
   is no concurrent write.
5. **Renderer + `sprite_adapter.dart`**: no agent writes them (§6).

---

## 11. Verification status (gate)

- `flutter analyze lib test` -> **No issues found** (full tables + 74 no-op
  `A_*` stubs + `p_random.dart` + `sounds.dart` compile).
- `flutter test` -> **all pass** (95 passed, 2 pre-existing skips). The
  play-sim test now asserts the FULL `states.length == 967` and the faithful
  `states[S_PLAY].nextState == 0`.
- Tables generated by `tool/gen_info.py` directly from
  `reference/chocolate-doom/src/doom/{info.c,info.h,sounds.h,d_items.c,doomdef.h}`
  for guaranteed 1:1 fidelity; `reference/` stays gitignored. Re-run the script
  to regenerate if the reference is updated.
