import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:soundtouch_client/soundtouch_client.dart';

import '../../data/soundtouch_providers.dart';
import '../../data/speaker_hub.dart';

class SourceRow {
  const SourceRow({
    required this.item,
    required this.available,
    required this.active,
    this.reason,
  });

  final SourceItem item;
  final bool available;
  final bool active;
  final String? reason;
}

class SourcesState {
  const SourcesState({
    this.loading = true,
    this.unreachable = false,
    this.rows = const [],
  });

  final bool loading;
  final bool unreachable;
  final List<SourceRow> rows;

  SourcesState copyWith({
    bool? loading,
    bool? unreachable,
    List<SourceRow>? rows,
  }) =>
      SourcesState(
        loading: loading ?? this.loading,
        unreachable: unreachable ?? this.unreachable,
        rows: rows ?? this.rows,
      );
}

final sourcesControllerProvider = NotifierProvider.family<SourcesController,
    SourcesState, String>(SourcesController.new);

/// A handful of sources are worth pinning to the top.
const _pinned = {'BLUETOOTH', 'AUX', 'AUX_INPUT'};

/// Hidden from the picker — internal / not user-selectable as a whole source.
const _hidden = {'INVALID_SOURCE', 'NOTIFICATION', 'ALEXA', 'UPDATE', 'STANDBY'};

class SourcesController extends FamilyNotifier<SourcesState, String> {
  bool _disposed = false;
  SoundTouchClient get _client => ref.read(soundTouchClientProvider(arg));

  @override
  SourcesState build(String arg) {
    _disposed = false;
    ref.onDispose(() => _disposed = true);

    // Re-fetch when the speaker says its source list or selection changed.
    ref.listen(
      speakerHubProvider(arg).select((s) => (s.revSources, s.nowPlaying)),
      (_, _) => refresh(),
    );

    Future.microtask(refresh);
    return const SourcesState();
  }

  Future<void> refresh() async {
    try {
      final sources = await _client.getSources();
      ServiceAvailability? avail;
      try {
        avail = await _client.getServiceAvailability();
      } on SoundTouchException {
        avail = null;
      }
      final np = ref.read(speakerHubProvider(arg)).nowPlaying;
      if (_disposed) return;

      final rows = <SourceRow>[
        for (final s in sources)
          if (!_hidden.contains(s.source.toUpperCase()))
            SourceRow(
              item: s,
              available: s.isReady && (avail?.isAvailable(s.source) ?? true),
              active: _isActive(s, np),
              reason: avail?.reasonFor(s.source),
            ),
      ]..sort(_ordering);

      state = state.copyWith(loading: false, unreachable: false, rows: rows);
    } on SoundTouchException {
      if (!_disposed) {
        state = state.copyWith(loading: false, unreachable: true);
      }
    }
  }

  bool _isActive(SourceItem s, NowPlaying? np) {
    if (np == null) return false;
    if (np.source.toUpperCase() != s.source.toUpperCase()) return false;
    final a = (np.sourceAccount ?? '').trim();
    final b = (s.sourceAccount ?? '').trim();
    return a.isEmpty || b.isEmpty || a == b;
  }

  int _ordering(SourceRow a, SourceRow b) {
    int rank(SourceRow r) => _pinned.contains(r.item.source.toUpperCase())
        ? 0
        : (r.available ? 1 : 2);
    final byRank = rank(a).compareTo(rank(b));
    if (byRank != 0) return byRank;
    return a.item.displayName
        .toLowerCase()
        .compareTo(b.item.displayName.toLowerCase());
  }

  Future<String?> select(SourceItem item) async {
    try {
      await _client.selectSourceItem(item);
      await ref.read(speakerHubProvider(arg).notifier).refreshSoon();
      await refresh();
      return null;
    } on SoundTouchApiError catch (e) {
      return 'This speaker refused that source (${e.name}).';
    } on SoundTouchException {
      return "Couldn't switch source. Try again.";
    }
  }
}
