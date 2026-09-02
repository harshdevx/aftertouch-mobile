import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../app_ink.dart';
import '../app_spacing.dart';

/// The signature "this is playing" cue — the monochrome stand-in for the
/// colour that would normally signal a live element (`specs/UX-DESIGN.md` §7).
///
/// Four ink bars pulsing on staggered sine timers. When the platform requests
/// reduced motion, the bars freeze at fixed varied heights so the state is
/// still visually distinct from "paused" (which renders nothing).
class PlayingEqualizer extends StatefulWidget {
  const PlayingEqualizer({
    super.key,
    this.size = 14,
    this.barCount = 4,
    this.color,
  });

  final double size;
  final int barCount;
  final Color? color;

  @override
  State<PlayingEqualizer> createState() => _PlayingEqualizerState();
}

class _PlayingEqualizerState extends State<PlayingEqualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Motion.equalizerLoop,
  );

  static const List<double> _phase = <double>[0.0, 0.55, 0.2, 0.8];
  static const List<double> _frozen = <double>[0.45, 0.9, 0.35, 0.7];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? context.ink.ink900;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final barWidth = (widget.size / (widget.barCount * 2 - 1)).clamp(1.5, 3.0);

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(widget.barCount, (i) {
              final double frac;
              if (reduceMotion) {
                frac = _frozen[i % _frozen.length];
              } else {
                final t = (_c.value + _phase[i % _phase.length]) % 1.0;
                frac = 0.25 + 0.75 * (0.5 - 0.5 * math.cos(t * 2 * math.pi));
              }
              return Container(
                width: barWidth,
                height: widget.size * frac,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(barWidth / 2),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
