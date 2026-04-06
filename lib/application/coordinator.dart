import 'package:flutter/foundation.dart';
import '../domain/domain_result.dart';
import '../core/signal.dart';

/// Defines the outcome of a Coordinator's flow.
class FlowResult<T> {
  final T? data;
  final DomainError? error;
  final bool isCancelled;

  const FlowResult.success(this.data) : error = null, isCancelled = false;

  const FlowResult.failure(this.error) : data = null, isCancelled = false;

  const FlowResult.cancelled() : data = null, error = null, isCancelled = true;
}

/// Abstract base class for complex UI flow coordination.
///
/// Flow Coordinators are responsible for connecting multiple screens
/// or intricate multi-step processes (e.g. Checkout Flow, Onboarding Flow)
/// that require an isolated sequence of operations and state.
abstract class FlowCoordinator<TResult> {
  bool _isActive = false;
  bool get isActive => _isActive;

  /// Call to begin the flow.
  @mustCallSuper
  Future<FlowResult<TResult>> start() async {
    if (_isActive) {
      debugPrint('[FlowCoordinator] Warning: Flow already active.');
      return FlowResult.failure(
        DomainError('Flow already in progress', code: 'FLOW_ACTIVE'),
      );
    }
    _isActive = true;
    try {
      return await executeFlow();
    } finally {
      _isActive = false;
    }
  }

  /// Override this to implement the multi-step flow logic.
  @protected
  Future<FlowResult<TResult>> executeFlow();

  /// A generalized helper to await a signal changing its value to a specific condition.
  /// Useful for waiting on user input or async state completion.
  @protected
  Future<T> waitForSignalCondition<T>(
    Signal<T> signal,
    bool Function(T value) condition,
  ) {
    if (condition(signal.value)) return Future.value(signal.value);

    final completer = ValueNotifier<T?>(null);
    void listener(T value) {
      if (condition(value) && completer.value == null) {
        completer.value = value;
      }
    }

    signal.addListener(listener);

    final future = Future.any([
      // Using a Future backed by a Completer logic tied to ValueNotifier
      // For simplicity in this mock, we just loop-wait, but real
      // implementation should use Completer pattern.
      _listenForCompletion(completer),
    ]);

    return future.whenComplete(() {
      signal.removeListener(listener);
    });
  }

  Future<T> _listenForCompletion<T>(ValueNotifier<T?> notifier) async {
    while (notifier.value == null) {
      await Future.delayed(const Duration(milliseconds: 16));
    }
    return notifier.value as T;
  }
}
