import 'signal_engine.dart';
import 'dart_engine.dart';
import 'rust_engine.dart';

/// Selects the appropriate engine at startup.
///
/// Usage:
/// ```dart
///   final engine = EngineSelector.select(SignalEngineMode.rust);
///   // Returns RustSignalEngine if available, DartSignalEngine otherwise.
/// ```
class EngineSelector {
  EngineSelector._();

  static SignalEngine? _activeEngine;

  /// Select the best available engine for the requested mode.
  ///
  /// If [requested] is [SignalEngineMode.rust] and the Rust library is
  /// available, returns [RustSignalEngine]. Otherwise always falls back
  /// to [DartSignalEngine] — never throws, never crashes.
  static SignalEngine select(SignalEngineMode requested) {
    if (_activeEngine != null) return _activeEngine!;

    if (requested == SignalEngineMode.rust && RustSignalEngine.isAvailable) {
      _activeEngine = RustSignalEngine.instance;
    } else {
      _activeEngine = DartSignalEngine.instance;
    }
    return _activeEngine!;
  }

  /// The currently active engine, or Dart engine by default.
  static SignalEngine get current =>
      _activeEngine ?? DartSignalEngine.instance;

  /// Reset for testing.
  static void reset() {
    _activeEngine = null;
  }
}
