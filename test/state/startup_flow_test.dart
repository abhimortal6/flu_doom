// Startup-flow test: faithful D_StartTitle -> M_NewGame -> M_Episode ->
// M_ChooseSkill -> G_InitNew boot path.
//
// Verifies the game boots to the TITLE screen (GS_DEMOSCREEN, NOT GS_LEVEL),
// that a key opens the main menu, and that New Game -> episode 1 -> a skill
// fires onStartNewGame (G_InitNew), entering GS_LEVEL with E1M1 freshly loaded
// and the player at the G_PlayerReborn starting loadout. Re-running New Game
// re-inits cleanly.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:flu_doom/engine/input/doomkeys.dart';
import 'package:flu_doom/engine/input/event.dart';
import 'package:flu_doom/game/play/info_tables.dart';
import 'package:flu_doom/game/play/playsim.dart';
import 'package:flu_doom/game/play/spawn.dart' show Skill;
import 'package:flu_doom/game/state/game_state.dart';
import 'package:flu_doom/game/integration/player_status_adapter.dart';
import 'package:flu_doom/game/world/world.dart';
import 'package:flu_doom/engine/video/framebuffer.dart';
import 'package:flu_doom/engine/wad/wad.dart';

/// Build a GameState wired to a real PlaySim exactly as doom_game.dart does
/// (minus the renderer/audio), so onStartNewGame runs the real G_InitNew.
({GameState gs, PlaySim sim, List<int> newGameCalls}) _build() {
  final WadFile wad = WadFile.fromBytes(
      Uint8List.fromList(File('assets/doom1.wad').readAsBytesSync()));
  final PlaySim sim = PlaySim(World.fromWad(wad, mapName: 'E1M1'));
  sim.spawnLevel();

  final List<int> newGameCalls = <int>[];
  late final GameState gs;
  gs = GameState(GameStateConfig(
    wad: wad,
    world: sim.world,
    playerStatus: PlayerStatusAdapter(sim.player),
    worldView: (Framebuffer fb) => fb.clear(96),
    onStartNewGame: (int episode, int skill) {
      newGameCalls.add(skill);
      sim.newGame(episode + 1, skill, 1);
    },
  ));
  gs.enterDemoScreen();
  return (gs: gs, sim: sim, newGameCalls: newGameCalls);
}

void _key(GameState gs, int k) =>
    gs.ticker(<DoomEvent>[DoomEvent.keyDown(k)]);

void main() {
  test('boots to the title screen (GS_DEMOSCREEN), not a level', () {
    final b = _build();
    expect(b.gs.gamestate, GameStateType.demoScreen,
        reason: 'D_StartTitle: boot shows TITLEPIC, not GS_LEVEL');
    expect(b.gs.menu.active, isFalse);
  });

  test('a key on the title opens the main menu', () {
    final b = _build();
    _key(b.gs, DoomKey.enter);
    expect(b.gs.menu.active, isTrue);
    expect(b.gs.menu.current.name, 'main');
  });

  test('New Game -> episode 1 -> skill fires G_InitNew and starts E1M1 fresh',
      () {
    final b = _build();
    final PlaySim sim = b.sim;

    // Dirty the player so we can prove the new game does a FULL fresh init.
    sim.player.health = 7;
    sim.player.weaponOwned[Wp.shotgun] = 1;
    sim.player.ammo[Am.clip] = 999;

    // Open the menu from the title.
    _key(b.gs, DoomKey.escape);
    expect(b.gs.menu.active, isTrue);

    // Main menu: New Game is the first item; Enter advances to the episode menu.
    expect(b.gs.menu.current.name, 'main');
    _key(b.gs, DoomKey.enter);
    expect(b.gs.menu.current.name, 'episode');

    // Episode menu: episode 1 (index 0) is selected; Enter advances to skill.
    _key(b.gs, DoomKey.enter);
    expect(b.gs.menu.current.name, 'skill');
    expect(b.gs.menu.message, isNull, reason: 'episode 1 is playable shareware');

    // Skill menu: pick "Hurt me plenty" (index 2). Enter starts the game.
    _key(b.gs, DoomKey.downArrow);
    _key(b.gs, DoomKey.downArrow);
    _key(b.gs, DoomKey.enter);

    // onStartNewGame fired with the chosen skill (index 2).
    expect(b.newGameCalls, <int>[2]);

    // ga_newgame resolved -> GS_LEVEL, menu closed.
    expect(b.gs.gamestate, GameStateType.level);
    expect(b.gs.menu.active, isFalse);

    // E1M1 loaded.
    expect(sim.world.level.name, 'E1M1');
    // gameskill propagated.
    expect(sim.skill, Skill.medium);

    // Fresh G_PlayerReborn loadout (overwriting the dirtied values above).
    expect(sim.player.health, 100);
    expect(sim.player.readyWeapon, Wp.pistol);
    expect(sim.player.weaponOwned[Wp.fist], 1);
    expect(sim.player.weaponOwned[Wp.pistol], 1);
    expect(sim.player.weaponOwned[Wp.shotgun], 0,
        reason: 'no other weapons after a fresh new game');
    expect(sim.player.ammo[Am.clip], 50);
    expect(sim.player.ammo[Am.shell], 0);
    // Fresh level: leveltime reset.
    expect(sim.levelTime, 0);
  });

  test('all episodes selectable: episode 2 starts (falls back to E1M1 in '
      'doom1.wad)', () {
    final b = _build();
    final PlaySim sim = b.sim;
    _key(b.gs, DoomKey.escape); // open menu
    _key(b.gs, DoomKey.enter); // New Game -> episode menu
    _key(b.gs, DoomKey.downArrow); // select episode 2 (index 1)
    _key(b.gs, DoomKey.enter); // choose it -> advances straight to skill

    // No shareware gate by default: episode 2 advances to the skill menu.
    expect(b.gs.menu.message, isNull);
    expect(b.gs.menu.current.name, 'skill');

    _key(b.gs, DoomKey.enter); // start on skill 0
    expect(b.gs.gamestate, GameStateType.level);
    // doom1.wad has no E2M1, so G_InitNew falls back to E1M1.
    expect(sim.world.level.name, 'E1M1');
    expect(sim.player.health, 100);
  });

  test('selecting New Game again re-inits cleanly', () {
    final b = _build();
    final PlaySim sim = b.sim;

    // First new game on Ultra-Violence (index 3).
    _key(b.gs, DoomKey.escape);
    _key(b.gs, DoomKey.enter); // -> episode
    _key(b.gs, DoomKey.enter); // -> skill
    _key(b.gs, DoomKey.downArrow);
    _key(b.gs, DoomKey.downArrow);
    _key(b.gs, DoomKey.downArrow);
    _key(b.gs, DoomKey.enter); // start (skill 3)
    expect(b.gs.gamestate, GameStateType.level);
    expect(sim.skill, Skill.hard);

    // Play a bit so leveltime advances, then start a fresh game again.
    sim.tic();
    sim.tic();
    expect(sim.levelTime, greaterThan(0));
    sim.player.health = 1; // damage carries nothing into the new game

    // Esc opens the menu mid-game; New Game restarts cleanly on skill 0.
    _key(b.gs, DoomKey.escape);
    expect(b.gs.menu.active, isTrue);
    _key(b.gs, DoomKey.enter); // -> episode
    _key(b.gs, DoomKey.enter); // -> skill
    _key(b.gs, DoomKey.enter); // start (skill 0, "too young to die")

    expect(b.gs.gamestate, GameStateType.level);
    expect(sim.skill, Skill.baby);
    expect(sim.world.level.name, 'E1M1');
    expect(sim.levelTime, 0, reason: 'fresh level resets leveltime');
    expect(sim.player.health, 100, reason: 'fresh reborn loadout');
    expect(sim.player.ammo[Am.clip], 50);
  });
}
