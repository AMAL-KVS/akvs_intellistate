/// High-level Dart wrapper around the Rust FFI bindings.
///
/// Provides a safe, ergonomic API for interacting with the Rust core engine.
/// Handles string marshalling, null pointer safety, and automatic fallback
/// detection.
///
/// Usage:
/// ```dart
/// if (RustBridge.initialize()) {
///   // Rust engine available
///   final id = RustBridge.instance!.createIntSignal(42, name: 'counter');
/// } else {
///   // Fallback to pure Dart engine
/// }
/// ```
library;

import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart' as pkg_ffi;
import 'package:flutter/foundation.dart';
import 'bindings.dart';

/// Value type discriminators matching the Rust SignalValueType enum.
enum RustSignalType {
  int_(0),
  float_(1),
  string_(2),
  bool_(3),
  bytes_(4);

  const RustSignalType(this.value);
  final int value;
}

/// Degradation level matching the Rust DegradationLevel enum.
enum RustDegradationLevel {
  normal(0),
  degraded(1),
  frozen(2);

  const RustDegradationLevel(this.value);
  final int value;

  static RustDegradationLevel fromInt(int v) {
    return switch (v) {
      0 => normal,
      1 => degraded,
      2 => frozen,
      _ => normal,
    };
  }
}

/// High-level bridge to the Rust IntelliState core engine.
///
/// Wraps [NativeBindings] with type-safe Dart APIs, automatic string
/// marshalling, and proper memory management.
class RustBridge {
  static RustBridge? _instance;
  final NativeBindings _bindings;
  bool _initialized = false;

  /// Whether the Rust engine is loaded and available.
  static bool get isAvailable => _instance != null && _instance!._initialized;

  /// The singleton instance, or null if Rust is unavailable.
  static RustBridge? get instance => _instance;

  RustBridge._(this._bindings);

  /// Attempts to load and initialize the Rust engine.
  ///
  /// Returns `true` if successful, `false` if the Rust library
  /// could not be loaded (pure Dart fallback should be used).
  ///
  /// Safe to call multiple times — subsequent calls are no-ops.
  static bool initialize() {
    if (_instance != null) return _instance!._initialized;

    try {
      final dylib = tryLoadLibrary();
      if (dylib == null) {
        debugPrint(
          '[IntelliState] Rust core not found — using pure Dart engine',
        );
        return false;
      }

      final bindings = NativeBindings.load(dylib);
      _instance = RustBridge._(bindings);
      _instance!._bindings.init();
      _instance!._initialized = true;

      debugPrint('[IntelliState] 🦀 Rust core engine loaded successfully');
      return true;
    } catch (e) {
      debugPrint('[IntelliState] Failed to load Rust core: $e');
      _instance = null;
      return false;
    }
  }

  /// Shutdown the Rust engine and release all resources.
  static void shutdown() {
    _instance?._bindings.shutdown();
    _instance?._initialized = false;
    _instance = null;
  }

  // ═════════════════════════════════════════════════════════════════════
  //  SIGNAL LIFECYCLE
  // ═════════════════════════════════════════════════════════════════════

  /// Create an integer signal. Returns the signal ID.
  int createIntSignal(int value, {String? name}) {
    final namePtr = _toNativeString(name);
    try {
      return _bindings.createInt(value, namePtr);
    } finally {
      _freeNativeString(namePtr);
    }
  }

  /// Create a float signal. Returns the signal ID.
  int createFloatSignal(double value, {String? name}) {
    final namePtr = _toNativeString(name);
    try {
      return _bindings.createFloat(value, namePtr);
    } finally {
      _freeNativeString(namePtr);
    }
  }

  /// Create a string signal. Returns the signal ID.
  int createStringSignal(String value, {String? name}) {
    final namePtr = _toNativeString(name);
    final valuePtr = _toNativeString(value);
    try {
      return _bindings.createString(valuePtr, namePtr);
    } finally {
      _freeNativeString(namePtr);
      _freeNativeString(valuePtr);
    }
  }

  /// Create a boolean signal. Returns the signal ID.
  int createBoolSignal(bool value, {String? name}) {
    final namePtr = _toNativeString(name);
    try {
      return _bindings.createBool(value ? 1 : 0, namePtr);
    } finally {
      _freeNativeString(namePtr);
    }
  }

  /// Dispose of a signal. Returns true if successful.
  bool disposeSignal(int signalId) {
    return _bindings.dispose(signalId) == 0;
  }

  // ═════════════════════════════════════════════════════════════════════
  //  GETTERS
  // ═════════════════════════════════════════════════════════════════════

  /// Get the value type of a signal.
  RustSignalType? getSignalType(int signalId) {
    final type_ = _bindings.getType(signalId);
    if (type_ < 0) return null;
    return RustSignalType.values.firstWhere(
      (t) => t.value == type_,
      orElse: () => RustSignalType.int_,
    );
  }

  /// Get an integer signal value.
  int getInt(int signalId) => _bindings.getInt(signalId);

  /// Get a float signal value.
  double getFloat(int signalId) => _bindings.getFloat(signalId);

  /// Get a string signal value.
  String getString(int signalId) {
    final ptr = _bindings.getString(signalId);
    if (ptr == ffi.nullptr) return '';
    try {
      return ptr.toDartString();
    } finally {
      _bindings.freeString(ptr);
    }
  }

  /// Get a boolean signal value.
  bool getBool(int signalId) => _bindings.getBool(signalId) != 0;

  // ═════════════════════════════════════════════════════════════════════
  //  SETTERS (return: 1=changed, 0=unchanged, -1=not found, -2=frozen)
  // ═════════════════════════════════════════════════════════════════════

  /// Set an integer signal value. Returns result code.
  int setInt(int signalId, int value) => _bindings.setInt(signalId, value);

  /// Set a float signal value. Returns result code.
  int setFloat(int signalId, double value) =>
      _bindings.setFloat(signalId, value);

  /// Set a string signal value. Returns result code.
  int setString(int signalId, String value) {
    final valuePtr = _toNativeString(value);
    try {
      return _bindings.setString(signalId, valuePtr);
    } finally {
      _freeNativeString(valuePtr);
    }
  }

  /// Set a boolean signal value. Returns result code.
  int setBool(int signalId, bool value) =>
      _bindings.setBool(signalId, value ? 1 : 0);

  // ═════════════════════════════════════════════════════════════════════
  //  SUBSCRIPTIONS
  // ═════════════════════════════════════════════════════════════════════

  /// Subscribe to a signal. Returns listener ID (0 on failure).
  int subscribe(int signalId) => _bindings.subscribe(signalId);

  /// Unsubscribe a listener from a signal.
  void unsubscribe(int signalId, int listenerId) =>
      _bindings.unsubscribe(signalId, listenerId);

  // ═════════════════════════════════════════════════════════════════════
  //  SCHEDULER
  // ═════════════════════════════════════════════════════════════════════

  /// Begin a batch.
  void batchBegin() => _bindings.batchBegin();

  /// End a batch (flushes all queued updates).
  void batchEnd() => _bindings.batchEnd();

  /// Manually flush all pending updates.
  int flush() => _bindings.flush();

  // ═════════════════════════════════════════════════════════════════════
  //  INTELLIGENCE
  // ═════════════════════════════════════════════════════════════════════

  /// Get the health score of a signal (0.0–1.0). Returns -1.0 if not found.
  double healthScore(int signalId) => _bindings.healthScore(signalId);

  /// Get the degradation level of a signal.
  RustDegradationLevel degradationLevel(int signalId) =>
      RustDegradationLevel.fromInt(_bindings.degradationLevel(signalId));

  // ═════════════════════════════════════════════════════════════════════
  //  RESILIENCE
  // ═════════════════════════════════════════════════════════════════════

  /// Record an error for a signal.
  void recordError(int signalId, String errorType) {
    final errPtr = _toNativeString(errorType);
    try {
      _bindings.recordError(signalId, errPtr);
    } finally {
      _freeNativeString(errPtr);
    }
  }

  /// Check if a signal is frozen.
  bool isFrozen(int signalId) => _bindings.isFrozen(signalId) != 0;

  /// Check if global safe mode is active.
  bool isSafeMode() => _bindings.isSafeMode() != 0;

  /// Freeze a signal.
  void freeze(int signalId) => _bindings.freeze(signalId);

  /// Unfreeze a signal.
  void unfreeze(int signalId) => _bindings.unfreeze(signalId);

  /// Enter global safe mode.
  void enterSafeMode() => _bindings.enterSafeMode();

  /// Exit global safe mode.
  void exitSafeMode() => _bindings.exitSafeMode();

  // ═════════════════════════════════════════════════════════════════════
  //  DIAGNOSTICS
  // ═════════════════════════════════════════════════════════════════════

  /// Get the total number of Rust-backed signals.
  int signalCount() => _bindings.signalCount();

  /// Get the total number of scheduler flushes.
  int flushCount() => _bindings.flushCount();

  /// Get the total crash count.
  int totalCrashes() => _bindings.totalCrashes();

  /// Get the number of buffered behavior events.
  int behaviorEventCount() => _bindings.behaviorCount();

  // ═════════════════════════════════════════════════════════════════════
  //  STRING HELPERS
  // ═════════════════════════════════════════════════════════════════════

  /// Convert a Dart string to a native UTF-8 pointer.
  /// Returns nullptr if the string is null.
  static ffi.Pointer<pkg_ffi.Utf8> _toNativeString(String? value) {
    if (value == null) return ffi.nullptr.cast<pkg_ffi.Utf8>();
    return value.toNativeUtf8();
  }

  /// Free a native string allocated by [_toNativeString].
  static void _freeNativeString(ffi.Pointer<pkg_ffi.Utf8> ptr) {
    if (ptr != ffi.nullptr.cast<pkg_ffi.Utf8>()) {
      pkg_ffi.calloc.free(ptr);
    }
  }
}
