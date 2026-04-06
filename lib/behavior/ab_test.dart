/// A/B testing for AKVS Behavior Intelligence.
///
/// Deterministic variant assignment based on session ID hash.
/// Supports weighted variants and conversion tracking.
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../core/signal.dart';
import 'behavior_config.dart';
import 'session_tracker.dart';

/// Internal state for an A/B test.
class _ABTestState {
  final String testId;
  final Map<String, Map<String, dynamic>> variants;
  final List<double> weights;
  String? assignedVariant;
  int totalConversions = 0;
  final Map<String, int> variantConversions = {};

  _ABTestState({
    required this.testId,
    required this.variants,
    required this.weights,
  });
}

/// A/B testing engine for AKVS Behavior Intelligence.
///
/// Usage:
/// ```dart
/// AkvsABTest.define(
///   testId: 'checkout_button_color',
///   variants: {
///     'control':   {'buttonColor': 'blue'},
///     'variant_a': {'buttonColor': 'green'},
///   },
///   weights: [0.5, 0.5],
/// );
///
/// final color = AkvsABTest.variantValue('checkout_button_color', 'buttonColor');
/// AkvsABTest.recordConversion('checkout_button_color');
/// ```
class AkvsABTest {
  AkvsABTest._();

  static final Map<String, _ABTestState> _tests = {};
  static final Map<String, Signal<String>> _signals = {};

  /// Define a new A/B test.
  ///
  /// Assignment is deterministic based on a hash of the session ID
  /// and test ID, so the same user always gets the same variant
  /// within a session.
  static void define({
    required String testId,
    required Map<String, Map<String, dynamic>> variants,
    List<double>? weights,
  }) {
    final variantNames = variants.keys.toList();
    final effectiveWeights =
        weights ?? List.filled(variantNames.length, 1.0 / variantNames.length);

    final state = _ABTestState(
      testId: testId,
      variants: variants,
      weights: effectiveWeights,
    );

    // Deterministic assignment
    state.assignedVariant = _assignVariant(
      testId: testId,
      variantNames: variantNames,
      weights: effectiveWeights,
    );

    _tests[testId] = state;

    // Initialize conversion counts
    for (final name in variantNames) {
      state.variantConversions[name] = 0;
    }

    // Update signal if exists
    if (_signals.containsKey(testId)) {
      _signals[testId]!.value = state.assignedVariant!;
    }

    // Load persisted data
    _loadPersistedData(testId);
  }

  /// Get the assigned variant name for this user.
  static String assignedVariant(String testId) {
    return _tests[testId]?.assignedVariant ?? 'control';
  }

  /// Get a specific value from the assigned variant.
  static dynamic variantValue(String testId, String key) {
    final state = _tests[testId];
    if (state == null) return null;
    final variant = state.assignedVariant;
    if (variant == null) return null;
    return state.variants[variant]?[key];
  }

  /// Record that this user converted (completed the target action).
  static void recordConversion(String testId) {
    final state = _tests[testId];
    if (state == null) return;

    state.totalConversions++;
    final variant = state.assignedVariant;
    if (variant != null) {
      state.variantConversions[variant] =
          (state.variantConversions[variant] ?? 0) + 1;
    }

    _persistConversion(testId);
  }

  /// Conversion rate per variant.
  static Map<String, double> conversionRates(String testId) {
    final state = _tests[testId];
    if (state == null) return {};

    final total = state.totalConversions;
    if (total == 0) return {for (final k in state.variants.keys) k: 0.0};

    return {
      for (final entry in state.variantConversions.entries)
        entry.key: entry.value / total,
    };
  }

  /// Returns a reactive `Signal<String>` for the assigned variant.
  ///
  /// ```dart
  /// final variant = AkvsABTest.asSignal('checkout_button_color');
  /// Watch((ctx) => variant() == 'variant_a'
  ///   ? GreenButton() : BlueButton())
  /// ```
  static Signal<String> asSignal(String testId) {
    if (!_signals.containsKey(testId)) {
      _signals[testId] = Signal<String>(assignedVariant(testId));
    }
    return _signals[testId]!;
  }

  /// Get all test variant assignments.
  static Map<String, String> get allVariants {
    return {
      for (final entry in _tests.entries)
        entry.key: entry.value.assignedVariant ?? 'control',
    };
  }

  /// Deterministic variant assignment using hash.
  static String _assignVariant({
    required String testId,
    required List<String> variantNames,
    required List<double> weights,
  }) {
    // Use session ID + test ID for deterministic assignment
    final seed = '${SessionTracker.currentSessionId}_$testId';
    final hash = seed.hashCode.abs();
    final normalized = (hash % 10000) / 10000.0;

    double cumulative = 0.0;
    for (int i = 0; i < variantNames.length; i++) {
      cumulative += weights[i];
      if (normalized < cumulative) {
        return variantNames[i];
      }
    }
    return variantNames.last;
  }

  /// Load persisted conversion data.
  static Future<void> _loadPersistedData(String testId) async {
    final prefix = AkvsBehavior.instance?.localStoragePrefix;
    if (prefix == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final state = _tests[testId];
      if (state == null) return;

      state.totalConversions =
          prefs.getInt('${prefix}_ab_${testId}_total') ?? 0;
      for (final variant in state.variants.keys) {
        state.variantConversions[variant] =
            prefs.getInt('${prefix}_ab_${testId}_$variant') ?? 0;
      }
    } catch (_) {
      // Silently fail
    }
  }

  /// Persist conversion data (fire-and-forget).
  static void _persistConversion(String testId) {
    final prefix = AkvsBehavior.instance?.localStoragePrefix;
    if (prefix == null) return;
    // ignore: discarded_futures
    _persistAsync(prefix, testId);
  }

  static Future<void> _persistAsync(String prefix, String testId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final state = _tests[testId];
      if (state == null) return;

      await prefs.setInt(
        '${prefix}_ab_${testId}_total',
        state.totalConversions,
      );
      for (final entry in state.variantConversions.entries) {
        await prefs.setInt('${prefix}_ab_${testId}_${entry.key}', entry.value);
      }
    } catch (_) {
      // Fire-and-forget
    }
  }

  /// Reset for testing.
  static void reset() {
    _tests.clear();
    _signals.clear();
  }
}
