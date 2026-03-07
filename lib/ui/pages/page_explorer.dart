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

enum ViewType { list, grid }

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
  ViewType _viewType = ViewType.list;
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
      currentItem = await ModelItem.get(await getDeviceId());
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
      String deviceId = await getDeviceId();
      ModelItem syncFolderItem = await ModelItem.fromMap({
        "parent_id": deviceId,
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
            IconButton(
              icon: Icon(_viewType == ViewType.list
                  ? Icons.grid_view
                  : Icons.view_list),
              onPressed: () => setState(() => _viewType =
                  _viewType == ViewType.list ? ViewType.grid : ViewType.list),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFileView() {
    if (_viewType == ViewType.grid) {
      return GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 150,
            childAspectRatio: 0.9,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8),
        itemCount: _items.length,
        itemBuilder: (context, index) {
          final item = _items[index];
          return _FileGridItem(
              item: item,
              onTap: () => _navigateTo(item),
              onLongPress: item.isFolder ? () => _onLongPress(item) : null,
              onDrop: widget.onItemDrop);
        },
      );
    } else {
      return ListView.builder(
        itemCount: _items.length,
        itemBuilder: (context, index) {
          final item = _items[index];
          return _FileListItem(
              item: item,
              onTap: () => _navigateTo(item),
              onLongPress: item.isFolder ? () => _onLongPress(item) : null,
              onDrop: widget.onItemDrop);
        },
      );
    }
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
      // Permission denied or access error
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

// --- UI Widgets for Items (with updated DragTarget) ---

class _FileListItem extends StatelessWidget {
  final ModelItem item;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Function(ModelItem item, ModelItem destination) onDrop;

  const _FileListItem(
      {required this.item,
      required this.onTap,
      this.onLongPress,
      required this.onDrop});

  Widget _buildItem() {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: ListTile(
        leading: Icon(
            item.isFolder ? Icons.folder : Icons.insert_drive_file_outlined),
        title: Text(item.name, overflow: TextOverflow.ellipsis),
        trailing: item.isFolder
            ? Icon(Icons.cloud_done,
                color: Colors.tealAccent.shade400, size: 20)
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final draggableItem = LongPressDraggable<ModelItem>(
      data: item,
      feedback: Opacity(
          opacity: 0.7,
          child: Card(
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 250),
                  child: _buildItem()))),
      child: _buildItem(),
    );

    if (item.isFolder) {
      return DragTarget<ModelItem>(
        builder: (context, candidateData, rejectedData) => draggableItem,
        onWillAcceptWithDetails: (details) => details.data.id != item.id,
        onAcceptWithDetails: (details) => onDrop(details.data, item),
      );
    }
    return draggableItem;
  }
}

class _FileGridItem extends StatelessWidget {
  final ModelItem item;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Function(ModelItem item, ModelItem destination) onDrop;

  const _FileGridItem(
      {required this.item,
      required this.onTap,
      this.onLongPress,
      required this.onDrop});

  Widget _buildItem(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(12),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  item.isFolder
                      ? Icons.folder
                      : Icons.insert_drive_file_outlined,
                  size: 48,
                  color: item.isFolder
                      ? Colors.amber.shade600
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: Text(item.name,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall),
                ),
              ],
            ),
            if (item.isFolder)
              Positioned(
                  top: 6,
                  right: 6,
                  child: Icon(Icons.cloud_done,
                      color: Colors.tealAccent.shade400, size: 16)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final draggableItem = LongPressDraggable<ModelItem>(
      data: item,
      feedback: Transform.scale(
          scale: 1.1,
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140, maxHeight: 120),
              child: Opacity(opacity: 0.7, child: _buildItem(context)))),
      child: _buildItem(context),
    );

    if (item.isFolder) {
      return DragTarget<ModelItem>(
        builder: (context, candidateData, rejectedData) => draggableItem,
        onWillAcceptWithDetails: (details) => details.data.id != item.id,
        onAcceptWithDetails: (details) => onDrop(details.data, item),
      );
    }
    return draggableItem;
  }
}
