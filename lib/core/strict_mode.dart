import 'package:flutter/foundation.dart';
import 'signal.dart';

/// Configuration options for Strict Mode enforcement.
class StrictModeOptions {
  /// Whether to throw an exception when a frozen signal is written to.
  /// If false, writes are simply ignored silently.
  final bool throwOnFrozenWrite;

  /// Whether to panic (throw) when the global error frequency is extremely high.
  final bool crashOnGlobalSafeMode;

  const StrictModeOptions({
    this.throwOnFrozenWrite = true,
    this.crashOnGlobalSafeMode = false,
  });
}

/// A development time strictness validator that enforces
/// boundary constraints and resilience rules aggressively.
class StrictMode {
  static StrictMode? _instance;
  final StrictModeOptions options;
  StrictMode._(this.options);

  /// Enable strict mode to trap aggressive state violations.
  static void enable({StrictModeOptions options = const StrictModeOptions()}) {
    if (_instance != null) return;
    _instance = StrictMode._(options);
    debugPrint('[IntelliState] 🛡️ Strict Mode Enabled');
  }

  /// Called automatically by Signal setter when it encounters a dropped write.
  static void checkFrozenWrite(Signal signal) {
    if (_instance == null) return;
    if (_instance!.options.throwOnFrozenWrite) {
      throw StateError(
        'Strict Mode: Attempted to write to Frozen signal "${signal.name ?? signal.hashCode}". '
        'This signal was frozen because it produced too many errors dynamically.',
      );
    } else {
      debugPrint(
        '[IntelliState] 🛡️ Blocked write to frozen signal ${signal.name}',
      );
    }
  }
}
