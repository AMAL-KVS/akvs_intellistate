import 'package:flutter/foundation.dart';
import '../core/signal.dart';

/// Configuration for IntelliState Learning Mode.
class LearningModeOptions {
  final bool verbose;
  LearningModeOptions({this.verbose = true});
}

/// A devtools-like functionality to detect performance issues and suggest optimizations.
///
/// Refactored to provide reactive, contextual hints exactly when issues occur,
/// rather than batching them into a 30-second timer. Each suggestion
/// only fires ONCE per session to avoid console spam.
class LearningMode {
  static LearningMode? _instance;
  final LearningModeOptions options;

  final Map<dynamic, List<DateTime>> _signalUpdateTimestamps = {};
  final Map<dynamic, List<DateTime>> _computedExecutionTimestamps = {};
  final Map<Object, Set<dynamic>> _observerToSignals = {};

  // Track which warnings have already been emitted this session.
  final Set<String> _emittedWarnings = {};

  int _batchPreventions = 0;

  LearningMode._(this.options);

  /// Enables the learning mode.
  static void enable({bool verbose = true}) {
    if (_instance != null) return;
    _instance = LearningMode._(LearningModeOptions(verbose: verbose));
    debugPrint('[IntelliState] 🚀 Learning Mode Enabled (Reactive Hints Active)');
  }

  /// Reports that a signal was updated.
  static void reportSignalUpdate(dynamic signal) {
    _instance?._onSignalUpdate(signal);
  }

  /// Reports that an observer (widget/effect/computed) subscribed to a signal.
  static void reportSubscription(Object observer, dynamic signal) {
    _instance?._onSubscription(observer, signal);
  }

  /// Reports that a computed value was recomputed.
  static void reportComputedExecuted(dynamic computed) {
    _instance?._onComputedExecuted(computed);
  }

  /// Reports that a batch prevented immediate updates.
  static void reportBatchPrevented() {
    _instance?._batchPreventions++;
  }

  void _onSignalUpdate(dynamic signal) {
    final now = DateTime.now();
    final timestamps = _signalUpdateTimestamps.putIfAbsent(signal, () => []);
    timestamps.add(now);

    // Check for 10+ updates in 5 seconds.
    final fiveSecondsAgo = now.subtract(const Duration(seconds: 5));
    timestamps.removeWhere((t) => t.isBefore(fiveSecondsAgo));

    if (timestamps.length >= 10) {
      final name = _nameOf(signal);
      _warnOnce(
        'high_update_rate_$name',
        'Signal "$name" triggered ${timestamps.length} rebuilds in 5s. '
        'Suggestion: Split into finer-grained signals or use batch().',
      );
      timestamps.clear();
    }
  }

  void _onSubscription(Object observer, dynamic signal) {
    final signals = _observerToSignals.putIfAbsent(observer, () => {});
    signals.add(signal);

    if (signals.length >= 8) {
      final name = _nameOf(observer);
      _warnOnce(
        'high_subscription_count_$name',
        'Observer "$name" subscribes to ${signals.length} signals. '
        'Suggestion: Extract child widgets with narrower signal scope.',
      );
    }
  }

  void _onComputedExecuted(dynamic computed) {
    final now = DateTime.now();
    final timestamps = _computedExecutionTimestamps.putIfAbsent(
      computed,
      () => [],
    );
    timestamps.add(now);

    final oneSecondAgo = now.subtract(const Duration(seconds: 1));
    timestamps.removeWhere((t) => t.isBefore(oneSecondAgo));

    if (timestamps.length >= 5) {
      final name = _nameOf(computed);
      _warnOnce(
        'high_computed_rate_$name',
        'Computed "$name" recomputes frequently (${timestamps.length}x per second). '
        'Suggestion: Add debounce or cache intermediate computation.',
      );
      timestamps.clear();
    }
  }

  void _warnOnce(String key, String message) {
    if (_emittedWarnings.contains(key)) return;
    _emittedWarnings.add(key);
    debugPrint('\n[IntelliState 💡 Hint] $message\n');
  }

  String _nameOf(dynamic obj) {
    if (obj == null) return 'null';
    if (obj is Signal && obj.name != null) return obj.name!;
    if (obj is Signal) return 'Signal<${obj.runtimeType}>';
    return obj.toString();
  }
}

/// Public API to enable Learning Mode.
void enableLearningMode({bool verbose = true}) {
  LearningMode.enable(verbose: verbose);
}
