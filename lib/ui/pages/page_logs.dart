import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../models/model_log.dart';
import '../common_widgets.dart';

class PageLogs extends StatefulWidget {
  const PageLogs({super.key});

  @override
  State<PageLogs> createState() => _PageLogsState();
}

class _PageLogsState extends State<PageLogs> {
  late Future<List<ModelLog>> _logsFuture;
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
    List<String> searches = [_filterType];
    if (_filterText != null && _filterText!.isNotEmpty) {
      searches.add(_filterText!);
    }
    _logsFuture = ModelLog.all(searches);
  }

  Future<void> _clearLogs() async {
    await ModelLog.clear();
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
              child: FutureBuilder<List<ModelLog>>(
                future: _logsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  } else if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Center(child: Text('No logs available'));
                  } else {
                    final logs = snapshot.data!;
                    return ListView.builder(
                      reverse: true,
                      itemCount: logs.length,
                      itemBuilder: (context, index) {
                        final log = logs[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          child: ListTile(
                            title: Text(
                              log.log,
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
              tooltip: 'Back',
              icon: const Icon(LucideIcons.arrowLeft),
              onPressed: _navigateBack,
            ),
            title: Row(
              children: [
                // 1. Wrap the TextField's container in an Expanded widget
                Expanded(
                  child: SizedBox(
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
                        fillColor: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withAlpha(20),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16.0),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.0),
                          borderSide: BorderSide
                              .none, // Removes default underline/borders
                        ),
                        hintText: 'Search logs..',
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
                              // splashRadius is deprecated in recent Flutter versions
                              // If you are on Flutter 3.22+, rely on IconButton's standard sizing
                              // or use style: IconButton.styleFrom() instead.
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
                ),
                // 2. Added spacing for better UX
                const SizedBox(width: 16),
                // 3. Dropdown remains fixed width
                SizedBox(
                  width: 150,
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _filterType,
                    onChanged: (String? newValue) {
                      if (newValue != null) {
                        // Assuming _filterType is part of setState or similar state management
                        _filterType = newValue;
                        _loadLogs();
                      }
                    },
                    items:
                        _logTypes.map<DropdownMenuItem<String>>((String value) {
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
                onPressed: () {
                  _clearLogs();
                },
              ),
            ],
          ),
        ],
      )),
    );
  }
}
