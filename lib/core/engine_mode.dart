/// Engine mode configuration for IntelliState.
///
/// Controls whether signals use the pure Dart engine or the
/// high-performance Rust core engine.
///
/// Default is [EngineMode.dart] — zero breaking changes to existing code.
library;

import '../ffi/rust_bridge.dart';

/// The execution engine for signal operations.
enum EngineMode {
  /// Pure Dart implementation (default, zero overhead).
  dart,

  /// Rust-backed implementation via FFI (higher performance).
  rust,
}

/// Global engine configuration and initialization.
///
/// Usage:
/// ```dart
/// void main() {
///   IntelliStateEngine.init(mode: EngineMode.rust);
///   // If Rust is available, signals will use Rust engine.
///   // If not, falls back to Dart automatically.
///   runApp(MyApp());
/// }
/// ```
class IntelliStateEngine {
  IntelliStateEngine._();

  static EngineMode _defaultMode = EngineMode.dart;
  static bool _rustAvailable = false;
  static bool _initialized = false;

  /// Initialize the IntelliState engine.
  ///
  /// Call this before `runApp()` to set up the engine mode.
  /// If [mode] is [EngineMode.rust], attempts to load the Rust core.
  /// Falls back to Dart silently if Rust is unavailable.
  static void init({EngineMode mode = EngineMode.dart}) {
    if (_initialized) return;
    _initialized = true;

    if (mode == EngineMode.rust) {
      _rustAvailable = RustBridge.initialize();
      _defaultMode = _rustAvailable ? EngineMode.rust : EngineMode.dart;
    } else {
      _defaultMode = EngineMode.dart;
    }
  }

  /// The currently active engine mode.
  static EngineMode get activeMode => _defaultMode;

  /// Whether the Rust engine is loaded and active.
  static bool get isRustActive =>
      _defaultMode == EngineMode.rust && _rustAvailable;

  /// Whether the engine has been initialized.
  static bool get isInitialized => _initialized;

  /// The Rust bridge instance (null if not using Rust).
  static RustBridge? get rustBridge =>
      isRustActive ? RustBridge.instance : null;

  /// Shutdown the engine. Primarily for testing.
  static void reset() {
    if (_rustAvailable) {
      RustBridge.shutdown();
    }
    _defaultMode = EngineMode.dart;
    _rustAvailable = false;
    _initialized = false;
  }
}
