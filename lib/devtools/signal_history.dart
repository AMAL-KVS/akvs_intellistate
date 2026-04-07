import '../core/signal.dart';

/// Represents a single historical state of a signal.
class HistoryEntry<T> {
  /// The value at this point in time.
  final T value;

  /// When this value was recorded.
  final DateTime timestamp;

  /// Optional stack trace tracking where this write originated.
  final StackTrace? stackTrace;

  const HistoryEntry(this.value, this.timestamp, {this.stackTrace});

  Map<String, dynamic> toJson() {
    return {
      'value': value.toString(),
      'timestamp': timestamp.toIso8601String(),
      'stackTrace': stackTrace?.toString(),
    };
  }
}

/// A time-travel debugging utility that records a signal's state history.
///
/// Automatically attaches to signals initialized with `.withHistory(size: N)`.
class SignalHistory<T> {
  final Signal<T> _signal;
  final int _maxSize;
  final List<HistoryEntry<T>> _history = [];
  bool _isReplaying = false;

  SignalHistory(this._signal, {int maxSize = 50}) : _maxSize = maxSize {
    // Record initial state
    if (_signal.isInitialized) {
      _history.add(HistoryEntry(_signal.value, DateTime.now()));
    }

    _signal.addListener(_onValueChanged);
  }

  void _onValueChanged(T newValue) {
    if (_isReplaying) return;

    _history.add(
      HistoryEntry(
        newValue,
        DateTime.now(),
        // Capture stacktrace if we are in debug mode
        stackTrace: StackTrace.current,
      ),
    );

    if (_history.length > _maxSize) {
      _history.removeAt(0); // remove oldest
    }
  }

  /// Get the full recorded history. Oldest first.
  List<HistoryEntry<T>> get entries => List.unmodifiable(_history);

  /// Replay the state of the signal to a specific historical index `[0..length-1]`.
  void replayTo(int index) {
    if (index < 0 || index >= _history.length) return;
    _isReplaying = true;
    _signal.value = _history[index].value;
    _isReplaying = false;
  }

  /// Replay to a state N steps ago.
  /// `ago(1)` means the previous state.
  void ago(int steps) {
    final targetIndex = _history.length - 1 - steps;
    replayTo(targetIndex);
  }

  /// Reset history collection.
  void clear() {
    _history.clear();
    if (_signal.isInitialized) {
      _history.add(HistoryEntry(_signal.value, DateTime.now()));
    }
  }

  /// Export history for offline debugging.
  List<Map<String, dynamic>> toJson() {
    return _history.map((e) => e.toJson()).toList();
  }

  void dispose() {
    _signal.removeListener(_onValueChanged);
  }
}
