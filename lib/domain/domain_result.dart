/// A typed domain error representing a validation or business logic failure.
class DomainError implements Exception {
  final String message;
  final String code;
  final dynamic details;

  const DomainError(this.message, {this.code = 'INVALID_STATE', this.details});

  @override
  String toString() => 'DomainError[$code]: $message';
}

/// A predictable result type for domain operations.
class DomainResult<T> {
  final T? _value;
  final DomainError? _error;

  const DomainResult.ok(T value) : _value = value, _error = null;

  const DomainResult.error(DomainError error) : _value = null, _error = error;

  bool get isOk => _error == null;
  bool get isError => _error != null;

  T get value {
    if (_error != null) throw _error;
    return _value as T;
  }

  DomainError? get error => _error;

  R fold<R>(R Function(T value) onOk, R Function(DomainError error) onError) {
    if (isOk) {
      return onOk(_value as T);
    } else {
      return onError(_error!);
    }
  }
}
