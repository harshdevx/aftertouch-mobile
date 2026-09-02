import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soundtouch_client/soundtouch_client.dart';

import 'package:aftertouch_app/data/settings_providers.dart';
import 'package:aftertouch_app/discovery/devices_controller.dart';
import 'package:aftertouch_app/main.dart';

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'onboarded_v1': true});
    prefs = await SharedPreferences.getInstance();
  });

  List<Override> baseOverrides(ManualDiscovery manual) => [
        sharedPrefsProvider.overrideWithValue(prefs),
        speakerDiscoveryProvider.overrideWithValue(manual),
      ];

  testWidgets('boots the monochrome shell and shows the empty state',
      (tester) async {
    final manual = ManualDiscovery();

    await tester.pumpWidget(
      ProviderScope(
        overrides: baseOverrides(manual),
        child: const AfterTouchApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Speakers'), findsOneWidget);
    expect(find.textContaining('speakers'), findsWidgets);
  });

  testWidgets('renders a discovered speaker row', (tester) async {
    final manual = ManualDiscovery();

    await tester.pumpWidget(
      ProviderScope(
        overrides: baseOverrides(manual),
        child: const AfterTouchApp(),
      ),
    );
    await tester.pump();

    manual.add(const DiscoveredSpeaker(
      host: '192.0.2.50',
      name: 'Kitchen',
      source: DiscoverySource.mdns,
    ));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Kitchen'), findsOneWidget);
    expect(find.textContaining(RegExp('OFFLINE|CHECKING')), findsWidgets);
  });

  testWidgets('shows onboarding when not yet onboarded', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final freshPrefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(freshPrefs),
          speakerDiscoveryProvider.overrideWithValue(ManualDiscovery()),
        ],
        child: const AfterTouchApp(),
      ),
    );
    await tester.pump();

    expect(find.text('AFTERTOUCH'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });
}
