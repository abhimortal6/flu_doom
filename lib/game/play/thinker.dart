// Thinker base + the global thinker list, ported from Chocolate Doom
// src/p_tick.c (thinker_t, P_AddThinker, P_RemoveThinker, P_RunThinkers) and
// the thinker_t struct in d_think.h.
//
// In vanilla, every active game object that needs per-tic processing is a
// `thinker_t` linked into a doubly-linked circular list whose sentinel is the
// global `thinkercap`. Each tic, P_RunThinkers walks the list and calls each
// thinker's `function.acp1(thinker)`. Removed thinkers are marked
// (function == -1) during the walk and unlinked/freed at the end of the same
// pass so that iteration stays safe.
//
// We model the same structure with a Dart class hierarchy: [Thinker] is the
// base (the linked-list node), subclasses (Mobj, plane thinkers, ...) override
// [tick]. The "function == -1" removal sentinel is replaced by the
// [removed] flag, checked during the run pass.

/// Base class for everything that "thinks" once per tic. Vanilla `thinker_t`.
///
/// Subclasses (mobjs, moving-plane thinkers, light flickers, ...) override
/// [tick]. Instances are linked into a [ThinkerList]; do not link manually —
/// use [ThinkerList.add] / [ThinkerList.remove].
abstract class Thinker {
  /// Previous node in the circular list (set by [ThinkerList]).
  Thinker? prev;

  /// Next node in the circular list (set by [ThinkerList]).
  Thinker? next;

  /// True once [ThinkerList.remove] has marked this thinker for deletion.
  /// Mirrors vanilla's `function.acv == (actionf_p1)(-1)` sentinel: the node
  /// stays linked until the end of the current [ThinkerList.runThinkers] pass.
  bool removed = false;

  /// Per-tic update. Vanilla `currentthinker->function.acp1(currentthinker)`.
  /// A freshly-added thinker whose function is null (vanilla NOP) does nothing.
  void tick();
}

/// The global thinker list. Vanilla wraps a single static `thinkercap`
/// sentinel; we keep an explicit object so the playsim can own one per game.
class ThinkerList {
  /// Sentinel head of the circular doubly-linked list. Its [tick] is never
  /// called; it only anchors the ring.
  final _Sentinel _cap = _Sentinel();

  ThinkerList() {
    _cap.prev = _cap;
    _cap.next = _cap;
  }

  /// Initialise / clear the list (P_InitThinkers): drop all thinkers.
  void clear() {
    _cap.prev = _cap;
    _cap.next = _cap;
  }

  /// P_AddThinker: link [t] in just before the sentinel (i.e. at the tail).
  void add(Thinker t) {
    t.removed = false;
    _cap.prev!.next = t;
    t.next = _cap;
    t.prev = _cap.prev;
    _cap.prev = t;
  }

  /// P_RemoveThinker: mark [t] for deletion. It stays linked until the current
  /// (or next) [runThinkers] pass unlinks it, matching vanilla semantics so
  /// that an in-progress traversal is not corrupted.
  void remove(Thinker t) {
    t.removed = true;
  }

  /// P_RunThinkers: walk the ring once, ticking live thinkers and unlinking
  /// any marked [removed]. Safe against thinkers added/removed during the walk
  /// (newly added ones land at the tail and are ticked this pass, exactly as
  /// vanilla; removed ones are unlinked as encountered).
  void runThinkers() {
    Thinker? current = _cap.next;
    while (current != null && !identical(current, _cap)) {
      if (current.removed) {
        // Unlink and advance.
        final Thinker? nextNode = current.next;
        current.prev!.next = current.next;
        current.next!.prev = current.prev;
        current = nextNode;
      } else {
        current.tick();
        current = current.next;
      }
    }
  }

  /// Iterate the live thinkers (for adapters such as the sprite source).
  /// Skips the sentinel and any thinker marked [removed].
  Iterable<Thinker> get thinkers sync* {
    Thinker? current = _cap.next;
    while (current != null && !identical(current, _cap)) {
      if (!current.removed) yield current;
      current = current.next;
    }
  }

  /// Number of live thinkers (diagnostics/tests).
  int get count {
    int n = 0;
    for (final Thinker _ in thinkers) {
      n++;
    }
    return n;
  }
}

/// The list sentinel. Never ticked.
class _Sentinel extends Thinker {
  @override
  void tick() {}
}
