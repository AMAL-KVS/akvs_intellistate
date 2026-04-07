// ignore_for_file: unused_field, deprecated_member_use_from_same_package
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
  bool _autoDispose;
  bool _isDisposed = false;

  /// The ID of the Rust-backed signal, if this signal is running in Hybrid mode.
  int? _rustSignalId;

  /// Optional human-readable name for this signal (used by devtools & behavior).
  String? name;

  /// If true, writes to this signal are tracked by the behavior system.
  @Deprecated('Use .behavior() fluent method instead. Auto-tracking is enabled when AkvsBehavior is active.')
  final bool behavioral;

  /// Classification for behavior tracking.
  @Deprecated('Use .behavior(category: ...) fluent method instead.')
  final String? behaviorCategory;

  // ── Fluent builder internal state ──────────────────────────────────

  /// Behavior category set via fluent `.behavior()` method.
  String? _fluentBehaviorCategory;

  /// Whether crash resilience is enabled via fluent `.resilient()`.
  bool _resilient = false;

  /// Fallback value for crash recovery.
  T? _resilientFallback;

  /// Crash callback for resilient signals.
  void Function(Object error, StackTrace stack)? _onCrash;

  /// Whether auto-dispose is enabled via fluent `.autoDispose()`.
  Duration _autoDisposeDelay = const Duration(seconds: 30);

  /// Whether signal history is enabled via fluent `.withHistory()`.
  bool _hasHistory = false;

  /// Maximum history entries to keep.
  int _historySize = 50;

  /// A/B test key for variant injection.
  String? _abTestKey;

  /// The current set of listeners subscribed to this signal.
  final Set<SignalListener<T>> _listeners = {};

  /// Write count since creation (used by devtools).
  int _writeCount = 0;

  /// Last update timestamp.
  DateTime? _lastUpdated;

  /// Number of writes since creation.
  int get writeCount => _writeCount;

  /// Timestamp of last value update.
  DateTime? get lastUpdated => _lastUpdated;

  /// Whether this signal has history enabled.
  bool get hasHistory => _hasHistory;

  /// The effective behavior category (fluent takes precedence over constructor).
  String? get effectiveBehaviorCategory =>
      _fluentBehaviorCategory ?? behaviorCategory;

  /// Whether this signal is resilient.
  bool get isResilient => _resilient;

  /// The A/B test key, if set.
  String? get abTestKey => _abTestKey;

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
    _writeCount++;
    _lastUpdated = DateTime.now();
    _notify();

    // Behavior tracking — invisible intelligence
    final behavior = AkvsBehavior.instance;
    if (behavior?.enabled == true && name != null) {
      String? category = effectiveBehaviorCategory;

      // Auto-detect navigation signals
      if (category == null) {
        final lowerName = name!.toLowerCase();
        if (lowerName.contains('screen') ||
            lowerName.contains('route') ||
            lowerName.contains('page') ||
            lowerName.contains('nav')) {
          category = 'navigation';
        }
      }

      // Check auto-tracking rules
      bool shouldTrack = behavioral || _fluentBehaviorCategory != null;
      
      if (!shouldTrack && behavior!.trackAllSignals) {
        shouldTrack = !behavior.excludeSignals.contains(name!);
        if (shouldTrack && behavior.includeSignalPrefixes.isNotEmpty) {
          shouldTrack = behavior.includeSignalPrefixes
              .any((prefix) => name!.startsWith(prefix));
        }
      }

      if (shouldTrack) {
        category ??= 'action';
        DependencyTracker.instance.notifyBehaviorWrite(
          signalName: name!,
          behaviorCategory: category,
          previousValueType: previousValue?.runtimeType.toString() ?? 'null',
          newValueType: newValue.runtimeType.toString(),
        );

        if (category == 'navigation' && newValue is String) {
          ScreenTracker.onScreenChange(name!, newValue as String);
        }
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
/// [name]: Human-readable name for devtools and behavior tracking.
///
/// Advanced configuration uses fluent builder methods:
/// ```dart
/// final counter = aiSignal(0);
/// final price = aiSignal(0.0, name: 'price');
/// final payment = aiSignal(PaymentState.idle)
///   .resilient(fallback: PaymentState.idle)
///   .behavior(category: 'action')
///   .withName('paymentState');
/// ```
Signal<T> aiSignal<T>(
  T initialValue, {
  String? name,
  @Deprecated('Use .behavior() fluent method instead') bool behavioral = false,
  @Deprecated('Use .behavior(category: ...) instead') String? behaviorCategory,
  bool autoDispose = false,
}) {
  return Signal<T>(
    initialValue,
    autoDispose: autoDispose,
    name: name,
    behavioral: behavioral,
    behaviorCategory: behaviorCategory,
  );
}

// ═══════════════════════════════════════════════════════════════════════
//  FLUENT BUILDER EXTENSION
// ═══════════════════════════════════════════════════════════════════════

/// Fluent builder methods for advanced signal configuration.
///
/// All methods mutate and return the SAME signal instance for chaining.
/// They are entirely optional — existing code with no chain calls still works.
///
/// ```dart
/// final payment = aiSignal(PaymentState.idle)
///   .resilient(fallback: PaymentState.idle)
///   .behavior(category: 'action')
///   .withName('paymentState')
///   .withHistory(size: 30);
/// ```
extension SignalBuilderExtension<T> on Signal<T> {
  /// Enables crash recovery guard with optional fallback.
  Signal<T> resilient({
    T? fallback,
    void Function(Object error, StackTrace stack)? onCrash,
  }) {
    _resilient = true;
    _resilientFallback = fallback;
    _onCrash = onCrash;
    return this;
  }

  /// Tags this signal for behavior tracking with an optional category.
  ///
  /// Categories: `'navigation'`, `'action'`, `'data'`, or any custom string.
  /// If not set, the signal is tracked as `'uncategorized'`.
  Signal<T> behavior({String category = 'action'}) {
    _fluentBehaviorCategory = category;
    if (name != null) {
      FeatureTracker.registerSignal(name!);
    }
    return this;
  }

  /// Sets a human-readable name (used in devtools and analytics).
  Signal<T> withName(String newName) {
    name = newName;
    return this;
  }

  /// Enables auto-dispose when listener count drops to 0.
  Signal<T> autoDispose({Duration delay = const Duration(seconds: 30)}) {
    _autoDispose = true;
    _autoDisposeDelay = delay;
    MemoryManager.instance.register(this);
    return this;
  }

  /// Enables signal history for time-travel debugging.
  Signal<T> withHistory({int size = 50}) {
    _hasHistory = true;
    _historySize = size;
    return this;
  }

  /// Marks this signal for A/B test variant injection.
  Signal<T> abTestKey(String key) {
    _abTestKey = key;
    return this;
  }
}
