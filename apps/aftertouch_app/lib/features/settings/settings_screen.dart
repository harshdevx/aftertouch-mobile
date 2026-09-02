import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:soundtouch_client/soundtouch_client.dart';

import '../../app_info.dart';
import '../../data/aftertouch_providers.dart';
import '../../data/settings_providers.dart';
import '../../design/app_ink.dart';
import '../../design/app_spacing.dart';
import '../../design/app_typography.dart';
import '../../design/widgets/segmented.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _url;
  String? _status;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: ref.read(afterTouchBaseUrlProvider) ?? '');
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _testAndSave() async {
    setState(() {
      _checking = true;
      _status = null;
    });
    final raw = _url.text.trim();
    await ref.read(afterTouchBaseUrlProvider.notifier).set(raw);

    if (raw.isEmpty) {
      setState(() {
        _checking = false;
        _status = 'Cleared. Catalog features are hidden.';
      });
      return;
    }

    final client = AfterTouchClient(baseUrl: raw);
    try {
      final v = await client.version();
      setState(() => _status = 'Connected — AfterTouch $v');
    } on AfterTouchException catch (e) {
      setState(() => _status = "Saved, but couldn't reach it: ${e.message}");
    } finally {
      client.close();
      setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ink = context.ink;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Space.gutter),
          children: [
            Text('AFTERTOUCH SERVER',
                style: AppType.label.copyWith(color: ink.ink500)),
            const SizedBox(height: Space.sm),
            Text(
              'Optional. Set this to browse TuneIn and RadioBrowser through a '
              'running AfterTouch instance (soundtouch-service). Playback '
              'control works without it.',
              style: AppType.body.copyWith(color: ink.ink700),
            ),
            const SizedBox(height: Space.lg),
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                hintText: 'http://soundtouch.local:8000',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: Space.md),
            FilledButton(
              onPressed: _checking ? null : _testAndSave,
              child: Text(_checking ? 'Checking…' : 'Save & test'),
            ),
            if (_status != null) ...[
              const SizedBox(height: Space.md),
              Text(_status!,
                  style: AppType.caption.copyWith(color: ink.ink500)),
            ],
            const SizedBox(height: Space.section),
            Text('APPEARANCE',
                style: AppType.label.copyWith(color: ink.ink500)),
            const SizedBox(height: Space.md),
            Consumer(
              builder: (context, ref, _) {
                final mode = ref.watch(themeModeProvider);
                return Segmented<ThemeMode>(
                  value: mode,
                  segments: const [
                    (ThemeMode.system, 'System'),
                    (ThemeMode.light, 'Light'),
                    (ThemeMode.dark, 'Dark'),
                  ],
                  onChanged: (m) =>
                      ref.read(themeModeProvider.notifier).set(m),
                );
              },
            ),
            const SizedBox(height: Space.section),
            Text('ABOUT', style: AppType.label.copyWith(color: ink.ink500)),
            const SizedBox(height: Space.sm),
            Text(
              'AfterTouch $appVersion — an unofficial community app. Not '
              'affiliated with, endorsed by, or connected to Bose Corporation. '
              '"SoundTouch" and "Bose" are trademarks of Bose Corporation.',
              style: AppType.caption.copyWith(color: ink.ink500),
            ),
          ],
        ),
      ),
    );
  }
}
