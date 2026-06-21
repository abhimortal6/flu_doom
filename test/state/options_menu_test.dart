// Options / Sound Volume menu wiring (m_menu.c M_Options / M_Sound).
//
// Drives the menu state machine from Main -> Options -> Sound Volume with
// synthetic key events and asserts:
//   - the SFX/Music thermometers adjust (0..15) on left/right and fire the
//     wired GameState callbacks (onSfxVolume / onMusicVolume),
//   - Messages toggles (M_ChangeMessages),
//   - the skull cursor skips spacer rows and navigation works,
//   - Backspace/Escape back out cleanly.
//
// A recording GameStateConfig captures onSfxVolume/onMusicVolume so the
// menu->audio routing is verified end-to-end without a real audio backend.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import '../helpers/wad_fixture.dart';
import 'package:flu_doom/engine/input/doomkeys.dart';
import 'package:flu_doom/engine/input/event.dart';
import 'package:flu_doom/engine/video/framebuffer.dart';
import 'package:flu_doom/engine/wad/wad.dart';
import 'package:flu_doom/game/state/game_state.dart';
import 'package:flu_doom/game/state/dummy_player_status.dart';
import 'package:flu_doom/game/world/world.dart';
import 'package:flu_doom/ui/hud/graphics_cache.dart';
import 'package:flu_doom/ui/menu/menu.dart';

WadFile _wad() {
  final Uint8List bytes =
      Uint8List.fromList(File('assets/doom1.wad').readAsBytesSync());
  return WadFile.fromBytes(bytes);
}

GraphicsCache _gc() => GraphicsCache(_wad());

void _key(MenuController m, int k) =>
    m.responder(DoomEvent.keyDown(k));

/// Open Main -> Options -> Sound Volume.
MenuController _intoSound(MenuController menu) {
  menu.open();
  // Main: index 0 = New Game, 1 = Options.
  _key(menu, DoomKey.downArrow); // -> Options
  expect(menu.current.name, 'main');
  _key(menu, DoomKey.enter); // open Options
  expect(menu.current.name, 'options');
  // Options last item (Sound Volume) is index 7. Navigate down to it.
  while (menu.current.items[menu.selectedIndex].patchName != 'M_SVOL') {
    _key(menu, DoomKey.downArrow);
  }
  _key(menu, DoomKey.enter); // open Sound
  expect(menu.current.name, 'sound');
  return menu;
}

void main() {
  // Bring-your-own-WAD: the WAD is gitignored and absent in a clean clone/CI.
  // Skip (don't fail) the WAD-dependent tests when assets/doom1.wad is missing.
  if (!wadFixtureExists) {
    test('WAD-dependent tests skipped (no assets/doom1.wad)', () {},
        skip: wadFixtureSkip);
    return;
  }
  test('thermometer + sound graphics lumps load', () {
    final GraphicsCache gc = _gc();
    for (final String n in <String>[
      'M_THERML',
      'M_THERMM',
      'M_THERMR',
      'M_THERMO',
      'M_SFXVOL',
      'M_MUSVOL',
      'M_SVOL',
      'M_ENDGAM',
      'M_MSENS',
      'M_SCRNSZ',
    ]) {
      expect(gc.has(n), isTrue, reason: '$n should be present');
    }
  });

  test('Main -> Options -> Sound Volume navigates', () {
    final MenuController menu = MenuController(_gc());
    _intoSound(menu);
    // SFX row is the first selectable item.
    expect(menu.selectedIndex, 0);
  });

  test('left/right adjust SFX volume and fire onSfxVolume (0..15)', () {
    final MenuController menu = MenuController(_gc());
    final List<int> sfx = <int>[];
    menu.onSfxVolume = sfx.add;
    _intoSound(menu);
    expect(menu.sfxVolume, 8); // default.

    _key(menu, DoomKey.rightArrow);
    expect(menu.sfxVolume, 9);
    _key(menu, DoomKey.rightArrow);
    expect(menu.sfxVolume, 10);
    _key(menu, DoomKey.leftArrow);
    expect(menu.sfxVolume, 9);
    expect(sfx, <int>[9, 10, 9]);

    // Clamp at 15.
    for (int i = 0; i < 20; i++) {
      _key(menu, DoomKey.rightArrow);
    }
    expect(menu.sfxVolume, 15);
    // Clamp at 0.
    for (int i = 0; i < 20; i++) {
      _key(menu, DoomKey.leftArrow);
    }
    expect(menu.sfxVolume, 0);
    expect(sfx.last, 0);
  });

  test('left/right adjust Music volume and fire onMusicVolume (0..15)', () {
    final MenuController menu = MenuController(_gc());
    final List<int> mus = <int>[];
    menu.onMusicVolume = mus.add;
    _intoSound(menu);
    // Move from SFX row down to Music row (skips the spacer between them).
    _key(menu, DoomKey.downArrow);
    expect(menu.current.items[menu.selectedIndex].patchName, 'M_MUSVOL');

    _key(menu, DoomKey.rightArrow);
    expect(menu.musicVolume, 9);
    _key(menu, DoomKey.leftArrow);
    _key(menu, DoomKey.leftArrow);
    expect(menu.musicVolume, 7);
    expect(mus, <int>[9, 8, 7]);
  });

  test('Enter on a slider acts as a right-slide (vanilla status==2)', () {
    final MenuController menu = MenuController(_gc());
    _intoSound(menu);
    expect(menu.sfxVolume, 8);
    _key(menu, DoomKey.enter);
    expect(menu.sfxVolume, 9);
  });

  test('skull navigation skips spacer rows in the Sound menu', () {
    final MenuController menu = MenuController(_gc());
    _intoSound(menu);
    expect(menu.selectedIndex, 0); // SFX
    _key(menu, DoomKey.downArrow);
    expect(menu.selectedIndex, 2); // Music (index 1 is a spacer, skipped)
    _key(menu, DoomKey.downArrow);
    expect(menu.selectedIndex, 0); // wraps past trailing spacer back to SFX
  });

  test('Messages toggles (M_ChangeMessages)', () {
    final MenuController menu = MenuController(_gc());
    menu.open();
    _key(menu, DoomKey.downArrow); // Options
    _key(menu, DoomKey.enter); // open Options
    // Navigate to Messages (M_MESSG).
    while (menu.current.items[menu.selectedIndex].patchName != 'M_MESSG') {
      _key(menu, DoomKey.downArrow);
    }
    expect(menu.showMessages, isTrue);
    _key(menu, DoomKey.enter);
    expect(menu.showMessages, isFalse);
    _key(menu, DoomKey.enter);
    expect(menu.showMessages, isTrue);
  });

  test('Backspace backs Sound -> Options -> Main; Escape closes', () {
    final MenuController menu = MenuController(_gc());
    _intoSound(menu);
    _key(menu, DoomKey.backspace);
    expect(menu.current.name, 'options');
    _key(menu, DoomKey.backspace);
    expect(menu.current.name, 'main');
    _key(menu, DoomKey.escape);
    expect(menu.active, isFalse);
  });

  test('Sound menu draws the thermometers (non-empty frame)', () {
    final MenuController menu = MenuController(_gc());
    _intoSound(menu);
    final Framebuffer fb = Framebuffer()..clear(0);
    menu.draw(fb);
    int nonZero = 0;
    for (int i = 0; i < fb.pixels.length; i++) {
      if (fb.pixels[i] != 0) nonZero++;
    }
    expect(nonZero, greaterThan(100));
  });

  // End-to-end: the GameState routes menu volume changes through the config
  // callbacks to the (recording) integration layer.
  test('GameState routes menu volume -> config.onSfxVolume/onMusicVolume', () {
    final WadFile wad = _wad();
    final List<int> sfx = <int>[];
    final List<int> mus = <int>[];
    final GameState gs = GameState(GameStateConfig(
      wad: wad,
      world: World.fromWad(wad),
      playerStatus: DummyPlayerStatus(),
      worldView: (Framebuffer fb) {},
      onSfxVolume: sfx.add,
      onMusicVolume: mus.add,
    ));

    gs.menu.open();
    _intoSound(gs.menu);
    _key(gs.menu, DoomKey.rightArrow); // SFX 8 -> 9
    _key(gs.menu, DoomKey.downArrow); // -> Music row
    _key(gs.menu, DoomKey.leftArrow); // Music 8 -> 7

    expect(sfx, <int>[9]);
    expect(mus, <int>[7]);
  });
}
