/// Single entry point for all AKVS features.
/// Everything is optional — call with zero arguments for defaults.
///
/// Minimal setup (beginners):
/// ```dart
///   void main() {
///     AkvsIntelliState.init();
///     runApp(MyApp());
///   }
/// ```
///
/// Full setup (production apps):
/// ```dart
///   void main() {
///     AkvsIntelliState.init(
///       analytics: AnalyticsConfig(
///         measurementId: 'G-XXXXXXXXXX',
///         apiSecret: 'your_secret',
///       ),
///       remoteConfig: RemoteConfigOptions(
///         url: 'https://yourapp.com/akvs-config.json',
///       ),
///       behavior: BehaviorOptions(
///         trackRetention: true,
///       ),
///       debug: DebugOptions(
///         learningMode: true,
///         signalInspector: true,
///       ),
///     );
///     runApp(MyApp());
///   }
/// ```
library;

import '../behavior/behavior_config.dart';
import '../devtools/learning_mode.dart';
import '../devtools/strict_mode.dart';

/// Initialisation configuration snapshot.
class AkvsConfig {
  final AnalyticsConfig? analytics;
  final RemoteConfigOptions? remoteConfig;
  final BehaviorOptions? behavior;
  final DebugOptions? debug;
  final CrashRecoveryOptions? crashRecovery;
  final bool strictMode;

  const AkvsConfig._({
    this.analytics,
    this.remoteConfig,
    this.behavior,
    this.debug,
    this.crashRecovery,
    this.strictMode = false,
  });
}

/// Single entry point for all AKVS IntelliState features.
class AkvsIntelliState {
  AkvsIntelliState._();

  static bool _initialised = false;
  static AkvsConfig _config = const AkvsConfig._();

  /// Initialises AKVS IntelliState.
  /// All parameters are optional and have sensible defaults.
  /// Safe to call with zero arguments.
  static void init({
    AnalyticsConfig? analytics,
    RemoteConfigOptions? remoteConfig,
    BehaviorOptions? behavior,
    DebugOptions? debug,
    CrashRecoveryOptions? crashRecovery,
    bool strictMode = false,
  }) {
    if (_initialised) return;
    _initialised = true;

    _config = AkvsConfig._(
      analytics: analytics,
      remoteConfig: remoteConfig,
      behavior: behavior,
      debug: debug,
      crashRecovery: crashRecovery,
      strictMode: strictMode,
    );

    // ── Analytics (stub — no underlying implementation yet) ──
    // if (analytics != null) AkvsAnalytics.init(...);

    // ── Remote Config (stub — no underlying implementation yet) ──
    // if (remoteConfig != null) AkvsRemoteConfig.init(...);

    // ── Behavior Intelligence ──
    if (behavior != null) {
      AkvsBehavior.init(
        enabled: true,
        trackScreens: behavior.trackScreens,
        trackInteractions: behavior.trackInteractions,
        trackRetention: behavior.trackRetention,
        trackSegments: behavior.trackFunnels, // closest mapping
        sessionGapThreshold: behavior.sessionGapThreshold,
        trackAllSignals: behavior.trackAllSignals,
        excludeSignals: behavior.excludeSignals,
        includeSignalPrefixes: behavior.includeSignalPrefixes,
        localStoragePrefix: behavior.localStoragePrefix,
      );
    }

    // ── Debug Tools ──
    if (debug?.learningMode == true) {
      enableLearningMode(verbose: debug!.verbose);
    }

    // ── Strict Mode ──
    if (strictMode) {
      AkvsStrictMode.enable();
    }
  }

  /// True after init() has been called.
  static bool get isInitialised => _initialised;

  /// The current configuration snapshot.
  static AkvsConfig get config => _config;

  /// Reset for testing.
  static void reset() {
    _initialised = false;
    _config = const AkvsConfig._();
  }
}

/// Analytics configuration for [AkvsIntelliState.init].
class AnalyticsConfig {
  /// GA4 measurement ID.
  final String measurementId;

  /// GA4 API secret.
  final String apiSecret;

  /// Application version string.
  final String appVersion;

  /// Sampling rate (0.0 – 1.0). Default 0.05 (5%).
  final double sampleRate;

  /// Whether to track widget rebuild counts.
  final bool trackRebuilds;

  /// Whether to track unhandled errors.
  final bool trackErrors;

  const AnalyticsConfig({
    required this.measurementId,
    required this.apiSecret,
    this.appVersion = '1.0.0',
    this.sampleRate = 0.05,
    this.trackRebuilds = true,
    this.trackErrors = true,
  });
}

/// Remote config options for [AkvsIntelliState.init].
class RemoteConfigOptions {
  /// URL to fetch remote configuration from.
  final String url;

  /// Polling interval for remote config refresh.
  final Duration pollInterval;

  /// Custom HTTP headers for the remote config request.
  final Map<String, String> headers;

  const RemoteConfigOptions({
    required this.url,
    this.pollInterval = const Duration(seconds: 60),
    this.headers = const {},
  });
}

/// Behavior tracking options for [AkvsIntelliState.init].
class BehaviorOptions {
  /// Whether to track screen journeys automatically.
  final bool trackScreens;

  /// Whether to detect rage taps and frustration signals.
  final bool trackInteractions;

  /// Whether to track DAU/WAU/MAU and churn risk.
  final bool trackRetention;

  /// Whether to track funnel completion.
  final bool trackFunnels;

  /// Minimum session gap to count as a new session.
  final Duration sessionGapThreshold;

  /// If true, ALL named signals are automatically tracked unless explicitly excluded.
  final bool trackAllSignals;

  /// Signal names to explicitly exclude from automatic tracking.
  final List<String> excludeSignals;

  /// If provided, only signals with these prefixes will be auto-tracked.
  final List<String> includeSignalPrefixes;

  /// If provided, behavior events are stored locally under this key prefix.
  final String? localStoragePrefix;

  const BehaviorOptions({
    this.trackScreens = true,
    this.trackInteractions = true,
    this.trackRetention = true,
    this.trackFunnels = true,
    this.sessionGapThreshold = const Duration(minutes: 30),
    this.trackAllSignals = true,
    this.excludeSignals = const [],
    this.includeSignalPrefixes = const [],
    this.localStoragePrefix,
  });
}

/// Crash recovery options for [AkvsIntelliState.init].
class CrashRecoveryOptions {
  /// If true, ALL signals get lightweight crash protection by default.
  /// Deep resilience (snapshot + remote config) still requires `.resilient()`.
  final bool lightGuardByDefault;

  /// Global crash callback.
  final void Function(Object error, StackTrace stack)? globalOnCrash;

  const CrashRecoveryOptions({
    this.lightGuardByDefault = true,
    this.globalOnCrash,
  });
}

/// Debug and devtools options for [AkvsIntelliState.init].
class DebugOptions {
  /// Enable learning mode (contextual suggestions).
  final bool learningMode;

  /// Enable verbose logging.
  final bool verbose;

  /// Enable floating signal inspector overlay widget.
  final bool signalInspector;

  /// Enable signal history / replay (time-travel debugging).
  final bool timeTravel;

  /// How many values to keep per signal for history.
  final int historySize;

  const DebugOptions({
    this.learningMode = false,
    this.verbose = false,
    this.signalInspector = false,
    this.timeTravel = false,
    this.historySize = 50,
  });
}
