# iwad_runtime

`iwad_runtime` embeds an IWAD-compatible runtime in Flutter apps.

The package does not bundle proprietary game data and does not bundle a default
IWAD. The application must explicitly provide an IWAD path or bytes:

```dart
final controller = IwadController();
await controller.start('/path/to/legally-obtained-iwad.wad');

IwadView(controller: controller);
```

For platforms where a file path is inconvenient, pass bytes:

```dart
final controller = IwadController();
await controller.startBytes(iwadBytes, fileName: 'game.wad');
```

## Screen Helper

`IwadScreen` can start from explicit data:

```dart
IwadScreen(iwadPath: '/path/to/legally-obtained-iwad.wad');
```

or:

```dart
IwadScreen(iwadBytes: iwadBytes, iwadFileName: 'game.wad');
```

If no IWAD is provided and the controller was not already started, `IwadScreen`
shows an error instead of silently loading bundled data.

## Status

- Android, iOS, Linux, macOS, Windows: native backend through `dart:ffi`.
- Web: WASM backend through the package asset loader.
- Runtime data: app-supplied IWAD path/bytes only.
- Apps should test compatibility with the IWAD data they supply.
- Audio: sound effects and OPL music are enabled through miniaudio.

## Multiplayer Support Boundary

`iwad_runtime` does not provide a network client, lobby, matchmaking, room UI,
server browser, NAT traversal, or relay service. Multiplayer support is exposed
as deterministic runtime hooks for another project to drive.

The native backend can expose tic command serialization, synchronized tick
advancement, and sync diagnostics. External applications are responsible for
transporting commands between peers and for validating IWAD/settings
compatibility before launch.

## Legal Notes

The package source and vendored engine code are GPL-2.0-or-later.
miniaudio is used under its public-domain option.

No proprietary game data is bundled, downloaded, or implied by this package.

See `THIRD_PARTY_GPL_ENGINE_LICENSE` and `THIRD_PARTY_MINIAUDIO_NOTICE`.
