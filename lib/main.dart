import 'dart:io';
import 'dart:ui';

import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/services/service_logger.dart';
import 'package:file_vault_bb/storage/storage_sqlite.dart';
import 'package:file_vault_bb/ui/pages/page_signin.dart';
import 'package:file_vault_bb/ui/themes.dart';
import 'package:file_vault_bb/utils/common.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

final logger = AppLogger(prefixes: ["main"]);
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StorageSqlite.initialize(mode: ExecutionMode.appForeground);
  await initializeSupabase();
  runApp(const MainApp());
}

// --- Data Models and Mock Service ---

/// Represents a single item in the file system (file or folder).
class FileItem {
  final String id;
  final String name;
  final String path;
  final bool isFolder;
  bool isBackedUp;

  FileItem({
    required this.id,
    required this.name,
    required this.path,
    this.isFolder = false,
    this.isBackedUp = false,
  });
}

/// A mock service to simulate fetching files and folders.
class FileSystemService {
  static final FileSystemService _instance = FileSystemService._internal();
  factory FileSystemService() => _instance;

  FileSystemService._internal() {
    _initializeMockFileSystem();
  }

  final Map<String, List<FileItem>> _mockFileSystem = {};

  void _initializeMockFileSystem() {
    _mockFileSystem['/'] = [
      FileItem(id: '1', name: 'Documents', path: '/', isFolder: true),
      FileItem(
          id: '2', name: 'Photos', path: '/', isFolder: true, isBackedUp: true),
      FileItem(id: '3', name: 'project_brief.pdf', path: '/'),
      FileItem(id: '4', name: 'logo.png', path: '/'),
    ];
    _mockFileSystem['/Documents/'] = [
      FileItem(id: '5', name: 'Work', path: '/Documents/', isFolder: true),
      FileItem(id: '6', name: 'Personal', path: '/Documents/', isFolder: true),
      FileItem(id: '7', name: 'meeting_notes.txt', path: '/Documents/'),
    ];
    _mockFileSystem['/Documents/Work/'] = [
      FileItem(
          id: '8', name: 'quarterly_report.docx', path: '/Documents/Work/'),
    ];
    _mockFileSystem['/Documents/Personal/'] = [];
    _mockFileSystem['/Photos/'] = [
      FileItem(id: '9', name: 'Vacation', path: '/Photos/', isFolder: true),
      FileItem(id: '10', name: 'Family', path: '/Photos/', isFolder: true),
    ];
    _mockFileSystem['/Photos/Vacation/'] = [
      FileItem(id: '11', name: 'beach.jpg', path: '/Photos/Vacation/'),
      FileItem(id: '12', name: 'mountain.jpg', path: '/Photos/Vacation/'),
    ];
    _mockFileSystem['/Photos/Family/'] = [];
  }

  Future<List<FileItem>> getFilesInPath(String path) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return _mockFileSystem[path] ?? [];
  }

  void toggleBackupStatus(FileItem folder) {
    final item = _findItem(folder.id);
    if (item != null && item.isFolder) {
      item.isBackedUp = !item.isBackedUp;
    }
  }

  void moveItem(FileItem itemToMove, FileItem destinationFolder) {
    if (!destinationFolder.isFolder) return;

    _mockFileSystem[itemToMove.path]
        ?.removeWhere((item) => item.id == itemToMove.id);

    final newPath = '${destinationFolder.path}${destinationFolder.name}/';
    final movedItem = FileItem(
        id: itemToMove.id,
        name: itemToMove.name,
        path: newPath,
        isFolder: itemToMove.isFolder,
        isBackedUp: itemToMove.isBackedUp);

    _mockFileSystem.putIfAbsent(newPath, () => []).add(movedItem);
  }

  FileItem? _findItem(String id) {
    for (var list in _mockFileSystem.values) {
      for (var item in list) {
        if (item.id == id) return item;
      }
    }
    return null;
  }
}

// --- Main Application Widget ---

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> with WidgetsBindingObserver {
  ThemeMode _themeMode = ThemeMode.system;
  late bool _isDarkMode;

  final logger = AppLogger(prefixes: ["MainApp"]);

  @override
  void initState() {
    super.initState();
    // Load the theme from saved preferences
    String? savedTheme = ModelSetting.get("theme", null);
    switch (savedTheme) {
      case "light":
        _themeMode = ThemeMode.light;
        _isDarkMode = false;
        break;
      case "dark":
        _themeMode = ThemeMode.dark;
        _isDarkMode = true;
        break;
      default:
        // Default to system theme
        _themeMode = ThemeMode.system;
        _isDarkMode =
            PlatformDispatcher.instance.platformBrightness == Brightness.dark;
        break;
    }
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    logger.info("App State:$state");
    if (Platform.isIOS || Platform.isAndroid) {
      if (state == AppLifecycleState.resumed) {
        //SyncUtils().startAutoSync();
        logger.info("Started Foreground Sync");
      } else if (state == AppLifecycleState.paused) {
        //SyncUtils().stopAutoSync();
        logger.info("Stopped Foreground Sync");
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Toggle between light and dark modes
  Future<void> _onThemeToggle() async {
    setState(() {
      _themeMode = _isDarkMode ? ThemeMode.light : ThemeMode.dark;
      _isDarkMode = !_isDarkMode;
    });
    await ModelSetting.set("theme", _isDarkMode ? "dark" : "light");
  }

  @override
  Widget build(BuildContext context) {
    bool isLargeScreen = false;
    if (isDebugEnabled) {
      isLargeScreen = MediaQuery.of(context).size.width > 600;
    } else {
      isLargeScreen =
          Platform.isWindows || Platform.isMacOS || Platform.isLinux;
    }
    Widget page = PageSignin(runningOnDesktop: isLargeScreen);
    return ChangeNotifierProvider(
      create: (_) => FontSizeController(),
      child: Builder(builder: (context) {
        return MaterialApp(
          builder: (context, child) {
            final textScaler =
                Provider.of<FontSizeController>(context).textScaler;
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: textScaler,
              ),
              child: child!,
            );
          },
          theme: AppThemes.lightTheme,
          darkTheme: AppThemes.darkTheme,
          themeMode: _themeMode,
          // Uses system theme by default
          home: page,
          debugShowCheckedModeBanner: false,
        );
      }),
    );
  }
}

// --- Main Screen and Layout ---

class FileExplorerScreen extends StatefulWidget {
  const FileExplorerScreen({super.key});

  @override
  State<FileExplorerScreen> createState() => _FileExplorerScreenState();
}

class _FileExplorerScreenState extends State<FileExplorerScreen> {
  final _fileSystem = FileSystemService();
  static const double _dualPaneBreakpoint = 800.0;

  void _onItemDropped(FileItem item, FileItem destination) {
    setState(() {
      _fileSystem.moveItem(item, destination);
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
  final Function(FileItem item, FileItem destination) onItemDrop;

  const FilePane({super.key, required this.onItemDrop});

  @override
  State<FilePane> createState() => _FilePaneState();
}

class _FilePaneState extends State<FilePane> {
  final _fileSystem = FileSystemService();
  List<FileItem> _items = [];
  String _currentPath = '/';
  ViewType _viewType = ViewType.list;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFiles(_currentPath);
  }

  Future<void> _loadFiles(String path) async {
    setState(() => _isLoading = true);
    final items = await _fileSystem.getFilesInPath(path);
    if (mounted) {
      setState(() {
        _currentPath = path;
        _items = items;
        _isLoading = false;
      });
    }
  }

  void _navigateTo(FileItem folder) {
    if (folder.isFolder) {
      _loadFiles('${folder.path}${folder.name}/');
    }
  }

  void _navigateBack() {
    if (_currentPath != '/') {
      final pathSegments = _currentPath.split('/')
        ..removeLast()
        ..removeLast();
      _loadFiles(pathSegments.isEmpty ? '/' : '${pathSegments.join('/')}/');
    }
  }

  void _onLongPress(FileItem folder) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(folder.name),
        content: Text(folder.isBackedUp
            ? 'Disable backup for this folder?'
            : 'Enable backup for this folder?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              setState(() => _fileSystem.toggleBackupStatus(folder));
              Navigator.of(context).pop();
            },
            child: Text(folder.isBackedUp ? 'Disable' : 'Enable'),
          ),
        ],
      ),
    );
  }

  Widget _buildBreadcrumb() {
    final parts = _currentPath.split('/')..removeLast();
    if (parts.isEmpty) parts.add('');

    List<Widget> breadcrumbWidgets = [];
    String cumulativePath = '/';

    for (int i = 0; i < parts.length; i++) {
      final part = parts[i];
      final isLast = i == parts.length - 1;
      final path = (i == 0) ? '/' : '$cumulativePath$part/';

      if (i > 0) cumulativePath += '$part/';

      breadcrumbWidgets.add(
        InkWell(
          onTap: () => _loadFiles(path),
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 4.0),
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
          leading: _currentPath != '/'
              ? IconButton(
                  icon: const Icon(Icons.arrow_back), onPressed: _navigateBack)
              : null,
          title: _buildBreadcrumb(),
          backgroundColor:
              Theme.of(context).colorScheme.surfaceContainerHighest,
          actions: [
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

// --- UI Widgets for Items (with updated DragTarget) ---

class _FileListItem extends StatelessWidget {
  final FileItem item;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Function(FileItem item, FileItem destination) onDrop;

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
        trailing: item.isBackedUp
            ? Icon(Icons.cloud_done,
                color: Colors.tealAccent.shade400, size: 20)
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final draggableItem = LongPressDraggable<FileItem>(
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
      return DragTarget<FileItem>(
        builder: (context, candidateData, rejectedData) => draggableItem,
        onWillAcceptWithDetails: (details) => details.data.id != item.id,
        onAcceptWithDetails: (details) => onDrop(details.data, item),
      );
    }
    return draggableItem;
  }
}

class _FileGridItem extends StatelessWidget {
  final FileItem item;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Function(FileItem item, FileItem destination) onDrop;

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
            if (item.isBackedUp)
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
    final draggableItem = LongPressDraggable<FileItem>(
      data: item,
      feedback: Transform.scale(
          scale: 1.1,
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140, maxHeight: 120),
              child: Opacity(opacity: 0.7, child: _buildItem(context)))),
      child: _buildItem(context),
    );

    if (item.isFolder) {
      return DragTarget<FileItem>(
        builder: (context, candidateData, rejectedData) => draggableItem,
        onWillAcceptWithDetails: (details) => details.data.id != item.id,
        onAcceptWithDetails: (details) => onDrop(details.data, item),
      );
    }
    return draggableItem;
  }
}
