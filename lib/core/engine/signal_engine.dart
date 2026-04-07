/// Abstract engine interface for signal storage and notification.
///
/// Currently only [DartSignalEngine] exists.
/// [RustSignalEngine] will slot in here without touching Signal.
///
/// The engine abstraction allows swapping the underlying signal
/// implementation at startup — from pure Dart to native Rust FFI —
/// without changing any user-facing API.
library;

/// The execution engine for signal operations.
enum SignalEngineMode {
  /// Pure Dart implementation. Default. Always available.
  dart,

  /// Rust FFI implementation. Falls back to dart if unavailable.
  rust,
}

/// Abstract engine interface.
///
/// Implementations provide the core read/write/subscribe primitives
/// that [Signal<T>] delegates to.
abstract class SignalEngine {
  /// Store a value for [signalId].
  void write<T>(int signalId, T value);

  /// Retrieve the current value for [signalId].
  T read<T>(int signalId);

  /// Register a listener for [signalId].
  void subscribe(int signalId, void Function() listener);

  /// Remove a listener.
  void unsubscribe(int signalId, void Function() listener);

  /// Batch multiple writes — listeners fire once after all writes.
  void batch(void Function() writes);

  /// Dispose a signal and all its listeners.
  void dispose(int signalId);

  /// The engine mode identifier.
  SignalEngineMode get mode;

  /// Total number of signals managed by this engine.
  int get signalCount;
}
