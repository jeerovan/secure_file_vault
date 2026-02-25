import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/model_item.dart';
import '../../models/model_state.dart';
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
  final SupabaseClient supabase = Supabase.instance.client;

  late TapGestureRecognizer _termsRecognizer;
  late TapGestureRecognizer _privacyRecognizer;

  bool processing = false;
  bool otpSent = false;
  bool errorSendingOtp = false;
  bool errorVerifyingOtp = false;
  bool signedIn = false;
  String email = ModelSetting.get(AppString.otpSentTo.string, "");

  @override
  void initState() {
    super.initState();
    _setupGestureRecognizers();
    _checkInitialAuthState();
  }

  void _setupGestureRecognizers() {
    _termsRecognizer = TapGestureRecognizer()
      ..onTap = () => openURL('https://fife.jeerovan.com/policy/terms');
    _privacyRecognizer = TapGestureRecognizer()
      ..onTap = () => openURL('https://fife.jeerovan.com/policy/privacy');
  }

  void _checkInitialAuthState() {
    if (supabase.auth.currentSession == null) {
      logger.info("Not signed in");
      int sentOtpAt =
          int.parse(ModelSetting.get(AppString.otpSentAt.string, 0).toString());
      int nowUtc = DateTime.now().toUtc().millisecondsSinceEpoch;

      // 15 minutes (900000 ms) expiry check
      if (sentOtpAt > 0 && nowUtc - sentOtpAt < 900000) {
        otpSent = true;
      }
    } else {
      signedIn = true;
      String? accessToken = supabase.auth.currentSession?.accessToken;
      logger.info("Access Token: $accessToken");
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.read<AppSetupState>().completeSignin();
      });
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    otpController.dispose();
    _termsRecognizer.dispose();
    _privacyRecognizer.dispose();
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
        await supabase.auth.signInWithOtp(email: email);
      }

      int nowUtc = DateTime.now().toUtc().millisecondsSinceEpoch;
      await ModelSetting.set(AppString.otpSentTo.string, email);
      await ModelSetting.set(AppString.otpSentAt.string, nowUtc);

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
      displaySnackBar(context,
          message: 'Sending OTP failed. Please try again!', seconds: 2);
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
    final String savedEmail = ModelSetting.get(AppString.otpSentTo.string, "");

    if (savedEmail.isEmpty || otp.isEmpty) return;

    setState(() {
      processing = true;
      errorVerifyingOtp = false;
    });

    try {
      Session? session;

      if (simulateTesting()) {
        if (await ModelState.get(AppString.dataSeeded.string,
                defaultValue: "no") ==
            "no") {
          await signalToUpdateHome();
        }
      } else {
        final AuthResponse response = await supabase.auth.verifyOTP(
          email: savedEmail,
          token: otp,
          type: OtpType.email,
        );

        if (response.session != null) {
          session = response.session;
          logger.debug(
              'Success: Sign-in complete. User ID: ${response.user?.id}');
        } else {
          throw Exception('OTP verified, but no session was established.');
        }
      }

      if (session != null || simulateTesting()) {
        await ModelSetting.delete(AppString.otpSentTo.string);
        await ModelSetting.delete(AppString.otpSentAt.string);
        await ModelSetting.set(AppString.signedIn.string, "yes");

        ModelItem deviceItem = await ModelItem.fromMap({
          "id": "fife",
          "name": "FiFe",
          "is_folder": 1,
        });
        await deviceItem.insert();

        logger.info("Login Successful");

        if (!mounted) return;
        final appSetup = context.read<AppSetupState>();
        await appSetup.completeSignin();
      }
    } on AuthException catch (error) {
      logger.debug('Auth Failure: ${error.message}');
      _handleVerifyError();
    } catch (e, s) {
      logger.error("verifyOtp", error: e, stackTrace: s);
      _handleVerifyError();
    } finally {
      if (mounted) {
        setState(() {
          processing = false;
        });
      }
    }
  }

  void _handleVerifyError() {
    if (!mounted) return;
    setState(() {
      errorVerifyingOtp = true;
    });
    displaySnackBar(context,
        message:
            'OTP verification failed. Please check the code and try again.',
        seconds: 3);
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
    await supabase.auth.signOut();
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
      String label, String hint, IconData icon) {
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
        Icon(Icons.lock_person_outlined,
            size: 48, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 24),
        Text(
          'Welcome Back',
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Sign in to continue to FiFe',
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
                return 'Please enter your email';
              }
              final emailRegex =
                  RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
              if (!emailRegex.hasMatch(value)) {
                return 'Please enter a valid email address';
              }
              return null;
            },
            decoration: _buildInputDecoration('Email Address',
                'your.email@example.com', Icons.email_outlined),
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
          label: errorSendingOtp ? 'Retry Sending OTP' : 'Send OTP',
          onPressed: () {
            if (_emailFormKey.currentState!.validate()) {
              sendOtp(emailController.text);
            }
          },
        ),
        const SizedBox(height: 24),
        _buildTermsText(),
      ],
    );
  }

  Widget _buildOtpView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.mark_email_read_outlined,
            size: 48, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 24),
        Text(
          'Check your email',
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          "We've sent a 6-digit code to\n$email",
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
              if (value == null || value.isEmpty) return 'Please enter the OTP';
              if (value.length < 6) return 'OTP must be 6 digits';
              return null;
            },
            decoration: _buildInputDecoration(
                    'Enter OTP', '000000', Icons.password_outlined)
                .copyWith(
              counterText: "", // Hides the maxLength counter below the field
            ),
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.bold),
            onFieldSubmitted: (value) {
              if (_otpFormKey.currentState!.validate()) verifyOtp(value);
            },
          ),
        ),
        const SizedBox(height: 24),
        _buildActionButton(
          label: errorVerifyingOtp ? 'Retry Verification' : 'Verify OTP',
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
          label: const Text('Use a different email'),
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
        Icon(Icons.check_circle_outline,
            size: 48, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 24),
        Text(
          'Already Signed In',
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
          label: const Text('Sign Out'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            foregroundColor: Theme.of(context).colorScheme.error,
            side: BorderSide(
                color: Theme.of(context).colorScheme.error.withAlpha(100)),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton(
      {required String label, required VoidCallback onPressed}) {
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
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
    );
  }

  Widget _buildTermsText() {
    return Text.rich(
      TextSpan(
        text: 'By continuing, you agree to our ',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
        children: [
          TextSpan(
            text: 'Terms of Service',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
            recognizer: _termsRecognizer,
          ),
          const TextSpan(text: ' and '),
          TextSpan(
            text: 'Privacy Policy',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
            recognizer: _privacyRecognizer,
          ),
          const TextSpan(text: '.'),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}
