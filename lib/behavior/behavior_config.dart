/// Central configuration for the AKVS Behavior Intelligence system.
///
/// Call [AkvsBehavior.init] before `runApp()` to activate behavior tracking.
/// If `init()` is never called, no behavior code executes (zero overhead).
library;

import 'session_tracker.dart';
import 'screen_tracker.dart';
import 'interaction_tracker.dart';
import 'feature_tracker.dart';
import 'funnel_tracker.dart';
import 'retention_tracker.dart';
import 'user_segment.dart';

/// One-time setup for the behavior intelligence module.
class AkvsBehavior {
  /// Whether the entire behavior module is active.
  final bool enabled;

  /// Whether to track screen journeys automatically.
  final bool trackScreens;

  /// Whether to detect rage taps and frustration signals.
  final bool trackInteractions;

  /// Whether to compute and update user segments.
  final bool trackSegments;

  /// Whether to track DAU/WAU/MAU and churn risk.
  final bool trackRetention;

  /// Minimum session gap to count as a new session.
  /// Default: 30 minutes.
  final Duration sessionGapThreshold;

  /// How many sessions until a user is considered a "power user".
  /// Default: 10 sessions.
  final int powerUserSessionThreshold;

  /// How many days of inactivity = churn risk.
  /// Default: 7 days.
  final int churnRiskDays;

  /// If provided, behavior events are stored locally using
  /// shared_preferences under this key prefix.
  final String? localStoragePrefix;

  /// If true, ALL named signals are automatically tracked unless explicitly excluded.
  final bool trackAllSignals;

  /// Signal names to explicitly exclude from automatic tracking.
  final List<String> excludeSignals;

  /// If provided, only signals with these prefixes will be auto-tracked.
  final List<String> includeSignalPrefixes;

  AkvsBehavior._({
    required this.enabled,
    required this.trackScreens,
    required this.trackInteractions,
    required this.trackSegments,
    required this.trackRetention,
    required this.sessionGapThreshold,
    required this.powerUserSessionThreshold,
    required this.churnRiskDays,
    required this.trackAllSignals,
    this.excludeSignals = const [],
    this.includeSignalPrefixes = const [],
    this.localStoragePrefix,
  });

  static AkvsBehavior? _instance;

  /// The current behavior configuration, or null if not initialized.
  static AkvsBehavior? get instance => _instance;

  /// Initialize the behavior intelligence system.
  ///
  /// Must be called before `runApp()`. All parameters are optional
  /// and default to sensible values.
  static void init({
    bool enabled = true,
    bool trackScreens = true,
    bool trackInteractions = true,
    bool trackSegments = true,
    bool trackRetention = true,
    Duration sessionGapThreshold = const Duration(minutes: 30),
    int powerUserSessionThreshold = 10,
    int churnRiskDays = 7,
    bool trackAllSignals = true,
    List<String> excludeSignals = const [],
    List<String> includeSignalPrefixes = const [],
    String? localStoragePrefix,
  }) {
    _instance = AkvsBehavior._(
      enabled: enabled,
      trackScreens: trackScreens,
      trackInteractions: trackInteractions,
      trackSegments: trackSegments,
      trackRetention: trackRetention,
      sessionGapThreshold: sessionGapThreshold,
      powerUserSessionThreshold: powerUserSessionThreshold,
      churnRiskDays: churnRiskDays,
      trackAllSignals: trackAllSignals,
      excludeSignals: excludeSignals,
      includeSignalPrefixes: includeSignalPrefixes,
      localStoragePrefix: localStoragePrefix,
    );

    if (!enabled) return;

    // Start session tracking
    SessionTracker.start();

    // Initialize sub-trackers
    if (trackScreens) {
      ScreenTracker.init();
    }
    if (trackInteractions) {
      InteractionTracker.init();
    }
    FeatureTracker.init();
    FunnelTracker.init();
    if (trackRetention) {
      RetentionTracker.init();
    }
    if (trackSegments) {
      UserSegmentEngine.init();
    }
  }

  /// Tear down the behavior system. Primarily for testing.
  static void reset() {
    SessionTracker.reset();
    ScreenTracker.reset();
    InteractionTracker.reset();
    FeatureTracker.reset();
    FunnelTracker.reset();
    RetentionTracker.reset();
    UserSegmentEngine.reset();
    _instance = null;
  }
}
