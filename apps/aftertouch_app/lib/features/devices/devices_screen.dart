import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/app_ink.dart';
import '../../design/app_spacing.dart';
import '../../design/app_typography.dart';
import '../../design/widgets/playing_equalizer.dart';
import '../../design/widgets/status_dot.dart';
import '../../discovery/devices_controller.dart';
import '../now_playing/now_playing_screen.dart';
import '../settings/settings_screen.dart';

class DevicesScreen extends ConsumerWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ink = context.ink;
    final state = ref.watch(devicesControllerProvider);
    final controller = ref.read(devicesControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Speakers'),
        actions: [
          IconButton(
            tooltip: 'Add by IP',
            onPressed: () => _showAddByIp(context, controller),
            icon: const Icon(Icons.add),
          ),
          IconButton(
            tooltip: 'Scan again',
            onPressed: controller.rescan,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
            icon: const Icon(Icons.settings_outlined),
          ),
          const SizedBox(width: Space.sm),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: controller.rescan,
        color: ink.ink900,
        backgroundColor: ink.paper,
        child: state.isEmpty
            ? _Empty(scanning: state.scanning)
            : ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: Space.sm),
                itemCount: state.entries.length + (state.scanning ? 1 : 0),
                separatorBuilder: (_, _) => Divider(
                  height: 1,
                  color: ink.ink100,
                  indent: Space.gutter + 32,
                ),
                itemBuilder: (context, i) {
                  if (i == state.entries.length) {
                    return const _ScanningRow();
                  }
                  final entry = state.entries[i];
                  return Dismissible(
                    // Host-based key stays stable as the row enriches with
                    // its MAC / now-playing info.
                    key: ValueKey('row:${entry.speakerKey}'),
                    direction: DismissDirection.endToStart,
                    background: ColoredBox(
                      color: ink.ink900,
                      child: Padding(
                        padding:
                            const EdgeInsets.only(right: Space.gutter),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'REMOVE',
                            style:
                                AppType.label.copyWith(color: ink.paper),
                          ),
                        ),
                      ),
                    ),
                    onDismissed: (_) {
                      controller.remove(entry);
                      ScaffoldMessenger.of(context)
                        ..clearSnackBars()
                        ..showSnackBar(SnackBar(
                          content: Text('Removed ${entry.name}'),
                          action: SnackBarAction(
                            label: 'Undo',
                            onPressed: controller.undoLastRemove,
                          ),
                        ));
                    },
                    child: _SpeakerRow(entry: entry),
                  );
                },
              ),
      ),
    );
  }

  Future<void> _showAddByIp(
    BuildContext context,
    DevicesController controller,
  ) async {
    final ctrl = TextEditingController();
    final host = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add speaker by IP'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(hintText: '192.168.1.42'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (host != null && host.trim().isNotEmpty) {
      await controller.addManual(host);
    }
  }
}

class _SpeakerRow extends StatelessWidget {
  const _SpeakerRow({required this.entry});

  final SpeakerEntry entry;

  @override
  Widget build(BuildContext context) {
    final ink = context.ink;
    final offline = !entry.reachable;

    return Opacity(
      opacity: offline ? 0.4 : 1,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => NowPlayingScreen(
              speakerKey: entry.speakerKey,
              title: entry.name,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.gutter,
            vertical: Space.lg,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 16,
                child: entry.isPlaying
                    ? const PlayingEqualizer(size: 14)
                    : Align(
                        alignment: Alignment.centerLeft,
                        child: StatusDot(online: entry.reachable),
                      ),
              ),
              const SizedBox(width: Space.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.name,
                      style: AppType.bodyStrong.copyWith(color: ink.ink900),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            entry.secondaryLine.toUpperCase(),
                            style: AppType.label.copyWith(color: ink.ink500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '  ·  ${entry.host}',
                          style: AppType.mono.copyWith(color: ink.ink300),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: ink.ink300),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanningRow extends StatelessWidget {
  const _ScanningRow();

  @override
  Widget build(BuildContext context) {
    final ink = context.ink;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.gutter,
        vertical: Space.lg,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 1.5, color: ink.ink500),
          ),
          const SizedBox(width: Space.lg + 2),
          Text(
            'SCANNING…',
            style: AppType.label.copyWith(color: ink.ink500),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.scanning});

  final bool scanning;

  @override
  Widget build(BuildContext context) {
    final ink = context.ink;
    return ListView(
      // ListView so RefreshIndicator still works when empty.
      padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
      children: [
        const SizedBox(height: 96),
        Center(
          child: Icon(Icons.speaker_outlined, size: 56, color: ink.ink300),
        ),
        const SizedBox(height: Space.xl),
        Text(
          scanning ? 'Looking for speakers…' : 'No speakers on this Wi-Fi yet',
          textAlign: TextAlign.center,
          style: AppType.title.copyWith(color: ink.ink900),
        ),
        const SizedBox(height: Space.sm),
        Text(
          'Make sure this device is on the same network as your speakers. '
          'Some routers block discovery between wired and wireless. '
          'You can also add a speaker by its IP address.',
          textAlign: TextAlign.center,
          style: AppType.body.copyWith(color: ink.ink500),
        ),
      ],
    );
  }
}
