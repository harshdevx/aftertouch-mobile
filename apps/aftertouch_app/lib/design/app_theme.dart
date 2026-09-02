import 'package:flutter/material.dart';

import 'app_ink.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

/// Builds a strictly monochrome [ThemeData]. No `ColorScheme.fromSeed`,
/// no Material You dynamic colour — every slot is filled from [AppInk].
ThemeData buildAppTheme(Brightness brightness) {
  final ink = brightness == Brightness.dark ? AppInk.dark : AppInk.light;

  final scheme = ColorScheme(
    brightness: brightness,
    primary: ink.ink900,
    onPrimary: ink.paper,
    secondary: ink.ink900,
    onSecondary: ink.paper,
    error: ink.ink900,
    onError: ink.paper,
    surface: ink.paper,
    onSurface: ink.ink900,
    surfaceContainerHighest: ink.paper2,
    outline: ink.ink300,
    outlineVariant: ink.ink100,
  );

  final text = TextTheme(
    displayMedium: AppType.display.copyWith(color: ink.ink900),
    titleLarge: AppType.title.copyWith(color: ink.ink900),
    bodyLarge: AppType.body.copyWith(color: ink.ink900),
    bodyMedium: AppType.body.copyWith(color: ink.ink700),
    labelLarge: AppType.label.copyWith(color: ink.ink500),
    bodySmall: AppType.caption.copyWith(color: ink.ink500),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: ink.paper,
    canvasColor: ink.paper,
    textTheme: text,
    dividerColor: ink.ink100,
    // No coloured ripple — a quiet monochrome highlight instead.
    splashColor: ink.paper2,
    highlightColor: ink.paper2,
    splashFactory: InkRipple.splashFactory,
    iconTheme: IconThemeData(color: ink.ink900),
    appBarTheme: AppBarTheme(
      backgroundColor: ink.paper,
      foregroundColor: ink.ink900,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: AppType.title.copyWith(color: ink.ink900),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: ink.ink900,
        foregroundColor: ink.paper,
        disabledBackgroundColor: ink.ink900.withValues(alpha: 0.32),
        minimumSize: const Size.fromHeight(kMinTarget),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radii.button),
        ),
        textStyle: AppType.bodyStrong.copyWith(fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ink.ink900,
        side: BorderSide(color: ink.ink900, width: 1.5),
        minimumSize: const Size.fromHeight(kMinTarget),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radii.button),
        ),
        textStyle: AppType.bodyStrong.copyWith(fontSize: 15),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: ink.ink700),
    ),
    sliderTheme: SliderThemeData(
      trackHeight: 2,
      activeTrackColor: ink.ink900,
      inactiveTrackColor: ink.paper2,
      thumbColor: ink.ink900,
      overlayColor: ink.ink900.withValues(alpha: 0.08),
      valueIndicatorColor: ink.ink900,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: ink.ink900,
      textColor: ink.ink900,
      minVerticalPadding: Space.md,
    ),
    dividerTheme: DividerThemeData(color: ink.ink100, thickness: 1, space: 1),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: ink.ink900,
      linearTrackColor: ink.paper2,
      circularTrackColor: ink.paper2,
    ),
  );
}
