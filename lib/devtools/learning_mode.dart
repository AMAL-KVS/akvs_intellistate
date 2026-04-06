import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/signal.dart';
import '../core/memory_manager.dart';
import '../behavior/behavior_config.dart';
import '../behavior/behavior_reporter.dart';
import '../behavior/feature_tracker.dart';
import '../behavior/funnel_tracker.dart';

/// Configuration for IntelliState Learning Mode.
class LearningModeOptions {
  final bool verbose;
  LearningModeOptions({this.verbose = true});
}

/// A devtools-like functionality to detect performance issues and suggest optimizations.
class LearningMode {
  static LearningMode? _instance;
  final LearningModeOptions options;

  final Map<dynamic, List<DateTime>> _signalUpdateTimestamps = {};
  final Map<Object, Set<dynamic>> _observerToSignals = {};
  final Map<dynamic, List<DateTime>> _computedExecutionTimestamps = {};

  int _batchPreventions = 0;
  // ignore: unused_field
  final Timer _summaryTimer;

  LearningMode._(this.options)
    : _summaryTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => LearningMode._instance?._emitSummary(),
      );

  /// Enables the learning mode.
  static void enable({bool verbose = true}) {
    if (_instance != null) return;
    _instance = LearningMode._(LearningModeOptions(verbose: verbose));
    debugPrint('[IntelliState] 🚀 Learning Mode Enabled');
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
      _warn(
        'Signal "${_nameOf(signal)}" triggered ${timestamps.length} rebuilds in 5s. '
        'Suggestion: Split into finer-grained signals or use batch().',
      );
      timestamps.clear(); // Only warn once per threshold burst
    }
  }

  void _onSubscription(Object observer, dynamic signal) {
    final signals = _observerToSignals.putIfAbsent(observer, () => {});
    signals.add(signal);

    if (signals.length >= 8) {
      _warn(
        'Observer "${_nameOf(observer)}" subscribes to ${signals.length} signals. '
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
      _warn(
        'Computed "${_nameOf(computed)}" recomputes frequently (${timestamps.length}x per second). '
        'Suggestion: Add debounce or cache intermediate computation.',
      );
      timestamps.clear();
    }
  }

  void _emitSummary() {
    final stats = MemoryManager.instance.stats;

    // Find heaviest signal
    dynamic heaviestSignal;
    int maxUpdates = 0;
    _signalUpdateTimestamps.forEach((signal, timestamps) {
      if (timestamps.length > maxUpdates) {
        maxUpdates = timestamps.length;
        heaviestSignal = signal;
      }
    });

    final buf = StringBuffer();
    buf.writeln('[IntelliState] 📊 Summary Report (Last 30s):');
    buf.writeln('- Rebuilds prevented by batching: $_batchPreventions');
    buf.writeln('- Signals currently tracked: ${stats['signal_count']}');
    buf.writeln('- Signals auto-disposed: ${stats['disposed_count']}');
    buf.writeln(
      '- Heaviest signal: ${_nameOf(heaviestSignal)} ($maxUpdates updates/sec)',
    );
    buf.writeln('- Active listener count: ${stats['active_listener_count']}');

    // Behavior Report — only if behavior module is active
    if (AkvsBehavior.instance?.enabled == true) {
      final snapshot = BehaviorReporter.currentSnapshot;
      final journey = snapshot.sessionJourney.join(' → ');
      final rageTapSummary =
          snapshot.rageTaps.isEmpty
              ? 'none'
              : snapshot.rageTaps
                  .map(
                    (r) =>
                        '${r.signalName} (${r.tapCount}x in ${r.within.inMilliseconds}ms)',
                  )
                  .join(', ');

      // Funnel summaries
      final funnelSummary =
          snapshot.funnelStatuses.isEmpty
              ? 'none'
              : snapshot.funnelStatuses.entries
                  .map((e) {
                    final pct =
                        (AkvsFunnel.completionPercentage(e.key) * 100).round();
                    return '${e.key} $pct% ${e.value.name}';
                  })
                  .join(', ');

      // A/B test summaries
      final abSummary =
          snapshot.abTestVariants.isEmpty
              ? 'none'
              : snapshot.abTestVariants.entries
                  .map((e) => '${e.key} → ${e.value}')
                  .join(', ');

      // Feature usage
      final topFeatures = FeatureTracker.topFeatures(n: 3);
      final featureStr =
          topFeatures.isEmpty
              ? 'none'
              : topFeatures
                  .map(
                    (f) =>
                        '$f(${FeatureTracker.featureUsageThisSession[f] ?? 0})',
                  )
                  .join(' ');

      final unusedStr =
          FeatureTracker.unusedSignalsThisSession.isEmpty
              ? 'none'
              : FeatureTracker.unusedSignalsThisSession.join(', ');

      final sessionDur = snapshot.sessionDuration;
      final durStr = '${sessionDur.inMinutes}m ${sessionDur.inSeconds % 60}s';

      final churnLabel =
          snapshot.churnRiskScore < 0.3
              ? 'low'
              : snapshot.churnRiskScore < 0.7
              ? 'medium'
              : 'high';

      buf.writeln('[IntelliState] ─── Behavior Report ────────────────');
      buf.writeln(
        '[IntelliState]   Session:  $durStr · engagement ${snapshot.engagementScore.toStringAsFixed(2)}',
      );
      buf.writeln('[IntelliState]   Segment:  ${snapshot.segment.name}');
      buf.writeln(
        '[IntelliState]   Journey:  ${journey.isEmpty ? 'none' : journey}',
      );
      buf.writeln('[IntelliState]   Funnels:  $funnelSummary');
      buf.writeln(
        '[IntelliState]   Rage taps: $rageTapSummary${snapshot.rageTaps.isNotEmpty ? ' ⚠' : ''}',
      );
      buf.writeln('[IntelliState]   A/B tests: $abSummary');
      buf.writeln('[IntelliState]   Top features: $featureStr');
      buf.writeln('[IntelliState]   Unused:   $unusedStr');
      buf.writeln(
        '[IntelliState]   Churn risk: ${snapshot.churnRiskScore.toStringAsFixed(2)} ($churnLabel) · DAU streak: ${snapshot.dauStreak}',
      );
      buf.writeln('[IntelliState] ────────────────────────────────────');
    }

    debugPrint(buf.toString());

    _batchPreventions = 0;
    _signalUpdateTimestamps.clear();
    _computedExecutionTimestamps.clear();
  }

  void _warn(String message) {
    debugPrint('[IntelliState] ⚠ $message');
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
