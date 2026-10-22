import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A full-height list with retained, portrait-only pull-down reachability.
///
/// One scroll coordinate consumes a drag exactly once: negative pixels reveal
/// reach space; positive pixels scroll content. Only direct dragging may expand
/// the negative range. Release holds that position, without a timed transition
/// or spring. Ordinary scrolling and accessibility actions remain available.
class ThumbReachListView extends StatefulWidget {
  const ThumbReachListView({
    super.key,
    required this.children,
    this.controller,
    this.padding,
    this.reverse = false,
  });

  final List<Widget> children;
  final ThumbReachScrollController? controller;
  final EdgeInsetsGeometry? padding;
  final bool reverse;

  @override
  State<ThumbReachListView> createState() => _ThumbReachListViewState();
}

class _ThumbReachListViewState extends State<ThumbReachListView> {
  final _ownedController = ThumbReachScrollController();
  ThumbReachScrollController get _controller =>
      widget.controller ?? _ownedController;

  @override
  void dispose() {
    _ownedController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final platform = Theme.of(context).platform;
    final mobile =
        platform == TargetPlatform.android || platform == TargetPlatform.iOS;
    final content = LayoutBuilder(builder: (context, constraints) {
      assert(constraints.hasBoundedHeight,
          'Thumb reach needs the bounded, safe content viewport.');
      final height = constraints.hasBoundedHeight
          ? math.max(0.0, constraints.maxHeight)
          : 0.0;
      final allowance =
          mobile && !widget.reverse && media.orientation == Orientation.portrait
              ? math.max(0.0, height - 360.0)
              : 0.0;
      _controller.configure((
        constraints.biggest,
        media.size,
        media.padding,
        media.viewPadding,
        media.viewInsets,
        mobile,
        widget.reverse
      ), mobile: mobile, allowance: allowance);
      final list = ListView(
        controller: _controller,
        reverse: widget.reverse,
        physics: mobile ? const _ThumbReachPhysics() : null,
        padding: widget.padding,
        // A fresh delegate also relays out unchanged rows when only inset
        // metadata changes, after the layout-time reach reset below.
        children: [...widget.children],
      );
      return mobile
          ? ScrollConfiguration(
              behavior:
                  ScrollConfiguration.of(context).copyWith(overscroll: false),
              child: list)
          : list;
    });
    // The caller owns fixed bottom controls and their inset. SafeArea removes
    // the other system insets once, before measuring the content viewport.
    return mobile ? SafeArea(bottom: false, child: content) : content;
  }
}

/// Supply the same controller above the screen's Scaffold using
/// [PrimaryScrollController] to retain native status-bar scroll-to-top.
class ThumbReachScrollController extends ScrollController {
  Object? _geometry;
  bool _mobile = false;
  double _allowance = 0;

  void configure(Object geometry,
      {required bool mobile, required double allowance}) {
    final reset = geometry != _geometry;
    _geometry = geometry;
    _mobile = mobile;
    _allowance = allowance;
    for (final position in positions.cast<_ThumbReachPosition>()) {
      position.configure(mobile, allowance, reset: reset);
    }
  }

  @override
  ScrollPosition createScrollPosition(ScrollPhysics physics,
          ScrollContext context, ScrollPosition? oldPosition) =>
      _ThumbReachPosition(
          physics: physics,
          context: context,
          oldPosition: oldPosition,
          mobile: _mobile,
          allowance: _allowance,
          keepScrollOffset: keepScrollOffset);
}

class _ThumbReachPosition extends ScrollPositionWithSingleContext {
  _ThumbReachPosition({
    required super.physics,
    required super.context,
    ScrollPosition? oldPosition,
    required super.keepScrollOffset,
    required bool mobile,
    required double allowance,
  })  : _mobile = mobile,
        _allowance = allowance,
        super(initialPixels: 0, oldPosition: oldPosition) {
    if (mobile && oldPosition == null && pixels < 0) correctPixels(0);
  }

  bool _mobile;
  double _allowance;
  bool _directDrag = false;

  void configure(bool mobile, double allowance, {required bool reset}) {
    final hadMobileReach = _mobile && hasPixels && pixels < 0;
    _mobile = mobile;
    _allowance = allowance;
    if (reset && hasPixels && pixels < 0 && (mobile || hadMobileReach)) {
      // Called by LayoutBuilder before the viewport is laid out. Correct only
      // reach pixels: positive content offsets keep their normal restoration.
      correctPixels(0);
    }
  }

  @override
  void applyUserOffset(double delta) {
    _directDrag = true;
    try {
      super.applyUserOffset(delta);
    } finally {
      _directDrag = false;
    }
  }

  @override
  void goBallistic(double velocity) {
    if (_mobile && pixels < 0) {
      goIdle();
    } else {
      super.goBallistic(velocity);
    }
  }

  @override
  void jumpTo(double value) =>
      super.jumpTo(_mobile ? math.max(0.0, value) : value);

  @override
  Future<void> animateTo(double to,
          {required Duration duration, required Curve curve}) =>
      super.animateTo(_mobile ? math.max(0.0, to) : to,
          duration: duration, curve: curve);

  @override
  void pointerScroll(double delta) {
    if (_mobile && pixels < 0) {
      if (delta > 0) {
        // Wheel/trackpad scrolling may remove retained reach, never expand it.
        super.jumpTo(math.min(maxScrollExtent, pixels + delta));
      }
    } else {
      super.pointerScroll(delta);
    }
  }

  double get _savedPixels => _mobile ? math.max(0.0, pixels) : pixels;

  @override
  void restoreOffset(double offset, {bool initialRestore = false}) =>
      super.restoreOffset(_mobile ? math.max(0.0, offset) : offset,
          initialRestore: initialRestore);

  @override
  void saveScrollOffset() => PageStorage.maybeOf(context.storageContext)
      ?.writeState(context.storageContext, _savedPixels);

  @override
  void saveOffset() => context.saveOffset(_savedPixels);
}

class _ThumbReachPhysics extends ClampingScrollPhysics {
  const _ThumbReachPhysics({super.parent});

  @override
  _ThumbReachPhysics applyTo(ScrollPhysics? ancestor) =>
      _ThumbReachPhysics(parent: buildParent(ancestor));

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) => true;

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) =>
      offset;

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    if (position is _ThumbReachPosition && value < 0) {
      final floor = position._directDrag
          ? -position._allowance
          : math.min(0.0, position.pixels);
      return value < floor ? value - math.min(position.pixels, floor) : 0;
    }
    return super.applyBoundaryConditions(position, value);
  }
}
