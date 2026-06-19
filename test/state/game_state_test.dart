import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flu_doom/engine/video/framebuffer.dart';
import 'package:flu_doom/engine/wad/wad.dart';
import 'package:flu_doom/engine/input/doomkeys.dart';
import 'package:flu_doom/engine/input/event.dart';
import 'package:flu_doom/game/state/dummy_player_status.dart';
import 'package:flu_doom/game/state/game_state.dart';
import 'package:flu_doom/game/state/interfaces.dart';
import 'package:flu_doom/game/world/world.dart';

GameState _build({
  void Function(int, int)? onNewGame,
  void Function()? onAdvance,
  IntermissionStats Function()? stats,
  required List<bool> worldViewCalled,
}) {
  final WadFile wad = WadFile.fromBytes(
      Uint8List.fromList(File('assets/doom1.wad').readAsBytesSync()));
  final World world = World.fromWad(wad, mapName: 'E1M1');
  final config = GameStateConfig(
    wad: wad,
    world: world,
    playerStatus: DummyPlayerStatus(),
    worldView: (Framebuffer fb) {
      worldViewCalled[0] = true;
      fb.clear(96); // simulate a rendered scene (non-zero)
    },
    onStartNewGame: onNewGame,
    onAdvanceLevel: onAdvance,
    statsProvider: stats,
  );
  return GameState(config);
}

void main() {
  test('boots into demo screen and ESC opens the menu', () {
    final called = <bool>[false];
    final GameState gs = _build(worldViewCalled: called);
    expect(gs.gamestate, GameStateType.demoScreen);

    gs.ticker(<DoomEvent>[const DoomEvent.keyDown(DoomKey.escape)]);
    expect(gs.menu.active, isTrue);
  });

  test('GS_LEVEL render calls WorldView then overlays status bar', () {
    final called = <bool>[false];
    final GameState gs = _build(worldViewCalled: called);
    gs.enterLevel();
    final Framebuffer fb = Framebuffer()..clear(0);
    gs.render(fb);
    expect(called[0], isTrue, reason: 'WorldView must be invoked in GS_LEVEL');

    // Bottom rows should carry the status bar (non-zero) and top rows the scene.
    int barNonZero = 0;
    for (int y = 168; y < 200; y++) {
      for (int x = 0; x < fb.width; x++) {
        if (fb.getPixel(x, y) != 0) barNonZero++;
      }
    }
    expect(barNonZero, greaterThan(1000));
  });

  test('completeLevel -> intermission, advance fires onAdvanceLevel', () {
    final called = <bool>[false];
    bool advanced = false;
    final GameState gs = _build(
      worldViewCalled: called,
      onAdvance: () => advanced = true,
      stats: () => IntermissionStats(
        episode: 0,
        lastMap: 0,
        nextMap: 1,
        killCount: 5,
        totalKills: 10,
        itemCount: 2,
        totalItems: 4,
        secretCount: 1,
        totalSecrets: 2,
        levelTimeSeconds: 65,
        parTimeSeconds: 30,
      ),
    );
    gs.enterLevel();
    gs.completeLevel();
    gs.ticker(<DoomEvent>[]); // consume ga_completed
    expect(gs.gamestate, GameStateType.intermission);
    expect(gs.intermission.active, isTrue);

    final Framebuffer fb = Framebuffer()..clear(0);
    gs.render(fb);
    int nonZero = 0;
    for (final int p in fb.pixels) {
      if (p != 0) nonZero++;
    }
    expect(nonZero, greaterThan(500),
        reason: 'intermission background + stats should draw');

    // Press a key during count-up snaps to final; press again advances.
    gs.ticker(<DoomEvent>[const DoomEvent.keyDown(DoomKey.enter)]);
    gs.ticker(<DoomEvent>[const DoomEvent.keyDown(DoomKey.enter)]);
    expect(advanced, isTrue);
    expect(gs.gamestate, GameStateType.level);
  });

  test('automap toggles within GS_LEVEL and replaces the 3D view', () {
    final called = <bool>[false];
    final GameState gs = _build(worldViewCalled: called);
    gs.enterLevel();

    // Tab toggles the automap on (routed via responder while GS_LEVEL).
    gs.ticker(<DoomEvent>[const DoomEvent.keyDown(DoomKey.tab)]);
    expect(gs.automap.active, isTrue);

    called[0] = false;
    final Framebuffer fb = Framebuffer()..clear(0);
    gs.render(fb);
    expect(called[0], isFalse,
        reason: 'with automap up, the 3D WorldView is not drawn');
    expect(gs.automap.linesDrawn, greaterThan(0));
  });
}
