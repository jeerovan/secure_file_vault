import 'package:file_vault_bb/services/service_auth.dart';
import 'package:file_vault_bb/utils/utils_sync.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../../l10n/app_localizations.dart';
import '../../models/model_item.dart';
import '../../models/model_profile.dart';
import '../../models/model_setting.dart';
import '../../services/service_logger.dart';
import '../../storage/storage_secure.dart';
import '../../ui/common_widgets.dart';
import '../../utils/common.dart';
import '../../utils/enums.dart';

class PageSignin extends StatefulWidget {
  const PageSignin({super.key});

  @override
  State<PageSignin> createState() => _PageSigninState();
}

class _PageSigninState extends State<PageSignin> {
  final logger = AppLogger(prefixes: ["Signin"]);

  final _emailFormKey = GlobalKey<FormState>();
  final _otpFormKey = GlobalKey<FormState>();

  final emailController = TextEditingController();
  final otpController = TextEditingController();
  final SecureStorage storage = SecureStorage();

  bool processing = false;
  bool otpSent = false;
  bool errorSendingOtp = false;
  bool errorVerifyingOtp = false;
  bool signedIn = false;
  String email = ModelSetting.get(AppString.otpSentTo.string);
  String neonAuthUrl = AppEnv.neonAuthUrl;

  @override
  void initState() {
    super.initState();
    _checkInitialAuthState();
  }

  void _checkInitialAuthState() {
    if (ModelSetting.get(AppString.signedIn.string, defaultValue: "no") ==
        "no") {
      logger.info("Not signed in");
      int sentOtpAt = int.parse(
        ModelSetting.get(AppString.otpSentAt.string, defaultValue: "0"),
      );
      int nowUtc = DateTime.now().toUtc().millisecondsSinceEpoch;

      if (sentOtpAt > 0 && nowUtc - sentOtpAt < 600000) {
        otpSent = true;
      }
    } else {
      signedIn = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.read<AppSetupState>().completeSignin();
      });
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    otpController.dispose();
    super.dispose();
  }

  Future<void> sendOtp(String text) async {
    if (processing) return;
    email = text.trim();
    if (email.isEmpty) return;

    setState(() {
      processing = true;
      errorSendingOtp = false;
    });

    try {
      if (email == testEmailId) {
        await Future.delayed(const Duration(seconds: 1));
        await ModelSetting.set(AppString.simulateTesting.string, "yes");
      } else {
        final response = await NeonAuth().sendOTP(email);
        if (response.statusCode != 200) {
          throw Exception('Failed to send OTP: ${response.data.toString()}');
        }
      }

      int nowUtc = DateTime.now().toUtc().millisecondsSinceEpoch;
      await ModelSetting.set(AppString.otpSentTo.string, email);
      await ModelSetting.set(AppString.otpSentAt.string, nowUtc.toString());

      if (!mounted) return;
      setState(() {
        otpSent = true;
      });
    } catch (e, s) {
      logger.error("sendOTP", error: e, stackTrace: s);
      if (!mounted) return;
      setState(() {
        errorSendingOtp = true;
      });
      displaySnackBar(
        context,
        message: AppLocalizations.of(context)!.sendingOtpFailedPleaseTryAgain,
        seconds: 2,
      );
    } finally {
      if (mounted) {
        setState(() {
          processing = false;
        });
      }
    }
  }

  Future<void> verifyOtp(String text) async {
    if (processing) return;
    final otp = text.trim();
    final String savedEmail = ModelSetting.get(AppString.otpSentTo.string);

    if (savedEmail.isEmpty || otp.isEmpty) return;

    setState(() {
      processing = true;
      errorVerifyingOtp = false;
    });
    logger.debug("$savedEmail:$otp");
    try {
      String? userId;
      if (simulateTesting()) {
        await Future.delayed(const Duration(seconds: 1));
        userId = 'fife';
      } else {
        String? authId = await NeonAuth().verifyOTP(email, otp);
        if (authId == null) {
          throw Exception("OTP verification failed");
        } else {
          userId = authId;
        }
      }

      await ModelSetting.delete(AppString.otpSentTo.string);
      await ModelSetting.delete(AppString.otpSentAt.string);

      logger.info("Login Successful");

      ModelProfile profile =
          await ModelProfile.fromMap({"id": userId, "email": email});
      await profile.insert();

      ModelItem deviceItem = await ModelItem.fromMap({
        "id": "fife",
        "name": "FiFe",
        "is_folder": 1,
      });
      await deviceItem.insert();
      await ModelSetting.set(AppString.signedIn.string, "yes");

      if (revenueCatSupported && !simulateTesting()) {
        await Purchases.logIn(userId);
      }

      if (!mounted) return;
      final appSetup = context.read<AppSetupState>();
      await appSetup.completeSignin();
    } catch (e, s) {
      logger.error("verifyOtp", error: e, stackTrace: s);
      _showOtpVerifyError();
    } finally {
      if (mounted) {
        setState(() {
          processing = false;
        });
      }
    }
  }

  void _showOtpVerifyError() {
    if (!mounted) return;
    setState(() {
      errorVerifyingOtp = true;
    });
    displaySnackBar(
      context,
      message:
          AppLocalizations.of(context)!.otpVerificationFailedPleaseTryAgain,
      seconds: 3,
    );
  }

  Future<void> changeEmail() async {
    await ModelSetting.delete(AppString.otpSentTo.string);
    await ModelSetting.delete(AppString.otpSentAt.string);
    setState(() {
      otpSent = false;
      otpController.clear();
    });
  }

  Future<void> signout() async {
    await SyncUtils.signout();
    setState(() {
      signedIn = false;
      otpSent = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text(''),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  width: 1,
                ),
              ),
              color: Theme.of(context).colorScheme.surface,
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: _buildCurrentStep(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentStep() {
    if (signedIn) {
      return _buildSignedInView();
    } else if (otpSent) {
      return _buildOtpView();
    } else {
      return _buildEmailView();
    }
  }

  InputDecoration _buildInputDecoration(
    String label,
    String hint,
    IconData icon,
  ) {
    final colors = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: colors.onSurfaceVariant,
      ),
      hintText: hint,
      hintStyle: TextStyle(
        color: colors.onSurfaceVariant.withAlpha(140),
        fontSize: 16,
      ),
      prefixIcon: Icon(icon, size: 24, color: colors.onSurfaceVariant),
      filled: true,
      fillColor: colors.surfaceContainerHighest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colors.outline, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colors.outline, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colors.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colors.error, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colors.error, width: 2),
      ),
    );
  }

  Widget _buildEmailView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.lock_person_outlined,
          size: 48,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 24),
        Text(
          AppLocalizations.of(context)!.welcomeTitle,
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          AppLocalizations.of(context)!
              .signInToContinue(AppString.appName.string),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 32),
        Form(
          key: _emailFormKey,
          child: TextFormField(
            autofocus: true,
            controller: emailController,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return AppLocalizations.of(context)!.pleaseEnterYourEmail;
              }
              final emailRegex =
                  RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
              if (!emailRegex.hasMatch(value)) {
                return AppLocalizations.of(context)!
                    .pleaseEnterValidEmailAddress;
              }
              return null;
            },
            decoration: _buildInputDecoration(
              AppLocalizations.of(context)!.emailAddressLabel,
              AppLocalizations.of(context)!.emailAddressHint,
              Icons.email_outlined,
            ),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (value) {
              if (_emailFormKey.currentState!.validate()) sendOtp(value);
            },
          ),
        ),
        const SizedBox(height: 24),
        _buildActionButton(
          label: errorSendingOtp
              ? AppLocalizations.of(context)!.retrySendingOtp
              : AppLocalizations.of(context)!.sendOtp,
          onPressed: () {
            if (_emailFormKey.currentState!.validate()) {
              sendOtp(emailController.text);
            }
          },
        ),
        const SizedBox(height: 24),
        PrivacyTermsWidget(),
      ],
    );
  }

  Widget _buildOtpView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.mark_email_read_outlined,
          size: 48,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 24),
        Text(
          AppLocalizations.of(context)!.checkYourEmail,
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          AppLocalizations.of(context)!.sentSixDigitCodeTo(email),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 32),
        Form(
          key: _otpFormKey,
          child: TextFormField(
            autofocus: true,
            controller: otpController,
            maxLength: 6,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return AppLocalizations.of(context)!.pleaseEnterOtp;
              }
              if (value.length < 6) {
                return AppLocalizations.of(context)!.otpMustBeSixDigits;
              }
              return null;
            },
            decoration: _buildInputDecoration(
              AppLocalizations.of(context)!.enterOtpLabel,
              AppLocalizations.of(context)!.otpHint,
              Icons.password_outlined,
            ).copyWith(
              counterText: "",
            ),
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              letterSpacing: 8,
              fontWeight: FontWeight.bold,
            ),
            onFieldSubmitted: (value) {
              if (_otpFormKey.currentState!.validate()) verifyOtp(value);
            },
          ),
        ),
        const SizedBox(height: 24),
        _buildActionButton(
          label: errorVerifyingOtp
              ? AppLocalizations.of(context)!.retryVerification
              : AppLocalizations.of(context)!.verifyOtp,
          onPressed: () {
            if (_otpFormKey.currentState!.validate()) {
              verifyOtp(otpController.text);
            }
          },
        ),
        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: processing ? null : changeEmail,
          icon: const Icon(Icons.arrow_back),
          label: Text(
            AppLocalizations.of(context)!.useDifferentEmail,
          ),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildSignedInView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.check_circle_outline,
          size: 48,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 24),
        Text(
          AppLocalizations.of(context)!.alreadySignedIn,
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 32),
        OutlinedButton.icon(
          onPressed: signout,
          icon: const Icon(Icons.logout),
          label: Text(AppLocalizations.of(context)!.signOut),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            foregroundColor: Theme.of(context).colorScheme.error,
            side: BorderSide(
              color: Theme.of(context).colorScheme.error.withAlpha(100),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required String label,
    required VoidCallback onPressed,
  }) {
    return FilledButton(
      onPressed: processing ? null : onPressed,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: processing
          ? SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
            )
          : Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
    );
  }
}
