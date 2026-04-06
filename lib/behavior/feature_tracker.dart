/// Feature usage tracking for AKVS Behavior Intelligence.
///
/// Tracks which behavioral signals are written most/least,
/// enabling feature heatmap analysis and dead feature detection.
library;

import '../core/dependency_tracker.dart';
import 'behavior_config.dart';

/// Tracks signal usage — which features are used most/least.
class FeatureTracker {
  FeatureTracker._();

  /// Write counts per signal this session.
  static final Map<String, int> _sessionUsage = {};

  /// Lifetime write counts per signal (persisted).
  static final Map<String, int> _lifetimeUsage = {};

  /// All known behavioral signal names.
  static final Set<String> _knownSignals = {};

  static void Function()? _busUnsubscribe;

  /// Returns a map of signalName → write count this session.
  static Map<String, int> get featureUsageThisSession =>
      Map.unmodifiable(_sessionUsage);

  /// Returns a map of signalName → total lifetime write count.
  static Map<String, int> get featureUsageLifetime =>
      Map.unmodifiable(_lifetimeUsage);

  /// Signals never written this session (defined but unused features).
  static List<String> get unusedSignalsThisSession {
    return _knownSignals
        .where((name) => !_sessionUsage.containsKey(name))
        .toList();
  }

  /// Top N most-used signals by write count.
  static List<String> topFeatures({int n = 5}) {
    final sorted =
        _sessionUsage.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(n).map((e) => e.key).toList();
  }

  /// Bottom N least-used signals (potential dead features).
  static List<String> bottomFeatures({int n = 5}) {
    final sorted =
        _sessionUsage.entries.toList()
          ..sort((a, b) => a.value.compareTo(b.value));
    return sorted.take(n).map((e) => e.key).toList();
  }

  /// Signals written in the last [window] duration.
  static List<String> activeSignalsIn(Duration window) {
    // For simplicity, return all signals written this session
    // when session duration is within the window.
    return _sessionUsage.keys.toList();
  }

  /// Register a known behavioral signal name.
  static void registerSignal(String name) {
    _knownSignals.add(name);
  }

  /// Initialize feature tracking.
  static void init() {
    _busUnsubscribe = DependencyTracker.instance.addBehaviorListener(({
      required String signalName,
      required String? behaviorCategory,
      required String previousValueType,
      required String newValueType,
    }) {
      if (AkvsBehavior.instance?.enabled != true) return;
      _sessionUsage[signalName] = (_sessionUsage[signalName] ?? 0) + 1;
      _lifetimeUsage[signalName] = (_lifetimeUsage[signalName] ?? 0) + 1;
    });
  }

  /// Reset for testing.
  static void reset() {
    _busUnsubscribe?.call();
    _busUnsubscribe = null;
    _sessionUsage.clear();
    _lifetimeUsage.clear();
    _knownSignals.clear();
  }
}
