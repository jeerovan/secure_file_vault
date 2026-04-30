import 'package:file_vault_bb/models/model_profile.dart';
import 'package:file_vault_bb/services/service_backend.dart';
import 'package:file_vault_bb/services/service_logger.dart';
import 'package:file_vault_bb/ui/common_widgets.dart';
import 'package:file_vault_bb/utils/common.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class SubscriptionPage extends StatefulWidget {
  const SubscriptionPage({super.key});

  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage> {
  final AppLogger logger = AppLogger(prefixes: ["Subscription"]);
  static const String entitlementId = 'pro';

  bool _isLoading = false;
  bool _isActive = false;
  bool _isExpired = false;
  Package? _proPackage;
  String? _managementUrl;

  @override
  void initState() {
    super.initState();
    if (revenueCatSupported) {
      _initializeData();
    } else {
      loadFromLocal();
    }
  }

  Future<void> loadFromLocal() async {
    ModelProfile? profile = await ModelProfile.get();
    if (profile != null) {
      if (profile.planExpiresAt! > 0) {
        _isActive = true;
      }
    }
  }

  Future<void> _initializeData() async {
    setState(() => _isLoading = true);
    try {
      final customerInfo = await Purchases.getCustomerInfo();
      final entitlement = customerInfo.entitlements.all[entitlementId];
      final isEntitled =
          customerInfo.entitlements.all[entitlementId]?.isActive ?? false;

      bool isExpired = false;
      if (!isEntitled &&
          entitlement != null &&
          entitlement.expirationDate != null) {
        final expirationDate = DateTime.parse(entitlement.expirationDate!);
        if (expirationDate.isBefore(DateTime.now())) {
          isExpired = true;
        }
      }

      _managementUrl = customerInfo.managementURL;

      setState(() {
        _isActive = isEntitled;
        _isExpired = isExpired;
      });

      if (!_isActive) {
        final offerings = await Purchases.getOfferings();
        if (offerings.current != null && offerings.current!.annual != null) {
          setState(() {
            _proPackage = offerings.current!.annual;
          });
        }
      }
    } catch (e) {
      debugPrint("Error initializing purchases: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _purchasePlan() async {
    if (_proPackage == null) return;
    String? userEmail = await getSignedInEmailId();
    setState(() => _isLoading = true);
    try {
      final params =
          PurchaseParams.package(_proPackage!, customerEmail: userEmail);
      final purchaseResult = await Purchases.purchase(params);
      logger.debug(purchaseResult.toString());
      final isEntitled = purchaseResult
              .customerInfo.entitlements.all[entitlementId]?.isActive ??
          false;

      if (isEntitled) {
        final api = BackendApi();
        await api.get(endpoint: '/subscription');
        if (mounted) {
          setState(() {
            _isActive = true;
            _managementUrl = purchaseResult.customerInfo.managementURL;
          });

          displaySnackBar(context,
              message: 'Successfully subscribed to FiFe Pro!', seconds: 2);
        }
      }
    } catch (e) {
      debugPrint("Purchase error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Purchase cancelled or failed.')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _restorePurchases() async {
    setState(() => _isLoading = true);
    try {
      CustomerInfo customerInfo = await Purchases.restorePurchases();
      final isEntitled =
          customerInfo.entitlements.all[entitlementId]?.isActive ?? false;

      setState(() {
        _isActive = isEntitled;
        _managementUrl = customerInfo.managementURL;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isEntitled
                ? 'Purchases restored successfully!'
                : 'No active subscriptions found.'),
          ),
        );
      }
    } catch (e) {
      debugPrint("Restore error: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _manageSubscription() async {
    if (_managementUrl != null) {
      final uri = Uri.parse(_managementUrl!);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        debugPrint("Could not launch $_managementUrl");
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Please manage subscriptions in your device settings.')),
        );
      }
    }
  }

  Future<void> _navigateBack() async {
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final surfaceColor = colorScheme.surfaceContainerHighest;
    return CrossPlatformBackHandler(
      canPop: true,
      onManualBack: _navigateBack,
      child: Scaffold(
        body: Column(
          children: [
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24.0, vertical: 32.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_isActive) ...[
                            _buildActiveStatusCard(theme, colorScheme),
                          ] else ...[
                            if (_isExpired) _buildExpiredBanner(),
                            const SizedBox(height: 24),
                            _buildPlanCard(
                              theme: theme,
                              colorScheme: colorScheme,
                              title: 'Free',
                              price: '\$0.00 / forever',
                              isActive: true,
                              isPro: false,
                              benefits: [
                                'Enjoy free storage from providers',
                                'Sync up to 3 devices securely',
                              ],
                            ),
                            const SizedBox(height: 24),
                            _buildPlanCard(
                              theme: theme,
                              colorScheme: colorScheme,
                              title: 'FiFe Pro - Yearly',
                              price: _proPackage?.storeProduct.priceString ??
                                  'Loading...',
                              isActive: false,
                              isPro: true,
                              benefits: [
                                'Modify storage limit for each provider',
                                'Sync up to 10 devices',
                              ],
                              buttonAction:
                                  revenueCatSupported ? _purchasePlan : null,
                            ),
                            const SizedBox(height: 24),
                            if (revenueCatSupported) PrivacyTermsWidget(),
                            const SizedBox(height: 24),
                            if (revenueCatSupported)
                              TextButton(
                                onPressed: _restorePurchases,
                                child: Text(
                                  'Restore Purchases',
                                  style: TextStyle(
                                    color: colorScheme.primary,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                          ],
                          const SizedBox(
                            height: 24,
                          ),
                          Text(
                            "* Subscription is associated with email account, not the device",
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.normal,
                              color: colorScheme.onErrorContainer,
                            ),
                          )
                        ],
                      ),
                    ),
            ),
            buildBottomAppBar(
                color: surfaceColor,
                leading: IconButton(
                    tooltip: 'Back',
                    icon: const Icon(LucideIcons.arrowLeft),
                    onPressed: _navigateBack),
                title: Text("FiFe Pro"),
                actions: [])
          ],
        ),
      ),
    );
  }

  Widget _buildExpiredBanner() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.error.withAlpha(125), width: 2),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: colorScheme.error,
            size: 32,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Subscription Expired',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onErrorContainer,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Your FiFe Pro benefits have been paused. Renew below to restore your storage limits and device syncs.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onErrorContainer,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveStatusCard(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withAlpha(50),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colorScheme.primary, width: 2),
      ),
      child: Column(
        children: [
          Icon(Icons.check_circle_rounded,
              color: colorScheme.primary, size: 64),
          const SizedBox(height: 16),
          Text(
            'FiFe Pro is Active',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '✓ Modify storage limits for each provider\n✓ Cross sync up to 10 devices',
            style: theme.textTheme.bodyLarge?.copyWith(
              height: 1.5,
              color: colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          if (revenueCatSupported)
            TextButton.icon(
              onPressed: _manageSubscription,
              icon:
                  Icon(Icons.open_in_new, size: 18, color: colorScheme.primary),
              label: const Text('Manage Subscription'),
              style: TextButton.styleFrom(
                foregroundColor: colorScheme.primary,
              ),
            )
        ],
      ),
    );
  }

  Widget _buildPlanCard({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required String title,
    required String price,
    required bool isActive,
    required bool isPro,
    required List<String> benefits,
    VoidCallback? buttonAction,
  }) {
    final borderColor =
        isPro ? colorScheme.primary : colorScheme.outlineVariant;
    final bgColor = isPro
        ? colorScheme.surface
        : colorScheme.surfaceContainerHighest.withAlpha(40);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: isPro ? 2 : 1),
        boxShadow: isPro
            ? [
                BoxShadow(
                  color: colorScheme.primary.withAlpha(20),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                )
              ]
            : [],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isPro ? colorScheme.primary : colorScheme.onSurface,
                ),
              ),
              if (isActive)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'CURRENT',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (revenueCatSupported)
            Text(
              price,
              style: theme.textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Divider(color: colorScheme.outlineVariant),
          ),
          ...benefits.map((benefit) => Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.check,
                      size: 20,
                      color: isPro
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        benefit,
                        style:
                            theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                      ),
                    ),
                  ],
                ),
              )),
          if (isPro && !isActive) ...[
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: buttonAction,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: Text(
                    revenueCatSupported
                        ? 'Subscribe Now'
                        : 'Subscribe on moile app',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ]
        ],
      ),
    );
  }
}
