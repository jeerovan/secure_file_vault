import 'dart:async';
import 'dart:io';
import 'package:file_vault_bb/models/model_item.dart';
import 'package:file_vault_bb/ui/common_widgets.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:open_filex/open_filex.dart';
import '../../l10n/app_localizations.dart';
import '../../models/model_item_task.dart';
import '../../services/service_logger.dart';
import '../../utils/enums.dart';
import '../../utils/utils_tasks.dart';
import 'page_file_info.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  AppLogger logger = AppLogger(prefixes: ["Search"]);
  bool processing = false;
  Timer? _debounce;
  late final TextEditingController _searchController;

  final ValueNotifier<List<ModelItem>> _itemsNotifier = ValueNotifier([]);
  final ValueNotifier<Set<ModelItem>> _selectedItemsNotifier =
      ValueNotifier({});
  final ValueNotifier<bool> _isMultiSelectNotifier = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _itemsNotifier.dispose();
    _selectedItemsNotifier.dispose();
    _isMultiSelectNotifier.dispose();
    super.dispose();
  }

  Future<void> performSearch(String query) async {
    if (!mounted) return;

    final searchQuery = query.trim();
    if (searchQuery.isEmpty) {
      _itemsNotifier.value = [];
      return;
    }
    setState(() {
      processing = true;
    });
    try {
      List<ModelItem> searchedItems = await ModelItem.searchItem(searchQuery);
      if (mounted) {
        setState(() {
          _itemsNotifier.value = searchedItems;
        });
      }
    } catch (e, s) {
      logger.error("Search failed", error: e, stackTrace: s);
    } finally {
      if (mounted) {
        setState(() {
          processing = false;
        });
      }
    }
  }

  void onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) {
      _debounce!.cancel();
    }
    _debounce = Timer(const Duration(milliseconds: 500), () {
      final trimmedQuery = query.trim();
      performSearch(trimmedQuery);
    });
  }

  Future<void> _navigateBack() async {
    Navigator.pop(context);
  }

  Future<void> _onTap(ModelItem item) async {
    if (_isMultiSelectNotifier.value) {
      _toggleSelection(item);
      return;
    }
    String path = await ModelItem.getPathForItem(item.id);
    final openResult = await OpenFilex.open(path);
    if (openResult.type != ResultType.done) {
      String message = 'Could not open file: ${openResult.message}';
      logger.error(message);
      if (mounted) {
        displaySnackBar(
          context,
          message: AppLocalizations.of(context)!.longPressToDownload,
          seconds: 2,
        );
      }
    }
  }

  void _onLongPress(ModelItem item) {
    if (!_isMultiSelectNotifier.value) {
      _isMultiSelectNotifier.value = true;
      _toggleSelection(item);
    }
  }

  void _toggleSelection(ModelItem item) {
    final currentSelection = Set<ModelItem>.from(_selectedItemsNotifier.value);

    if (currentSelection.contains(item)) {
      currentSelection.remove(item);
    } else {
      currentSelection.add(item);
    }

    _selectedItemsNotifier.value = currentSelection;

    if (currentSelection.isEmpty && _isMultiSelectNotifier.value) {
      _cancelMultiSelect();
    }
  }

  void _cancelMultiSelect() {
    _isMultiSelectNotifier.value = false;
    _selectedItemsNotifier.value = {};
  }

  Future<void> trashItems() async {
    final currentItems = List<ModelItem>.from(_itemsNotifier.value);
    final toRemove = [];
    final selectedItems = List<ModelItem>.from(_selectedItemsNotifier.value);
    logger.log('Trashing ${selectedItems.length} items');
    for (ModelItem modelItem in selectedItems) {
      bool addToRemove = true;
      bool isLocalPath = await ModelItem.isLocalPath(modelItem.id);
      if (isLocalPath) {
        String localPath = await ModelItem.getPathForLocalItem(modelItem.id);
        if (File(localPath).existsSync()) {
          addToRemove = false;
        }
      }
      if (addToRemove) {
        modelItem.archivedAt = DateTime.now().toUtc().millisecondsSinceEpoch;
        await modelItem.update(["archived_at"]);
        toRemove.add(modelItem);
      }
    }
    currentItems.removeWhere((item) => toRemove.contains(item));
    _itemsNotifier.value = currentItems;
    _cancelMultiSelect();
  }

  Future<void> downloadItems() async {
    final selectedItems = List<ModelItem>.from(_selectedItemsNotifier.value);
    logger.log('Downloading ${selectedItems.length} items');
    bool hasTasks = false;
    for (ModelItem item in selectedItems) {
      String path = await ModelItem.getPathForItem(item.id);
      if (!File(path).existsSync()) {
        await ModelItemTask.addTask(item.id, ItemTask.download.value);
        hasTasks = true;
      }
    }
    if (hasTasks) {
      TaskManager.init();
    }
    _cancelMultiSelect();
  }

  Future<void> showInfo() async {
    final selectedItems = List<ModelItem>.from(_selectedItemsNotifier.value);
    if (selectedItems.length > 1) {
      return;
    }
    ModelItem item = selectedItems.first;
    if (!item.isFolder) {
      Navigator.of(context)
          .push(AnimatedPageRoute(child: PageFileInfo(item: item)));
    }
  }

  Widget _buildAppBar() {
    final surfaceColor = Theme.of(context).colorScheme.surfaceContainerHighest;

    return ListenableBuilder(
      listenable:
          Listenable.merge([_selectedItemsNotifier, _isMultiSelectNotifier]),
      builder: (context, _) {
        final isMultiSelectMode = _isMultiSelectNotifier.value;
        final selectedItems = _selectedItemsNotifier.value;

        if (isMultiSelectMode) {
          return buildBottomAppBar(
            color: surfaceColor,
            leading: IconButton(
              icon: const Icon(LucideIcons.x),
              tooltip: AppLocalizations.of(context)!.cancel,
              onPressed: _cancelMultiSelect,
            ),
            title: Text(
              AppLocalizations.of(context)!
                  .selectedItemsCount(selectedItems.length),
            ),
            actions: [
              if (selectedItems.length == 1)
                IconButton(
                  icon: const Icon(LucideIcons.info),
                  tooltip: AppLocalizations.of(context)!.info,
                  onPressed: showInfo,
                ),
              IconButton(
                icon: const Icon(LucideIcons.downloadCloud),
                tooltip: AppLocalizations.of(context)!.download,
                onPressed: downloadItems,
              ),
              IconButton(
                icon: const Icon(LucideIcons.archive),
                tooltip: AppLocalizations.of(context)!.archive,
                onPressed: trashItems,
              ),
            ],
          );
        }

        return buildBottomAppBar(
          color: surfaceColor,
          leading: IconButton(
            icon: const Icon(LucideIcons.arrowLeft),
            onPressed: _navigateBack,
          ),
          title: SizedBox(
            height: 40,
            child: TextField(
              controller: _searchController,
              onChanged: onSearchChanged,
              textAlignVertical: TextAlignVertical.center,
              textInputAction: TextInputAction.search,
              style: Theme.of(context).textTheme.bodyMedium,
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor:
                    Theme.of(context).colorScheme.onSurface.withAlpha(20),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.0),
                  borderSide: BorderSide.none,
                ),
                hintText:
                    AppLocalizations.of(context)!.searchWithMinThreeCharacters,
                hintStyle: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withAlpha(125),
                ),
                prefixIcon: Icon(
                  LucideIcons.search,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurface.withAlpha(125),
                ),
                suffixIcon: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _searchController,
                  builder: (context, value, child) {
                    if (value.text.isEmpty) return const SizedBox.shrink();
                    return IconButton(
                      icon: const Icon(LucideIcons.x, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        onSearchChanged('');
                      },
                    );
                  },
                ),
              ),
            ),
          ),
          actions: const [],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return CrossPlatformBackHandler(
      canPop: true,
      onManualBack: _navigateBack,
      child: Scaffold(
        body: Column(
          children: [
            Expanded(
              child: processing
                  ? const Center(child: CircularProgressIndicator())
                  : _buildFileView(),
            ),
            _buildAppBar()
          ],
        ),
      ),
    );
  }

  Widget _buildFileView() {
    return ValueListenableBuilder<List<ModelItem>>(
      valueListenable: _itemsNotifier,
      builder: (context, items, _) {
        if (items.isEmpty) {
          if (_searchController.text.isEmpty) {
            return Center(
              child: Text(
                AppLocalizations.of(context)!.typeBelowToSearch,
              ),
            );
          } else {
            return Center(
              child: Text(
                AppLocalizations.of(context)!.noResults,
              ),
            );
          }
        }
        return ListView.builder(
          reverse: true,
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];

            return FileListItem(
              key: ValueKey(item.id),
              item: item,
              selectedItemsNotifier: _selectedItemsNotifier,
              isMultiSelectNotifier: _isMultiSelectNotifier,
              onTap: () => _onTap(item),
              onLongPress: () => _onLongPress(item),
            );
          },
        );
      },
    );
  }
}
