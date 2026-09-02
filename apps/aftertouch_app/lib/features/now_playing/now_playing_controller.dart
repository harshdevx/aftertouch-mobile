import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:soundtouch_client/soundtouch_client.dart';

import '../../data/soundtouch_providers.dart';
import '../../data/speaker_hub.dart';

class NowPlayingState {
  const NowPlayingState({
    this.info,
    this.nowPlaying,
    this.volume,
    this.connection = LiveConnection.connecting,
  });

  final DeviceInfo? info;
  final NowPlaying? nowPlaying;
  final Volume? volume;
  final LiveConnection connection;

  bool get loading =>
      nowPlaying == null && connection == LiveConnection.connecting;
  bool get unreachable =>
      nowPlaying == null && connection == LiveConnection.offline;
  bool get isLive => connection == LiveConnection.live;

  PlayStatus get playStatus => nowPlaying?.playStatus ?? PlayStatus.unknown;
  bool get isPlaying => playStatus.isPlaying;
  bool get isStandby => nowPlaying?.isStandby ?? false;
}

final nowPlayingControllerProvider = NotifierProvider.family<
    NowPlayingController, NowPlayingState, String>(NowPlayingController.new);

/// Thin action layer over [SpeakerHub]. The hub owns the live state
/// (`gabbo` WebSocket, with HTTP polling as fallback); this issues commands
/// and nudges a refresh so the UI catches up before the event arrives.
///
/// It mirrors the hub via [ref.listen] rather than [ref.watch]: watching would
/// mark this notifier "outdated" on every hub tick, and a slider drag landing
/// in that window would call `ref` on an outdated element and assert.
class NowPlayingController extends FamilyNotifier<NowPlayingState, String> {
  late SoundTouchClient _client;
  late SpeakerHub _hub;

  @override
  NowPlayingState build(String arg) {
    _client = ref.read(soundTouchClientProvider(arg));
    _hub = ref.read(speakerHubProvider(arg).notifier);

    ref.listen<SpeakerSnapshot>(
      speakerHubProvider(arg),
      (_, snap) => state = _fromSnapshot(snap),
    );

    return _fromSnapshot(ref.read(speakerHubProvider(arg)));
  }

  NowPlayingState _fromSnapshot(SpeakerSnapshot s) => NowPlayingState(
        info: s.info,
        nowPlaying: s.nowPlaying,
        volume: s.volume,
        connection: s.connection,
      );

  Future<void> _do(Future<void> Function() action) async {
    try {
      await action();
    } on SoundTouchException {
      // Surfaced by the next snapshot; a transient failure is not fatal.
    }
    await _hub.refreshSoon();
  }

  Future<void> playPause() => _do(() => _client.playPause(state.playStatus));
  Future<void> next() => _do(_client.nextTrack);
  Future<void> previous() => _do(_client.previousTrack);
  Future<void> power() => _do(_client.power);
  Future<void> toggleMute() => _do(() => _client.sendKey(RemoteKey.mute));

  Future<void> toggleShuffle() {
    final on = state.nowPlaying?.shuffle == ShuffleMode.on;
    return _do(() =>
        _client.sendKey(on ? RemoteKey.shuffleOff : RemoteKey.shuffleOn));
  }

  Future<void> cycleRepeat() {
    final key = switch (state.nowPlaying?.repeat) {
      RepeatSetting.off => RemoteKey.repeatAll,
      RepeatSetting.all => RemoteKey.repeatOne,
      _ => RemoteKey.repeatOff,
    };
    return _do(() => _client.sendKey(key));
  }

  void setVolume(int level) => _hub.setVolumeOptimistic(level);
}
