import '../core/signal.dart';
import 'domain_result.dart';

/// A function that validates a value and returns a [DomainError] if invalid.
typedef Validator<T> = DomainError? Function(T value);

/// A `DomainSignal` wraps a standard `Signal` but enforces validation rules
/// before accepting new values.
///
/// If a new value fails validation, the signal retains its previous value
/// and returns a [DomainResult.error]. Otherwise, it updates and returns
/// [DomainResult.ok].
class DomainSignal<T> {
  final Signal<T> _inner;
  final List<Validator<T>> _validators;

  DomainSignal(
    T initialValue, {
    List<Validator<T>>? validators,
    String? name,
    bool behavioral = false,
  }) : _validators = validators ?? [],
       _inner = aiSignal(initialValue, name: name, behavioral: behavioral);

  /// Get the current validated value.
  T call() => _inner();

  /// Get the current validated value.
  T get value => _inner.value;

  /// Attempt to update the value passing through all validation rules.
  DomainResult<T> update(T newValue) {
    for (final validator in _validators) {
      final error = validator(newValue);
      if (error != null) {
        return DomainResult.error(error);
      }
    }
    _inner.value = newValue;
    return DomainResult.ok(newValue);
  }

  /// Update value bypassing validation (use with caution, e.g. hydrating from DB).
  void forceUpdate(T newValue) {
    _inner.value = newValue;
  }

  /// Listen to changes on the underlying signal.
  void addListener(SignalListener<T> listener) => _inner.addListener(listener);

  void removeListener(SignalListener<T> listener) =>
      _inner.removeListener(listener);

  void dispose() => _inner.dispose();
}

// ═══════════════════════════════════════════════════════════════════════
//  COMMON VALIDATORS
// ═══════════════════════════════════════════════════════════════════════

class Validators {
  static Validator<String> notEmpty([String? customMessage]) {
    return (String value) {
      if (value.trim().isEmpty) {
        return DomainError(
          customMessage ?? 'Value cannot be empty',
          code: 'VALIDATION_NOT_EMPTY',
        );
      }
      return null;
    };
  }

  static Validator<int> min(int minValue, [String? customMessage]) {
    return (int value) {
      if (value < minValue) {
        return DomainError(
          customMessage ?? 'Value must be at least $minValue',
          code: 'VALIDATION_MIN',
        );
      }
      return null;
    };
  }

  static Validator<int> max(int maxValue, [String? customMessage]) {
    return (int value) {
      if (value > maxValue) {
        return DomainError(
          customMessage ?? 'Value must be at most $maxValue',
          code: 'VALIDATION_MAX',
        );
      }
      return null;
    };
  }

  static Validator<String> regex(RegExp pattern, [String? customMessage]) {
    return (String value) {
      if (!pattern.hasMatch(value)) {
        return DomainError(
          customMessage ?? 'Value does not match required pattern',
          code: 'VALIDATION_PATTERN',
        );
      }
      return null;
    };
  }
}
