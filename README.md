# AfterTouch (mobile)

A monochrome Flutter app for controlling **Bose SoundTouch** speakers over your
local network. It talks directly to the speakers on the LAN — playback, volume,
tone, presets, sources, recents, and DLNA library browsing all work without any
Bose cloud service.

> **Not affiliated with Bose.** "SoundTouch" and "Bose" are trademarks of Bose
> Corporation. This is an independent, community project. The name "SoundTouch"
> appears here only to describe the hardware and local protocol the app speaks
> to.

## Features

- **Discovery** — finds speakers on the LAN via mDNS / DNS-SD, with an
  "Add by IP" fallback. Duplicate hits for one speaker (a `.local` name and a
  numeric IP) are merged into a single row; swipe a row away to remove it, with
  one-tap undo. Known speakers are remembered between launches.
- **Now Playing** — artwork (rendered greyscale), track metadata, scrubber,
  transport controls, shuffle / repeat, docked volume and mute. Live updates
  over the speaker's WebSocket event stream, with HTTP polling as a fallback.
- **Sound / EQ** — probes each speaker and shows only the controls it actually
  supports: volume, bass, treble, balance. Writes are optimistic and debounced.
- **Presets** — 2×3 grid; tap to recall, long-press to replace with what's
  playing or to clear a slot.
- **Recents** — replay anything from the speaker's recently-played list.
- **Sources** — switch between Bluetooth, AUX, and any streaming sources the
  speaker exposes, with availability reasons surfaced inline.
- **Library / DLNA** — browse UPnP/DLNA media servers visible to the speaker,
  add or remove servers, walk folders, and play tracks. Runs entirely
  speaker-to-server; no companion service required.
- **Radio catalog** *(optional)* — when an [AfterTouch](#upstream-project)
  service URL is configured in Settings, browse and search TuneIn and
  RadioBrowser through it and play results to a speaker, including "save as
  preset".
- **Monochrome UI** — an achromatic greyscale interface throughout; hierarchy
  and state come from weight, contrast, inversion, and motion rather than hue.
  System / Light / Dark themes.

## Project layout

A Dart [pub workspace](https://dart.dev/tools/pub/workspaces) (no melos):

```
aftertouch-mobile/
  pubspec.yaml                  workspace root
  packages/
    soundtouch_client/          pure-Dart client for the SoundTouch local API
  apps/
    aftertouch_app/             the Flutter app
```

### `packages/soundtouch_client`

A pure-Dart (no Flutter) client for the SoundTouch local Web API:

- HTTP control on `:8090` (XML on the wire)
- real-time events over the WebSocket "gabbo" channel on `:8080`
- UPnP / AVTransport on `:8091`
- mDNS device discovery

It has its own unit tests and two runnable examples:

```bash
# List SoundTouch speakers on the current network
dart run packages/soundtouch_client/example/discover.dart          # one pass
dart run packages/soundtouch_client/example/discover.dart --watch  # until Ctrl-C

# Dump a speaker's DLNA/library responses for troubleshooting
dart run packages/soundtouch_client/example/library_probe.dart <speaker-ip>
```

## Requirements

- Flutter (stable), Dart SDK ≥ 3.12
- A device or simulator on the **same LAN/VLAN** as the speakers. Multicast must
  be allowed between the two — AP isolation, guest networks, and some mesh
  setups block mDNS; use "Add by IP" there.

## Getting started

```bash
cd aftertouch-mobile
flutter pub get                       # resolves the whole workspace

dart analyze                          # lint the workspace
dart test  -C packages/soundtouch_client
flutter test apps/aftertouch_app

cd apps/aftertouch_app
flutter run -d <device>
```

### Platform notes

- **Android** — needs `INTERNET`, `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`,
  and `CHANGE_WIFI_MULTICAST_STATE` (all install-time, already in the manifest).
  No runtime location permission is required for discovery. Cleartext HTTP to
  the LAN is allowed via a network-security config.
- **iOS** — Info.plist declares Local Network usage, the Bonjour service types,
  and local-networking ATS. iOS shows a one-time "allow local network access"
  prompt on first discovery.

## Upstream project

The protocol knowledge and the shape of `packages/soundtouch_client` come from
the **Bose SoundTouch Toolkit** by **Tobias Gesellchen** — a Go library and set
of tools that keep SoundTouch speakers usable after the Bose cloud shutdown:

- Repository: <https://github.com/gesellix/bose-soundtouch>
- Docs: <https://gesellix.github.io/Bose-SoundTouch/>
- License: MIT — Copyright (c) 2026 Tobias Gesellchen

`packages/soundtouch_client` is an independent Dart re-implementation of that
project's `pkg/client` (HTTP + WebSocket + discovery). Endpoint behaviour,
the "gabbo" event channel, the discovery approach, and the DLNA/`STORED_MUSIC`
flow were all learned from that codebase and its documentation.

That project also runs a local cloud-replacement service called **AfterTouch**.
This app is named to pair with it: the optional radio catalog talks to a running
AfterTouch instance, and everything else works speaker-direct without one.

The Go project in turn credits earlier reverse-engineering work that this app
also stands on — notably
[SoundCork](https://github.com/deborahgu/soundcork) (Deborah Kaplan et al.) and
[SoundTouch Plus](https://github.com/thlucas1/homeassistantcomponent_soundtouchplus)
(Todd Lucas), whose notes document much of the undocumented SoundTouch API.

## License

Provided as-is, for interoperability with hardware you own. See the upstream
project for the MIT-licensed Go implementation this client is derived from; if
you redistribute `soundtouch_client`, carry that attribution with it.

## Notes

I have used claude code to create requirements and develop the app.
