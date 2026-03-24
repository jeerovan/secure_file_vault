import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_vault_bb/utils/utils_sync.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../models/model_file.dart';
import '../../models/model_item.dart';
import '../../services/service_logger.dart';
import '../../services/service_recon.dart';
import '../../utils/common.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path_lib;

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';

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
  List<ModelItem> _items = [];
  ModelItem? currentItem;
  bool _isLoading = false;
  bool _isLocalPath = false;
  bool _isDeviceRoot = false;
  List<ModelItem> parentChilds = [];
  // Multi-select state
  bool _isMultiSelectMode = false;
  final Set<String> _selectedItemIds = {};

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  @override
  void dispose() {
    _breadcrumbController.dispose();
    super.dispose();
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
    final items = await ModelItem.getAllInFolder(currentItem);
    _isLocalPath = await ModelItem.isLocalPath(currentItem!.id);
    String deviceRootHash = await getDeviceHash();
    _isDeviceRoot = currentItem?.id == deviceRootHash;
    if (mounted) {
      setState(() {
        _items = items;
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

  void _navigateTo(ModelItem item) {
    if (_isMultiSelectMode) {
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
    if (!_isMultiSelectMode) {
      setState(() {
        _isMultiSelectMode = true;
        _selectedItemIds.add(item.id);
      });
    }
  }

  void _toggleSelection(ModelItem item) {
    setState(() {
      if (_selectedItemIds.contains(item.id)) {
        _selectedItemIds.remove(item.id);
        if (_selectedItemIds.isEmpty) {
          _isMultiSelectMode = false; // Exit mode if nothing is selected
        }
      } else {
        _selectedItemIds.add(item.id);
      }
    });
  }

  void _cancelMultiSelect() {
    setState(() {
      _isMultiSelectMode = false;
      _selectedItemIds.clear();
    });
  }

  Future<void> trashItems() async {
    logger.log('Archiving/Trashing ${_selectedItemIds.length} items');
    // TODO: Implement your trash/archive logic here utilizing _selectedItemIds

    _cancelMultiSelect();
    _loadFiles(); // Refresh view
  }

  Future<void> downloadItems() async {
    logger.log('Downloading ${_selectedItemIds.length} items');
    // TODO: Implement your download logic here utilizing _selectedItemIds

    _cancelMultiSelect();
  }

  PreferredSizeWidget _buildAppBar() {
    final surfaceColor = Theme.of(context).colorScheme.surfaceContainerHighest;

    if (_isMultiSelectMode) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.x),
          onPressed: _cancelMultiSelect,
        ),
        title: Text('${_selectedItemIds.length} Selected'),
        backgroundColor: surfaceColor,
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.download),
            tooltip: 'Download',
            onPressed: downloadItems,
          ),
          IconButton(
            icon: const Icon(LucideIcons.trash2),
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
              icon: const Icon(LucideIcons.arrowLeft), onPressed: _navigateBack)
          : null,
      title: _buildBreadcrumb(),
      backgroundColor: surfaceColor,
      actions: [
        if (_isLocalPath)
          IconButton(
              icon: const Icon(LucideIcons.refreshCw),
              onPressed: _syncRootFolders),
        if (_isDeviceRoot)
          IconButton(
              icon: const Icon(LucideIcons.plus), onPressed: addSyncFolder),
        PopupMenuButton<int>(
          icon: const Icon(LucideIcons.moreVertical),
          onSelected: (value) {
            switch (value) {
              case 0:
                // context.read<AppSetupState>().logout();
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
          ],
        ),
      ],
    );
  }

  Widget _buildBreadcrumb() {
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
          onTap: () => {_navigateTo(item)},
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
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
        breadcrumbWidgets.add(Icon(Icons.chevron_right,
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
              : _items.isEmpty
                  ? const Center(child: Text('This folder is empty.'))
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
        final isSelected = _selectedItemIds.contains(item.id);
        return _FileListItem(
          key: Key(item.id),
          item: item,
          isMultiSelectMode: _isMultiSelectMode,
          isSelected: isSelected,
          onTap: () => _navigateTo(item),
          onLongPress: () => _onLongPress(item),
        );
      },
    );
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
  final bool isMultiSelectMode;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _FileListItem({
    super.key,
    required this.item,
    required this.isMultiSelectMode,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  State<_FileListItem> createState() => _FileListItemState();
}

class _FileListItemState extends State<_FileListItem> {
  bool? _isLocal;
  bool? _isUploaded;
  AppLogger logger = AppLogger(prefixes: ["FileListItem"]);

  @override
  void initState() {
    super.initState();
    if (!widget.item.isFolder) _checkFileStates();
  }

  @override
  void didUpdateWidget(covariant _FileListItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-check statuses if the underlying item changes (e.g., during recycling in ListView)
    if (oldWidget.item.id != widget.item.id && !widget.item.isFolder) {
      _checkFileStates();
    }
  }

  Future<bool> fileExistsLocally(ModelItem item) async {
    String path = await ModelItem.getPathForItem(item.id);
    AppLogger(prefixes: ["FileListItem"]).debug(path);
    return await File(path).exists();
  }

  Future<bool> fileUploadedToCloud(ModelItem item) async {
    ModelFile? modelFile = await ModelFile.get(item.fileId!);
    if (modelFile != null) {
      return modelFile.uploadedAt > 0;
    }
    return false;
  }

  Future<void> _checkFileStates() async {
    // Run both async tasks concurrently for optimal performance
    final results = await Future.wait([
      fileExistsLocally(widget.item),
      widget.item.isFolder
          ? Future.value(false)
          : fileUploadedToCloud(widget.item),
    ]);

    // Always check if the widget is still in the tree before calling setState
    if (!mounted) return;

    setState(() {
      _isLocal = results[0];
      _isUploaded = results[1];
    });
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
                width: 32,
                height: 32,
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
                          color: widget.item.isFolder
                              ? theme.colorScheme.primary.withAlpha(150)
                              : theme.colorScheme.secondary.withAlpha(150)),
                    ),

                    // Local Existence Indicator (Grey while loading, then Red/Green)
                    if (!widget.item.isFolder)
                      Positioned(
                        bottom: -2,
                        right: -2,
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

              const SizedBox(width: 16),

              // 3. File Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.item.name,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // 4. State Indicators (Cloud / Local)
              if (!widget.item.isFolder) _buildTrailingIndicator()
            ],
          ),
        ),
      ),
    );
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
}
