import 'dart:async';

/// Internal interface for objects that can observe signals.
abstract interface class SignalObserver {
  /// Called when a dependency of this observer changes.
  void markDirty();
}

/// A container for the current tracking context.
class _TrackingContext {
  final void Function(dynamic signal) onDepend;
  _TrackingContext(this.onDepend);
}

/// Singleton responsible for tracking reactive dependencies.
///
/// Uses [Zone] to maintain a stack of tracking contexts, ensuring that
/// nested computations or effects don't leak dependencies across scopes.
class DependencyTracker {
  DependencyTracker._();

  static final DependencyTracker instance = DependencyTracker._();

  /// Key for storing the tracking context in the current [Zone].
  static const Object _contextKey = #akvs_intellistate_tracking_context;

  /// Returns true if a tracking context is currently active in the current [Zone].
  bool get isTracking => Zone.current[_contextKey] != null;

  /// Internal graph mapping signals to their observers.
  final Map<dynamic, Set<SignalObserver>> _graph = {};

  /// Tracks signal reads within [fn].
  ///
  /// When a signal is read inside [fn], [onDepend] will be called with that signal.
  void track(void Function() fn, void Function(dynamic signal) onDepend) {
    runZoned(fn, zoneValues: {_contextKey: _TrackingContext(onDepend)});
  }

  /// Notifies the tracker that a signal has been read.
  ///
  /// If a tracking context is active, the signal is reported to it.
  void reportRead(dynamic signal) {
    final context = Zone.current[_contextKey] as _TrackingContext?;
    if (context != null) {
      context.onDepend(signal);
    }
  }

  /// Registers an observer for a specific signal.
  void register(dynamic signal, SignalObserver observer) {
    _graph.putIfAbsent(signal, () => {}).add(observer);
  }

  /// Unregisters an observer from all signals it was watching.
  void unregister(SignalObserver observer) {
    for (final observers in _graph.values) {
      observers.remove(observer);
    }
    _graph.removeWhere((key, value) => value.isEmpty);
  }

  /// Unregisters an observer from a specific signal.
  void unregisterFrom(dynamic signal, SignalObserver observer) {
    _graph[signal]?.remove(observer);
    if (_graph[signal]?.isEmpty ?? false) {
      _graph.remove(signal);
    }
  }

  /// Invalidates all observers that depend on the given [signal].
  ///
  /// This normally triggers a re-computation or schedules an effect.
  void invalidate(dynamic signal) {
    final observers = _graph[signal];
    if (observers != null) {
      // Copy to avoid concurrent modification errors
      for (final observer in List.from(observers)) {
        observer.markDirty();
      }
    }
  }

  /// Returns the set of signals that the given [observer] depends on.
  ///
  /// Primarily used for devtools and auditing.
  Set<dynamic> dependenciesOf(SignalObserver observer) {
    final deps = <dynamic>{};
    _graph.forEach((signal, observers) {
      if (observers.contains(observer)) {
        deps.add(signal);
      }
    });
    return deps;
  }

  /// Internal behavior event bus — invisible to public API.
  /// Used by behavior trackers to observe signal writes without
  /// polluting the reactive dependency graph.
  final _BehaviorBus _behaviorBus = _BehaviorBus();

  /// Notify the behavior bus that a signal was written.
  /// Called internally from Signal.set value.
  void notifyBehaviorWrite({
    required String signalName,
    required String? behaviorCategory,
    required String previousValueType,
    required String newValueType,
  }) {
    _behaviorBus._notify(
      signalName: signalName,
      behaviorCategory: behaviorCategory,
      previousValueType: previousValueType,
      newValueType: newValueType,
    );
  }

  /// Register a behavior listener. Returns a removal function.
  void Function() addBehaviorListener(
    void Function({
      required String signalName,
      required String? behaviorCategory,
      required String previousValueType,
      required String newValueType,
    })
    listener,
  ) {
    return _behaviorBus._addListener(listener);
  }
}

/// Callback signature for behavior write events.
typedef _BehaviorWriteCallback =
    void Function({
      required String signalName,
      required String? behaviorCategory,
      required String previousValueType,
      required String newValueType,
    });

/// Internal event bus for behavior tracking.
///
/// This class is private to the library — it is NOT exported.
/// Behavior trackers register listeners here to observe signal writes
/// without interfering with the reactive dependency graph.
class _BehaviorBus {
  final List<_BehaviorWriteCallback> _listeners = [];

  void Function() _addListener(_BehaviorWriteCallback listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  void _notify({
    required String signalName,
    required String? behaviorCategory,
    required String previousValueType,
    required String newValueType,
  }) {
    for (final listener in List.from(_listeners)) {
      listener(
        signalName: signalName,
        behaviorCategory: behaviorCategory,
        previousValueType: previousValueType,
        newValueType: newValueType,
      );
    }
  }
}
