import 'dart:async';
import 'dart:io';
import 'package:file_vault_bb/models/model_item.dart';
import 'package:file_vault_bb/ui/common_widgets.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:open_filex/open_filex.dart';

import '../../models/model_file.dart';
import '../../services/service_logger.dart';
import '../../utils/common.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  AppLogger logger = AppLogger(prefixes: ["Search"]);
  List<ModelItem> items = [];
  bool processing = false;
  Timer? _debounce;
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> performSearch(String query) async {
    if (!mounted) return;

    final searchQuery = query.trim();
    if (searchQuery.isEmpty) {
      if (mounted) {
        setState(() {
          items.clear();
        });
      }
      return;
    }
    setState(() {
      processing = true;
    });
    try {
      List<ModelItem> searchedItems = await ModelItem.searchItem(searchQuery);
      if (mounted) {
        setState(() {
          items = searchedItems;
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

  Future<void> onTap(ModelItem item) async {
    String path = await ModelItem.getPathForItem(item.id);
    final openResult = await OpenFilex.open(path);
    if (openResult.type != ResultType.done) {
      String message = 'Could not open file: ${openResult.message}';
      logger.error(message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final surfaceColor = Theme.of(context).colorScheme.surfaceContainerHighest;
    return CrossPlatformBackHandler(
      canPop: true,
      onManualBack: _navigateBack,
      child: Scaffold(
        body: Column(
          children: [
            Expanded(
              child: processing
                  ? const Center(child: CircularProgressIndicator())
                  : items.isEmpty
                      ? Center(
                          child: _searchController.text.isEmpty && items.isEmpty
                              ? Text("Type below to search")
                              : Text("No results"))
                      : ListView.builder(
                          reverse: true,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16.0, vertical: 24.0),
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final item = items[index];
                            return _SearchListItem(
                              key: ValueKey(item.id),
                              item: item,
                              onTap: () => onTap(item),
                            );
                          },
                        ),
            ),
            buildBottomAppBar(
              color: surfaceColor,
              leading: IconButton(
                icon: const Icon(LucideIcons.arrowLeft),
                onPressed: _navigateBack,
              ),
              title: SizedBox(
                height: 40, // Keeps the search bar vertically constrained
                child: TextField(
                  controller: _searchController,
                  onChanged: onSearchChanged, // Triggers the debounce timer
                  textAlignVertical: TextAlignVertical
                      .center, // FIX: Perfectly centers text vertically
                  textInputAction: TextInputAction.search,
                  style: Theme.of(context).textTheme.bodyMedium,
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor:
                        Theme.of(context).colorScheme.onSurface.withAlpha(20),
                    // FIX: Removed vertical padding so textAlignVertical can do its job
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16.0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12.0),
                      borderSide:
                          BorderSide.none, // Removes default underline/borders
                    ),
                    hintText: 'Search with min 3 characters',
                    hintStyle: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withAlpha(125),
                    ),
                    prefixIcon: Icon(
                      LucideIcons.search,
                      size: 20,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withAlpha(125),
                    ),
                    suffixIcon: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _searchController,
                      builder: (context, value, child) {
                        if (value.text.isEmpty) return const SizedBox.shrink();
                        return IconButton(
                          icon: const Icon(LucideIcons.x, size: 18),
                          splashRadius: 20,
                          onPressed: () {
                            _searchController.clear();
                            onSearchChanged(
                                ''); // Immediately reset search with debounce
                          },
                        );
                      },
                    ),
                  ),
                ),
              ),
              actions: const [], // Action button removed as requested
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchListItem extends StatefulWidget {
  final ModelItem item;
  final VoidCallback onTap;

  const _SearchListItem({super.key, required this.item, required this.onTap});

  @override
  State<_SearchListItem> createState() => _SearchListItemState();
}

class _SearchListItemState extends State<_SearchListItem> {
  bool? _isLocal;
  bool? _isUploaded;
  int transferProgress = 0;
  AppLogger logger = AppLogger(prefixes: ["SearchListItem"]);

  @override
  void initState() {
    super.initState();
    if (!widget.item.isFolder) {
      _checkFileStates();
    }
  }

  Future<void> _checkFileStates() async {
    // Run both async tasks concurrently for optimal performance
    final stateResults = await Future.wait([
      fileExistsLocally(widget.item),
      widget.item.isFolder
          ? Future.value(false)
          : fileUploadedToCloud(widget.item),
    ]);

    // Always check if the widget is still in the tree before calling setState
    if (!mounted) return;

    setState(() {
      _isLocal = stateResults[0];
      _isUploaded = stateResults[1];
    });
  }

  Future<bool> fileExistsLocally(ModelItem item) async {
    String path = await ModelItem.getPathForItem(item.id);
    return await File(path).exists();
  }

  Future<bool> fileUploadedToCloud(ModelItem item) async {
    ModelFile? modelFile = await ModelFile.get(item.fileHash!);
    if (modelFile != null) {
      return modelFile.uploadedAt > 0;
    }
    return false;
  }

  Widget _buildTrailingIndicator() {
    if (_isUploaded == null) {
      // Show a subtle, tiny loading spinner while checking cloud status
      return const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    if (_isUploaded!) {
      return Icon(
        Icons.check,
        size: 16,
        color: Theme.of(context).colorScheme.primary.withAlpha(150),
      );
    }

    return SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: widget.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
        child: Row(
          children: [
            SizedBox(
              width: 30,
              height: 30,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  if (widget.item.isFolder)
                    Align(
                      alignment: Alignment.center,
                      child: Icon(LucideIcons.folder,
                          size: 28,
                          color: theme.colorScheme.primary.withAlpha(150)),
                    ),

                  // Local Existence Indicator (Grey while loading, then Red/Green)
                  if (!widget.item.isFolder)
                    Align(
                      alignment: Alignment.center,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: _isLocal == null
                              ? Colors.grey.shade400 // Loading state
                              : (_isLocal! ? Colors.green : Colors.red),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Theme.of(context).scaffoldBackgroundColor,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(width: 4),

            // 3. File Details
            Expanded(
                child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  widget.item.name,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.onSurface,
                    height:
                        1.2, // Tighter line height for better vertical rhythm in lists
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                // Only display if it is a file
                if (!widget.item.isFolder) ...[
                  const SizedBox(
                      height:
                          2), // Subtle spacing separates title from metadata
                  Text(
                    readableFileSizeFromBytes(widget.item.size),
                    style: theme.textTheme.bodySmall?.copyWith(
                      // onSurfaceVariant provides the perfect professional muted contrast
                      // against the onSurface title color
                      color: theme.colorScheme.onSurfaceVariant,
                      letterSpacing:
                          0.1, // Enhances readability for small alphanumeric text
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            )),

            const SizedBox(width: 8),

            // 4. State Indicators (Cloud / Local)
            if (!widget.item.isFolder) _buildTrailingIndicator()
          ],
        ),
      ),
    );
  }
}
