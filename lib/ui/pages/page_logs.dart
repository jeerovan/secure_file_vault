import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../l10n/app_localizations.dart';
import '../common_widgets.dart';
import '../../utils/common.dart';

class PageLogs extends StatefulWidget {
  const PageLogs({super.key});

  @override
  State<PageLogs> createState() => _PageLogsState();
}

class _PageLogsState extends State<PageLogs> {
  late Future<List<String>> _logsFuture;
  String? _filterText;
  String _filterType = 'All';
  final List<String> _logTypes = ['All', 'INFO', 'DEBUG', 'WARNING', 'ERROR'];
  late final TextEditingController _searchController;

  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _loadLogs();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _loadLogs() {
    if (mounted) {
      setState(() {});
    }
    _logsFuture = _readAndFilterLogs();
  }

  Future<List<String>> _readAndFilterLogs() async {
    try {
      final tempDir = await getAppTempDirectory();
      final logFile = File('${tempDir.path}/app_logs.txt');
      if (!await logFile.exists()) {
        return [];
      }

      final lines = await logFile.readAsLines();

      return lines.where((line) {
        // Filter by type
        if (_filterType != 'All') {
          if (!line.contains('[$_filterType]')) {
            return false;
          }
        }
        // Filter by text
        if (_filterText != null && _filterText!.isNotEmpty) {
          if (!line.toLowerCase().contains(_filterText!.toLowerCase())) {
            return false;
          }
        }
        return true;
      }).toList()
        ..reversed.forEach((_) {}); // Keep order as is, but UI handles reverse
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _clearLogs() async {
    try {
      final tempDir = await getAppTempDirectory();
      final logFile = File('${tempDir.path}/app_logs.txt');
      if (await logFile.exists()) {
        await logFile.writeAsString('');
      }
    } catch (e) {
      dev.log("Failed to clear logs", error: e);
    }
    _loadLogs();
  }

  Future<void> _navigateBack() async {
    Navigator.pop(context);
  }

  void onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) {
      _debounce!.cancel();
    }
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _filterText = query.trim();
      _loadLogs();
    });
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
              child: RefreshIndicator(
                onRefresh: () async {
                  _loadLogs();
                },
                child: FutureBuilder<List<String>>(
                  future: _logsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    } else if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          AppLocalizations.of(context)!
                              .errorWithMessage(snapshot.error.toString()),
                        ),
                      );
                    } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return Center(
                        child: Text(
                          AppLocalizations.of(context)!.noLogsAvailable,
                        ),
                      );
                    } else {
                      final logs = snapshot.data!;
                      return ListView.builder(
                        reverse: true,
                        itemCount: logs.length,
                        itemBuilder: (context, index) {
                          // Since reverse: true, index 0 is bottom.
                          // To show newest at bottom, we need the list to be [oldest, ..., newest]
                          // and access them as logs[logs.length - 1 - index]
                          final log = logs[logs.length - 1 - index];
                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            child: ListTile(
                              title: Text(
                                log,
                                style: const TextStyle(fontSize: 10),
                              ),
                            ),
                          );
                        },
                      );
                    }
                  },
                ),
              ),
            ),
            buildBottomAppBar(
              color: surfaceColor,
              leading: IconButton(
                tooltip: AppLocalizations.of(context)!.backTooltip,
                icon: const Icon(LucideIcons.arrowLeft),
                onPressed: _navigateBack,
              ),
              title: Row(
                children: [
                  Expanded(
                    child: SizedBox(
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
                          fillColor: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withAlpha(20),
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 16.0),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.0),
                            borderSide: BorderSide.none,
                          ),
                          hintText:
                              AppLocalizations.of(context)!.searchLogsHint,
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
                              if (value.text.isEmpty) {
                                return const SizedBox.shrink();
                              }
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
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 100,
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _filterType,
                      onChanged: (String? newValue) {
                        if (newValue != null) {
                          _filterType = newValue;
                          _loadLogs();
                        }
                      },
                      items: _logTypes
                          .map<DropdownMenuItem<String>>((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(
                            value,
                            style: const TextStyle(fontSize: 14),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(LucideIcons.trash2),
                  tooltip: AppLocalizations.of(context)!.clearLogs,
                  onPressed: () {
                    _clearLogs();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
