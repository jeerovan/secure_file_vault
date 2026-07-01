import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/ui/pages/page_logs.dart';
import 'package:file_vault_bb/ui/pages/page_sqlite.dart';
import 'package:file_vault_bb/ui/pages/page_subscription.dart';
import 'package:sodium/sodium_sumo.dart';

import '../../l10n/app_localizations.dart';
import '../../storage/storage_channel.dart';
import '../../ui/pages/page_devices.dart';
import '../../ui/pages/page_file_info.dart';
import '../../ui/pages/page_search.dart';
import '../../ui/pages/page_settings.dart';
import '../../ui/pages/page_storage_providers.dart';
import '../../ui/pages/page_trash.dart';
import '../../utils/enums.dart';
import '../../utils/utils_sync.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';
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

import '../../utils/utils_tasks.dart';
import '../common_widgets.dart';

class PageExplorer extends StatefulWidget {
  final Function(String?) onThemeChange;
  const PageExplorer({
    super.key,
    required this.onThemeChange,
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
          return FilePane(
            onThemeChange: widget.onThemeChange,
          );
        },
      ),
    );
  }
}

// --- File Pane Widget ---

class FilePane extends StatefulWidget {
  final Function(String?) onThemeChange;
  const FilePane({
    super.key,
    required this.onThemeChange,
  });

  @override
  State<FilePane> createState() => _FilePaneState();
}

class _FilePaneState extends State<FilePane> {
  final AppLogger logger = AppLogger(prefixes: ["Explorer"]);
  final ScrollController _breadcrumbController = ScrollController();
  final ValueNotifier<List<ModelItem>> _itemsNotifier = ValueNotifier([]);
  final ValueNotifier<Set<ModelItem>> _selectedItemsNotifier =
      ValueNotifier({});
  final ValueNotifier<bool> _isMultiSelectNotifier = ValueNotifier(false);

  ModelItem? currentItem;
  bool _isLoading = false;
  bool _isLocalPath = false;
  bool _isDeviceRoot = false;
  bool _syncInProgress = false;
  bool _loggingEnabled =
      ModelSetting.get(AppString.loggingEnabled.string, defaultValue: "no") ==
          "yes";
  bool _storageFull =
      ModelSetting.get(AppString.storageFull.string, defaultValue: "no") ==
          "yes";
  List<ModelItem> parentChilds = [];
  String? deviceHash;
  @override
  void initState() {
    super.initState();
    EventStream().notifier.addListener(_handleAppEvents);
    _loadFiles();
    _syncRootFolders();
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
      case EventType.syncStatus:
        if (event.key == EventKey.running) {
          if (mounted) {
            setState(() {
              _syncInProgress = true;
            });
          }
        } else if (event.key == EventKey.stopped) {
          if (mounted) {
            setState(() {
              _syncInProgress = false;
            });
          }
        } else if (event.key == EventKey.storageFull) {
          if (mounted) {
            _storageFull = event.id == "yes";
          }
        }
        break;
      case EventType.settings:
        if (event.key == EventKey.logging) {
          _loggingEnabled = event.id == "yes";
        }
        break;
      case EventType.system:
        if (event.key == EventKey.signout) {
          context.read<AppSetupState>().recheckStatus();
        }
        break;
    }
  }

  Future<void> _loadFiles() async {
    if (currentItem == null) {
      deviceHash = await getDeviceHash();
      ModelItem? rootFife = await ModelItem.get("fife");
      if (rootFife != null) {
        parentChilds.add(rootFife);
      }
      currentItem = await ModelItem.get(deviceHash!);
      if (currentItem != null) parentChilds.add(currentItem!);
    }
    if (currentItem == null) {
      return;
    }

    if (mounted) {
      setState(() => _isLoading = true);
    }
    final items = await ModelItem.getDisplayItems(currentItem);
    _isLocalPath = await ModelItem.isLocalPath(currentItem!.id);
    String deviceRootHash = await getDeviceHash();
    _isDeviceRoot = currentItem?.id == deviceRootHash;
    if (mounted) {
      setState(() {
        _itemsNotifier.value = items;
        _isLoading = false;
      });
    }
  }

  Future<void> _syncRootFolders() async {
    if (_syncInProgress) {
      return;
    }
    setState(() {
      _syncInProgress = true;
    });
    await SyncUtils().reconFolders(caller: "Explorer");
    _loadFiles();
  }

  Future<void> _onTap(ModelItem item) async {
    if (Platform.isIOS || Platform.isMacOS) {
      String deviceHash = await getDeviceHash();
      if (item.parentId == deviceHash) {
        if (item.bookmark == null ||
            (item.bookmark != null && item.bookmark!.isEmpty)) {
          if (item.path != null) {
            addSyncFolder(initialDirectory: item.path);
            return;
          }
        }
      }
    }

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
        if (mounted) {
          displaySnackBar(context,
              message: AppLocalizations.of(context)!.longPressToDownload,
              seconds: 2);
        }
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
    if (currentItem != null && currentItem!.id == 'fife') {
      return;
    }
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

  Future<void> deleteLocal() async {
    final selectedItems = List<ModelItem>.from(_selectedItemsNotifier.value);
    logger.log('Deleting local copy ${selectedItems.length} items');
    if (!_isLocalPath) {
      for (ModelItem modelItem in selectedItems) {
        String localPath = await ModelItem.getPathForItem(modelItem.id);
        await clearPathContents(localPath);
      }
    }
    _cancelMultiSelect();
    _loadFiles();
  }

  Future<void> trashItems() async {
    final currentItems = List<ModelItem>.from(_itemsNotifier.value);
    final toRemove = [];
    final selectedItems = List<ModelItem>.from(_selectedItemsNotifier.value);
    logger.log('Trashing ${selectedItems.length} items');
    bool locallyExists = false;
    if (_isLocalPath) {
      for (ModelItem modelItem in selectedItems) {
        bool isFolder = modelItem.isFolder;
        bool addToRemove = false;
        String localPath = await ModelItem.getPathForLocalItem(modelItem.id);
        if (isFolder) {
          Directory directory = Directory(localPath);
          if (!directory.existsSync()) {
            addToRemove = true;
          } else {
            locallyExists = true;
          }
        } else {
          if (!File(localPath).existsSync()) {
            addToRemove = true;
          } else {
            locallyExists = true;
          }
        }
        if (addToRemove) {
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
        // Delete local copy
        String localPath = await ModelItem.getPathForItem(modelItem.id);
        clearPathContents(localPath);
      }
    }
    currentItems.removeWhere((item) => toRemove.contains(item));
    _itemsNotifier.value = currentItems;
    _cancelMultiSelect();
    if (locallyExists && mounted) {
      displaySnackBar(context,
          message: AppLocalizations.of(context)!.fewItemsExistLocally,
          seconds: 2);
    }
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
      }
    }
    if (hasTasks) {
      TaskManager.init(inBackground: false);
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

  Future<void> showArchives() async {
    Navigator.of(context).push(AnimatedPageRoute(child: const PageTrash()));
  }

  Future<void> showDevices() async {
    Navigator.of(context)
        .push(AnimatedPageRoute(child: const PageDevices(onStack: true)));
  }

  Future<void> showStorageProviders() async {
    Navigator.of(context)
        .push(AnimatedPageRoute(child: const StorageProvidersScreen()));
  }

  Future<void> showSearchScreen() async {
    Navigator.of(context).push(AnimatedPageRoute(child: const SearchScreen()));
  }

  Future<void> showSettingScreen() async {
    Navigator.of(context).push(AnimatedPageRoute(
        child: SettingsPage(
      onThemeChange: widget.onThemeChange,
    )));
  }

  Future<void> showLogsScreen() async {
    Navigator.of(context).push(AnimatedPageRoute(child: const PageLogs()));
  }

  Future<void> showSubscriptionScreen() async {
    Navigator.of(context)
        .push(AnimatedPageRoute(child: const SubscriptionPage()));
  }

  Future<void> showDatabase() async {
    Navigator.of(context).push(AnimatedPageRoute(child: const PageSqlite()));
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
              if (!_isLocalPath)
                IconButton(
                  icon: const Icon(LucideIcons.trash),
                  tooltip: AppLocalizations.of(context)!.delete,
                  onPressed: deleteLocal,
                ),
              if (selectedItems.length == 1 && !selectedItems.first.isFolder)
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

        // Default Mode
        return buildBottomAppBar(
          color: surfaceColor,
          leading: currentItem?.id != 'fife'
              ? IconButton(
                  icon: const Icon(LucideIcons.arrowLeft),
                  onPressed: _navigateBack)
              : null,
          title: BreadcrumbTrail(
            parentChilds: parentChilds,
            onTap: _onTap, // Ensure _onTap matches the expected signature
          ),
          actions: [
            if (_isDeviceRoot && !_syncInProgress)
              IconButton(
                  icon: const Icon(LucideIcons.plus), onPressed: addSyncFolder),
            if (_isLocalPath)
              AnimatedSyncButton(
                  isSyncing: _syncInProgress, onPressed: _syncRootFolders),
            PopupMenuButton<int>(
              icon: Stack(
                children: [
                  const Icon(LucideIcons.moreVertical),
                  if (_storageFull)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              onSelected: (value) {
                if (value == 1) showArchives();
                if (value == 2) showDevices();
                if (value == 3) showStorageProviders();
                if (value == 4) showSearchScreen();
                if (value == 5) showSettingScreen();
                if (value == 6) showLogsScreen();
                if (value == 7) showSubscriptionScreen();
                if (value == 8) showDatabase();
              },
              itemBuilder: (context) => [
                PopupMenuItem<int>(
                  value: 7,
                  child: Row(
                    children: [
                      Icon(LucideIcons.dollarSign, color: Colors.grey),
                      SizedBox(width: 16),
                      Text(
                        AppLocalizations.of(context)!
                            .appPro(AppString.appName.string),
                      ),
                    ],
                  ),
                ),
                if (_loggingEnabled)
                  PopupMenuItem<int>(
                    value: 6,
                    child: Row(
                      children: [
                        Icon(LucideIcons.tableProperties, color: Colors.grey),
                        SizedBox(width: 16),
                        Text(AppLocalizations.of(context)!.logs)
                      ],
                    ),
                  ),
                PopupMenuItem<int>(
                  value: 5,
                  child: Row(
                    children: [
                      Icon(LucideIcons.settings, color: Colors.grey),
                      SizedBox(width: 16),
                      Text(AppLocalizations.of(context)!.settings)
                    ],
                  ),
                ),
                PopupMenuItem<int>(
                  value: 1,
                  child: Row(
                    children: [
                      Icon(LucideIcons.archive, color: Colors.grey),
                      SizedBox(width: 16),
                      Text(AppLocalizations.of(context)!.trash)
                    ],
                  ),
                ),
                PopupMenuItem<int>(
                  value: 2,
                  child: Row(
                    children: [
                      Icon(LucideIcons.monitorSmartphone, color: Colors.grey),
                      SizedBox(width: 16),
                      Text(AppLocalizations.of(context)!.devicesTitle)
                    ],
                  ),
                ),
                PopupMenuItem<int>(
                  value: 3,
                  child: Row(
                    children: [
                      _storageFull
                          ? Icon(LucideIcons.alertTriangle, color: Colors.red)
                          : Icon(LucideIcons.hardDrive, color: Colors.grey),
                      SizedBox(width: 16),
                      Text(AppLocalizations.of(context)!.storage)
                    ],
                  ),
                ),
                PopupMenuItem<int>(
                  value: 4,
                  child: Row(
                    children: [
                      Icon(LucideIcons.search, color: Colors.grey),
                      SizedBox(width: 16),
                      Text(AppLocalizations.of(context)!.search)
                    ],
                  ),
                ),
                if (isDebugEnabled)
                  PopupMenuItem<int>(
                    value: 8,
                    child: Row(
                      children: [
                        Icon(LucideIcons.database, color: Colors.grey),
                        SizedBox(width: 16),
                        Text(AppLocalizations.of(context)!.database)
                      ],
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  Future<void> _addSyncFolder(String folderPath, String? bookmark) async {
    String folderName = path_lib.basename(folderPath);
    String deviceRoot = await getDeviceHash();
    ModelItem syncFolderItem = await ModelItem.fromMap({
      "parent_id": deviceRoot,
      "path": folderPath,
      "name": folderName,
      "is_folder": 1,
      "bookmark": bookmark
    });
    await syncFolderItem.insert();
    await reconFolder(syncFolderItem);
  }

  Future<void> reconFolder(ModelItem item) async {
    if (mounted) {
      setState(() {
        _syncInProgress = true;
      });
    }
    SodiumSumo sodium = await SodiumSumoInit.init();
    final reconService = ReconciliationService(sodium);
    await reconService.reconcile(item);
    _loadFiles();
    SyncUtils.waitAndSyncChanges("Explorer");
  }

  void addFolderConfirm(String folderPath, String? bookmark) {
    String folderName = path_lib.basename(folderPath);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.addFolderTitle),
        content: Text(folderName),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _addSyncFolder(folderPath, bookmark);
            },
            child: Text(AppLocalizations.of(context)!.confirm),
          ),
        ],
      ),
    );
  }

  Future<void> addSyncFolder({String? initialDirectory}) async {
    String? folderPath;
    String? bookmark;
    if (Platform.isIOS) {
      final result = await ChannelStorage.pickDirectory(
          initialDirectory: initialDirectory);
      if (result != null) {
        logger.debug(result.toString());
        folderPath = result["path"];
        bookmark = result["bookmark"];
      }
    } else {
      folderPath = await getSelectFolderWithReadWritePermission(
          initialDirectory: initialDirectory);
      bookmark = "sandboxed";
    }
    if (folderPath != null) {
      ModelItem? existingFolder = await ModelItem.syncFolderExists(folderPath);
      if (existingFolder == null) {
        addFolderConfirm(folderPath, bookmark);
      } else {
        bookmark ??= "sandboxed";
        await ModelItem.updateBookmark(existingFolder.id, bookmark);
        await reconFolder(existingFolder);
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
            if (currentItem != null &&
                deviceHash != null &&
                currentItem?.id == deviceHash) {
              return Center(
                child:
                    Text(AppLocalizations.of(context)!.tapPlusToAddSyncFolder),
              );
            } else {
              return Center(
                child: Text(AppLocalizations.of(context)!.thisFolderIsEmpty),
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
        });
  }
}

class BreadcrumbTrail extends StatefulWidget {
  final List<ModelItem> parentChilds;
  final Function(ModelItem) onTap;

  const BreadcrumbTrail({
    super.key,
    required this.parentChilds,
    required this.onTap,
  });

  @override
  State<BreadcrumbTrail> createState() => _BreadcrumbTrailState();
}

class _BreadcrumbTrailState extends State<BreadcrumbTrail> {
  final ScrollController _scrollController = ScrollController();

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  void initState() {
    super.initState();
    // Fires when the breadcrumb is first built (e.g. exiting multi-select)
    _scrollToEnd();
  }

  @override
  void didUpdateWidget(covariant BreadcrumbTrail oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Fires safely whenever the parent passes a new or mutated path
    _scrollToEnd();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> breadcrumbWidgets = [];

    for (int i = 0; i < widget.parentChilds.length; i++) {
      final item = widget.parentChilds[i];
      final isLast = i == widget.parentChilds.length - 1;
      final colorScheme = Theme.of(context).colorScheme;

      breadcrumbWidgets.add(
        InkWell(
          onTap: () => widget.onTap(item),
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
            child: Text(
              item.name,
              style: TextStyle(
                fontSize: Theme.of(context).textTheme.titleMedium?.fontSize,
                color: isLast
                    ? colorScheme.onSurface
                    : colorScheme.onSurface.withValues(alpha: 0.55),
                fontWeight: isLast ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      );

      if (!isLast) {
        breadcrumbWidgets.add(
          Icon(
            LucideIcons.chevronRight,
            size: 18,
            color: colorScheme.onSurface.withValues(alpha: 0.40),
          ),
        );
      }
    }

    breadcrumbWidgets.add(const SizedBox(width: 16));

    // Wrapped the Row in an intrinsic height/alignment container to
    // guarantee vertical centering regardless of the SingleChildScrollView
    return SizedBox(
      height: 64.0,
      child: SingleChildScrollView(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: breadcrumbWidgets,
        ),
      ),
    );
  }
}

Future<String?> getSelectFolderWithReadWritePermission(
    {String? initialDirectory}) async {
  try {
    final String? selectedDirectory = await FilePicker.platform
        .getDirectoryPath(initialDirectory: initialDirectory);

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
