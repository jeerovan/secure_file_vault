import 'dart:async';
import 'dart:io';

import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/utils/utils_sync.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import '../models/model_file.dart';
import '../models/model_item.dart';
import '../models/model_item_task.dart';
import '../services/service_events.dart';
import '../storage/storage_secure.dart';
import '../utils/enums.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../services/service_logger.dart';
import 'package:permission_handler/permission_handler.dart';

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

    if (ModelSetting.get(AppString.signedIn.string, defaultValue: "no") ==
        "no") {
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
    String deviceId = await getDeviceUuid();
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

class PrivacyTermsWidget extends StatefulWidget {
  const PrivacyTermsWidget({super.key});

  @override
  State<PrivacyTermsWidget> createState() => _PrivacyTermsWidgetState();
}

class _PrivacyTermsWidgetState extends State<PrivacyTermsWidget> {
  late TapGestureRecognizer termsRecognizer;

  late TapGestureRecognizer privacyRecognizer;

  @override
  void initState() {
    super.initState();
    _setupGestureRecognizers();
  }

  @override
  void dispose() {
    termsRecognizer.dispose();
    privacyRecognizer.dispose();
    super.dispose();
  }

  void _setupGestureRecognizers() {
    termsRecognizer = TapGestureRecognizer()
      ..onTap = () => openURL('https://fife.jeero.one/terms');
    privacyRecognizer = TapGestureRecognizer()
      ..onTap = () => openURL('https://fife.jeero.one/privacy');
  }

  @override
  Widget build(BuildContext context) {
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
            recognizer: termsRecognizer,
          ),
          const TextSpan(text: ' and '),
          TextSpan(
            text: 'Privacy Policy',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
            recognizer: privacyRecognizer,
          ),
          const TextSpan(text: '.'),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
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

class FileListItem extends StatefulWidget {
  final ModelItem item;
  final ValueNotifier<Set<ModelItem>> selectedItemsNotifier;
  final ValueNotifier<bool> isMultiSelectNotifier;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const FileListItem({
    required super.key,
    required this.item,
    required this.selectedItemsNotifier,
    required this.isMultiSelectNotifier,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  State<FileListItem> createState() => _FileListItemState();
}

class _FileListItemState extends State<FileListItem> {
  bool? _isLocal;
  bool? _isUploaded;
  bool _isUploading = false;
  bool _isDownloading = false;
  int transferProgress = 0;
  AppLogger logger = AppLogger(prefixes: ["FileListItem"]);

  @override
  void initState() {
    super.initState();
    if (!widget.item.isFolder) {
      _checkFileStates();
    }
    EventStream().notifier.addListener(_handleItemUpdateEvent);
  }

  @override
  void didUpdateWidget(covariant FileListItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-check statuses if the underlying item changes (e.g., during recycling in ListView)
    if (oldWidget.item.id != widget.item.id && !widget.item.isFolder) {
      _checkFileStates();
    }
  }

  @override
  void dispose() {
    EventStream().notifier.removeListener(_handleItemUpdateEvent);
    super.dispose();
  }

  void _handleItemUpdateEvent() {
    if (!mounted) return;
    final AppEvent? event = EventStream().notifier.value;
    if (event == null) return;

    switch (event.type) {
      case EventType.updateItem:
        if (event.key == EventKey.uploaded) {
          if (event.id == widget.item.id) {
            setState(() {
              _isUploaded = true;
              _isUploading = false;
              transferProgress = 0;
            });
          }
        } else if (event.key == EventKey.downloaded) {
          if (event.id == widget.item.id) {
            setState(() {
              _isLocal = true;
              _isDownloading = false;
              transferProgress = 0;
            });
          }
        } else if (event.key == EventKey.uploadProgress) {
          if (event.id == widget.item.id) {
            setState(() {
              transferProgress = event.value;
              _isUploading = true;
            });
          }
        } else if (event.key == EventKey.downloadProgress) {
          if (event.id == widget.item.id) {
            setState(() {
              transferProgress = event.value;
              _isDownloading = true;
            });
          }
        }
        break;
      default:
        break;
    }
  }

  Future<bool> fileExistsLocally(ModelItem item) async {
    String path = await ModelItem.getPathForItem(item.id);
    return await File(path).exists();
  }

  Future<bool> fileUploadedToCloud(ModelItem item) async {
    ModelFile? modelFile = await ModelFile.get(item.fileHash!);
    if (modelFile != null) {
      return modelFile.uploadedAt > 0;
    }
    return false;
  }

  Future<int> getUploadProgress(ModelItem item) async {
    ModelItemTask? itemTask = await ModelItemTask.get(item.id);
    if (itemTask != null && itemTask.task == ItemTask.upload.value) {
      return itemTask.progress;
    } else {
      return -1;
    }
  }

  Future<int> getDownloadProgress(ModelItem item) async {
    ModelItemTask? itemTask = await ModelItemTask.get(item.id);
    if (itemTask != null && itemTask.task == ItemTask.download.value) {
      return itemTask.progress;
    } else {
      return -1;
    }
  }

  Future<void> _checkFileStates() async {
    // Run both async tasks concurrently for optimal performance
    final stateResults = await Future.wait([
      fileExistsLocally(widget.item),
      widget.item.isFolder
          ? Future.value(false)
          : fileUploadedToCloud(widget.item),
    ]);

    final transferResults = await Future.wait(
        [getUploadProgress(widget.item), getDownloadProgress(widget.item)]);

    // Always check if the widget is still in the tree before calling setState
    if (!mounted) return;

    setState(() {
      _isLocal = stateResults[0];
      _isUploaded = stateResults[1];
      if (transferResults[0] > -1) {
        _isUploading = true;
        transferProgress = transferResults[0];
      } else if (transferResults[1] > -1) {
        _isDownloading = true;
        transferProgress = transferResults[1];
      }
    });
  }

  Widget _buildTrailingIndicator() {
    if (_isUploading || _isDownloading) {
      return TransferAnimatedIcon(isUpload: _isUploading);
    }
    if (_isUploaded == null) {
      // Show a subtle, tiny loading spinner while checking cloud status
      return const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    if (_isUploaded!) {
      return Icon(
        Icons.check,
        size: 16,
        color: Theme.of(context).colorScheme.primary.withAlpha(150),
      );
    }

    return SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
        listenable: Listenable.merge(
            [widget.selectedItemsNotifier, widget.isMultiSelectNotifier]),
        builder: (context, _) {
          final isSelected =
              widget.selectedItemsNotifier.value.contains(widget.item);
          final isMultiSelectMode = widget.isMultiSelectNotifier.value;
          final theme = Theme.of(context);

          return Stack(children: [
            // --- 1. Progress Background ---
            Positioned.fill(
              child: Align(
                // Automatically handles LTR (starts left) and RTL (starts right)
                alignment: AlignmentDirectional.centerStart,
                // Smoothly animates the width changes as data arrives
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: transferProgress / 100),
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) {
                    return FractionallySizedBox(
                      widthFactor: value,
                      heightFactor: 1.0,
                      child: Container(
                        // Using a subtle primary container color for the progress fill
                        color:
                            theme.colorScheme.primaryContainer.withAlpha(100),
                      ),
                    );
                  },
                ),
              ),
            ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onTap,
                onLongPress: widget.onLongPress,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8.0, vertical: 8.0),
                  child: Row(
                    children: [
                      // 1. Multi-Select Circular Checkbox
                      AnimatedSize(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOutCubic,
                        child: SizedBox(
                          width: 18,
                          child: isMultiSelectMode
                              ? Row(
                                  children: [
                                    AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 200),
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: isSelected
                                            ? Colors.grey.shade600
                                            : Colors.transparent,
                                        border: Border.all(
                                          color: isSelected
                                              ? Colors.grey.shade600
                                              : theme.colorScheme.outline,
                                          width: 2,
                                        ),
                                      ),
                                      child: null,
                                    ),
                                  ],
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),

                      // 2. File / Folder Icon
                      SizedBox(
                        width: 30,
                        height: 30,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            if (widget.item.isFolder)
                              Align(
                                alignment: Alignment.center,
                                child: Icon(LucideIcons.folder,
                                    size: 28,
                                    color: theme.colorScheme.primary
                                        .withAlpha(150)),
                              ),

                            // Local Existence Indicator (Grey while loading, then Red/Green)
                            if (!widget.item.isFolder)
                              Align(
                                alignment: Alignment.center,
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: _isLocal == null
                                        ? Colors.grey.shade400 // Loading state
                                        : (_isLocal!
                                            ? Colors.green
                                            : Colors.red),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Theme.of(context)
                                          .scaffoldBackgroundColor,
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),

                      const SizedBox(width: 4),

                      // 3. File Details
                      Expanded(
                          child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            widget.item.name,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w500,
                              color: theme.colorScheme.onSurface,
                              height:
                                  1.2, // Tighter line height for better vertical rhythm in lists
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          // Only display if it is a file
                          if (!widget.item.isFolder) ...[
                            const SizedBox(
                                height:
                                    2), // Subtle spacing separates title from metadata
                            Text(
                              readableFileSizeFromBytes(widget.item.size),
                              style: theme.textTheme.bodySmall?.copyWith(
                                // onSurfaceVariant provides the perfect professional muted contrast
                                // against the onSurface title color
                                color: theme.colorScheme.onSurfaceVariant,
                                letterSpacing:
                                    0.1, // Enhances readability for small alphanumeric text
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      )),

                      const SizedBox(width: 8),

                      // 4. State Indicators (Cloud / Local)
                      if (!widget.item.isFolder) _buildTrailingIndicator()
                    ],
                  ),
                ),
              ),
            )
          ]);
        });
  }
}

class TransferAnimatedIcon extends StatefulWidget {
  final bool isUpload;

  const TransferAnimatedIcon({super.key, required this.isUpload});

  @override
  State<TransferAnimatedIcon> createState() => _TransferAnimatedIconState();
}

class _TransferAnimatedIconState extends State<TransferAnimatedIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _revealAnimation;
  late final Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();

    // 1. Slow, 2-second duration for a calming, smooth effect
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    // 2. The arrow reveals gradually over the first 70% of the animation.
    // Curves.easeInOutCubic makes the start and end of the fill very smooth.
    _revealAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.7, curve: Curves.easeInOutCubic),
      ),
    );

    // 3. Holds full visibility, then smoothly fades out during the last 20%
    // to create a seamless, non-jarring loop.
    _opacityAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 80),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.0).chain(
          CurveTween(curve: Curves.easeOut),
        ),
        weight: 20,
      ),
    ]).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final iconData = widget.isUpload
        ? Icons.arrow_upward_rounded
        : Icons.arrow_downward_rounded;

    final iconColor = Theme.of(context).colorScheme.primary;

    // Determine alignments:
    // - Upload reveals bottom-to-top (anchored to bottomCenter)
    // - Download reveals top-to-bottom (anchored to topCenter)
    final alignment =
        widget.isUpload ? Alignment.bottomCenter : Alignment.topCenter;

    return SizedBox(
      width: 24,
      height: 24,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Stack(
            alignment: alignment,
            children: [
              // Background Icon (Track)
              // Using Opacity widget avoids the recently deprecated Color.withOpacity()
              Opacity(
                opacity: 0.2,
                child: Icon(
                  iconData,
                  color: iconColor,
                  size: 20,
                ),
              ),

              // Animated Foreground Icon (Fill)
              Opacity(
                opacity: _opacityAnimation.value,
                child: ClipRect(
                  child: Align(
                    alignment: alignment,
                    heightFactor: _revealAnimation.value,
                    widthFactor: 1.0,
                    child: Icon(
                      iconData,
                      color: iconColor,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class AnimatedSyncButton extends StatefulWidget {
  final bool isSyncing;
  final VoidCallback onPressed;

  const AnimatedSyncButton({
    super.key,
    required this.isSyncing,
    required this.onPressed,
  });

  @override
  State<AnimatedSyncButton> createState() => _AnimatedSyncButtonState();
}

class _AnimatedSyncButtonState extends State<AnimatedSyncButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 1), // Adjust rotation speed here
      vsync: this,
    );

    if (widget.isSyncing) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(AnimatedSyncButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSyncing != oldWidget.isSyncing) {
      if (widget.isSyncing) {
        _controller.repeat();
      } else {
        // Smoothly completes the current rotation instead of snapping abruptly
        _controller
            .animateTo(1.0, duration: const Duration(milliseconds: 300))
            .then((_) {
          if (mounted) _controller.reset();
        });
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
    return IconButton(
      // Optional UX enhancement: disable button while syncing to prevent duplicate calls
      onPressed: widget.isSyncing ? null : widget.onPressed,
      icon: RotationTransition(
        turns: _controller,
        child: const Icon(LucideIcons.refreshCw),
      ),
    );
  }
}
