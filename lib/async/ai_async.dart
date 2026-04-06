import 'dart:async';
import '../core/signal.dart';
import '../core/dependency_tracker.dart';
import '../core/scheduler.dart';

/// Sealed class representing an asynchronous value.
sealed class AsyncValue<T> {
  const AsyncValue._();

  /// Convenience method to map the [AsyncValue] state to a specific type.
  R when<R>({
    required R Function(T data) data,
    required R Function() loading,
    required R Function(Object error, StackTrace stackTrace) error,
  }) {
    return switch (this) {
      AsyncData<T>(:final value) => data(value),
      AsyncLoading<T>() => loading(),
      AsyncError<T>(:final errorObj, :final stackTrace) => error(
        errorObj,
        stackTrace,
      ),
    };
  }

  /// Returns the data if the state is [AsyncData], otherwise null.
  T? get valueOrNull => switch (this) {
    AsyncData<T>(:final value) => value,
    _ => null,
  };
}

/// Represents a successful computation.
class AsyncData<T> extends AsyncValue<T> {
  final T value;
  const AsyncData(this.value) : super._();
}

/// Represents an in-flight computation.
class AsyncLoading<T> extends AsyncValue<T> {
  const AsyncLoading() : super._();
}

/// Represents a failed computation.
class AsyncError<T> extends AsyncValue<T> {
  final Object errorObj;
  final StackTrace stackTrace;
  const AsyncError(this.errorObj, this.stackTrace) : super._();
}

/// A reactive container for asynchronous computations.
///
/// Automatically re-triggers the computation when its dependencies change.
class AsyncSignal<T> extends Signal<AsyncValue<T>> implements SignalObserver {
  final Future<T> Function() _factory;
  final Duration? _cacheFor;

  Completer<T>? _activeCompleter;
  DateTime? _lastSuccessTime;

  /// Signals that this async signal currently depends on.
  final Set<dynamic> _dependencies = {};

  /// Creates a new [AsyncSignal].
  AsyncSignal(
    Future<T> Function() factory, {
    Duration? cacheFor,
    super.autoDispose,
  }) : _factory = factory,
       _cacheFor = cacheFor,
       super(const AsyncLoading()) {
    _trigger();
  }

  @override
  AsyncValue<T> call() {
    checkDisposed();
    DependencyTracker.instance.reportRead(this);
    return super.value;
  }

  @override
  void markDirty() {
    if (!isDisposed) {
      UpdateScheduler.instance.scheduleEffect(_trigger);
    }
  }

  /// Forces a fresh execution of the async factory, bypassing any cache.
  void refresh() {
    _lastSuccessTime = null;
    _trigger();
  }

  void _trigger() {
    if (isDisposed) return;

    // Check cache
    if (_cacheFor != null && _lastSuccessTime != null) {
      final now = DateTime.now();
      if (now.difference(_lastSuccessTime!) < _cacheFor) {
        return;
      }
    }

    // Cancel dependency tracking old listeners
    for (final _ in _dependencies) {
      DependencyTracker.instance.unregister(this);
    }
    _dependencies.clear();

    // Start fresh tracking
    late Future<T> future;
    DependencyTracker.instance.track(() => future = _factory(), (signal) {
      _dependencies.add(signal);
      DependencyTracker.instance.register(signal, this);
    });

    _execute(future);
  }

  void _execute(Future<T> future) {
    // Deduplication logic: If a new trigger starts, it generates a new future.
    // We only care about the result of the MOST RECENT future.
    final myCompleter = Completer<T>();
    _activeCompleter = myCompleter;

    if (super.value is! AsyncLoading) {
      super.value = const AsyncLoading();
    }

    future
        .then((result) {
          if (_activeCompleter == myCompleter && !isDisposed) {
            _lastSuccessTime = DateTime.now();
            super.value = AsyncData(result);
          }
        })
        .catchError((err, stack) {
          if (_activeCompleter == myCompleter && !isDisposed) {
            super.value = AsyncError(err, stack);
          }
        });
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

/// Creates a reactive async signal.
AsyncSignal<T> aiAsync<T>(
  Future<T> Function() factory, {
  Duration? cacheFor,
  bool autoDispose = false,
}) {
  return AsyncSignal<T>(factory, cacheFor: cacheFor, autoDispose: autoDispose);
}
