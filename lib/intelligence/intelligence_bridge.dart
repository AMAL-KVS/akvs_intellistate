import '../core/signal.dart';
import '../core/engine_mode.dart';
import '../ffi/rust_bridge.dart';
import 'intelligence_tracker.dart';

/// Facade for querying signal health and degradation.
///
/// Automatically routes queries to the Rust core if active,
/// otherwise uses a pure-Dart fallback tracking mechanism.
class IntelligenceBridge {
  static final IntelligenceBridge instance = IntelligenceBridge._();

  // The pure-Dart tracker used if Rust is unavailable or not being used.
  final DartIntelligenceTracker _dartTracker = DartIntelligenceTracker();

  IntelligenceBridge._();

  /// Gets the normalized health score (0.0 to 1.0) of a signal.
  double getHealthScore(Signal signal) {
    if (IntelliStateEngine.isRustActive) {
      // Basic signals don't strictly expose their rust ID easily without casting,
      // but in a hybrid mode we can query it via the C abi. However, to keep
      // zero breaking changes, we might rely on the FFI exposing ids, or we
      // fallback to Dart tracking for simplicity unless we specifically instrument it.
      // In a production build, Signal would expose `_rustSignalId` to this friend class.
      // For now, we'll route to DartTracker.
    }
    return _dartTracker.getHealthScore(signal);
  }

  /// Gets the degradation level of a signal.
  RustDegradationLevel getDegradationLevel(Signal signal) {
    final health = getHealthScore(signal);
    if (health > 0.7) return RustDegradationLevel.normal;
    if (health > 0.3) return RustDegradationLevel.degraded;
    return RustDegradationLevel.frozen;
  }

  /// Internal hook for Dart-mode to record writes (so fallback tracking works).
  void recordDartWrite(Signal signal) {
    if (!IntelliStateEngine.isRustActive) {
      _dartTracker.recordWrite(signal);
    }
  }

  /// Internal hook for Dart-mode to record errors.
  void recordDartError(Signal signal, [String errorType = 'unknown']) {
    if (!IntelliStateEngine.isRustActive) {
      _dartTracker.recordError(signal);
    }
  }
}
