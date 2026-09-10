import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soundtouch_client/soundtouch_client.dart';

import 'nsd_discovery.dart';

const _kKnownHostsPref = 'known_speaker_hosts';

/// Discovery can emit many times a second (NSD fires per-service, mDNS per
/// pass). Coalesce bursts into one rebuild.
const _kRebuildDebounce = Duration(milliseconds: 300);

/// Never re-probe the same host more often than this (protects against rapid
/// rebuilds hammering the network / main thread).
const _kMinProbeGap = Duration(seconds: 5);

/// Background reachability sweep so "offline → online" still updates without a
/// manual rescan.
const _kRefreshInterval = Duration(seconds: 15);

/// Cap concurrent `/info` probes so a handful of dead hosts can't tie up the
/// event loop with pending sockets.
const _kMaxConcurrentProbes = 4;

/// A host that has *never* answered this session and fails this many probes in
/// a row is treated as a stale record (moved network, old mDNS cache, dead
/// saved entry) and hidden until the next explicit rescan or app restart.
/// Speakers that answered at least once are kept and shown as "Offline".
const _kAutoDropAfterFails = 3;

/// Per-probe network timeout. A speaker on the LAN answers `/info` in well
/// under a second; anything slower is treated as unreachable.
const _kProbeTimeout = Duration(seconds: 3);

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
    // Pure-Dart mDNS is the Android safety net; keep its cadence slow — each
    // pass binds a socket and parses all LAN mDNS traffic.
    MdnsDiscovery(scanInterval: const Duration(seconds: 15)),
  ]);
  ref.onDispose(d.stop);
  return d;
});

bool _looksLikeIp(String h) =>
    RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(h);

bool _isLocalName(String h) => !_looksLikeIp(h);

/// A normalised MAC / device-id key, or null when we don't have one yet.
String? _macKey(String? mac) {
  final m = mac?.trim().toLowerCase();
  return (m == null || m.isEmpty) ? null : 'mac:$m';
}

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

  /// Stable key for list identity (e.g. `Dismissible`). Prefers the MAC once
  /// a probe has revealed it, so the key doesn't change as the row enriches.
  String get dedupeKey =>
      _macKey(info?.deviceId ?? discovered.deviceId) ??
      'host:${discovered.host.toLowerCase()}';

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
    DiscoveredSpeaker? discovered,
    DeviceInfo? info,
    NowPlaying? nowPlaying,
    bool? reachable,
    bool? probed,
  }) =>
      SpeakerEntry(
        discovered: discovered ?? this.discovered,
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
    this.localIps = const [],
    this.knownHostCount = 0,
  });

  final bool scanning;
  final List<SpeakerEntry> entries;

  /// This device's own IPv4 address(es).
  final List<String> localIps;

  final int knownHostCount;

  bool get isEmpty => entries.isEmpty;

  DevicesState copyWith({
    bool? scanning,
    List<SpeakerEntry>? entries,
    List<String>? localIps,
    int? knownHostCount,
  }) =>
      DevicesState(
        scanning: scanning ?? this.scanning,
        entries: entries ?? this.entries,
        localIps: localIps ?? this.localIps,
        knownHostCount: knownHostCount ?? this.knownHostCount,
      );
}

final devicesControllerProvider =
    NotifierProvider<DevicesController, DevicesState>(DevicesController.new);

/// Remembers a just-removed row so the UI can offer a single-level undo.
class _Removed {
  _Removed(this.entry, this.keys,
      {required this.wasManual, required this.wasKnown});
  final SpeakerEntry entry;
  final Set<String> keys;
  final bool wasManual;
  final bool wasKnown;
}

class DevicesController extends Notifier<DevicesState>
    with WidgetsBindingObserver {
  StreamSubscription<List<DiscoveredSpeaker>>? _sub;
  final _manual = <DiscoveredSpeaker>[];
  final _knownGood = <String>{};

  /// Identity keys the user has removed this session — discovery hits matching
  /// any of these are ignored until the app restarts.
  final _dismissed = <String>{};
  _Removed? _lastRemoved;

  /// Hosts auto-dropped as stale mDNS records. Suppressed until the next
  /// explicit [rescan] (unlike [_dismissed], which lasts the whole session).
  final _autoDropped = <String>{};

  /// Consecutive failed probes per host, and hosts that have answered at least
  /// once this session (never auto-drop those).
  final _probeFails = <String, int>{};
  final _everReachable = <String>{};

  // Debounced discovery ingest.
  List<DiscoveredSpeaker> _lastFound = const [];
  Timer? _rebuildTimer;

  // Probe scheduling: bounded concurrency + per-host rate limiting.
  final _probing = <String>{};
  final _probeQueue = <DiscoveredSpeaker>[];
  final _probeAt = <String, DateTime>{};

  Timer? _refreshTimer;
  Timer? _scanFallback;

  bool _disposed = false;
  DateTime _lastRescan = DateTime.fromMillisecondsSinceEpoch(0);
  late SpeakerDiscovery _discovery;

  @override
  DevicesState build() {
    _discovery = ref.read(speakerDiscoveryProvider);
    _disposed = false;
    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() {
      _disposed = true;
      WidgetsBinding.instance.removeObserver(this);
      _sub?.cancel();
      _rebuildTimer?.cancel();
      _refreshTimer?.cancel();
      _scanFallback?.cancel();
    });

    _sub = _discovery.speakers.listen(_ingest);
    _refreshTimer =
        Timer.periodic(_kRefreshInterval, (_) => _refreshReachability());
    _scanFallback = Timer(const Duration(seconds: 10), _settleScanning);

    Future.microtask(() async {
      if (_disposed) return;
      await _loadKnownHosts();
      await _loadLocalIps();
      if (!_disposed) unawaited(_discovery.start());
    });

    return const DevicesState(scanning: true);
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
    _scanFallback?.cancel();
    _scanFallback = Timer(const Duration(seconds: 8), _settleScanning);
    try {
      await _discovery.restart();
    } catch (_) {/* non-fatal */}
    // An explicit rescan re-checks everything and gives auto-dropped hosts
    // another chance (a user swipe, tracked separately, still sticks).
    _probeAt.clear();
    _probeFails.clear();
    _autoDropped.clear();
    _rebuild();
  }

  /// Add a speaker by IP/host that discovery can't see (VLAN, mDNS blocked).
  Future<void> addManual(String host) async {
    final trimmed = host.trim();
    if (trimmed.isEmpty) return;
    // Adding by hand clears any earlier dismissal of that address.
    _dismissed.remove('host:${trimmed.toLowerCase()}');
    _probeAt.remove(trimmed);
    _manual
      ..removeWhere((e) => e.host == trimmed)
      ..add(DiscoveredSpeaker(host: trimmed));
    _rebuild();
  }

  /// Remove a row from the list. It won't come back from passive discovery
  /// this session; an explicit "Add by IP" or app restart brings it back.
  Future<void> remove(SpeakerEntry entry) async {
    final keys = _dismissKeys(entry);
    _dismissed.addAll(keys);

    final host = entry.discovered.host;
    final wasManual = _manual.any((m) => m.host == host);
    _manual.removeWhere((m) => m.host == host);
    final wasKnown = _knownGood.remove(host);
    if (wasKnown) await _persistKnown();

    _lastRemoved =
        _Removed(entry, keys, wasManual: wasManual, wasKnown: wasKnown);

    state = state.copyWith(
      entries: [
        for (final e in state.entries)
          if (!identical(e, entry) && !_sameSpeaker(e, entry)) e,
      ],
      knownHostCount: _knownGood.length,
    );
  }

  /// Undo the most recent [remove].
  Future<void> undoLastRemove() async {
    final r = _lastRemoved;
    if (r == null) return;
    _lastRemoved = null;
    _dismissed.removeAll(r.keys);

    final host = r.entry.discovered.host;
    if ((r.wasManual || r.wasKnown) && !_manual.any((m) => m.host == host)) {
      _manual.add(DiscoveredSpeaker(host: host));
    }
    if (r.wasKnown) {
      _knownGood.add(host);
      await _persistKnown();
    }
    _probeAt.remove(host);

    if (!state.entries.any((e) => _sameSpeaker(e, r.entry))) {
      state = state.copyWith(
        entries: [
          ...state.entries,
          r.entry.copyWith(probed: false),
        ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
        knownHostCount: _knownGood.length,
      );
    } else {
      state = state.copyWith(knownHostCount: _knownGood.length);
    }
    _queueProbe(r.entry.discovered);
  }

  Set<String> _dismissKeys(SpeakerEntry e) {
    final keys = <String>{'host:${e.discovered.host.toLowerCase()}'};
    final mac = _macKey(e.info?.deviceId ?? e.discovered.deviceId);
    if (mac != null) keys.add(mac);
    final n = e.name.toLowerCase().trim();
    if (n.isNotEmpty && n != e.discovered.host.toLowerCase()) keys.add('name:$n');
    return keys;
  }

  bool _isSuppressed(DiscoveredSpeaker s) {
    if (_autoDropped.contains(s.host.toLowerCase())) return true;
    if (_dismissed.isEmpty) return false;
    if (_dismissed.contains('host:${s.host.toLowerCase()}')) return true;
    final mac = _macKey(s.deviceId);
    if (mac != null && _dismissed.contains(mac)) return true;
    final n = s.name?.toLowerCase().trim();
    return n != null && n.isNotEmpty && _dismissed.contains('name:$n');
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
      if (hosts.isNotEmpty) _rebuild();
    } catch (_) {/* first run / no prefs */}
  }

  Future<void> _persistKnown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_kKnownHostsPref, _knownGood.toList());
    } catch (_) {}
  }

  Future<void> _rememberHost(String host) async {
    if (!_knownGood.add(host)) return;
    await _persistKnown();
    if (!_disposed) state = state.copyWith(knownHostCount: _knownGood.length);
  }

  // --- discovery ingest (debounced) ----------------------------------------

  void _ingest(List<DiscoveredSpeaker> found) {
    if (_disposed) return;
    _lastFound = found;
    _rebuildTimer ??= Timer(_kRebuildDebounce, () {
      _rebuildTimer = null;
      _rebuild();
    });
  }

  void _rebuild() {
    if (_disposed) return;

    final entries = <SpeakerEntry>[...state.entries];
    for (final s in [..._manual, ..._lastFound]) {
      if (_isSuppressed(s)) continue;
      final i = entries.indexWhere((e) => _discoveryMatches(e, s));
      if (i < 0) {
        entries.add(SpeakerEntry(discovered: s));
      } else {
        final better = _preferDiscovered(entries[i].discovered, s);
        if (!identical(better, entries[i].discovered)) {
          entries[i] = entries[i].copyWith(discovered: better);
        }
      }
    }

    final deduped = _collapse(entries)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    if (_sig(deduped) != _sig(state.entries)) {
      state = state.copyWith(entries: deduped);
    }

    for (final e in deduped) {
      if (!e.probed || _probeIsStale(e.host)) _queueProbe(e.discovered);
    }
    _settleScanning();
  }

  // --- probing (rate-limited, bounded concurrency) ------------------------

  bool _probeIsStale(String host) {
    final at = _probeAt[host];
    return at == null || DateTime.now().difference(at) > _kRefreshInterval;
  }

  void _refreshReachability() {
    if (_disposed) return;
    for (final e in state.entries) {
      _queueProbe(e.discovered);
    }
  }

  void _queueProbe(DiscoveredSpeaker s) {
    if (_disposed) return;
    if (_probing.contains(s.host)) return;
    if (_probeQueue.any((q) => q.host == s.host)) return;
    final at = _probeAt[s.host];
    if (at != null && DateTime.now().difference(at) < _kMinProbeGap) return;
    _probeQueue.add(s);
    _pumpProbes();
  }

  void _pumpProbes() {
    while (!_disposed &&
        _probing.length < _kMaxConcurrentProbes &&
        _probeQueue.isNotEmpty) {
      final s = _probeQueue.removeAt(0);
      _probing.add(s.host);
      unawaited(_probe(s).whenComplete(() {
        _probing.remove(s.host);
        _probeAt[s.host] = DateTime.now();
        if (!_disposed) {
          _pumpProbes();
          _settleScanning();
        }
      }));
    }
  }

  void _settleScanning() {
    if (!_disposed &&
        state.scanning &&
        _probing.isEmpty &&
        _probeQueue.isEmpty) {
      state = state.copyWith(scanning: false);
    }
  }

  Future<void> _probe(DiscoveredSpeaker s) async {
    final client = SoundTouchClient(
        host: s.host, httpPort: s.port, timeout: _kProbeTimeout);
    try {
      final info = await client.getInfo();
      NowPlaying? np;
      try {
        np = await client.getNowPlaying();
      } on SoundTouchException {
        np = null;
      }
      _everReachable.add(s.host);
      _probeFails.remove(s.host);
      _apply(
          s,
          (e) => e.copyWith(
              info: info, nowPlaying: np, reachable: true, probed: true));
      unawaited(_rememberHost(s.host));
    } on SoundTouchException {
      _onProbeFailed(s);
    } catch (_) {
      // Any unexpected error is treated the same as unreachable.
      _onProbeFailed(s);
    } finally {
      try {
        await client.dispose();
      } catch (_) {}
    }
  }

  void _onProbeFailed(DiscoveredSpeaker s) {
    if (_disposed) return;
    final fails = (_probeFails[s.host] ?? 0) + 1;
    _probeFails[s.host] = fails;

    if (!_everReachable.contains(s.host) && fails >= _kAutoDropAfterFails) {
      _autoDrop(s.host);
      return;
    }
    _apply(s, (e) => e.copyWith(reachable: false, probed: true));
  }

  /// Pull a host that has never responded: drop its row, stop probing it, and
  /// ignore further discovery hits for it until the next rescan / restart.
  void _autoDrop(String host) {
    if (_disposed) return;
    final h = host.toLowerCase();
    _autoDropped.add(h);
    _probeQueue.removeWhere((q) => q.host.toLowerCase() == h);
    final next = [
      for (final e in state.entries)
        if (e.discovered.host.toLowerCase() != h) e,
    ];
    if (next.length != state.entries.length) {
      state = state.copyWith(entries: next);
    }
    _settleScanning();
  }

  void _apply(
    DiscoveredSpeaker s,
    SpeakerEntry Function(SpeakerEntry) update,
  ) {
    if (_disposed) return;
    final next = [
      for (final e in state.entries)
        if (_discoveryMatches(e, s)) update(e) else e,
    ];
    if (_sig(next) != _sig(state.entries)) {
      state = state.copyWith(entries: next);
    }
  }

  /// Cheap change-detector so an unchanged probe result / discovery tick
  /// doesn't rebuild the list.
  static String _sig(List<SpeakerEntry> es) => es
      .map((e) => '${e.host}:${e.discovered.port}|${e.name}|${e.model}|'
          '${e.reachable}|${e.probed}|${e.isPlaying}|'
          '${e.nowPlaying?.primaryLine}|${e.nowPlaying?.secondaryLine}')
      .join(';;');

  // --- merging -----------------------------------------------------------

  /// True if [a] and [b] are almost certainly the same physical speaker.
  bool _sameSpeaker(SpeakerEntry a, SpeakerEntry b) {
    final am = _macKey(a.info?.deviceId ?? a.discovered.deviceId);
    final bm = _macKey(b.info?.deviceId ?? b.discovered.deviceId);
    if (am != null && bm != null) return am == bm; // two known MACs are decisive
    final ah = a.discovered.host.toLowerCase();
    final bh = b.discovered.host.toLowerCase();
    if (ah == bh) return true;
    // A name match only bridges a `.local` alias to a numeric IP — never two
    // different numeric IPs, which could be a live speaker plus a stale record.
    if (!_isLocalName(ah) && !_isLocalName(bh)) return false;
    final an = a.name.toLowerCase().trim();
    final bn = b.name.toLowerCase().trim();
    return an.isNotEmpty && an == bn;
  }

  bool _discoveryMatches(SpeakerEntry e, DiscoveredSpeaker s) {
    final em = _macKey(e.info?.deviceId ?? e.discovered.deviceId);
    final sm = _macKey(s.deviceId);
    if (em != null && sm != null) return em == sm;
    final eh = e.discovered.host.toLowerCase();
    final sh = s.host.toLowerCase();
    if (eh == sh) return true;
    if (!_isLocalName(eh) && !_isLocalName(sh)) return false;
    final sn = s.name?.toLowerCase().trim();
    return sn != null && sn.isNotEmpty && e.name.toLowerCase().trim() == sn;
  }

  /// Pick the better `DiscoveredSpeaker` when a fresh hit describes a speaker
  /// we already track — upgrade a `.local` host to a routable IP, fill in a
  /// missing name / MAC / model. Returns [cur] unchanged if nothing improves.
  DiscoveredSpeaker _preferDiscovered(
      DiscoveredSpeaker cur, DiscoveredSpeaker inc) {
    final upgradeHost = _isLocalName(cur.host) && !_isLocalName(inc.host);
    final host = upgradeHost ? inc.host : cur.host;
    final port = upgradeHost ? inc.port : cur.port;
    final name = cur.name ?? inc.name;
    final deviceId = cur.deviceId ?? inc.deviceId;
    final model = (cur.model?.isNotEmpty ?? false) ? cur.model : inc.model;

    if (host == cur.host &&
        port == cur.port &&
        name == cur.name &&
        deviceId == cur.deviceId &&
        model == cur.model) {
      return cur;
    }
    return DiscoveredSpeaker(
      host: host,
      port: port,
      name: name,
      deviceId: deviceId,
      model: model,
      source: cur.source,
    );
  }

  SpeakerEntry _mergeEntries(SpeakerEntry a, SpeakerEntry b) {
    final primary = (b.reachable && !a.reachable)
        ? b
        : (a.probed && !b.probed)
            ? a
            : (b.probed && !a.probed)
                ? b
                : a;
    final other = identical(primary, a) ? b : a;
    return primary.copyWith(
      discovered: _preferDiscovered(primary.discovered, other.discovered),
      info: primary.info ?? other.info,
      nowPlaying: primary.nowPlaying ?? other.nowPlaying,
      reachable: primary.reachable || other.reachable,
      probed: primary.probed || other.probed,
    );
  }

  /// Collapse any entries that describe the same speaker (e.g. a `.local` row
  /// and an IP row created before a probe filled in the shared MAC).
  List<SpeakerEntry> _collapse(List<SpeakerEntry> input) {
    final out = <SpeakerEntry>[];
    for (final e in input) {
      final j = out.indexWhere((o) => _sameSpeaker(o, e));
      if (j < 0) {
        out.add(e);
      } else {
        out[j] = _mergeEntries(out[j], e);
      }
    }
    return out;
  }
}
