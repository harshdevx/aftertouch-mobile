import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:soundtouch_client/soundtouch_client.dart';

import '../../data/aftertouch_providers.dart';
import '../../data/speaker_hub.dart';

enum CatalogProvider { tuneIn, radioBrowser }

class CatalogCrumb {
  const CatalogCrumb(this.name, this.path);
  final String name;

  /// null = provider root (TuneIn only).
  final String? path;
}

class CatalogState {
  const CatalogState({
    this.provider = CatalogProvider.tuneIn,
    this.loading = false,
    this.error,
    this.sections = const [],
    this.crumbs = const [],
    this.query = '',
    this.searchMode = false,
  });

  final CatalogProvider provider;
  final bool loading;
  final String? error;
  final List<BmxSection> sections;
  final List<CatalogCrumb> crumbs;
  final String query;
  final bool searchMode;

  bool get canGoUp => searchMode || crumbs.length > 1;

  CatalogState copyWith({
    CatalogProvider? provider,
    bool? loading,
    Object? error = _keep,
    List<BmxSection>? sections,
    List<CatalogCrumb>? crumbs,
    String? query,
    bool? searchMode,
  }) =>
      CatalogState(
        provider: provider ?? this.provider,
        loading: loading ?? this.loading,
        error: error == _keep ? this.error : error as String?,
        sections: sections ?? this.sections,
        crumbs: crumbs ?? this.crumbs,
        query: query ?? this.query,
        searchMode: searchMode ?? this.searchMode,
      );

  static const _keep = Object();
}

final catalogControllerProvider =
    NotifierProvider<CatalogController, CatalogState>(CatalogController.new);

class CatalogController extends Notifier<CatalogState> {
  AfterTouchClient? get _client => ref.read(afterTouchClientProvider);

  /// speakerKey → the key the AfterTouch server has this speaker registered
  /// under (often not the LAN IP we know it by).
  final _serverKeyCache = <String, String>{};

  static String _normId(String? s) =>
      (s ?? '').toUpperCase().replaceAll(RegExp('[^0-9A-F]'), '');

  /// Resolve which registry key the AfterTouch server expects for [speakerKey].
  /// Matches on the speaker's Bose device id first (survives IP changes), then
  /// on address. Triggers a server-side sweep once if the speaker is missing.
  Future<String?> _serverDeviceKey(AfterTouchClient client, String speakerKey) async {
    if (_serverKeyCache[speakerKey] case final cached?) return cached;

    final host = speakerKey.split(':').first;
    final wantId = _normId(ref.read(speakerHubProvider(speakerKey)).info?.deviceId);

    String? match(List<AtServerDevice> devices) {
      for (final d in devices) {
        if (wantId.isNotEmpty && _normId(d.deviceId) == wantId) return d.key;
      }
      for (final d in devices) {
        if (d.ip == host || d.key == host || d.key == speakerKey) return d.key;
      }
      return null;
    }

    var key = match(await client.serverDevices());
    if (key == null) {
      await client.triggerServerDiscovery();
      await Future<void>.delayed(const Duration(milliseconds: 2500));
      key = match(await client.serverDevices());
    }
    if (key != null) _serverKeyCache[speakerKey] = key;
    return key;
  }

  @override
  CatalogState build() {
    Future.microtask(browseRoot);
    return const CatalogState(loading: true);
  }

  void switchProvider(CatalogProvider p) {
    if (p == state.provider) return;
    state = CatalogState(provider: p, loading: true);
    if (p == CatalogProvider.tuneIn) {
      browseRoot();
    } else {
      state = state.copyWith(loading: false, sections: const []);
    }
  }

  Future<void> browseRoot() async {
    final client = _client;
    if (client == null) {
      state = state.copyWith(loading: false, error: 'No AfterTouch server set');
      return;
    }
    state = state.copyWith(
      loading: true,
      error: null,
      searchMode: false,
      query: '',
      crumbs: const [CatalogCrumb('Browse', null)],
    );
    await _load(() => client.tuneInNavigate());
  }

  Future<void> enter(BmxItem item) async {
    final client = _client;
    if (client == null || item.navigatePath == null) return;
    state = state.copyWith(
      loading: true,
      error: null,
      crumbs: [...state.crumbs, CatalogCrumb(item.name, item.navigatePath)],
    );
    await _load(() => client.tuneInNavigate(item.navigatePath));
  }

  Future<void> up() async {
    final client = _client;
    if (client == null) return;
    if (state.searchMode) {
      await browseRoot();
      return;
    }
    if (state.crumbs.length <= 1) return;
    final crumbs = state.crumbs.sublist(0, state.crumbs.length - 1);
    state = state.copyWith(loading: true, error: null, crumbs: crumbs);
    await _load(() => client.tuneInNavigate(crumbs.last.path));
  }

  Future<void> search(String q) async {
    final client = _client;
    final query = q.trim();
    if (client == null || query.isEmpty) return;
    state = state.copyWith(
      loading: true,
      error: null,
      searchMode: true,
      query: query,
      crumbs: [CatalogCrumb('"$query"', null)],
    );
    await _load(
      () => state.provider == CatalogProvider.tuneIn
          ? client.tuneInSearch(query)
          : client.radioBrowserSearch(query),
    );
  }

  Future<void> _load(Future<BmxNav> Function() fetch) async {
    try {
      final nav = await fetch();
      state = state.copyWith(loading: false, sections: nav.sections, error: null);
    } on AfterTouchException catch (e) {
      state = state.copyWith(loading: false, error: e.message, sections: const []);
    }
  }

  /// Returns null on success, else a message.
  Future<String?> play(BmxItem item, String speakerKey) async {
    final client = _client;
    if (client == null || item.playLocation == null) {
      return "That item can't be played.";
    }
    try {
      final deviceKey = await _serverDeviceKey(client, speakerKey);
      if (deviceKey == null) {
        return 'Your AfterTouch server can’t see this speaker. It has to be on '
            'the same network as the speaker — open the server’s web UI and run '
            'discovery, then try again.';
      }
      if (state.provider == CatalogProvider.tuneIn) {
        await client.playTuneIn(deviceKey,
            location: item.playLocation!, type: item.playType, name: item.name);
      } else {
        await client.playRadioBrowser(deviceKey,
            location: item.playLocation!, name: item.name);
      }
      await ref.read(speakerHubProvider(speakerKey).notifier).refreshSoon();
      return null;
    } on AfterTouchException catch (e) {
      return e.message;
    }
  }
}
