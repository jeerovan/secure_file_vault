import 'dart:async';

class BackgroundSyncInterrupted implements Exception {
  const BackgroundSyncInterrupted(this.reason);
  final String reason;
  @override
  String toString() => 'Background sync interrupted: $reason';
}

/// Scoped to the headless isolate. Foreground sync has no imposed budget.
class SyncBudget {
  SyncBudget({
    required DateTime deadline,
    this.maxRoots = 2,
    this.maxScanItems = 256,
    this.maxMetadataPages = 4,
    Duration Function()? elapsed,
  })  : _duration = deadline.difference(DateTime.now()),
        _elapsed = elapsed ?? (Stopwatch()..start()).elapsedDurationGetter {
    _timer = Timer(_duration.isNegative ? Duration.zero : _duration,
        () => cancel('deadline'));
  }

  static final Object _zoneKey = Object();
  static SyncBudget? get current => Zone.current[_zoneKey] as SyncBudget?;
  final Duration _duration;
  final Duration Function() _elapsed;
  final int maxRoots;
  final int maxScanItems;
  final int maxMetadataPages;
  final Set<void Function()> _abortActions = {};
  Timer? _timer;
  String? _reason;

  bool get interrupted => _reason != null || remaining <= Duration.zero;
  Duration get remaining => _duration - _elapsed();
  String get reason => _reason ?? 'deadline';

  Future<T> run<T>(Future<T> Function() action) =>
      runZoned(action, zoneValues: {_zoneKey: this});

  void checkpoint({Duration reserve = Duration.zero}) {
    if (interrupted || remaining <= reserve) {
      cancel(_reason ?? 'deadline');
      throw BackgroundSyncInterrupted(reason);
    }
  }

  void cancel(String reason) {
    if (_reason != null) return;
    _reason = reason;
    for (final abort in _abortActions.toList()) {
      abort();
    }
    _abortActions.clear();
  }

  /// Register actual I/O cancellation, rather than abandoning its Future.
  void Function() onCancel(void Function() abort) {
    if (interrupted) {
      abort();
    } else {
      _abortActions.add(abort);
    }
    return () => _abortActions.remove(abort);
  }

  void dispose() {
    _timer?.cancel();
    _abortActions.clear();
  }

  static void check({Duration reserve = Duration.zero}) =>
      current?.checkpoint(reserve: reserve);

  static Stream<T> guardStream<T>(Stream<T> source) => source.map((value) {
        check();
        return value;
      });
}

extension on Stopwatch {
  Duration elapsedDurationGetter() => elapsed;
}
