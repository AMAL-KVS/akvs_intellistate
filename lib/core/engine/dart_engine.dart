import 'signal_engine.dart';

/// Pure-Dart implementation of the [SignalEngine] interface.
///
/// This is the default engine used by all signals. It stores values
/// in a simple in-memory map and notifies listeners synchronously.
///
/// This engine is always available on all platforms.
class DartSignalEngine implements SignalEngine {
  DartSignalEngine._();

  static final DartSignalEngine instance = DartSignalEngine._();

  /// Internal storage: signalId → current value.
  final Map<int, dynamic> _store = {};

  /// Listeners: signalId → set of callbacks.
  final Map<int, Set<void Function()>> _listeners = {};

  /// Auto-incrementing ID generator.
  int _nextId = 0;

  /// Whether a batch is currently active.
  bool _isBatching = false;

  /// Signal IDs that were written during the current batch.
  final Set<int> _batchDirty = {};

  /// Allocate a new signal ID and store its initial value.
  int allocate<T>(T initialValue) {
    final id = _nextId++;
    _store[id] = initialValue;
    _listeners[id] = {};
    return id;
  }

  @override
  void write<T>(int signalId, T value) {
    _store[signalId] = value;
    if (_isBatching) {
      _batchDirty.add(signalId);
    } else {
      _notifyListeners(signalId);
    }
  }

  @override
  T read<T>(int signalId) {
    return _store[signalId] as T;
  }

  @override
  void subscribe(int signalId, void Function() listener) {
    _listeners.putIfAbsent(signalId, () => {}).add(listener);
  }

  @override
  void unsubscribe(int signalId, void Function() listener) {
    _listeners[signalId]?.remove(listener);
  }

  @override
  void batch(void Function() writes) {
    final wasBatching = _isBatching;
    _isBatching = true;
    try {
      writes();
    } finally {
      _isBatching = wasBatching;
      if (!_isBatching) {
        // Flush: notify all dirty signals once
        final dirty = Set<int>.from(_batchDirty);
        _batchDirty.clear();
        for (final id in dirty) {
          _notifyListeners(id);
        }
      }
    }
  }

  @override
  void dispose(int signalId) {
    _store.remove(signalId);
    _listeners.remove(signalId);
  }

  void _notifyListeners(int signalId) {
    final listeners = _listeners[signalId];
    if (listeners != null) {
      for (final listener in List.from(listeners)) {
        listener();
      }
    }
  }

  @override
  SignalEngineMode get mode => SignalEngineMode.dart;

  @override
  int get signalCount => _store.length;

  /// Reset for testing.
  void reset() {
    _store.clear();
    _listeners.clear();
    _nextId = 0;
    _isBatching = false;
    _batchDirty.clear();
  }
}
