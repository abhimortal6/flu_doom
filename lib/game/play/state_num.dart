// Named state indices (a subset of vanilla statenum_t) used directly by the
// playsim code. The full states[] table (info_tables.dart) is indexed by raw
// integers; these constants give readable names to the entries the engine
// references by name (player, puff, blood, etc.), matching info.h ordering.
//
// Only the states actually referenced in code are named here; every state is
// still present (by index) in info_tables.dart. Values are the exact vanilla
// statenum_t ordinals.

abstract final class St {
  static const int sNull = 0;
  static const int sLightDone = 1;

  // Weapon (player sprite) states referenced by the pspr logic.
  static const int sPunch = 2;
  static const int sPunchDown = 3;
  static const int sPunchUp = 4;
  static const int sPistol = 10;
  static const int sPistolDown = 14;
  static const int sPistolUp = 15;

  // Player mobj states (PLAY sprite).
  static const int sPlay = 149;
  static const int sPlayRun1 = 150;
  static const int sPlayRun2 = 151;
  static const int sPlayRun3 = 152;
  static const int sPlayRun4 = 153;
  static const int sPlayAtk1 = 154;
  static const int sPlayAtk2 = 155;
  static const int sPlayPain = 156;
  static const int sPlayPain2 = 157;
  static const int sPlayDie1 = 158;
  static const int sPlayXdie1 = 165;

  // Common effect states.
  static const int sPuff1 = 93;
  static const int sBlood1 = 90;
  static const int sTfog = 130;
  static const int sIfog = 139;
}
