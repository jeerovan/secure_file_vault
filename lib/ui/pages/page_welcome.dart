import 'package:file_vault_bb/services/service_backend.dart';
import 'package:file_vault_bb/ui/common_widgets.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

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
          _errorMessage = "Failed to fetch.";
        });
      }
    }
  }

  Future<void> _nextPage() async {
    if (_currentPage < 2) {
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
                    message: _errorMessage!,
                    style: Theme.of(context).textTheme.bodyLarge,
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
              'assets/logo.png', // Replace with your actual asset path
              width: 100,
              height: 100,
              color: theme.colorScheme.primary, // Applies the theme color tint
            ),
          ),
          const SizedBox(height: 48),
          Text(
            "FiFe",
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            "Your Private Files Ferry",
            style: theme.textTheme.titleLarge?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            "An open-source, cloud storage service built with zero-trust architecture. Your data is encrypted locally before it ever leaves your device.",
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
            "Supported Storage",
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            "Connect your favorite providers. Start right away with FiFe's built-in 1 GB free secure storage.",
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),

          // FiFe Default Storage Card
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
                color:
                    theme.colorScheme.primary, // Applies the theme color tint
              ),
              title: Text("FiFe Cloud",
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onPrimaryContainer)),
              subtitle: Text("Start backups instantly",
                  style: TextStyle(
                      color:
                          theme.colorScheme.onPrimaryContainer.withAlpha(80))),
              trailing: Text("1.0 GB",
                  style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary)),
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
                            borderRadius: BorderRadius.circular(16)),
                        child: ListTile(
                          leading: Icon(_getProviderIcon(provider.id),
                              color: theme.colorScheme.onSurfaceVariant),
                          title: Text(provider.title,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
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
                              const SizedBox(
                                width: 4.0,
                              ),
                              Text(
                                'Free',
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
            "* Free storage as mentioned on provider's website. Pay-as-you-go with compatible providers.",
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            "Why Use FiFe?",
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 32),
          _buildBenefitItem(
            theme,
            icon: LucideIcons.boxes,
            title: "Claim Free Cloud Storage",
            description:
                "Maximize your space by connecting multiple cloud providers. Securely take advantage of their free storage tiers in one unified app.",
          ),
          const SizedBox(height: 24),
          _buildBenefitItem(
            theme,
            icon: LucideIcons.fileLock2,
            title: "Top-Notch Security",
            description:
                "Powered by advanced Sodium cryptography. All encryption and decryption happens entirely locally on your device.",
          ),
          const SizedBox(height: 24),
          _buildBenefitItem(
            theme,
            icon: LucideIcons.key,
            title: "Bring Your Own Key (BYOK)",
            description:
                "Maintain complete sovereignty over your data across all cloud storage providers. Keep encrypted storage using your own accounts.",
          ),
          const SizedBox(height: 24),
          _buildBenefitItem(
            theme,
            icon: LucideIcons.dollarSign,
            title: "Pay-as-you-go for storage.",
            description:
                "Pay for used storage only with compatible providers. No middleman, no data lock-in.",
          ),
        ],
      ),
    );
  }

  Widget _buildBenefitItem(ThemeData theme,
      {required IconData icon,
      required String title,
      required String description}) {
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

  // --- Bottom Controls ---
  Widget _buildBottomControls(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Custom Page Indicator
          Row(
            children: List.generate(
              3,
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

          // Next / Get Started Button
          FilledButton(
            onPressed: _nextPage,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Text(
              _currentPage == 2 ? "Get Started" : "Next",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}
