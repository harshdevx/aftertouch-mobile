import 'package:flutter/widgets.dart';

/// Forces its child to pure luminance — the monochrome mandate applied to
/// album art (UX spec decision D2). Never invert art between themes.
class Greyscale extends StatelessWidget {
  const Greyscale({super.key, required this.child});

  final Widget child;

  static const ColorFilter _filter = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0, 0, 0, 1, 0, //
  ]);

  @override
  Widget build(BuildContext context) =>
      ColorFiltered(colorFilter: _filter, child: child);
}
