// Action-function dispatch framework, ported from the state machine in
// Chocolate Doom src/info.c / p_enemy.c / p_pspr.c.
//
// In vanilla, each `state_t` carries `void (*action)()`. State transitions in
// P_SetMobjState / P_SetPsprite call that action with the mobj (and, for
// weapon states, the player + pspdef). We model the action as a *name* (a
// stable string key) stored in the state table; the actual behaviour lives in
// an [ActionRegistry] keyed by that name.
//
// THIS SLICE implements only the state machine plumbing. The vast majority of
// A_* functions (enemy AI, weapon firing, attacks, sounds) are NOT implemented
// here — they are registered as no-op stubs that log ONCE the first time they
// fire, so later waves can replace them without touching the state tables.

import 'mobj.dart';
import 'player.dart';

/// Signature for a "thing" action (enemy AI, mobj behaviour). Vanilla actions
/// that take only a mobj. The weapon variant additionally receives the player
/// and the active pspdef; we pass nullable extras so one map can hold both.
typedef MobjAction = void Function(Mobj mobj, {Player? player, Pspdef? psp});

/// Registry mapping action names (as referenced by the state table) to their
/// implementations. Unregistered names resolve to a log-once no-op stub.
class ActionRegistry {
  ActionRegistry._();

  static final ActionRegistry instance = ActionRegistry._();

  final Map<String, MobjAction> _actions = <String, MobjAction>{};
  final Set<String> _warned = <String>{};

  /// Sink for the "unimplemented action fired" log line. Tests/integration may
  /// replace this; defaults to no output to keep test logs clean while still
  /// being observable via [firedStubs].
  void Function(String message) logSink = (_) {};

  /// Names of stub actions that have fired at least once (diagnostics/tests).
  Set<String> get firedStubs => _warned;

  /// Register a real implementation for [name], replacing any prior one.
  void register(String name, MobjAction action) {
    _actions[name] = action;
  }

  /// Look up an action by [name]. Always returns a callable: a registered
  /// implementation, or a log-once no-op stub for unimplemented A_* functions.
  MobjAction resolve(String? name) {
    if (name == null) return _noop;
    final MobjAction? real = _actions[name];
    if (real != null) return real;
    return (Mobj mobj, {Player? player, Pspdef? psp}) {
      if (_warned.add(name)) {
        logSink('[playsim] unimplemented action $name (no-op stub)');
      }
    };
  }

  static void _noop(Mobj mobj, {Player? player, Pspdef? psp}) {}
}
