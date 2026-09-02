import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:soundtouch_client/soundtouch_client.dart';

import '../../data/soundtouch_providers.dart';

class EqState {
  const EqState({
    this.loading = true,
    this.unreachable = false,
    this.volume,
    this.bass,
    this.bassCaps,
    this.tone,
    this.balance,
  });

  final bool loading;
  final bool unreachable;

  final Volume? volume;
  final Bass? bass; // classic /bass
  final BassCapabilities? bassCaps;
  final ToneControls? tone; // newer /audioproducttonecontrols
  final Balance? balance;

  /// Whether the newer tone endpoint is what drives bass/treble.
  bool get useTone => tone != null;
  bool get hasClassicBass =>
      tone == null && bass != null && (bassCaps?.available ?? true);
  bool get hasTreble => tone != null;
  bool get hasBalance => balance != null;

  bool get isEmpty =>
      volume == null && bass == null && tone == null && balance == null;

  EqState copyWith({
    bool? loading,
    bool? unreachable,
    Volume? volume,
    Bass? bass,
    BassCapabilities? bassCaps,
    ToneControls? tone,
    Balance? balance,
  }) =>
      EqState(
        loading: loading ?? this.loading,
        unreachable: unreachable ?? this.unreachable,
        volume: volume ?? this.volume,
        bass: bass ?? this.bass,
        bassCaps: bassCaps ?? this.bassCaps,
        tone: tone ?? this.tone,
        balance: balance ?? this.balance,
      );
}

final eqControllerProvider =
    NotifierProvider.family<EqController, EqState, String>(EqController.new);

/// Loads only the audio controls the speaker actually answers — models vary
/// widely, so we probe every endpoint and render what succeeds (UX spec §9.4).
class EqController extends FamilyNotifier<EqState, String> {
  bool _disposed = false;

  SoundTouchClient get _client => ref.read(soundTouchClientProvider(arg));

  @override
  EqState build(String arg) {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    Future.microtask(_probe);
    return const EqState();
  }

  Future<void> _probe() async {
    final results = await Future.wait<Object?>([
      _try(_client.getVolume),
      _try(_client.getToneControls),
      _try(_client.getBassCapabilities),
      _try(_client.getBass),
      _try(_client.getBalance),
    ]);
    if (_disposed) return;

    final volume = results[0] as Volume?;
    final tone = results[1] as ToneControls?;
    final bassCaps = results[2] as BassCapabilities?;
    final bass = results[3] as Bass?;
    final balance = results[4] as Balance?;

    state = EqState(
      loading: false,
      unreachable: volume == null &&
          tone == null &&
          bass == null &&
          balance == null,
      volume: volume,
      tone: tone,
      bassCaps: bassCaps,
      bass: bass,
      balance: balance,
    );
  }

  Future<T?> _try<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on SoundTouchException {
      return null;
    }
  }

  // --- setters (optimistic + debounced) ------------------------------------

  final _debouncers = <String, Timer>{};

  void _debounce(String key, Future<void> Function() write) {
    _debouncers[key]?.cancel();
    _debouncers[key] = Timer(const Duration(milliseconds: 140), () async {
      try {
        await write();
      } on SoundTouchException {
        await _probe(); // reconcile
      }
    });
  }

  void setVolume(int level) {
    final v = state.volume;
    if (v != null) {
      state = state.copyWith(
        volume: Volume(
            deviceId: v.deviceId,
            target: level,
            actual: level,
            muted: v.muted),
      );
    }
    _debounce('volume', () => _client.setVolume(level));
  }

  void setBass(int level) {
    if (state.useTone) {
      final t = state.tone!;
      state = state.copyWith(
        tone: ToneControls(
          bass: ToneBand(
              value: level, min: t.bass.min, max: t.bass.max, step: t.bass.step),
          treble: t.treble,
        ),
      );
      _debounce('bass', () => _client.setToneControls(bass: level));
    } else {
      final b = state.bass;
      if (b != null) {
        state = state.copyWith(
            bass: Bass(deviceId: b.deviceId, target: level, actual: level));
      }
      _debounce('bass', () => _client.setBass(level));
    }
  }

  void setTreble(int level) {
    final t = state.tone;
    if (t == null) return;
    state = state.copyWith(
      tone: ToneControls(
        bass: t.bass,
        treble: ToneBand(
            value: level,
            min: t.treble.min,
            max: t.treble.max,
            step: t.treble.step),
      ),
    );
    _debounce('treble', () => _client.setToneControls(treble: level));
  }

  void setBalance(int level) {
    final b = state.balance;
    if (b != null) {
      state = state.copyWith(
        balance: Balance(
            deviceId: b.deviceId,
            target: level,
            actual: level,
            min: b.min,
            max: b.max),
      );
    }
    _debounce('balance', () => _client.setBalance(level));
  }
}
