import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/app_ink.dart';
import '../../design/app_spacing.dart';
import '../../design/app_typography.dart';
import 'eq_controller.dart';

class EqScreen extends ConsumerWidget {
  const EqScreen({super.key, required this.speakerKey, required this.title});

  final String speakerKey;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ink = context.ink;
    final state = ref.watch(eqControllerProvider(speakerKey));
    final c = ref.read(eqControllerProvider(speakerKey).notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Sound')),
      body: SafeArea(
        child: switch (state) {
          EqState(loading: true) => const Center(child: _Spinner()),
          EqState(unreachable: true) => Center(
              child: Text("Can't reach this speaker",
                  style: AppType.body.copyWith(color: ink.ink500)),
            ),
          _ => ListView(
              padding: const EdgeInsets.fromLTRB(
                  Space.gutter, Space.xl, Space.gutter, Space.xxl),
              children: [
                if (state.volume != null)
                  _Band(
                    label: 'Volume',
                    value: state.volume!.actual,
                    min: 0,
                    max: 100,
                    onChanged: c.setVolume,
                  ),
                if (state.useTone)
                  _Band(
                    label: 'Bass',
                    value: state.tone!.bass.value,
                    min: state.tone!.bass.min,
                    max: state.tone!.bass.max,
                    onChanged: c.setBass,
                  )
                else if (state.hasClassicBass)
                  _Band(
                    label: 'Bass',
                    value: state.bass!.actual,
                    min: state.bassCaps?.min ?? -9,
                    max: state.bassCaps?.max ?? 9,
                    onChanged: c.setBass,
                  ),
                if (state.hasTreble)
                  _Band(
                    label: 'Treble',
                    value: state.tone!.treble.value,
                    min: state.tone!.treble.min,
                    max: state.tone!.treble.max,
                    onChanged: c.setTreble,
                  ),
                if (state.hasBalance)
                  _Band(
                    label: 'Balance',
                    value: state.balance!.actual,
                    min: state.balance!.min,
                    max: state.balance!.max,
                    onChanged: c.setBalance,
                    endLabels: ('L', 'R'),
                  ),
                if (state.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.xxl),
                    child: Text(
                      'This speaker exposes no adjustable sound controls.',
                      style: AppType.body.copyWith(color: ink.ink500),
                    ),
                  ),
              ],
            ),
        },
      ),
    );
  }
}

class _Band extends StatelessWidget {
  const _Band({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.endLabels,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  final (String, String)? endLabels;

  bool get _centerZero => min < 0 && max > 0;

  @override
  Widget build(BuildContext context) {
    final ink = context.ink;
    final display = _centerZero && value > 0 ? '+$value' : '$value';

    return Padding(
      padding: const EdgeInsets.only(bottom: Space.section),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label.toUpperCase(),
                  style: AppType.label.copyWith(color: ink.ink500)),
              Text(display, style: AppType.mono.copyWith(color: ink.ink900)),
            ],
          ),
          const SizedBox(height: Space.xs),
          Slider(
            value: value.toDouble().clamp(min.toDouble(), max.toDouble()),
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: (max - min) > 0 ? (max - min) : null,
            onChanged: (d) => onChanged(d.round()),
          ),
          if (endLabels != null)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(endLabels!.$1,
                    style: AppType.label.copyWith(color: ink.ink300)),
                Text(endLabels!.$2,
                    style: AppType.label.copyWith(color: ink.ink300)),
              ],
            )
          else if (_centerZero)
            Center(
              child: Text('0',
                  style: AppType.label.copyWith(color: ink.ink300)),
            ),
        ],
      ),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
            strokeWidth: 1.5, color: context.ink.ink500),
      );
}
