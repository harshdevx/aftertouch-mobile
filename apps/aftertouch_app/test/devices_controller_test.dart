import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soundtouch_client/soundtouch_client.dart';

import 'package:aftertouch_app/discovery/devices_controller.dart';

// Longer than the controller's discovery debounce so a rebuild has run.
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 400));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  ProviderContainer harness(ManualDiscovery d) {
    final c = ProviderContainer(
      overrides: [speakerDiscoveryProvider.overrideWithValue(d)],
    );
    addTearDown(c.dispose);
    c.read(devicesControllerProvider); // force build()
    return c;
  }

  test('a .local hit and an IP hit for the same speaker collapse to one row',
      () async {
    final disco = ManualDiscovery();
    final c = harness(disco);

    disco.add(const DiscoveredSpeaker(
        host: 'kitchen.local',
        name: 'Kitchen',
        source: DiscoverySource.mdns));
    disco.add(const DiscoveredSpeaker(
        host: '192.0.2.9', name: 'Kitchen', source: DiscoverySource.mdns));
    await _settle();

    final entries = c.read(devicesControllerProvider).entries;
    expect(entries, hasLength(1));
    expect(entries.single.host, '192.0.2.9',
        reason: 'the routable IP should win over the .local name');
  });

  test('the same speaker seen on every tick never duplicates', () async {
    final disco = ManualDiscovery();
    final c = harness(disco);

    const hit = DiscoveredSpeaker(
      host: '192.0.2.10',
      name: 'Den',
      deviceId: 'AA:BB:CC:00:11:22',
      source: DiscoverySource.mdns,
    );
    for (var i = 0; i < 5; i++) {
      disco.add(hit);
      await _settle();
    }

    expect(c.read(devicesControllerProvider).entries, hasLength(1));
  });

  test('a MAC-tagged .local hit merges with a bare IP hit of the same MAC',
      () async {
    final disco = ManualDiscovery();
    final c = harness(disco);

    disco.add(const DiscoveredSpeaker(
      host: 'office.local',
      name: 'Office',
      deviceId: '00:11:22:33:44:55',
      source: DiscoverySource.mdns,
    ));
    disco.add(const DiscoveredSpeaker(
      host: '192.0.2.11',
      deviceId: '00:11:22:33:44:55',
      source: DiscoverySource.mdns,
    ));
    await _settle();

    final entries = c.read(devicesControllerProvider).entries;
    expect(entries, hasLength(1));
    expect(entries.single.host, '192.0.2.11');
  });

  test('two numeric IPs sharing a name stay separate rows (no phantom merge)',
      () async {
    final disco = ManualDiscovery();
    final c = harness(disco);

    // A stale mDNS record and the live address, same speaker name.
    disco.add(const DiscoveredSpeaker(
        host: '192.0.2.17', name: 'Kitchen', source: DiscoverySource.mdns));
    disco.add(const DiscoveredSpeaker(
        host: '192.0.2.42', name: 'Kitchen', source: DiscoverySource.mdns));
    await _settle();

    final hosts = c
        .read(devicesControllerProvider)
        .entries
        .map((e) => e.host)
        .toSet();
    expect(hosts, {'192.0.2.17', '192.0.2.42'},
        reason: 'a stale IP must not be able to hide the live one');
  });

  test('remove() drops the row and blocks re-discovery until undo', () async {
    final disco = ManualDiscovery();
    final c = harness(disco);
    final ctrl = c.read(devicesControllerProvider.notifier);

    disco.add(const DiscoveredSpeaker(
        host: '192.0.2.20', name: 'Patio', source: DiscoverySource.mdns));
    await _settle();
    expect(c.read(devicesControllerProvider).entries, hasLength(1));

    await ctrl.remove(c.read(devicesControllerProvider).entries.single);
    expect(c.read(devicesControllerProvider).entries, isEmpty);

    // A fresh, identical discovery tick must not resurrect it.
    disco.add(const DiscoveredSpeaker(
        host: '192.0.2.20', name: 'Patio', source: DiscoverySource.mdns));
    await _settle();
    expect(c.read(devicesControllerProvider).entries, isEmpty);

    await ctrl.undoLastRemove();
    expect(
      c.read(devicesControllerProvider).entries.map((e) => e.name).toList(),
      ['Patio'],
    );
  });
}
