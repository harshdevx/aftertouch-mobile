import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:soundtouch_client/soundtouch_client.dart';

import '../../data/soundtouch_providers.dart';
import '../../design/app_ink.dart';
import '../../design/app_spacing.dart';
import '../../design/app_typography.dart';
import '../../design/widgets/greyscale.dart';

final _recentsProvider =
    FutureProvider.family.autoDispose<List<RecentItem>, String>((ref, key) {
  return ref.watch(soundTouchClientProvider(key)).getRecents();
});

class RecentsScreen extends ConsumerWidget {
  const RecentsScreen({super.key, required this.speakerKey, required this.title});

  final String speakerKey;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ink = context.ink;
    final async = ref.watch(_recentsProvider(speakerKey));

    return Scaffold(
      appBar: AppBar(title: const Text('Recents')),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: _Spinner()),
          error: (_, _) => Center(
            child: Text("Can't reach this speaker",
                style: AppType.body.copyWith(color: ink.ink500)),
          ),
          data: (items) => items.isEmpty
              ? Center(
                  child: Text('Nothing played recently',
                      style: AppType.body.copyWith(color: ink.ink500)),
                )
              : ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, _) => Divider(
                      height: 1, color: ink.ink100, indent: 72),
                  itemBuilder: (context, i) => _RecentRow(
                    item: items[i],
                    onTap: () async {
                      final client =
                          ref.read(soundTouchClientProvider(speakerKey));
                      try {
                        await client.select(items[i].contentItem);
                        if (context.mounted) Navigator.of(context).pop();
                      } on SoundTouchException {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Couldn't start that.")),
                          );
                        }
                      }
                    },
                  ),
                ),
        ),
      ),
    );
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.item, required this.onTap});
  final RecentItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = context.ink;
    final art = item.contentItem.containerArt;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: Space.gutter, vertical: Space.md),
        child: Row(
          children: [
            SizedBox(
              width: 40,
              height: 40,
              child: art != null && art.isNotEmpty
                  ? Greyscale(
                      child: CachedNetworkImage(
                          imageUrl: art, fit: BoxFit.cover))
                  : ColoredBox(color: ink.paper2),
            ),
            const SizedBox(width: Space.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.body.copyWith(color: ink.ink900)),
                  const SizedBox(height: 2),
                  Text(item.contentItem.source.toUpperCase(),
                      style: AppType.label.copyWith(color: ink.ink500)),
                ],
              ),
            ),
          ],
        ),
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
