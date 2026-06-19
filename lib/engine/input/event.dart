// Doom event type + event queue, ported from Chocolate Doom src/d_event.h
// (evtype_t / event_t) and the D_PostEvent / D_PopEvent ring buffer in
// src/d_loop.c.
//
// In vanilla Doom, input is posted into a fixed ring buffer and the game
// drains it once per tic. We mirror that contract: sources call [postEvent];
// the game loop calls [popEvent] until it returns null.

import 'doomkeys.dart';

/// Doom event types (evtype_t).
enum EventType {
  keyDown,
  keyUp,
  mouse,
  joystick,
  quit,
}

/// A Doom input event (event_t). For key events, [data1] holds the
/// [DoomKey] code. Other fields mirror the C struct for forward
/// compatibility (mouse deltas, etc.) but are unused this phase.
class DoomEvent {
  const DoomEvent(this.type, {this.data1 = 0, this.data2 = 0, this.data3 = 0});

  final EventType type;

  /// For key events: the Doom keycode. For mouse: button state.
  final int data1;

  /// Mouse X delta / joystick axis.
  final int data2;

  /// Mouse Y delta / joystick axis.
  final int data3;

  /// Convenience constructor for a key-down event.
  const DoomEvent.keyDown(int key) : this(EventType.keyDown, data1: key);

  /// Convenience constructor for a key-up event.
  const DoomEvent.keyUp(int key) : this(EventType.keyUp, data1: key);

  @override
  String toString() => 'DoomEvent($type, d1=$data1)';
}

/// Fixed-size event ring buffer, matching vanilla's MAXEVENTS (=64) semantics.
/// Sources post events; the game loop drains them once per tic.
class EventQueue {
  EventQueue({this.capacity = 64}) : _buffer = List<DoomEvent?>.filled(64, null);

  final int capacity;
  final List<DoomEvent?> _buffer;
  int _head = 0; // write index (eventhead)
  int _tail = 0; // read index (eventtail)

  /// Post an event into the queue (D_PostEvent). Drops the event if full
  /// (vanilla overwrites oldest; we drop to avoid surprising replay, which is
  /// acceptable for the input plumbing contract).
  void postEvent(DoomEvent event) {
    final int next = (_head + 1) % capacity;
    if (next == _tail) {
      // Queue full: drop oldest to keep latest input responsive.
      _tail = (_tail + 1) % capacity;
    }
    _buffer[_head] = event;
    _head = next;
  }

  /// Pop the next event (D_PopEvent), or null if empty.
  DoomEvent? popEvent() {
    if (_tail == _head) return null;
    final DoomEvent? e = _buffer[_tail];
    _tail = (_tail + 1) % capacity;
    return e;
  }

  /// True if there are no pending events.
  bool get isEmpty => _tail == _head;

  /// Drain all pending events into a list (in order).
  List<DoomEvent> drain() {
    final List<DoomEvent> out = <DoomEvent>[];
    DoomEvent? e;
    while ((e = popEvent()) != null) {
      out.add(e!);
    }
    return out;
  }
}
