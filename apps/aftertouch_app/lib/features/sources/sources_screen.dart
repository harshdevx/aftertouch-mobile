import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/app_ink.dart';
import '../../design/app_spacing.dart';
import '../../design/app_typography.dart';
import 'sources_controller.dart';

class SourcesScreen extends ConsumerWidget {
  const SourcesScreen({super.key, required this.speakerKey, required this.title});

  final String speakerKey;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ink = context.ink;
    final state = ref.watch(sourcesControllerProvider(speakerKey));
    final c = ref.read(sourcesControllerProvider(speakerKey).notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Sources')),
      body: SafeArea(
        child: state.loading
            ? const Center(child: _Spinner())
            : state.unreachable
                ? Center(
                    child: Text("Can't reach this speaker",
                        style: AppType.body.copyWith(color: ink.ink500)),
                  )
                : ListView.separated(
                    itemCount: state.rows.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: ink.ink100, indent: Space.gutter),
                    itemBuilder: (context, i) {
                      final row = state.rows[i];
                      return _SourceTile(
                        row: row,
                        onTap: row.available && !row.active
                            ? () async {
                                final err = await c.select(row.item);
                                if (err != null && context.mounted) {
                                  ScaffoldMessenger.of(context)
                                    ..clearSnackBars()
                                    ..showSnackBar(
                                        SnackBar(content: Text(err)));
                                } else if (context.mounted) {
                                  Navigator.of(context).pop();
                                }
                              }
                            : null,
                      );
                    },
                  ),
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({required this.row, required this.onTap});

  final SourceRow row;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ink = context.ink;
    final dim = !row.available && !row.active;

    return InkWell(
      onTap: onTap,
      child: Opacity(
        opacity: dim ? 0.4 : 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: Space.gutter, vertical: Space.lg),
          child: Row(
            children: [
              // 3px active bar
              Container(
                width: 3,
                height: 28,
                color: row.active ? ink.ink900 : Colors.transparent,
              ),
              const SizedBox(width: Space.lg),
              Icon(_iconFor(row.item.source), size: 20, color: ink.ink700),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.item.displayName,
                      style: (row.active
                              ? AppType.bodyStrong
                              : AppType.body)
                          .copyWith(color: ink.ink900),
                    ),
                    if (dim && row.reason != null && row.reason!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          row.reason!,
                          style: AppType.caption.copyWith(color: ink.ink500),
                        ),
                      )
                    else if (dim)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text('Unavailable',
                            style:
                                AppType.caption.copyWith(color: ink.ink500)),
                      ),
                  ],
                ),
              ),
              if (row.active) Icon(Icons.check, size: 18, color: ink.ink900),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconFor(String source) => switch (source.toUpperCase()) {
        'BLUETOOTH' => Icons.bluetooth,
        'AUX' || 'AUX_INPUT' => Icons.cable,
        'SPOTIFY' => Icons.music_note,
        'TUNEIN' || 'LOCAL_INTERNET_RADIO' => Icons.radio,
        'STORED_MUSIC' || 'LOCAL_MUSIC' => Icons.library_music,
        'AIRPLAY' => Icons.airplay,
        'AMAZON' => Icons.music_note,
        _ => Icons.speaker,
      };
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
