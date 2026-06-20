// Sector specials, ported from Chocolate Doom src/p_spec.c.
//
// THIS SLICE: P_PlayerInSpecialSector — the damaging-floor / secret-sector
// per-tic check. The rest of p_spec.c (texture animation, line specials,
// thinker spawning) lives in other modules (lights, doors, switches, spawn).

import 'mobj.dart';
import 'p_inter.dart';
import 'p_random.dart';
import 'player.dart';

/// powertype_t (doomdef.h): pw_ironfeet index into player.powers. The radiation
/// suit power that protects against nukage/slime damage.
const int _pwIronfeet = 3;

/// P_PlayerInSpecialSector (p_spec.c). Called every tic frame that the player
/// origin is in a special sector. Ported 1:1.
///
/// Dependencies vanilla reads as file-scope globals are passed in explicitly:
/// [leveltime] (the per-tic clock; the `&0x1f` gate is the ~0.9s damage tick),
/// [interactions] for P_DamageMobj, and [exitLevel] for the special-11 finale
/// (G_ExitLevel). [exitLevel] may be null if no exit flow is wired.
void playerInSpecialSector(
  Player player, {
  required int leveltime,
  required Interactions interactions,
  void Function()? exitLevel,
}) {
  final Mobj mo = player.mo!;

  // sector = player->mo->subsector->sector;
  final sector = mo.subsectorSector!;

  // Falling, not all the way down yet?
  if (mo.z != sector.floorHeight) {
    return;
  }

  // Has hitten ground.
  switch (sector.special) {
    case 5:
      // HELLSLIME DAMAGE
      if (player.powers[_pwIronfeet] == 0) {
        if ((leveltime & 0x1f) == 0) {
          interactions.damageMobj(mo, null, null, 10);
        }
      }
      break;

    case 7:
      // NUKAGE DAMAGE
      if (player.powers[_pwIronfeet] == 0) {
        if ((leveltime & 0x1f) == 0) {
          interactions.damageMobj(mo, null, null, 5);
        }
      }
      break;

    case 16:
    // SUPER HELLSLIME DAMAGE
    case 4:
      // STROBE HURT
      if (player.powers[_pwIronfeet] == 0 || (pRandom() < 5)) {
        if ((leveltime & 0x1f) == 0) {
          interactions.damageMobj(mo, null, null, 20);
        }
      }
      break;

    case 9:
      // SECRET SECTOR
      player.secretCount++;
      sector.special = 0;
      break;

    case 11:
      // EXIT SUPER DAMAGE! (for E1M8 finale)
      // player->cheats &= ~CF_GODMODE; (cheats not modelled; omitted.)

      if ((leveltime & 0x1f) == 0) {
        interactions.damageMobj(mo, null, null, 20);
      }

      if (player.health <= 10) {
        exitLevel?.call();
      }
      break;

    default:
      // I_Error("P_PlayerInSpecialSector: unknown special %i", ...): vanilla
      // aborts here. The play-sim treats an unrecognised special as a no-op so
      // a malformed map cannot crash the engine.
      break;
  }
}
