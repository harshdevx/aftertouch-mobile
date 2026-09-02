import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:soundtouch_client/soundtouch_client.dart';

import '../../design/app_ink.dart';
import '../../design/app_spacing.dart';
import '../../design/app_typography.dart';
import '../../design/widgets/greyscale.dart';
import '../../design/widgets/playing_equalizer.dart';
import 'presets_controller.dart';

class PresetsScreen extends ConsumerWidget {
  const PresetsScreen({super.key, required this.speakerKey, required this.title});

  final String speakerKey;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ink = context.ink;
    final state = ref.watch(presetsControllerProvider(speakerKey));
    final c = ref.read(presetsControllerProvider(speakerKey).notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Presets')),
      body: SafeArea(
        child: state.loading
            ? const Center(child: _Spinner())
            : state.unreachable
                ? Center(
                    child: Text("Can't reach this speaker",
                        style: AppType.body.copyWith(color: ink.ink500)),
                  )
                : GridView.count(
                    padding: const EdgeInsets.all(Space.gutter),
                    crossAxisCount: 2,
                    mainAxisSpacing: Space.md,
                    crossAxisSpacing: Space.md,
                    children: [
                      for (var slot = 1; slot <= 6; slot++)
                        _PresetCell(
                          slot: slot,
                          preset: state.bySlot[slot],
                          active: state.activeSlot == slot,
                          onTap: () => _onTap(context, c, state, slot),
                          onLongPress: () =>
                              _onLongPress(context, c, state, slot),
                        ),
                    ],
                  ),
      ),
    );
  }

  Future<void> _onTap(
    BuildContext context,
    PresetsController c,
    PresetsState state,
    int slot,
  ) async {
    if (state.bySlot.containsKey(slot)) {
      await c.recall(slot);
      return;
    }
    // Empty slot.
    if (state.canStoreCurrent) {
      final err = await c.storeCurrent(slot);
      if (err != null && context.mounted) _toast(context, err);
    } else if (context.mounted) {
      _toast(context, 'Play something, then long-press a slot to save it.');
    }
  }

  Future<void> _onLongPress(
    BuildContext context,
    PresetsController c,
    PresetsState state,
    int slot,
  ) async {
    final filled = state.bySlot.containsKey(slot);
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              enabled: state.canStoreCurrent,
              leading: const Icon(Icons.bookmark_add_outlined),
              title: Text(filled
                  ? 'Replace with what\'s playing'
                  : 'Save what\'s playing here'),
              subtitle: state.canStoreCurrent
                  ? null
                  : const Text('Nothing presetable is playing'),
              onTap: () => Navigator.pop(context, 'store'),
            ),
            if (filled)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Remove preset'),
                onTap: () => Navigator.pop(context, 'remove'),
              ),
          ],
        ),
      ),
    );
    if (action == 'store') {
      final err = await c.storeCurrent(slot);
      if (err != null && context.mounted) _toast(context, err);
    } else if (action == 'remove') {
      final err = await c.remove(slot);
      if (err != null && context.mounted) _toast(context, err);
    }
  }

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }
}

class _PresetCell extends StatelessWidget {
  const _PresetCell({
    required this.slot,
    required this.preset,
    required this.active,
    required this.onTap,
    required this.onLongPress,
  });

  final int slot;
  final Preset? preset;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final ink = context.ink;
    final art = preset?.contentItem.containerArt;

    if (preset == null) {
      return _Frame(
        border: Border.all(color: ink.ink300, width: 1.5),
        dashed: true,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, color: ink.ink300),
            const SizedBox(height: Space.xs),
            Text('PRESET $slot',
                style: AppType.label.copyWith(color: ink.ink300)),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: _Frame(
        border: Border.all(
          color: active ? ink.ink900 : ink.ink100,
          width: active ? 2 : 1,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (art != null && art.isNotEmpty)
              Greyscale(
                child: CachedNetworkImage(imageUrl: art, fit: BoxFit.cover),
              )
            else
              ColoredBox(color: ink.paper2),
            // bottom scrim for label legibility (achromatic → allowed)
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.center,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00000000), Color(0xB3000000)],
                ),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: Space.sm, vertical: 2),
                color: ink.ink900,
                child: Text('$slot',
                    style: AppType.label.copyWith(color: ink.paper)),
              ),
            ),
            if (active)
              const Positioned(
                right: Space.sm,
                top: Space.sm,
                child: PlayingEqualizer(size: 12, color: Color(0xFFFFFFFF)),
              ),
            Positioned(
              left: Space.sm,
              right: Space.sm,
              bottom: Space.sm,
              child: Text(
                preset!.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppType.bodyStrong.copyWith(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({required this.child, this.border, this.dashed = false});
  final Widget child;
  final BoxBorder? border;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.all(Radii.surface),
      child: Container(
        decoration: BoxDecoration(
          border: border,
          borderRadius: const BorderRadius.all(Radii.surface),
        ),
        child: child,
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
