import 'dependency_tracker.dart';
import 'scheduler.dart';
import 'memory_manager.dart';
import 'package:meta/meta.dart';

import '../behavior/feature_tracker.dart';
import '../behavior/screen_tracker.dart';
import '../behavior/behavior_config.dart';
import '../intelligence/intelligence_bridge.dart';
import 'engine_mode.dart';
import 'strict_mode.dart';

/// Function that executes when a signal value changes.
typedef SignalListener<T> = void Function(T value);

/// A reactive value container that auto-tracks dependencies.
///
/// Signals are the atoms of state in the IntelliState system.
/// They store a value and notify observers when that value changes.
class Signal<T> implements ManagedSignal, SignalObserver {
  T? _valueInside;
  bool _initialized = false;
  final bool _autoDispose;
  bool _isDisposed = false;

  /// The ID of the Rust-backed signal, if this signal is running in Hybrid mode.
  int? _rustSignalId;

  /// Optional human-readable name for this signal (used by devtools & behavior).
  final String? name;

  /// If true, writes to this signal are tracked by the behavior system.
  final bool behavioral;

  /// Classification for behavior tracking:
  /// - `'navigation'` → ScreenTracker watches this signal
  /// - `'action'` → UserActionEvent fires on write
  /// - any custom string → FeatureTracker tracks it
  final String? behaviorCategory;

  /// The current set of listeners subscribed to this signal.
  final Set<SignalListener<T>> _listeners = {};

  /// Creates a new Signal with an initial [value].
  Signal(
    T value, {
    bool autoDispose = false,
    this.name,
    this.behavioral = false,
    this.behaviorCategory,
  }) : _autoDispose = autoDispose {
    _valueInside = value;
    _initialized = true;
    if (_autoDispose) {
      MemoryManager.instance.register(this);
    }
    if (behavioral && name != null) {
      FeatureTracker.registerSignal(name!);
    }

    // Register with Rust engine if active and type is supported primitive.
    if (IntelliStateEngine.isRustActive) {
      final rust = IntelliStateEngine.rustBridge!;
      if (T == int) {
        _rustSignalId = rust.createIntSignal(value as int, name: name);
      } else if (T == double) {
        _rustSignalId = rust.createFloatSignal(value as double, name: name);
      } else if (T == String) {
        _rustSignalId = rust.createStringSignal(value as String, name: name);
      } else if (T == bool) {
        _rustSignalId = rust.createBoolSignal(value as bool, name: name);
      }
    }
  }

  /// Internal constructor for uninitialized signals (like Computed).
  @internal
  Signal.internal({bool autoDispose = false})
    : _autoDispose = autoDispose,
      name = null,
      behavioral = false,
      behaviorCategory = null {
    if (_autoDispose) {
      MemoryManager.instance.register(this);
    }
  }

  /// Returns the current value of the signal.
  ///
  /// If called within a tracking context (e.g. effect or computed),
  /// the caller will automatically subscribe to this signal.
  T call() {
    checkDisposed();
    DependencyTracker.instance.reportRead(this);
    return value;
  }

  /// Whether the signal has been initialized with a value.
  bool get isInitialized => _initialized;

  /// Gets the current value. Throws if not initialized.
  T get value {
    checkDisposed();

    if (_rustSignalId != null && IntelliStateEngine.isRustActive) {
      final rust = IntelliStateEngine.rustBridge!;
      if (T == int) return rust.getInt(_rustSignalId!) as T;
      if (T == double) return rust.getFloat(_rustSignalId!) as T;
      if (T == String) return rust.getString(_rustSignalId!) as T;
      if (T == bool) return rust.getBool(_rustSignalId!) as T;
    }

    if (!_initialized) {
      throw StateError('Signal not initialized.');
    }
    return _valueInside as T;
  }

  /// Sets a new value for the signal.
  ///
  /// If the new value is different from the current value (using `==`),
  /// all observers will be notified via the [UpdateScheduler].
  set value(T newValue) {
    checkDisposed();

    // Fast path: if nothing changed, don't update
    if (_initialized && _valueInside == newValue) return;

    if (_rustSignalId != null && IntelliStateEngine.isRustActive) {
      final rust = IntelliStateEngine.rustBridge!;
      int res = -2; // frozen
      if (T == int) {
        res = rust.setInt(_rustSignalId!, newValue as int);
      } else if (T == double) {
        res = rust.setFloat(_rustSignalId!, newValue as double);
      } else if (T == String) {
        res = rust.setString(_rustSignalId!, newValue as String);
      } else if (T == bool) {
        res = rust.setBool(_rustSignalId!, newValue as bool);
      }

      // If frozen (-2), we do not update local state or fire listeners
      if (res < 0) {
        if (res == -2) StrictMode.checkFrozenWrite(this);
        return;
      }
    }

    // Report metric to pure-dart tracker (which no-ops if Rust is in use)
    IntelligenceBridge.instance.recordDartWrite(this);

    final previousValue = _valueInside;
    _valueInside = newValue;
    _initialized = true;
    _notify();

    // Behavior tracking — guarded: zero cost if not enabled
    if (behavioral && AkvsBehavior.instance?.enabled == true && name != null) {
      DependencyTracker.instance.notifyBehaviorWrite(
        signalName: name!,
        behaviorCategory: behaviorCategory,
        previousValueType: previousValue?.runtimeType.toString() ?? 'null',
        newValueType: newValue.runtimeType.toString(),
      );

      // Navigation signals trigger screen change
      if (behaviorCategory == 'navigation' && newValue is String) {
        ScreenTracker.onScreenChange(name!, newValue);
      }
    }
  }

  /// Updates the signal value using a functional transformation.
  ///
  /// Convenient for incrementing counters or appending to lists.
  void update(T Function(T value) fn) {
    value = fn(value);
  }

  /// Adds a listener to this signal.
  ///
  /// The listener will be called whenever the signal value changes.
  void addListener(SignalListener<T> listener) {
    checkDisposed();
    final wasEmpty = _listeners.isEmpty;
    _listeners.add(listener);

    if (wasEmpty && _autoDispose) {
      MemoryManager.instance.onListenerAdded(this);
    }
  }

  /// Removes a listener from this signal.
  void removeListener(SignalListener<T> listener) {
    if (_isDisposed) return;
    _listeners.remove(listener);

    if (_listeners.isEmpty && _autoDispose) {
      MemoryManager.instance.onListenerRemoved(this);
    }
  }

  /// Notifies the scheduler that this signal has changed.
  void _notify() {
    UpdateScheduler.instance.markDirty(this);
    DependencyTracker.instance.invalidate(this);

    // Notify external listeners immediately (usually non-reactive code)
    // Reactive code like Effects will be triggered by invalidate -> markDirty.
    for (final listener in List.from(_listeners)) {
      listener(value);
    }
  }

  @override
  void markDirty() {
    // Basic Signal objects don't have internal dirty states.
    // This is primarily for Computed values.
  }

  @override
  int get listenerCount => _listeners.length;

  @override
  bool get isDisposed => _isDisposed;

  /// Disposes of the signal, clearing all listeners.
  ///
  /// After disposal, the signal can no longer be read or written to.
  @override
  @mustCallSuper
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _listeners.clear();

    if (_rustSignalId != null && IntelliStateEngine.isRustActive) {
      IntelliStateEngine.rustBridge!.disposeSignal(_rustSignalId!);
      _rustSignalId = null;
    }
    // Dependency tracker cleanup happens automatically as observers are removed.
  }

  /// Internal helper to check if the signal is disposed.
  @protected
  void checkDisposed() {
    if (_isDisposed) {
      throw StateError('Cannot interact with a disposed Signal.');
    }
  }
}

/// Creates a new [Signal] with the given [initialValue].
///
/// [autoDispose]: If true, the signal will be disposed after it
/// is no longer being listened to.
///
/// [name]: Human-readable name for devtools and behavior tracking.
///
/// [behavioral]: If true, writes are tracked by BehaviorReporter.
///
/// [behaviorCategory]: Classification for behavior tracking.
/// - `'navigation'` → ScreenTracker watches this signal
/// - `'action'` → UserActionEvent fired on write
/// - any string → FeatureTracker tracks it
Signal<T> aiSignal<T>(
  T initialValue, {
  bool autoDispose = false,
  String? name,
  bool behavioral = false,
  String? behaviorCategory,
}) {
  return Signal<T>(
    initialValue,
    autoDispose: autoDispose,
    name: name,
    behavioral: behavioral,
    behaviorCategory: behaviorCategory,
  );
}
