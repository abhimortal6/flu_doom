// GENERATED 1:1 from reference/chocolate-doom/src/doom/info.c + d_items.c by
// tool/gen_info.py. The full vanilla states[] / mobjinfo[] / weaponinfo[]
// tables, plus the Mt.* mobjtype ordinals and the DoomEd->type map.
// DO NOT EDIT BY HAND.
//
// Every A_* action is referenced BY NAME; ActionRegistry resolves names to
// implementations (or log-once no-op stubs). See actions.dart / combat_actions.dart.

import 'info.dart';
import 'mobj_flags.dart';

const int _fb = ffFullBright;

/// mobjtype ordinals, vanilla `mobjtype_t` (info.h). Value = index into [mobjInfo].
abstract final class Mt {
  static const int player = 0;
  static const int possessed = 1;
  static const int shotguy = 2;
  static const int vile = 3;
  static const int fire = 4;
  static const int undead = 5;
  static const int tracer = 6;
  static const int smoke = 7;
  static const int fatso = 8;
  static const int fatshot = 9;
  static const int chainguy = 10;
  static const int troop = 11;
  static const int sergeant = 12;
  static const int shadows = 13;
  static const int head = 14;
  static const int bruiser = 15;
  static const int bruisershot = 16;
  static const int knight = 17;
  static const int skull = 18;
  static const int spider = 19;
  static const int baby = 20;
  static const int cyborg = 21;
  static const int pain = 22;
  static const int wolfss = 23;
  static const int keen = 24;
  static const int bossbrain = 25;
  static const int bossspit = 26;
  static const int bosstarget = 27;
  static const int spawnshot = 28;
  static const int spawnfire = 29;
  static const int barrel = 30;
  static const int troopshot = 31;
  static const int headshot = 32;
  static const int rocket = 33;
  static const int plasma = 34;
  static const int bfg = 35;
  static const int arachplaz = 36;
  static const int puff = 37;
  static const int blood = 38;
  static const int tfog = 39;
  static const int ifog = 40;
  static const int teleportman = 41;
  static const int extrabfg = 42;
  static const int misc0 = 43;
  static const int misc1 = 44;
  static const int misc2 = 45;
  static const int misc3 = 46;
  static const int misc4 = 47;
  static const int misc5 = 48;
  static const int misc6 = 49;
  static const int misc7 = 50;
  static const int misc8 = 51;
  static const int misc9 = 52;
  static const int misc10 = 53;
  static const int misc11 = 54;
  static const int misc12 = 55;
  static const int inv = 56;
  static const int misc13 = 57;
  static const int ins = 58;
  static const int misc14 = 59;
  static const int misc15 = 60;
  static const int misc16 = 61;
  static const int mega = 62;
  static const int clip = 63;
  static const int misc17 = 64;
  static const int misc18 = 65;
  static const int misc19 = 66;
  static const int misc20 = 67;
  static const int misc21 = 68;
  static const int misc22 = 69;
  static const int misc23 = 70;
  static const int misc24 = 71;
  static const int misc25 = 72;
  static const int chaingun = 73;
  static const int misc26 = 74;
  static const int misc27 = 75;
  static const int misc28 = 76;
  static const int shotgun = 77;
  static const int supershotgun = 78;
  static const int misc29 = 79;
  static const int misc30 = 80;
  static const int misc31 = 81;
  static const int misc32 = 82;
  static const int misc33 = 83;
  static const int misc34 = 84;
  static const int misc35 = 85;
  static const int misc36 = 86;
  static const int misc37 = 87;
  static const int misc38 = 88;
  static const int misc39 = 89;
  static const int misc40 = 90;
  static const int misc41 = 91;
  static const int misc42 = 92;
  static const int misc43 = 93;
  static const int misc44 = 94;
  static const int misc45 = 95;
  static const int misc46 = 96;
  static const int misc47 = 97;
  static const int misc48 = 98;
  static const int misc49 = 99;
  static const int misc50 = 100;
  static const int misc51 = 101;
  static const int misc52 = 102;
  static const int misc53 = 103;
  static const int misc54 = 104;
  static const int misc55 = 105;
  static const int misc56 = 106;
  static const int misc57 = 107;
  static const int misc58 = 108;
  static const int misc59 = 109;
  static const int misc60 = 110;
  static const int misc61 = 111;
  static const int misc62 = 112;
  static const int misc63 = 113;
  static const int misc64 = 114;
  static const int misc65 = 115;
  static const int misc66 = 116;
  static const int misc67 = 117;
  static const int misc68 = 118;
  static const int misc69 = 119;
  static const int misc70 = 120;
  static const int misc71 = 121;
  static const int misc72 = 122;
  static const int misc73 = 123;
  static const int misc74 = 124;
  static const int misc75 = 125;
  static const int misc76 = 126;
  static const int misc77 = 127;
  static const int misc78 = 128;
  static const int misc79 = 129;
  static const int misc80 = 130;
  static const int misc81 = 131;
  static const int misc82 = 132;
  static const int misc83 = 133;
  static const int misc84 = 134;
  static const int misc85 = 135;
  static const int misc86 = 136;
}

/// Ammo types, vanilla `ammotype_t` (doomdef.h).
abstract final class Am {
  static const int clip = 0;
  static const int shell = 1;
  static const int cell = 2;
  static const int misl = 3;
  static const int numAmmo = 4;
  static const int noAmmo = 5;
}

/// Weapon slots, vanilla `weapontype_t` (doomdef.h).
abstract final class Wp {
  static const int fist = 0;
  static const int pistol = 1;
  static const int shotgun = 2;
  static const int chaingun = 3;
  static const int missile = 4;
  static const int plasma = 5;
  static const int bfg = 6;
  static const int chainsaw = 7;
  static const int supershotgun = 8;
  static const int numWeapons = 9;
  static const int noChange = 10;
}

/// One weapon's psprite states + ammo, vanilla `weaponinfo_t` (d_items.h).
class WeaponInfo {
  const WeaponInfo(this.ammo, this.upState, this.downState,
      this.readyState, this.atkState, this.flashState);
  final int ammo;
  final int upState;
  final int downState;
  final int readyState;
  final int atkState;
  final int flashState;
}

/// weaponinfo[], vanilla d_items.c. Indexed by [Wp].
const List<WeaponInfo> weaponInfo = <WeaponInfo>[
  WeaponInfo(Am.noAmmo, 4, 3, 2, 5, 0), // fist
  WeaponInfo(Am.clip, 12, 11, 10, 13, 17), // pistol
  WeaponInfo(Am.shell, 20, 19, 18, 21, 30), // shotgun
  WeaponInfo(Am.clip, 51, 50, 49, 52, 55), // chaingun
  WeaponInfo(Am.misl, 59, 58, 57, 60, 63), // missile launcher
  WeaponInfo(Am.cell, 76, 75, 74, 77, 79), // plasma rifle
  WeaponInfo(Am.cell, 83, 82, 81, 84, 88), // bfg 9000
  WeaponInfo(Am.noAmmo, 70, 69, 67, 71, 0), // chainsaw
  WeaponInfo(Am.shell, 34, 33, 32, 35, 47), // super shotgun
];

/// states[], vanilla info.c. Indexed by statenum_t ordinal (St.*).
const List<State> states = <State>[
  State(SpriteNum.troo, 0, -1, null, 0), // 0 S_NULL
  State(SpriteNum.shtg, 4, 0, 'A_Light0', 0), // 1 S_LIGHTDONE
  State(SpriteNum.pung, 0, 1, 'A_WeaponReady', 2), // 2 S_PUNCH
  State(SpriteNum.pung, 0, 1, 'A_Lower', 3), // 3 S_PUNCHDOWN
  State(SpriteNum.pung, 0, 1, 'A_Raise', 4), // 4 S_PUNCHUP
  State(SpriteNum.pung, 1, 4, null, 6), // 5 S_PUNCH1
  State(SpriteNum.pung, 2, 4, 'A_Punch', 7), // 6 S_PUNCH2
  State(SpriteNum.pung, 3, 5, null, 8), // 7 S_PUNCH3
  State(SpriteNum.pung, 2, 4, null, 9), // 8 S_PUNCH4
  State(SpriteNum.pung, 1, 5, 'A_ReFire', 2), // 9 S_PUNCH5
  State(SpriteNum.pisg, 0, 1, 'A_WeaponReady', 10), // 10 S_PISTOL
  State(SpriteNum.pisg, 0, 1, 'A_Lower', 11), // 11 S_PISTOLDOWN
  State(SpriteNum.pisg, 0, 1, 'A_Raise', 12), // 12 S_PISTOLUP
  State(SpriteNum.pisg, 0, 4, null, 14), // 13 S_PISTOL1
  State(SpriteNum.pisg, 1, 6, 'A_FirePistol', 15), // 14 S_PISTOL2
  State(SpriteNum.pisg, 2, 4, null, 16), // 15 S_PISTOL3
  State(SpriteNum.pisg, 1, 5, 'A_ReFire', 10), // 16 S_PISTOL4
  State(SpriteNum.pisf, _fb, 7, 'A_Light1', 1), // 17 S_PISTOLFLASH
  State(SpriteNum.shtg, 0, 1, 'A_WeaponReady', 18), // 18 S_SGUN
  State(SpriteNum.shtg, 0, 1, 'A_Lower', 19), // 19 S_SGUNDOWN
  State(SpriteNum.shtg, 0, 1, 'A_Raise', 20), // 20 S_SGUNUP
  State(SpriteNum.shtg, 0, 3, null, 22), // 21 S_SGUN1
  State(SpriteNum.shtg, 0, 7, 'A_FireShotgun', 23), // 22 S_SGUN2
  State(SpriteNum.shtg, 1, 5, null, 24), // 23 S_SGUN3
  State(SpriteNum.shtg, 2, 5, null, 25), // 24 S_SGUN4
  State(SpriteNum.shtg, 3, 4, null, 26), // 25 S_SGUN5
  State(SpriteNum.shtg, 2, 5, null, 27), // 26 S_SGUN6
  State(SpriteNum.shtg, 1, 5, null, 28), // 27 S_SGUN7
  State(SpriteNum.shtg, 0, 3, null, 29), // 28 S_SGUN8
  State(SpriteNum.shtg, 0, 7, 'A_ReFire', 18), // 29 S_SGUN9
  State(SpriteNum.shtf, _fb, 4, 'A_Light1', 31), // 30 S_SGUNFLASH1
  State(SpriteNum.shtf, 1 | _fb, 3, 'A_Light2', 1), // 31 S_SGUNFLASH2
  State(SpriteNum.sht2, 0, 1, 'A_WeaponReady', 32), // 32 S_DSGUN
  State(SpriteNum.sht2, 0, 1, 'A_Lower', 33), // 33 S_DSGUNDOWN
  State(SpriteNum.sht2, 0, 1, 'A_Raise', 34), // 34 S_DSGUNUP
  State(SpriteNum.sht2, 0, 3, null, 36), // 35 S_DSGUN1
  State(SpriteNum.sht2, 0, 7, 'A_FireShotgun2', 37), // 36 S_DSGUN2
  State(SpriteNum.sht2, 1, 7, null, 38), // 37 S_DSGUN3
  State(SpriteNum.sht2, 2, 7, 'A_CheckReload', 39), // 38 S_DSGUN4
  State(SpriteNum.sht2, 3, 7, 'A_OpenShotgun2', 40), // 39 S_DSGUN5
  State(SpriteNum.sht2, 4, 7, null, 41), // 40 S_DSGUN6
  State(SpriteNum.sht2, 5, 7, 'A_LoadShotgun2', 42), // 41 S_DSGUN7
  State(SpriteNum.sht2, 6, 6, null, 43), // 42 S_DSGUN8
  State(SpriteNum.sht2, 7, 6, 'A_CloseShotgun2', 44), // 43 S_DSGUN9
  State(SpriteNum.sht2, 0, 5, 'A_ReFire', 32), // 44 S_DSGUN10
  State(SpriteNum.sht2, 1, 7, null, 46), // 45 S_DSNR1
  State(SpriteNum.sht2, 0, 3, null, 33), // 46 S_DSNR2
  State(SpriteNum.sht2, 8 | _fb, 5, 'A_Light1', 48), // 47 S_DSGUNFLASH1
  State(SpriteNum.sht2, 9 | _fb, 4, 'A_Light2', 1), // 48 S_DSGUNFLASH2
  State(SpriteNum.chgg, 0, 1, 'A_WeaponReady', 49), // 49 S_CHAIN
  State(SpriteNum.chgg, 0, 1, 'A_Lower', 50), // 50 S_CHAINDOWN
  State(SpriteNum.chgg, 0, 1, 'A_Raise', 51), // 51 S_CHAINUP
  State(SpriteNum.chgg, 0, 4, 'A_FireCGun', 53), // 52 S_CHAIN1
  State(SpriteNum.chgg, 1, 4, 'A_FireCGun', 54), // 53 S_CHAIN2
  State(SpriteNum.chgg, 1, 0, 'A_ReFire', 49), // 54 S_CHAIN3
  State(SpriteNum.chgf, _fb, 5, 'A_Light1', 1), // 55 S_CHAINFLASH1
  State(SpriteNum.chgf, 1 | _fb, 5, 'A_Light2', 1), // 56 S_CHAINFLASH2
  State(SpriteNum.misg, 0, 1, 'A_WeaponReady', 57), // 57 S_MISSILE
  State(SpriteNum.misg, 0, 1, 'A_Lower', 58), // 58 S_MISSILEDOWN
  State(SpriteNum.misg, 0, 1, 'A_Raise', 59), // 59 S_MISSILEUP
  State(SpriteNum.misg, 1, 8, 'A_GunFlash', 61), // 60 S_MISSILE1
  State(SpriteNum.misg, 1, 12, 'A_FireMissile', 62), // 61 S_MISSILE2
  State(SpriteNum.misg, 1, 0, 'A_ReFire', 57), // 62 S_MISSILE3
  State(SpriteNum.misf, _fb, 3, 'A_Light1', 64), // 63 S_MISSILEFLASH1
  State(SpriteNum.misf, 1 | _fb, 4, null, 65), // 64 S_MISSILEFLASH2
  State(SpriteNum.misf, 2 | _fb, 4, 'A_Light2', 66), // 65 S_MISSILEFLASH3
  State(SpriteNum.misf, 3 | _fb, 4, 'A_Light2', 1), // 66 S_MISSILEFLASH4
  State(SpriteNum.sawg, 2, 4, 'A_WeaponReady', 68), // 67 S_SAW
  State(SpriteNum.sawg, 3, 4, 'A_WeaponReady', 67), // 68 S_SAWB
  State(SpriteNum.sawg, 2, 1, 'A_Lower', 69), // 69 S_SAWDOWN
  State(SpriteNum.sawg, 2, 1, 'A_Raise', 70), // 70 S_SAWUP
  State(SpriteNum.sawg, 0, 4, 'A_Saw', 72), // 71 S_SAW1
  State(SpriteNum.sawg, 1, 4, 'A_Saw', 73), // 72 S_SAW2
  State(SpriteNum.sawg, 1, 0, 'A_ReFire', 67), // 73 S_SAW3
  State(SpriteNum.plsg, 0, 1, 'A_WeaponReady', 74), // 74 S_PLASMA
  State(SpriteNum.plsg, 0, 1, 'A_Lower', 75), // 75 S_PLASMADOWN
  State(SpriteNum.plsg, 0, 1, 'A_Raise', 76), // 76 S_PLASMAUP
  State(SpriteNum.plsg, 0, 3, 'A_FirePlasma', 78), // 77 S_PLASMA1
  State(SpriteNum.plsg, 1, 20, 'A_ReFire', 74), // 78 S_PLASMA2
  State(SpriteNum.plsf, _fb, 4, 'A_Light1', 1), // 79 S_PLASMAFLASH1
  State(SpriteNum.plsf, 1 | _fb, 4, 'A_Light1', 1), // 80 S_PLASMAFLASH2
  State(SpriteNum.bfgg, 0, 1, 'A_WeaponReady', 81), // 81 S_BFG
  State(SpriteNum.bfgg, 0, 1, 'A_Lower', 82), // 82 S_BFGDOWN
  State(SpriteNum.bfgg, 0, 1, 'A_Raise', 83), // 83 S_BFGUP
  State(SpriteNum.bfgg, 0, 20, 'A_BFGsound', 85), // 84 S_BFG1
  State(SpriteNum.bfgg, 1, 10, 'A_GunFlash', 86), // 85 S_BFG2
  State(SpriteNum.bfgg, 1, 10, 'A_FireBFG', 87), // 86 S_BFG3
  State(SpriteNum.bfgg, 1, 20, 'A_ReFire', 81), // 87 S_BFG4
  State(SpriteNum.bfgf, _fb, 11, 'A_Light1', 89), // 88 S_BFGFLASH1
  State(SpriteNum.bfgf, 1 | _fb, 6, 'A_Light2', 1), // 89 S_BFGFLASH2
  State(SpriteNum.blud, 2, 8, null, 91), // 90 S_BLOOD1
  State(SpriteNum.blud, 1, 8, null, 92), // 91 S_BLOOD2
  State(SpriteNum.blud, 0, 8, null, 0), // 92 S_BLOOD3
  State(SpriteNum.puff, _fb, 4, null, 94), // 93 S_PUFF1
  State(SpriteNum.puff, 1, 4, null, 95), // 94 S_PUFF2
  State(SpriteNum.puff, 2, 4, null, 96), // 95 S_PUFF3
  State(SpriteNum.puff, 3, 4, null, 0), // 96 S_PUFF4
  State(SpriteNum.bal1, _fb, 4, null, 98), // 97 S_TBALL1
  State(SpriteNum.bal1, 1 | _fb, 4, null, 97), // 98 S_TBALL2
  State(SpriteNum.bal1, 2 | _fb, 6, null, 100), // 99 S_TBALLX1
  State(SpriteNum.bal1, 3 | _fb, 6, null, 101), // 100 S_TBALLX2
  State(SpriteNum.bal1, 4 | _fb, 6, null, 0), // 101 S_TBALLX3
  State(SpriteNum.bal2, _fb, 4, null, 103), // 102 S_RBALL1
  State(SpriteNum.bal2, 1 | _fb, 4, null, 102), // 103 S_RBALL2
  State(SpriteNum.bal2, 2 | _fb, 6, null, 105), // 104 S_RBALLX1
  State(SpriteNum.bal2, 3 | _fb, 6, null, 106), // 105 S_RBALLX2
  State(SpriteNum.bal2, 4 | _fb, 6, null, 0), // 106 S_RBALLX3
  State(SpriteNum.plss, _fb, 6, null, 108), // 107 S_PLASBALL
  State(SpriteNum.plss, 1 | _fb, 6, null, 107), // 108 S_PLASBALL2
  State(SpriteNum.plse, _fb, 4, null, 110), // 109 S_PLASEXP
  State(SpriteNum.plse, 1 | _fb, 4, null, 111), // 110 S_PLASEXP2
  State(SpriteNum.plse, 2 | _fb, 4, null, 112), // 111 S_PLASEXP3
  State(SpriteNum.plse, 3 | _fb, 4, null, 113), // 112 S_PLASEXP4
  State(SpriteNum.plse, 4 | _fb, 4, null, 0), // 113 S_PLASEXP5
  State(SpriteNum.misl, _fb, 1, null, 114), // 114 S_ROCKET
  State(SpriteNum.bfs1, _fb, 4, null, 116), // 115 S_BFGSHOT
  State(SpriteNum.bfs1, 1 | _fb, 4, null, 115), // 116 S_BFGSHOT2
  State(SpriteNum.bfe1, _fb, 8, null, 118), // 117 S_BFGLAND
  State(SpriteNum.bfe1, 1 | _fb, 8, null, 119), // 118 S_BFGLAND2
  State(SpriteNum.bfe1, 2 | _fb, 8, 'A_BFGSpray', 120), // 119 S_BFGLAND3
  State(SpriteNum.bfe1, 3 | _fb, 8, null, 121), // 120 S_BFGLAND4
  State(SpriteNum.bfe1, 4 | _fb, 8, null, 122), // 121 S_BFGLAND5
  State(SpriteNum.bfe1, 5 | _fb, 8, null, 0), // 122 S_BFGLAND6
  State(SpriteNum.bfe2, _fb, 8, null, 124), // 123 S_BFGEXP
  State(SpriteNum.bfe2, 1 | _fb, 8, null, 125), // 124 S_BFGEXP2
  State(SpriteNum.bfe2, 2 | _fb, 8, null, 126), // 125 S_BFGEXP3
  State(SpriteNum.bfe2, 3 | _fb, 8, null, 0), // 126 S_BFGEXP4
  State(SpriteNum.misl, 1 | _fb, 8, 'A_Explode', 128), // 127 S_EXPLODE1
  State(SpriteNum.misl, 2 | _fb, 6, null, 129), // 128 S_EXPLODE2
  State(SpriteNum.misl, 3 | _fb, 4, null, 0), // 129 S_EXPLODE3
  State(SpriteNum.tfog, _fb, 6, null, 131), // 130 S_TFOG
  State(SpriteNum.tfog, 1 | _fb, 6, null, 132), // 131 S_TFOG01
  State(SpriteNum.tfog, _fb, 6, null, 133), // 132 S_TFOG02
  State(SpriteNum.tfog, 1 | _fb, 6, null, 134), // 133 S_TFOG2
  State(SpriteNum.tfog, 2 | _fb, 6, null, 135), // 134 S_TFOG3
  State(SpriteNum.tfog, 3 | _fb, 6, null, 136), // 135 S_TFOG4
  State(SpriteNum.tfog, 4 | _fb, 6, null, 137), // 136 S_TFOG5
  State(SpriteNum.tfog, 5 | _fb, 6, null, 138), // 137 S_TFOG6
  State(SpriteNum.tfog, 6 | _fb, 6, null, 139), // 138 S_TFOG7
  State(SpriteNum.tfog, 7 | _fb, 6, null, 140), // 139 S_TFOG8
  State(SpriteNum.tfog, 8 | _fb, 6, null, 141), // 140 S_TFOG9
  State(SpriteNum.tfog, 9 | _fb, 6, null, 0), // 141 S_TFOG10
  State(SpriteNum.ifog, _fb, 6, null, 143), // 142 S_IFOG
  State(SpriteNum.ifog, 1 | _fb, 6, null, 144), // 143 S_IFOG01
  State(SpriteNum.ifog, _fb, 6, null, 145), // 144 S_IFOG02
  State(SpriteNum.ifog, 1 | _fb, 6, null, 146), // 145 S_IFOG2
  State(SpriteNum.ifog, 2 | _fb, 6, null, 147), // 146 S_IFOG3
  State(SpriteNum.ifog, 3 | _fb, 6, null, 148), // 147 S_IFOG4
  State(SpriteNum.ifog, 4 | _fb, 6, null, 0), // 148 S_IFOG5
  State(SpriteNum.play, 0, -1, null, 0), // 149 S_PLAY
  State(SpriteNum.play, 0, 4, null, 151), // 150 S_PLAY_RUN1
  State(SpriteNum.play, 1, 4, null, 152), // 151 S_PLAY_RUN2
  State(SpriteNum.play, 2, 4, null, 153), // 152 S_PLAY_RUN3
  State(SpriteNum.play, 3, 4, null, 150), // 153 S_PLAY_RUN4
  State(SpriteNum.play, 4, 12, null, 149), // 154 S_PLAY_ATK1
  State(SpriteNum.play, 5 | _fb, 6, null, 154), // 155 S_PLAY_ATK2
  State(SpriteNum.play, 6, 4, null, 157), // 156 S_PLAY_PAIN
  State(SpriteNum.play, 6, 4, 'A_Pain', 149), // 157 S_PLAY_PAIN2
  State(SpriteNum.play, 7, 10, null, 159), // 158 S_PLAY_DIE1
  State(SpriteNum.play, 8, 10, 'A_PlayerScream', 160), // 159 S_PLAY_DIE2
  State(SpriteNum.play, 9, 10, 'A_Fall', 161), // 160 S_PLAY_DIE3
  State(SpriteNum.play, 10, 10, null, 162), // 161 S_PLAY_DIE4
  State(SpriteNum.play, 11, 10, null, 163), // 162 S_PLAY_DIE5
  State(SpriteNum.play, 12, 10, null, 164), // 163 S_PLAY_DIE6
  State(SpriteNum.play, 13, -1, null, 0), // 164 S_PLAY_DIE7
  State(SpriteNum.play, 14, 5, null, 166), // 165 S_PLAY_XDIE1
  State(SpriteNum.play, 15, 5, 'A_XScream', 167), // 166 S_PLAY_XDIE2
  State(SpriteNum.play, 16, 5, 'A_Fall', 168), // 167 S_PLAY_XDIE3
  State(SpriteNum.play, 17, 5, null, 169), // 168 S_PLAY_XDIE4
  State(SpriteNum.play, 18, 5, null, 170), // 169 S_PLAY_XDIE5
  State(SpriteNum.play, 19, 5, null, 171), // 170 S_PLAY_XDIE6
  State(SpriteNum.play, 20, 5, null, 172), // 171 S_PLAY_XDIE7
  State(SpriteNum.play, 21, 5, null, 173), // 172 S_PLAY_XDIE8
  State(SpriteNum.play, 22, -1, null, 0), // 173 S_PLAY_XDIE9
  State(SpriteNum.poss, 0, 10, 'A_Look', 175), // 174 S_POSS_STND
  State(SpriteNum.poss, 1, 10, 'A_Look', 174), // 175 S_POSS_STND2
  State(SpriteNum.poss, 0, 4, 'A_Chase', 177), // 176 S_POSS_RUN1
  State(SpriteNum.poss, 0, 4, 'A_Chase', 178), // 177 S_POSS_RUN2
  State(SpriteNum.poss, 1, 4, 'A_Chase', 179), // 178 S_POSS_RUN3
  State(SpriteNum.poss, 1, 4, 'A_Chase', 180), // 179 S_POSS_RUN4
  State(SpriteNum.poss, 2, 4, 'A_Chase', 181), // 180 S_POSS_RUN5
  State(SpriteNum.poss, 2, 4, 'A_Chase', 182), // 181 S_POSS_RUN6
  State(SpriteNum.poss, 3, 4, 'A_Chase', 183), // 182 S_POSS_RUN7
  State(SpriteNum.poss, 3, 4, 'A_Chase', 176), // 183 S_POSS_RUN8
  State(SpriteNum.poss, 4, 10, 'A_FaceTarget', 185), // 184 S_POSS_ATK1
  State(SpriteNum.poss, 5, 8, 'A_PosAttack', 186), // 185 S_POSS_ATK2
  State(SpriteNum.poss, 4, 8, null, 176), // 186 S_POSS_ATK3
  State(SpriteNum.poss, 6, 3, null, 188), // 187 S_POSS_PAIN
  State(SpriteNum.poss, 6, 3, 'A_Pain', 176), // 188 S_POSS_PAIN2
  State(SpriteNum.poss, 7, 5, null, 190), // 189 S_POSS_DIE1
  State(SpriteNum.poss, 8, 5, 'A_Scream', 191), // 190 S_POSS_DIE2
  State(SpriteNum.poss, 9, 5, 'A_Fall', 192), // 191 S_POSS_DIE3
  State(SpriteNum.poss, 10, 5, null, 193), // 192 S_POSS_DIE4
  State(SpriteNum.poss, 11, -1, null, 0), // 193 S_POSS_DIE5
  State(SpriteNum.poss, 12, 5, null, 195), // 194 S_POSS_XDIE1
  State(SpriteNum.poss, 13, 5, 'A_XScream', 196), // 195 S_POSS_XDIE2
  State(SpriteNum.poss, 14, 5, 'A_Fall', 197), // 196 S_POSS_XDIE3
  State(SpriteNum.poss, 15, 5, null, 198), // 197 S_POSS_XDIE4
  State(SpriteNum.poss, 16, 5, null, 199), // 198 S_POSS_XDIE5
  State(SpriteNum.poss, 17, 5, null, 200), // 199 S_POSS_XDIE6
  State(SpriteNum.poss, 18, 5, null, 201), // 200 S_POSS_XDIE7
  State(SpriteNum.poss, 19, 5, null, 202), // 201 S_POSS_XDIE8
  State(SpriteNum.poss, 20, -1, null, 0), // 202 S_POSS_XDIE9
  State(SpriteNum.poss, 10, 5, null, 204), // 203 S_POSS_RAISE1
  State(SpriteNum.poss, 9, 5, null, 205), // 204 S_POSS_RAISE2
  State(SpriteNum.poss, 8, 5, null, 206), // 205 S_POSS_RAISE3
  State(SpriteNum.poss, 7, 5, null, 176), // 206 S_POSS_RAISE4
  State(SpriteNum.spos, 0, 10, 'A_Look', 208), // 207 S_SPOS_STND
  State(SpriteNum.spos, 1, 10, 'A_Look', 207), // 208 S_SPOS_STND2
  State(SpriteNum.spos, 0, 3, 'A_Chase', 210), // 209 S_SPOS_RUN1
  State(SpriteNum.spos, 0, 3, 'A_Chase', 211), // 210 S_SPOS_RUN2
  State(SpriteNum.spos, 1, 3, 'A_Chase', 212), // 211 S_SPOS_RUN3
  State(SpriteNum.spos, 1, 3, 'A_Chase', 213), // 212 S_SPOS_RUN4
  State(SpriteNum.spos, 2, 3, 'A_Chase', 214), // 213 S_SPOS_RUN5
  State(SpriteNum.spos, 2, 3, 'A_Chase', 215), // 214 S_SPOS_RUN6
  State(SpriteNum.spos, 3, 3, 'A_Chase', 216), // 215 S_SPOS_RUN7
  State(SpriteNum.spos, 3, 3, 'A_Chase', 209), // 216 S_SPOS_RUN8
  State(SpriteNum.spos, 4, 10, 'A_FaceTarget', 218), // 217 S_SPOS_ATK1
  State(SpriteNum.spos, 5 | _fb, 10, 'A_SPosAttack', 219), // 218 S_SPOS_ATK2
  State(SpriteNum.spos, 4, 10, null, 209), // 219 S_SPOS_ATK3
  State(SpriteNum.spos, 6, 3, null, 221), // 220 S_SPOS_PAIN
  State(SpriteNum.spos, 6, 3, 'A_Pain', 209), // 221 S_SPOS_PAIN2
  State(SpriteNum.spos, 7, 5, null, 223), // 222 S_SPOS_DIE1
  State(SpriteNum.spos, 8, 5, 'A_Scream', 224), // 223 S_SPOS_DIE2
  State(SpriteNum.spos, 9, 5, 'A_Fall', 225), // 224 S_SPOS_DIE3
  State(SpriteNum.spos, 10, 5, null, 226), // 225 S_SPOS_DIE4
  State(SpriteNum.spos, 11, -1, null, 0), // 226 S_SPOS_DIE5
  State(SpriteNum.spos, 12, 5, null, 228), // 227 S_SPOS_XDIE1
  State(SpriteNum.spos, 13, 5, 'A_XScream', 229), // 228 S_SPOS_XDIE2
  State(SpriteNum.spos, 14, 5, 'A_Fall', 230), // 229 S_SPOS_XDIE3
  State(SpriteNum.spos, 15, 5, null, 231), // 230 S_SPOS_XDIE4
  State(SpriteNum.spos, 16, 5, null, 232), // 231 S_SPOS_XDIE5
  State(SpriteNum.spos, 17, 5, null, 233), // 232 S_SPOS_XDIE6
  State(SpriteNum.spos, 18, 5, null, 234), // 233 S_SPOS_XDIE7
  State(SpriteNum.spos, 19, 5, null, 235), // 234 S_SPOS_XDIE8
  State(SpriteNum.spos, 20, -1, null, 0), // 235 S_SPOS_XDIE9
  State(SpriteNum.spos, 11, 5, null, 237), // 236 S_SPOS_RAISE1
  State(SpriteNum.spos, 10, 5, null, 238), // 237 S_SPOS_RAISE2
  State(SpriteNum.spos, 9, 5, null, 239), // 238 S_SPOS_RAISE3
  State(SpriteNum.spos, 8, 5, null, 240), // 239 S_SPOS_RAISE4
  State(SpriteNum.spos, 7, 5, null, 209), // 240 S_SPOS_RAISE5
  State(SpriteNum.vile, 0, 10, 'A_Look', 242), // 241 S_VILE_STND
  State(SpriteNum.vile, 1, 10, 'A_Look', 241), // 242 S_VILE_STND2
  State(SpriteNum.vile, 0, 2, 'A_VileChase', 244), // 243 S_VILE_RUN1
  State(SpriteNum.vile, 0, 2, 'A_VileChase', 245), // 244 S_VILE_RUN2
  State(SpriteNum.vile, 1, 2, 'A_VileChase', 246), // 245 S_VILE_RUN3
  State(SpriteNum.vile, 1, 2, 'A_VileChase', 247), // 246 S_VILE_RUN4
  State(SpriteNum.vile, 2, 2, 'A_VileChase', 248), // 247 S_VILE_RUN5
  State(SpriteNum.vile, 2, 2, 'A_VileChase', 249), // 248 S_VILE_RUN6
  State(SpriteNum.vile, 3, 2, 'A_VileChase', 250), // 249 S_VILE_RUN7
  State(SpriteNum.vile, 3, 2, 'A_VileChase', 251), // 250 S_VILE_RUN8
  State(SpriteNum.vile, 4, 2, 'A_VileChase', 252), // 251 S_VILE_RUN9
  State(SpriteNum.vile, 4, 2, 'A_VileChase', 253), // 252 S_VILE_RUN10
  State(SpriteNum.vile, 5, 2, 'A_VileChase', 254), // 253 S_VILE_RUN11
  State(SpriteNum.vile, 5, 2, 'A_VileChase', 243), // 254 S_VILE_RUN12
  State(SpriteNum.vile, 6 | _fb, 0, 'A_VileStart', 256), // 255 S_VILE_ATK1
  State(SpriteNum.vile, 6 | _fb, 10, 'A_FaceTarget', 257), // 256 S_VILE_ATK2
  State(SpriteNum.vile, 7 | _fb, 8, 'A_VileTarget', 258), // 257 S_VILE_ATK3
  State(SpriteNum.vile, 8 | _fb, 8, 'A_FaceTarget', 259), // 258 S_VILE_ATK4
  State(SpriteNum.vile, 9 | _fb, 8, 'A_FaceTarget', 260), // 259 S_VILE_ATK5
  State(SpriteNum.vile, 10 | _fb, 8, 'A_FaceTarget', 261), // 260 S_VILE_ATK6
  State(SpriteNum.vile, 11 | _fb, 8, 'A_FaceTarget', 262), // 261 S_VILE_ATK7
  State(SpriteNum.vile, 12 | _fb, 8, 'A_FaceTarget', 263), // 262 S_VILE_ATK8
  State(SpriteNum.vile, 13 | _fb, 8, 'A_FaceTarget', 264), // 263 S_VILE_ATK9
  State(SpriteNum.vile, 14 | _fb, 8, 'A_VileAttack', 265), // 264 S_VILE_ATK10
  State(SpriteNum.vile, 15 | _fb, 20, null, 243), // 265 S_VILE_ATK11
  State(SpriteNum.vile, 26 | _fb, 10, null, 267), // 266 S_VILE_HEAL1
  State(SpriteNum.vile, 27 | _fb, 10, null, 268), // 267 S_VILE_HEAL2
  State(SpriteNum.vile, 28 | _fb, 10, null, 243), // 268 S_VILE_HEAL3
  State(SpriteNum.vile, 16, 5, null, 270), // 269 S_VILE_PAIN
  State(SpriteNum.vile, 16, 5, 'A_Pain', 243), // 270 S_VILE_PAIN2
  State(SpriteNum.vile, 16, 7, null, 272), // 271 S_VILE_DIE1
  State(SpriteNum.vile, 17, 7, 'A_Scream', 273), // 272 S_VILE_DIE2
  State(SpriteNum.vile, 18, 7, 'A_Fall', 274), // 273 S_VILE_DIE3
  State(SpriteNum.vile, 19, 7, null, 275), // 274 S_VILE_DIE4
  State(SpriteNum.vile, 20, 7, null, 276), // 275 S_VILE_DIE5
  State(SpriteNum.vile, 21, 7, null, 277), // 276 S_VILE_DIE6
  State(SpriteNum.vile, 22, 7, null, 278), // 277 S_VILE_DIE7
  State(SpriteNum.vile, 23, 5, null, 279), // 278 S_VILE_DIE8
  State(SpriteNum.vile, 24, 5, null, 280), // 279 S_VILE_DIE9
  State(SpriteNum.vile, 25, -1, null, 0), // 280 S_VILE_DIE10
  State(SpriteNum.fire, _fb, 2, 'A_StartFire', 282), // 281 S_FIRE1
  State(SpriteNum.fire, 1 | _fb, 2, 'A_Fire', 283), // 282 S_FIRE2
  State(SpriteNum.fire, _fb, 2, 'A_Fire', 284), // 283 S_FIRE3
  State(SpriteNum.fire, 1 | _fb, 2, 'A_Fire', 285), // 284 S_FIRE4
  State(SpriteNum.fire, 2 | _fb, 2, 'A_FireCrackle', 286), // 285 S_FIRE5
  State(SpriteNum.fire, 1 | _fb, 2, 'A_Fire', 287), // 286 S_FIRE6
  State(SpriteNum.fire, 2 | _fb, 2, 'A_Fire', 288), // 287 S_FIRE7
  State(SpriteNum.fire, 1 | _fb, 2, 'A_Fire', 289), // 288 S_FIRE8
  State(SpriteNum.fire, 2 | _fb, 2, 'A_Fire', 290), // 289 S_FIRE9
  State(SpriteNum.fire, 3 | _fb, 2, 'A_Fire', 291), // 290 S_FIRE10
  State(SpriteNum.fire, 2 | _fb, 2, 'A_Fire', 292), // 291 S_FIRE11
  State(SpriteNum.fire, 3 | _fb, 2, 'A_Fire', 293), // 292 S_FIRE12
  State(SpriteNum.fire, 2 | _fb, 2, 'A_Fire', 294), // 293 S_FIRE13
  State(SpriteNum.fire, 3 | _fb, 2, 'A_Fire', 295), // 294 S_FIRE14
  State(SpriteNum.fire, 4 | _fb, 2, 'A_Fire', 296), // 295 S_FIRE15
  State(SpriteNum.fire, 3 | _fb, 2, 'A_Fire', 297), // 296 S_FIRE16
  State(SpriteNum.fire, 4 | _fb, 2, 'A_Fire', 298), // 297 S_FIRE17
  State(SpriteNum.fire, 3 | _fb, 2, 'A_Fire', 299), // 298 S_FIRE18
  State(SpriteNum.fire, 4 | _fb, 2, 'A_FireCrackle', 300), // 299 S_FIRE19
  State(SpriteNum.fire, 5 | _fb, 2, 'A_Fire', 301), // 300 S_FIRE20
  State(SpriteNum.fire, 4 | _fb, 2, 'A_Fire', 302), // 301 S_FIRE21
  State(SpriteNum.fire, 5 | _fb, 2, 'A_Fire', 303), // 302 S_FIRE22
  State(SpriteNum.fire, 4 | _fb, 2, 'A_Fire', 304), // 303 S_FIRE23
  State(SpriteNum.fire, 5 | _fb, 2, 'A_Fire', 305), // 304 S_FIRE24
  State(SpriteNum.fire, 6 | _fb, 2, 'A_Fire', 306), // 305 S_FIRE25
  State(SpriteNum.fire, 7 | _fb, 2, 'A_Fire', 307), // 306 S_FIRE26
  State(SpriteNum.fire, 6 | _fb, 2, 'A_Fire', 308), // 307 S_FIRE27
  State(SpriteNum.fire, 7 | _fb, 2, 'A_Fire', 309), // 308 S_FIRE28
  State(SpriteNum.fire, 6 | _fb, 2, 'A_Fire', 310), // 309 S_FIRE29
  State(SpriteNum.fire, 7 | _fb, 2, 'A_Fire', 0), // 310 S_FIRE30
  State(SpriteNum.puff, 1, 4, null, 312), // 311 S_SMOKE1
  State(SpriteNum.puff, 2, 4, null, 313), // 312 S_SMOKE2
  State(SpriteNum.puff, 1, 4, null, 314), // 313 S_SMOKE3
  State(SpriteNum.puff, 2, 4, null, 315), // 314 S_SMOKE4
  State(SpriteNum.puff, 3, 4, null, 0), // 315 S_SMOKE5
  State(SpriteNum.fatb, _fb, 2, 'A_Tracer', 317), // 316 S_TRACER
  State(SpriteNum.fatb, 1 | _fb, 2, 'A_Tracer', 316), // 317 S_TRACER2
  State(SpriteNum.fbxp, _fb, 8, null, 319), // 318 S_TRACEEXP1
  State(SpriteNum.fbxp, 1 | _fb, 6, null, 320), // 319 S_TRACEEXP2
  State(SpriteNum.fbxp, 2 | _fb, 4, null, 0), // 320 S_TRACEEXP3
  State(SpriteNum.skel, 0, 10, 'A_Look', 322), // 321 S_SKEL_STND
  State(SpriteNum.skel, 1, 10, 'A_Look', 321), // 322 S_SKEL_STND2
  State(SpriteNum.skel, 0, 2, 'A_Chase', 324), // 323 S_SKEL_RUN1
  State(SpriteNum.skel, 0, 2, 'A_Chase', 325), // 324 S_SKEL_RUN2
  State(SpriteNum.skel, 1, 2, 'A_Chase', 326), // 325 S_SKEL_RUN3
  State(SpriteNum.skel, 1, 2, 'A_Chase', 327), // 326 S_SKEL_RUN4
  State(SpriteNum.skel, 2, 2, 'A_Chase', 328), // 327 S_SKEL_RUN5
  State(SpriteNum.skel, 2, 2, 'A_Chase', 329), // 328 S_SKEL_RUN6
  State(SpriteNum.skel, 3, 2, 'A_Chase', 330), // 329 S_SKEL_RUN7
  State(SpriteNum.skel, 3, 2, 'A_Chase', 331), // 330 S_SKEL_RUN8
  State(SpriteNum.skel, 4, 2, 'A_Chase', 332), // 331 S_SKEL_RUN9
  State(SpriteNum.skel, 4, 2, 'A_Chase', 333), // 332 S_SKEL_RUN10
  State(SpriteNum.skel, 5, 2, 'A_Chase', 334), // 333 S_SKEL_RUN11
  State(SpriteNum.skel, 5, 2, 'A_Chase', 323), // 334 S_SKEL_RUN12
  State(SpriteNum.skel, 6, 0, 'A_FaceTarget', 336), // 335 S_SKEL_FIST1
  State(SpriteNum.skel, 6, 6, 'A_SkelWhoosh', 337), // 336 S_SKEL_FIST2
  State(SpriteNum.skel, 7, 6, 'A_FaceTarget', 338), // 337 S_SKEL_FIST3
  State(SpriteNum.skel, 8, 6, 'A_SkelFist', 323), // 338 S_SKEL_FIST4
  State(SpriteNum.skel, 9 | _fb, 0, 'A_FaceTarget', 340), // 339 S_SKEL_MISS1
  State(SpriteNum.skel, 9 | _fb, 10, 'A_FaceTarget', 341), // 340 S_SKEL_MISS2
  State(SpriteNum.skel, 10, 10, 'A_SkelMissile', 342), // 341 S_SKEL_MISS3
  State(SpriteNum.skel, 10, 10, 'A_FaceTarget', 323), // 342 S_SKEL_MISS4
  State(SpriteNum.skel, 11, 5, null, 344), // 343 S_SKEL_PAIN
  State(SpriteNum.skel, 11, 5, 'A_Pain', 323), // 344 S_SKEL_PAIN2
  State(SpriteNum.skel, 11, 7, null, 346), // 345 S_SKEL_DIE1
  State(SpriteNum.skel, 12, 7, null, 347), // 346 S_SKEL_DIE2
  State(SpriteNum.skel, 13, 7, 'A_Scream', 348), // 347 S_SKEL_DIE3
  State(SpriteNum.skel, 14, 7, 'A_Fall', 349), // 348 S_SKEL_DIE4
  State(SpriteNum.skel, 15, 7, null, 350), // 349 S_SKEL_DIE5
  State(SpriteNum.skel, 16, -1, null, 0), // 350 S_SKEL_DIE6
  State(SpriteNum.skel, 16, 5, null, 352), // 351 S_SKEL_RAISE1
  State(SpriteNum.skel, 15, 5, null, 353), // 352 S_SKEL_RAISE2
  State(SpriteNum.skel, 14, 5, null, 354), // 353 S_SKEL_RAISE3
  State(SpriteNum.skel, 13, 5, null, 355), // 354 S_SKEL_RAISE4
  State(SpriteNum.skel, 12, 5, null, 356), // 355 S_SKEL_RAISE5
  State(SpriteNum.skel, 11, 5, null, 323), // 356 S_SKEL_RAISE6
  State(SpriteNum.manf, _fb, 4, null, 358), // 357 S_FATSHOT1
  State(SpriteNum.manf, 1 | _fb, 4, null, 357), // 358 S_FATSHOT2
  State(SpriteNum.misl, 1 | _fb, 8, null, 360), // 359 S_FATSHOTX1
  State(SpriteNum.misl, 2 | _fb, 6, null, 361), // 360 S_FATSHOTX2
  State(SpriteNum.misl, 3 | _fb, 4, null, 0), // 361 S_FATSHOTX3
  State(SpriteNum.fatt, 0, 15, 'A_Look', 363), // 362 S_FATT_STND
  State(SpriteNum.fatt, 1, 15, 'A_Look', 362), // 363 S_FATT_STND2
  State(SpriteNum.fatt, 0, 4, 'A_Chase', 365), // 364 S_FATT_RUN1
  State(SpriteNum.fatt, 0, 4, 'A_Chase', 366), // 365 S_FATT_RUN2
  State(SpriteNum.fatt, 1, 4, 'A_Chase', 367), // 366 S_FATT_RUN3
  State(SpriteNum.fatt, 1, 4, 'A_Chase', 368), // 367 S_FATT_RUN4
  State(SpriteNum.fatt, 2, 4, 'A_Chase', 369), // 368 S_FATT_RUN5
  State(SpriteNum.fatt, 2, 4, 'A_Chase', 370), // 369 S_FATT_RUN6
  State(SpriteNum.fatt, 3, 4, 'A_Chase', 371), // 370 S_FATT_RUN7
  State(SpriteNum.fatt, 3, 4, 'A_Chase', 372), // 371 S_FATT_RUN8
  State(SpriteNum.fatt, 4, 4, 'A_Chase', 373), // 372 S_FATT_RUN9
  State(SpriteNum.fatt, 4, 4, 'A_Chase', 374), // 373 S_FATT_RUN10
  State(SpriteNum.fatt, 5, 4, 'A_Chase', 375), // 374 S_FATT_RUN11
  State(SpriteNum.fatt, 5, 4, 'A_Chase', 364), // 375 S_FATT_RUN12
  State(SpriteNum.fatt, 6, 20, 'A_FatRaise', 377), // 376 S_FATT_ATK1
  State(SpriteNum.fatt, 7 | _fb, 10, 'A_FatAttack1', 378), // 377 S_FATT_ATK2
  State(SpriteNum.fatt, 8, 5, 'A_FaceTarget', 379), // 378 S_FATT_ATK3
  State(SpriteNum.fatt, 6, 5, 'A_FaceTarget', 380), // 379 S_FATT_ATK4
  State(SpriteNum.fatt, 7 | _fb, 10, 'A_FatAttack2', 381), // 380 S_FATT_ATK5
  State(SpriteNum.fatt, 8, 5, 'A_FaceTarget', 382), // 381 S_FATT_ATK6
  State(SpriteNum.fatt, 6, 5, 'A_FaceTarget', 383), // 382 S_FATT_ATK7
  State(SpriteNum.fatt, 7 | _fb, 10, 'A_FatAttack3', 384), // 383 S_FATT_ATK8
  State(SpriteNum.fatt, 8, 5, 'A_FaceTarget', 385), // 384 S_FATT_ATK9
  State(SpriteNum.fatt, 6, 5, 'A_FaceTarget', 364), // 385 S_FATT_ATK10
  State(SpriteNum.fatt, 9, 3, null, 387), // 386 S_FATT_PAIN
  State(SpriteNum.fatt, 9, 3, 'A_Pain', 364), // 387 S_FATT_PAIN2
  State(SpriteNum.fatt, 10, 6, null, 389), // 388 S_FATT_DIE1
  State(SpriteNum.fatt, 11, 6, 'A_Scream', 390), // 389 S_FATT_DIE2
  State(SpriteNum.fatt, 12, 6, 'A_Fall', 391), // 390 S_FATT_DIE3
  State(SpriteNum.fatt, 13, 6, null, 392), // 391 S_FATT_DIE4
  State(SpriteNum.fatt, 14, 6, null, 393), // 392 S_FATT_DIE5
  State(SpriteNum.fatt, 15, 6, null, 394), // 393 S_FATT_DIE6
  State(SpriteNum.fatt, 16, 6, null, 395), // 394 S_FATT_DIE7
  State(SpriteNum.fatt, 17, 6, null, 396), // 395 S_FATT_DIE8
  State(SpriteNum.fatt, 18, 6, null, 397), // 396 S_FATT_DIE9
  State(SpriteNum.fatt, 19, -1, 'A_BossDeath', 0), // 397 S_FATT_DIE10
  State(SpriteNum.fatt, 17, 5, null, 399), // 398 S_FATT_RAISE1
  State(SpriteNum.fatt, 16, 5, null, 400), // 399 S_FATT_RAISE2
  State(SpriteNum.fatt, 15, 5, null, 401), // 400 S_FATT_RAISE3
  State(SpriteNum.fatt, 14, 5, null, 402), // 401 S_FATT_RAISE4
  State(SpriteNum.fatt, 13, 5, null, 403), // 402 S_FATT_RAISE5
  State(SpriteNum.fatt, 12, 5, null, 404), // 403 S_FATT_RAISE6
  State(SpriteNum.fatt, 11, 5, null, 405), // 404 S_FATT_RAISE7
  State(SpriteNum.fatt, 10, 5, null, 364), // 405 S_FATT_RAISE8
  State(SpriteNum.cpos, 0, 10, 'A_Look', 407), // 406 S_CPOS_STND
  State(SpriteNum.cpos, 1, 10, 'A_Look', 406), // 407 S_CPOS_STND2
  State(SpriteNum.cpos, 0, 3, 'A_Chase', 409), // 408 S_CPOS_RUN1
  State(SpriteNum.cpos, 0, 3, 'A_Chase', 410), // 409 S_CPOS_RUN2
  State(SpriteNum.cpos, 1, 3, 'A_Chase', 411), // 410 S_CPOS_RUN3
  State(SpriteNum.cpos, 1, 3, 'A_Chase', 412), // 411 S_CPOS_RUN4
  State(SpriteNum.cpos, 2, 3, 'A_Chase', 413), // 412 S_CPOS_RUN5
  State(SpriteNum.cpos, 2, 3, 'A_Chase', 414), // 413 S_CPOS_RUN6
  State(SpriteNum.cpos, 3, 3, 'A_Chase', 415), // 414 S_CPOS_RUN7
  State(SpriteNum.cpos, 3, 3, 'A_Chase', 408), // 415 S_CPOS_RUN8
  State(SpriteNum.cpos, 4, 10, 'A_FaceTarget', 417), // 416 S_CPOS_ATK1
  State(SpriteNum.cpos, 5 | _fb, 4, 'A_CPosAttack', 418), // 417 S_CPOS_ATK2
  State(SpriteNum.cpos, 4 | _fb, 4, 'A_CPosAttack', 419), // 418 S_CPOS_ATK3
  State(SpriteNum.cpos, 5, 1, 'A_CPosRefire', 417), // 419 S_CPOS_ATK4
  State(SpriteNum.cpos, 6, 3, null, 421), // 420 S_CPOS_PAIN
  State(SpriteNum.cpos, 6, 3, 'A_Pain', 408), // 421 S_CPOS_PAIN2
  State(SpriteNum.cpos, 7, 5, null, 423), // 422 S_CPOS_DIE1
  State(SpriteNum.cpos, 8, 5, 'A_Scream', 424), // 423 S_CPOS_DIE2
  State(SpriteNum.cpos, 9, 5, 'A_Fall', 425), // 424 S_CPOS_DIE3
  State(SpriteNum.cpos, 10, 5, null, 426), // 425 S_CPOS_DIE4
  State(SpriteNum.cpos, 11, 5, null, 427), // 426 S_CPOS_DIE5
  State(SpriteNum.cpos, 12, 5, null, 428), // 427 S_CPOS_DIE6
  State(SpriteNum.cpos, 13, -1, null, 0), // 428 S_CPOS_DIE7
  State(SpriteNum.cpos, 14, 5, null, 430), // 429 S_CPOS_XDIE1
  State(SpriteNum.cpos, 15, 5, 'A_XScream', 431), // 430 S_CPOS_XDIE2
  State(SpriteNum.cpos, 16, 5, 'A_Fall', 432), // 431 S_CPOS_XDIE3
  State(SpriteNum.cpos, 17, 5, null, 433), // 432 S_CPOS_XDIE4
  State(SpriteNum.cpos, 18, 5, null, 434), // 433 S_CPOS_XDIE5
  State(SpriteNum.cpos, 19, -1, null, 0), // 434 S_CPOS_XDIE6
  State(SpriteNum.cpos, 13, 5, null, 436), // 435 S_CPOS_RAISE1
  State(SpriteNum.cpos, 12, 5, null, 437), // 436 S_CPOS_RAISE2
  State(SpriteNum.cpos, 11, 5, null, 438), // 437 S_CPOS_RAISE3
  State(SpriteNum.cpos, 10, 5, null, 439), // 438 S_CPOS_RAISE4
  State(SpriteNum.cpos, 9, 5, null, 440), // 439 S_CPOS_RAISE5
  State(SpriteNum.cpos, 8, 5, null, 441), // 440 S_CPOS_RAISE6
  State(SpriteNum.cpos, 7, 5, null, 408), // 441 S_CPOS_RAISE7
  State(SpriteNum.troo, 0, 10, 'A_Look', 443), // 442 S_TROO_STND
  State(SpriteNum.troo, 1, 10, 'A_Look', 442), // 443 S_TROO_STND2
  State(SpriteNum.troo, 0, 3, 'A_Chase', 445), // 444 S_TROO_RUN1
  State(SpriteNum.troo, 0, 3, 'A_Chase', 446), // 445 S_TROO_RUN2
  State(SpriteNum.troo, 1, 3, 'A_Chase', 447), // 446 S_TROO_RUN3
  State(SpriteNum.troo, 1, 3, 'A_Chase', 448), // 447 S_TROO_RUN4
  State(SpriteNum.troo, 2, 3, 'A_Chase', 449), // 448 S_TROO_RUN5
  State(SpriteNum.troo, 2, 3, 'A_Chase', 450), // 449 S_TROO_RUN6
  State(SpriteNum.troo, 3, 3, 'A_Chase', 451), // 450 S_TROO_RUN7
  State(SpriteNum.troo, 3, 3, 'A_Chase', 444), // 451 S_TROO_RUN8
  State(SpriteNum.troo, 4, 8, 'A_FaceTarget', 453), // 452 S_TROO_ATK1
  State(SpriteNum.troo, 5, 8, 'A_FaceTarget', 454), // 453 S_TROO_ATK2
  State(SpriteNum.troo, 6, 6, 'A_TroopAttack', 444), // 454 S_TROO_ATK3
  State(SpriteNum.troo, 7, 2, null, 456), // 455 S_TROO_PAIN
  State(SpriteNum.troo, 7, 2, 'A_Pain', 444), // 456 S_TROO_PAIN2
  State(SpriteNum.troo, 8, 8, null, 458), // 457 S_TROO_DIE1
  State(SpriteNum.troo, 9, 8, 'A_Scream', 459), // 458 S_TROO_DIE2
  State(SpriteNum.troo, 10, 6, null, 460), // 459 S_TROO_DIE3
  State(SpriteNum.troo, 11, 6, 'A_Fall', 461), // 460 S_TROO_DIE4
  State(SpriteNum.troo, 12, -1, null, 0), // 461 S_TROO_DIE5
  State(SpriteNum.troo, 13, 5, null, 463), // 462 S_TROO_XDIE1
  State(SpriteNum.troo, 14, 5, 'A_XScream', 464), // 463 S_TROO_XDIE2
  State(SpriteNum.troo, 15, 5, null, 465), // 464 S_TROO_XDIE3
  State(SpriteNum.troo, 16, 5, 'A_Fall', 466), // 465 S_TROO_XDIE4
  State(SpriteNum.troo, 17, 5, null, 467), // 466 S_TROO_XDIE5
  State(SpriteNum.troo, 18, 5, null, 468), // 467 S_TROO_XDIE6
  State(SpriteNum.troo, 19, 5, null, 469), // 468 S_TROO_XDIE7
  State(SpriteNum.troo, 20, -1, null, 0), // 469 S_TROO_XDIE8
  State(SpriteNum.troo, 12, 8, null, 471), // 470 S_TROO_RAISE1
  State(SpriteNum.troo, 11, 8, null, 472), // 471 S_TROO_RAISE2
  State(SpriteNum.troo, 10, 6, null, 473), // 472 S_TROO_RAISE3
  State(SpriteNum.troo, 9, 6, null, 474), // 473 S_TROO_RAISE4
  State(SpriteNum.troo, 8, 6, null, 444), // 474 S_TROO_RAISE5
  State(SpriteNum.sarg, 0, 10, 'A_Look', 476), // 475 S_SARG_STND
  State(SpriteNum.sarg, 1, 10, 'A_Look', 475), // 476 S_SARG_STND2
  State(SpriteNum.sarg, 0, 2, 'A_Chase', 478), // 477 S_SARG_RUN1
  State(SpriteNum.sarg, 0, 2, 'A_Chase', 479), // 478 S_SARG_RUN2
  State(SpriteNum.sarg, 1, 2, 'A_Chase', 480), // 479 S_SARG_RUN3
  State(SpriteNum.sarg, 1, 2, 'A_Chase', 481), // 480 S_SARG_RUN4
  State(SpriteNum.sarg, 2, 2, 'A_Chase', 482), // 481 S_SARG_RUN5
  State(SpriteNum.sarg, 2, 2, 'A_Chase', 483), // 482 S_SARG_RUN6
  State(SpriteNum.sarg, 3, 2, 'A_Chase', 484), // 483 S_SARG_RUN7
  State(SpriteNum.sarg, 3, 2, 'A_Chase', 477), // 484 S_SARG_RUN8
  State(SpriteNum.sarg, 4, 8, 'A_FaceTarget', 486), // 485 S_SARG_ATK1
  State(SpriteNum.sarg, 5, 8, 'A_FaceTarget', 487), // 486 S_SARG_ATK2
  State(SpriteNum.sarg, 6, 8, 'A_SargAttack', 477), // 487 S_SARG_ATK3
  State(SpriteNum.sarg, 7, 2, null, 489), // 488 S_SARG_PAIN
  State(SpriteNum.sarg, 7, 2, 'A_Pain', 477), // 489 S_SARG_PAIN2
  State(SpriteNum.sarg, 8, 8, null, 491), // 490 S_SARG_DIE1
  State(SpriteNum.sarg, 9, 8, 'A_Scream', 492), // 491 S_SARG_DIE2
  State(SpriteNum.sarg, 10, 4, null, 493), // 492 S_SARG_DIE3
  State(SpriteNum.sarg, 11, 4, 'A_Fall', 494), // 493 S_SARG_DIE4
  State(SpriteNum.sarg, 12, 4, null, 495), // 494 S_SARG_DIE5
  State(SpriteNum.sarg, 13, -1, null, 0), // 495 S_SARG_DIE6
  State(SpriteNum.sarg, 13, 5, null, 497), // 496 S_SARG_RAISE1
  State(SpriteNum.sarg, 12, 5, null, 498), // 497 S_SARG_RAISE2
  State(SpriteNum.sarg, 11, 5, null, 499), // 498 S_SARG_RAISE3
  State(SpriteNum.sarg, 10, 5, null, 500), // 499 S_SARG_RAISE4
  State(SpriteNum.sarg, 9, 5, null, 501), // 500 S_SARG_RAISE5
  State(SpriteNum.sarg, 8, 5, null, 477), // 501 S_SARG_RAISE6
  State(SpriteNum.head, 0, 10, 'A_Look', 502), // 502 S_HEAD_STND
  State(SpriteNum.head, 0, 3, 'A_Chase', 503), // 503 S_HEAD_RUN1
  State(SpriteNum.head, 1, 5, 'A_FaceTarget', 505), // 504 S_HEAD_ATK1
  State(SpriteNum.head, 2, 5, 'A_FaceTarget', 506), // 505 S_HEAD_ATK2
  State(SpriteNum.head, 3 | _fb, 5, 'A_HeadAttack', 503), // 506 S_HEAD_ATK3
  State(SpriteNum.head, 4, 3, null, 508), // 507 S_HEAD_PAIN
  State(SpriteNum.head, 4, 3, 'A_Pain', 509), // 508 S_HEAD_PAIN2
  State(SpriteNum.head, 5, 6, null, 503), // 509 S_HEAD_PAIN3
  State(SpriteNum.head, 6, 8, null, 511), // 510 S_HEAD_DIE1
  State(SpriteNum.head, 7, 8, 'A_Scream', 512), // 511 S_HEAD_DIE2
  State(SpriteNum.head, 8, 8, null, 513), // 512 S_HEAD_DIE3
  State(SpriteNum.head, 9, 8, null, 514), // 513 S_HEAD_DIE4
  State(SpriteNum.head, 10, 8, 'A_Fall', 515), // 514 S_HEAD_DIE5
  State(SpriteNum.head, 11, -1, null, 0), // 515 S_HEAD_DIE6
  State(SpriteNum.head, 11, 8, null, 517), // 516 S_HEAD_RAISE1
  State(SpriteNum.head, 10, 8, null, 518), // 517 S_HEAD_RAISE2
  State(SpriteNum.head, 9, 8, null, 519), // 518 S_HEAD_RAISE3
  State(SpriteNum.head, 8, 8, null, 520), // 519 S_HEAD_RAISE4
  State(SpriteNum.head, 7, 8, null, 521), // 520 S_HEAD_RAISE5
  State(SpriteNum.head, 6, 8, null, 503), // 521 S_HEAD_RAISE6
  State(SpriteNum.bal7, _fb, 4, null, 523), // 522 S_BRBALL1
  State(SpriteNum.bal7, 1 | _fb, 4, null, 522), // 523 S_BRBALL2
  State(SpriteNum.bal7, 2 | _fb, 6, null, 525), // 524 S_BRBALLX1
  State(SpriteNum.bal7, 3 | _fb, 6, null, 526), // 525 S_BRBALLX2
  State(SpriteNum.bal7, 4 | _fb, 6, null, 0), // 526 S_BRBALLX3
  State(SpriteNum.boss, 0, 10, 'A_Look', 528), // 527 S_BOSS_STND
  State(SpriteNum.boss, 1, 10, 'A_Look', 527), // 528 S_BOSS_STND2
  State(SpriteNum.boss, 0, 3, 'A_Chase', 530), // 529 S_BOSS_RUN1
  State(SpriteNum.boss, 0, 3, 'A_Chase', 531), // 530 S_BOSS_RUN2
  State(SpriteNum.boss, 1, 3, 'A_Chase', 532), // 531 S_BOSS_RUN3
  State(SpriteNum.boss, 1, 3, 'A_Chase', 533), // 532 S_BOSS_RUN4
  State(SpriteNum.boss, 2, 3, 'A_Chase', 534), // 533 S_BOSS_RUN5
  State(SpriteNum.boss, 2, 3, 'A_Chase', 535), // 534 S_BOSS_RUN6
  State(SpriteNum.boss, 3, 3, 'A_Chase', 536), // 535 S_BOSS_RUN7
  State(SpriteNum.boss, 3, 3, 'A_Chase', 529), // 536 S_BOSS_RUN8
  State(SpriteNum.boss, 4, 8, 'A_FaceTarget', 538), // 537 S_BOSS_ATK1
  State(SpriteNum.boss, 5, 8, 'A_FaceTarget', 539), // 538 S_BOSS_ATK2
  State(SpriteNum.boss, 6, 8, 'A_BruisAttack', 529), // 539 S_BOSS_ATK3
  State(SpriteNum.boss, 7, 2, null, 541), // 540 S_BOSS_PAIN
  State(SpriteNum.boss, 7, 2, 'A_Pain', 529), // 541 S_BOSS_PAIN2
  State(SpriteNum.boss, 8, 8, null, 543), // 542 S_BOSS_DIE1
  State(SpriteNum.boss, 9, 8, 'A_Scream', 544), // 543 S_BOSS_DIE2
  State(SpriteNum.boss, 10, 8, null, 545), // 544 S_BOSS_DIE3
  State(SpriteNum.boss, 11, 8, 'A_Fall', 546), // 545 S_BOSS_DIE4
  State(SpriteNum.boss, 12, 8, null, 547), // 546 S_BOSS_DIE5
  State(SpriteNum.boss, 13, 8, null, 548), // 547 S_BOSS_DIE6
  State(SpriteNum.boss, 14, -1, 'A_BossDeath', 0), // 548 S_BOSS_DIE7
  State(SpriteNum.boss, 14, 8, null, 550), // 549 S_BOSS_RAISE1
  State(SpriteNum.boss, 13, 8, null, 551), // 550 S_BOSS_RAISE2
  State(SpriteNum.boss, 12, 8, null, 552), // 551 S_BOSS_RAISE3
  State(SpriteNum.boss, 11, 8, null, 553), // 552 S_BOSS_RAISE4
  State(SpriteNum.boss, 10, 8, null, 554), // 553 S_BOSS_RAISE5
  State(SpriteNum.boss, 9, 8, null, 555), // 554 S_BOSS_RAISE6
  State(SpriteNum.boss, 8, 8, null, 529), // 555 S_BOSS_RAISE7
  State(SpriteNum.bos2, 0, 10, 'A_Look', 557), // 556 S_BOS2_STND
  State(SpriteNum.bos2, 1, 10, 'A_Look', 556), // 557 S_BOS2_STND2
  State(SpriteNum.bos2, 0, 3, 'A_Chase', 559), // 558 S_BOS2_RUN1
  State(SpriteNum.bos2, 0, 3, 'A_Chase', 560), // 559 S_BOS2_RUN2
  State(SpriteNum.bos2, 1, 3, 'A_Chase', 561), // 560 S_BOS2_RUN3
  State(SpriteNum.bos2, 1, 3, 'A_Chase', 562), // 561 S_BOS2_RUN4
  State(SpriteNum.bos2, 2, 3, 'A_Chase', 563), // 562 S_BOS2_RUN5
  State(SpriteNum.bos2, 2, 3, 'A_Chase', 564), // 563 S_BOS2_RUN6
  State(SpriteNum.bos2, 3, 3, 'A_Chase', 565), // 564 S_BOS2_RUN7
  State(SpriteNum.bos2, 3, 3, 'A_Chase', 558), // 565 S_BOS2_RUN8
  State(SpriteNum.bos2, 4, 8, 'A_FaceTarget', 567), // 566 S_BOS2_ATK1
  State(SpriteNum.bos2, 5, 8, 'A_FaceTarget', 568), // 567 S_BOS2_ATK2
  State(SpriteNum.bos2, 6, 8, 'A_BruisAttack', 558), // 568 S_BOS2_ATK3
  State(SpriteNum.bos2, 7, 2, null, 570), // 569 S_BOS2_PAIN
  State(SpriteNum.bos2, 7, 2, 'A_Pain', 558), // 570 S_BOS2_PAIN2
  State(SpriteNum.bos2, 8, 8, null, 572), // 571 S_BOS2_DIE1
  State(SpriteNum.bos2, 9, 8, 'A_Scream', 573), // 572 S_BOS2_DIE2
  State(SpriteNum.bos2, 10, 8, null, 574), // 573 S_BOS2_DIE3
  State(SpriteNum.bos2, 11, 8, 'A_Fall', 575), // 574 S_BOS2_DIE4
  State(SpriteNum.bos2, 12, 8, null, 576), // 575 S_BOS2_DIE5
  State(SpriteNum.bos2, 13, 8, null, 577), // 576 S_BOS2_DIE6
  State(SpriteNum.bos2, 14, -1, null, 0), // 577 S_BOS2_DIE7
  State(SpriteNum.bos2, 14, 8, null, 579), // 578 S_BOS2_RAISE1
  State(SpriteNum.bos2, 13, 8, null, 580), // 579 S_BOS2_RAISE2
  State(SpriteNum.bos2, 12, 8, null, 581), // 580 S_BOS2_RAISE3
  State(SpriteNum.bos2, 11, 8, null, 582), // 581 S_BOS2_RAISE4
  State(SpriteNum.bos2, 10, 8, null, 583), // 582 S_BOS2_RAISE5
  State(SpriteNum.bos2, 9, 8, null, 584), // 583 S_BOS2_RAISE6
  State(SpriteNum.bos2, 8, 8, null, 558), // 584 S_BOS2_RAISE7
  State(SpriteNum.skul, _fb, 10, 'A_Look', 586), // 585 S_SKULL_STND
  State(SpriteNum.skul, 1 | _fb, 10, 'A_Look', 585), // 586 S_SKULL_STND2
  State(SpriteNum.skul, _fb, 6, 'A_Chase', 588), // 587 S_SKULL_RUN1
  State(SpriteNum.skul, 1 | _fb, 6, 'A_Chase', 587), // 588 S_SKULL_RUN2
  State(SpriteNum.skul, 2 | _fb, 10, 'A_FaceTarget', 590), // 589 S_SKULL_ATK1
  State(SpriteNum.skul, 3 | _fb, 4, 'A_SkullAttack', 591), // 590 S_SKULL_ATK2
  State(SpriteNum.skul, 2 | _fb, 4, null, 592), // 591 S_SKULL_ATK3
  State(SpriteNum.skul, 3 | _fb, 4, null, 591), // 592 S_SKULL_ATK4
  State(SpriteNum.skul, 4 | _fb, 3, null, 594), // 593 S_SKULL_PAIN
  State(SpriteNum.skul, 4 | _fb, 3, 'A_Pain', 587), // 594 S_SKULL_PAIN2
  State(SpriteNum.skul, 5 | _fb, 6, null, 596), // 595 S_SKULL_DIE1
  State(SpriteNum.skul, 6 | _fb, 6, 'A_Scream', 597), // 596 S_SKULL_DIE2
  State(SpriteNum.skul, 7 | _fb, 6, null, 598), // 597 S_SKULL_DIE3
  State(SpriteNum.skul, 8 | _fb, 6, 'A_Fall', 599), // 598 S_SKULL_DIE4
  State(SpriteNum.skul, 9, 6, null, 600), // 599 S_SKULL_DIE5
  State(SpriteNum.skul, 10, 6, null, 0), // 600 S_SKULL_DIE6
  State(SpriteNum.spid, 0, 10, 'A_Look', 602), // 601 S_SPID_STND
  State(SpriteNum.spid, 1, 10, 'A_Look', 601), // 602 S_SPID_STND2
  State(SpriteNum.spid, 0, 3, 'A_Metal', 604), // 603 S_SPID_RUN1
  State(SpriteNum.spid, 0, 3, 'A_Chase', 605), // 604 S_SPID_RUN2
  State(SpriteNum.spid, 1, 3, 'A_Chase', 606), // 605 S_SPID_RUN3
  State(SpriteNum.spid, 1, 3, 'A_Chase', 607), // 606 S_SPID_RUN4
  State(SpriteNum.spid, 2, 3, 'A_Metal', 608), // 607 S_SPID_RUN5
  State(SpriteNum.spid, 2, 3, 'A_Chase', 609), // 608 S_SPID_RUN6
  State(SpriteNum.spid, 3, 3, 'A_Chase', 610), // 609 S_SPID_RUN7
  State(SpriteNum.spid, 3, 3, 'A_Chase', 611), // 610 S_SPID_RUN8
  State(SpriteNum.spid, 4, 3, 'A_Metal', 612), // 611 S_SPID_RUN9
  State(SpriteNum.spid, 4, 3, 'A_Chase', 613), // 612 S_SPID_RUN10
  State(SpriteNum.spid, 5, 3, 'A_Chase', 614), // 613 S_SPID_RUN11
  State(SpriteNum.spid, 5, 3, 'A_Chase', 603), // 614 S_SPID_RUN12
  State(SpriteNum.spid, _fb, 20, 'A_FaceTarget', 616), // 615 S_SPID_ATK1
  State(SpriteNum.spid, 6 | _fb, 4, 'A_SPosAttack', 617), // 616 S_SPID_ATK2
  State(SpriteNum.spid, 7 | _fb, 4, 'A_SPosAttack', 618), // 617 S_SPID_ATK3
  State(SpriteNum.spid, 7 | _fb, 1, 'A_SpidRefire', 616), // 618 S_SPID_ATK4
  State(SpriteNum.spid, 8, 3, null, 620), // 619 S_SPID_PAIN
  State(SpriteNum.spid, 8, 3, 'A_Pain', 603), // 620 S_SPID_PAIN2
  State(SpriteNum.spid, 9, 20, 'A_Scream', 622), // 621 S_SPID_DIE1
  State(SpriteNum.spid, 10, 10, 'A_Fall', 623), // 622 S_SPID_DIE2
  State(SpriteNum.spid, 11, 10, null, 624), // 623 S_SPID_DIE3
  State(SpriteNum.spid, 12, 10, null, 625), // 624 S_SPID_DIE4
  State(SpriteNum.spid, 13, 10, null, 626), // 625 S_SPID_DIE5
  State(SpriteNum.spid, 14, 10, null, 627), // 626 S_SPID_DIE6
  State(SpriteNum.spid, 15, 10, null, 628), // 627 S_SPID_DIE7
  State(SpriteNum.spid, 16, 10, null, 629), // 628 S_SPID_DIE8
  State(SpriteNum.spid, 17, 10, null, 630), // 629 S_SPID_DIE9
  State(SpriteNum.spid, 18, 30, null, 631), // 630 S_SPID_DIE10
  State(SpriteNum.spid, 18, -1, 'A_BossDeath', 0), // 631 S_SPID_DIE11
  State(SpriteNum.bspi, 0, 10, 'A_Look', 633), // 632 S_BSPI_STND
  State(SpriteNum.bspi, 1, 10, 'A_Look', 632), // 633 S_BSPI_STND2
  State(SpriteNum.bspi, 0, 20, null, 635), // 634 S_BSPI_SIGHT
  State(SpriteNum.bspi, 0, 3, 'A_BabyMetal', 636), // 635 S_BSPI_RUN1
  State(SpriteNum.bspi, 0, 3, 'A_Chase', 637), // 636 S_BSPI_RUN2
  State(SpriteNum.bspi, 1, 3, 'A_Chase', 638), // 637 S_BSPI_RUN3
  State(SpriteNum.bspi, 1, 3, 'A_Chase', 639), // 638 S_BSPI_RUN4
  State(SpriteNum.bspi, 2, 3, 'A_Chase', 640), // 639 S_BSPI_RUN5
  State(SpriteNum.bspi, 2, 3, 'A_Chase', 641), // 640 S_BSPI_RUN6
  State(SpriteNum.bspi, 3, 3, 'A_BabyMetal', 642), // 641 S_BSPI_RUN7
  State(SpriteNum.bspi, 3, 3, 'A_Chase', 643), // 642 S_BSPI_RUN8
  State(SpriteNum.bspi, 4, 3, 'A_Chase', 644), // 643 S_BSPI_RUN9
  State(SpriteNum.bspi, 4, 3, 'A_Chase', 645), // 644 S_BSPI_RUN10
  State(SpriteNum.bspi, 5, 3, 'A_Chase', 646), // 645 S_BSPI_RUN11
  State(SpriteNum.bspi, 5, 3, 'A_Chase', 635), // 646 S_BSPI_RUN12
  State(SpriteNum.bspi, _fb, 20, 'A_FaceTarget', 648), // 647 S_BSPI_ATK1
  State(SpriteNum.bspi, 6 | _fb, 4, 'A_BspiAttack', 649), // 648 S_BSPI_ATK2
  State(SpriteNum.bspi, 7 | _fb, 4, null, 650), // 649 S_BSPI_ATK3
  State(SpriteNum.bspi, 7 | _fb, 1, 'A_SpidRefire', 648), // 650 S_BSPI_ATK4
  State(SpriteNum.bspi, 8, 3, null, 652), // 651 S_BSPI_PAIN
  State(SpriteNum.bspi, 8, 3, 'A_Pain', 635), // 652 S_BSPI_PAIN2
  State(SpriteNum.bspi, 9, 20, 'A_Scream', 654), // 653 S_BSPI_DIE1
  State(SpriteNum.bspi, 10, 7, 'A_Fall', 655), // 654 S_BSPI_DIE2
  State(SpriteNum.bspi, 11, 7, null, 656), // 655 S_BSPI_DIE3
  State(SpriteNum.bspi, 12, 7, null, 657), // 656 S_BSPI_DIE4
  State(SpriteNum.bspi, 13, 7, null, 658), // 657 S_BSPI_DIE5
  State(SpriteNum.bspi, 14, 7, null, 659), // 658 S_BSPI_DIE6
  State(SpriteNum.bspi, 15, -1, 'A_BossDeath', 0), // 659 S_BSPI_DIE7
  State(SpriteNum.bspi, 15, 5, null, 661), // 660 S_BSPI_RAISE1
  State(SpriteNum.bspi, 14, 5, null, 662), // 661 S_BSPI_RAISE2
  State(SpriteNum.bspi, 13, 5, null, 663), // 662 S_BSPI_RAISE3
  State(SpriteNum.bspi, 12, 5, null, 664), // 663 S_BSPI_RAISE4
  State(SpriteNum.bspi, 11, 5, null, 665), // 664 S_BSPI_RAISE5
  State(SpriteNum.bspi, 10, 5, null, 666), // 665 S_BSPI_RAISE6
  State(SpriteNum.bspi, 9, 5, null, 635), // 666 S_BSPI_RAISE7
  State(SpriteNum.apls, _fb, 5, null, 668), // 667 S_ARACH_PLAZ
  State(SpriteNum.apls, 1 | _fb, 5, null, 667), // 668 S_ARACH_PLAZ2
  State(SpriteNum.apbx, _fb, 5, null, 670), // 669 S_ARACH_PLEX
  State(SpriteNum.apbx, 1 | _fb, 5, null, 671), // 670 S_ARACH_PLEX2
  State(SpriteNum.apbx, 2 | _fb, 5, null, 672), // 671 S_ARACH_PLEX3
  State(SpriteNum.apbx, 3 | _fb, 5, null, 673), // 672 S_ARACH_PLEX4
  State(SpriteNum.apbx, 4 | _fb, 5, null, 0), // 673 S_ARACH_PLEX5
  State(SpriteNum.cybr, 0, 10, 'A_Look', 675), // 674 S_CYBER_STND
  State(SpriteNum.cybr, 1, 10, 'A_Look', 674), // 675 S_CYBER_STND2
  State(SpriteNum.cybr, 0, 3, 'A_Hoof', 677), // 676 S_CYBER_RUN1
  State(SpriteNum.cybr, 0, 3, 'A_Chase', 678), // 677 S_CYBER_RUN2
  State(SpriteNum.cybr, 1, 3, 'A_Chase', 679), // 678 S_CYBER_RUN3
  State(SpriteNum.cybr, 1, 3, 'A_Chase', 680), // 679 S_CYBER_RUN4
  State(SpriteNum.cybr, 2, 3, 'A_Chase', 681), // 680 S_CYBER_RUN5
  State(SpriteNum.cybr, 2, 3, 'A_Chase', 682), // 681 S_CYBER_RUN6
  State(SpriteNum.cybr, 3, 3, 'A_Metal', 683), // 682 S_CYBER_RUN7
  State(SpriteNum.cybr, 3, 3, 'A_Chase', 676), // 683 S_CYBER_RUN8
  State(SpriteNum.cybr, 4, 6, 'A_FaceTarget', 685), // 684 S_CYBER_ATK1
  State(SpriteNum.cybr, 5, 12, 'A_CyberAttack', 686), // 685 S_CYBER_ATK2
  State(SpriteNum.cybr, 4, 12, 'A_FaceTarget', 687), // 686 S_CYBER_ATK3
  State(SpriteNum.cybr, 5, 12, 'A_CyberAttack', 688), // 687 S_CYBER_ATK4
  State(SpriteNum.cybr, 4, 12, 'A_FaceTarget', 689), // 688 S_CYBER_ATK5
  State(SpriteNum.cybr, 5, 12, 'A_CyberAttack', 676), // 689 S_CYBER_ATK6
  State(SpriteNum.cybr, 6, 10, 'A_Pain', 676), // 690 S_CYBER_PAIN
  State(SpriteNum.cybr, 7, 10, null, 692), // 691 S_CYBER_DIE1
  State(SpriteNum.cybr, 8, 10, 'A_Scream', 693), // 692 S_CYBER_DIE2
  State(SpriteNum.cybr, 9, 10, null, 694), // 693 S_CYBER_DIE3
  State(SpriteNum.cybr, 10, 10, null, 695), // 694 S_CYBER_DIE4
  State(SpriteNum.cybr, 11, 10, null, 696), // 695 S_CYBER_DIE5
  State(SpriteNum.cybr, 12, 10, 'A_Fall', 697), // 696 S_CYBER_DIE6
  State(SpriteNum.cybr, 13, 10, null, 698), // 697 S_CYBER_DIE7
  State(SpriteNum.cybr, 14, 10, null, 699), // 698 S_CYBER_DIE8
  State(SpriteNum.cybr, 15, 30, null, 700), // 699 S_CYBER_DIE9
  State(SpriteNum.cybr, 15, -1, 'A_BossDeath', 0), // 700 S_CYBER_DIE10
  State(SpriteNum.pain, 0, 10, 'A_Look', 701), // 701 S_PAIN_STND
  State(SpriteNum.pain, 0, 3, 'A_Chase', 703), // 702 S_PAIN_RUN1
  State(SpriteNum.pain, 0, 3, 'A_Chase', 704), // 703 S_PAIN_RUN2
  State(SpriteNum.pain, 1, 3, 'A_Chase', 705), // 704 S_PAIN_RUN3
  State(SpriteNum.pain, 1, 3, 'A_Chase', 706), // 705 S_PAIN_RUN4
  State(SpriteNum.pain, 2, 3, 'A_Chase', 707), // 706 S_PAIN_RUN5
  State(SpriteNum.pain, 2, 3, 'A_Chase', 702), // 707 S_PAIN_RUN6
  State(SpriteNum.pain, 3, 5, 'A_FaceTarget', 709), // 708 S_PAIN_ATK1
  State(SpriteNum.pain, 4, 5, 'A_FaceTarget', 710), // 709 S_PAIN_ATK2
  State(SpriteNum.pain, 5 | _fb, 5, 'A_FaceTarget', 711), // 710 S_PAIN_ATK3
  State(SpriteNum.pain, 5 | _fb, 0, 'A_PainAttack', 702), // 711 S_PAIN_ATK4
  State(SpriteNum.pain, 6, 6, null, 713), // 712 S_PAIN_PAIN
  State(SpriteNum.pain, 6, 6, 'A_Pain', 702), // 713 S_PAIN_PAIN2
  State(SpriteNum.pain, 7 | _fb, 8, null, 715), // 714 S_PAIN_DIE1
  State(SpriteNum.pain, 8 | _fb, 8, 'A_Scream', 716), // 715 S_PAIN_DIE2
  State(SpriteNum.pain, 9 | _fb, 8, null, 717), // 716 S_PAIN_DIE3
  State(SpriteNum.pain, 10 | _fb, 8, null, 718), // 717 S_PAIN_DIE4
  State(SpriteNum.pain, 11 | _fb, 8, 'A_PainDie', 719), // 718 S_PAIN_DIE5
  State(SpriteNum.pain, 12 | _fb, 8, null, 0), // 719 S_PAIN_DIE6
  State(SpriteNum.pain, 12, 8, null, 721), // 720 S_PAIN_RAISE1
  State(SpriteNum.pain, 11, 8, null, 722), // 721 S_PAIN_RAISE2
  State(SpriteNum.pain, 10, 8, null, 723), // 722 S_PAIN_RAISE3
  State(SpriteNum.pain, 9, 8, null, 724), // 723 S_PAIN_RAISE4
  State(SpriteNum.pain, 8, 8, null, 725), // 724 S_PAIN_RAISE5
  State(SpriteNum.pain, 7, 8, null, 702), // 725 S_PAIN_RAISE6
  State(SpriteNum.sswv, 0, 10, 'A_Look', 727), // 726 S_SSWV_STND
  State(SpriteNum.sswv, 1, 10, 'A_Look', 726), // 727 S_SSWV_STND2
  State(SpriteNum.sswv, 0, 3, 'A_Chase', 729), // 728 S_SSWV_RUN1
  State(SpriteNum.sswv, 0, 3, 'A_Chase', 730), // 729 S_SSWV_RUN2
  State(SpriteNum.sswv, 1, 3, 'A_Chase', 731), // 730 S_SSWV_RUN3
  State(SpriteNum.sswv, 1, 3, 'A_Chase', 732), // 731 S_SSWV_RUN4
  State(SpriteNum.sswv, 2, 3, 'A_Chase', 733), // 732 S_SSWV_RUN5
  State(SpriteNum.sswv, 2, 3, 'A_Chase', 734), // 733 S_SSWV_RUN6
  State(SpriteNum.sswv, 3, 3, 'A_Chase', 735), // 734 S_SSWV_RUN7
  State(SpriteNum.sswv, 3, 3, 'A_Chase', 728), // 735 S_SSWV_RUN8
  State(SpriteNum.sswv, 4, 10, 'A_FaceTarget', 737), // 736 S_SSWV_ATK1
  State(SpriteNum.sswv, 5, 10, 'A_FaceTarget', 738), // 737 S_SSWV_ATK2
  State(SpriteNum.sswv, 6 | _fb, 4, 'A_CPosAttack', 739), // 738 S_SSWV_ATK3
  State(SpriteNum.sswv, 5, 6, 'A_FaceTarget', 740), // 739 S_SSWV_ATK4
  State(SpriteNum.sswv, 6 | _fb, 4, 'A_CPosAttack', 741), // 740 S_SSWV_ATK5
  State(SpriteNum.sswv, 5, 1, 'A_CPosRefire', 737), // 741 S_SSWV_ATK6
  State(SpriteNum.sswv, 7, 3, null, 743), // 742 S_SSWV_PAIN
  State(SpriteNum.sswv, 7, 3, 'A_Pain', 728), // 743 S_SSWV_PAIN2
  State(SpriteNum.sswv, 8, 5, null, 745), // 744 S_SSWV_DIE1
  State(SpriteNum.sswv, 9, 5, 'A_Scream', 746), // 745 S_SSWV_DIE2
  State(SpriteNum.sswv, 10, 5, 'A_Fall', 747), // 746 S_SSWV_DIE3
  State(SpriteNum.sswv, 11, 5, null, 748), // 747 S_SSWV_DIE4
  State(SpriteNum.sswv, 12, -1, null, 0), // 748 S_SSWV_DIE5
  State(SpriteNum.sswv, 13, 5, null, 750), // 749 S_SSWV_XDIE1
  State(SpriteNum.sswv, 14, 5, 'A_XScream', 751), // 750 S_SSWV_XDIE2
  State(SpriteNum.sswv, 15, 5, 'A_Fall', 752), // 751 S_SSWV_XDIE3
  State(SpriteNum.sswv, 16, 5, null, 753), // 752 S_SSWV_XDIE4
  State(SpriteNum.sswv, 17, 5, null, 754), // 753 S_SSWV_XDIE5
  State(SpriteNum.sswv, 18, 5, null, 755), // 754 S_SSWV_XDIE6
  State(SpriteNum.sswv, 19, 5, null, 756), // 755 S_SSWV_XDIE7
  State(SpriteNum.sswv, 20, 5, null, 757), // 756 S_SSWV_XDIE8
  State(SpriteNum.sswv, 21, -1, null, 0), // 757 S_SSWV_XDIE9
  State(SpriteNum.sswv, 12, 5, null, 759), // 758 S_SSWV_RAISE1
  State(SpriteNum.sswv, 11, 5, null, 760), // 759 S_SSWV_RAISE2
  State(SpriteNum.sswv, 10, 5, null, 761), // 760 S_SSWV_RAISE3
  State(SpriteNum.sswv, 9, 5, null, 762), // 761 S_SSWV_RAISE4
  State(SpriteNum.sswv, 8, 5, null, 728), // 762 S_SSWV_RAISE5
  State(SpriteNum.keen, 0, -1, null, 763), // 763 S_KEENSTND
  State(SpriteNum.keen, 0, 6, null, 765), // 764 S_COMMKEEN
  State(SpriteNum.keen, 1, 6, null, 766), // 765 S_COMMKEEN2
  State(SpriteNum.keen, 2, 6, 'A_Scream', 767), // 766 S_COMMKEEN3
  State(SpriteNum.keen, 3, 6, null, 768), // 767 S_COMMKEEN4
  State(SpriteNum.keen, 4, 6, null, 769), // 768 S_COMMKEEN5
  State(SpriteNum.keen, 5, 6, null, 770), // 769 S_COMMKEEN6
  State(SpriteNum.keen, 6, 6, null, 771), // 770 S_COMMKEEN7
  State(SpriteNum.keen, 7, 6, null, 772), // 771 S_COMMKEEN8
  State(SpriteNum.keen, 8, 6, null, 773), // 772 S_COMMKEEN9
  State(SpriteNum.keen, 9, 6, null, 774), // 773 S_COMMKEEN10
  State(SpriteNum.keen, 10, 6, 'A_KeenDie', 775), // 774 S_COMMKEEN11
  State(SpriteNum.keen, 11, -1, null, 0), // 775 S_COMMKEEN12
  State(SpriteNum.keen, 12, 4, null, 777), // 776 S_KEENPAIN
  State(SpriteNum.keen, 12, 8, 'A_Pain', 763), // 777 S_KEENPAIN2
  State(SpriteNum.bbrn, 0, -1, null, 0), // 778 S_BRAIN
  State(SpriteNum.bbrn, 1, 36, 'A_BrainPain', 778), // 779 S_BRAIN_PAIN
  State(SpriteNum.bbrn, 0, 100, 'A_BrainScream', 781), // 780 S_BRAIN_DIE1
  State(SpriteNum.bbrn, 0, 10, null, 782), // 781 S_BRAIN_DIE2
  State(SpriteNum.bbrn, 0, 10, null, 783), // 782 S_BRAIN_DIE3
  State(SpriteNum.bbrn, 0, -1, 'A_BrainDie', 0), // 783 S_BRAIN_DIE4
  State(SpriteNum.sswv, 0, 10, 'A_Look', 784), // 784 S_BRAINEYE
  State(SpriteNum.sswv, 0, 181, 'A_BrainAwake', 786), // 785 S_BRAINEYESEE
  State(SpriteNum.sswv, 0, 150, 'A_BrainSpit', 786), // 786 S_BRAINEYE1
  State(SpriteNum.bosf, _fb, 3, 'A_SpawnSound', 788), // 787 S_SPAWN1
  State(SpriteNum.bosf, 1 | _fb, 3, 'A_SpawnFly', 789), // 788 S_SPAWN2
  State(SpriteNum.bosf, 2 | _fb, 3, 'A_SpawnFly', 790), // 789 S_SPAWN3
  State(SpriteNum.bosf, 3 | _fb, 3, 'A_SpawnFly', 787), // 790 S_SPAWN4
  State(SpriteNum.fire, _fb, 4, 'A_Fire', 792), // 791 S_SPAWNFIRE1
  State(SpriteNum.fire, 1 | _fb, 4, 'A_Fire', 793), // 792 S_SPAWNFIRE2
  State(SpriteNum.fire, 2 | _fb, 4, 'A_Fire', 794), // 793 S_SPAWNFIRE3
  State(SpriteNum.fire, 3 | _fb, 4, 'A_Fire', 795), // 794 S_SPAWNFIRE4
  State(SpriteNum.fire, 4 | _fb, 4, 'A_Fire', 796), // 795 S_SPAWNFIRE5
  State(SpriteNum.fire, 5 | _fb, 4, 'A_Fire', 797), // 796 S_SPAWNFIRE6
  State(SpriteNum.fire, 6 | _fb, 4, 'A_Fire', 798), // 797 S_SPAWNFIRE7
  State(SpriteNum.fire, 7 | _fb, 4, 'A_Fire', 0), // 798 S_SPAWNFIRE8
  State(SpriteNum.misl, 1 | _fb, 10, null, 800), // 799 S_BRAINEXPLODE1
  State(SpriteNum.misl, 2 | _fb, 10, null, 801), // 800 S_BRAINEXPLODE2
  State(SpriteNum.misl, 3 | _fb, 10, 'A_BrainExplode', 0), // 801 S_BRAINEXPLODE3
  State(SpriteNum.arm1, 0, 6, null, 803), // 802 S_ARM1
  State(SpriteNum.arm1, 1 | _fb, 7, null, 802), // 803 S_ARM1A
  State(SpriteNum.arm2, 0, 6, null, 805), // 804 S_ARM2
  State(SpriteNum.arm2, 1 | _fb, 6, null, 804), // 805 S_ARM2A
  State(SpriteNum.bar1, 0, 6, null, 807), // 806 S_BAR1
  State(SpriteNum.bar1, 1, 6, null, 806), // 807 S_BAR2
  State(SpriteNum.bexp, _fb, 5, null, 809), // 808 S_BEXP
  State(SpriteNum.bexp, 1 | _fb, 5, 'A_Scream', 810), // 809 S_BEXP2
  State(SpriteNum.bexp, 2 | _fb, 5, null, 811), // 810 S_BEXP3
  State(SpriteNum.bexp, 3 | _fb, 10, 'A_Explode', 812), // 811 S_BEXP4
  State(SpriteNum.bexp, 4 | _fb, 10, null, 0), // 812 S_BEXP5
  State(SpriteNum.fcan, _fb, 4, null, 814), // 813 S_BBAR1
  State(SpriteNum.fcan, 1 | _fb, 4, null, 815), // 814 S_BBAR2
  State(SpriteNum.fcan, 2 | _fb, 4, null, 813), // 815 S_BBAR3
  State(SpriteNum.bon1, 0, 6, null, 817), // 816 S_BON1
  State(SpriteNum.bon1, 1, 6, null, 818), // 817 S_BON1A
  State(SpriteNum.bon1, 2, 6, null, 819), // 818 S_BON1B
  State(SpriteNum.bon1, 3, 6, null, 820), // 819 S_BON1C
  State(SpriteNum.bon1, 2, 6, null, 821), // 820 S_BON1D
  State(SpriteNum.bon1, 1, 6, null, 816), // 821 S_BON1E
  State(SpriteNum.bon2, 0, 6, null, 823), // 822 S_BON2
  State(SpriteNum.bon2, 1, 6, null, 824), // 823 S_BON2A
  State(SpriteNum.bon2, 2, 6, null, 825), // 824 S_BON2B
  State(SpriteNum.bon2, 3, 6, null, 826), // 825 S_BON2C
  State(SpriteNum.bon2, 2, 6, null, 827), // 826 S_BON2D
  State(SpriteNum.bon2, 1, 6, null, 822), // 827 S_BON2E
  State(SpriteNum.bkey, 0, 10, null, 829), // 828 S_BKEY
  State(SpriteNum.bkey, 1 | _fb, 10, null, 828), // 829 S_BKEY2
  State(SpriteNum.rkey, 0, 10, null, 831), // 830 S_RKEY
  State(SpriteNum.rkey, 1 | _fb, 10, null, 830), // 831 S_RKEY2
  State(SpriteNum.ykey, 0, 10, null, 833), // 832 S_YKEY
  State(SpriteNum.ykey, 1 | _fb, 10, null, 832), // 833 S_YKEY2
  State(SpriteNum.bsku, 0, 10, null, 835), // 834 S_BSKULL
  State(SpriteNum.bsku, 1 | _fb, 10, null, 834), // 835 S_BSKULL2
  State(SpriteNum.rsku, 0, 10, null, 837), // 836 S_RSKULL
  State(SpriteNum.rsku, 1 | _fb, 10, null, 836), // 837 S_RSKULL2
  State(SpriteNum.ysku, 0, 10, null, 839), // 838 S_YSKULL
  State(SpriteNum.ysku, 1 | _fb, 10, null, 838), // 839 S_YSKULL2
  State(SpriteNum.stim, 0, -1, null, 0), // 840 S_STIM
  State(SpriteNum.medi, 0, -1, null, 0), // 841 S_MEDI
  State(SpriteNum.soul, _fb, 6, null, 843), // 842 S_SOUL
  State(SpriteNum.soul, 1 | _fb, 6, null, 844), // 843 S_SOUL2
  State(SpriteNum.soul, 2 | _fb, 6, null, 845), // 844 S_SOUL3
  State(SpriteNum.soul, 3 | _fb, 6, null, 846), // 845 S_SOUL4
  State(SpriteNum.soul, 2 | _fb, 6, null, 847), // 846 S_SOUL5
  State(SpriteNum.soul, 1 | _fb, 6, null, 842), // 847 S_SOUL6
  State(SpriteNum.pinv, _fb, 6, null, 849), // 848 S_PINV
  State(SpriteNum.pinv, 1 | _fb, 6, null, 850), // 849 S_PINV2
  State(SpriteNum.pinv, 2 | _fb, 6, null, 851), // 850 S_PINV3
  State(SpriteNum.pinv, 3 | _fb, 6, null, 848), // 851 S_PINV4
  State(SpriteNum.pstr, _fb, -1, null, 0), // 852 S_PSTR
  State(SpriteNum.pins, _fb, 6, null, 854), // 853 S_PINS
  State(SpriteNum.pins, 1 | _fb, 6, null, 855), // 854 S_PINS2
  State(SpriteNum.pins, 2 | _fb, 6, null, 856), // 855 S_PINS3
  State(SpriteNum.pins, 3 | _fb, 6, null, 853), // 856 S_PINS4
  State(SpriteNum.mega, _fb, 6, null, 858), // 857 S_MEGA
  State(SpriteNum.mega, 1 | _fb, 6, null, 859), // 858 S_MEGA2
  State(SpriteNum.mega, 2 | _fb, 6, null, 860), // 859 S_MEGA3
  State(SpriteNum.mega, 3 | _fb, 6, null, 857), // 860 S_MEGA4
  State(SpriteNum.suit, _fb, -1, null, 0), // 861 S_SUIT
  State(SpriteNum.pmap, _fb, 6, null, 863), // 862 S_PMAP
  State(SpriteNum.pmap, 1 | _fb, 6, null, 864), // 863 S_PMAP2
  State(SpriteNum.pmap, 2 | _fb, 6, null, 865), // 864 S_PMAP3
  State(SpriteNum.pmap, 3 | _fb, 6, null, 866), // 865 S_PMAP4
  State(SpriteNum.pmap, 2 | _fb, 6, null, 867), // 866 S_PMAP5
  State(SpriteNum.pmap, 1 | _fb, 6, null, 862), // 867 S_PMAP6
  State(SpriteNum.pvis, _fb, 6, null, 869), // 868 S_PVIS
  State(SpriteNum.pvis, 1, 6, null, 868), // 869 S_PVIS2
  State(SpriteNum.clip, 0, -1, null, 0), // 870 S_CLIP
  State(SpriteNum.ammo, 0, -1, null, 0), // 871 S_AMMO
  State(SpriteNum.rock, 0, -1, null, 0), // 872 S_ROCK
  State(SpriteNum.brok, 0, -1, null, 0), // 873 S_BROK
  State(SpriteNum.cell, 0, -1, null, 0), // 874 S_CELL
  State(SpriteNum.celp, 0, -1, null, 0), // 875 S_CELP
  State(SpriteNum.shel, 0, -1, null, 0), // 876 S_SHEL
  State(SpriteNum.sbox, 0, -1, null, 0), // 877 S_SBOX
  State(SpriteNum.bpak, 0, -1, null, 0), // 878 S_BPAK
  State(SpriteNum.bfug, 0, -1, null, 0), // 879 S_BFUG
  State(SpriteNum.mgun, 0, -1, null, 0), // 880 S_MGUN
  State(SpriteNum.csaw, 0, -1, null, 0), // 881 S_CSAW
  State(SpriteNum.laun, 0, -1, null, 0), // 882 S_LAUN
  State(SpriteNum.plas, 0, -1, null, 0), // 883 S_PLAS
  State(SpriteNum.shot, 0, -1, null, 0), // 884 S_SHOT
  State(SpriteNum.sgn2, 0, -1, null, 0), // 885 S_SHOT2
  State(SpriteNum.colu, _fb, -1, null, 0), // 886 S_COLU
  State(SpriteNum.smt2, 0, -1, null, 0), // 887 S_STALAG
  State(SpriteNum.gor1, 0, 10, null, 889), // 888 S_BLOODYTWITCH
  State(SpriteNum.gor1, 1, 15, null, 890), // 889 S_BLOODYTWITCH2
  State(SpriteNum.gor1, 2, 8, null, 891), // 890 S_BLOODYTWITCH3
  State(SpriteNum.gor1, 1, 6, null, 888), // 891 S_BLOODYTWITCH4
  State(SpriteNum.play, 13, -1, null, 0), // 892 S_DEADTORSO
  State(SpriteNum.play, 18, -1, null, 0), // 893 S_DEADBOTTOM
  State(SpriteNum.pol2, 0, -1, null, 0), // 894 S_HEADSONSTICK
  State(SpriteNum.pol5, 0, -1, null, 0), // 895 S_GIBS
  State(SpriteNum.pol4, 0, -1, null, 0), // 896 S_HEADONASTICK
  State(SpriteNum.pol3, _fb, 6, null, 898), // 897 S_HEADCANDLES
  State(SpriteNum.pol3, 1 | _fb, 6, null, 897), // 898 S_HEADCANDLES2
  State(SpriteNum.pol1, 0, -1, null, 0), // 899 S_DEADSTICK
  State(SpriteNum.pol6, 0, 6, null, 901), // 900 S_LIVESTICK
  State(SpriteNum.pol6, 1, 8, null, 900), // 901 S_LIVESTICK2
  State(SpriteNum.gor2, 0, -1, null, 0), // 902 S_MEAT2
  State(SpriteNum.gor3, 0, -1, null, 0), // 903 S_MEAT3
  State(SpriteNum.gor4, 0, -1, null, 0), // 904 S_MEAT4
  State(SpriteNum.gor5, 0, -1, null, 0), // 905 S_MEAT5
  State(SpriteNum.smit, 0, -1, null, 0), // 906 S_STALAGTITE
  State(SpriteNum.col1, 0, -1, null, 0), // 907 S_TALLGRNCOL
  State(SpriteNum.col2, 0, -1, null, 0), // 908 S_SHRTGRNCOL
  State(SpriteNum.col3, 0, -1, null, 0), // 909 S_TALLREDCOL
  State(SpriteNum.col4, 0, -1, null, 0), // 910 S_SHRTREDCOL
  State(SpriteNum.cand, _fb, -1, null, 0), // 911 S_CANDLESTIK
  State(SpriteNum.cbra, _fb, -1, null, 0), // 912 S_CANDELABRA
  State(SpriteNum.col6, 0, -1, null, 0), // 913 S_SKULLCOL
  State(SpriteNum.tre1, 0, -1, null, 0), // 914 S_TORCHTREE
  State(SpriteNum.tre2, 0, -1, null, 0), // 915 S_BIGTREE
  State(SpriteNum.elec, 0, -1, null, 0), // 916 S_TECHPILLAR
  State(SpriteNum.ceye, _fb, 6, null, 918), // 917 S_EVILEYE
  State(SpriteNum.ceye, 1 | _fb, 6, null, 919), // 918 S_EVILEYE2
  State(SpriteNum.ceye, 2 | _fb, 6, null, 920), // 919 S_EVILEYE3
  State(SpriteNum.ceye, 1 | _fb, 6, null, 917), // 920 S_EVILEYE4
  State(SpriteNum.fsku, _fb, 6, null, 922), // 921 S_FLOATSKULL
  State(SpriteNum.fsku, 1 | _fb, 6, null, 923), // 922 S_FLOATSKULL2
  State(SpriteNum.fsku, 2 | _fb, 6, null, 921), // 923 S_FLOATSKULL3
  State(SpriteNum.col5, 0, 14, null, 925), // 924 S_HEARTCOL
  State(SpriteNum.col5, 1, 14, null, 924), // 925 S_HEARTCOL2
  State(SpriteNum.tblu, _fb, 4, null, 927), // 926 S_BLUETORCH
  State(SpriteNum.tblu, 1 | _fb, 4, null, 928), // 927 S_BLUETORCH2
  State(SpriteNum.tblu, 2 | _fb, 4, null, 929), // 928 S_BLUETORCH3
  State(SpriteNum.tblu, 3 | _fb, 4, null, 926), // 929 S_BLUETORCH4
  State(SpriteNum.tgrn, _fb, 4, null, 931), // 930 S_GREENTORCH
  State(SpriteNum.tgrn, 1 | _fb, 4, null, 932), // 931 S_GREENTORCH2
  State(SpriteNum.tgrn, 2 | _fb, 4, null, 933), // 932 S_GREENTORCH3
  State(SpriteNum.tgrn, 3 | _fb, 4, null, 930), // 933 S_GREENTORCH4
  State(SpriteNum.tred, _fb, 4, null, 935), // 934 S_REDTORCH
  State(SpriteNum.tred, 1 | _fb, 4, null, 936), // 935 S_REDTORCH2
  State(SpriteNum.tred, 2 | _fb, 4, null, 937), // 936 S_REDTORCH3
  State(SpriteNum.tred, 3 | _fb, 4, null, 934), // 937 S_REDTORCH4
  State(SpriteNum.smbt, _fb, 4, null, 939), // 938 S_BTORCHSHRT
  State(SpriteNum.smbt, 1 | _fb, 4, null, 940), // 939 S_BTORCHSHRT2
  State(SpriteNum.smbt, 2 | _fb, 4, null, 941), // 940 S_BTORCHSHRT3
  State(SpriteNum.smbt, 3 | _fb, 4, null, 938), // 941 S_BTORCHSHRT4
  State(SpriteNum.smgt, _fb, 4, null, 943), // 942 S_GTORCHSHRT
  State(SpriteNum.smgt, 1 | _fb, 4, null, 944), // 943 S_GTORCHSHRT2
  State(SpriteNum.smgt, 2 | _fb, 4, null, 945), // 944 S_GTORCHSHRT3
  State(SpriteNum.smgt, 3 | _fb, 4, null, 942), // 945 S_GTORCHSHRT4
  State(SpriteNum.smrt, _fb, 4, null, 947), // 946 S_RTORCHSHRT
  State(SpriteNum.smrt, 1 | _fb, 4, null, 948), // 947 S_RTORCHSHRT2
  State(SpriteNum.smrt, 2 | _fb, 4, null, 949), // 948 S_RTORCHSHRT3
  State(SpriteNum.smrt, 3 | _fb, 4, null, 946), // 949 S_RTORCHSHRT4
  State(SpriteNum.hdb1, 0, -1, null, 0), // 950 S_HANGNOGUTS
  State(SpriteNum.hdb2, 0, -1, null, 0), // 951 S_HANGBNOBRAIN
  State(SpriteNum.hdb3, 0, -1, null, 0), // 952 S_HANGTLOOKDN
  State(SpriteNum.hdb4, 0, -1, null, 0), // 953 S_HANGTSKULL
  State(SpriteNum.hdb5, 0, -1, null, 0), // 954 S_HANGTLOOKUP
  State(SpriteNum.hdb6, 0, -1, null, 0), // 955 S_HANGTNOBRAIN
  State(SpriteNum.pob1, 0, -1, null, 0), // 956 S_COLONGIBS
  State(SpriteNum.pob2, 0, -1, null, 0), // 957 S_SMALLPOOL
  State(SpriteNum.brs1, 0, -1, null, 0), // 958 S_BRAINSTEM
  State(SpriteNum.tlmp, _fb, 4, null, 960), // 959 S_TECHLAMP
  State(SpriteNum.tlmp, 1 | _fb, 4, null, 961), // 960 S_TECHLAMP2
  State(SpriteNum.tlmp, 2 | _fb, 4, null, 962), // 961 S_TECHLAMP3
  State(SpriteNum.tlmp, 3 | _fb, 4, null, 959), // 962 S_TECHLAMP4
  State(SpriteNum.tlp2, _fb, 4, null, 964), // 963 S_TECH2LAMP
  State(SpriteNum.tlp2, 1 | _fb, 4, null, 965), // 964 S_TECH2LAMP2
  State(SpriteNum.tlp2, 2 | _fb, 4, null, 966), // 965 S_TECH2LAMP3
  State(SpriteNum.tlp2, 3 | _fb, 4, null, 963), // 966 S_TECH2LAMP4
];

/// mobjinfo[], vanilla info.c. Indexed by mobjtype_t ordinal (Mt.*).
const List<MobjInfo> mobjInfo = <MobjInfo>[
  MobjInfo( // 0 MT_PLAYER
    doomedNum: -1,
    spawnState: 149,
    spawnHealth: 100,
    seeState: 150,
    seeSound: 0,
    reactionTime: 0,
    attackSound: 0,
    painState: 156,
    painChance: 255,
    painSound: 25,
    meleeState: 0,
    missileState: 154,
    deathState: 158,
    xdeathState: 165,
    deathSound: 57,
    speed: 0,
    radius: 16 << 16,
    height: 56 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSolid | mfShootable | mfDropOff | mfPickup | mfNotDeathmatch,
    raiseState: 0,
  ),
  MobjInfo( // 1 MT_POSSESSED
    doomedNum: 3004,
    spawnState: 174,
    spawnHealth: 20,
    seeState: 176,
    seeSound: 36,
    reactionTime: 8,
    attackSound: 1,
    painState: 187,
    painChance: 200,
    painSound: 27,
    meleeState: 0,
    missileState: 184,
    deathState: 189,
    xdeathState: 194,
    deathSound: 59,
    speed: 8,
    radius: 20 << 16,
    height: 56 << 16,
    mass: 100,
    damage: 0,
    activeSound: 75,
    flags: mfSolid | mfShootable | mfCountKill,
    raiseState: 203,
  ),
  MobjInfo( // 2 MT_SHOTGUY
    doomedNum: 9,
    spawnState: 207,
    spawnHealth: 30,
    seeState: 209,
    seeSound: 37,
    reactionTime: 8,
    attackSound: 0,
    painState: 220,
    painChance: 170,
    painSound: 27,
    meleeState: 0,
    missileState: 217,
    deathState: 222,
    xdeathState: 227,
    deathSound: 60,
    speed: 8,
    radius: 20 << 16,
    height: 56 << 16,
    mass: 100,
    damage: 0,
    activeSound: 75,
    flags: mfSolid | mfShootable | mfCountKill,
    raiseState: 236,
  ),
  MobjInfo( // 3 MT_VILE
    doomedNum: 64,
    spawnState: 241,
    spawnHealth: 700,
    seeState: 243,
    seeSound: 48,
    reactionTime: 8,
    attackSound: 0,
    painState: 269,
    painChance: 10,
    painSound: 28,
    meleeState: 0,
    missileState: 255,
    deathState: 271,
    xdeathState: 0,
    deathSound: 71,
    speed: 15,
    radius: 20 << 16,
    height: 56 << 16,
    mass: 500,
    damage: 0,
    activeSound: 80,
    flags: mfSolid | mfShootable | mfCountKill,
    raiseState: 0,
  ),
  MobjInfo( // 4 MT_FIRE
    doomedNum: -1,
    spawnState: 281,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfNoBlockmap | mfNoGravity,
    raiseState: 0,
  ),
  MobjInfo( // 5 MT_UNDEAD
    doomedNum: 66,
    spawnState: 321,
    spawnHealth: 300,
    seeState: 323,
    seeSound: 106,
    reactionTime: 8,
    attackSound: 0,
    painState: 343,
    painChance: 100,
    painSound: 27,
    meleeState: 335,
    missileState: 339,
    deathState: 345,
    xdeathState: 0,
    deathSound: 74,
    speed: 10,
    radius: 20 << 16,
    height: 56 << 16,
    mass: 500,
    damage: 0,
    activeSound: 105,
    flags: mfSolid | mfShootable | mfCountKill,
    raiseState: 351,
  ),
  MobjInfo( // 6 MT_TRACER
    doomedNum: -1,
    spawnState: 316,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 107,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 318,
    xdeathState: 0,
    deathSound: 82,
    speed: 10 << 16,
    radius: 11 << 16,
    height: 8 << 16,
    mass: 100,
    damage: 10,
    activeSound: 0,
    flags: mfNoBlockmap | mfMissile | mfDropOff | mfNoGravity,
    raiseState: 0,
  ),
  MobjInfo( // 7 MT_SMOKE
    doomedNum: -1,
    spawnState: 311,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfNoBlockmap | mfNoGravity,
    raiseState: 0,
  ),
  MobjInfo( // 8 MT_FATSO
    doomedNum: 67,
    spawnState: 362,
    spawnHealth: 600,
    seeState: 364,
    seeSound: 49,
    reactionTime: 8,
    attackSound: 0,
    painState: 386,
    painChance: 80,
    painSound: 29,
    meleeState: 0,
    missileState: 376,
    deathState: 388,
    xdeathState: 0,
    deathSound: 100,
    speed: 8,
    radius: 48 << 16,
    height: 64 << 16,
    mass: 1000,
    damage: 0,
    activeSound: 75,
    flags: mfSolid | mfShootable | mfCountKill,
    raiseState: 398,
  ),
  MobjInfo( // 9 MT_FATSHOT
    doomedNum: -1,
    spawnState: 357,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 16,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 359,
    xdeathState: 0,
    deathSound: 17,
    speed: 20 << 16,
    radius: 6 << 16,
    height: 8 << 16,
    mass: 100,
    damage: 8,
    activeSound: 0,
    flags: mfNoBlockmap | mfMissile | mfDropOff | mfNoGravity,
    raiseState: 0,
  ),
  MobjInfo( // 10 MT_CHAINGUY
    doomedNum: 65,
    spawnState: 406,
    spawnHealth: 70,
    seeState: 408,
    seeSound: 37,
    reactionTime: 8,
    attackSound: 0,
    painState: 420,
    painChance: 170,
    painSound: 27,
    meleeState: 0,
    missileState: 416,
    deathState: 422,
    xdeathState: 429,
    deathSound: 60,
    speed: 8,
    radius: 20 << 16,
    height: 56 << 16,
    mass: 100,
    damage: 0,
    activeSound: 75,
    flags: mfSolid | mfShootable | mfCountKill,
    raiseState: 435,
  ),
  MobjInfo( // 11 MT_TROOP
    doomedNum: 3001,
    spawnState: 442,
    spawnHealth: 60,
    seeState: 444,
    seeSound: 39,
    reactionTime: 8,
    attackSound: 0,
    painState: 455,
    painChance: 200,
    painSound: 27,
    meleeState: 452,
    missileState: 452,
    deathState: 457,
    xdeathState: 462,
    deathSound: 62,
    speed: 8,
    radius: 20 << 16,
    height: 56 << 16,
    mass: 100,
    damage: 0,
    activeSound: 76,
    flags: mfSolid | mfShootable | mfCountKill,
    raiseState: 470,
  ),
  MobjInfo( // 12 MT_SERGEANT
    doomedNum: 3002,
    spawnState: 475,
    spawnHealth: 150,
    seeState: 477,
    seeSound: 41,
    reactionTime: 8,
    attackSound: 52,
    painState: 488,
    painChance: 180,
    painSound: 26,
    meleeState: 485,
    missileState: 0,
    deathState: 490,
    xdeathState: 0,
    deathSound: 64,
    speed: 10,
    radius: 30 << 16,
    height: 56 << 16,
    mass: 400,
    damage: 0,
    activeSound: 77,
    flags: mfSolid | mfShootable | mfCountKill,
    raiseState: 496,
  ),
  MobjInfo( // 13 MT_SHADOWS
    doomedNum: 58,
    spawnState: 475,
    spawnHealth: 150,
    seeState: 477,
    seeSound: 41,
    reactionTime: 8,
    attackSound: 52,
    painState: 488,
    painChance: 180,
    painSound: 26,
    meleeState: 485,
    missileState: 0,
    deathState: 490,
    xdeathState: 0,
    deathSound: 64,
    speed: 10,
    radius: 30 << 16,
    height: 56 << 16,
    mass: 400,
    damage: 0,
    activeSound: 77,
    flags: mfSolid | mfShootable | mfShadow | mfCountKill,
    raiseState: 496,
  ),
  MobjInfo( // 14 MT_HEAD
    doomedNum: 3005,
    spawnState: 502,
    spawnHealth: 400,
    seeState: 503,
    seeSound: 42,
    reactionTime: 8,
    attackSound: 0,
    painState: 507,
    painChance: 128,
    painSound: 26,
    meleeState: 0,
    missileState: 504,
    deathState: 510,
    xdeathState: 0,
    deathSound: 65,
    speed: 8,
    radius: 31 << 16,
    height: 56 << 16,
    mass: 400,
    damage: 0,
    activeSound: 77,
    flags: mfSolid | mfShootable | mfFloat | mfNoGravity | mfCountKill,
    raiseState: 516,
  ),
  MobjInfo( // 15 MT_BRUISER
    doomedNum: 3003,
    spawnState: 527,
    spawnHealth: 1000,
    seeState: 529,
    seeSound: 43,
    reactionTime: 8,
    attackSound: 0,
    painState: 540,
    painChance: 50,
    painSound: 26,
    meleeState: 537,
    missileState: 537,
    deathState: 542,
    xdeathState: 0,
    deathSound: 67,
    speed: 8,
    radius: 24 << 16,
    height: 64 << 16,
    mass: 1000,
    damage: 0,
    activeSound: 77,
    flags: mfSolid | mfShootable | mfCountKill,
    raiseState: 549,
  ),
  MobjInfo( // 16 MT_BRUISERSHOT
    doomedNum: -1,
    spawnState: 522,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 16,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 524,
    xdeathState: 0,
    deathSound: 17,
    speed: 15 << 16,
    radius: 6 << 16,
    height: 8 << 16,
    mass: 100,
    damage: 8,
    activeSound: 0,
    flags: mfNoBlockmap | mfMissile | mfDropOff | mfNoGravity,
    raiseState: 0,
  ),
  MobjInfo( // 17 MT_KNIGHT
    doomedNum: 69,
    spawnState: 556,
    spawnHealth: 500,
    seeState: 558,
    seeSound: 47,
    reactionTime: 8,
    attackSound: 0,
    painState: 569,
    painChance: 50,
    painSound: 26,
    meleeState: 566,
    missileState: 566,
    deathState: 571,
    xdeathState: 0,
    deathSound: 72,
    speed: 8,
    radius: 24 << 16,
    height: 64 << 16,
    mass: 1000,
    damage: 0,
    activeSound: 77,
    flags: mfSolid | mfShootable | mfCountKill,
    raiseState: 578,
  ),
  MobjInfo( // 18 MT_SKULL
    doomedNum: 3006,
    spawnState: 585,
    spawnHealth: 100,
    seeState: 587,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 51,
    painState: 593,
    painChance: 256,
    painSound: 26,
    meleeState: 0,
    missileState: 589,
    deathState: 595,
    xdeathState: 0,
    deathSound: 17,
    speed: 8,
    radius: 16 << 16,
    height: 56 << 16,
    mass: 50,
    damage: 3,
    activeSound: 77,
    flags: mfSolid | mfShootable | mfFloat | mfNoGravity,
    raiseState: 0,
  ),
  MobjInfo( // 19 MT_SPIDER
    doomedNum: 7,
    spawnState: 601,
    spawnHealth: 3000,
    seeState: 603,
    seeSound: 45,
    reactionTime: 8,
    attackSound: 2,
    painState: 619,
    painChance: 40,
    painSound: 26,
    meleeState: 0,
    missileState: 615,
    deathState: 621,
    xdeathState: 0,
    deathSound: 69,
    speed: 12,
    radius: 128 << 16,
    height: 100 << 16,
    mass: 1000,
    damage: 0,
    activeSound: 77,
    flags: mfSolid | mfShootable | mfCountKill,
    raiseState: 0,
  ),
  MobjInfo( // 20 MT_BABY
    doomedNum: 68,
    spawnState: 632,
    spawnHealth: 500,
    seeState: 634,
    seeSound: 46,
    reactionTime: 8,
    attackSound: 0,
    painState: 651,
    painChance: 128,
    painSound: 26,
    meleeState: 0,
    missileState: 647,
    deathState: 653,
    xdeathState: 0,
    deathSound: 70,
    speed: 12,
    radius: 64 << 16,
    height: 64 << 16,
    mass: 600,
    damage: 0,
    activeSound: 78,
    flags: mfSolid | mfShootable | mfCountKill,
    raiseState: 660,
  ),
  MobjInfo( // 21 MT_CYBORG
    doomedNum: 16,
    spawnState: 674,
    spawnHealth: 4000,
    seeState: 676,
    seeSound: 44,
    reactionTime: 8,
    attackSound: 0,
    painState: 690,
    painChance: 20,
    painSound: 26,
    meleeState: 0,
    missileState: 684,
    deathState: 691,
    xdeathState: 0,
    deathSound: 68,
    speed: 16,
    radius: 40 << 16,
    height: 110 << 16,
    mass: 1000,
    damage: 0,
    activeSound: 77,
    flags: mfSolid | mfShootable | mfCountKill,
    raiseState: 0,
  ),
  MobjInfo( // 22 MT_PAIN
    doomedNum: 71,
    spawnState: 701,
    spawnHealth: 400,
    seeState: 702,
    seeSound: 50,
    reactionTime: 8,
    attackSound: 0,
    painState: 712,
    painChance: 128,
    painSound: 30,
    meleeState: 0,
    missileState: 708,
    deathState: 714,
    xdeathState: 0,
    deathSound: 73,
    speed: 8,
    radius: 31 << 16,
    height: 56 << 16,
    mass: 400,
    damage: 0,
    activeSound: 77,
    flags: mfSolid | mfShootable | mfFloat | mfNoGravity | mfCountKill,
    raiseState: 720,
  ),
  MobjInfo( // 23 MT_WOLFSS
    doomedNum: 84,
    spawnState: 726,
    spawnHealth: 50,
    seeState: 728,
    seeSound: 101,
    reactionTime: 8,
    attackSound: 0,
    painState: 742,
    painChance: 170,
    painSound: 27,
    meleeState: 0,
    missileState: 736,
    deathState: 744,
    xdeathState: 749,
    deathSound: 102,
    speed: 8,
    radius: 20 << 16,
    height: 56 << 16,
    mass: 100,
    damage: 0,
    activeSound: 75,
    flags: mfSolid | mfShootable | mfCountKill,
    raiseState: 758,
  ),
  MobjInfo( // 24 MT_KEEN
    doomedNum: 72,
    spawnState: 763,
    spawnHealth: 100,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 776,
    painChance: 256,
    painSound: 103,
    meleeState: 0,
    missileState: 0,
    deathState: 764,
    xdeathState: 0,
    deathSound: 104,
    speed: 0,
    radius: 16 << 16,
    height: 72 << 16,
    mass: 10000000,
    damage: 0,
    activeSound: 0,
    flags: mfSolid | mfSpawnCeiling | mfNoGravity | mfShootable | mfCountKill,
    raiseState: 0,
  ),
  MobjInfo( // 25 MT_BOSSBRAIN
    doomedNum: 88,
    spawnState: 778,
    spawnHealth: 250,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 779,
    painChance: 255,
    painSound: 97,
    meleeState: 0,
    missileState: 0,
    deathState: 780,
    xdeathState: 0,
    deathSound: 98,
    speed: 0,
    radius: 16 << 16,
    height: 16 << 16,
    mass: 10000000,
    damage: 0,
    activeSound: 0,
    flags: mfSolid | mfShootable,
    raiseState: 0,
  ),
  MobjInfo( // 26 MT_BOSSSPIT
    doomedNum: 89,
    spawnState: 784,
    spawnHealth: 1000,
    seeState: 785,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 32 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfNoBlockmap | mfNoSector,
    raiseState: 0,
  ),
  MobjInfo( // 27 MT_BOSSTARGET
    doomedNum: 87,
    spawnState: 0,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 32 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfNoBlockmap | mfNoSector,
    raiseState: 0,
  ),
  MobjInfo( // 28 MT_SPAWNSHOT
    doomedNum: -1,
    spawnState: 787,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 94,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 17,
    speed: 10 << 16,
    radius: 6 << 16,
    height: 32 << 16,
    mass: 100,
    damage: 3,
    activeSound: 0,
    flags: mfNoBlockmap | mfMissile | mfDropOff | mfNoGravity | mfNoClip,
    raiseState: 0,
  ),
  MobjInfo( // 29 MT_SPAWNFIRE
    doomedNum: -1,
    spawnState: 791,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfNoBlockmap | mfNoGravity,
    raiseState: 0,
  ),
  MobjInfo( // 30 MT_BARREL
    doomedNum: 2035,
    spawnState: 806,
    spawnHealth: 20,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 808,
    xdeathState: 0,
    deathSound: 82,
    speed: 0,
    radius: 10 << 16,
    height: 42 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSolid | mfShootable | mfNoBlood,
    raiseState: 0,
  ),
  MobjInfo( // 31 MT_TROOPSHOT
    doomedNum: -1,
    spawnState: 97,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 16,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 99,
    xdeathState: 0,
    deathSound: 17,
    speed: 10 << 16,
    radius: 6 << 16,
    height: 8 << 16,
    mass: 100,
    damage: 3,
    activeSound: 0,
    flags: mfNoBlockmap | mfMissile | mfDropOff | mfNoGravity,
    raiseState: 0,
  ),
  MobjInfo( // 32 MT_HEADSHOT
    doomedNum: -1,
    spawnState: 102,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 16,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 104,
    xdeathState: 0,
    deathSound: 17,
    speed: 10 << 16,
    radius: 6 << 16,
    height: 8 << 16,
    mass: 100,
    damage: 5,
    activeSound: 0,
    flags: mfNoBlockmap | mfMissile | mfDropOff | mfNoGravity,
    raiseState: 0,
  ),
  MobjInfo( // 33 MT_ROCKET
    doomedNum: -1,
    spawnState: 114,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 14,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 127,
    xdeathState: 0,
    deathSound: 82,
    speed: 20 << 16,
    radius: 11 << 16,
    height: 8 << 16,
    mass: 100,
    damage: 20,
    activeSound: 0,
    flags: mfNoBlockmap | mfMissile | mfDropOff | mfNoGravity,
    raiseState: 0,
  ),
  MobjInfo( // 34 MT_PLASMA
    doomedNum: -1,
    spawnState: 107,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 8,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 109,
    xdeathState: 0,
    deathSound: 17,
    speed: 25 << 16,
    radius: 13 << 16,
    height: 8 << 16,
    mass: 100,
    damage: 5,
    activeSound: 0,
    flags: mfNoBlockmap | mfMissile | mfDropOff | mfNoGravity,
    raiseState: 0,
  ),
  MobjInfo( // 35 MT_BFG
    doomedNum: -1,
    spawnState: 115,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 117,
    xdeathState: 0,
    deathSound: 15,
    speed: 25 << 16,
    radius: 13 << 16,
    height: 8 << 16,
    mass: 100,
    damage: 100,
    activeSound: 0,
    flags: mfNoBlockmap | mfMissile | mfDropOff | mfNoGravity,
    raiseState: 0,
  ),
  MobjInfo( // 36 MT_ARACHPLAZ
    doomedNum: -1,
    spawnState: 667,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 8,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 669,
    xdeathState: 0,
    deathSound: 17,
    speed: 25 << 16,
    radius: 13 << 16,
    height: 8 << 16,
    mass: 100,
    damage: 5,
    activeSound: 0,
    flags: mfNoBlockmap | mfMissile | mfDropOff | mfNoGravity,
    raiseState: 0,
  ),
  MobjInfo( // 37 MT_PUFF
    doomedNum: -1,
    spawnState: 93,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfNoBlockmap | mfNoGravity,
    raiseState: 0,
  ),
  MobjInfo( // 38 MT_BLOOD
    doomedNum: -1,
    spawnState: 90,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfNoBlockmap,
    raiseState: 0,
  ),
  MobjInfo( // 39 MT_TFOG
    doomedNum: -1,
    spawnState: 130,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfNoBlockmap | mfNoGravity,
    raiseState: 0,
  ),
  MobjInfo( // 40 MT_IFOG
    doomedNum: -1,
    spawnState: 142,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfNoBlockmap | mfNoGravity,
    raiseState: 0,
  ),
  MobjInfo( // 41 MT_TELEPORTMAN
    doomedNum: 14,
    spawnState: 0,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfNoBlockmap | mfNoSector,
    raiseState: 0,
  ),
  MobjInfo( // 42 MT_EXTRABFG
    doomedNum: -1,
    spawnState: 123,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfNoBlockmap | mfNoGravity,
    raiseState: 0,
  ),
  MobjInfo( // 43 MT_MISC0
    doomedNum: 2018,
    spawnState: 802,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSpecial,
    raiseState: 0,
  ),
  MobjInfo( // 44 MT_MISC1
    doomedNum: 2019,
    spawnState: 804,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSpecial,
    raiseState: 0,
  ),
  MobjInfo( // 45 MT_MISC2
    doomedNum: 2014,
    spawnState: 816,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSpecial | mfCountItem,
    raiseState: 0,
  ),
  MobjInfo( // 46 MT_MISC3
    doomedNum: 2015,
    spawnState: 822,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSpecial | mfCountItem,
    raiseState: 0,
  ),
  MobjInfo( // 47 MT_MISC4
    doomedNum: 5,
    spawnState: 828,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSpecial | mfNotDeathmatch,
    raiseState: 0,
  ),
  MobjInfo( // 48 MT_MISC5
    doomedNum: 13,
    spawnState: 830,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSpecial | mfNotDeathmatch,
    raiseState: 0,
  ),
  MobjInfo( // 49 MT_MISC6
    doomedNum: 6,
    spawnState: 832,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSpecial | mfNotDeathmatch,
    raiseState: 0,
  ),
  MobjInfo( // 50 MT_MISC7
    doomedNum: 39,
    spawnState: 838,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSpecial | mfNotDeathmatch,
    raiseState: 0,
  ),
  MobjInfo( // 51 MT_MISC8
    doomedNum: 38,
    spawnState: 836,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSpecial | mfNotDeathmatch,
    raiseState: 0,
  ),
  MobjInfo( // 52 MT_MISC9
    doomedNum: 40,
    spawnState: 834,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSpecial | mfNotDeathmatch,
    raiseState: 0,
  ),
  MobjInfo( // 53 MT_MISC10
    doomedNum: 2011,
    spawnState: 840,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSpecial,
    raiseState: 0,
  ),
  MobjInfo( // 54 MT_MISC11
    doomedNum: 2012,
    spawnState: 841,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSpecial,
    raiseState: 0,
  ),
  MobjInfo( // 55 MT_MISC12
    doomedNum: 2013,
    spawnState: 842,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSpecial | mfCountItem,
    raiseState: 0,
  ),
  MobjInfo( // 56 MT_INV
    doomedNum: 2022,
    spawnState: 848,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSpecial | mfCountItem,
    raiseState: 0,
  ),
  MobjInfo( // 57 MT_MISC13
    doomedNum: 2023,
    spawnState: 852,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSpecial | mfCountItem,
    raiseState: 0,
  ),
  MobjInfo( // 58 MT_INS
    doomedNum: 2024,
    spawnState: 853,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSpecial | mfCountItem,
    raiseState: 0,
  ),
  MobjInfo( // 59 MT_MISC14
    doomedNum: 2025,
    spawnState: 861,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSpecial,
    raiseState: 0,
  ),
  MobjInfo( // 60 MT_MISC15
    doomedNum: 2026,
    spawnState: 862,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSpecial | mfCountItem,
    raiseState: 0,
  ),
  MobjInfo( // 61 MT_MISC16
    doomedNum: 2045,
    spawnState: 868,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSpecial | mfCountItem,
    raiseState: 0,
  ),
  MobjInfo( // 62 MT_MEGA
    doomedNum: 83,
    spawnState: 857,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSpecial | mfCountItem,
    raiseState: 0,
  ),
  MobjInfo( // 63 MT_CLIP
    doomedNum: 2007,
    spawnState: 870,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSpecial,
    raiseState: 0,
  ),
  MobjInfo( // 64 MT_MISC17
    doomedNum: 2048,
    spawnState: 871,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSpecial,
    raiseState: 0,
  ),
  MobjInfo( // 65 MT_MISC18
    doomedNum: 2010,
    spawnState: 872,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSpecial,
    raiseState: 0,
  ),
  MobjInfo( // 66 MT_MISC19
    doomedNum: 2046,
    spawnState: 873,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSpecial,
    raiseState: 0,
  ),
  MobjInfo( // 67 MT_MISC20
    doomedNum: 2047,
    spawnState: 874,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSpecial,
    raiseState: 0,
  ),
  MobjInfo( // 68 MT_MISC21
    doomedNum: 17,
    spawnState: 875,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSpecial,
    raiseState: 0,
  ),
  MobjInfo( // 69 MT_MISC22
    doomedNum: 2008,
    spawnState: 876,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSpecial,
    raiseState: 0,
  ),
  MobjInfo( // 70 MT_MISC23
    doomedNum: 2049,
    spawnState: 877,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSpecial,
    raiseState: 0,
  ),
  MobjInfo( // 71 MT_MISC24
    doomedNum: 8,
    spawnState: 878,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSpecial,
    raiseState: 0,
  ),
  MobjInfo( // 72 MT_MISC25
    doomedNum: 2006,
    spawnState: 879,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSpecial,
    raiseState: 0,
  ),
  MobjInfo( // 73 MT_CHAINGUN
    doomedNum: 2002,
    spawnState: 880,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSpecial,
    raiseState: 0,
  ),
  MobjInfo( // 74 MT_MISC26
    doomedNum: 2005,
    spawnState: 881,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSpecial,
    raiseState: 0,
  ),
  MobjInfo( // 75 MT_MISC27
    doomedNum: 2003,
    spawnState: 882,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSpecial,
    raiseState: 0,
  ),
  MobjInfo( // 76 MT_MISC28
    doomedNum: 2004,
    spawnState: 883,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSpecial,
    raiseState: 0,
  ),
  MobjInfo( // 77 MT_SHOTGUN
    doomedNum: 2001,
    spawnState: 884,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSpecial,
    raiseState: 0,
  ),
  MobjInfo( // 78 MT_SUPERSHOTGUN
    doomedNum: 82,
    spawnState: 885,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSpecial,
    raiseState: 0,
  ),
  MobjInfo( // 79 MT_MISC29
    doomedNum: 85,
    spawnState: 959,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 16 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSolid,
    raiseState: 0,
  ),
  MobjInfo( // 80 MT_MISC30
    doomedNum: 86,
    spawnState: 963,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 16 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSolid,
    raiseState: 0,
  ),
  MobjInfo( // 81 MT_MISC31
    doomedNum: 2028,
    spawnState: 886,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 16 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSolid,
    raiseState: 0,
  ),
  MobjInfo( // 82 MT_MISC32
    doomedNum: 30,
    spawnState: 907,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 16 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSolid,
    raiseState: 0,
  ),
  MobjInfo( // 83 MT_MISC33
    doomedNum: 31,
    spawnState: 908,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 16 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSolid,
    raiseState: 0,
  ),
  MobjInfo( // 84 MT_MISC34
    doomedNum: 32,
    spawnState: 909,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 16 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSolid,
    raiseState: 0,
  ),
  MobjInfo( // 85 MT_MISC35
    doomedNum: 33,
    spawnState: 910,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 16 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSolid,
    raiseState: 0,
  ),
  MobjInfo( // 86 MT_MISC36
    doomedNum: 37,
    spawnState: 913,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 16 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSolid,
    raiseState: 0,
  ),
  MobjInfo( // 87 MT_MISC37
    doomedNum: 36,
    spawnState: 924,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 16 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSolid,
    raiseState: 0,
  ),
  MobjInfo( // 88 MT_MISC38
    doomedNum: 41,
    spawnState: 917,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 16 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSolid,
    raiseState: 0,
  ),
  MobjInfo( // 89 MT_MISC39
    doomedNum: 42,
    spawnState: 921,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 16 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSolid,
    raiseState: 0,
  ),
  MobjInfo( // 90 MT_MISC40
    doomedNum: 43,
    spawnState: 914,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 16 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSolid,
    raiseState: 0,
  ),
  MobjInfo( // 91 MT_MISC41
    doomedNum: 44,
    spawnState: 926,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 16 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSolid,
    raiseState: 0,
  ),
  MobjInfo( // 92 MT_MISC42
    doomedNum: 45,
    spawnState: 930,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 16 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSolid,
    raiseState: 0,
  ),
  MobjInfo( // 93 MT_MISC43
    doomedNum: 46,
    spawnState: 934,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 16 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSolid,
    raiseState: 0,
  ),
  MobjInfo( // 94 MT_MISC44
    doomedNum: 55,
    spawnState: 938,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 16 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSolid,
    raiseState: 0,
  ),
  MobjInfo( // 95 MT_MISC45
    doomedNum: 56,
    spawnState: 942,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 16 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSolid,
    raiseState: 0,
  ),
  MobjInfo( // 96 MT_MISC46
    doomedNum: 57,
    spawnState: 946,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 16 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSolid,
    raiseState: 0,
  ),
  MobjInfo( // 97 MT_MISC47
    doomedNum: 47,
    spawnState: 906,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 16 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSolid,
    raiseState: 0,
  ),
  MobjInfo( // 98 MT_MISC48
    doomedNum: 48,
    spawnState: 916,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 16 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSolid,
    raiseState: 0,
  ),
  MobjInfo( // 99 MT_MISC49
    doomedNum: 34,
    spawnState: 911,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: 0,
    raiseState: 0,
  ),
  MobjInfo( // 100 MT_MISC50
    doomedNum: 35,
    spawnState: 912,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 16 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSolid,
    raiseState: 0,
  ),
  MobjInfo( // 101 MT_MISC51
    doomedNum: 49,
    spawnState: 888,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 16 << 16,
    height: 68 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSolid | mfSpawnCeiling | mfNoGravity,
    raiseState: 0,
  ),
  MobjInfo( // 102 MT_MISC52
    doomedNum: 50,
    spawnState: 902,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 16 << 16,
    height: 84 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSolid | mfSpawnCeiling | mfNoGravity,
    raiseState: 0,
  ),
  MobjInfo( // 103 MT_MISC53
    doomedNum: 51,
    spawnState: 903,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 16 << 16,
    height: 84 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSolid | mfSpawnCeiling | mfNoGravity,
    raiseState: 0,
  ),
  MobjInfo( // 104 MT_MISC54
    doomedNum: 52,
    spawnState: 904,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 16 << 16,
    height: 68 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSolid | mfSpawnCeiling | mfNoGravity,
    raiseState: 0,
  ),
  MobjInfo( // 105 MT_MISC55
    doomedNum: 53,
    spawnState: 905,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 16 << 16,
    height: 52 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSolid | mfSpawnCeiling | mfNoGravity,
    raiseState: 0,
  ),
  MobjInfo( // 106 MT_MISC56
    doomedNum: 59,
    spawnState: 902,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 84 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSpawnCeiling | mfNoGravity,
    raiseState: 0,
  ),
  MobjInfo( // 107 MT_MISC57
    doomedNum: 60,
    spawnState: 904,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 68 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSpawnCeiling | mfNoGravity,
    raiseState: 0,
  ),
  MobjInfo( // 108 MT_MISC58
    doomedNum: 61,
    spawnState: 903,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 52 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSpawnCeiling | mfNoGravity,
    raiseState: 0,
  ),
  MobjInfo( // 109 MT_MISC59
    doomedNum: 62,
    spawnState: 905,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 52 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSpawnCeiling | mfNoGravity,
    raiseState: 0,
  ),
  MobjInfo( // 110 MT_MISC60
    doomedNum: 63,
    spawnState: 888,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 68 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSpawnCeiling | mfNoGravity,
    raiseState: 0,
  ),
  MobjInfo( // 111 MT_MISC61
    doomedNum: 22,
    spawnState: 515,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: 0,
    raiseState: 0,
  ),
  MobjInfo( // 112 MT_MISC62
    doomedNum: 15,
    spawnState: 164,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: 0,
    raiseState: 0,
  ),
  MobjInfo( // 113 MT_MISC63
    doomedNum: 18,
    spawnState: 193,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: 0,
    raiseState: 0,
  ),
  MobjInfo( // 114 MT_MISC64
    doomedNum: 21,
    spawnState: 495,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: 0,
    raiseState: 0,
  ),
  MobjInfo( // 115 MT_MISC65
    doomedNum: 23,
    spawnState: 600,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: 0,
    raiseState: 0,
  ),
  MobjInfo( // 116 MT_MISC66
    doomedNum: 20,
    spawnState: 461,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: 0,
    raiseState: 0,
  ),
  MobjInfo( // 117 MT_MISC67
    doomedNum: 19,
    spawnState: 226,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: 0,
    raiseState: 0,
  ),
  MobjInfo( // 118 MT_MISC68
    doomedNum: 10,
    spawnState: 173,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: 0,
    raiseState: 0,
  ),
  MobjInfo( // 119 MT_MISC69
    doomedNum: 12,
    spawnState: 173,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: 0,
    raiseState: 0,
  ),
  MobjInfo( // 120 MT_MISC70
    doomedNum: 28,
    spawnState: 894,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 16 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSolid,
    raiseState: 0,
  ),
  MobjInfo( // 121 MT_MISC71
    doomedNum: 24,
    spawnState: 895,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: 0,
    raiseState: 0,
  ),
  MobjInfo( // 122 MT_MISC72
    doomedNum: 27,
    spawnState: 896,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 16 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSolid,
    raiseState: 0,
  ),
  MobjInfo( // 123 MT_MISC73
    doomedNum: 29,
    spawnState: 897,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 16 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSolid,
    raiseState: 0,
  ),
  MobjInfo( // 124 MT_MISC74
    doomedNum: 25,
    spawnState: 899,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 16 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSolid,
    raiseState: 0,
  ),
  MobjInfo( // 125 MT_MISC75
    doomedNum: 26,
    spawnState: 900,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 16 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSolid,
    raiseState: 0,
  ),
  MobjInfo( // 126 MT_MISC76
    doomedNum: 54,
    spawnState: 915,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 32 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSolid,
    raiseState: 0,
  ),
  MobjInfo( // 127 MT_MISC77
    doomedNum: 70,
    spawnState: 813,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 16 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSolid,
    raiseState: 0,
  ),
  MobjInfo( // 128 MT_MISC78
    doomedNum: 73,
    spawnState: 950,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 16 << 16,
    height: 88 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSolid | mfSpawnCeiling | mfNoGravity,
    raiseState: 0,
  ),
  MobjInfo( // 129 MT_MISC79
    doomedNum: 74,
    spawnState: 951,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 16 << 16,
    height: 88 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSolid | mfSpawnCeiling | mfNoGravity,
    raiseState: 0,
  ),
  MobjInfo( // 130 MT_MISC80
    doomedNum: 75,
    spawnState: 952,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 16 << 16,
    height: 64 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSolid | mfSpawnCeiling | mfNoGravity,
    raiseState: 0,
  ),
  MobjInfo( // 131 MT_MISC81
    doomedNum: 76,
    spawnState: 953,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 16 << 16,
    height: 64 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSolid | mfSpawnCeiling | mfNoGravity,
    raiseState: 0,
  ),
  MobjInfo( // 132 MT_MISC82
    doomedNum: 77,
    spawnState: 954,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 16 << 16,
    height: 64 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSolid | mfSpawnCeiling | mfNoGravity,
    raiseState: 0,
  ),
  MobjInfo( // 133 MT_MISC83
    doomedNum: 78,
    spawnState: 955,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 16 << 16,
    height: 64 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfSolid | mfSpawnCeiling | mfNoGravity,
    raiseState: 0,
  ),
  MobjInfo( // 134 MT_MISC84
    doomedNum: 79,
    spawnState: 956,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfNoBlockmap,
    raiseState: 0,
  ),
  MobjInfo( // 135 MT_MISC85
    doomedNum: 80,
    spawnState: 957,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfNoBlockmap,
    raiseState: 0,
  ),
  MobjInfo( // 136 MT_MISC86
    doomedNum: 81,
    spawnState: 958,
    spawnHealth: 1000,
    seeState: 0,
    seeSound: 0,
    reactionTime: 8,
    attackSound: 0,
    painState: 0,
    painChance: 0,
    painSound: 0,
    meleeState: 0,
    missileState: 0,
    deathState: 0,
    xdeathState: 0,
    deathSound: 0,
    speed: 0,
    radius: 20 << 16,
    height: 16 << 16,
    mass: 100,
    damage: 0,
    activeSound: 0,
    flags: mfNoBlockmap,
    raiseState: 0,
  ),
];

/// DoomEd-number -> mobjtype index, built once from [mobjInfo].
final Map<int, int> doomedToMobjType = _buildDoomedMap();

Map<int, int> _buildDoomedMap() {
  final Map<int, int> m = <int, int>{};
  for (int i = 0; i < mobjInfo.length; i++) {
    final int d = mobjInfo[i].doomedNum;
    if (d > 0) m.putIfAbsent(d, () => i);
  }
  return m;
}

/// Every A_* action name referenced by states[] (for ActionRegistry no-op
/// registration so the tables compile before real implementations land).
const List<String> allActionNames = <String>[
  'A_BFGSpray',
  'A_BFGsound',
  'A_BabyMetal',
  'A_BossDeath',
  'A_BrainAwake',
  'A_BrainDie',
  'A_BrainExplode',
  'A_BrainPain',
  'A_BrainScream',
  'A_BrainSpit',
  'A_BruisAttack',
  'A_BspiAttack',
  'A_CPosAttack',
  'A_CPosRefire',
  'A_Chase',
  'A_CheckReload',
  'A_CloseShotgun2',
  'A_CyberAttack',
  'A_Explode',
  'A_FaceTarget',
  'A_Fall',
  'A_FatAttack1',
  'A_FatAttack2',
  'A_FatAttack3',
  'A_FatRaise',
  'A_Fire',
  'A_FireBFG',
  'A_FireCGun',
  'A_FireCrackle',
  'A_FireMissile',
  'A_FirePistol',
  'A_FirePlasma',
  'A_FireShotgun',
  'A_FireShotgun2',
  'A_GunFlash',
  'A_HeadAttack',
  'A_Hoof',
  'A_KeenDie',
  'A_Light0',
  'A_Light1',
  'A_Light2',
  'A_LoadShotgun2',
  'A_Look',
  'A_Lower',
  'A_Metal',
  'A_OpenShotgun2',
  'A_Pain',
  'A_PainAttack',
  'A_PainDie',
  'A_PlayerScream',
  'A_PosAttack',
  'A_Punch',
  'A_Raise',
  'A_ReFire',
  'A_SPosAttack',
  'A_SargAttack',
  'A_Saw',
  'A_Scream',
  'A_SkelFist',
  'A_SkelMissile',
  'A_SkelWhoosh',
  'A_SkullAttack',
  'A_SpawnFly',
  'A_SpawnSound',
  'A_SpidRefire',
  'A_StartFire',
  'A_Tracer',
  'A_TroopAttack',
  'A_VileAttack',
  'A_VileChase',
  'A_VileStart',
  'A_VileTarget',
  'A_WeaponReady',
  'A_XScream',
];
