// Shared geometry for the GAMEPLAY overlay controls.
//
// Both the LIVE overlay (touch_controls_overlay.dart) and the layout CUSTOMIZER
// (controls_customize_screen.dart) need to agree on, for each repositionable
// control: its pixel SIZE and its DEFAULT normalized center within the usable
// area. Centralizing it here keeps the two in lockstep — the customizer drags
// the same buttons the live overlay places, and a saved fraction lands in the
// same spot in both.
//
// A [ButtonPosition] fraction (dx, dy) is the normalized CENTER of the control
// in the usable area [0..size]. [resolveCenter] turns a fraction into a pixel
// center CLAMPED so the control body stays fully on screen. [defaultCenterFor]
// gives the built-in (un-customized) normalized center, derived from the same
// corner-cluster layout the live overlay has always used.

import 'package:flutter/widgets.dart';

import '../../input_actions/controls_settings.dart';
import 'overlay_button_id.dart';

/// Per-control sizing + default placement for one overlay layout
/// (a specific size / orientation / handedness / scale).
class OverlayLayout {
  OverlayLayout({
    required this.area,
    required this.landscape,
    required this.leftHanded,
    required double scale,
  }) : _scale = scale;

  /// Usable area (already inside SafeArea) in logical pixels.
  final Size area;
  final bool landscape;
  final bool leftHanded;
  final double _scale;

  // Effective scale: the live overlay shaves portrait down to 0.9 to leave room
  // (see _buildGameplay). Keep that here so sizes match exactly.
  double get scale => _scale * (landscape ? 1.0 : 0.9);

  double get pad => 16 * scale;
  double get gap => 10 * scale;

  /// Diameter (px) of the control with the given id.
  double sizeFor(String id) {
    switch (id) {
      case OverlayButtonId.movementStick:
        return 140 * scale;
      case OverlayButtonId.fire:
        return 68 * scale;
      case OverlayButtonId.use:
        return 48 * scale;
      case OverlayButtonId.prevWeapon:
      case OverlayButtonId.nextWeapon:
        return 42 * scale;
      case OverlayButtonId.automap:
      case OverlayButtonId.menu:
      case OverlayButtonId.pause:
        return 40 * scale;
      default:
        return 48 * scale;
    }
  }

  /// Built-in normalized center (dx, dy in 0..1) for [id], reproducing the
  /// legacy corner-cluster layout. Movement stick bottom-(left|right); the
  /// FIRE/USE + weapon cluster hugs the opposite bottom corner; the
  /// MENU/MAP/PAUSE utility row sits along the top of the action side.
  ButtonPosition defaultCenterFor(String id) {
    final double w = area.width;
    final double h = area.height;
    if (w <= 0 || h <= 0) return const ButtonPosition(0.5, 0.5);

    // Half-extents as fractions, used to inset cluster anchors off the edges.
    double hx(String b) => (sizeFor(b) / 2) / w;
    double hy(String b) => (sizeFor(b) / 2) / h;
    final double px = pad / w;
    final double py = pad / h;
    final double gx = gap / w;
    final double gy = gap / h;

    // Movement side vs action side (mirrored when left-handed).
    final bool moveLeft = !leftHanded; // stick on left for right-handed
    double moveSideX(double halfX) =>
        moveLeft ? (px + halfX) : (1.0 - px - halfX);
    double actionSideX(double halfX) =>
        moveLeft ? (1.0 - px - halfX) : (px + halfX);

    switch (id) {
      case OverlayButtonId.movementStick:
        return ButtonPosition(
          moveSideX(hx(id)),
          1.0 - py - hy(id),
        );

      // Bottom action cluster: [USE][gap][FIRE] in a row, crossAxis end-aligned
      // so the bigger FIRE's bottom matches USE's bottom. FIRE sits in the
      // outer corner; USE to its inner side.
      case OverlayButtonId.fire:
        return ButtonPosition(
          actionSideX(hx(id)),
          1.0 - py - hy(id),
        );
      case OverlayButtonId.use: {
        final double fireH = sizeFor(OverlayButtonId.fire) / w;
        final double useH = sizeFor(id) / w;
        // USE center is one (fireFull + gap + useHalf) inboard of FIRE center,
        // toward screen center.
        final double fireCx = actionSideX(sizeFor(OverlayButtonId.fire) / 2 / w);
        final double offset = (fireH / 2) + gx + (useH / 2);
        final double cx = moveLeft ? (fireCx - offset) : (fireCx + offset);
        // Bottom-aligned with FIRE.
        final double fireBottom = 1.0 - py; // bottom edge fraction
        final double cy = fireBottom - hy(id);
        return ButtonPosition(cx, cy);
      }

      // Weapon row sits one cluster-gap ABOVE the FIRE/USE row.
      case OverlayButtonId.prevWeapon:
      case OverlayButtonId.nextWeapon: {
        final double fireBottom = 1.0 - py;
        final double fireFull = sizeFor(OverlayButtonId.fire) / h;
        final double wH = sizeFor(id) / h;
        final double rowCy = fireBottom - fireFull - gy - (wH / 2);
        // PREV is outer, NEXT inner (Row order: prev, next). Outer == action
        // corner side.
        final double prevCx = actionSideX(sizeFor(OverlayButtonId.prevWeapon) / 2 / w);
        final double step =
            (sizeFor(OverlayButtonId.prevWeapon) / 2 / w) +
            gx +
            (sizeFor(OverlayButtonId.nextWeapon) / 2 / w);
        if (id == OverlayButtonId.prevWeapon) {
          return ButtonPosition(prevCx, rowCy);
        }
        final double nextCx = moveLeft ? (prevCx - step) : (prevCx + step);
        return ButtonPosition(nextCx, rowCy);
      }

      // Utility row along the TOP of the action side: [MENU][MAP][PAUSE].
      case OverlayButtonId.menu:
      case OverlayButtonId.automap:
      case OverlayButtonId.pause: {
        final double uH = sizeFor(id) / w;
        final double cy = py + hy(id);
        // Order outward->inward differs by handedness so the row reads
        // MENU/MAP/PAUSE from the corner inward, matching the live Row.
        final double menuCx = actionSideX(uH / 2);
        final double step = uH + gx; // uniform small-button spacing
        int index;
        switch (id) {
          case OverlayButtonId.menu:
            index = 0;
            break;
          case OverlayButtonId.automap:
            index = 1;
            break;
          default:
            index = 2;
        }
        final double cx =
            moveLeft ? (menuCx - step * index) : (menuCx + step * index);
        return ButtonPosition(cx, cy);
      }

      default:
        return const ButtonPosition(0.5, 0.5);
    }
  }

  /// The normalized center to USE for [id]: the saved override if present,
  /// else the built-in default.
  ButtonPosition centerFor(String id, Map<String, ButtonPosition> overrides) {
    return overrides[id] ?? defaultCenterFor(id);
  }

  /// Convert a normalized center into a TOP-LEFT pixel offset for a control of
  /// [id]'s size, CLAMPED so the whole control body stays inside [area].
  Offset topLeftFor(String id, ButtonPosition center) {
    final double s = sizeFor(id);
    final double half = s / 2;
    double cx = center.dx * area.width;
    double cy = center.dy * area.height;
    // Clamp the CENTER so the body never leaves the area.
    final double minCx = half;
    final double maxCx = (area.width - half).clamp(half, double.infinity);
    final double minCy = half;
    final double maxCy = (area.height - half).clamp(half, double.infinity);
    cx = cx.clamp(minCx, maxCx);
    cy = cy.clamp(minCy, maxCy);
    return Offset(cx - half, cy - half);
  }

  /// Inverse of [topLeftFor]: a dropped top-left back to a clamped normalized
  /// center (used by the customizer while dragging).
  ButtonPosition centerFromTopLeft(String id, Offset topLeft) {
    final double half = sizeFor(id) / 2;
    final double cx = topLeft.dx + half;
    final double cy = topLeft.dy + half;
    final double w = area.width <= 0 ? 1 : area.width;
    final double h = area.height <= 0 ? 1 : area.height;
    return ButtonPosition(cx / w, cy / h).clamped();
  }
}
