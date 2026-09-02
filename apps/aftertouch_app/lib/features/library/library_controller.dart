import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:soundtouch_client/soundtouch_client.dart';

import '../../data/soundtouch_providers.dart';
import '../../data/speaker_hub.dart';

class RegisteredServer {
  const RegisteredServer({
    required this.account,
    required this.name,
    required this.ready,
  });
  final String account;
  final String name;
  final bool ready;
}

class Crumb {
  const Crumb(this.name, this.container);
  final String name;

  /// `null` for the server root.
  final ContentItem? container;
}

class LibraryState {
  const LibraryState({
    this.loading = true,
    this.unreachable = false,
    this.registered = const [],
    this.discovered = const [],
    this.busy = false,
    this.rawSources,
    this.rawMediaServers,
    this.browseAccount,
    this.crumbs = const [],
    this.entries = const [],
    this.browseLoading = false,
    this.browseError,
    this.browseRaw,
    this.browseRequest,
  });

  final bool loading;
  final bool unreachable;

  /// STORED_MUSIC sources already on the speaker.
  final List<RegisteredServer> registered;

  /// DLNA servers the speaker can see that aren't registered yet.
  final List<MediaServer> discovered;

  final bool busy;

  /// Raw `/sources` + `/listMediaServers` XML (diagnostics for the server list).
  final String? rawSources;
  final String? rawMediaServers;

  // browse sub-state
  final String? browseAccount;
  final List<Crumb> crumbs;
  final List<NavigateItem> entries;
  final bool browseLoading;
  final String? browseError;

  /// Raw XML the speaker returned for the last browse (diagnostics).
  final String? browseRaw;

  /// Exact request body sent for the last browse (diagnostics).
  final String? browseRequest;

  bool get browsing => browseAccount != null;

  LibraryState copyWith({
    bool? loading,
    bool? unreachable,
    List<RegisteredServer>? registered,
    List<MediaServer>? discovered,
    bool? busy,
    Object? rawSources = _keep,
    Object? rawMediaServers = _keep,
    Object? browseAccount = _keep,
    List<Crumb>? crumbs,
    List<NavigateItem>? entries,
    bool? browseLoading,
    Object? browseError = _keep,
    Object? browseRaw = _keep,
    Object? browseRequest = _keep,
  }) =>
      LibraryState(
        loading: loading ?? this.loading,
        unreachable: unreachable ?? this.unreachable,
        registered: registered ?? this.registered,
        discovered: discovered ?? this.discovered,
        busy: busy ?? this.busy,
        rawSources:
            rawSources == _keep ? this.rawSources : rawSources as String?,
        rawMediaServers: rawMediaServers == _keep
            ? this.rawMediaServers
            : rawMediaServers as String?,
        browseAccount: browseAccount == _keep
            ? this.browseAccount
            : browseAccount as String?,
        crumbs: crumbs ?? this.crumbs,
        entries: entries ?? this.entries,
        browseLoading: browseLoading ?? this.browseLoading,
        browseError:
            browseError == _keep ? this.browseError : browseError as String?,
        browseRaw: browseRaw == _keep ? this.browseRaw : browseRaw as String?,
        browseRequest: browseRequest == _keep
            ? this.browseRequest
            : browseRequest as String?,
      );

  static const _keep = Object();
}

final libraryControllerProvider = NotifierProvider.family<LibraryController,
    LibraryState, String>(LibraryController.new);

class LibraryController extends FamilyNotifier<LibraryState, String> {
  bool _disposed = false;
  SoundTouchClient get _client => ref.read(soundTouchClientProvider(arg));

  @override
  LibraryState build(String arg) {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    ref.listen(
      speakerHubProvider(arg).select((s) => s.revSources),
      (_, _) => refresh(),
    );
    Future.microtask(refresh);
    return const LibraryState();
  }

  /// A `/sources` row counts as a music-library server when its source name
  /// mentions stored music / UPnP / DLNA (firmware varies: `STORED_MUSIC`,
  /// `STORED_MUSIC_MEDIA_RENDERER`, `UPNP`, …).
  static bool _isLibrarySource(String source) {
    final s = source.toUpperCase();
    return s.contains('STORED_MUSIC') ||
        s.contains('UPNP') ||
        s.contains('DLNA') ||
        s.contains('MEDIA_RENDERER');
  }

  Future<void> refresh() async {
    try {
      String? rawSources;
      try {
        rawSources = await _client.debugGet('/sources');
      } on SoundTouchException {
        rawSources = null;
      }
      final sources = await _client.getSources();
      final registered = [
        for (final s in sources)
          if (_isLibrarySource(s.source) && (s.sourceAccount ?? '').isNotEmpty)
            RegisteredServer(
              account: s.sourceAccount!,
              name: s.displayName,
              ready: s.isReady,
            ),
      ];

      var discovered = <MediaServer>[];
      String? rawMedia;
      try {
        rawMedia = await _client.debugGet('/listMediaServers');
        final all = await _client.listMediaServers();
        final known = registered
            .map((r) => r.account.replaceAll('/0', '').replaceAll('uuid:', ''))
            .toSet();
        discovered = [
          for (final m in all)
            if (!known.contains(m.udn)) m,
        ];
      } on SoundTouchException {
        discovered = [];
      }

      if (_disposed) return;
      state = state.copyWith(
        loading: false,
        unreachable: false,
        registered: registered,
        discovered: discovered,
        rawSources: rawSources,
        rawMediaServers: rawMedia,
      );
    } on SoundTouchException {
      if (!_disposed) {
        state = state.copyWith(loading: false, unreachable: true);
      }
    }
  }

  Future<String?> register(MediaServer server) async {
    state = state.copyWith(busy: true);
    try {
      await _client.addLibraryServer(server.udn, server.name);
      try {
        final info = await _client.getInfo();
        await _client.notifySourcesUpdated(info.deviceId);
      } on SoundTouchException {
        /* nudge is best-effort */
      }
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await refresh();
      return null;
    } on SoundTouchApiError catch (e) {
      return 'Speaker refused the server (${e.name}).';
    } on SoundTouchException {
      return "Couldn't add that server.";
    } finally {
      if (!_disposed) state = state.copyWith(busy: false);
    }
  }

  Future<String?> unregister(String account) async {
    state = state.copyWith(busy: true);
    try {
      await _client.removeLibraryServer(account);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await refresh();
      return null;
    } on SoundTouchException {
      return "Couldn't remove that server.";
    } finally {
      if (!_disposed) state = state.copyWith(busy: false);
    }
  }

  // --- browsing --------------------------------------------------------------

  Future<void> open(String account, String name) async {
    state = state.copyWith(
      browseAccount: account,
      crumbs: [Crumb(name, null)],
      entries: const [],
      browseLoading: true,
      browseError: null,
    );
    await _loadCurrent();
  }

  void closeBrowse() {
    state = state.copyWith(
      browseAccount: null,
      crumbs: const [],
      entries: const [],
      browseError: null,
    );
  }

  Future<void> enter(NavigateItem item) async {
    if (!item.isDir || item.contentItem == null) return;
    state = state.copyWith(
      crumbs: [...state.crumbs, Crumb(item.name, item.contentItem)],
      entries: const [],
      browseLoading: true,
      browseError: null,
    );
    await _loadCurrent();
  }

  Future<void> up() async {
    if (state.crumbs.length <= 1) {
      closeBrowse();
      return;
    }
    state = state.copyWith(
      crumbs: state.crumbs.sublist(0, state.crumbs.length - 1),
      entries: const [],
      browseLoading: true,
      browseError: null,
    );
    await _loadCurrent();
  }

  Future<void> _loadCurrent() async {
    final account = state.browseAccount;
    if (account == null) return;
    final container = state.crumbs.last.container;
    try {
      var detail = await _client.navigateDetailed(
        'STORED_MUSIC',
        sourceAccount: account,
        container: container,
      );
      // Some firmware only wants the sourceAccount when descending, not at the
      // server root — retry once without it if the root came back empty.
      if (detail.response.items.isEmpty && container == null) {
        final alt = await _client.navigateDetailed('STORED_MUSIC',
            container: null);
        if (alt.response.items.isNotEmpty) detail = alt;
      }
      if (_disposed) return;
      state = state.copyWith(
        entries: detail.response.items,
        browseLoading: false,
        browseError: null,
        browseRaw: detail.raw,
        browseRequest: detail.request,
      );
    } on SoundTouchException catch (e) {
      if (!_disposed) {
        state = state.copyWith(
          browseLoading: false,
          browseError: e.message,
          browseRaw: e is SoundTouchParseError ? e.rawBody : null,
        );
      }
    }
  }

  Future<String?> play(NavigateItem item) async {
    final ci = item.contentItem;
    if (ci == null) return "That item can't be played.";
    try {
      await _client.select(ci);
      await ref.read(speakerHubProvider(arg).notifier).refreshSoon();
      return null;
    } on SoundTouchException {
      return "Couldn't start playback.";
    }
  }
}
