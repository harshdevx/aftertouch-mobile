import 'package:flutter/widgets.dart';

/// Achromatic ink ramp (saturation 0 — the whole palette). See
/// `specs/UX-DESIGN.md` §2. Never introduce a hue anywhere in the app.
@immutable
class AppInk {
  const AppInk({
    required this.paper,
    required this.paper2,
    required this.ink100,
    required this.ink300,
    required this.ink500,
    required this.ink700,
    required this.ink900,
  });

  /// Page background; text colour on inverted surfaces.
  final Color paper;

  /// Pressed states, subtle fills, slider troughs.
  final Color paper2;

  /// Hairline dividers, disabled borders.
  final Color ink100;

  /// Empty-state borders, tertiary glyphs.
  final Color ink300;

  /// Secondary text, metadata, inactive icons (>= 4.5:1 on [paper]).
  final Color ink500;

  /// Body text on tinted fills.
  final Color ink700;

  /// Primary text, primary icons, emphasis borders, filled buttons.
  final Color ink900;

  static const AppInk light = AppInk(
    paper: Color(0xFFFFFFFF),
    paper2: Color(0xFFF4F4F4),
    ink100: Color(0xFFE4E4E4),
    ink300: Color(0xFFB4B4B4),
    ink500: Color(0xFF767676),
    ink700: Color(0xFF3A3A3A),
    ink900: Color(0xFF000000),
  );

  static const AppInk dark = AppInk(
    paper: Color(0xFF000000),
    paper2: Color(0xFF141414),
    ink100: Color(0xFF262626),
    ink300: Color(0xFF484848),
    ink500: Color(0xFF9A9A9A),
    ink700: Color(0xFFC9C9C9),
    ink900: Color(0xFFFFFFFF),
  );

  /// Ink swapped with paper — for [InvertedSurface] descendants.
  AppInk get inverted => AppInk(
        paper: ink900,
        paper2: ink700,
        ink100: ink300,
        ink300: ink300,
        ink500: ink500,
        ink700: paper2,
        ink900: paper,
      );
}

/// Access the active [AppInk] via `AppInkTheme.of(context)` or the
/// `context.ink` extension.
class AppInkTheme extends InheritedWidget {
  const AppInkTheme({required this.ink, required super.child, super.key});

  final AppInk ink;

  static AppInk of(BuildContext context) {
    final w = context.dependOnInheritedWidgetOfExactType<AppInkTheme>();
    assert(w != null, 'AppInkTheme is missing from the widget tree');
    return w!.ink;
  }

  @override
  bool updateShouldNotify(AppInkTheme oldWidget) => oldWidget.ink != ink;
}

extension AppInkContext on BuildContext {
  AppInk get ink => AppInkTheme.of(this);
}
