import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:file_vault_bb/utils/utils_sync.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';
import '../../models/model_file.dart';
import '../../models/model_item.dart';
import '../../models/model_item_task.dart';
import '../../services/service_events.dart';
import '../../services/service_logger.dart';
import '../../services/service_recon.dart';
import '../../utils/common.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path_lib;

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../utils/utils_tasks.dart';
import '../common_widgets.dart';

class PageExplorer extends StatefulWidget {
  final ThemeMode themeMode;
  final VoidCallback onThemeToggle;
  const PageExplorer({
    super.key,
    required this.themeMode,
    required this.onThemeToggle,
  });

  @override
  State<PageExplorer> createState() => _PageExplorerState();
}

class _PageExplorerState extends State<PageExplorer> {
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
  final AppLogger logger = AppLogger(prefixes: ["Explorer"]);
  final ScrollController _breadcrumbController = ScrollController();
  final ValueNotifier<List<ModelItem>> _itemsNotifier = ValueNotifier([]);
  ModelItem? currentItem;
  bool _isLoading = false;
  bool _isLocalPath = false;
  bool _isDeviceRoot = false;
  List<ModelItem> parentChilds = [];
  // Multi-select state
  final ValueNotifier<Set<ModelItem>> _selectedItemsNotifier =
      ValueNotifier({});

  // Notifier for multi-select mode state
  final ValueNotifier<bool> _isMultiSelectNotifier = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    EventStream().notifier.addListener(_handleAppEvents);
    _loadFiles();
  }

  @override
  void dispose() {
    EventStream().notifier.removeListener(_handleAppEvents);
    _breadcrumbController.dispose();
    _itemsNotifier.dispose();
    _selectedItemsNotifier.dispose();
    _isMultiSelectNotifier.dispose();
    super.dispose();
  }

  Future<void> _handleAppEvents() async {
    final AppEvent? event = EventStream().notifier.value;
    if (event == null) return;
    switch (event.type) {
      case EventType.updateItem:
        if (event.key == EventKey.added) {
          ModelItem? item = await ModelItem.get(event.id);
          if (item != null &&
              currentItem != null &&
              item.parentId == currentItem!.id) {
            final currentItems = List<ModelItem>.from(_itemsNotifier.value);
            if (item.isFolder) {
              currentItems.insert(0, item);
            } else {
              currentItems.add(item);
            }
            _itemsNotifier.value = currentItems;
          }
        } else if (event.key == EventKey.removed) {
          final removedId = event.id;
          final currentItems = List<ModelItem>.from(_itemsNotifier.value);
          currentItems.removeWhere((item) => item.id == removedId);
          _itemsNotifier.value = currentItems;
        }
        break;
    }
  }

  Future<void> _loadFiles() async {
    if (currentItem == null) {
      ModelItem? rootFife = await ModelItem.get("fife");
      if (rootFife != null) {
        parentChilds.add(rootFife);
      }
      currentItem = await ModelItem.get(await getDeviceHash());
      if (currentItem != null) parentChilds.add(currentItem!);
    }
    if (currentItem == null) return;
    setState(() => _isLoading = true);
    final items = await ModelItem.getDisplayItems(currentItem);
    _isLocalPath = await ModelItem.isLocalPath(currentItem!.id);
    String deviceRootHash = await getDeviceHash();
    _isDeviceRoot = currentItem?.id == deviceRootHash;
    _itemsNotifier.value = items;
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _syncRootFolders() async {
    List<ModelItem> syncFolders = await ModelItem.getAllSyncedFolders();
    for (ModelItem syncFolder in syncFolders) {
      await ReconciliationService().reconcile(syncFolder.id);
    }
    _loadFiles();
    // Issue server sync irrespective of items change
    SyncUtils.waitAndSyncChanges();
  }

  Future<void> _onTap(ModelItem item) async {
    if (_isMultiSelectNotifier.value) {
      _toggleSelection(item);
      return;
    }

    if (item.isFolder) {
      currentItem = item;
      _loadFiles();
      if (parentChilds.contains(item)) {
        parentChilds = parentChilds.sublist(0, parentChilds.indexOf(item) + 1);
      } else {
        parentChilds.add(item);
      }
    } else {
      String path = await ModelItem.getPathForItem(item.id);
      final openResult = await OpenFilex.open(path);
      if (openResult.type != ResultType.done) {
        String message = 'Could not open file: ${openResult.message}';
        logger.error(message);
      }
    }
  }

  Future<void> _navigateBack() async {
    ModelItem? parentItem = await ModelItem.getParentItem(currentItem);
    if (parentItem != null) {
      parentChilds = parentChilds.sublist(0, parentChilds.length - 1);
      currentItem = parentItem;
      _loadFiles();
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

    // Automatically exit multi-select mode if no items are selected
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
    if (await ModelItem.isLocalPath(currentItem!.id)) {
      for (ModelItem modelItem in selectedItems) {
        String localPath = await ModelItem.getPathForLocalItem(modelItem.id);
        if (!File(localPath).existsSync()) {
          modelItem.archivedAt = DateTime.now().toUtc().millisecondsSinceEpoch;
          await modelItem.update(["archived_at"]);
          toRemove.add(modelItem);
        }
      }
    } else {
      // A recon scan on other devices will automatically reset archive_at
      for (ModelItem modelItem in selectedItems) {
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
      if (item.isFolder) continue;
      String path = await ModelItem.getPathForItem(item.id);
      if (!File(path).existsSync()) {
        await ModelItemTask.addTask(item.id, ItemTask.download.value);
        hasTasks = true;
        // Broadcast download events
        EventStream().publish(AppEvent(
            type: EventType.updateItem,
            id: item.id,
            key: EventKey.downloadProgress,
            value: 0.0));
      }
    }
    if (hasTasks) {
      TaskManager.init(inBackground: false);
    }
    _cancelMultiSelect();
  }

  Future<void> showInfo() async {}

  Future<void> signout() async {
    context.read<AppSetupState>().logout();
  }

  Future<void> showArchives() async {
    context.read<AppSetupState>().showArchives();
  }

  PreferredSizeWidget _buildAppBar() {
    final surfaceColor = Theme.of(context).colorScheme.surfaceContainerHighest;
    Widget buildBreadcrumb() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_breadcrumbController.hasClients) {
          _breadcrumbController.animateTo(
            _breadcrumbController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
          );
        }
      });
      List<Widget> breadcrumbWidgets = [];

      for (int i = 0; i < parentChilds.length; i++) {
        ModelItem item = parentChilds[i];
        final part = item.name;
        final isLast = i == parentChilds.length - 1;

        breadcrumbWidgets.add(
          InkWell(
            onTap: () => {_onTap(item)},
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
              child: Text(
                part,
                style: TextStyle(
                  fontSize: Theme.of(context).textTheme.titleMedium?.fontSize,
                  color: isLast
                      ? Theme.of(context).colorScheme.onSurface
                      : Theme.of(context).colorScheme.onSurface.withAlpha(140),
                  fontWeight: isLast ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ),
        );

        if (!isLast) {
          breadcrumbWidgets.add(Icon(LucideIcons.chevronRight,
              size: 18,
              color: Theme.of(context).colorScheme.onSurface.withAlpha(100)));
        }
      }

      breadcrumbWidgets.add(const SizedBox(width: 16));

      return SingleChildScrollView(
        controller: _breadcrumbController,
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: breadcrumbWidgets,
        ),
      );
    }

    return PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        // Update AppBar only when selection/multi-select changes
        child: ListenableBuilder(
            listenable: Listenable.merge(
                [_selectedItemsNotifier, _isMultiSelectNotifier]),
            builder: (context, _) {
              final isMultiSelectMode = _isMultiSelectNotifier.value;
              final selectedItems = _selectedItemsNotifier.value;
              if (isMultiSelectMode) {
                return AppBar(
                  leading: IconButton(
                    icon: const Icon(LucideIcons.x),
                    tooltip: 'Cancel',
                    onPressed: _cancelMultiSelect,
                  ),
                  title: Text('${selectedItems.length} Selected'),
                  backgroundColor: surfaceColor,
                  actions: [
                    // TODO show storage details: file id, storage provider, parts, reference counts
                    if (selectedItems.length == 1 &&
                        !selectedItems.first.isFolder)
                      IconButton(
                        icon: const Icon(LucideIcons.info),
                        tooltip: 'Info',
                        onPressed: showInfo,
                      ),
                    IconButton(
                      icon: const Icon(LucideIcons.downloadCloud),
                      tooltip: 'Download',
                      onPressed: downloadItems,
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.archive),
                      tooltip: 'Archive',
                      onPressed: trashItems,
                    ),
                  ],
                );
              }

              // Default AppBar
              return AppBar(
                leading: currentItem?.id != 'fife'
                    ? IconButton(
                        icon: const Icon(LucideIcons.arrowLeft),
                        onPressed: _navigateBack)
                    : null,
                title: buildBreadcrumb(),
                backgroundColor: surfaceColor,
                actions: [
                  if (_isLocalPath)
                    IconButton(
                        icon: const Icon(LucideIcons.refreshCw),
                        onPressed: _syncRootFolders),
                  if (_isDeviceRoot)
                    IconButton(
                        icon: const Icon(LucideIcons.plus),
                        onPressed: addSyncFolder),
                  PopupMenuButton<int>(
                    icon: const Icon(LucideIcons.moreVertical),
                    onSelected: (value) {
                      switch (value) {
                        case 0:
                          signout();
                          break;
                        case 1:
                          showArchives();
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem<int>(
                        value: 0,
                        child: Row(
                          children: [
                            const Icon(LucideIcons.logOut, color: Colors.grey),
                            const SizedBox(width: 16),
                            const Text('Signout'),
                          ],
                        ),
                      ),
                      PopupMenuItem<int>(
                        value: 1,
                        child: Row(
                          children: [
                            const Icon(LucideIcons.archive, color: Colors.grey),
                            const SizedBox(width: 16),
                            const Text('Trash'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              );
            }));
  }

  Future<void> _addSyncFolder(String folderPath) async {
    String folderName = path_lib.basename(folderPath);
    String deviceRoot = await getDeviceHash();
    ModelItem syncFolderItem = await ModelItem.fromMap({
      "parent_id": deviceRoot,
      "path": folderPath,
      "name": folderName,
      "is_folder": 1,
    });
    await syncFolderItem.insert();
    final reconService = ReconciliationService();
    await reconService.reconcile(syncFolderItem.id);
    _loadFiles();
  }

  void addFolderConfirm(String folderPath) {
    String folderName = path_lib.basename(folderPath);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Add folder"),
        content: Text(folderName),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _addSyncFolder(folderPath);
            },
            child: Text('Confirm'),
          ),
        ],
      ),
    );
  }

  Future<void> addSyncFolder() async {
    String? folderPath = await getSelectFolderWithReadWritePermission();
    if (folderPath != null) {
      bool folderPathExists = await ModelItem.syncFolderExists(folderPath);
      if (!folderPathExists) {
        addFolderConfirm(folderPath);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _buildFileView(),
        ),
        _buildAppBar()
      ],
    );
  }

  Widget _buildFileView() {
    return ValueListenableBuilder<List<ModelItem>>(
        valueListenable: _itemsNotifier,
        builder: (context, items, _) {
          if (items.isEmpty) {
            return const Center(child: Text('This Folder is empty.'));
          }
          return ListView.builder(
            reverse: true,
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];

              return _FileListItem(
                key: ValueKey(item.id),
                item: item,
                selectedItemsNotifier: _selectedItemsNotifier,
                isMultiSelectNotifier: _isMultiSelectNotifier,
                onTap: () => _onTap(item),
                onLongPress: () => _onLongPress(item),
              );
            },
          );
        });
  }
}

Future<String?> getSelectFolderWithReadWritePermission() async {
  // Request storage permission for Android
  if (Platform.isAndroid) {
    // Android 13+ uses granular media permissions
    if (await _isAndroid13OrAbove()) {
      // For Android 13+, file_picker handles permissions internally
      // when user selects via SAF (Storage Access Framework)
      return await FilePicker.platform.getDirectoryPath();
    } else {
      // For Android 12 and below
      final status = await Permission.storage.request();

      if (status.isGranted) {
        return await FilePicker.platform.getDirectoryPath();
      }
    }
  }

  // iOS doesn't require explicit permissions for user-selected directories
  if (Platform.isIOS) {
    return await FilePicker.platform.getDirectoryPath();
  }

  // Desktop platforms (Windows, macOS, Linux) don't use runtime permissions
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    try {
      final String? selectedDirectory =
          await FilePicker.platform.getDirectoryPath();

      if (selectedDirectory != null) {
        // Test write access by attempting to create a temp file
        final testFile = File('$selectedDirectory/.test_write_access');
        await testFile.writeAsString('test');
        await testFile.delete();

        return selectedDirectory;
      } else {
        return null;
      }
    } on FileSystemException catch (e, s) {
      AppLogger(prefixes: ["GetFolderWithPermission"])
          .error("Permission denied or access error", error: e, stackTrace: s);
      return null;
    }
  }

  return null;
}

Future<bool> _isAndroid13OrAbove() async {
  if (Platform.isAndroid) {
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    return androidInfo.version.sdkInt >= 33;
  }
  return false;
}

class _FileListItem extends StatefulWidget {
  final ModelItem item;
  final ValueNotifier<Set<ModelItem>> selectedItemsNotifier;
  final ValueNotifier<bool> isMultiSelectNotifier;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _FileListItem({
    super.key,
    required this.item,
    required this.selectedItemsNotifier,
    required this.isMultiSelectNotifier,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  State<_FileListItem> createState() => _FileListItemState();
}

class _FileListItemState extends State<_FileListItem> {
  bool? _isLocal;
  bool? _isUploaded;
  bool _isUploading = false;
  bool _isDownloading = false;
  double transferProgress = 0.0;
  AppLogger logger = AppLogger(prefixes: ["FileListItem"]);

  @override
  void initState() {
    super.initState();
    if (!widget.item.isFolder) {
      _checkFileStates();
    }
    EventStream().notifier.addListener(_handleItemUpdateEvent);
  }

  @override
  void didUpdateWidget(covariant _FileListItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-check statuses if the underlying item changes (e.g., during recycling in ListView)
    if (oldWidget.item.id != widget.item.id && !widget.item.isFolder) {
      _checkFileStates();
    }
  }

  @override
  void dispose() {
    EventStream().notifier.removeListener(_handleItemUpdateEvent);
    super.dispose();
  }

  void _handleItemUpdateEvent() {
    final AppEvent? event = EventStream().notifier.value;
    if (event == null) return;

    switch (event.type) {
      case EventType.updateItem:
        if (event.key == EventKey.uploaded) {
          if (event.id == widget.item.id) {
            setState(() {
              _isUploaded = true;
              _isUploading = false;
            });
          }
        } else if (event.key == EventKey.downloaded) {
          if (event.id == widget.item.id) {
            setState(() {
              _isLocal = true;
              _isDownloading = false;
            });
          }
        } else if (event.key == EventKey.uploadProgress) {
          if (event.id == widget.item.id) {
            setState(() {
              transferProgress = event.value;
              _isUploading = true;
            });
          }
        } else if (event.key == EventKey.downloadProgress) {
          if (event.id == widget.item.id) {
            setState(() {
              transferProgress = event.value;
              _isDownloading = true;
            });
          }
        }
        break;
    }
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

  Future<bool> isUploading(ModelItem item) async {
    ModelItemTask? itemTask = await ModelItemTask.get(item.id);
    if (itemTask != null) {
      return itemTask.task == ItemTask.upload.value;
    } else {
      return false;
    }
  }

  Future<bool> isDownloading(ModelItem item) async {
    ModelItemTask? itemTask = await ModelItemTask.get(item.id);
    if (itemTask != null) {
      return itemTask.task == ItemTask.upload.value;
    } else {
      return false;
    }
  }

  Future<void> _checkFileStates() async {
    // Run both async tasks concurrently for optimal performance
    final results = await Future.wait([
      fileExistsLocally(widget.item),
      widget.item.isFolder
          ? Future.value(false)
          : fileUploadedToCloud(widget.item),
      isUploading(widget.item),
      isDownloading(widget.item)
    ]);

    // Always check if the widget is still in the tree before calling setState
    if (!mounted) return;

    setState(() {
      _isLocal = results[0];
      _isUploaded = results[1];
      _isUploading = results[2];
      _isDownloading = results[3];
    });
  }

  Widget _buildTrailingIndicator() {
    if (_isUploading || _isDownloading) {
      return TransferAnimatedIcon(isUpload: _isUploading);
    }
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
    return ListenableBuilder(
        listenable: Listenable.merge(
            [widget.selectedItemsNotifier, widget.isMultiSelectNotifier]),
        builder: (context, _) {
          final isSelected =
              widget.selectedItemsNotifier.value.contains(widget.item);
          final isMultiSelectMode = widget.isMultiSelectNotifier.value;
          final theme = Theme.of(context);

          return Stack(children: [
            // --- 1. Progress Background ---
            Positioned.fill(
              child: Align(
                // Automatically handles LTR (starts left) and RTL (starts right)
                alignment: AlignmentDirectional.centerStart,
                // Smoothly animates the width changes as data arrives
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: transferProgress),
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) {
                    return FractionallySizedBox(
                      widthFactor: value,
                      heightFactor: 1.0,
                      child: Container(
                        // Using a subtle primary container color for the progress fill
                        color: theme.colorScheme.primaryContainer.withAlpha(70),
                      ),
                    );
                  },
                ),
              ),
            ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onTap,
                onLongPress: widget.onLongPress,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8.0, vertical: 8.0),
                  child: Row(
                    children: [
                      // 1. Multi-Select Circular Checkbox
                      AnimatedSize(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOutCubic,
                        child: SizedBox(
                          width: 18,
                          child: isMultiSelectMode
                              ? Row(
                                  children: [
                                    AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 200),
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: isSelected
                                            ? Colors.grey.shade600
                                            : Colors.transparent,
                                        border: Border.all(
                                          color: isSelected
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
                            if (widget.item.isFolder)
                              Align(
                                alignment: Alignment.center,
                                child: Icon(LucideIcons.folder,
                                    size: 28,
                                    color: theme.colorScheme.primary
                                        .withAlpha(150)),
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
                                        : (_isLocal!
                                            ? Colors.green
                                            : Colors.red),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Theme.of(context)
                                          .scaffoldBackgroundColor,
                                      width: 2,
                                    ),
                                  ),
                                ),
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

                      const SizedBox(width: 8),

                      // 4. State Indicators (Cloud / Local)
                      if (!widget.item.isFolder) _buildTrailingIndicator()
                    ],
                  ),
                ),
              ),
            )
          ]);
        });
  }
}

class TransferAnimatedIcon extends StatefulWidget {
  final bool isUpload;

  const TransferAnimatedIcon({super.key, required this.isUpload});

  @override
  State<TransferAnimatedIcon> createState() => _TransferAnimatedIconState();
}

class _TransferAnimatedIconState extends State<TransferAnimatedIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _slideAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    // Arrow slides from center to edge
    _slideAnimation = Tween<double>(begin: -0.5, end: 0.5).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    // Arrow fades in at the start, and fades out at the end of the slide
    _fadeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 30),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 30),
    ]).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Swap direction based on Upload vs Download
    final yDirectionMultiplier = widget.isUpload ? -1.0 : 1.0;

    return SizedBox(
      width: 24,
      height: 24,
      child: ClipRect(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return FractionalTranslation(
              translation:
                  Offset(0, _slideAnimation.value * yDirectionMultiplier),
              child: Opacity(
                opacity: _fadeAnimation.value,
                child: Icon(
                  widget.isUpload
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded,
                  color: Theme.of(context).colorScheme.primary,
                  size: 14,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
