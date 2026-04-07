import '../core/signal.dart';
import 'domain_result.dart';

/// A function that validates a value and returns a [DomainError] if invalid.
typedef Validator<T> = DomainError? Function(T value);

/// A Signal with built-in validation rules.
/// Rejects invalid values silently (or with a callback).
///
/// Supports two validation styles:
///
/// **New style** (single validate function):
/// ```dart
///   final age = DomainSignal<int>(
///     0,
///     validate: (v) => v >= 0 && v <= 120,
///     validationMessage: (v) => 'Age must be 0–120, got $v',
///   );
///   age.value = 25;    // accepted
///   age.value = -5;    // rejected, age stays 25
/// ```
///
/// **Classic style** (validator list, returns DomainResult):
/// ```dart
///   final age = DomainSignal<int>(
///     0,
///     validators: [Validators.min(0), Validators.max(120)],
///   );
///   final result = age.update(25); // DomainResult.ok(25)
/// ```
class DomainSignal<T> {
  final Signal<T> _inner;
  final List<Validator<T>> _validators;

  /// Single validation function (new API). Returns true if valid.
  final bool Function(T value)? _validate;

  /// Returns a human-readable message for invalid values (new API).
  final String Function(T value)? validationMessage;

  /// Called when a value fails validation.
  final void Function(T rejectedValue, String? message)? onValidationFailure;

  /// The last validation failure message. Null if last write was valid.
  String? _lastValidationMessage;

  DomainSignal(
    T initialValue, {
    bool Function(T value)? validate,
    List<Validator<T>>? validators,
    this.validationMessage,
    this.onValidationFailure,
    String? name,
    @Deprecated('Use .behavior() on the inner signal') bool behavioral = false,
  })  : _validate = validate,
        _validators = validators ?? [],
        _inner = aiSignal(
          initialValue,
          name: name,
          // ignore: deprecated_member_use_from_same_package
          behavioral: behavioral,
        );

  /// Get the current validated value (callable shorthand).
  T call() => _inner();

  /// Get the current validated value.
  T get value => _inner.value;

  /// The last validation failure message. Null if last write was valid.
  String? get lastValidationMessage => _lastValidationMessage;

  /// True if the current value passes all validation rules.
  bool get isValid {
    final val = _inner.value;
    if (_validate != null && !_validate(val)) return false;
    for (final v in _validators) {
      if (v(val) != null) return false;
    }
    return true;
  }

  /// Attempt to update the value passing through all validation rules.
  ///
  /// Returns [DomainResult.ok] if accepted, [DomainResult.error] if rejected.
  /// The signal value remains unchanged on rejection.
  DomainResult<T> update(T newValue) {
    // Check new-style validate function
    if (_validate != null && !_validate(newValue)) {
      final msg =
          validationMessage?.call(newValue) ?? 'Validation failed for $newValue';
      _lastValidationMessage = msg;
      onValidationFailure?.call(newValue, msg);
      return DomainResult.error(
        DomainError(msg, code: 'VALIDATION_FAILED'),
      );
    }

    // Check classic-style validators
    for (final validator in _validators) {
      final error = validator(newValue);
      if (error != null) {
        _lastValidationMessage = error.message;
        onValidationFailure?.call(newValue, _lastValidationMessage);
        return DomainResult.error(error);
      }
    }

    _lastValidationMessage = null;
    _inner.value = newValue;
    return DomainResult.ok(newValue);
  }

  /// Update value bypassing validation (use with caution, e.g. hydrating from DB).
  void forceUpdate(T newValue) {
    _lastValidationMessage = null;
    _inner.value = newValue;
  }

  /// The underlying signal (for advanced integrations).
  Signal<T> get signal => _inner;

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

  static Validator<double> range(double min, double max,
      [String? customMessage]) {
    return (double value) {
      if (value < min || value > max) {
        return DomainError(
          customMessage ?? 'Value must be between $min and $max',
          code: 'VALIDATION_RANGE',
        );
      }
      return null;
    };
  }
}
