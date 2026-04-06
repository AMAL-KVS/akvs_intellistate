import 'dart:async';

/// Interface for disposable reactive objects.
abstract interface class Disposable {
  /// Dispose of the resource.
  void dispose();

  /// Whether the resource has been disposed.
  bool get isDisposed;
}

/// Interface for signals used by MemoryManager.
abstract interface class ManagedSignal extends Disposable {
  /// The current listener count.
  int get listenerCount;
}

/// Singleton responsible for automatic resource management of signals.
///
/// Handles garbage collection for signals with the [autoDispose] flag.
class MemoryManager {
  MemoryManager._();

  static final MemoryManager instance = MemoryManager._();

  /// Timers for signals that are pending disposal.
  final Map<ManagedSignal, Timer> _disposalTimers = {};

  /// All tracked signals (for stats).
  final Set<ManagedSignal> _trackedSignals = {};

  /// Total number of signals disposed by the manager since launch.
  int _disposedCount = 0;

  /// Registers a signal for memory management (only if autoDispose is true).
  void register(ManagedSignal signal) {
    _trackedSignals.add(signal);
  }

  /// Called when a listener is added to a signal.
  ///
  /// Cancels any pending disposal timer.
  void onListenerAdded(ManagedSignal signal) {
    _disposalTimers.remove(signal)?.cancel();
  }

  /// Called when a listener is removed from a signal.
  ///
  /// If zero listeners remain, schedules the signal for disposal.
  void onListenerRemoved(ManagedSignal signal) {
    if (signal.listenerCount == 0 && !signal.isDisposed) {
      _disposalTimers[signal] = Timer(const Duration(seconds: 30), () {
        if (signal.listenerCount == 0 && !signal.isDisposed) {
          signal.dispose();
          _disposedCount++;
          _disposalTimers.remove(signal);
          _trackedSignals.remove(signal);
        }
      });
    }
  }

  /// Forceful disposal of all managed signals.
  ///
  /// Useful for testing or app shutdown.
  void disposeAll() {
    for (final timer in _disposalTimers.values) {
      timer.cancel();
    }
    _disposalTimers.clear();

    final signalsToDispose = Set<ManagedSignal>.from(_trackedSignals);
    for (final signal in signalsToDispose) {
      if (!signal.isDisposed) {
        signal.dispose();
      }
    }
    _trackedSignals.clear();
  }

  /// Returns statistics about the current state of memory management.
  Map<String, int> get stats {
    int totalListeners = 0;
    for (final signal in _trackedSignals) {
      totalListeners += signal.listenerCount;
    }

    return {
      'signal_count': _trackedSignals.length,
      'disposed_count': _disposedCount,
      'active_listener_count': totalListeners,
      'pending_disposal_count': _disposalTimers.length,
    };
  }
}
