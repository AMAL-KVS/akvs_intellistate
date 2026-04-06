import 'package:flutter/foundation.dart';
import '../domain/domain_result.dart';

/// Controller base structure for coordinating UI logic with Application UseCases.
///
/// SignalController acts as a standard pattern to tie feature-level UI logic
/// to Domain/Application logic. By convention:
/// - Keep them completely devoid of Flutter widget dependencies (No BuildContext).
/// - Expose minimal, specific public methods for the UI to interact with.
/// - Drive UI updates purely through `Signal` fields mutated internally.
abstract class SignalController {
  /// Check if the controller is disposed.
  bool get isDisposed => _isDisposed;
  bool _isDisposed = false;

  /// Subclasses should clean up internal resources (listeners, signals, etc)
  /// when this controller is no longer in use.
  @mustCallSuper
  void dispose() {
    _isDisposed = true;
  }

  /// Internal helper to easily run a DomainResult returning task,
  /// executing a standard side effect on error (e.g., logging or showing a toast).
  @protected
  Future<T?> runUseCase<T>(
    Future<DomainResult<T>> Function() task, {
    void Function(DomainError error)? onError,
  }) async {
    if (_isDisposed) return null;

    final result = await task();
    if (_isDisposed) return null;

    return result.fold((data) => data, (error) {
      if (onError != null) {
        onError(error);
      } else {
        debugPrint('[SignalController] Unhandled UseCase Error: $error');
      }
      return null;
    });
  }
}
