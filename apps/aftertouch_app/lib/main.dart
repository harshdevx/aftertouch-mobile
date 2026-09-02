import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/settings_providers.dart';
import 'design/app_ink.dart';
import 'design/app_theme.dart';
import 'features/devices/devices_screen.dart';
import 'features/onboarding/onboarding_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      child: const AfterTouchApp(),
    ),
  );
}

class AfterTouchApp extends ConsumerWidget {
  const AfterTouchApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final onboarded = ref.watch(onboardedProvider);

    return MaterialApp(
      title: 'AfterTouch',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: themeMode,
      builder: (context, child) {
        final ink = Theme.of(context).brightness == Brightness.dark
            ? AppInk.dark
            : AppInk.light;
        return AppInkTheme(ink: ink, child: child ?? const SizedBox.shrink());
      },
      home: onboarded ? const DevicesScreen() : const OnboardingScreen(),
    );
  }
}
