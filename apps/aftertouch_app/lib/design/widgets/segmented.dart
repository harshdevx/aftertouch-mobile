import 'package:flutter/widgets.dart';

import '../app_ink.dart';
import '../app_spacing.dart';
import '../app_typography.dart';

/// Monochrome segmented control: outline segments, active one filled ink.
class Segmented<T> extends StatelessWidget {
  const Segmented({
    super.key,
    required this.value,
    required this.segments,
    required this.onChanged,
  });

  final T value;
  final List<(T, String)> segments;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final ink = context.ink;
    return Row(
      children: [
        for (final (v, label) in segments)
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(v),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: Space.md),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: v == value ? ink.ink900 : null,
                  border: Border.all(color: ink.ink900),
                ),
                child: Text(
                  label.toUpperCase(),
                  style: AppType.label
                      .copyWith(color: v == value ? ink.paper : ink.ink900),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
