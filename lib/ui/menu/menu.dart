// Menu system (m_menu.c port): the main menu, episode + skill selection, and a
// basic options menu. Renders the Doom menu graphics (M_DOOM banner, item
// patches, M_SKULL animated cursor) into the indexed [Framebuffer]. Input is
// routed through [responder] (M_Responder).
//
// Items that depend on subsystems this module does not own (sound volume,
// detail, save/load) are present for layout fidelity but their actions are
// stubs that post a callback or do nothing — documented in CONTRACTS_STATE.md.

import '../../engine/input/doomkeys.dart';
import '../../engine/input/event.dart';
import '../../engine/video/framebuffer.dart';
import '../../engine/video/patch.dart';
import '../hud/fonts.dart';
import '../hud/graphics_cache.dart';

/// SWSTRING (d_englsh.h): shown when a shareware player picks an episode beyond
/// episode 1 (vanilla M_Episode -> M_StartMessage(SWSTRING)).
const String _swString =
    'This is the shareware version of doom.\n\n'
    'You need to order the entire trilogy.\n\n'
    'Press a key.';

/// A single selectable menu item.
class MenuItem {
  MenuItem(this.patchName, this.onSelect, {this.altText});

  /// Lump name of the item's graphic (e.g. "M_NGAME"). May be null for a
  /// text-only / spacer item.
  final String? patchName;

  /// Fallback text drawn with the HUD font if the patch is missing.
  final String? altText;

  /// Invoked when the item is chosen (Enter / right on a selector). Receives
  /// the controller so it can navigate. Null = inert.
  final void Function(MenuController c)? onSelect;
}

/// A menu definition (menu_t): a banner, a list of items, a draw origin, and
/// optionally a parent to return to on Escape/Backspace.
class MenuDef {
  MenuDef({
    required this.name,
    required this.items,
    this.bannerPatch,
    this.x = 97,
    this.y = 64,
    this.lineHeight = 16,
    this.parent,
  });

  final String name;
  final List<MenuItem> items;

  /// Title banner lump (e.g. M_DOOM for the main menu); null for none.
  final String? bannerPatch;

  /// Top-left of the first item (vanilla menu_t.x / y).
  final int x;
  final int y;

  /// Vertical spacing between items (LINEHEIGHT = 16).
  final int lineHeight;

  /// Menu to return to on cancel, or null (cancel closes the menu).
  MenuDef? parent;

  int selected = 0;
}

/// Drives the menu state machine and draws it.
class MenuController {
  MenuController(this._gc, {this.shareware = false}) {
    _font = HudFont.stcfn(_gc);
    _buildMenus();
  }

  final GraphicsCache _gc;
  late final HudFont _font;

  /// Shareware gating. When true (vanilla M_Episode shareware branch) choosing
  /// an episode other than 1 pops the SWSTRING message instead of starting.
  /// Defaults to false here: ALL listed episodes are selectable and fire
  /// onNewGame(episode, skill); the integration layer's G_InitNew decides what
  /// to actually load (and falls back to E1M1 if the chosen episode's map is
  /// absent from the loaded WAD).
  final bool shareware;

  /// Whether the menu is currently shown (menuactive).
  bool active = false;

  /// Active message-box text (M_StartMessage), or null. While set, the menu
  /// shows the message and any key dismisses it (messageToPrint / messageNeedsInput).
  String? _message;

  /// The currently-shown message text, or null (exposed for tests).
  String? get message => _message;

  /// The currently displayed menu.
  late MenuDef current;

  late MenuDef _mainMenu;
  late MenuDef _episodeMenu;
  late MenuDef _skillMenu;
  late MenuDef _optionsMenu;

  // Skull cursor animation (M_SKULL1/2 swap every ~8 tics, vanilla skullAnimCounter).
  int _skullCounter = 0;
  int _skullFrame = 0;
  static const int _skullAnimTics = 8;

  // Chosen episode / skill (episode fixed to 0 for shareware).
  int chosenEpisode = 0;
  int chosenSkill = 2;

  /// Callback fired when the player confirms a new game (episode, skill). The
  /// integration layer wires this to G_DeferedInitNew. Null = no-op.
  void Function(int episode, int skill)? onNewGame;

  /// Callback when "Quit Game" is chosen.
  void Function()? onQuit;

  void _buildMenus() {
    // Skill selection (M_SKILL): 5 difficulties.
    _skillMenu = MenuDef(
      name: 'skill',
      bannerPatch: 'M_NEWG',
      x: 48,
      y: 63,
      items: <MenuItem>[
        MenuItem('M_JKILL', (MenuController c) => c._startGame(0),
            altText: "I'm too young to die"),
        MenuItem('M_ROUGH', (MenuController c) => c._startGame(1),
            altText: 'Hey, not too rough'),
        MenuItem('M_HURT', (MenuController c) => c._startGame(2),
            altText: 'Hurt me plenty'),
        MenuItem('M_ULTRA', (MenuController c) => c._startGame(3),
            altText: 'Ultra-Violence'),
        MenuItem('M_NMARE', (MenuController c) => c._startGame(4),
            altText: 'Nightmare!'),
      ],
    );

    // Episode selection (M_EPISOD). Shareware only has episode 1, but we list
    // the patch and gate selection.
    _episodeMenu = MenuDef(
      name: 'episode',
      bannerPatch: 'M_EPISOD',
      x: 48,
      y: 63,
      items: <MenuItem>[
        MenuItem('M_EPI1', (MenuController c) => c._chooseEpisode(0),
            altText: 'Knee-Deep in the Dead'),
        MenuItem('M_EPI2', (MenuController c) => c._chooseEpisode(1),
            altText: 'The Shores of Hell'),
        MenuItem('M_EPI3', (MenuController c) => c._chooseEpisode(2),
            altText: 'Inferno'),
      ],
    );

    // Options (M_OPTION) — most actions stubbed (owned by another agent).
    _optionsMenu = MenuDef(
      name: 'options',
      bannerPatch: 'M_OPTTTL',
      x: 60,
      y: 37,
      items: <MenuItem>[
        MenuItem('M_ENDGAM', null, altText: 'End Game'),
        MenuItem('M_MESSG', null, altText: 'Messages: ON'),
        MenuItem('M_DETAIL', null, altText: 'Graphic Detail: HIGH'),
        MenuItem('M_SCRNSZ', null, altText: 'Screen Size'),
        MenuItem('M_MSENS', null, altText: 'Mouse Sensitivity'),
        MenuItem('M_SVOL', null, altText: 'Sound Volume'),
      ],
    );

    // Main menu (M_DOOM banner). Shareware hides "Read This!" episode 4 etc.
    _mainMenu = MenuDef(
      name: 'main',
      bannerPatch: 'M_DOOM',
      x: 97,
      y: 64,
      items: <MenuItem>[
        MenuItem('M_NGAME', (MenuController c) => c._enter(c._episodeMenu),
            altText: 'New Game'),
        MenuItem('M_OPTION', (MenuController c) => c._enter(c._optionsMenu),
            altText: 'Options'),
        MenuItem('M_LOADG', null, altText: 'Load Game'),
        MenuItem('M_SAVEG', null, altText: 'Save Game'),
        MenuItem('M_RDTHIS', null, altText: 'Read This!'),
        MenuItem('M_QUITG', (MenuController c) => c._quit(),
            altText: 'Quit Game'),
      ],
    );

    _episodeMenu.parent = _mainMenu;
    _optionsMenu.parent = _mainMenu;
    _skillMenu.parent = _episodeMenu;
    current = _mainMenu;
  }

  /// Open the main menu (M_StartControlPanel).
  void open() {
    active = true;
    current = _mainMenu;
    _message = null;
  }

  /// Close the menu (M_ClearMenus).
  void close() {
    active = false;
    _message = null;
  }

  void _enter(MenuDef m) {
    m.selected = 0;
    current = m;
  }

  void _chooseEpisode(int ep) {
    // M_Episode (shareware branch): only episode 1 (index 0) is playable; any
    // other choice pops the SWSTRING message and stays on the episode menu.
    if (shareware && ep != 0) {
      _message = _swString;
      return;
    }
    chosenEpisode = ep;
    _enter(_skillMenu);
  }

  void _startGame(int skill) {
    chosenSkill = skill;
    active = false;
    onNewGame?.call(chosenEpisode, skill);
  }

  void _quit() {
    onQuit?.call();
  }

  /// Advance the cursor animation one tic (M_Ticker).
  void tick() {
    if (++_skullCounter >= _skullAnimTics) {
      _skullCounter = 0;
      _skullFrame ^= 1;
    }
  }

  /// Handle a key event (M_Responder). Returns true if the menu consumed it.
  /// The state machine should only call this while [active], except for the
  /// Escape key that opens the menu (handled by the state machine itself).
  bool responder(DoomEvent ev) {
    if (ev.type != EventType.keyDown) return false;
    if (!active) return false;
    // M_Responder messageToPrint branch: while a message box is up, any key
    // dismisses it and the event is consumed (no menu navigation).
    if (_message != null) {
      _message = null;
      return true;
    }
    final int key = ev.data1;
    final MenuDef m = current;
    switch (key) {
      case DoomKey.downArrow:
        _moveCursor(1);
        return true;
      case DoomKey.upArrow:
        _moveCursor(-1);
        return true;
      case DoomKey.enter:
      case DoomKey.rightArrow:
        final MenuItem item = m.items[m.selected];
        item.onSelect?.call(this);
        return true;
      case DoomKey.escape:
        close();
        return true;
      case DoomKey.backspace:
      case DoomKey.leftArrow:
        if (m.parent != null) {
          current = m.parent!;
        } else {
          close();
        }
        return true;
    }
    return false;
  }

  void _moveCursor(int delta) {
    final MenuDef m = current;
    final int n = m.items.length;
    if (n == 0) return;
    m.selected = (m.selected + delta) % n;
    if (m.selected < 0) m.selected += n;
  }

  /// Index of the currently highlighted item (for tests / integration).
  int get selectedIndex => current.selected;

  /// Draw the active menu (M_Drawer). No-op if not [active].
  void draw(Framebuffer fb) {
    if (!active) return;
    // M_Drawer messageToPrint branch: a message box replaces the menu items.
    if (_message != null) {
      _drawMessage(fb, _message!);
      return;
    }
    final MenuDef m = current;
    // Banner.
    if (m.bannerPatch != null) {
      final Patch? p = _gc.patch(m.bannerPatch!);
      if (p != null) {
        // Centre the banner horizontally near the top (vanilla draws M_DOOM at
        // 94,2 but we centre for portability).
        final int bx = (kScreenWidth - p.width) ~/ 2;
        p.draw(fb, bx, 2);
      }
    }
    // Items.
    for (int i = 0; i < m.items.length; i++) {
      final MenuItem item = m.items[i];
      final int iy = m.y + i * m.lineHeight;
      if (item.patchName != null) {
        _gc.draw(fb, item.patchName!, m.x, iy);
      }
    }
    // Skull cursor to the left of the selected item (vanilla SKULLXOFF = -32).
    final String skull = _skullFrame == 0 ? 'M_SKULL1' : 'M_SKULL2';
    final int cy = m.y - 5 + m.selected * m.lineHeight;
    _gc.draw(fb, skull, m.x - 32, cy);
  }

  /// M_Drawer message box: centre each '\n'-separated line vertically, using the
  /// STCFN HUD font (vanilla draws the message via the small font).
  void _drawMessage(Framebuffer fb, String text) {
    final List<String> lines = text.split('\n');
    final int lineH = _font.height;
    int y = (kScreenHeight - lines.length * lineH) ~/ 2;
    for (final String line in lines) {
      final int w = _font.widthOf(line);
      final int x = (kScreenWidth - w) ~/ 2;
      _font.draw(fb, x, y, line);
      y += lineH;
    }
  }
}
