import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kThemePref = 'theme_mode';
const _kOnboardedPref = 'onboarded_v1';

/// The already-loaded [SharedPreferences]. Overridden in `main()` after an
/// `await SharedPreferences.getInstance()`, so everything downstream is
/// synchronous and there is no first-frame flash.
final sharedPrefsProvider = Provider<SharedPreferences>(
  (_) => throw StateError('sharedPrefsProvider not overridden'),
);

/// App theme choice — System / Light / Dark. All three are monochrome; this
/// only flips ink and paper.
final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    final raw = ref.read(sharedPrefsProvider).getString(_kThemePref);
    return switch (raw) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    await ref.read(sharedPrefsProvider).setString(_kThemePref, mode.name);
  }
}

/// Whether the first-run onboarding has been completed.
final onboardedProvider =
    NotifierProvider<OnboardedNotifier, bool>(OnboardedNotifier.new);

class OnboardedNotifier extends Notifier<bool> {
  @override
  bool build() =>
      ref.read(sharedPrefsProvider).getBool(_kOnboardedPref) ?? false;

  Future<void> complete() async {
    state = true;
    await ref.read(sharedPrefsProvider).setBool(_kOnboardedPref, true);
  }
}
