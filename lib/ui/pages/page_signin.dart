import '../../models/model_item.dart';
import '../../models/model_state.dart';
import '../../models/model_setting.dart';
import '../../services/service_logger.dart';
import '../../storage/storage_secure.dart';
import '../../ui/common_widgets.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../utils/common.dart';
import '../../utils/enums.dart';

class PageSignin extends StatefulWidget {
  const PageSignin({
    super.key,
  });

  @override
  State<PageSignin> createState() => _PageSigninState();
}

class _PageSigninState extends State<PageSignin> {
  final logger = AppLogger(prefixes: ["Signin"]);
  final _formKey = GlobalKey<FormState>();
  final emailController = TextEditingController();
  final otpController = TextEditingController();
  SecureStorage storage = SecureStorage();
  bool processing = false;
  bool otpSent = false;
  bool canResend = false;
  bool errorSendingOtp = false;
  bool errorVerifyingOtp = false;
  String email = ModelSetting.get(AppString.otpSentTo.string, "");
  final SupabaseClient supabase = Supabase.instance.client;
  bool signedIn = false;

  @override
  void initState() {
    super.initState();
    if (supabase.auth.currentSession == null) {
      logger.info("Not signed in");
      int sentOtpAt =
          int.parse(ModelSetting.get(AppString.otpSentAt.string, 0).toString());
      int nowUtc = DateTime.now().toUtc().millisecondsSinceEpoch;
      if (sentOtpAt > 0 && nowUtc - sentOtpAt < 900000) {
        otpSent = true;
      }
    } else {
      signedIn = true;
      String? accessToken = supabase.auth.currentSession?.accessToken;
      logger.info("Access Token: $accessToken");
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<AppSetupState>().completeSignin();
      });
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    otpController.dispose();
    super.dispose();
  }

  // OTP expire after 5min
  // Can re-send after 1min
  Future<void> sendOtp(String text) async {
    if (processing) return;
    email = text.trim();
    if (email.isNotEmpty) {
      setState(() {
        processing = true;
      });
      try {
        if (email == testEmailId) {
          await Future.delayed(const Duration(seconds: 1));
          await ModelSetting.set(AppString.simulateTesting.string, "yes");
        } else {
          await supabase.auth.signInWithOtp(
            email: email,
          );
        }
        int nowUtc = DateTime.now().toUtc().millisecondsSinceEpoch;
        await ModelSetting.set(AppString.otpSentTo.string, email);
        await ModelSetting.set(AppString.otpSentAt.string, nowUtc);
        otpSent = true;
        errorSendingOtp = false;
      } catch (e, s) {
        logger.error("sendOTP", error: e, stackTrace: s);
        errorSendingOtp = true;
        if (mounted) {
          displaySnackBar(context,
              message: 'Sending OTP failed. Please try again!', seconds: 2);
        }
      }
      if (mounted) {
        setState(() {
          processing = false;
        });
      }
    }
  }

  // cases: First time, Re-login
  Future<void> verifyOtp(String text) async {
    if (processing) return;
    final otp = text.trim();
    final String email = ModelSetting.get(AppString.otpSentTo.string, "");
    if (email.isNotEmpty && otp.isNotEmpty) {
      setState(() {
        processing = true;
      });
      try {
        Session? session;
        if (simulateTesting()) {
          if (await ModelState.get(AppString.dataSeeded.string,
                  defaultValue: "no") ==
              "no") {
            //await seedGroupsAndNotes();
            await signalToUpdateHome(); // update home with data
          }
        } else {
          try {
            final AuthResponse response = await supabase.auth.verifyOTP(
              email: email,
              token: otp,
              type: OtpType.email,
            );

            // If we reach this point without an exception, the OTP was valid.
            // A successful sign-in will return a valid session.
            if (response.session != null) {
              session = response.session;
              logger.debug(
                  'Success: Sign-in complete. User ID: ${response.user?.id}');
            } else {
              logger.debug(
                  'Warning: OTP verified, but no session was established.');
            }
          } on AuthException catch (error) {
            // Catches Supabase-specific authentication errors (e.g., wrong OTP, expired token)
            logger.debug(
                'Failure: Sign-in failed. Reason: ${error.message} (Status Code: ${error.statusCode})');
          } catch (error) {
            // Catches any other unexpected framework or network errors
            logger.debug(
                'Failure: An unexpected error occurred during sign-in: $error');
          }
        }
        if (session != null || simulateTesting()) {
          await ModelSetting.delete(AppString.otpSentTo.string);
          await ModelSetting.delete(AppString.otpSentAt.string);
          await ModelSetting.set(
              AppString.signedIn.string, "yes"); // used for simulation only
          // insert root folder: fife
          ModelItem deviceItem = await ModelItem.fromMap({
            "id": "fife",
            "name": "FiFe",
            "is_folder": 1,
          });
          await deviceItem.insert();
          if (session != null) {
            logger.info("Login Successfull");
          }
          if (mounted) {
            await context.read<AppSetupState>().completeSignin();
          }
        }
        errorVerifyingOtp = false;
      } catch (e, s) {
        logger.error("verifyOtp", error: e, stackTrace: s);
        errorVerifyingOtp = true;
        if (mounted) {
          displaySnackBar(context,
              message: 'OTP verification failed. Please try again!',
              seconds: 2);
        }
      }
      if (mounted) {
        setState(() {
          processing = false;
        });
      }
    }
  }

  Future<void> changeEmail() async {
    await ModelSetting.delete(AppString.otpSentTo.string);
    await ModelSetting.delete(AppString.otpSentAt.string);
    setState(() {
      otpSent = false;
    });
  }

  Future<void> signout() async {
    await supabase.auth.signOut();
    signedIn = false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(otpSent ? 'Verify OTP' : 'Email SignIn'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: _buildCurrentStep(),
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

  Widget _buildEmailView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Form(
          key: _formKey,
          child: TextFormField(
            autofocus: true,
            controller: emailController,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter your email';
              }
              // Email regex pattern
              final emailRegex = RegExp(
                r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
              );
              if (!emailRegex.hasMatch(value)) {
                return 'Please enter a valid email address';
              }
              return null; // Valid email
            },
            decoration: InputDecoration(
              labelText: 'Enter Email',
              labelStyle: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              hintText: 'your.email@example.com',
              hintStyle: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant
                    .withAlpha(140),
                fontSize: 16,
              ),
              prefixIcon: Icon(
                Icons.email_outlined,
                size: 24,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 20,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.outline,
                  width: 1.5,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.outline,
                  width: 1.5,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                ),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.error,
                  width: 1.5,
                ),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.error,
                  width: 2,
                ),
              ),
            ),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.5,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (value) {
              // Validate before calling sendOtp
              if (_formKey.currentState!.validate()) {
                sendOtp(value);
              }
            },
          ),
        ),
        const SizedBox(
          height: 20,
        ),
        Row(
          children: [
            Expanded(
              child: Wrap(
                runSpacing: 8.0,
                spacing: 8,
                children: [
                  const Text(
                    'By continuing, you agree to our ',
                    style: TextStyle(fontSize: 12),
                  ),
                  GestureDetector(
                    onTap: () =>
                        openURL('https://fife.jeerovan.com/policy/terms'),
                    child: const Text(
                      'Terms of Service',
                      style: TextStyle(
                        color: Colors.blue,
                        fontSize: 12,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                  const Text(
                    'and',
                    style: TextStyle(fontSize: 12),
                  ),
                  GestureDetector(
                    onTap: () =>
                        openURL('https://fife.jeerovan.com/policy/privacy'),
                    child: const Text(
                      'Privacy Policy',
                      style: TextStyle(
                        color: Colors.blue,
                        fontSize: 12,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _buildActionButton(
          label: errorSendingOtp ? 'Retry' : 'Send OTP',
          onPressed: () => {
            if (_formKey.currentState!.validate())
              {sendOtp(emailController.text)}
          },
        ),
        const Spacer(),
      ],
    );
  }

  Widget _buildOtpView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          "We have sent a one-time password (OTP) to your email $email",
        ),
        const SizedBox(height: 20),
        TextField(
          autofocus: true,
          controller: otpController,
          decoration: const InputDecoration(labelText: 'Enter OTP'),
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          onSubmitted: verifyOtp,
        ),
        const SizedBox(height: 20),
        _buildActionButton(
          label: errorVerifyingOtp ? 'Retry' : 'Verify OTP',
          onPressed: () => verifyOtp(otpController.text),
        ),
        const Spacer(),
        TextButton(
          onPressed: changeEmail,
          child: const Text('Go Back'),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildSignedInView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TextButton(
          onPressed: signout,
          child: const Text('Sign Out'),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required String label,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton(
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (processing)
            const Padding(
              padding: EdgeInsets.only(right: 8.0),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                ),
              ),
            ),
          Text(
            label,
          ),
        ],
      ),
    );
  }
}
