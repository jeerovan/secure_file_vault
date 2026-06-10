import 'package:file_vault_bb/services/service_backend.dart';
import 'package:file_vault_bb/ui/common_widgets.dart';
import 'package:file_vault_bb/utils/common.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/model_setting.dart';

// --- Data Model ---
class CloudProvider {
  final int id;
  final String title;
  final int bytes;

  CloudProvider({required this.id, required this.title, required this.bytes});

  factory CloudProvider.fromJson(Map<String, dynamic> json) {
    return CloudProvider(
      id: json['id'] as int,
      title: json['title'] as String,
      bytes: json['bytes'] as int,
    );
  }

  // Helper to convert bytes to GB (1 GB = 1073741824 bytes)
  String get formattedGB {
    double gb = bytes / 1073741824;
    return '${gb.toStringAsFixed(1)} GB';
  }
}

// --- Main Onboarding Screen ---
class FiFeOnboardingScreen extends StatefulWidget {
  const FiFeOnboardingScreen({super.key});

  @override
  State<FiFeOnboardingScreen> createState() => _FiFeOnboardingScreenState();
}

class _FiFeOnboardingScreenState extends State<FiFeOnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  List<CloudProvider> _providers = [];
  bool _isLoading = true;
  String? _errorMessage;
  final api = BackendApi();

  @override
  void initState() {
    super.initState();
    _fetchProviders();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _fetchProviders() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final result = await api.get(endpoint: '/storages');
      final List<dynamic> data = result["data"];
      setState(() {
        _errorMessage = null;
        _providers = data.map((json) => CloudProvider.fromJson(json)).toList();
        _isLoading = false;
        _providers.removeWhere((item) => item.id == 1);
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = AppLocalizations.of(context)!.failedToFetch;
        });
      }
    }
  }

  Future<void> _nextPage() async {
    if (_currentPage < 3) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      await ModelSetting.set(AppString.onboarding.string, "yes");
      if (mounted) {
        context.read<AppSetupState>().onBoarded();
      }
    }
  }

  IconData _getProviderIcon(int id) {
    IconData iconData;
    switch (id) {
      case 1:
        iconData = LucideIcons.ship;
        break;
      case 2:
        iconData = LucideIcons.package;
        break;
      case 3:
        iconData = LucideIcons.cloudLightning;
        break;
      case 4:
        iconData = LucideIcons.tableProperties;
        break;
      case 5:
        iconData = LucideIcons.hardDrive;
        break;
      default:
        iconData = LucideIcons.hardDrive;
    }
    return iconData;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? tryFailedRequestAgain(
                    context: context,
                    message: _errorMessage!,
                    onPressed: _fetchProviders)
                : Column(
                    children: [
                      Expanded(
                        child: PageView(
                          controller: _pageController,
                          onPageChanged: (index) {
                            setState(() => _currentPage = index);
                          },
                          children: [
                            _buildPurposePage(theme),
                            _buildSecurityPage(theme),
                            _buildProvidersPage(theme),
                            _buildBenefitsPage(theme),
                          ],
                        ),
                      ),
                      _buildBottomControls(theme),
                    ],
                  ),
      ),
    );
  }

  // --- Step 1: Purpose ---
  Widget _buildPurposePage(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Image.asset(
              'assets/logo.png',
              width: 100,
              height: 100,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 48),
          Text(
            AppString.appName.string,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.of(context)!.appTagline,
            style: theme.textTheme.titleLarge?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            AppLocalizations.of(context)!.onboardingPurposeDescription,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // --- Step 2: Cloud Providers ---
  Widget _buildProvidersPage(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          Text(
            AppLocalizations.of(context)!.supportedStorageTitle,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            AppLocalizations.of(context)!.supportedStorageDescription,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          Card(
            elevation: 0,
            color: theme.colorScheme.primaryContainer,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: Image.asset(
                'assets/logo.png',
                width: 40,
                height: 40,
                color: theme.colorScheme.primary,
              ),
              title: Text(
                AppLocalizations.of(context)!.fifeCloud,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              subtitle: Text(
                AppLocalizations.of(context)!.startBackupsInstantly,
                style: TextStyle(
                  color: theme.colorScheme.onPrimaryContainer.withAlpha(80),
                ),
              ),
              trailing: Text(
                AppLocalizations.of(context)!.freeStorageSizeOneGb,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: _providers.length,
                    itemBuilder: (context, index) {
                      final provider = _providers[index];
                      return Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 12),
                        color: theme.colorScheme.surfaceContainerHighest,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: ListTile(
                          leading: Icon(
                            _getProviderIcon(provider.id),
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          title: Text(
                            provider.title,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                provider.formattedGB,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 4.0),
                              Text(
                                AppLocalizations.of(context)!.freeLabel,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.normal,
                                ),
                              )
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 12),
          Text(
            AppLocalizations.of(context)!.providerStorageDisclaimer,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // --- Step 3: Benefits ---
  Widget _buildBenefitsPage(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              AppLocalizations.of(context)!.whyUseFifeTitle,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 32),
            _buildBenefitItem(
              theme,
              icon: LucideIcons.boxes,
              title: AppLocalizations.of(context)!.claimFreeCloudStorageTitle,
              description: AppLocalizations.of(context)!
                  .claimFreeCloudStorageDescription,
            ),
            const SizedBox(height: 24),
            _buildBenefitItem(
              theme,
              icon: LucideIcons.fileLock2,
              title: AppLocalizations.of(context)!.topNotchSecurityTitle,
              description:
                  AppLocalizations.of(context)!.topNotchSecurityDescription,
            ),
            const SizedBox(height: 24),
            _buildBenefitItem(
              theme,
              icon: LucideIcons.key,
              title: AppLocalizations.of(context)!.bringYourOwnKeyTitle,
              description:
                  AppLocalizations.of(context)!.bringYourOwnKeyDescription,
            ),
            const SizedBox(height: 24),
            _buildBenefitItem(
              theme,
              icon: LucideIcons.dollarSign,
              title: AppLocalizations.of(context)!.payAsYouGoStorageTitle,
              description:
                  AppLocalizations.of(context)!.payAsYouGoStorageDescription,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBenefitItem(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: theme.colorScheme.onSecondaryContainer),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSecurityPage(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            Center(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withAlpha(20),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.primary.withAlpha(40),
                      blurRadius: 30,
                      spreadRadius: 10,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.enhanced_encryption_rounded,
                  size: 64,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 32),
            Center(
              child: Text(
                AppLocalizations.of(context)!.zeroKnowledgePrivacyTitle,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                AppLocalizations.of(context)!.zeroKnowledgePrivacyDescription,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurface.withAlpha(140),
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 48),
            _buildSecurityFeatureRow(
              theme: theme,
              icon: Icons.create_new_folder_outlined,
              title: AppLocalizations.of(context)!.localSelectionTitle,
              description:
                  AppLocalizations.of(context)!.localSelectionDescription,
            ),
            _buildSecurityFeatureRow(
              theme: theme,
              icon: Icons.data_object_rounded,
              title: AppLocalizations.of(context)!.metadataEncryptionTitle,
              description:
                  AppLocalizations.of(context)!.metadataEncryptionDescription,
            ),
            _buildSecurityFeatureRow(
              theme: theme,
              icon: Icons.lock_outline_rounded,
              title: AppLocalizations.of(context)!.contentEncryptionTitle,
              description:
                  AppLocalizations.of(context)!.contentEncryptionDescription,
            ),
            _buildSecurityFeatureRow(
              theme: theme,
              icon: Icons.cloud_off_rounded,
              title: AppLocalizations.of(context)!.blindServerTitle,
              description: AppLocalizations.of(context)!.blindServerDescription,
              isLast: true,
            ),
            const SizedBox(height: 48),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => openURL(
                  'https://github.com/jeerovan/secure_file_vault',
                ),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withAlpha(130),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant.withAlpha(130),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.code_rounded,
                        color: theme.colorScheme.primary,
                        size: 28,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AppLocalizations.of(context)!
                                  .dontTrustVerifyTitle,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              AppLocalizations.of(context)!
                                  .openSourceVerificationDescription,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color:
                                    theme.colorScheme.onSurface.withAlpha(150),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        color: theme.colorScheme.onSurface.withAlpha(110),
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSecurityFeatureRow({
    required ThemeData theme,
    required IconData icon,
    required String title,
    required String description,
    bool isLast = false,
  }) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.colorScheme.primary.withAlpha(45),
                    width: 2,
                  ),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: theme.colorScheme.primary.withAlpha(35),
                    margin: const EdgeInsets.symmetric(vertical: 4),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withAlpha(145),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Bottom Controls ---
  Widget _buildBottomControls(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: List.generate(
              4,
              (index) => AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.only(right: 8),
                height: 8,
                width: _currentPage == index ? 24 : 8,
                decoration: BoxDecoration(
                  color: _currentPage == index
                      ? theme.colorScheme.primary
                      : theme.colorScheme.primary.withAlpha(30),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
          FilledButton(
            onPressed: _nextPage,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Text(
              _currentPage == 3
                  ? AppLocalizations.of(context)!.getStarted
                  : AppLocalizations.of(context)!.next,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}
