# Network Support Design

## Decision

`iwad_runtime` should not become a complete network Doom client. Its role is to expose enough deterministic runtime support for another project to build real multiplayer on top.

The outside project owns transport, rooms, discovery, relay, UI, matchmaking, NAT traversal, and product policy. This package owns only the Doom runtime hooks needed to drive a synchronized game from externally supplied player commands.

## Goals

- Allow a host/client project to run Doom in deterministic multiplayer lockstep.
- Keep transport out of this package so the same runtime can be used with UDP, WebSocket, relay, LAN discovery, or a custom backend.
- Expose compatibility checks that prevent obvious desyncs before launch.
- Provide state and error reporting for waiting, connected, disconnected, and desynchronized sessions.
- Preserve the current single-player API and behavior.

## Non-Goals

- No built-in lobby, server browser, matchmaking, accounts, chat, or NAT traversal.
- No bundled online service.
- No remote-play/video-streaming mode.
- No promise that every platform gets multiplayer in the first slice.

## Recommended First Slice

Start with native-only two-player lockstep support. Web support can come later through the same Dart-facing API once the synchronization boundary is proven.

The first external transport target should be simple LAN or local-process integration, not internet matchmaking. The useful milestone is proving that two runtimes can start the same IWAD/map and advance without desync when fed the same ordered tic command sets.

## Runtime Boundary

The package should expose a multiplayer session facade with these responsibilities:

- initialize a net-capable game with agreed settings;
- build the local player's `ticcmd_t` for a tick without immediately advancing the world alone;
- accept remote `ticcmd_t` values for the same tick;
- advance the game only when a complete command set is available;
- expose basic session state and deterministic checksums or sync diagnostics.

The package should not open sockets or make network policy decisions.

## Compatibility Inputs

Before starting a multiplayer run, the caller should be able to compare:

- IWAD checksum;
- game version and mission/mode;
- episode, map, skill, deathmatch/co-op flags;
- player count and local player index;
- optional feature flags such as monsters, fast monsters, respawn, and tic duplication.

## Likely Native Work

The current source already includes parts of the Doom networking loop, but the build does not enable `FEATURE_MULTIPLAYER`, and the vendored network implementation files are not all present. The safer implementation path is to add a controlled external-tic mode rather than simply turning on the original network stack.

Native hooks should be small and explicit:

- start with multiplayer settings;
- export local tic command bytes;
- import complete per-tic command sets;
- run exactly one synchronized tic or report that it is blocked;
- expose a lightweight sync checksum for tests and diagnostics.

## Testing Strategy

Tests should focus on determinism before real networking:

- single runtime still behaves as before;
- two runtimes started from the same settings produce matching sync checksums over many ticks;
- differing IWAD/settings are rejected before launch;
- missing remote commands block advancement instead of drifting;
- disconnect and shutdown leave the runtime reusable or clearly terminated.

## Open Questions

- Which external project will own the first transport integration?
- Should the first multiplayer mode be co-op, deathmatch, or both with one shared settings object?
- Do we need web support in the first implementation wave, or is native proof enough?
