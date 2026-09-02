import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soundtouch_client/soundtouch_client.dart';

import 'package:aftertouch_app/data/soundtouch_providers.dart';
import 'package:aftertouch_app/data/speaker_hub.dart';
import 'package:aftertouch_app/features/now_playing/now_playing_controller.dart';

class _FakeClient implements SoundTouchClient {
  final events$ = StreamController<SoundTouchEvent>.broadcast();
  final conn$ = StreamController<GabboConnectionState>.broadcast();

  int nowPlayingCalls = 0;
  NowPlaying current = const NowPlaying(deviceId: 'D', source: 'STANDBY');

  @override
  Stream<SoundTouchEvent> get events => events$.stream;
  @override
  Stream<GabboConnectionState> get eventConnectionState => conn$.stream;

  @override
  Future<NowPlaying> getNowPlaying() async {
    nowPlayingCalls++;
    return current;
  }

  @override
  Future<Volume> getVolume() async =>
      const Volume(deviceId: 'D', target: 20, actual: 20, muted: false);

  @override
  Future<DeviceInfo> getInfo() async =>
      const DeviceInfo(deviceId: 'D', name: 'Test', type: 'SoundTouch 20');

  @override
  Future<void> setVolume(int level) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late _FakeClient fake;

  setUp(() {
    fake = _FakeClient();
    container = ProviderContainer(overrides: [
      soundTouchClientProvider('host').overrideWithValue(fake),
    ]);
  });

  tearDown(() {
    container.dispose();
    fake.events$.close();
    fake.conn$.close();
  });

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

  test('starts in connecting, polls a snapshot immediately', () async {
    final snap = container.read(speakerHubProvider('host'));
    expect(snap.connection, LiveConnection.connecting);

    await settle();
    expect(fake.nowPlayingCalls, greaterThanOrEqualTo(1));
    expect(container.read(speakerHubProvider('host')).connection,
        LiveConnection.polling);
  });

  test('socket connect → live + catch-up snapshot; disconnect → polling',
      () async {
    container.read(speakerHubProvider('host'));
    await settle();

    fake.conn$.add(GabboConnectionState.connected);
    await settle();
    expect(container.read(speakerHubProvider('host')).connection,
        LiveConnection.live);

    fake.conn$.add(GabboConnectionState.disconnected);
    await settle();
    expect(container.read(speakerHubProvider('host')).connection,
        LiveConnection.polling);
  });

  test('nowPlayingUpdated event with payload updates the snapshot', () async {
    container.read(speakerHubProvider('host'));
    await settle();

    fake.events$.add(const NowPlayingEvent(
      NowPlaying(deviceId: 'D', source: 'SPOTIFY', track: 'Song'),
    ));
    await settle();

    expect(container.read(speakerHubProvider('host')).nowPlaying?.track, 'Song');
  });

  test('presetsUpdated bumps the rev counter', () async {
    container.read(speakerHubProvider('host'));
    await settle();
    final before = container.read(speakerHubProvider('host')).revPresets;

    fake.events$.add(const PresetsChangedEvent());
    await settle();

    expect(container.read(speakerHubProvider('host')).revPresets, before + 1);
  });

  test('NowPlayingController actions are safe right after a hub tick', () async {
    // Regression: watching the hub marked this notifier "outdated" on every
    // tick; an action calling `ref` in that window asserted. Now it mirrors
    // the hub via ref.listen, so this must simply not throw.
    final notifier =
        container.read(nowPlayingControllerProvider('host').notifier);
    await settle();

    for (var i = 0; i < 5; i++) {
      fake.events$.add(VolumeEvent(
        Volume(deviceId: 'D', target: i, actual: i, muted: false),
      ));
      notifier.setVolume(20 + i); // same window as the dependency change
    }

    await settle();
    // No assertion thrown; the controller still tracks the hub.
    expect(container.read(nowPlayingControllerProvider('host')).volume, isNotNull);
  });
}
