import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/app_ink.dart';
import '../../design/app_spacing.dart';
import '../../design/app_typography.dart';
import '../presets/save_as_preset.dart';
import 'library_controller.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key, required this.speakerKey, required this.title});

  final String speakerKey;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ink = context.ink;
    final state = ref.watch(libraryControllerProvider(speakerKey));
    final c = ref.read(libraryControllerProvider(speakerKey).notifier);

    return PopScope(
      canPop: !state.browsing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) c.up();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(state.browsing ? _crumbTitle(state) : 'Library'),
          leading: state.browsing
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: c.up,
                )
              : null,
          actions: [
            if (!state.browsing)
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: c.refresh,
              ),
          ],
        ),
        body: SafeArea(
          child: state.loading
              ? const Center(child: _Spinner())
              : state.unreachable
                  ? Center(
                      child: Text("Can't reach this speaker",
                          style: AppType.body.copyWith(color: ink.ink500)),
                    )
                  : state.browsing
                      ? _Browser(state: state, c: c, speakerKey: speakerKey)
                      : _Servers(state: state, c: c),
        ),
      ),
    );
  }

  String _crumbTitle(LibraryState s) =>
      s.crumbs.isEmpty ? 'Library' : s.crumbs.last.name;
}

class _Servers extends StatelessWidget {
  const _Servers({required this.state, required this.c});
  final LibraryState state;
  final LibraryController c;

  @override
  Widget build(BuildContext context) {
    final ink = context.ink;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      children: [
        if (state.busy)
          const LinearProgressIndicator(minHeight: 2),
        _SectionLabel('On this speaker'),
        if (state.registered.isEmpty)
          _Hint('No music servers added yet.'),
        for (final s in state.registered)
          ListTile(
            leading: Icon(Icons.dns_outlined, color: ink.ink700),
            title: Text(s.name, style: AppType.body.copyWith(color: ink.ink900)),
            subtitle: s.ready
                ? null
                : Text('Not ready',
                    style: AppType.caption.copyWith(color: ink.ink500)),
            trailing: IconButton(
              icon: Icon(Icons.close, color: ink.ink300),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final err = await c.unregister(s.account);
                _toast(messenger, err);
              },
            ),
            onTap: s.account.isEmpty ? null : () => c.open(s.account, s.name),
          ),
        const SizedBox(height: Space.lg),
        _SectionLabel('Found on the network'),
        if (state.discovered.isEmpty)
          _Hint('No other DLNA servers visible to this speaker.'),
        for (final m in state.discovered)
          ListTile(
            leading: Icon(Icons.add, color: ink.ink900),
            title: Text(m.name, style: AppType.body.copyWith(color: ink.ink900)),
            subtitle: m.modelName != null
                ? Text(m.modelName!,
                    style: AppType.caption.copyWith(color: ink.ink500))
                : null,
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              final err = await c.register(m);
              _toast(messenger, err ?? 'Added ${m.name}');
            },
          ),
        if (state.rawSources != null || state.rawMediaServers != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Space.gutter, Space.xl, Space.gutter, 0),
            child: ExpansionTile(
              title: Text('Speaker responses',
                  style: AppType.label.copyWith(color: ink.ink500)),
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              children: [
                if (state.rawSources != null)
                  _Mono(label: '/sources', body: state.rawSources!),
                if (state.rawMediaServers != null)
                  _Mono(
                      label: '/listMediaServers',
                      body: state.rawMediaServers!),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy'),
                    onPressed: () => Clipboard.setData(ClipboardData(
                      text: '/sources\n${state.rawSources ?? ''}\n\n'
                          '/listMediaServers\n${state.rawMediaServers ?? ''}',
                    )),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Browser extends ConsumerWidget {
  const _Browser({
    required this.state,
    required this.c,
    required this.speakerKey,
  });
  final LibraryState state;
  final LibraryController c;
  final String speakerKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ink = context.ink;

    if (state.browseLoading) return const Center(child: _Spinner());
    if (state.browseError != null) {
      return _Diagnostic(
        headline: "Couldn't read that folder",
        detail: state.browseError!,
        request: state.browseRequest,
        raw: state.browseRaw,
      );
    }
    if (state.entries.isEmpty) {
      return _Diagnostic(
        headline: 'Nothing in this folder',
        detail: 'The speaker returned an empty list.',
        request: state.browseRequest,
        raw: state.browseRaw,
      );
    }

    return Column(
      children: [
        _Crumbs(state: state),
        Divider(height: 1, color: ink.ink100),
        Expanded(
          child: ListView.separated(
            itemCount: state.entries.length,
            separatorBuilder: (_, _) =>
                Divider(height: 1, color: ink.ink100, indent: 56),
            itemBuilder: (context, i) {
              final item = state.entries[i];
              return ListTile(
                leading: Icon(
                  item.isDir ? Icons.folder_outlined : Icons.music_note,
                  color: item.isDir ? ink.ink700 : ink.ink500,
                ),
                title: Text(item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.body.copyWith(color: ink.ink900)),
                subtitle: item.artist != null
                    ? Text(item.artist!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.caption.copyWith(color: ink.ink500))
                    : null,
                trailing: item.isDir
                    ? Icon(Icons.chevron_right, color: ink.ink300)
                    : null,
                onTap: () async {
                  if (item.isDir) {
                    await c.enter(item);
                  } else {
                    final messenger = ScaffoldMessenger.of(context);
                    final err = await c.play(item);
                    if (err != null) {
                      _toast(messenger, err);
                      return;
                    }
                    messenger
                      ..clearSnackBars()
                      ..showSnackBar(SnackBar(
                        content: Text('Playing ${item.name}'),
                        action: SnackBarAction(
                          label: 'Save as preset',
                          onPressed: () async {
                            final msg = await pickSlotAndSaveCurrent(
                                context, ref, speakerKey);
                            if (msg != null && context.mounted) {
                              messenger.showSnackBar(
                                  SnackBar(content: Text(msg)));
                            }
                          },
                        ),
                      ));
                  }
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Crumbs extends StatelessWidget {
  const _Crumbs({required this.state});
  final LibraryState state;

  @override
  Widget build(BuildContext context) {
    final ink = context.ink;
    return Container(
      height: 36,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        child: Text(
          state.crumbs.map((c) => c.name).join('  ›  '),
          style: AppType.label.copyWith(color: ink.ink500),
        ),
      ),
    );
  }
}

/// Empty / error state with the raw speaker exchange behind a disclosure, so
/// DLNA browse problems can be reported precisely.
class _Diagnostic extends StatelessWidget {
  const _Diagnostic({
    required this.headline,
    required this.detail,
    this.request,
    this.raw,
  });

  final String headline;
  final String detail;
  final String? request;
  final String? raw;

  @override
  Widget build(BuildContext context) {
    final ink = context.ink;
    return ListView(
      padding: const EdgeInsets.all(Space.gutter),
      children: [
        const SizedBox(height: Space.xxl),
        Text(headline,
            textAlign: TextAlign.center,
            style: AppType.title.copyWith(color: ink.ink900)),
        const SizedBox(height: Space.sm),
        Text(detail,
            textAlign: TextAlign.center,
            style: AppType.body.copyWith(color: ink.ink500)),
        if (request != null || raw != null) ...[
          const SizedBox(height: Space.xl),
          ExpansionTile(
            title: Text('Speaker exchange',
                style: AppType.label.copyWith(color: ink.ink500)),
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            children: [
              if (request != null) _Mono(label: 'REQUEST', body: request!),
              if (raw != null) _Mono(label: 'RESPONSE', body: raw!),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copy'),
                  onPressed: () => Clipboard.setData(ClipboardData(
                    text: 'REQUEST\n${request ?? ''}\n\nRESPONSE\n${raw ?? ''}',
                  )),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Mono extends StatelessWidget {
  const _Mono({required this.label, required this.body});
  final String label;
  final String body;

  @override
  Widget build(BuildContext context) {
    final ink = context.ink;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: Space.sm),
      padding: const EdgeInsets.all(Space.md),
      color: ink.paper2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppType.label.copyWith(color: ink.ink500)),
          const SizedBox(height: Space.xs),
          SelectableText(
            body.length > 4000 ? '${body.substring(0, 4000)}…' : body,
            style: AppType.mono.copyWith(color: ink.ink700),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(
            Space.gutter, Space.lg, Space.gutter, Space.sm),
        child: Text(text.toUpperCase(),
            style: AppType.label.copyWith(color: context.ink.ink500)),
      );
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: Space.gutter, vertical: Space.sm),
        child: Text(text,
            style: AppType.body.copyWith(color: context.ink.ink500)),
      );
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

void _toast(ScaffoldMessengerState messenger, String? msg) {
  if (msg == null) return;
  messenger
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(msg)));
}
