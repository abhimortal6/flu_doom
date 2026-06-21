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

/// menuitem_t.status (m_menu.c). -1 = spacer (skipped by up/down navigation and
/// not selectable); 1 = a normal item (Enter activates `onSelect`); 2 = a slider
/// item (left/right arrows adjust it via `onSlide(choice)`, Enter == right).
enum MenuItemStatus { spacer, normal, slider }

/// A single selectable menu item (menuitem_t).
class MenuItem {
  MenuItem(
    this.patchName,
    this.onSelect, {
    this.altText,
    this.status = MenuItemStatus.normal,
    this.onSlide,
  });

  /// A status-2 slider item: left/right adjust it via [onSlide], drawn with a
  /// thermometer. [thermWidth] is the number of cells (M_DrawThermo's
  /// thermWidth) and [thermDot] returns the current 0..thermWidth-1 dot.
  MenuItem.slider(
    this.patchName, {
    required this.onSlide,
    required this.thermWidth,
    required this.thermDot,
    this.altText,
  })  : status = MenuItemStatus.slider,
        onSelect = null;

  /// A spacer row (menuitem_t.status == -1): not navigable, no action. Used by
  /// the Options/Sound menus where a thermometer occupies the row *below* its
  /// label.
  MenuItem.spacer()
      : patchName = null,
        altText = null,
        status = MenuItemStatus.spacer,
        onSelect = null,
        onSlide = null,
        thermWidth = 0,
        thermDot = null;

  /// Lump name of the item's graphic (e.g. "M_NGAME"). May be null for a
  /// text-only / spacer item.
  final String? patchName;

  /// Fallback text drawn with the HUD font if the patch is missing.
  final String? altText;

  /// menuitem_t.status: spacer / normal / slider.
  final MenuItemStatus status;

  /// Invoked when a normal item is chosen (Enter). Receives the controller so it
  /// can navigate. Null = inert.
  final void Function(MenuController c)? onSelect;

  /// Invoked for a slider item with the vanilla `choice`: 0 = left (decrement),
  /// 1 = right (increment). Mirrors M_SfxVol/M_MusicVol/M_SizeDisplay.
  void Function(MenuController c, int choice)? onSlide;

  /// Slider cell count (M_DrawThermo thermWidth). 0 for non-sliders.
  int thermWidth = 0;

  /// Returns the current thermometer dot position (0..thermWidth-1) for a
  /// slider item, or null for non-sliders.
  int Function()? thermDot;
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
  late MenuDef _soundMenu;

  // --- Options/Sound state (the vanilla globals these menus mutate) ---

  /// sfxVolume (user scale 0..15). M_SfxVol clamps; M_DrawSound thermDot.
  int sfxVolume = 8;

  /// musicVolume (user scale 0..15). M_MusicVol clamps; M_DrawSound thermDot.
  int musicVolume = 8;

  /// screenSize (0..8, vanilla screenblocks 3..11). M_SizeDisplay. STUB: not
  /// wired to a real R_SetViewSize yet (the renderer always draws full size), so
  /// adjusting this only moves the thermometer — see CONTRACTS_STATE.md.
  int screenSize = 8;

  /// mouseSensitivity (0..9, M_DrawThermo width 10). STUB: not consumed by the
  /// input layer here (mouse look is owned by another agent) — purely cosmetic.
  int mouseSensitivity = 5;

  /// showMessages (M_ChangeMessages toggles 1<->0). Functional flag; the HUD
  /// message system can read [showMessages] but the wiring to suppress messages
  /// is the integration layer's call (currently just toggles the label).
  bool showMessages = true;

  /// detailLevel (0 = HIGH, 1 = LOW). M_ChangeDetail toggles.
  ///
  /// The 3D renderer has no low-detail (column-doubling) mode — it always draws
  /// full 320x200 (see CONTRACTS_RENDER.md deviation #2). Rather than leave this
  /// a dead label, the integration layer maps it to the PRESENT-layer upscale
  /// filter: HIGH (0) -> SMOOTH (bilinear), LOW (1) -> SHARP (nearest/pixelated).
  /// Toggling it therefore changes something visible. Fired via [onDetailChanged].
  int detailLevel = 0;

  /// screenSize is wired to the live present-layer "screen size" via
  /// [onScreenSize] (cosmetic letterboxing of the 320x200 image; the renderer
  /// stays full-size). 0..8 -> a present inset; see integration. Null = no-op.
  void Function(int screenSize0to8)? onScreenSize;

  /// Fired when Graphic Detail toggles, with the new detailLevel (0 HIGH/smooth,
  /// 1 LOW/sharp). Integration maps it to the upscale filter. Null = no-op.
  void Function(int detailLevel)? onDetailChanged;

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

  /// Fired whenever the SFX volume changes (M_SfxVol -> S_SetSfxVolume), with
  /// the user-scale value 0..15. Integration wires this to
  /// SfxSoundHook.setSfxVolume. Null = no-op.
  void Function(int volume0to15)? onSfxVolume;

  /// Fired whenever the music volume changes (M_MusicVol -> S_SetMusicVolume),
  /// with the user-scale value 0..15. Integration wires this to
  /// MusicEngine.setMusicVolume. Null = no-op.
  void Function(int volume0to15)? onMusicVolume;

  /// Fired when "End Game" is confirmed (M_EndGameResponse -> D_StartTitle).
  /// Integration returns to the title/demo screen. Null = no-op.
  void Function()? onEndGame;

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

    // Sound Volume (SoundDef): SFX + Music thermometers (0..15). Each label sits
    // on its row with a spacer row below it where M_DrawSound draws the
    // thermometer (SoundDef.y + LINEHEIGHT*(item+1)). Faithful to SoundMenu[].
    _soundMenu = MenuDef(
      name: 'sound',
      bannerPatch: 'M_SVOL',
      x: 80,
      y: 64,
      items: <MenuItem>[
        MenuItem.slider(
          'M_SFXVOL',
          altText: 'Sound FX Volume',
          onSlide: (MenuController c, int choice) => c._sfxVol(choice),
          thermWidth: 16,
          thermDot: () => sfxVolume,
        ),
        MenuItem.spacer(),
        MenuItem.slider(
          'M_MUSVOL',
          altText: 'Music Volume',
          onSlide: (MenuController c, int choice) => c._musicVol(choice),
          thermWidth: 16,
          thermDot: () => musicVolume,
        ),
        MenuItem.spacer(),
      ],
    );

    // Options (OptionsDef). Faithful to OptionsMenu[]: End Game, Messages,
    // Detail, Screen Size (slider, spacer below), Mouse Sensitivity (slider,
    // spacer below), Sound Volume. Spacer rows host the thermometers drawn one
    // line below their label.
    _optionsMenu = MenuDef(
      name: 'options',
      bannerPatch: 'M_OPTTTL',
      x: 60,
      y: 37,
      items: <MenuItem>[
        MenuItem('M_ENDGAM', (MenuController c) => c._endGame(),
            altText: 'End Game'),
        MenuItem('M_MESSG', (MenuController c) => c._changeMessages(),
            altText: 'Messages'),
        MenuItem('M_DETAIL', (MenuController c) => c._changeDetail(),
            altText: 'Graphic Detail'),
        MenuItem.slider(
          'M_SCRNSZ',
          altText: 'Screen Size',
          onSlide: (MenuController c, int choice) => c._sizeDisplay(choice),
          thermWidth: 9,
          thermDot: () => screenSize,
        ),
        MenuItem.spacer(),
        MenuItem.slider(
          'M_MSENS',
          altText: 'Mouse Sensitivity',
          onSlide: (MenuController c, int choice) =>
              c._changeSensitivity(choice),
          thermWidth: 10,
          thermDot: () => mouseSensitivity,
        ),
        MenuItem.spacer(),
        MenuItem('M_SVOL', (MenuController c) => c._enter(c._soundMenu),
            altText: 'Sound Volume'),
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
    _soundMenu.parent = _optionsMenu;
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
    // Land on the first selectable (non-spacer) item, like vanilla menus whose
    // first row is always selectable.
    m.selected = 0;
    while (m.selected < m.items.length &&
        m.items[m.selected].status == MenuItemStatus.spacer) {
      m.selected++;
    }
    if (m.selected >= m.items.length) m.selected = 0;
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

  // --- Options/Sound handlers (m_menu.c) ---

  /// M_SfxVol: choice 0 decrements, 1 increments sfxVolume (clamped 0..15), then
  /// S_SetSfxVolume(sfxVolume*8) — routed out via [onSfxVolume].
  void _sfxVol(int choice) {
    if (choice == 0) {
      if (sfxVolume > 0) sfxVolume--;
    } else {
      if (sfxVolume < 15) sfxVolume++;
    }
    onSfxVolume?.call(sfxVolume);
  }

  /// M_MusicVol: choice 0 decrements, 1 increments musicVolume (clamped 0..15),
  /// then S_SetMusicVolume — routed out via [onMusicVolume].
  void _musicVol(int choice) {
    if (choice == 0) {
      if (musicVolume > 0) musicVolume--;
    } else {
      if (musicVolume < 15) musicVolume++;
    }
    onMusicVolume?.call(musicVolume);
  }

  /// M_SizeDisplay: choice 0/1 decrements/increments screenSize (0..8). The
  /// renderer stays full 320x200; integration maps screenSize to a present-layer
  /// inset (letterbox) of the displayed image via [onScreenSize], so shrinking it
  /// is visible without touching the render math — see CONTRACTS_STATE.md.
  void _sizeDisplay(int choice) {
    if (choice == 0) {
      if (screenSize > 0) screenSize--;
    } else {
      if (screenSize < 8) screenSize++;
    }
    onScreenSize?.call(screenSize);
  }

  /// M_ChangeSensitivity: choice 0/1 decrements/increments mouseSensitivity
  /// (0..9). STUB: not consumed by the input layer here — cosmetic only.
  void _changeSensitivity(int choice) {
    if (choice == 0) {
      if (mouseSensitivity > 0) mouseSensitivity--;
    } else {
      if (mouseSensitivity < 9) mouseSensitivity++;
    }
  }

  /// M_ChangeMessages: toggle showMessages on/off.
  void _changeMessages() {
    showMessages = !showMessages;
  }

  /// M_ChangeDetail: toggle detailLevel HIGH<->LOW. Wired to the present-layer
  /// upscale filter via [onDetailChanged] (HIGH=smooth, LOW=sharp).
  void _changeDetail() {
    detailLevel = 1 - detailLevel;
    onDetailChanged?.call(detailLevel);
  }

  /// M_EndGame -> M_EndGameResponse -> D_StartTitle. Returns to the title/demo
  /// screen and closes the menu. (Vanilla pops a confirm message box first; we
  /// route straight out — noted in CONTRACTS_STATE.md.)
  void _endGame() {
    active = false;
    onEndGame?.call();
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
      case DoomKey.leftArrow:
        // M_Responder key_menu_left: slide a slider item left (choice 0); other
        // items ignore it but the key is still consumed.
        final MenuItem li = m.items[m.selected];
        if (li.status == MenuItemStatus.slider && li.onSlide != null) {
          li.onSlide!(this, 0);
        }
        return true;
      case DoomKey.rightArrow:
        // M_Responder key_menu_right: slide a slider item right (choice 1);
        // other items ignore it (Enter activates them instead).
        final MenuItem ri = m.items[m.selected];
        if (ri.status == MenuItemStatus.slider && ri.onSlide != null) {
          ri.onSlide!(this, 1);
        }
        return true;
      case DoomKey.enter:
        // M_Responder key_menu_forward: activate. For a slider this is a
        // right-slide; for a normal item it runs onSelect.
        final MenuItem item = m.items[m.selected];
        if (item.status == MenuItemStatus.slider && item.onSlide != null) {
          item.onSlide!(this, 1);
        } else {
          item.onSelect?.call(this);
        }
        return true;
      case DoomKey.escape:
        close();
        return true;
      case DoomKey.backspace:
        // M_Responder key_menu_back: go to the previous menu (or close at root).
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
    // Skip spacer rows (menuitem_t.status == -1), like vanilla's do/while.
    int next = m.selected;
    for (int i = 0; i < n; i++) {
      next = (next + delta) % n;
      if (next < 0) next += n;
      if (m.items[next].status != MenuItemStatus.spacer) break;
    }
    m.selected = next;
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
    // Centre the 320-wide menu on a wider (widescreen) framebuffer. 0 at 320.
    final int ox = (fb.width - kScreenWidth) ~/ 2;
    final MenuDef m = current;
    // Banner.
    if (m.bannerPatch != null) {
      final Patch? p = _gc.patch(m.bannerPatch!);
      if (p != null) {
        // Centre the banner horizontally near the top on the FULL screen width
        // (vanilla draws M_DOOM at 94,2 but we centre for portability).
        final int bx = (fb.width - p.width) ~/ 2;
        p.draw(fb, bx, 2);
      }
    }
    // Items.
    for (int i = 0; i < m.items.length; i++) {
      final MenuItem item = m.items[i];
      final int iy = m.y + i * m.lineHeight;
      if (item.patchName != null) {
        _gc.draw(fb, item.patchName!, ox + m.x, iy);
      }
      // Slider items draw a thermometer one row BELOW the label (M_DrawThermo at
      // y + LINEHEIGHT*(item+1)), exactly as M_DrawSound / M_DrawOptions.
      if (item.status == MenuItemStatus.slider && item.thermDot != null) {
        _drawThermo(fb, ox + m.x, iy + m.lineHeight, item.thermWidth,
            item.thermDot!().clamp(0, item.thermWidth - 1));
      }
    }
    // Skull cursor to the left of the selected item (vanilla SKULLXOFF = -32).
    final String skull = _skullFrame == 0 ? 'M_SKULL1' : 'M_SKULL2';
    final int cy = m.y - 5 + m.selected * m.lineHeight;
    _gc.draw(fb, skull, ox + m.x - 32, cy);
  }

  /// M_DrawThermo (m_menu.c): the volume/size slider. M_THERML left cap, then
  /// [thermWidth] M_THERMM cells, an M_THERMR right cap, and the M_THERMO dot at
  /// (x+8) + thermDot*8.
  void _drawThermo(Framebuffer fb, int x, int y, int thermWidth, int thermDot) {
    int xx = x;
    _gc.draw(fb, 'M_THERML', xx, y);
    xx += 8;
    for (int i = 0; i < thermWidth; i++) {
      _gc.draw(fb, 'M_THERMM', xx, y);
      xx += 8;
    }
    _gc.draw(fb, 'M_THERMR', xx, y);
    _gc.draw(fb, 'M_THERMO', (x + 8) + thermDot * 8, y);
  }

  /// M_Drawer message box: centre each '\n'-separated line vertically, using the
  /// STCFN HUD font (vanilla draws the message via the small font). Centres
  /// horizontally on the FULL screen width (widescreen-aware).
  void _drawMessage(Framebuffer fb, String text) {
    final List<String> lines = text.split('\n');
    final int lineH = _font.height;
    int y = (kScreenHeight - lines.length * lineH) ~/ 2;
    for (final String line in lines) {
      final int w = _font.widthOf(line);
      final int x = (fb.width - w) ~/ 2;
      _font.draw(fb, x, y, line);
      y += lineH;
    }
  }
}
