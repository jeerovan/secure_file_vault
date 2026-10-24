import 'package:file_vault_bb/services/service_auth.dart';
import 'package:file_vault_bb/utils/utils_sync.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../../l10n/app_localizations.dart';
import '../../models/model_profile.dart';
import '../../models/model_setting.dart';
import '../../services/service_logger.dart';
import '../../storage/storage_secure.dart';
import '../../ui/common_widgets.dart';
import '../../utils/common.dart';
import '../../utils/enums.dart';
import '../../services/service_session_work.dart';
import '../../services/service_recovery_reset.dart';
import '../../services/service_vault_key_setup.dart';
import '../../services/service_backend.dart';
import '../../services/service_session_authentication.dart';

class PageSignin extends StatefulWidget {
  const PageSignin({super.key, this.auth, this.sessions});
  final NeonAuth? auth;
  final SessionAuthentication? sessions;

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
  bool verifiedPending = false;
  bool completingFailed = false;
  SessionAuthentication get _sessions =>
      widget.sessions ?? SessionAuthentication.instance;
  NeonAuth get _auth => widget.auth ?? NeonAuth();
  String email = ModelSetting.get(AppString.otpSentTo.string);
  String neonAuthUrl = AppEnv.neonAuthUrl;

  @override
  void initState() {
    super.initState();
    _checkInitialAuthState();
    _prefillRecoveryEmail();
  }

  Future<void> _prefillRecoveryEmail() async {
    try {
      final account = await _sessions.pendingAccount();
      final retained = SessionWork.authenticationRequired
          ? await SessionWork.authenticate(ModelProfile.get)
          : null;
      final pending = account?.email ??
          retained?.email ??
          await RecoveryResetService.instance.pendingEmail() ??
          await VaultKeySetupService.instance.pendingEmail();
      if (mounted &&
          !otpSent &&
          !processing &&
          emailController.text.isEmpty &&
          pending != null) {
        emailController.text = pending;
      }
      if (mounted && account != null && !processing) {
        setState(() {
          verifiedPending = true;
          email = account.email;
        });
      }
    } on SessionInvalidated {
      /* Cleanup owns navigation. */
    } catch (_) {
      /* A failed optional hint must not prevent a fresh sign-in. */
    }
  }

  void _checkInitialAuthState() {
    if (SessionWork.authenticationRequired ||
        ModelSetting.get(AppString.signedIn.string, defaultValue: "no") ==
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
    return _sendOtp(text);
  }

  Future<void> _sendOtp(String text) async {
    if (processing) return;
    email = text.trim();
    if (email.isEmpty) return;

    setState(() {
      processing = true;
      errorSendingOtp = false;
    });

    try {
      if (isLocalTestingEmail(email)) {
        final attempt = await _sessions.beginAttempt();
        final api = BackendApi(
            localTestingProvider: () => true,
            accessTokenProvider: () async => AppEnv.localTestAuthToken,
            signedEmailIdProvider: () async => email,
            deviceUuidProvider: () async => '',
            vaultGenerationOverride: '',
            sessionCookieProvider: () async => null);
        final response = await SessionWork.authenticate(
            () => api.post(endpoint: '/local-test/session', jsonBody: {}));
        api.close();
        final token =
            response['data'] is Map ? response['data']['sessionToken'] : null;
        final user = response['data'] is Map ? response['data']['user'] : null;
        if (response['success'] != 1 ||
            token is! String ||
            token.isEmpty ||
            !token.startsWith(AppEnv.localSessionPrefix) ||
            user is! Map ||
            user['id'] is! String ||
            (user['id'] as String).isEmpty ||
            user['email'] is! String ||
            (user['email'] as String).trim().toLowerCase() !=
                email.toLowerCase()) {
          throw StateError('Local authentication failed');
        }
        await _sessions.stageVerified(
            attempt,
            AuthenticatedAccount(
                id: user['id'],
                email: user['email'],
                service: 'local-test',
                cookie: token));
        await _completeSignin(user['id'], user['email']);
        return;
      } else if (email.toLowerCase() == testEmailId.toLowerCase()) {
        await Future.delayed(const Duration(seconds: 1));
      } else {
        final response = await _auth.sendOTP(email);
        if (response.statusCode != 200) {
          throw Exception('Failed to send OTP: ${response.body}');
        }
      }

      int nowUtc = DateTime.now().toUtc().millisecondsSinceEpoch;
      await SessionWork.authenticate(() async {
        await ModelSetting.set(AppString.otpSentTo.string, email);
        await ModelSetting.set(AppString.otpSentAt.string, nowUtc.toString());
      });

      if (!mounted) return;
      setState(() {
        otpSent = true;
      });
    } catch (e, s) {
      logger.error("sendOTP", error: e, stackTrace: s);
      if (!mounted) return;
      try {
        if (await _sessions.pendingAccount() != null) {
          await _authenticationFailed(e);
          return;
        }
      } on SessionInvalidated {
        if (mounted) await context.read<AppSetupState>().recheckStatus();
        return;
      } catch (_) {
        // A transient key-store/database failure must remain a retryable UI.
      }
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
    return _verifyOtp(text);
  }

  Future<void> _verifyOtp(String text) async {
    if (processing) return;
    final otp = text.trim();
    final String savedEmail = await SessionWork.authenticate(
        () => ModelSetting.getRaw(AppString.otpSentTo.string));

    if (savedEmail.isEmpty || otp.isEmpty) return;

    setState(() {
      processing = true;
      errorVerifyingOtp = false;
    });
    try {
      String? userId;
      if (savedEmail.toLowerCase() == testEmailId.toLowerCase()) {
        await Future.delayed(const Duration(seconds: 1));
        userId = 'fife';
        final attempt = await _sessions.beginAttempt();
        await _sessions.stageVerified(
            attempt,
            AuthenticatedAccount(
                id: userId, email: savedEmail, service: 'simulation'));
      } else {
        String? authId = await _auth.verifyOTP(savedEmail, otp);
        if (authId == null) {
          throw Exception("OTP verification failed");
        } else {
          userId = authId;
        }
      }

      logger.info("Login Successful");

      await _completeSignin(userId, savedEmail);
    } catch (e, s) {
      logger.error("verifyOtp", error: e, stackTrace: s);
      await _authenticationFailed(e);
    } finally {
      if (mounted) {
        setState(() {
          processing = false;
        });
      }
    }
  }

  Future<void> _completeSignin(String userId, String profileEmail) async {
    AuthenticatedAccount? account;
    try {
      account = await _sessions.pendingAccount();
    } on SessionInvalidated {
      if (mounted) await context.read<AppSetupState>().recheckStatus();
      return;
    }
    if (account?.id != userId ||
        account?.email.trim().toLowerCase() !=
            profileEmail.trim().toLowerCase()) {
      throw const SessionInvalidated();
    }
    await _sessions.completeSignin(
        refreshNeon: (value) => _auth.refreshForSignin(value));

    if (subscriptionsSupported && !simulateTesting()) {
      try {
        if (await Purchases.isConfigured) {
          await Purchases.logIn(userId);
        } else {
          final key = defaultTargetPlatform == TargetPlatform.android
              ? AppEnv.rcAndroidKey
              : AppEnv.rcIosKey;
          if (key.isNotEmpty) {
            await Purchases.configure(
                PurchasesConfiguration(key)..appUserID = userId);
          }
        }
      } catch (_) {/* Billing retries independently of vault authentication. */}
    }

    if (!mounted) return;
    await context.read<AppSetupState>().completeSignin();
  }

  Future<void> _authenticationFailed(Object error) async {
    if (!mounted) return;
    if (error is SessionInvalidated) {
      await context.read<AppSetupState>().recheckStatus();
      return;
    }
    AuthenticatedAccount? account;
    try {
      account = await _sessions.pendingAccount();
    } on SessionInvalidated {
      if (mounted) await context.read<AppSetupState>().recheckStatus();
      return;
    } catch (_) {
      if (mounted) {
        setState(() => completingFailed = true);
        displaySnackBar(context,
            message: AppLocalizations.of(context)!.pleaseTryAgain, seconds: 3);
      }
      return;
    }
    if (!mounted) return;
    if (error is VerifiedSigninExpired) {
      await SessionWork.authenticate(() async {
        await ModelSetting.delete(AppString.otpSentTo.string);
        await ModelSetting.delete(AppString.otpSentAt.string);
      });
      if (mounted) {
        setState(() {
          verifiedPending = false;
          otpSent = false;
        });
      }
    } else if (account != null) {
      final verifiedEmail = account.email;
      setState(() {
        verifiedPending = true;
        completingFailed = true;
        email = verifiedEmail;
      });
    } else {
      _showOtpVerifyError();
    }
  }

  Future<void> _resumeSignin() async {
    if (processing) return;
    setState(() {
      processing = true;
      completingFailed = false;
    });
    try {
      final account = await _sessions.pendingAccount();
      if (account == null) throw const VerifiedSigninExpired();
      await _completeSignin(account.id, account.email);
    } catch (error) {
      await _authenticationFailed(error);
    } finally {
      if (mounted) setState(() => processing = false);
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
    if (processing) return;
    setState(() => processing = true);
    try {
      await _sessions.discardCandidate();
      await SessionWork.authenticate(() async {
        await ModelSetting.delete(AppString.otpSentTo.string);
        await ModelSetting.delete(AppString.otpSentAt.string);
      });
      if (!mounted) return;
      setState(() {
        otpSent = false;
        verifiedPending = false;
        completingFailed = false;
        otpController.clear();
      });
    } catch (error) {
      await _authenticationFailed(error);
    } finally {
      if (mounted) setState(() => processing = false);
    }
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
    if (verifiedPending) {
      return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.mark_email_read_outlined, size: 48),
            const SizedBox(height: 24),
            Semantics(
                liveRegion: true,
                child: Text(
                    AppLocalizations.of(context)!.signinVerifiedContinue,
                    textAlign: TextAlign.center)),
            if (completingFailed) ...[
              const SizedBox(height: 16),
              Text(AppLocalizations.of(context)!.pleaseTryAgain,
                  textAlign: TextAlign.center),
            ],
            const SizedBox(height: 24),
            _buildActionButton(
                label: AppLocalizations.of(context)!.continueLabel,
                onPressed: _resumeSignin),
            TextButton(
                onPressed: processing ? null : changeEmail,
                child: Text(AppLocalizations.of(context)!.useDifferentEmail)),
          ]);
    } else if (signedIn) {
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
          SessionWork.authenticationRequired
              ? AppLocalizations.of(context)!.sessionExpiredRetained
              : AppLocalizations.of(context)!
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
