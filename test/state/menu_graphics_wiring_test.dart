// The in-game Options menu Graphic Detail + Screen Size items are wired to the
// present layer (not dead labels). These tests drive M_ChangeDetail /
// M_SizeDisplay through the public MenuController and assert the callbacks fire
// with the right values and the underlying state toggles.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flu_doom/engine/input/doomkeys.dart';
import 'package:flu_doom/engine/input/event.dart';
import 'package:flu_doom/engine/wad/wad.dart';
import 'package:flu_doom/ui/hud/graphics_cache.dart';
import 'package:flu_doom/ui/menu/menu.dart';

GraphicsCache _gc() {
  final Uint8List bytes =
      Uint8List.fromList(File('assets/doom1.wad').readAsBytesSync());
  return GraphicsCache(WadFile.fromBytes(bytes));
}

void main() {
  test('Graphic Detail toggle flips detailLevel and fires onDetailChanged', () {
    final MenuController menu = MenuController(_gc());
    final List<int> fired = <int>[];
    menu.onDetailChanged = fired.add;

    expect(menu.detailLevel, 0); // HIGH by default

    // M_ChangeDetail is invoked via the menu item's onSelect.
    final MenuItem detailItem = _optionsItem(menu, 'M_DETAIL');
    detailItem.onSelect!(menu);
    expect(menu.detailLevel, 1); // LOW
    expect(fired, <int>[1]);

    detailItem.onSelect!(menu);
    expect(menu.detailLevel, 0); // back to HIGH
    expect(fired, <int>[1, 0]);
  });

  test('Screen Size slider fires onScreenSize with the new value', () {
    final MenuController menu = MenuController(_gc());
    final List<int> fired = <int>[];
    menu.onScreenSize = fired.add;

    expect(menu.screenSize, 8); // full by default

    final MenuItem sizeItem = _optionsItem(menu, 'M_SCRNSZ');
    // choice 0 = decrement.
    sizeItem.onSlide!(menu, 0);
    expect(menu.screenSize, 7);
    expect(fired.last, 7);

    // choice 1 = increment.
    sizeItem.onSlide!(menu, 1);
    expect(menu.screenSize, 8);
    expect(fired.last, 8);
  });
}

/// Navigate to the Options submenu and return the item with the given patch.
/// Main menu order: New Game(0), Options(1). Move to Options and Enter.
MenuItem _optionsItem(MenuController menu, String patch) {
  menu.open();
  while (menu.selectedIndex != 1) {
    menu.responder(const DoomEvent.keyDown(DoomKey.downArrow));
  }
  menu.responder(const DoomEvent.keyDown(DoomKey.enter));
  return menu.current.items.firstWhere((i) => i.patchName == patch);
}
