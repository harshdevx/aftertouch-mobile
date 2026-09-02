import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/app_ink.dart';
import '../../design/app_spacing.dart';
import '../../design/app_typography.dart';
import 'presets_controller.dart';

/// Ask for a slot (1–6), then store whatever is playing now on [speakerKey]
/// into it. Returns a short message to surface (success or failure), or null
/// if the user cancelled.
Future<String?> pickSlotAndSaveCurrent(
  BuildContext context,
  WidgetRef ref,
  String speakerKey,
) async {
  final ink = context.ink;
  final existing = ref.read(presetsControllerProvider(speakerKey)).bySlot;

  final slot = await showModalBottomSheet<int>(
    context: context,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(Space.gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SAVE TO PRESET',
                style: AppType.label.copyWith(color: ink.ink500)),
            const SizedBox(height: Space.md),
            for (var s = 1; s <= 6; s++)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Text('$s',
                    style: AppType.bodyStrong.copyWith(color: ink.ink900)),
                title: Text(
                  existing[s]?.name ?? 'Empty',
                  style: AppType.body.copyWith(
                    color: existing[s] == null ? ink.ink500 : ink.ink900,
                  ),
                ),
                trailing: existing.containsKey(s)
                    ? Text('replace',
                        style: AppType.label.copyWith(color: ink.ink300))
                    : null,
                onTap: () => Navigator.pop(context, s),
              ),
          ],
        ),
      ),
    ),
  );

  if (slot == null) return null;
  final err = await ref
      .read(presetsControllerProvider(speakerKey).notifier)
      .storeCurrent(slot);
  return err ?? 'Saved to preset $slot';
}
