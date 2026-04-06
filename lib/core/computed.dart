import 'dependency_tracker.dart';
import 'scheduler.dart';
import 'signal.dart';

/// A reactive value that is derived from other signals.
///
/// Computed signals are lazy: they only recompute when their dependencies
/// change AND they are being read.
class Computed<T> extends Signal<T> implements SignalObserver {
  final T Function() _factory;

  /// Whether the cached value is stale.
  bool _isDirty = true;

  /// Signals that this computed value currently depends on.
  final Set<dynamic> _dependencies = {};

  /// Creates a new [Computed] signal from a value factory.
  Computed(this._factory, {super.autoDispose}) : super.internal() {
    _isDirty = true;
  }

  @override
  T call() {
    checkDisposed();
    if (_isDirty) {
      _recompute();
    }
    return super.call();
  }

  @override
  T get value {
    if (_isDirty) {
      _recompute();
    }
    return super.value;
  }

  @override
  set value(T newValue) {
    throw StateError('Computed signals are read-only.');
  }

  @override
  void markDirty() {
    if (!_isDirty) {
      _isDirty = true;
      UpdateScheduler.instance.scheduleComputed(_recompute);
      // Notify our own listeners that our value is now stale/going to change.
      DependencyTracker.instance.invalidate(this);
    }
  }

  /// Re-evaluates the factory and updates the cached value.
  void _recompute() {
    if (isDisposed) return;

    // Clear old dependencies from the tracker.
    for (final _ in _dependencies) {
      DependencyTracker.instance.unregister(this);
    }
    _dependencies.clear();

    late T newValue;
    DependencyTracker.instance.track(() => newValue = _factory(), (signal) {
      _dependencies.add(signal);
      DependencyTracker.instance.register(signal, this);
    });

    _isDirty = false;

    // If different from previous, update and notify via Signal's mechanism.
    if (!isInitialized || super.value != newValue) {
      super.value = newValue;
    }
  }

  @override
  void dispose() {
    for (final _ in _dependencies) {
      DependencyTracker.instance.unregister(this);
    }
    _dependencies.clear();
    super.dispose();
  }
}

/// Creates a new [Computed] signal that reactively derives its value.
Computed<T> computed<T>(T Function() factory, {bool autoDispose = false}) {
  return Computed<T>(factory, autoDispose: autoDispose);
}

/// Helper to handle null safely in initial value.
T unsafeCast<T>(dynamic obj) => obj as T;
