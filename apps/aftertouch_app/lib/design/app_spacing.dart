import 'package:flutter/widgets.dart';

/// Spacing scale (dp) from `specs/UX-DESIGN.md` §4.
abstract final class Space {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double gutter = 20;
  static const double xl = 24;
  static const double section = 32;
  static const double xxl = 40;
  static const double xxxl = 48;
}

/// Corner radii. `0` for chips/tabs (hard editorial edge), `full` = stadium.
abstract final class Radii {
  static const Radius none = Radius.zero;
  static const Radius button = Radius.circular(8);
  static const Radius surface = Radius.circular(12);
  static const Radius full = Radius.circular(999);
}

/// Motion durations. Keep functional and short.
abstract final class Motion {
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration base = Duration(milliseconds: 160);
  static const Duration slow = Duration(milliseconds: 200);

  /// One loop of the "playing" equalizer.
  static const Duration equalizerLoop = Duration(milliseconds: 900);
  static const Curve curve = Curves.easeOutCubic;
}

/// Minimum interactive target (dp).
const double kMinTarget = 48;
