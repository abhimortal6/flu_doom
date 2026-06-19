// Switch textures + buttons, ported 1:1 from Chocolate Doom src/p_switch.c:
//   - alphSwitchList[] (switchlist_t), P_InitSwitchList,
//   - P_StartButton + the button timer (button_t / buttonlist),
//   - P_ChangeSwitchTexture (the switch texture swap + sound).
//
// Faithfulness is mandatory: this is a port, not a paraphrase. C
// file-scope globals (switchlist[], numswitches, buttonlist[]) become instance
// fields on [SwitchManager]. The button countdown that vanilla runs inside
// P_UpdateSpecials runs here from [tickButtons], called once per tic by the
// integration.

import '../../engine/data/textures.dart';
import '../world/defs.dart';
import 'sound_hook.dart';
import 'sounds.dart';

/// switchlist_t: a pair of texture names (off/on) gated by an "episode" rank.
class _SwitchListEntry {
  const _SwitchListEntry(this.name1, this.name2, this.episode);
  final String name1;
  final String name2;
  final int episode;
}

/// alphSwitchList[] (p_switch.c). Verbatim order and rank.
const List<_SwitchListEntry> _alphSwitchList = <_SwitchListEntry>[
  // Doom shareware episode 1 switches
  _SwitchListEntry('SW1BRCOM', 'SW2BRCOM', 1),
  _SwitchListEntry('SW1BRN1', 'SW2BRN1', 1),
  _SwitchListEntry('SW1BRN2', 'SW2BRN2', 1),
  _SwitchListEntry('SW1BRNGN', 'SW2BRNGN', 1),
  _SwitchListEntry('SW1BROWN', 'SW2BROWN', 1),
  _SwitchListEntry('SW1COMM', 'SW2COMM', 1),
  _SwitchListEntry('SW1COMP', 'SW2COMP', 1),
  _SwitchListEntry('SW1DIRT', 'SW2DIRT', 1),
  _SwitchListEntry('SW1EXIT', 'SW2EXIT', 1),
  _SwitchListEntry('SW1GRAY', 'SW2GRAY', 1),
  _SwitchListEntry('SW1GRAY1', 'SW2GRAY1', 1),
  _SwitchListEntry('SW1METAL', 'SW2METAL', 1),
  _SwitchListEntry('SW1PIPE', 'SW2PIPE', 1),
  _SwitchListEntry('SW1SLAD', 'SW2SLAD', 1),
  _SwitchListEntry('SW1STARG', 'SW2STARG', 1),
  _SwitchListEntry('SW1STON1', 'SW2STON1', 1),
  _SwitchListEntry('SW1STON2', 'SW2STON2', 1),
  _SwitchListEntry('SW1STONE', 'SW2STONE', 1),
  _SwitchListEntry('SW1STRTN', 'SW2STRTN', 1),
  // Doom registered episodes 2&3 switches
  _SwitchListEntry('SW1BLUE', 'SW2BLUE', 2),
  _SwitchListEntry('SW1CMT', 'SW2CMT', 2),
  _SwitchListEntry('SW1GARG', 'SW2GARG', 2),
  _SwitchListEntry('SW1GSTON', 'SW2GSTON', 2),
  _SwitchListEntry('SW1HOT', 'SW2HOT', 2),
  _SwitchListEntry('SW1LION', 'SW2LION', 2),
  _SwitchListEntry('SW1SATYR', 'SW2SATYR', 2),
  _SwitchListEntry('SW1SKIN', 'SW2SKIN', 2),
  _SwitchListEntry('SW1VINE', 'SW2VINE', 2),
  _SwitchListEntry('SW1WOOD', 'SW2WOOD', 2),
  // Doom II switches
  _SwitchListEntry('SW1PANEL', 'SW2PANEL', 3),
  _SwitchListEntry('SW1ROCK', 'SW2ROCK', 3),
  _SwitchListEntry('SW1MET2', 'SW2MET2', 3),
  _SwitchListEntry('SW1WDMET', 'SW2WDMET', 3),
  _SwitchListEntry('SW1BRIK', 'SW2BRIK', 3),
  _SwitchListEntry('SW1MOD1', 'SW2MOD1', 3),
  _SwitchListEntry('SW1ZIM', 'SW2ZIM', 3),
  _SwitchListEntry('SW1STON6', 'SW2STON6', 3),
  _SwitchListEntry('SW1TEK', 'SW2TEK', 3),
  _SwitchListEntry('SW1MARB', 'SW2MARB', 3),
  _SwitchListEntry('SW1SKULL', 'SW2SKULL', 3),
];

/// MAXSWITCHES (p_spec.h).
const int kMaxSwitches = 50;

/// MAXBUTTONS (p_spec.h).
const int kMaxButtons = 16;

/// BUTTONTIME (p_spec.h).
const int kButtonTime = 35;

/// bwhere_e (p_spec.h): which texture slot a button swaps.
enum ButtonWhere { top, middle, bottom }

/// button_t (p_spec.h). A switch texture counting down to revert.
class Button {
  Line? line;
  ButtonWhere where = ButtonWhere.top;
  int bTexture = 0;
  int bTimer = 0;
  DegenMobj? soundOrg;
}

/// Owns the switch list + button timers (p_switch.c). One instance per level.
class SwitchManager {
  SwitchManager(this.textures, this.sound) {
    _initSwitchList();
  }

  final Textures textures;
  final SoundHook sound;

  /// switchlist[MAXSWITCHES*2] — texture numbers, paired off/on, -1 terminated.
  final List<int> switchList = List<int>.filled(kMaxSwitches * 2, 0);
  int numSwitches = 0;

  /// buttonlist[MAXBUTTONS].
  final List<Button> buttonList =
      List<Button>.generate(kMaxButtons, (_) => Button());

  // -----------------------------------------------------------------------
  // P_InitSwitchList. Shareware Doom1 -> episode rank 1 (gamemode shareware).
  // -----------------------------------------------------------------------
  void _initSwitchList() {
    // Shareware/registered/retail/commercial all map to a rank here; the
    // shareware IWAD only contains the rank-1 textures, but R_TextureNumForName
    // degrades missing names to 0, so building all <= rank-3 entries is safe
    // and matches commercial. We use rank 1 (shareware) to mirror gamemode.
    const int episode = 1;
    int slIndex = 0;
    for (int i = 0; i < _alphSwitchList.length; i++) {
      if (_alphSwitchList[i].episode <= episode) {
        // Only register pairs whose textures actually exist in this IWAD;
        // R_TextureNumForName would I_Error on a missing one in vanilla, but
        // the shareware IWAD contains every rank-1 texture, so checkTexture
        // returns a valid number for them. Skip a pair if either is absent so
        // we never map a switch onto the placeholder texture 0.
        final int n1 = textures.checkTextureNumForName(_alphSwitchList[i].name1);
        final int n2 = textures.checkTextureNumForName(_alphSwitchList[i].name2);
        if (n1 < 0 || n2 < 0) continue;
        switchList[slIndex++] = n1;
        switchList[slIndex++] = n2;
      }
    }
    numSwitches = slIndex ~/ 2;
    if (slIndex < switchList.length) switchList[slIndex] = -1;
  }

  // -----------------------------------------------------------------------
  // P_StartButton. Start a button counting down till it reverts.
  // -----------------------------------------------------------------------
  void startButton(Line line, ButtonWhere w, int texture, int time) {
    // See if button is already pressed.
    for (int i = 0; i < kMaxButtons; i++) {
      if (buttonList[i].bTimer != 0 && identical(buttonList[i].line, line)) {
        return;
      }
    }

    for (int i = 0; i < kMaxButtons; i++) {
      if (buttonList[i].bTimer == 0) {
        buttonList[i].line = line;
        buttonList[i].where = w;
        buttonList[i].bTexture = texture;
        buttonList[i].bTimer = time;
        buttonList[i].soundOrg = line.frontSector.soundOrg;
        return;
      }
    }

    throw StateError('P_StartButton: no button slots left!');
  }

  // -----------------------------------------------------------------------
  // P_ChangeSwitchTexture. Swap the switch texture; if [useAgain] it becomes a
  // button that reverts after BUTTONTIME. Plays the switch sound.
  // -----------------------------------------------------------------------
  void changeSwitchTexture(Line line, int useAgain) {
    if (useAgain == 0) {
      line.special = 0;
    }

    final Side side0 = line.frontSide; // sides[line->sidenum[0]]
    int texTop = side0.topTexture;
    int texMid = side0.midTexture;
    int texBot = side0.bottomTexture;

    int soundId = Sfx.swtchn;

    // EXIT SWITCH?
    if (line.special == 11) {
      soundId = Sfx.swtchx;
    }

    for (int i = 0; i < numSwitches * 2; i++) {
      if (switchList[i] == texTop) {
        sound.startSound(_buttonSoundOrigin(), soundId);
        side0.topTexture = switchList[i ^ 1];
        if (useAgain != 0) {
          startButton(line, ButtonWhere.top, switchList[i], kButtonTime);
        }
        return;
      } else {
        if (switchList[i] == texMid) {
          sound.startSound(_buttonSoundOrigin(), soundId);
          side0.midTexture = switchList[i ^ 1];
          if (useAgain != 0) {
            startButton(line, ButtonWhere.middle, switchList[i], kButtonTime);
          }
          return;
        } else {
          if (switchList[i] == texBot) {
            sound.startSound(_buttonSoundOrigin(), soundId);
            side0.bottomTexture = switchList[i ^ 1];
            if (useAgain != 0) {
              startButton(line, ButtonWhere.bottom, switchList[i], kButtonTime);
            }
            return;
          }
        }
      }
    }
  }

  /// Vanilla passes `buttonlist->soundorg` (buttonlist[0].soundorg) — by the
  /// time the texture swap happens this slot may be empty; the sound origin is
  /// only used as the audio position. Mirror vanilla: use buttonlist[0].
  Object? _buttonSoundOrigin() => buttonList[0].soundOrg;

  // -----------------------------------------------------------------------
  // Button countdown — the "DO BUTTONS" loop from P_UpdateSpecials
  // (p_spec.c). Run once per tic by the integration.
  // -----------------------------------------------------------------------
  void tickButtons() {
    for (int i = 0; i < kMaxButtons; i++) {
      if (buttonList[i].bTimer != 0) {
        buttonList[i].bTimer--;
        if (buttonList[i].bTimer == 0) {
          final Button b = buttonList[i];
          final Side side0 = b.line!.frontSide;
          switch (b.where) {
            case ButtonWhere.top:
              side0.topTexture = b.bTexture;
              break;
            case ButtonWhere.middle:
              side0.midTexture = b.bTexture;
              break;
            case ButtonWhere.bottom:
              side0.bottomTexture = b.bTexture;
              break;
          }
          sound.startSound(b.soundOrg, Sfx.swtchn);
          // memset(&buttonlist[i],0,...) — reset the slot.
          buttonList[i] = Button();
        }
      }
    }
  }
}
