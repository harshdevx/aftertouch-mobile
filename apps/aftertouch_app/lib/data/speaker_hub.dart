import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:soundtouch_client/soundtouch_client.dart';

import 'soundtouch_providers.dart';

enum LiveConnection {
  /// First connect in progress, no data yet.
  connecting,

  /// `gabbo` WebSocket is up — state is push-driven, no polling.
  live,

  /// Socket down; falling back to HTTP polling.
  polling,

  /// Can't reach the speaker at all.
  offline,
}

/// A single source of truth for one speaker's live state. Backed by the
/// `gabbo` WebSocket when it's up, HTTP polling when it isn't, and it
/// re-snapshots on every (re)connect so nothing is missed while offline.
///
/// The `rev*` counters bump when the speaker reports that a list changed;
/// screens `ref.listen` them to refresh without polling those lists.
class SpeakerSnapshot {
  const SpeakerSnapshot({
    this.info,
    this.nowPlaying,
    this.volume,
    this.connection = LiveConnection.connecting,
    this.revPresets = 0,
    this.revSources = 0,
    this.revRecents = 0,
    this.revZone = 0,
  });

  final DeviceInfo? info;
  final NowPlaying? nowPlaying;
  final Volume? volume;
  final LiveConnection connection;
  final int revPresets;
  final int revSources;
  final int revRecents;
  final int revZone;

  bool get reachable => connection != LiveConnection.offline;
  bool get isLive => connection == LiveConnection.live;

  SpeakerSnapshot copyWith({
    DeviceInfo? info,
    NowPlaying? nowPlaying,
    Volume? volume,
    LiveConnection? connection,
    int? revPresets,
    int? revSources,
    int? revRecents,
    int? revZone,
  }) =>
      SpeakerSnapshot(
        info: info ?? this.info,
        nowPlaying: nowPlaying ?? this.nowPlaying,
        volume: volume ?? this.volume,
        connection: connection ?? this.connection,
        revPresets: revPresets ?? this.revPresets,
        revSources: revSources ?? this.revSources,
        revRecents: revRecents ?? this.revRecents,
        revZone: revZone ?? this.revZone,
      );
}

final speakerHubProvider = NotifierProvider.family<SpeakerHub, SpeakerSnapshot,
    String>(SpeakerHub.new);

class SpeakerHub extends FamilyNotifier<SpeakerSnapshot, String>
    with WidgetsBindingObserver {
  Timer? _poll;
  Timer? _volDebounce;
  StreamSubscription<SoundTouchEvent>? _evSub;
  StreamSubscription<GabboConnectionState>? _connSub;
  bool _disposed = false;

  SoundTouchClient get _client => ref.read(soundTouchClientProvider(arg));

  @override
  SpeakerSnapshot build(String arg) {
    _disposed = false;
    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() {
      _disposed = true;
      WidgetsBinding.instance.removeObserver(this);
      _poll?.cancel();
      _volDebounce?.cancel();
      _evSub?.cancel();
      _connSub?.cancel();
    });

    _evSub = _client.events.listen(_onEvent);
    _connSub = _client.eventConnectionState.listen(_onConnection);
    Future.microtask(() => _snapshot());
    _startPolling(); // until the socket proves itself

    return const SpeakerSnapshot();
  }

  // --- socket lifecycle ---------------------------------------------------

  void _onConnection(GabboConnectionState s) {
    if (_disposed) return;
    switch (s) {
      case GabboConnectionState.connected:
        _stopPolling();
        state = state.copyWith(connection: LiveConnection.live);
        unawaited(_snapshot()); // catch up on anything missed
      case GabboConnectionState.connecting:
        break; // keep doing whatever we were doing
      case GabboConnectionState.disconnected:
      case GabboConnectionState.idle:
        if (state.connection == LiveConnection.live) {
          state = state.copyWith(connection: LiveConnection.polling);
        }
        _startPolling();
    }
  }

  void _onEvent(SoundTouchEvent e) {
    if (_disposed) return;
    switch (e) {
      case NowPlayingEvent(nowPlaying: final np?):
        state = state.copyWith(nowPlaying: np);
      case NowPlayingEvent():
        unawaited(_fetchNowPlaying());
      case NowSelectionChangedEvent():
        unawaited(_fetchNowPlaying());
      case VolumeEvent(volume: final v?):
        state = state.copyWith(volume: v);
      case VolumeEvent():
        unawaited(_fetchVolume());
      case PresetsChangedEvent():
        state = state.copyWith(revPresets: state.revPresets + 1);
      case SourcesChangedEvent():
        state = state.copyWith(revSources: state.revSources + 1);
      case RecentsChangedEvent():
        state = state.copyWith(revRecents: state.revRecents + 1);
      case ZoneChangedEvent():
        state = state.copyWith(revZone: state.revZone + 1);
      case ConnectionStateEvent():
      case HandshakeEvent():
      case InfoChangedEvent():
      case UnknownEvent():
        break;
    }
  }

  // --- polling fallback --------------------------------------------------

  void _startPolling() {
    _poll ??= Timer.periodic(
      const Duration(milliseconds: 1500),
      (_) => _snapshot(),
    );
  }

  void _stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  Future<void> _snapshot() async {
    if (_disposed) return;
    try {
      final np = await _client.getNowPlaying();
      if (_disposed) return;
      Volume? vol;
      try {
        vol = await _client.getVolume();
      } on SoundTouchException {
        vol = state.volume;
      }
      var info = state.info;
      if (info == null) {
        try {
          info = await _client.getInfo();
        } on SoundTouchException {
          info = null;
        }
      }
      if (_disposed) return;
      state = state.copyWith(
        nowPlaying: np,
        volume: vol,
        info: info,
        connection: state.connection == LiveConnection.live
            ? LiveConnection.live
            : LiveConnection.polling,
      );
    } on SoundTouchException {
      if (!_disposed) {
        state = state.copyWith(connection: LiveConnection.offline);
      }
    }
  }

  Future<void> _fetchNowPlaying() async {
    try {
      final np = await _client.getNowPlaying();
      if (!_disposed) state = state.copyWith(nowPlaying: np);
    } on SoundTouchException {
      /* next tick */
    }
  }

  Future<void> _fetchVolume() async {
    try {
      final v = await _client.getVolume();
      if (!_disposed) state = state.copyWith(volume: v);
    } on SoundTouchException {
      /* next tick */
    }
  }

  /// Pull a fresh snapshot shortly after an action (covers the gap before an
  /// event arrives, and everything when polling).
  Future<void> refreshSoon() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await _snapshot();
  }

  /// Optimistic volume — moves the slider now, writes (debounced) after.
  void setVolumeOptimistic(int level) {
    final v = state.volume;
    state = state.copyWith(
      volume: Volume(
        deviceId: v?.deviceId ?? '',
        target: level,
        actual: level,
        muted: v?.muted ?? false,
      ),
    );
    _volDebounce?.cancel();
    _volDebounce = Timer(const Duration(milliseconds: 120), () async {
      try {
        await _client.setVolume(level);
      } on SoundTouchException {
        await _fetchVolume();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_disposed) {
      unawaited(_snapshot());
    }
  }
}
