import 'package:flutter/widgets.dart';

/// Type scale from `specs/UX-DESIGN.md` §3.
///
/// Families are placeholders until the real faces are bundled:
///   - UI: Inter  → falls back to the platform sans
///   - numeric: IBM Plex Mono → falls back to the platform mono
/// Colour is applied by call sites from the ink ramp, not baked in here.
abstract final class AppType {
  static const String _ui = 'Inter';
  static const String _mono = 'IBMPlexMono';

  static const List<String> _uiFallback = <String>[
    'SF Pro Text',
    'Roboto',
    'sans-serif',
  ];
  static const List<String> _monoFallback = <String>[
    'SF Mono',
    'Roboto Mono',
    'monospace',
  ];

  static const TextStyle display = TextStyle(
    fontFamily: _ui,
    fontFamilyFallback: _uiFallback,
    fontSize: 30,
    height: 36 / 30,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
  );

  static const TextStyle title = TextStyle(
    fontFamily: _ui,
    fontFamilyFallback: _uiFallback,
    fontSize: 20,
    height: 26 / 20,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle body = TextStyle(
    fontFamily: _ui,
    fontFamilyFallback: _uiFallback,
    fontSize: 16,
    height: 22 / 16,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle bodyStrong = TextStyle(
    fontFamily: _ui,
    fontFamilyFallback: _uiFallback,
    fontSize: 16,
    height: 22 / 16,
    fontWeight: FontWeight.w600,
  );

  /// Section headers, status words, metadata. Callers uppercase the text.
  static const TextStyle label = TextStyle(
    fontFamily: _ui,
    fontFamilyFallback: _uiFallback,
    fontSize: 13,
    height: 16 / 13,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.3,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: _ui,
    fontFamilyFallback: _uiFallback,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w400,
  );

  /// Times, percentages, counts, IP addresses — tabular figures.
  static const TextStyle mono = TextStyle(
    fontFamily: _mono,
    fontFamilyFallback: _monoFallback,
    fontSize: 13,
    height: 16 / 13,
    fontWeight: FontWeight.w400,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
  );
}
