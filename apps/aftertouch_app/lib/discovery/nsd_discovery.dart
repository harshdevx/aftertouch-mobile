import 'dart:async';

import 'package:nsd/nsd.dart' as nsd;
import 'package:soundtouch_client/soundtouch_client.dart';

/// [SpeakerDiscovery] backed by the platform's service-discovery stack
/// (Android NsdManager, Apple NetService) via the `nsd` plugin.
///
/// On Android this also acquires the Wi-Fi multicast lock for the whole
/// process, which lets a concurrently-running [MdnsDiscovery] actually
/// receive responses — the two are meant to run together behind a
/// [CompositeDiscovery].
class NsdDiscovery implements SpeakerDiscovery {
  NsdDiscovery();

  final _controller = StreamController<List<DiscoveredSpeaker>>.broadcast();
  final _reports = StreamController<DiscoveryReport>.broadcast();
  final Map<String, DiscoveredSpeaker> _found = <String, DiscoveredSpeaker>{};
  final List<nsd.Discovery> _handles = <nsd.Discovery>[];
  bool _running = false;
  bool _busy = false;
  int _rawSeen = 0;

  @override
  Stream<List<DiscoveredSpeaker>> get speakers => _controller.stream;

  @override
  Stream<DiscoveryReport> get reports => _reports.stream;

  void _report(DiscoveryPhase phase, {String? detail}) {
    if (_reports.isClosed) return;
    _reports.add(DiscoveryReport(
      source: 'nsd',
      phase: phase,
      seen: _rawSeen,
      speakers: _found.length,
      detail: detail,
    ));
  }

  @override
  Future<void> start() async {
    if (_running || _busy) return;
    _running = true;
    await _beginBrowse();
  }

  @override
  Future<void> restart() async {
    if (_busy) return;
    // A live browse that has already produced results is left alone — tearing
    // an NsdManager discovery down and back up mid-flight just loses state.
    if (_handles.isNotEmpty && _found.isNotEmpty) return;
    await _tearDown();
    _found.clear();
    _running = true;
    await _beginBrowse();
  }

  Future<void> _beginBrowse() async {
    _busy = true;
    _report(DiscoveryPhase.starting);
    var ok = 0;
    for (final type in mdnsServiceTypes) {
      try {
        // No ipLookupType: on some Android builds the extra resolve step
        // times out and drops the service entirely. autoResolve gives us
        // host+port; MdnsDiscovery (run alongside) supplies clean IPv4s.
        final handle = await nsd.startDiscovery('$type.', autoResolve: true);
        handle.addListener(() => _sync(handle));
        _handles.add(handle);
        ok++;
      } catch (e) {
        _report(DiscoveryPhase.error, detail: '$type: $e');
      }
    }
    _busy = false;
    _report(
      ok == 0 ? DiscoveryPhase.error : DiscoveryPhase.browsing,
      detail: 'browsing $ok/${mdnsServiceTypes.length} service types',
    );
  }

  void _sync(nsd.Discovery handle) {
    _rawSeen = handle.services.length;
    for (final service in handle.services) {
      final speaker = _toSpeaker(service);
      if (speaker == null) continue;
      _found[speaker.deviceId ?? speaker.host] = speaker;
    }
    if (!_controller.isClosed) {
      _controller.add(List.unmodifiable(_found.values));
    }
    _report(DiscoveryPhase.browsing);
  }

  DiscoveredSpeaker? _toSpeaker(nsd.Service s) {
    // Prefer a resolved IPv4 address; fall back to the (possibly .local) host.
    String? addr;
    final addresses = s.addresses;
    if (addresses != null && addresses.isNotEmpty) {
      addr = addresses
          .firstWhere(
            (a) => a.type.name == 'IPv4',
            orElse: () => addresses.first,
          )
          .address;
    }
    addr ??= s.host;
    if (addr == null || addr.isEmpty) return null;

    final txt = <String, String>{};
    s.txt?.forEach((k, v) {
      if (v != null) txt[k] = String.fromCharCodes(v);
    });

    return DiscoveredSpeaker(
      host: addr,
      port: (s.port ?? 0) == 0 ? httpPort : s.port!,
      name: s.name,
      deviceId: txt['MAC'] ?? txt['mac'],
      model: txt['DESCRIPTION'] ?? txt['MANUFACTURER'],
      source: DiscoverySource.mdns,
    );
  }

  Future<void> _tearDown() async {
    _running = false;
    for (final h in _handles) {
      try {
        await nsd.stopDiscovery(h);
      } catch (_) {}
    }
    _handles.clear();
  }

  @override
  Future<void> stop() async {
    await _tearDown();
    await _controller.close();
    await _reports.close();
  }
}
