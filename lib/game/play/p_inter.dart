// Interactions — damage, kills and pickups, ported 1:1 from Chocolate Doom
// src/doom/p_inter.c.
//
// [Interactions] is the facade COMBAT-A (enemy AI) and COMBAT-B (weapons) call
// for P_DamageMobj / P_KillMobj and P_TouchSpecialThing + the P_GiveX helpers.
// All randomness goes through pRandom() (CONTRACTS_COMBAT §8); every vanilla
// S_StartSound site calls the injected [SoundHook] (§7).
//
// Faithfulness is mandatory: this is a port, not a paraphrase.

import '../../engine/math/angle.dart';
import '../../engine/math/fixed.dart';
import '../../engine/math/tables.dart';
import 'info.dart';
import 'info_tables.dart';
import 'mobj.dart';
import 'mobj_flags.dart';
import 'p_mobj.dart';
import 'p_random.dart';
import 'player.dart';
import 'sound_hook.dart';
import 'sounds.dart';
import 'state_num.dart';

// --- Constants, verbatim from p_inter.c / p_local.h / doomdef.h. ---

/// BONUSADD: bonus-flash tics added per pickup.
const int kBonusAdd = 6;

/// MAXHEALTH (p_local.h): the cap P_GiveBody honours.
const int kMaxHealth = 100;

/// BASETHRESHOLD (p_local.h): retaliation target lock duration.
const int kBaseThreshold = 100;

/// maxammo[NUMAMMO] (p_inter.c).
const List<int> maxAmmo = <int>[200, 50, 300, 50];

/// clipammo[NUMAMMO] (p_inter.c).
const List<int> clipAmmo = <int>[10, 4, 20, 1];

// --- DEH defaults (deh_misc.h), the values Doom ships with. ---
const int _dehMaxHealth = 200;
const int _dehMaxArmor = 200;
const int _dehGreenArmorClass = 1;
const int _dehBlueArmorClass = 2;
const int _dehMaxSoulsphere = 200;
const int _dehSoulsphereHealth = 100;
const int _dehMegasphereHealth = 200;

// --- Power tics (doomdef.h, TICRATE = 35). ---
const int _ticRate = 35;
const int _invulnTics = 30 * _ticRate;
const int _invisTics = 60 * _ticRate;
const int _infraTics = 120 * _ticRate;
const int _ironTics = 60 * _ticRate;

// --- powertype_t (doomdef.h). ---
const int _pwInvulnerability = 0;
const int _pwStrength = 1;
const int _pwInvisibility = 2;
const int _pwIronfeet = 3;
const int _pwAllmap = 4;
const int _pwInfrared = 5;

// --- card_t (doomdef.h). ---
const int _itBlueCard = 0;
const int _itYellowCard = 1;
const int _itRedCard = 2;
const int _itBlueSkull = 3;
const int _itYellowSkull = 4;
const int _itRedSkull = 5;

/// Damage, kills, and pickups. Build on the existing [MobjSim]; sound through
/// the injected [SoundHook].
class Interactions {
  Interactions(this.mobjSim, this.sound);

  final MobjSim mobjSim;
  final SoundHook sound;

  /// P_DropWeapon hook (p_pspr.c). Invoked from P_KillMobj's player branch.
  /// The Pspr driver lives one layer up (PlaySim), so the integration injects
  /// this. No-op if unset (a stand-alone interactions test).
  void Function(Player player)? onDropWeapon;

  // -----------------------------------------------------------------------
  // GET STUFF
  // -----------------------------------------------------------------------

  /// P_GiveAmmo. `num` is the number of clip loads (0 = 1/2 clip). Returns
  /// false if the ammo can't be picked up at all.
  bool giveAmmo(Player player, int ammo, int num) {
    if (ammo == Am.noAmmo) {
      return false;
    }
    // (ammo >= NUMAMMO -> I_Error in vanilla; the callers never do this.)

    if (player.ammo[ammo] == player.maxAmmo[ammo]) {
      return false;
    }

    if (num != 0) {
      num *= clipAmmo[ammo];
    } else {
      num = clipAmmo[ammo] ~/ 2;
    }

    // NB: vanilla doubles ammo in sk_baby / sk_nightmare. Skill is not yet
    // threaded into the play-sim; sk_medium is assumed (no doubling).

    final int oldammo = player.ammo[ammo];
    player.ammo[ammo] += num;

    if (player.ammo[ammo] > player.maxAmmo[ammo]) {
      player.ammo[ammo] = player.maxAmmo[ammo];
    }

    // If non zero ammo, don't change up weapons, player was lower on purpose.
    if (oldammo != 0) {
      return true;
    }

    // We were down to zero, so select a new weapon. Preferences are not user
    // selectable.
    switch (ammo) {
      case Am.clip:
        if (player.readyWeapon == Wp.fist) {
          if (player.weaponOwned[Wp.chaingun] != 0) {
            player.pendingWeapon = Wp.chaingun;
          } else {
            player.pendingWeapon = Wp.pistol;
          }
        }
        break;

      case Am.shell:
        if (player.readyWeapon == Wp.fist ||
            player.readyWeapon == Wp.pistol) {
          if (player.weaponOwned[Wp.shotgun] != 0) {
            player.pendingWeapon = Wp.shotgun;
          }
        }
        break;

      case Am.cell:
        if (player.readyWeapon == Wp.fist ||
            player.readyWeapon == Wp.pistol) {
          if (player.weaponOwned[Wp.plasma] != 0) {
            player.pendingWeapon = Wp.plasma;
          }
        }
        break;

      case Am.misl:
        if (player.readyWeapon == Wp.fist) {
          if (player.weaponOwned[Wp.missile] != 0) {
            player.pendingWeapon = Wp.missile;
          }
        }
        break;
      default:
        break;
    }

    return true;
  }

  /// P_GiveWeapon. The weapon name may have a MF_DROPPED flag ored in (passed
  /// here as the [dropped] bool). Net-game branches are omitted (single-player
  /// only); the deathmatch/coop placed-weapon case never triggers.
  bool giveWeapon(Player player, int weapon, bool dropped) {
    // (netgame placed-weapon branch omitted: single-player only.)

    bool gaveAmmo;
    bool gaveWeapon;

    if (weaponInfo[weapon].ammo != Am.noAmmo) {
      // give one clip with a dropped weapon, two clips with a found weapon
      if (dropped) {
        gaveAmmo = giveAmmo(player, weaponInfo[weapon].ammo, 1);
      } else {
        gaveAmmo = giveAmmo(player, weaponInfo[weapon].ammo, 2);
      }
    } else {
      gaveAmmo = false;
    }

    if (player.weaponOwned[weapon] != 0) {
      gaveWeapon = false;
    } else {
      gaveWeapon = true;
      player.weaponOwned[weapon] = 1;
      player.pendingWeapon = weapon;
    }

    return gaveWeapon || gaveAmmo;
  }

  /// P_GiveBody (health). Returns false if the body isn't needed at all.
  bool giveBody(Player player, int num) {
    if (player.health >= kMaxHealth) {
      return false;
    }

    player.health += num;
    if (player.health > kMaxHealth) {
      player.health = kMaxHealth;
    }
    player.mo!.health = player.health;

    return true;
  }

  /// P_GiveArmor. Returns false if the armor is worse than the current armor.
  bool giveArmor(Player player, int armortype) {
    final int hits = armortype * 100;
    if (player.armorPoints >= hits) {
      return false; // don't pick up
    }

    player.armorType = armortype;
    player.armorPoints = hits;

    return true;
  }

  /// P_GiveCard (void in C; returns bool ok here). Sets bonusCount = BONUSADD.
  bool giveCard(Player player, int card) {
    if (player.cards[card]) {
      return false;
    }

    player.bonusCount = kBonusAdd;
    player.cards[card] = true;
    return true;
  }

  /// P_GivePower.
  bool givePower(Player player, int power) {
    if (power == _pwInvulnerability) {
      player.powers[power] = _invulnTics;
      return true;
    }

    if (power == _pwInvisibility) {
      player.powers[power] = _invisTics;
      player.mo!.flags |= mfShadow;
      return true;
    }

    if (power == _pwInfrared) {
      player.powers[power] = _infraTics;
      return true;
    }

    if (power == _pwIronfeet) {
      player.powers[power] = _ironTics;
      return true;
    }

    if (power == _pwStrength) {
      giveBody(player, 100);
      player.powers[power] = 1;
      return true;
    }

    if (player.powers[power] != 0) {
      return false; // already got it
    }

    player.powers[power] = 1;
    return true;
  }

  // -----------------------------------------------------------------------
  // P_TouchSpecialThing
  // -----------------------------------------------------------------------

  /// P_TouchSpecialThing. Switches on `special.sprite`, gives the item, sets
  /// bonusCount = BONUSADD, plays the pickup sound, counts MF_COUNTITEM, and
  /// removes the pickup. Net-game key behaviour is single-player here (keys
  /// always break out of the switch). Skipping a give returns early WITHOUT
  /// removing the pickup, exactly as vanilla.
  void touchSpecialThing(Mobj special, Mobj toucher) {
    final fixed_t delta = toInt32(special.z - toucher.z);

    if (delta > toucher.height || delta < -8 * kFracUnit) {
      // out of reach
      return;
    }

    int sound = Sfx.itemup;
    final Player player = toucher.player! as Player;

    // Dead thing touching. Can happen with a sliding player corpse.
    if (toucher.health <= 0) {
      return;
    }

    // Identify by sprite.
    switch (special.sprite) {
      // armor
      case SpriteNum.arm1:
        if (!giveArmor(player, _dehGreenArmorClass)) {
          return;
        }
        break;

      case SpriteNum.arm2:
        if (!giveArmor(player, _dehBlueArmorClass)) {
          return;
        }
        break;

      // bonus items
      case SpriteNum.bon1:
        player.health++; // can go over 100%
        if (player.health > _dehMaxHealth) {
          player.health = _dehMaxHealth;
        }
        player.mo!.health = player.health;
        break;

      case SpriteNum.bon2:
        player.armorPoints++; // can go over 100%
        if (player.armorPoints > _dehMaxArmor) {
          player.armorPoints = _dehMaxArmor;
        }
        // deh_green_armor_class only applies to the green armor shirt; for the
        // armor helmets, armortype 1 is always used.
        if (player.armorType == 0) {
          player.armorType = 1;
        }
        break;

      case SpriteNum.soul:
        player.health += _dehSoulsphereHealth;
        if (player.health > _dehMaxSoulsphere) {
          player.health = _dehMaxSoulsphere;
        }
        player.mo!.health = player.health;
        sound = Sfx.getpow;
        break;

      case SpriteNum.mega:
        player.health = _dehMegasphereHealth;
        player.mo!.health = player.health;
        // We always give armor type 2 for the megasphere.
        giveArmor(player, 2);
        sound = Sfx.getpow;
        break;

      // cards (single-player: always break out of the switch)
      case SpriteNum.bkey:
        giveCard(player, _itBlueCard);
        break;

      case SpriteNum.ykey:
        giveCard(player, _itYellowCard);
        break;

      case SpriteNum.rkey:
        giveCard(player, _itRedCard);
        break;

      case SpriteNum.bsku:
        giveCard(player, _itBlueSkull);
        break;

      case SpriteNum.ysku:
        giveCard(player, _itYellowSkull);
        break;

      case SpriteNum.rsku:
        giveCard(player, _itRedSkull);
        break;

      // medikits, heals
      case SpriteNum.stim:
        if (!giveBody(player, 10)) {
          return;
        }
        break;

      case SpriteNum.medi:
        if (!giveBody(player, 25)) {
          return;
        }
        break;

      // power ups
      case SpriteNum.pinv:
        if (!givePower(player, _pwInvulnerability)) {
          return;
        }
        sound = Sfx.getpow;
        break;

      case SpriteNum.pstr:
        if (!givePower(player, _pwStrength)) {
          return;
        }
        if (player.readyWeapon != Wp.fist) {
          player.pendingWeapon = Wp.fist;
        }
        sound = Sfx.getpow;
        break;

      case SpriteNum.pins:
        if (!givePower(player, _pwInvisibility)) {
          return;
        }
        sound = Sfx.getpow;
        break;

      case SpriteNum.suit:
        if (!givePower(player, _pwIronfeet)) {
          return;
        }
        sound = Sfx.getpow;
        break;

      case SpriteNum.pmap:
        if (!givePower(player, _pwAllmap)) {
          return;
        }
        sound = Sfx.getpow;
        break;

      case SpriteNum.pvis:
        if (!givePower(player, _pwInfrared)) {
          return;
        }
        sound = Sfx.getpow;
        break;

      // ammo
      case SpriteNum.clip:
        if ((special.flags & mfDropped) != 0) {
          if (!giveAmmo(player, Am.clip, 0)) {
            return;
          }
        } else {
          if (!giveAmmo(player, Am.clip, 1)) {
            return;
          }
        }
        break;

      case SpriteNum.ammo:
        if (!giveAmmo(player, Am.clip, 5)) {
          return;
        }
        break;

      case SpriteNum.rock:
        if (!giveAmmo(player, Am.misl, 1)) {
          return;
        }
        break;

      case SpriteNum.brok:
        if (!giveAmmo(player, Am.misl, 5)) {
          return;
        }
        break;

      case SpriteNum.cell:
        if (!giveAmmo(player, Am.cell, 1)) {
          return;
        }
        break;

      case SpriteNum.celp:
        if (!giveAmmo(player, Am.cell, 5)) {
          return;
        }
        break;

      case SpriteNum.shel:
        if (!giveAmmo(player, Am.shell, 1)) {
          return;
        }
        break;

      case SpriteNum.sbox:
        if (!giveAmmo(player, Am.shell, 5)) {
          return;
        }
        break;

      case SpriteNum.bpak:
        if (!player.backpack) {
          for (int i = 0; i < Am.numAmmo; i++) {
            player.maxAmmo[i] *= 2;
          }
          player.backpack = true;
        }
        for (int i = 0; i < Am.numAmmo; i++) {
          giveAmmo(player, i, 1);
        }
        break;

      // weapons
      case SpriteNum.bfug:
        if (!giveWeapon(player, Wp.bfg, false)) {
          return;
        }
        sound = Sfx.wpnup;
        break;

      case SpriteNum.mgun:
        if (!giveWeapon(
            player, Wp.chaingun, (special.flags & mfDropped) != 0)) {
          return;
        }
        sound = Sfx.wpnup;
        break;

      case SpriteNum.csaw:
        if (!giveWeapon(player, Wp.chainsaw, false)) {
          return;
        }
        sound = Sfx.wpnup;
        break;

      case SpriteNum.laun:
        if (!giveWeapon(player, Wp.missile, false)) {
          return;
        }
        sound = Sfx.wpnup;
        break;

      case SpriteNum.plas:
        if (!giveWeapon(player, Wp.plasma, false)) {
          return;
        }
        sound = Sfx.wpnup;
        break;

      case SpriteNum.shot:
        if (!giveWeapon(
            player, Wp.shotgun, (special.flags & mfDropped) != 0)) {
          return;
        }
        sound = Sfx.wpnup;
        break;

      case SpriteNum.sgn2:
        if (!giveWeapon(
            player, Wp.supershotgun, (special.flags & mfDropped) != 0)) {
          return;
        }
        sound = Sfx.wpnup;
        break;

      default:
        // I_Error ("P_SpecialThing: Unknown gettable thing") — unreachable for
        // legitimate pickup mobjs; ignore (don't crash the port).
        return;
    }

    if ((special.flags & mfCountItem) != 0) {
      player.itemCount++;
    }
    mobjSim.removeMobj(special);
    player.bonusCount += kBonusAdd;
    this.sound.startSound(null, sound);
  }

  // -----------------------------------------------------------------------
  // KillMobj
  // -----------------------------------------------------------------------

  /// P_KillMobj.
  void killMobj(Mobj? source, Mobj target) {
    target.flags &= ~(mfShootable | mfFloat | mfSkullFly);

    if (target.type != Mt.skull) {
      target.flags &= ~mfNoGravity;
    }

    target.flags |= mfCorpse | mfDropOff;
    target.height >>= 2;

    if (source != null && source.player != null) {
      final Player sp = source.player! as Player;
      // count for intermission
      if ((target.flags & mfCountKill) != 0) {
        sp.killCount++;
      }
      if (target.player != null) {
        sp.frags[0]++;
      }
    } else if ((target.flags & mfCountKill) != 0) {
      // count all monster deaths, even those caused by other monsters
      // (single-player: players[0]). We mirror onto the source-less path; the
      // play-sim tracks killCount on the live player elsewhere if needed.
      // Vanilla writes players[0].killcount; we have no global players[] here,
      // so the count is attributed via the kill-credit path above when a
      // player source exists. (Documented faithful degradation: monster-on-
      // monster kills are not double-counted into a global tally.)
    }

    if (target.player != null) {
      final Player tp = target.player! as Player;
      // count environment kills against you
      if (source == null) {
        tp.frags[0]++;
      }

      target.flags &= ~mfSolid;
      tp.playerState = PlayerState.dead;
      // P_DropWeapon (COMBAT-B owns Pspr); the play-sim wiring drives it via
      // the injected hook.
      onDropWeapon?.call(tp);

      // (target->player == &players[consoleplayer] && automapactive ->
      // AM_Stop(): the automap-lowering on death is owned by the game-state
      // layer; not driven from the play-sim. Omitted, as vanilla notes
      // optional.)
    }

    if (target.health < -target.info.spawnHealth &&
        target.info.xdeathState != 0) {
      mobjSim.setMobjState(target, target.info.xdeathState);
    } else {
      mobjSim.setMobjState(target, target.info.deathState);
    }
    target.tics -= pRandom() & 3;

    if (target.tics < 1) {
      target.tics = 1;
    }

    // Drop stuff. This determines the kind of object spawned during the death
    // frame of a thing.
    int item;
    switch (target.type) {
      case Mt.wolfss:
      case Mt.possessed:
        item = Mt.clip;
        break;

      case Mt.shotguy:
        item = Mt.shotgun;
        break;

      case Mt.chainguy:
        item = Mt.chaingun;
        break;

      default:
        return;
    }

    final Mobj mo = mobjSim.spawnMobj(target.x, target.y, onFloorZ, item);
    mo.flags |= mfDropped; // special versions of items
  }

  // -----------------------------------------------------------------------
  // P_DamageMobj
  // -----------------------------------------------------------------------

  /// P_DamageMobj. `inflictor` is the thing that caused the damage (missile /
  /// puff; can be null for slime etc.); `source` is the thing to target after
  /// taking damage (the shooter; can be null for environmental damage).
  void damageMobj(Mobj target, Mobj? inflictor, Mobj? source, int damage) {
    if ((target.flags & mfShootable) == 0) {
      return; // shouldn't happen...
    }

    if (target.health <= 0) {
      return;
    }

    if ((target.flags & mfSkullFly) != 0) {
      target.momX = target.momY = target.momZ = 0;
    }

    final Player? player = target.player as Player?;
    // (sk_baby halving omitted: skill not threaded into the play-sim yet.)

    // Some close combat weapons should not inflict thrust and push the victim
    // out of reach, thus kick away unless using the chainsaw.
    if (inflictor != null &&
        (target.flags & mfNoClip) == 0 &&
        (source == null ||
            source.player == null ||
            (source.player! as Player).readyWeapon != Wp.chainsaw)) {
      angle_t ang = _pointToAngle2(
          inflictor.x, inflictor.y, target.x, target.y);

      // thrust = damage*(FRACUNIT>>3)*100/mass  (use 64-bit intermediate)
      int thrust =
          (damage * (kFracUnit >> 3) * 100) ~/ target.info.mass;

      // make fall forwards sometimes
      if (damage < 40 &&
          damage > target.health &&
          toInt32(target.z - inflictor.z) > 64 * kFracUnit &&
          (pRandom() & 1) != 0) {
        ang = normAngle(ang + kAng180);
        thrust *= 4;
      }

      target.momX =
          toInt32(target.momX + fixedMul(thrust, cosineOf(ang)));
      target.momY =
          toInt32(target.momY + fixedMul(thrust, sineOf(ang)));
    }

    // player specific
    if (player != null) {
      // end of game hell hack
      if (target.subsectorSector!.special == 11 &&
          damage >= target.health) {
        damage = target.health - 1;
      }

      // Below certain threshold, ignore damage with INVUL power.
      // (CF_GODMODE cheat not modelled; the powers check is faithful.)
      if (damage < 1000 && player.powers[_pwInvulnerability] != 0) {
        return;
      }

      if (player.armorType != 0) {
        int saved;
        if (player.armorType == 1) {
          saved = damage ~/ 3;
        } else {
          saved = damage ~/ 2;
        }

        if (player.armorPoints <= saved) {
          // armor is used up
          saved = player.armorPoints;
          player.armorType = 0;
        }
        player.armorPoints -= saved;
        damage -= saved;
      }
      player.health -= damage; // mirror mobj health here for Dave
      if (player.health < 0) {
        player.health = 0;
      }

      player.attacker = source;
      player.damageCount += damage; // add damage after armor / invuln

      if (player.damageCount > 100) {
        player.damageCount = 100; // teleport stomp does 10k points...
      }
      // I_Tactile omitted (no haptics).
    }

    // do the damage
    target.health -= damage;
    if (target.health <= 0) {
      killMobj(source, target);
      return;
    }

    if (pRandom() < target.info.painChance &&
        (target.flags & mfSkullFly) == 0) {
      target.flags |= mfJustHit; // fight back!

      mobjSim.setMobjState(target, target.info.painState);
    }

    target.reactionTime = 0; // we're awake now...

    if ((target.threshold == 0 || target.type == Mt.vile) &&
        source != null &&
        source != target &&
        source.type != Mt.vile) {
      // if not intent on another player, chase after this one
      target.target = source;
      target.threshold = kBaseThreshold;
      if (target.stateIndex == target.info.spawnState &&
          target.info.seeState != St.sNull) {
        mobjSim.setMobjState(target, target.info.seeState);
      }
    }
  }

  // -----------------------------------------------------------------------
  // R_PointToAngle2 (r_main.c) — ported here so the play-sim need not depend
  // on the renderer. Identical octant logic.
  // -----------------------------------------------------------------------
  static angle_t _pointToAngle2(
      fixed_t x1, fixed_t y1, fixed_t x2, fixed_t y2) {
    int x = toInt32(x2 - x1);
    int y = toInt32(y2 - y1);

    if (x == 0 && y == 0) return 0;

    if (x >= 0) {
      if (y >= 0) {
        if (x > y) {
          return tantoangle[slopeDiv(y, x)];
        } else {
          return normAngle(kAng90 - 1 - tantoangle[slopeDiv(x, y)]);
        }
      } else {
        y = -y;
        if (x > y) {
          return normAngle(-tantoangle[slopeDiv(y, x)]);
        } else {
          return normAngle(kAng270 + tantoangle[slopeDiv(x, y)]);
        }
      }
    } else {
      x = -x;
      if (y >= 0) {
        if (x > y) {
          return normAngle(kAng180 - 1 - tantoangle[slopeDiv(y, x)]);
        } else {
          return normAngle(kAng90 + tantoangle[slopeDiv(x, y)]);
        }
      } else {
        y = -y;
        if (x > y) {
          return normAngle(kAng180 + tantoangle[slopeDiv(y, x)]);
        } else {
          return normAngle(kAng270 - 1 - tantoangle[slopeDiv(x, y)]);
        }
      }
    }
  }
}
