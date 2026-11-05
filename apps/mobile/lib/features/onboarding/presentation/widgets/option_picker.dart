import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/oma_colors.dart';
import '../../application/master_data_providers.dart';
import '../../domain/entities/master_option.dart';
import 'master_chips.dart';
import 'tap_field.dart';

class OptionPickerField extends ConsumerWidget {
  const OptionPickerField({
    required this.label,
    required this.type,
    required this.selectedId,
    required this.onChanged,
    this.placeholder = 'Choose',
    super.key,
  });

  final String label;
  final MasterDataType type;
  final String? selectedId;
  final String placeholder;
  final ValueChanged<MasterOption?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options = ref.watch(masterOptionsProvider(type));
    if (options case AsyncError()) {
      return MasterLoadError(
        onRetry: () => ref.invalidate(masterOptionsProvider(type)),
      );
    }
    final list = options.value ?? const <MasterOption>[];
    final current = list.where((o) => o.id == selectedId).firstOrNull;
    return TapField(
      label: label,
      value: current?.label,
      placeholder: placeholder,
      onTap: list.isEmpty
          ? null
          : () async {
              final picked = await showModalBottomSheet<_Pick>(
                context: context,
                showDragHandle: true,
                builder: (_) => _OptionList(
                  title: label,
                  options: list,
                  selectedId: selectedId,
                ),
              );
              if (picked != null) onChanged(picked.option);
            },
    );
  }
}

class _Pick {
  const _Pick(this.option);

  final MasterOption? option;
}

class _OptionList extends StatelessWidget {
  const _OptionList({
    required this.title,
    required this.options,
    required this.selectedId,
  });

  final String title;
  final List<MasterOption> options;
  final String? selectedId;

  @override
  Widget build(BuildContext context) {
    final c = context.oma;
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
          ),
          for (final o in options)
            ListTile(
              title: Text(o.label),
              trailing: o.id == selectedId
                  ? Icon(Icons.check, color: c.primary)
                  : null,
              onTap: () => Navigator.pop(context, _Pick(o)),
            ),
          ListTile(
            title: Text(
              'Prefer not to say',
              style: TextStyle(color: c.textMuted),
            ),
            onTap: () => Navigator.pop(context, const _Pick(null)),
          ),
        ],
      ),
    );
  }
}

class SearchPickerSheet extends ConsumerStatefulWidget {
  const SearchPickerSheet({
    required this.title,
    required this.type,
    this.categoryId,
    this.selectedIds = const {},
    super.key,
  });

  final String title;
  final MasterDataType type;
  final String? categoryId;
  final Set<String> selectedIds;

  static Future<MasterOption?> show(
    BuildContext context, {
    required String title,
    required MasterDataType type,
    String? categoryId,
    Set<String> selectedIds = const {},
  }) => showModalBottomSheet<MasterOption>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.85,
      child: SearchPickerSheet(
        title: title,
        type: type,
        categoryId: categoryId,
        selectedIds: selectedIds,
      ),
    ),
  );

  @override
  ConsumerState<SearchPickerSheet> createState() => _SearchPickerSheetState();
}

class _SearchPickerSheetState extends ConsumerState<SearchPickerSheet> {
  final _items = <MasterOption>[];
  final _scroll = ScrollController();
  Timer? _debounce;
  String _query = '';
  int _page = 0;
  bool _hasMore = true;
  bool _loading = false;
  bool _failed = false;

  /// Bumped on every new query so a slow old page is ignored.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 200) _loadMore();
    });
    _loadMore();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _onQuery(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      setState(() {
        _query = q.trim();
        _items.clear();
        _page = 0;
        _hasMore = true;
        _generation++;
        _loading = false;
      });
      _loadMore();
    });
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    final gen = _generation;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final p = await ref
          .read(masterDataRepositoryProvider)
          .page(
            widget.type,
            query: _query,
            categoryId: widget.categoryId,
            page: _page + 1,
          );
      if (!mounted || gen != _generation) return;
      setState(() {
        _items.addAll(p.items);
        _page = p.page;
        _hasMore = p.hasMore;
      });
    } on Object {
      if (mounted && gen == _generation) setState(() => _failed = true);
    } finally {
      if (mounted && gen == _generation) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.oma;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                TextField(
                  autofocus: true,
                  onChanged: _onQuery,
                  decoration: const InputDecoration(
                    hintText: 'Search',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              itemCount: _items.length + 1,
              itemBuilder: (context, i) {
                if (i < _items.length) {
                  final o = _items[i];
                  return ListTile(
                    title: Text(o.label),
                    trailing: widget.selectedIds.contains(o.id)
                        ? Icon(Icons.check, color: c.primary)
                        : null,
                    onTap: () => Navigator.pop(context, o),
                  );
                }
                if (_failed) {
                  return Padding(
                    padding: const EdgeInsets.all(20),
                    child: MasterLoadError(onRetry: _loadMore),
                  );
                }
                if (_loading) {
                  return const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (_items.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      'No results for "$_query".',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.textMuted),
                    ),
                  );
                }
                return const SizedBox(height: 24);
              },
            ),
          ),
        ],
      ),
    );
  }
}
