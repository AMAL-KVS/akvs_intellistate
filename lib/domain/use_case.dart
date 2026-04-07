import '../core/signal.dart';

/// A single-responsibility business operation.
/// Reads and writes signals. Fully testable with no Flutter dependency.
///
/// Usage:
/// ```dart
///   class AddToCartUseCase extends UseCase<CartItem, void> {
///     final CartStore _cart;
///     AddToCartUseCase(this._cart);
///
///     @override
///     Future<void> execute(CartItem input) async {
///       if (_cart.items().length >= 99) {
///         throw CartFullException();
///       }
///       await _cart.addItem(input);
///     }
///   }
///
///   // Call it:
///   final addToCart = AddToCartUseCase(CartStore.of());
///   await addToCart(CartItem(name: 'Widget'));
/// ```
abstract class UseCase<Input, Output> {
  final Signal<bool> _isRunning = Signal<bool>(false);
  final Signal<Object?> _lastError = Signal<Object?>(null);

  /// Execute the use case with [input].
  Future<Output> execute(Input input);

  /// Callable shorthand: `await useCase(input)`.
  Future<Output> call(Input input) async {
    _isRunning.value = true;
    _lastError.value = null;
    try {
      final result = await execute(input);
      return result;
    } catch (e) {
      _lastError.value = e;
      rethrow;
    } finally {
      _isRunning.value = false;
    }
  }

  /// Whether this use case is currently executing.
  Signal<bool> get isRunning => _isRunning;

  /// The last error from [execute], or null.
  Signal<Object?> get lastError => _lastError;
}

/// A use case with no input parameter.
abstract class NoInputUseCase<Output> extends UseCase<void, Output> {
  /// Callable shorthand with no arguments.
  Future<Output> run() => call(null);
}
