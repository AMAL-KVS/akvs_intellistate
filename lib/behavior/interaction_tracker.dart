/// Interaction tracking for AKVS Behavior Intelligence.
///
/// Detects frustration signals like rage taps (>= 3 rapid writes
/// to the same signal within 1 second).
library;

import '../core/dependency_tracker.dart';
import 'behavior_config.dart';
import 'behavior_event.dart';
import 'behavior_reporter.dart';
import 'session_tracker.dart';

/// Detects rage taps and computes frustration scores.
///
/// A "rage tap" is defined as >= 3 writes to the same signal
/// within a 1-second window.
class InteractionTracker {
  InteractionTracker._();

  /// Tracks recent timestamps per signal for rage detection.
  static final Map<String, List<DateTime>> _recentWrites = {};

  /// All rage tap events this session.
  static final List<RageTapEvent> _rageTapsThisSession = [];

  /// Signal names that caused rage taps.
  static final Set<String> _frustrationSignals = {};

  static void Function()? _busUnsubscribe;

  /// List of all rage tap events this session.
  static List<RageTapEvent> get rageTapsThisSession =>
      List.unmodifiable(_rageTapsThisSession);

  /// Signal names that caused rage taps (frustration signals).
  static List<String> get frustrationSignals => _frustrationSignals.toList();

  /// Overall frustration score this session (0.0–1.0).
  ///
  /// Derived from rage tap count and frequency.
  static double get frustrationScore {
    if (_rageTapsThisSession.isEmpty) return 0.0;
    // Score increases with number of rage taps, capped at 1.0
    return (_rageTapsThisSession.length * 0.2).clamp(0.0, 1.0);
  }

  /// Returns true if [signalName] is a known frustration point.
  static bool isFrustrationSignal(String signalName) =>
      _frustrationSignals.contains(signalName);

  /// Track a signal write for rage detection.
  static void onSignalWrite(String signalName, DateTime timestamp) {
    if (AkvsBehavior.instance?.trackInteractions != true) return;

    final timestamps = _recentWrites.putIfAbsent(signalName, () => []);
    timestamps.add(timestamp);

    // Clean up timestamps older than 1 second
    final oneSecondAgo = timestamp.subtract(const Duration(seconds: 1));
    timestamps.removeWhere((t) => t.isBefore(oneSecondAgo));

    // Check for rage tap (>= 3 writes in 1 second)
    if (timestamps.length >= 3) {
      final within = timestamps.last.difference(timestamps.first);
      final event = RageTapEvent(
        timestamp: timestamp,
        sessionId: SessionTracker.currentSessionId,
        signalName: signalName,
        tapCount: timestamps.length,
        within: within,
      );

      _rageTapsThisSession.add(event);
      _frustrationSignals.add(signalName);
      BehaviorReporter.report(event);

      // Reset to avoid continuous rage tap events for the same burst
      timestamps.clear();
    }
  }

  /// Initialize interaction tracking.
  static void init() {
    _busUnsubscribe = DependencyTracker.instance.addBehaviorListener(({
      required String signalName,
      required String? behaviorCategory,
      required String previousValueType,
      required String newValueType,
    }) {
      onSignalWrite(signalName, DateTime.now());
    });
  }

  /// Reset for testing.
  static void reset() {
    _busUnsubscribe?.call();
    _busUnsubscribe = null;
    _recentWrites.clear();
    _rageTapsThisSession.clear();
    _frustrationSignals.clear();
  }
}
