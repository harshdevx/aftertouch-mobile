import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:soundtouch_client/soundtouch_client.dart';

import '../../design/app_ink.dart';
import '../../design/app_spacing.dart';
import '../../design/app_typography.dart';
import '../../design/widgets/greyscale.dart';
import '../../design/widgets/playing_equalizer.dart';
import '../../data/aftertouch_providers.dart';
import '../catalog/catalog_screen.dart';
import '../eq/eq_screen.dart';
import '../library/library_screen.dart';
import '../presets/presets_screen.dart';
import '../recents/recents_screen.dart';
import '../sources/sources_screen.dart';
import 'now_playing_controller.dart';

class NowPlayingScreen extends ConsumerWidget {
  const NowPlayingScreen({
    super.key,
    required this.speakerKey,
    required this.title,
  });

  /// `"host"` or `"host:port"` — the key for [nowPlayingControllerProvider].
  final String speakerKey;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ink = context.ink;
    final state = ref.watch(nowPlayingControllerProvider(speakerKey));
    final controller =
        ref.read(nowPlayingControllerProvider(speakerKey).notifier);
    final np = state.nowPlaying;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text((state.info?.name ?? title).toUpperCase(),
                  overflow: TextOverflow.ellipsis,
                  style: AppType.label.copyWith(color: ink.ink500)),
            ),
            const SizedBox(width: Space.sm),
            _LiveDot(live: state.isLive),
          ],
        ),
        actions: [
          if (!state.unreachable && !(np?.isStandby ?? false))
            IconButton(
              tooltip: 'Sleep',
              icon: const Icon(Icons.power_settings_new),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                await controller.power();
                messenger
                  ..clearSnackBars()
                  ..showSnackBar(
                      const SnackBar(content: Text('Sent to standby')));
              },
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz),
            onSelected: (choice) {
              final route = switch (choice) {
                'sound' => MaterialPageRoute<void>(
                    builder: (_) =>
                        EqScreen(speakerKey: speakerKey, title: title)),
                'presets' => MaterialPageRoute<void>(
                    builder: (_) =>
                        PresetsScreen(speakerKey: speakerKey, title: title)),
                'sources' => MaterialPageRoute<void>(
                    builder: (_) =>
                        SourcesScreen(speakerKey: speakerKey, title: title)),
                'library' => MaterialPageRoute<void>(
                    builder: (_) =>
                        LibraryScreen(speakerKey: speakerKey, title: title)),
                'radio' => MaterialPageRoute<void>(
                    builder: (_) =>
                        CatalogScreen(speakerKey: speakerKey, title: title)),
                _ => MaterialPageRoute<void>(
                    builder: (_) =>
                        RecentsScreen(speakerKey: speakerKey, title: title)),
              };
              Navigator.of(context).push(route);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'sound', child: Text('Sound')),
              const PopupMenuItem(value: 'sources', child: Text('Sources')),
              const PopupMenuItem(
                  value: 'library', child: Text('Library (DLNA)')),
              if (ref.watch(afterTouchClientProvider) != null)
                const PopupMenuItem(
                    value: 'radio', child: Text('Radio (AfterTouch)')),
              const PopupMenuItem(value: 'presets', child: Text('Presets')),
              const PopupMenuItem(value: 'recents', child: Text('Recents')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: state.loading && np == null
            ? const Center(child: _MonoSpinner())
            : state.unreachable && np == null
                ? _Unreachable(onRetry: controller.playPause)
                : np != null && np.isStandby
                    ? _Standby(onWake: controller.power)
                    : _Content(
                        state: state,
                        controller: controller,
                      ),
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.state, required this.controller});

  final NowPlayingState state;
  final NowPlayingController controller;

  @override
  Widget build(BuildContext context) {
    final ink = context.ink;
    final np = state.nowPlaying!;
    final artSide =
        (MediaQuery.sizeOf(context).width - Space.gutter * 2).clamp(0.0, 360.0);

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
                Space.gutter, Space.xl, Space.gutter, Space.lg),
            children: [
              Center(
                child: _Art(
                  url: np.hasArt ? np.artUrl : null,
                  side: artSide,
                  label: np.source,
                  playing: np.playStatus.isPlaying,
                ),
              ),
              const SizedBox(height: Space.xl),
              Text(
                np.primaryLine,
                style: AppType.display.copyWith(color: ink.ink900),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (np.artist != null) ...[
                const SizedBox(height: Space.xs),
                Text(np.artist!,
                    style: AppType.body.copyWith(color: ink.ink700)),
              ],
              if (np.album != null) ...[
                const SizedBox(height: Space.xxs),
                Text(np.album!.toUpperCase(),
                    style: AppType.label.copyWith(color: ink.ink500)),
              ],
              const SizedBox(height: Space.xl),
              _Progress(np: np),
              const SizedBox(height: Space.xl),
              _TransportRow(state: state, controller: controller),
              const SizedBox(height: Space.lg),
              _SecondaryRow(np: np, controller: controller),
            ],
          ),
        ),
        _VolumeBar(state: state, controller: controller),
      ],
    );
  }
}

class _Art extends StatelessWidget {
  const _Art({
    required this.url,
    required this.side,
    required this.label,
    required this.playing,
  });

  final String? url;
  final double side;
  final String label;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    final ink = context.ink;
    return Container(
      width: side,
      height: side,
      decoration: BoxDecoration(
        border: Border.all(color: ink.ink100),
        color: ink.paper2,
      ),
      clipBehavior: Clip.antiAlias,
      child: url == null
          ? Center(
              child: Text(
                label.toUpperCase(),
                style: AppType.label.copyWith(color: ink.ink300),
              ),
            )
          : Greyscale(
              child: CachedNetworkImage(
                imageUrl: url!,
                fit: BoxFit.cover,
                fadeInDuration: Motion.fast,
                errorWidget: (_, _, _) => Center(
                  child: Icon(Icons.music_note, color: ink.ink300),
                ),
              ),
            ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.np});
  final NowPlaying np;

  @override
  Widget build(BuildContext context) {
    final ink = context.ink;
    final pos = np.position;
    final dur = np.duration;

    if (dur == null || dur.inSeconds <= 0) {
      // Live stream — no scrub, just a state marker.
      return Row(
        children: [
          if (np.playStatus.isPlaying)
            const PlayingEqualizer(size: 12)
          else
            Icon(Icons.circle, size: 8, color: ink.ink300),
          const SizedBox(width: Space.sm),
          Text('LIVE', style: AppType.label.copyWith(color: ink.ink500)),
        ],
      );
    }

    final value =
        pos == null ? 0.0 : (pos.inSeconds / dur.inSeconds).clamp(0.0, 1.0);
    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Slider(value: value, onChanged: null),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_fmt(pos ?? Duration.zero),
                style: AppType.mono.copyWith(color: ink.ink500)),
            Text(_fmt(dur), style: AppType.mono.copyWith(color: ink.ink500)),
          ],
        ),
      ],
    );
  }

  static String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0
        ? '$h:${m.toString().padLeft(2, '0')}:$s'
        : '$m:$s';
  }
}

class _TransportRow extends StatelessWidget {
  const _TransportRow({required this.state, required this.controller});
  final NowPlayingState state;
  final NowPlayingController controller;

  @override
  Widget build(BuildContext context) {
    final ink = context.ink;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          iconSize: 34,
          onPressed: controller.previous,
          icon: Icon(Icons.skip_previous, color: ink.ink900),
        ),
        const SizedBox(width: Space.xl),
        _PlayPauseButton(playing: state.isPlaying, onTap: controller.playPause),
        const SizedBox(width: Space.xl),
        IconButton(
          iconSize: 34,
          onPressed: controller.next,
          icon: Icon(Icons.skip_next, color: ink.ink900),
        ),
      ],
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  const _PlayPauseButton({required this.playing, required this.onTap});
  final bool playing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = context.ink;
    return Semantics(
      button: true,
      label: playing ? 'Pause' : 'Play',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: playing ? ink.ink900 : null,
            border: Border.all(color: ink.ink900, width: 2),
          ),
          child: Icon(
            playing ? Icons.pause : Icons.play_arrow,
            size: 34,
            color: playing ? ink.paper : ink.ink900,
          ),
        ),
      ),
    );
  }
}

class _SecondaryRow extends StatelessWidget {
  const _SecondaryRow({required this.np, required this.controller});
  final NowPlaying np;
  final NowPlayingController controller;

  @override
  Widget build(BuildContext context) {
    final ink = context.ink;
    final repeatLabel = switch (np.repeat) {
      RepeatSetting.one => Icons.repeat_one,
      _ => Icons.repeat,
    };
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _Toggle(
          icon: Icons.shuffle,
          active: np.shuffle == ShuffleMode.on,
          onTap: controller.toggleShuffle,
        ),
        _Toggle(
          icon: repeatLabel,
          active: np.repeat == RepeatSetting.all || np.repeat == RepeatSetting.one,
          onTap: controller.cycleRepeat,
        ),
        if (np.favoriteEnabled)
          IconButton(
            onPressed: () {},
            icon: Icon(Icons.favorite_border, color: ink.ink500),
          ),
      ],
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.icon, required this.active, required this.onTap});
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = context.ink;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? ink.ink900 : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 20, color: active ? ink.paper : ink.ink500),
      ),
    );
  }
}

class _VolumeBar extends StatelessWidget {
  const _VolumeBar({required this.state, required this.controller});
  final NowPlayingState state;
  final NowPlayingController controller;

  @override
  Widget build(BuildContext context) {
    final ink = context.ink;
    final v = state.volume;
    final level = v?.actual ?? 0;
    final muted = v?.muted ?? false;

    return Container(
      padding: const EdgeInsets.fromLTRB(
          Space.lg, Space.sm, Space.gutter, Space.sm),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: ink.ink100)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onLongPress: controller.toggleMute,
            child: Icon(
              muted ? Icons.volume_off : Icons.volume_up,
              color: ink.ink700,
            ),
          ),
          Expanded(
            child: Slider(
              value: level.toDouble().clamp(0, 100),
              max: 100,
              onChanged: (d) => controller.setVolume(d.round()),
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(
              muted ? '—' : '$level',
              textAlign: TextAlign.end,
              style: AppType.mono.copyWith(color: ink.ink500),
            ),
          ),
        ],
      ),
    );
  }
}

class _Standby extends StatelessWidget {
  const _Standby({required this.onWake});
  final Future<void> Function() onWake;

  @override
  Widget build(BuildContext context) {
    final ink = context.ink;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.power_settings_new, size: 56, color: ink.ink300),
          const SizedBox(height: Space.lg),
          Text('Standby', style: AppType.title.copyWith(color: ink.ink900)),
          const SizedBox(height: Space.lg),
          OutlinedButton(onPressed: onWake, child: const Text('Wake')),
        ],
      ),
    );
  }
}

class _Unreachable extends StatelessWidget {
  const _Unreachable({required this.onRetry});
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final ink = context.ink;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off, size: 48, color: ink.ink300),
            const SizedBox(height: Space.lg),
            Text("Can't reach this speaker",
                style: AppType.title.copyWith(color: ink.ink900)),
            const SizedBox(height: Space.sm),
            Text(
              'Check it is powered on and on the same Wi-Fi.',
              textAlign: TextAlign.center,
              style: AppType.body.copyWith(color: ink.ink500),
            ),
          ],
        ),
      ),
    );
  }
}

/// Filled = `gabbo` WebSocket live; hollow = HTTP polling fallback.
class _LiveDot extends StatelessWidget {
  const _LiveDot({required this.live});
  final bool live;

  @override
  Widget build(BuildContext context) {
    final ink = context.ink;
    return Tooltip(
      message: live ? 'Live updates' : 'Polling',
      child: Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: live ? ink.ink900 : null,
          border: live ? null : Border.all(color: ink.ink300, width: 1.5),
        ),
      ),
    );
  }
}

class _MonoSpinner extends StatelessWidget {
  const _MonoSpinner();

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 1.5,
          color: context.ink.ink500,
        ),
      );
}
