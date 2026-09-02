import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:soundtouch_client/soundtouch_client.dart';

import '../../data/soundtouch_providers.dart';
import '../../data/speaker_hub.dart';

class PresetsState {
  const PresetsState({
    this.loading = true,
    this.unreachable = false,
    this.bySlot = const {},
    this.nowPlaying,
  });

  final bool loading;
  final bool unreachable;

  /// slot (1..6) -> preset, sparse.
  final Map<int, Preset> bySlot;
  final NowPlaying? nowPlaying;

  bool get canStoreCurrent =>
      nowPlaying?.contentItem?.isPresetable ?? false;

  /// Slot whose content matches what's playing now, if any.
  int? get activeSlot {
    final loc = nowPlaying?.contentItem?.location;
    if (loc == null) return null;
    for (final e in bySlot.entries) {
      if (e.value.contentItem.location == loc) return e.key;
    }
    return null;
  }

  PresetsState copyWith({
    bool? loading,
    bool? unreachable,
    Map<int, Preset>? bySlot,
    NowPlaying? nowPlaying,
  }) =>
      PresetsState(
        loading: loading ?? this.loading,
        unreachable: unreachable ?? this.unreachable,
        bySlot: bySlot ?? this.bySlot,
        nowPlaying: nowPlaying ?? this.nowPlaying,
      );
}

final presetsControllerProvider = NotifierProvider.family<PresetsController,
    PresetsState, String>(PresetsController.new);

class PresetsController extends FamilyNotifier<PresetsState, String> {
  bool _disposed = false;
  SoundTouchClient get _client => ref.read(soundTouchClientProvider(arg));

  @override
  PresetsState build(String arg) {
    _disposed = false;
    ref.onDispose(() => _disposed = true);

    // Refresh when the speaker reports a preset change or the selection moves
    // (so the "playing now" slot marker stays right).
    ref.listen(
      speakerHubProvider(arg).select((s) => (s.revPresets, s.nowPlaying)),
      (_, _) => refresh(),
    );

    Future.microtask(refresh);
    return const PresetsState();
  }

  Future<void> refresh() async {
    try {
      final presets = await _client.getPresets();
      NowPlaying? np;
      try {
        np = await _client.getNowPlaying();
      } on SoundTouchException {
        np = null;
      }
      if (_disposed) return;
      state = state.copyWith(
        loading: false,
        unreachable: false,
        bySlot: {for (final p in presets) p.id: p},
        nowPlaying: np,
      );
    } on SoundTouchException {
      if (_disposed) return;
      state = state.copyWith(loading: false, unreachable: true);
    }
  }

  Future<void> recall(int slot) async {
    try {
      await _client.selectPreset(slot);
    } on SoundTouchException {
      // no-op; a failed recall is visible by the state not changing
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await refresh();
  }

  /// Returns `null` on success, or a short user-facing reason on failure.
  ///
  /// `/storePreset` is undocumented but works on real ST10/20/300 hardware.
  /// The common real failure is a cloud source (e.g. Spotify) whose account
  /// isn't primed — the speaker answers with an error rather than "unsupported".
  Future<String?> storeCurrent(int slot) async {
    try {
      await _client.storeCurrentAsPreset(slot);
      await refresh();
      return null;
    } on SoundTouchArgumentError {
      return "What's playing now can't be saved as a preset.";
    } on SoundTouchApiError catch (e) {
      return 'Speaker rejected the save (${e.name}). Streaming sources may '
          'need AfterTouch; radio and library presets save directly.';
    } on SoundTouchException {
      return "Couldn't save the preset. Try again.";
    }
  }

  Future<String?> remove(int slot) async {
    try {
      await _client.removePreset(slot);
      await refresh();
      return null;
    } on SoundTouchApiError catch (e) {
      return 'Speaker rejected the change (${e.name}).';
    } on SoundTouchException {
      return "Couldn't remove the preset. Try again.";
    }
  }
}
