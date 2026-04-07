import 'dart:async';

import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/utils/utils_sync.dart';
import 'package:flutter/services.dart';

import '../storage/storage_secure.dart';
import '../utils/enums.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../services/service_logger.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/common.dart';

class AppSetupState extends ChangeNotifier {
  final SecureStorage _prefs;
  final AppLogger logger = AppLogger(prefixes: ["AppSetupState"]);
  SetupStep _currentStep = SetupStep.loading;

  // User data
  String? _selectedPlan;

  AppSetupState(this._prefs) {
    _checkSetupStatus();
  }

  // Getters
  SetupStep get currentStep => _currentStep;
  String? get selectedPlan => _selectedPlan;

  // Check all setup steps on app start
  Future<void> _checkSetupStatus() async {
    logger.info("Checking..");
    _currentStep = SetupStep.loading;
    notifyListeners();

    bool onboarded =
        ModelSetting.get(AppString.onboarding.string, defaultValue: "no") ==
            "yes";
    if (!onboarded) {
      logger.info("Onboarding");
      _currentStep = SetupStep.onboard;
      notifyListeners();
      return;
    }

    if (getSignedInUserId() == null) {
      logger.info("Signin");
      _currentStep = SetupStep.signin;
      notifyListeners();
      return;
    }

    // Check security key
    String? securityKey = await _prefs.read(key: AppString.masterKey.string);
    if (securityKey == null) {
      logger.info("SecurityKey");
      _currentStep = SetupStep.checkAccessKey;
      notifyListeners();
      return;
    }

    // Check device registration
    String deviceId = await getDeviceId();
    if (deviceId.isEmpty) {
      logger.info("Registration");
      _currentStep = SetupStep.registerDevice;
      notifyListeners();
      return;
    }

    PermissionStatus storagePermission = await getStoragePermissionStatus();
    if (!storagePermission.isGranted) {
      logger.info("Storage Permission");
      _currentStep = SetupStep.storagePermission;
      notifyListeners();
      return;
    }

    // All setup complete
    SyncUtils.waitAndSyncChanges();
    _currentStep = SetupStep.explorer;
    notifyListeners();
  }

  // Onboarded
  Future<void> onBoarded() async {
    _currentStep = SetupStep.signin;
    notifyListeners();
  }

  // Registration
  Future<void> completeSignin() async {
    _currentStep = SetupStep.checkAccessKey;
    notifyListeners();
  }

  // Security key
  Future<void> decodeAccessKey() async {
    _currentStep = SetupStep.decodeAccessKey;
    notifyListeners();
  }

  Future<void> generateAccessKey() async {
    _currentStep = SetupStep.generateAccessKey;
    notifyListeners();
  }

  Future<void> showAccessKeys() async {
    _currentStep = SetupStep.showAccessKey;
    notifyListeners();
  }

  // Device setup
  Future<void> registerDevice() async {
    _currentStep = SetupStep.registerDevice;
    notifyListeners();
  }

  Future<void> manageDevices() async {
    _currentStep = SetupStep.manageDevices;
    notifyListeners();
  }

  Future<void> deviceRegistered() async {
    _currentStep = SetupStep.storagePermission;
    notifyListeners();
  }

  Future<void> showExplorer() async {
    _currentStep = SetupStep.explorer;
    notifyListeners();
  }

  // Logout / Reset
  Future<void> logout() async {
    bool signedOut = await SyncUtils.signout();
    if (signedOut) {
      _selectedPlan = null;
      _currentStep = SetupStep.signin;
      notifyListeners();
    }
  }

  // Force recheck (useful after app resumes from background)
  Future<void> recheckStatus() async {
    await _checkSetupStatus();
  }
}

class MessageInCenter extends StatelessWidget {
  final String text;

  const MessageInCenter({
    super.key,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(text),
          ),
        ],
      ),
    );
  }
}

class Loading extends StatelessWidget {
  const Loading({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
        ],
      ),
    );
  }
}

class FloatingActionButtonWithBadge extends StatelessWidget {
  final int filterCount;
  final VoidCallback onPressed;
  final Icon icon;
  final String heroTag;

  const FloatingActionButtonWithBadge({
    super.key,
    required this.filterCount,
    required this.onPressed,
    required this.icon,
    required this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.topRight,
      clipBehavior:
          Clip.none, // Allows the badge to be positioned outside the FAB
      children: [
        FloatingActionButton(
          heroTag: heroTag,
          shape: const CircleBorder(),
          onPressed: onPressed,
          child: icon,
        ),
        if (filterCount > 0)
          Positioned(
            right: -6,
            top: -6,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white),
              ),
              constraints: const BoxConstraints(
                minWidth: 20,
                minHeight: 20,
              ),
              child: Text(
                '$filterCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}

class WidgetKeyValueTable extends StatelessWidget {
  final Map data;

  const WidgetKeyValueTable({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Table(
      columnWidths: const {
        0: IntrinsicColumnWidth(), // Column for keys
        1: IntrinsicColumnWidth(), // Column for values
      },
      children: data.entries.map((entry) {
        return TableRow(
          children: [
            Container(
              padding: const EdgeInsets.all(11.0),
              child: Text(
                capitalize(entry.key),
                textAlign: TextAlign.right,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(color: Theme.of(context).colorScheme.primary),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                entry.value.toString(),
                textAlign: TextAlign.left,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        );
      }).toList(),
    );
  }
}

// Try failed request again
Widget tryFailedRequestAgain(
    {required String message,
    required TextStyle? style,
    required Function() onPressed}) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: style,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onPressed,
            icon: const Icon(Icons.refresh),
            label: const Text("Try Again"),
          ),
        ],
      ),
    ),
  );
}

class CrossPlatformBackHandler extends StatelessWidget {
  final Widget child;

  /// The manual action to trigger when back/ESC is pressed.
  final VoidCallback onManualBack;

  /// Determines if the system can pop automatically.
  /// Set to false to block default behavior and use [onManualBack].
  final bool canPop;

  const CrossPlatformBackHandler({
    super.key,
    required this.child,
    required this.onManualBack,
    this.canPop = false,
  });

  @override
  Widget build(BuildContext context) {
    // 1. CallbackShortcuts handles hardware keyboard events (Desktop ESC key)
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): onManualBack,
      },
      // Focus ensures the keyboard listener is active on this screen
      child: Focus(
        autofocus: true,
        // 2. PopScope handles Android back button / iOS swipe (replaces WillPopScope)
        child: PopScope(
          canPop: canPop,
          onPopInvokedWithResult: (bool didPop, Object? result) {
            // If the system already popped (canPop was true), do nothing to avoid duplicate pops.
            if (didPop) return;

            // Otherwise, trigger your custom manual logic
            onManualBack();
          },
          child: child,
        ),
      ),
    );
  }
}

/// Helper method to build the toolbar layout cleanly
Widget buildBottomAppBar({
  required Color color,
  Widget? leading,
  required Widget title,
  required List<Widget> actions,
}) {
  return Container(
    color: color,
    child: SafeArea(
      top: false, // Crucial: prevents the status bar padding issue
      bottom: true, // Protects against bottom system navigation bars
      child: SizedBox(
        height: 64.0, // Standard Material 3 toolbar height
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(width: 4.0),
            if (leading != null) leading,
            if (leading == null)
              const SizedBox(width: 16.0), // Padding if no leading icon
            Expanded(
              // Expanded forces the title/breadcrumb to take up remaining space
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: title,
              ),
            ),
            ...actions,
            const SizedBox(width: 4.0),
          ],
        ),
      ),
    ),
  );
}

class WidgetTextWithLinks extends StatefulWidget {
  final String text;
  final TextAlign? align;

  const WidgetTextWithLinks({super.key, required this.text, this.align});

  @override
  State<WidgetTextWithLinks> createState() => _WidgetTextWithLinksState();
}

class _WidgetTextWithLinksState extends State<WidgetTextWithLinks> {
  @override
  Widget build(BuildContext context) {
    return Consumer<FontSizeController>(builder: (context, controller, child) {
      return RichText(
        text: TextSpan(
          children: _buildTextWithLinks(context, controller, widget.text),
        ),
        textAlign: widget.align == null ? TextAlign.left : widget.align!,
      );
    });
  }

  List<TextSpan> _buildTextWithLinks(
      BuildContext context, FontSizeController controller, String text) {
    final List<TextSpan> spans = [];
    final RegExp linkRegExp = RegExp(r'(https?://[^\s]+)');
    final matches = linkRegExp.allMatches(text);

    int lastMatchEnd = 0;

    double fontSize = 15;

    for (final match in matches) {
      final start = match.start;
      final end = match.end;

      // Add plain text before the link
      if (start > lastMatchEnd) {
        spans.add(
          TextSpan(
              text: text.substring(lastMatchEnd, start),
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: controller.getScaledSize(fontSize))),
        );
      }

      // Add the link text
      final linkText = text.substring(start, end);
      try {
        final linkUri = Uri.parse(linkText);
        spans.add(TextSpan(
          text: linkText,
          style: TextStyle(
              color: Colors.blue, fontSize: controller.getScaledSize(fontSize)),
          recognizer: TapGestureRecognizer()
            ..onTap = () async {
              if (await canLaunchUrl(linkUri)) {
                await launchUrl(linkUri);
              } else {
                final logger = AppLogger(
                    prefixes: ["common_widgets", "WidgetTextWithLink"]);
                logger.error("Could not launch $linkText");
              }
            },
        ));
      } catch (e) {
        spans.add(
          TextSpan(
              text: linkText,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: controller.getScaledSize(fontSize))),
        );
      }

      lastMatchEnd = end;
    }

    // Add the remaining plain text after the last link
    if (lastMatchEnd < text.length) {
      spans.add(TextSpan(
          text: text.substring(lastMatchEnd),
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: controller.getScaledSize(fontSize),
          )));
    }

    return spans;
  }
}

class TimerWidget extends StatefulWidget {
  final int runningState;

  const TimerWidget({
    super.key,
    required this.runningState,
  });

  @override
  State<TimerWidget> createState() => TimerWidgetState();
}

class TimerWidgetState extends State<TimerWidget> {
  late int _secondsElapsed;
  Timer? _timer;
  int runningState = 0;

  @override
  void initState() {
    super.initState();
    _secondsElapsed = 0; // Initialize timer duration
  }

  @override
  void dispose() {
    _timer?.cancel(); // Clean up the timer when the widget is disposed
    super.dispose();
  }

  /// Start the timer
  void start() {
    if (_timer != null && _timer!.isActive) return; // Prevent multiple timers
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _secondsElapsed++;
      });
    });
  }

  /// Stop the timer
  void stop() {
    _timer?.cancel();
  }

  /// Reset the timer
  void reset() {
    stop();
    setState(() {
      _secondsElapsed = 0;
    });
  }

  String get _formattedTime {
    final minutes = (_secondsElapsed ~/ 60).toString().padLeft(2, '0');
    final seconds = (_secondsElapsed % 60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  void setRunningState() {
    if (widget.runningState == 2) {
      stop();
    } else if (widget.runningState == 1) {
      start();
    } else if (widget.runningState == 0) {
      reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    setRunningState();
    return Text(
      _formattedTime,
      style: TextStyle(
        color: Colors.red,
        fontSize: 16.0,
      ),
    );
  }
}

Future<void> displaySnackBar(BuildContext context,
    {required String message, required int seconds}) async {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(
      message,
    ),
    duration: Duration(seconds: seconds),
  ));
}

class ColorPickerDialog extends StatefulWidget {
  final String? color;

  const ColorPickerDialog({super.key, this.color});

  @override
  State<ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<ColorPickerDialog> {
  Color selectedColor = colorFromHex("#06b6d4"); // Default selected color
  double hue = 0.0; // Default hue for the color bar

  @override
  void initState() {
    super.initState();
    if (widget.color != null) {
      selectedColor = colorFromHex(widget.color!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      content: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 15.0, // Horizontal spacing between circles
              runSpacing: 15.0, // Vertical spacing between rows
              children: predefinedColors.map((color) {
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      selectedColor = color;
                    });
                  },
                  child: CircleAvatar(
                    backgroundColor: color,
                    radius: 15, // Fixed size for the circles
                    child: selectedColor == color
                        ? Icon(Icons.check, color: Colors.white, size: 16)
                        : null,
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 16),

            // Fourth row with color preview and slider
            Row(
              children: [
                // Circle to show the selected color
                CircleAvatar(
                  backgroundColor: selectedColor,
                  radius: 15,
                ),
                const SizedBox(width: 10),

                // Color slider
                Expanded(
                  child: Stack(
                    alignment: AlignmentDirectional.center,
                    children: [
                      // HSV gradient as slider background
                      Padding(
                        padding: const EdgeInsets.only(left: 15, right: 15),
                        child: Container(
                          height: 30,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                for (double i = 0; i <= 1; i += 0.1)
                                  HSVColor.fromAHSV(1.0, i * 360, 1.0, 1.0)
                                      .toColor()
                              ],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                          ),
                        ),
                      ),

                      // Actual slider overlay
                      Slider(
                        value: hue,
                        onChanged: (newHue) {
                          setState(() {
                            hue = newHue;
                            selectedColor =
                                HSVColor.fromAHSV(1.0, hue * 360, 1.0, 1.0)
                                    .toColor();
                          });
                        },
                        min: 0.0,
                        max: 1.0,
                        activeColor: Colors.transparent,
                        // Transparent for gradient
                        inactiveColor: Colors.transparent,
                        thumbColor: Colors.transparent,
                        secondaryActiveColor: Colors.transparent,
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(null); // Cancel action
          },
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(selectedColor); // Return selected color
          },
          child: const Text('Ok'),
        ),
      ],
    );
  }
}

class AnimatedWidgetSwap extends StatefulWidget {
  final Widget firstWidget;
  final Widget secondWidget;
  final bool showFirst;
  final Duration duration;

  const AnimatedWidgetSwap({
    super.key,
    required this.firstWidget,
    required this.secondWidget,
    required this.showFirst,
    this.duration = const Duration(milliseconds: 300),
  });

  @override
  State<AnimatedWidgetSwap> createState() => _AnimatedWidgetSwapState();
}

class _AnimatedWidgetSwapState extends State<AnimatedWidgetSwap>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideOutAnimation;
  late Animation<Offset> _slideInAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    _slideOutAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(1.0, 0.0),
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _slideInAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void didUpdateWidget(AnimatedWidgetSwap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.showFirst != widget.showFirst) {
      if (widget.showFirst) {
        _controller.reverse();
      } else {
        _controller.forward();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SlideTransition(
          position: _slideOutAnimation,
          child: widget.showFirst ? widget.firstWidget : Container(),
        ),
        SlideTransition(
          position: _slideInAnimation,
          child: widget.showFirst ? Container() : widget.secondWidget,
        ),
      ],
    );
  }
}

class AnimatedPageRoute extends PageRouteBuilder {
  final Widget child;

  AnimatedPageRoute({required this.child})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) => child,
          transitionDuration: const Duration(milliseconds: 150),
          reverseTransitionDuration: const Duration(milliseconds: 150),
        );

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    // Animation for the new screen (Child)
    const curve = Curves.linear;
    final childSlideAnimation = Tween(
      begin: const Offset(0.0, 0.02),
      end: Offset.zero,
    ).chain(CurveTween(curve: curve)).animate(animation);

    final childFadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).chain(CurveTween(curve: curve)).animate(animation);

    // Animation for the previous screen (Parent)
    final parentScaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).chain(CurveTween(curve: curve)).animate(secondaryAnimation);

    final parentFadeAnimation = Tween<double>(
      begin: 1.0,
      end: 0.8,
    ).chain(CurveTween(curve: curve)).animate(secondaryAnimation);

    return Stack(
      children: [
        // Animate the Parent screen
        FadeTransition(
          opacity: parentFadeAnimation,
          child: ScaleTransition(
            scale: parentScaleAnimation,
            child: Container(), // This will be the parent screen
          ),
        ),
        // Animate the Child screen
        FadeTransition(
          opacity: childFadeAnimation,
          child: SlideTransition(
            position: childSlideAnimation,
            child: child,
          ),
        ),
      ],
    );
  }
}

class UploadDownloadIndicator extends StatefulWidget {
  final double size;
  final bool uploading;
  const UploadDownloadIndicator(
      {super.key, required this.size, required this.uploading});
  @override
  State<UploadDownloadIndicator> createState() =>
      UploadDownloadIndicatorState();
}

class UploadDownloadIndicatorState extends State<UploadDownloadIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: Duration(seconds: 1),
    )..repeat(reverse: true);

    _fadeAnimation = Tween<double>(begin: 0.2, end: 1.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Opacity(
        opacity: 0.6,
        child: Icon(
          widget.uploading ? Icons.arrow_upward : Icons.arrow_downward,
          size: widget.size,
        ),
      ),
    );
  }
}

class DownloadButton extends StatefulWidget {
  final VoidCallback onPressed;
  final double iconSize;

  const DownloadButton({
    super.key,
    this.iconSize = 30.0,
    required this.onPressed, // Default icon size
  });

  @override
  State<DownloadButton> createState() => _DownloadButtonState();
}

class _DownloadButtonState extends State<DownloadButton> {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Theme.of(context).colorScheme.onSurface.withAlpha(50),
          width: 2.0,
        ),
      ),
      child: IconButton(
        tooltip: "Download",
        icon: Opacity(
          opacity: 0.5,
          child: Icon(
            Icons.arrow_downward,
            size: widget.iconSize,
          ),
        ),
        onPressed: widget.onPressed,
      ),
    );
  }
}

class VideoPlayDownloadButton extends StatelessWidget {
  final double iconSize;
  final bool showPlay;
  final VoidCallback onPressed;
  const VideoPlayDownloadButton(
      {super.key,
      required this.iconSize,
      required this.showPlay,
      required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      width: iconSize,
      height: iconSize,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        // Semi-transparent grey background
        shape: BoxShape.circle,
      ),
      child: showPlay
          ? Icon(
              LucideIcons.play,
              color: Colors.white,
              size: iconSize / 2,
            )
          : IconButton(
              tooltip: "Download",
              icon: Icon(
                Icons.arrow_downward,
                color: Colors.white,
                size: iconSize / 2,
              ),
              onPressed: onPressed,
            ),
    );
  }
}

class ImageDownloadButton extends StatefulWidget {
  final VoidCallback onPressed;
  final double iconSize;
  const ImageDownloadButton({
    super.key,
    required this.iconSize,
    required this.onPressed,
  });

  @override
  State<ImageDownloadButton> createState() => _ImageDownloadButtonState();
}

class _ImageDownloadButtonState extends State<ImageDownloadButton> {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.iconSize,
      height: widget.iconSize,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        // Semi-transparent grey background
        shape: BoxShape.circle,
      ),
      child: IconButton(
        tooltip: "Download",
        icon: Icon(
          Icons.arrow_downward,
          color: Colors.white,
          size: widget.iconSize / 2,
        ),
        onPressed: widget.onPressed,
      ),
    );
  }
}
