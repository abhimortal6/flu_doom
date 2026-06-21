# Contributing to flu_doom

Thanks for your interest. flu_doom is a **pure-Dart (no FFI) port of vanilla
Doom** (Chocolate Doom + Nuked-OPL3) running as a Flutter app. A few
ground rules keep the port faithful.

## The one rule that matters: port faithfully, never paraphrase

Every engine module is ported **faithfully** from the C reference (Chocolate
Doom; Nuked-OPL3 for OPL), preserving the original logic and fixed-point math.
When adding or fixing engine code:

- **Do not paraphrase, restructure, or "clean up" the C.** Paraphrasing has
  repeatedly introduced subtle fixed-point bugs.
- Fixed-point math depends on **32-bit signed integer overflow** — preserve it
  exactly. Target Dart native (AOT) int semantics; the web target is out of scope.
- **Verify behavior in motion** (rotate, move, with sprites on screen), not from
  a single static frame.
- Name the C source you ported from in your PR description.

UI/Flutter glue (menus, touch controls, the present path, import flow) is normal
Dart and does not need to mirror any C file.

## Build, run, test

```sh
flutter pub get
flutter run -d macos --release     # primary dev/verify target
flutter test                       # render / play / state / sound suites
flutter analyze                    # lint (flutter_lints)
```

`flutter_soloud` needs CMake to build its native backend: `brew install cmake`.
On macOS `--release`, a relaunch can run a stale AOT snapshot; run
`flutter clean` first when a change must be visible.

flu_doom ships no game data — supply your own IWAD (see the README's
"Bring your own WAD" section). Do not commit `*.wad` files.

## Frozen interfaces

Cross-module interfaces are frozen in the `CONTRACTS_*.md` documents (see the
README's module map). Read the relevant contract before changing a boundary; if
a contract must change, update the contract document in the same PR.

## License

By contributing, you agree your contributions are licensed under the project's
**GPLv2** (see `LICENSE`).
