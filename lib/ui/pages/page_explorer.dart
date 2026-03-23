import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_vault_bb/utils/utils_sync.dart';
import '../../models/model_item.dart';
import '../../services/service_logger.dart';
import '../../services/service_recon.dart';
import '../../ui/common_widgets.dart';
import '../../utils/common.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

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
  static const double _dualPaneBreakpoint = 800.0;

  void _onItemDropped(ModelItem item, ModelItem destination) {
    setState(() {
      //TODO handle move item
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > _dualPaneBreakpoint) {
            return Row(
              children: [
                Expanded(
                    child: FilePane(
                        key: const ValueKey('pane1'),
                        onItemDrop: _onItemDropped)),
                const VerticalDivider(width: 1, thickness: 1),
                Expanded(
                    child: FilePane(
                        key: const ValueKey('pane2'),
                        onItemDrop: _onItemDropped)),
              ],
            );
          } else {
            return FilePane(onItemDrop: _onItemDropped);
          }
        },
      ),
    );
  }
}

// --- File Pane Widget ---

class FilePane extends StatefulWidget {
  final Function(ModelItem item, ModelItem destination) onItemDrop;

  const FilePane({super.key, required this.onItemDrop});

  @override
  State<FilePane> createState() => _FilePaneState();
}

class _FilePaneState extends State<FilePane> {
  final AppLogger logger = AppLogger(prefixes: ["Explorer"]);

  List<ModelItem> _items = [];
  ModelItem? currentItem;
  bool _isLoading = false;
  List<ModelItem> parentChilds = [];

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    if (currentItem == null) {
      ModelItem? rootFife = await ModelItem.get("fife");
      if (rootFife != null) {
        parentChilds.add(rootFife);
      }
      currentItem = await ModelItem.get(await getDeviceRoot());
      if (currentItem != null) parentChilds.add(currentItem!);
    }
    if (currentItem == null) return;
    setState(() => _isLoading = true);
    final items = await ModelItem.getAllInFolder(currentItem);
    if (mounted) {
      setState(() {
        _items = items;
        _isLoading = false;
      });
    }
  }

  Future<void> _syncRootFolder() async {
    final reconService = ReconciliationService();
    await reconService.reconcile(currentItem!.id);
    _loadFiles();
    SyncUtils.waitAndSyncChanges();
  }

  void _navigateTo(ModelItem item) {
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

  void _onLongPress(ModelItem folder) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(folder.name),
        content: Text(folder.isFolder
            ? 'Disable backup for this folder?'
            : 'Enable backup for this folder?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: Text(folder.isFolder ? 'Disable' : 'Enable'),
          ),
        ],
      ),
    );
  }

  Widget _buildBreadcrumb() {
    List<Widget> breadcrumbWidgets = [];
    String cumulativePath = '/';

    for (int i = 0; i < parentChilds.length; i++) {
      ModelItem item = parentChilds[i];
      final part = item.name;
      final isLast = i == parentChilds.length - 1;
      final path = (i == 0) ? '/' : '$cumulativePath$part/';

      if (i > 0) cumulativePath += '$part/';

      breadcrumbWidgets.add(
        InkWell(
          onTap: () => {_navigateTo(item)},
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
            child: Text(
              part.isEmpty ? 'Home' : part,
              style: TextStyle(
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

    return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: breadcrumbWidgets));
  }

  Future<void> addSyncFolder() async {
    String? folderPath = await getSelectFolderWithReadWritePermission();
    if (folderPath != null) {
      String folderName = path.basename(folderPath);
      String deviceRoot = await getDeviceRoot();
      ModelItem syncFolderItem = await ModelItem.fromMap({
        "parent_id": deviceRoot,
        "path": folderPath,
        "name": folderName,
        "is_folder": 1,
      });
      await syncFolderItem.insert();
      _loadFiles();
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
        AppBar(
          leading: currentItem?.id != 'fife'
              ? IconButton(
                  icon: const Icon(Icons.arrow_back), onPressed: _navigateBack)
              : null,
          title: _buildBreadcrumb(),
          backgroundColor:
              Theme.of(context).colorScheme.surfaceContainerHighest,
          actions: [
            if (currentItem?.path != null)
              IconButton(icon: Icon(Icons.sync), onPressed: _syncRootFolder),
            IconButton(icon: Icon(Icons.add), onPressed: addSyncFolder),
            IconButton(
              icon: Icon(Icons.logout),
              onPressed: () async =>
                  {await context.read<AppSetupState>().logout()},
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFileView() {
    return ListView.builder(
      itemCount: _items.length,
      itemBuilder: (context, index) {
        final item = _items[index];
        return _FileListItem(
          item: item,
          onTap: () => _navigateTo(item),
          onLongPress: item.isFolder ? () => _onLongPress(item) : null,
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
    } on FileSystemException catch (e) {
      // TODO Permission denied or access error
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
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _FileListItem({
    super.key,
    required this.item,
    required this.onTap,
    this.onLongPress,
  });

  @override
  State<_FileListItem> createState() => _FileListItemState();
}

class _FileListItemState extends State<_FileListItem> {
  bool? _isLocal;
  bool? _isUploaded;

  @override
  void initState() {
    super.initState();
    if (!widget.item.isFolder) _loadStatuses();
  }

  @override
  void didUpdateWidget(covariant _FileListItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-fetch only if the item instance actually changes
    if (oldWidget.item != widget.item && !widget.item.isFolder) {
      _loadStatuses();
    }
  }

  Future<bool> fileExistsLocally(ModelItem item) async {
    return true;
  }

  Future<bool> fileUploadedToCloud(ModelItem item) async {
    return true;
  }

  Future<void> _loadStatuses() async {
    // Reset state to null (loading) if refreshing
    setState(() {
      _isLocal = null;
      _isUploaded = null;
    });

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
    return ListTile(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      leading: SizedBox(
        width: 32,
        height: 32,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Align(
              alignment: Alignment.center,
              child: Icon(
                widget.item.isFolder
                    ? Icons.folder
                    : Icons.insert_drive_file_outlined,
                size: 28,
                color: widget.item.isFolder
                    ? Colors.amber.shade400
                    : Theme.of(context).iconTheme.color,
              ),
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
      title: Text(
        widget.item.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      // Cloud Uploaded Indicator
      trailing: widget.item.isFolder ? null : _buildTrailingIndicator(),
    );
  }

  Widget? _buildTrailingIndicator() {
    if (widget.item.isFolder) return null;

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
        size: 20,
        color: Theme.of(context).colorScheme.primary,
      );
    }

    return null;
  }
}
