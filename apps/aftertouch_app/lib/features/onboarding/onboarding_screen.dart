import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/settings_providers.dart';
import '../../design/app_ink.dart';
import '../../design/app_spacing.dart';
import '../../design/app_typography.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _page = PageController();
  int _index = 0;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  void _next() {
    if (_index == 0) {
      _page.nextPage(
        duration: Motion.slow,
        curve: Motion.curve,
      );
    } else {
      ref.read(onboardedProvider.notifier).complete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ink = context.ink;
    final networkNote = Platform.isIOS
        ? 'AfterTouch needs Local Network access and the same Wi-Fi as your '
            'speakers. You\'ll see a permission prompt next.'
        : 'Keep this device on the same Wi-Fi as your speakers. Some routers '
            'block discovery between devices — you can always add a speaker by '
            'its IP address.';

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _page,
                onPageChanged: (i) => setState(() => _index = i),
                children: [
                  _Card(
                    kicker: 'AFTERTOUCH',
                    title: 'Your SoundTouch speakers, without the cloud.',
                    body: 'Control playback, volume, presets, sources and '
                        'multiroom — straight over your local network.',
                  ),
                  _Card(
                    kicker: 'FINDING SPEAKERS',
                    title: 'One quick thing.',
                    body: networkNote,
                  ),
                ],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < 2; i++)
                  Container(
                    margin: const EdgeInsets.all(4),
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == _index ? ink.ink900 : null,
                      border: i == _index
                          ? null
                          : Border.all(color: ink.ink300, width: 1.5),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(Space.gutter),
              child: Column(
                children: [
                  FilledButton(
                    onPressed: _next,
                    child: Text(_index == 0 ? 'Continue' : 'Get started'),
                  ),
                  if (_index == 0)
                    TextButton(
                      onPressed: () =>
                          ref.read(onboardedProvider.notifier).complete(),
                      child: const Text('Skip'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.kicker, required this.title, required this.body});

  final String kicker;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final ink = context.ink;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          Space.section, Space.xxxl, Space.section, Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(kicker,
              style: AppType.label.copyWith(color: ink.ink500, letterSpacing: 1)),
          const SizedBox(height: Space.lg),
          Text(title, style: AppType.display.copyWith(color: ink.ink900)),
          const SizedBox(height: Space.lg),
          Text(body, style: AppType.body.copyWith(color: ink.ink700)),
        ],
      ),
    );
  }
}
