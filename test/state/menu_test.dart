import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flu_doom/engine/video/framebuffer.dart';
import 'package:flu_doom/engine/wad/wad.dart';
import 'package:flu_doom/engine/input/doomkeys.dart';
import 'package:flu_doom/engine/input/event.dart';
import 'package:flu_doom/ui/hud/graphics_cache.dart';
import 'package:flu_doom/ui/menu/menu.dart';

GraphicsCache _gc() {
  final Uint8List bytes =
      Uint8List.fromList(File('assets/doom1.wad').readAsBytesSync());
  return GraphicsCache(WadFile.fromBytes(bytes));
}

void main() {
  test('main menu graphics lumps load (M_DOOM, items, skull)', () {
    final GraphicsCache gc = _gc();
    expect(gc.has('M_DOOM'), isTrue);
    expect(gc.has('M_NGAME'), isTrue);
    expect(gc.has('M_OPTION'), isTrue);
    expect(gc.has('M_SKULL1'), isTrue);
  });

  test('M_Responder navigation changes selection', () {
    final MenuController menu = MenuController(_gc());
    menu.open();
    expect(menu.active, isTrue);
    expect(menu.selectedIndex, 0);

    menu.responder(const DoomEvent.keyDown(DoomKey.downArrow));
    expect(menu.selectedIndex, 1);

    menu.responder(const DoomEvent.keyDown(DoomKey.downArrow));
    expect(menu.selectedIndex, 2);

    menu.responder(const DoomEvent.keyDown(DoomKey.upArrow));
    expect(menu.selectedIndex, 1);
  });

  test('selecting New Game opens episode then skill, then fires onNewGame', () {
    final MenuController menu = MenuController(_gc());
    int? gotEpisode;
    int? gotSkill;
    menu.onNewGame = (int ep, int sk) {
      gotEpisode = ep;
      gotSkill = sk;
    };
    menu.open();
    expect(menu.current.name, 'main');

    // Enter on "New Game" -> episode menu.
    menu.responder(const DoomEvent.keyDown(DoomKey.enter));
    expect(menu.current.name, 'episode');

    // Choose episode 1 -> skill menu.
    menu.responder(const DoomEvent.keyDown(DoomKey.enter));
    expect(menu.current.name, 'skill');

    // Move to "Hurt me plenty" (index 2) and confirm.
    menu.responder(const DoomEvent.keyDown(DoomKey.downArrow));
    menu.responder(const DoomEvent.keyDown(DoomKey.downArrow));
    menu.responder(const DoomEvent.keyDown(DoomKey.enter));

    expect(gotEpisode, 0);
    expect(gotSkill, 2);
    expect(menu.active, isFalse);
  });

  test('M_Drawer renders something when active', () {
    final MenuController menu = MenuController(_gc())..open();
    final Framebuffer fb = Framebuffer()..clear(0);
    menu.draw(fb);
    int nonZero = 0;
    for (int i = 0; i < fb.pixels.length; i++) {
      if (fb.pixels[i] != 0) nonZero++;
    }
    expect(nonZero, greaterThan(100),
        reason: 'banner + items + skull should draw');
  });

  test('Escape / Backspace navigate back and close', () {
    final MenuController menu = MenuController(_gc())..open();
    menu.responder(const DoomEvent.keyDown(DoomKey.enter)); // -> episode
    expect(menu.current.name, 'episode');
    menu.responder(const DoomEvent.keyDown(DoomKey.backspace)); // -> main
    expect(menu.current.name, 'main');
    menu.responder(const DoomEvent.keyDown(DoomKey.escape)); // close
    expect(menu.active, isFalse);
  });
}
