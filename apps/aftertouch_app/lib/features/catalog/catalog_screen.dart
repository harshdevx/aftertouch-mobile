import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:soundtouch_client/soundtouch_client.dart';

import '../../design/app_ink.dart';
import '../../design/app_spacing.dart';
import '../../design/app_typography.dart';
import '../presets/save_as_preset.dart';
import 'catalog_controller.dart';

/// Browse / search TuneIn and RadioBrowser through a configured AfterTouch
/// instance, and play a result to [speakerKey].
class CatalogScreen extends ConsumerStatefulWidget {
  const CatalogScreen({super.key, required this.speakerKey, required this.title});

  final String speakerKey;
  final String title;

  @override
  ConsumerState<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends ConsumerState<CatalogScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ink = context.ink;
    final state = ref.watch(catalogControllerProvider);
    final c = ref.read(catalogControllerProvider.notifier);

    return PopScope(
      canPop: !state.canGoUp,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) c.up();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Radio'),
          leading: state.canGoUp
              ? IconButton(
                  icon: const Icon(Icons.arrow_back), onPressed: c.up)
              : null,
        ),
        body: SafeArea(
          child: Column(
            children: [
              _ProviderToggle(
                value: state.provider,
                onChanged: c.switchProvider,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    Space.gutter, 0, Space.gutter, Space.sm),
                child: TextField(
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  onSubmitted: c.search,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: state.provider == CatalogProvider.tuneIn
                        ? 'Search TuneIn'
                        : 'Search RadioBrowser',
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              if (state.crumbs.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: Space.gutter, vertical: 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      state.crumbs.map((e) => e.name).join('  ›  '),
                      style: AppType.label.copyWith(color: ink.ink500),
                    ),
                  ),
                ),
              Divider(height: 1, color: ink.ink100),
              Expanded(child: _body(context, state, c)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    CatalogState state,
    CatalogController c,
  ) {
    final ink = context.ink;
    if (state.loading) {
      return const Center(child: _Spinner());
    }
    if (state.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(Space.gutter),
          child: Text(state.error!,
              textAlign: TextAlign.center,
              style: AppType.body.copyWith(color: ink.ink500)),
        ),
      );
    }
    final sections = state.sections.where((s) => s.items.isNotEmpty).toList();
    if (sections.isEmpty) {
      return Center(
        child: Text(
          state.provider == CatalogProvider.radioBrowser && !state.searchMode
              ? 'Search RadioBrowser above.'
              : 'Nothing here.',
          style: AppType.body.copyWith(color: ink.ink500),
        ),
      );
    }

    return ListView(
      children: [
        for (final section in sections) ...[
          if (section.name.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Space.gutter, Space.lg, Space.gutter, Space.sm),
              child: Text(section.name.toUpperCase(),
                  style: AppType.label.copyWith(color: ink.ink500)),
            ),
          for (final item in section.items)
            _ItemTile(
              item: item,
              onTap: () async {
                if (item.isFolder) {
                  await c.enter(item);
                } else if (item.isPlayable) {
                  final messenger = ScaffoldMessenger.of(context);
                  final err = await c.play(item, widget.speakerKey);
                  messenger
                    ..clearSnackBars()
                    ..showSnackBar(SnackBar(
                      content: Text(err ?? 'Playing ${item.name}'),
                      action: err != null
                          ? null
                          : SnackBarAction(
                              label: 'Save as preset',
                              onPressed: () async {
                                final msg = await pickSlotAndSaveCurrent(
                                    context, ref, widget.speakerKey);
                                if (msg != null && context.mounted) {
                                  messenger.showSnackBar(
                                      SnackBar(content: Text(msg)));
                                }
                              },
                            ),
                    ));
                }
              },
            ),
        ],
      ],
    );
  }
}

class _ProviderToggle extends StatelessWidget {
  const _ProviderToggle({required this.value, required this.onChanged});
  final CatalogProvider value;
  final ValueChanged<CatalogProvider> onChanged;

  @override
  Widget build(BuildContext context) {
    final ink = context.ink;
    Widget seg(String label, CatalogProvider p) {
      final active = p == value;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(p),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: Space.md),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? ink.ink900 : null,
              border: Border.all(color: ink.ink900),
            ),
            child: Text(
              label.toUpperCase(),
              style: AppType.label
                  .copyWith(color: active ? ink.paper : ink.ink900),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(Space.gutter),
      child: Row(
        children: [
          seg('TuneIn', CatalogProvider.tuneIn),
          seg('RadioBrowser', CatalogProvider.radioBrowser),
        ],
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item, required this.onTap});
  final BmxItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = context.ink;
    return ListTile(
      leading: Icon(
        item.isFolder ? Icons.folder_outlined : Icons.radio,
        color: item.isFolder ? ink.ink700 : ink.ink500,
      ),
      title: Text(item.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppType.body.copyWith(color: ink.ink900)),
      subtitle: item.subtitle.isEmpty
          ? null
          : Text(item.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.caption.copyWith(color: ink.ink500)),
      trailing: item.isFolder
          ? Icon(Icons.chevron_right, color: ink.ink300)
          : null,
      onTap: onTap,
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
