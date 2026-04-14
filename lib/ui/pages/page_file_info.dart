import 'package:file_vault_bb/models/model_file.dart';
import 'package:file_vault_bb/models/model_item.dart';
import 'package:file_vault_bb/ui/common_widgets.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../services/service_backend.dart';
import '../../services/service_logger.dart';
import '../../utils/enums.dart';

class PageFileInfo extends StatefulWidget {
  final ModelItem item;
  const PageFileInfo({super.key, required this.item});

  @override
  State<PageFileInfo> createState() => _PageFileInfoState();
}

class _PageFileInfoState extends State<PageFileInfo> {
  AppLogger logger = AppLogger(prefixes: ["FileInfo"]);
  List<Map<String, dynamic>> storages = [];
  ModelFile? modelFile;
  List<int> parts = [];
  bool _isLoading = true;
  String? _errorMessage;
  final api = BackendApi();

  @override
  void initState() {
    super.initState();
    fetchFile();
  }

  Future<void> fetchFile() async {
    _errorMessage = null;
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });
    modelFile = await ModelFile.get(widget.item.fileHash!);
    if (modelFile == null) {
      _errorMessage = "File not found";
    } else {
      parts = List.generate(modelFile!.parts, (i) => i + 1);
    }
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _navigateBack() async {
    Navigator.pop(context);
  }

  String formattedSize(int fileSizeBytes) {
    if (fileSizeBytes < 1024) return '$fileSizeBytes B';
    if (fileSizeBytes < 1024 * 1024) {
      return '${(fileSizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    if (fileSizeBytes < 1024 * 1024 * 1024) {
      return '${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(fileSizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String formattedDate(int utcMilliSeconds) {
    final DateTime uploadedDate = DateTime.fromMillisecondsSinceEpoch(
      modelFile!.uploadedAt,
      isUtc: true,
    ).toLocal();
    return DateFormat('MMM d, yyyy').format(uploadedDate);
  }

  String formattedTime(int utcMilliSeconds) {
    final DateTime uploadedDate = DateTime.fromMillisecondsSinceEpoch(
      modelFile!.uploadedAt,
      isUtc: true,
    ).toLocal();
    return DateFormat('h:mm a').format(uploadedDate);
  }

  @override
  Widget build(BuildContext context) {
    final surfaceColor = Theme.of(context).colorScheme.surfaceContainerHighest;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return CrossPlatformBackHandler(
      canPop: true,
      onManualBack: _navigateBack,
      child: Scaffold(
        body: Column(
          children: [
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _errorMessage != null
                      ? tryFailedRequestAgain(
                          message: _errorMessage!,
                          style: Theme.of(context).textTheme.bodyLarge,
                          onPressed: fetchFile)
                      : modelFile == null
                          ? const SizedBox.shrink()
                          : CustomScrollView(
                              physics: const BouncingScrollPhysics(),
                              slivers: [
                                SliverToBoxAdapter(
                                  child: _buildHeaderSection(context),
                                ),
                                SliverPadding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20, vertical: 24),
                                  sliver: SliverToBoxAdapter(
                                    child: _buildMetadataGrid(context),
                                  ),
                                ),
                                SliverPadding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20),
                                  sliver: SliverToBoxAdapter(
                                    child: Text(
                                      'File Parts (${modelFile!.parts})',
                                      style:
                                          theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                                ),
                                SliverPadding(
                                  padding: const EdgeInsets.only(
                                      left: 20, right: 20, top: 12, bottom: 40),
                                  sliver: _buildPartsList(context),
                                ),
                              ],
                            ),
            ),
            buildBottomAppBar(
                color: surfaceColor,
                leading: IconButton(
                    icon: const Icon(LucideIcons.arrowLeft),
                    onPressed: _navigateBack),
                title: Text("File Details"),
                actions: []),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderSection(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withAlpha(40),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons
                  .insert_drive_file_rounded, // Better to replace with dynamic icon based on extension
              size: 56,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            widget.item.name,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Encrypted Backup',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetadataGrid(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 600 ? 4 : 2;
        return GridView.count(
          crossAxisCount: crossAxisCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.5,
          children: [
            _InfoCard(
              title: 'Size',
              value: formattedSize(widget.item.size),
              icon: Icons.data_usage_rounded,
            ),
            if (modelFile?.providerId != null)
              _InfoCard(
                title: 'Provider',
                value: StorageProviderExtension.stringFromInt(
                    modelFile!.providerId!),
                icon: Icons.cloud_done_rounded,
              ),
            if (modelFile!.uploadedAt > 0)
              _InfoCard(
                title: 'Uploaded At',
                value: formattedDate(modelFile!.uploadedAt),
                subtitle: formattedTime(modelFile!.uploadedAt),
                icon: Icons.access_time_rounded,
              ),
            if (modelFile!.uploadedAt > 0)
              _InfoCard(
                title: 'Status',
                value: 'Uploaded',
                icon: Icons.sync_rounded,
                iconColor: Colors.green,
              ),
          ],
        );
      },
    );
  }

  Widget _buildPartsList(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final isFirst = index == 0;
          final isLast = index == parts.length - 1;

          return Container(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withAlpha(30),
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(isFirst ? 16 : 0),
                bottom: Radius.circular(isLast ? 16 : 0),
              ),
            ),
            child: Column(
              children: [
                ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.extension_rounded, // Represents a "part" or "chunk"
                      size: 20,
                      color: colorScheme.primary,
                    ),
                  ),
                  title: Text(
                    '${modelFile!.id}_${parts[index]}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                  trailing: Icon(
                    Icons.lock_outline_rounded,
                    size: 16,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                if (!isLast)
                  Divider(
                    height: 1,
                    indent: 64,
                    endIndent: 16,
                    color: colorScheme.outlineVariant.withAlpha(50),
                  ),
              ],
            ),
          );
        },
        childCount: parts.length,
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final String value;
  final String? subtitle;
  final IconData icon;
  final Color? iconColor;

  const _InfoCard({
    required this.title,
    required this.value,
    this.subtitle,
    required this.icon,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withAlpha(40),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withAlpha(50),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: iconColor ?? colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                title,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ]
        ],
      ),
    );
  }
}
