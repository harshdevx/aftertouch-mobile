import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soundtouch_client/soundtouch_client.dart';

import 'nsd_discovery.dart';

const _kKnownHostsPref = 'known_speaker_hosts';

/// The discovery backend. Overridable in tests with a [ManualDiscovery].
///
/// On device we run **both** the platform NSD stack *and* pure-Dart mDNS:
/// NSD holds the Wi-Fi multicast lock and handles the iOS permission, while
/// the pure-Dart path does active periodic queries and resolves clean IPv4
/// addresses (NSD sometimes only yields a `.local` name). Either one alone
/// has been observed to miss the speaker on Android.
final speakerDiscoveryProvider = Provider<SpeakerDiscovery>((ref) {
  final d = CompositeDiscovery([
    NsdDiscovery(),
    MdnsDiscovery(scanInterval: const Duration(seconds: 8)),
  ]);
  ref.onDispose(d.stop);
  return d;
});

/// One row on the Devices screen: what discovery told us, enriched with a
/// live `/info` + `/now_playing` probe.
class SpeakerEntry {
  const SpeakerEntry({
    required this.discovered,
    this.info,
    this.nowPlaying,
    this.reachable = false,
    this.probed = false,
  });

  final DiscoveredSpeaker discovered;
  final DeviceInfo? info;
  final NowPlaying? nowPlaying;
  final bool reachable;

  /// True once at least one `/info` probe has completed (so we don't flash
  /// "Offline" before the first check returns).
  final bool probed;

  String get id => info?.deviceId ?? discovered.deviceId ?? discovered.host;
  String get name => info?.name ?? discovered.name ?? discovered.host;
  String get host => discovered.host;
  String get model => info?.type ?? discovered.model ?? '';

  String get speakerKey => discovered.port == 8090
      ? discovered.host
      : '${discovered.host}:${discovered.port}';

  bool get isPlaying => nowPlaying?.playStatus.isPlaying ?? false;

  String get secondaryLine {
    if (!probed) return 'Checking…';
    if (!reachable) return 'Offline';
    final np = nowPlaying;
    if (np == null) return model.isEmpty ? 'Online' : model;
    if (np.isStandby) return 'Standby';
    if (np.playStatus.isPlaying) {
      final artist = np.secondaryLine;
      return artist == null ? np.primaryLine : '${np.primaryLine} — $artist';
    }
    return 'Idle';
  }

  SpeakerEntry copyWith({
    DeviceInfo? info,
    NowPlaying? nowPlaying,
    bool? reachable,
    bool? probed,
  }) =>
      SpeakerEntry(
        discovered: discovered,
        info: info ?? this.info,
        nowPlaying: nowPlaying ?? this.nowPlaying,
        reachable: reachable ?? this.reachable,
        probed: probed ?? this.probed,
      );
}

class DevicesState {
  const DevicesState({
    this.scanning = false,
    this.entries = const [],
    this.reports = const {},
    this.localIps = const [],
    this.knownHostCount = 0,
  });

  final bool scanning;
  final List<SpeakerEntry> entries;

  /// Latest [DiscoveryReport] per mechanism (`nsd`, `mdns`).
  final Map<String, DiscoveryReport> reports;

  /// This device's own IPv4 address(es) — shows the user which subnet the
  /// phone is on, to compare against where the speaker lives.
  final List<String> localIps;

  final int knownHostCount;

  bool get isEmpty => entries.isEmpty;

  /// One-line summary for the collapsed status strip.
  String get summaryLine {
    final parts = <String>[];
    for (final src in const ['nsd', 'mdns']) {
      final r = reports[src];
      if (r == null) continue;
      parts.add('${src.toUpperCase()} ${r.phase.name}');
    }
    if (parts.isEmpty) return scanning ? 'Starting discovery…' : 'Idle';
    final replies = reports.values.fold<int>(0, (a, r) => a + r.seen);
    return '${parts.join(" · ")} · $replies replies';
  }

  DevicesState copyWith({
    bool? scanning,
    List<SpeakerEntry>? entries,
    Map<String, DiscoveryReport>? reports,
    List<String>? localIps,
    int? knownHostCount,
  }) =>
      DevicesState(
        scanning: scanning ?? this.scanning,
        entries: entries ?? this.entries,
        reports: reports ?? this.reports,
        localIps: localIps ?? this.localIps,
        knownHostCount: knownHostCount ?? this.knownHostCount,
      );
}

final devicesControllerProvider =
    NotifierProvider<DevicesController, DevicesState>(DevicesController.new);

class DevicesController extends Notifier<DevicesState>
    with WidgetsBindingObserver {
  StreamSubscription<List<DiscoveredSpeaker>>? _sub;
  StreamSubscription<DiscoveryReport>? _reportSub;
  final _manual = <DiscoveredSpeaker>[];
  final _knownGood = <String>{};
  bool _disposed = false;
  DateTime _lastRescan = DateTime.fromMillisecondsSinceEpoch(0);
  late SpeakerDiscovery _discovery;

  @override
  DevicesState build() {
    final discovery = _discovery = ref.read(speakerDiscoveryProvider);
    _disposed = false;
    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() {
      _disposed = true;
      WidgetsBinding.instance.removeObserver(this);
      _sub?.cancel();
      _reportSub?.cancel();
    });

    _sub = discovery.speakers.listen(_onDiscovered);
    _reportSub = discovery.reports.listen(_onReport);
    Future.microtask(() async {
      if (_disposed) return;
      await _loadKnownHosts();
      await _loadLocalIps();
      if (!_disposed) unawaited(discovery.start());
    });

    return const DevicesState(scanning: true);
  }

  void _onReport(DiscoveryReport r) {
    if (_disposed) return;
    state = state.copyWith(reports: {...state.reports, r.source: r});
  }

  Future<void> _loadLocalIps() async {
    try {
      final ifaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      final ips = [
        for (final i in ifaces)
          for (final a in i.addresses) a.address,
      ];
      if (!_disposed) state = state.copyWith(localIps: ips);
    } catch (_) {/* not fatal */}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Only re-sweep on resume when we have nothing to show — a working list
    // shouldn't be disturbed every time the app foregrounds.
    if (state == AppLifecycleState.resumed &&
        !_disposed &&
        !this.state.entries.any((e) => e.reachable)) {
      unawaited(rescan());
    }
  }

  Future<void> rescan() async {
    final now = DateTime.now();
    if (now.difference(_lastRescan) < const Duration(seconds: 2)) return;
    _lastRescan = now;

    state = state.copyWith(scanning: true);
    try {
      await _discovery.restart();
    } catch (_) {/* non-fatal */}
    await Future.wait([
      for (final e in state.entries) _probe(e.discovered),
      for (final m in _manual) _probe(m),
    ]);
    if (!_disposed) state = state.copyWith(scanning: false);
  }

  /// Add a speaker by IP/host that discovery can't see (VLAN, mDNS blocked).
  Future<void> addManual(String host) async {
    final trimmed = host.trim();
    if (trimmed.isEmpty) return;
    _manual
      ..removeWhere((e) => e.host == trimmed)
      ..add(DiscoveredSpeaker(host: trimmed));
    _onDiscovered(const []);
  }

  Future<void> _loadKnownHosts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hosts = prefs.getStringList(_kKnownHostsPref) ?? const [];
      for (final h in hosts) {
        _knownGood.add(h);
        if (!_manual.any((e) => e.host == h)) {
          _manual.add(DiscoveredSpeaker(host: h));
        }
      }
      if (!_disposed) state = state.copyWith(knownHostCount: hosts.length);
      if (hosts.isNotEmpty) _onDiscovered(const []);
    } catch (_) {/* first run / no prefs */}
  }

  Future<void> _rememberHost(String host) async {
    if (!_knownGood.add(host)) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_kKnownHostsPref, _knownGood.toList());
    } catch (_) {}
  }

  void _onDiscovered(List<DiscoveredSpeaker> found) {
    if (_disposed) return;
    final byKey = <String, SpeakerEntry>{};
    for (final existing in state.entries) {
      byKey[existing.id] = existing;
    }
    for (final s in [..._manual, ...found]) {
      byKey.putIfAbsent(
        s.deviceId ?? s.host,
        () => SpeakerEntry(discovered: s),
      );
    }

    state = state.copyWith(
      scanning: false,
      entries: byKey.values.toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
    );

    for (final s in [..._manual, ...found]) {
      unawaited(_probe(s));
    }
  }

  Future<void> _probe(DiscoveredSpeaker s) async {
    final client = SoundTouchClient(host: s.host, httpPort: s.port);
    try {
      final info = await client.getInfo();
      NowPlaying? np;
      try {
        np = await client.getNowPlaying();
      } on SoundTouchException {
        np = null;
      }
      _apply(s,
          (e) => e.copyWith(info: info, nowPlaying: np, reachable: true, probed: true));
      unawaited(_rememberHost(s.host));
    } on SoundTouchException {
      _apply(s, (e) => e.copyWith(reachable: false, probed: true));
    } finally {
      await client.dispose();
    }
  }

  void _apply(
    DiscoveredSpeaker s,
    SpeakerEntry Function(SpeakerEntry) update,
  ) {
    if (_disposed) return;
    final key = s.deviceId ?? s.host;
    state = state.copyWith(
      entries: [
        for (final e in state.entries)
          if (e.id == key || e.host == s.host) update(e) else e,
      ],
    );
  }
}
