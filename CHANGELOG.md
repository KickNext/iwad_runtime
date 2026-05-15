## 0.1.2

* Fixed native runtime shutdown so a quit or dispose fully clears process-wide
  Doom state before the next start.
* Reset mutable startup, menu, sound, WAD, and zone state across repeated
  native sessions.

## 0.1.1

* Improved pub.dev metadata, license detection, and public API documentation.
* Moved release and publishing instructions into `AGENTS.md`.

## 0.1.0

* Initial IWAD-compatible Flutter package.
* Added FFI backend for Android, Linux, and Windows.
* Added bundled WASM backend for Flutter web.
* Added `IwadController`, `IwadView`, desktop mouse capture, mobile touch controls, example app, and smoke tooling.
