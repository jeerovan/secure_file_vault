import 'package:file_vault_bb/ui/common_widgets.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../../models/model_item.dart';
import '../../services/service_logger.dart';
import '../../utils/common.dart';
import 'package:flutter/material.dart';

class PageTrash extends StatefulWidget {
  const PageTrash({super.key});

  @override
  State<PageTrash> createState() => _PageTrashState();
}

class _PageTrashState extends State<PageTrash> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          return FilePane();
        },
      ),
    );
  }
}

// --- File Pane Widget ---
class FilePane extends StatefulWidget {
  const FilePane({
    super.key,
  });

  @override
  State<FilePane> createState() => _FilePaneState();
}

class _FilePaneState extends State<FilePane> {
  final AppLogger logger = AppLogger(prefixes: ["TrashPage"]);
  List<ModelItem> _items = [];
  bool _isLoading = false;
  // Multi-select state
  bool _isMultiSelectMode = false;
  final Set<ModelItem> _selectedItems = {};

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadFiles() async {
    setState(() => _isLoading = true);
    final items = await ModelItem.getArchived();
    if (mounted) {
      setState(() {
        _items = items;
        _isLoading = false;
      });
    }
  }

  void _onLongPress(ModelItem item) {
    if (!_isMultiSelectMode) {
      setState(() {
        _isMultiSelectMode = true;
        _selectedItems.add(item);
      });
    }
  }

  void _toggleSelection(ModelItem item) {
    setState(() {
      if (_selectedItems.contains(item)) {
        _selectedItems.remove(item);
        if (_selectedItems.isEmpty) {
          _isMultiSelectMode = false; // Exit mode if nothing is selected
        }
      } else {
        _selectedItems.add(item);
        _isMultiSelectMode = true;
      }
    });
  }

  void _cancelMultiSelect() {
    setState(() {
      _isMultiSelectMode = false;
      _selectedItems.clear();
    });
  }

  Future<void> deleteItems() async {
    setState(() {
      _isLoading = true;
    });
    logger.log('Deleting ${_selectedItems.length} items');
    for (ModelItem modelItem in _selectedItems) {
      await modelItem.remove();
    }
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
    _cancelMultiSelect();
    _loadFiles();
  }

  Future<void> clearAll() async {
    setState(() {
      _isLoading = true;
    });
    logger.log('Clear all');
    for (ModelItem modelItem in _items) {
      await modelItem.remove();
    }
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
    _loadFiles();
  }

  Future<void> recoverItems() async {
    logger.log('Recovering ${_selectedItems.length} items');
    for (ModelItem item in _selectedItems) {
      item.archivedAt = 0;
      await item.update(["archived_at"]);
    }
    _cancelMultiSelect();
    _loadFiles();
  }

  Future<void> navigateBack() async {
    Navigator.pop(context);
  }

  PreferredSizeWidget _buildAppBar() {
    final surfaceColor = Theme.of(context).colorScheme.surfaceContainerHighest;

    if (_isMultiSelectMode) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.x),
          tooltip: 'Cancel',
          onPressed: _cancelMultiSelect,
        ),
        title: Text('${_selectedItems.length} Selected'),
        backgroundColor: surfaceColor,
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.undo),
            tooltip: 'Recover',
            onPressed: recoverItems,
          ),
          IconButton(
            icon: const Icon(LucideIcons.trash),
            tooltip: 'Delete',
            onPressed: deleteItems,
          ),
        ],
      );
    }

    // Default AppBar
    return AppBar(
      leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          tooltip: 'Back',
          onPressed: navigateBack),
      title: Text("Trash"),
      backgroundColor: surfaceColor,
      actions: [
        if (_items.isNotEmpty)
          IconButton(
              icon: const Icon(LucideIcons.trash2),
              tooltip: 'Empty',
              onPressed: clearAll),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _items.isEmpty
                  ? const Center(child: Text('No items.'))
                  : _buildFileView(),
        ),
        _buildAppBar()
      ],
    );
  }

  Widget _buildFileView() {
    return ListView.builder(
      reverse: true,
      itemCount: _items.length,
      itemBuilder: (context, index) {
        final item = _items[index];
        final isSelected = _selectedItems.contains(item);

        return _FileListItem(
          key: Key(item.id),
          item: item,
          isMultiSelectMode: _isMultiSelectMode,
          isSelected: isSelected,
          onTap: () => _toggleSelection(item),
          onLongPress: () => _onLongPress(item),
        );
      },
    );
  }
}

class _FileListItem extends StatefulWidget {
  final ModelItem item;
  final bool isMultiSelectMode;
  final bool isSelected;
  final VoidCallback onLongPress;
  final VoidCallback onTap;

  const _FileListItem({
    super.key,
    required this.item,
    required this.isMultiSelectMode,
    required this.isSelected,
    required this.onLongPress,
    required this.onTap,
  });

  @override
  State<_FileListItem> createState() => _FileListItemState();
}

class _FileListItemState extends State<_FileListItem> {
  AppLogger logger = AppLogger(prefixes: ["ArchiveListItem"]);

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
          child: Row(
            children: [
              // 1. Multi-Select Circular Checkbox
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                child: SizedBox(
                  width: 18,
                  child: widget.isMultiSelectMode
                      ? Row(
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: widget.isSelected
                                    ? Colors.grey.shade600
                                    : Colors.transparent,
                                border: Border.all(
                                  color: widget.isSelected
                                      ? Colors.grey.shade600
                                      : theme.colorScheme.outline,
                                  width: 2,
                                ),
                              ),
                              child: null,
                            ),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
              ),

              // 2. File / Folder Icon
              SizedBox(
                width: 30,
                height: 30,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Align(
                      alignment: Alignment.center,
                      child: Icon(
                          widget.item.isFolder
                              ? LucideIcons.folder
                              : LucideIcons.file,
                          size: 28,
                          color: theme.colorScheme.primary.withAlpha(150)),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 16),

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
            ],
          ),
        ),
      ),
    );
  }
}
