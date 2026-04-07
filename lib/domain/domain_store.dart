import 'package:flutter/foundation.dart';
import '../core/signal.dart';

/// A grouped container of related signals with built-in
/// business rules, validation, and actions.
///
/// Think of it as a Cubit/ViewModel but purely signal-based.
/// No events, no streams, no abstract classes to extend.
///
/// Usage:
/// ```dart
///   class CartStore extends DomainStore {
///     final items    = aiSignal<List<CartItem>>([]);
///     final discount = aiSignal(0.0);
///     final isCartLoading = aiSignal(false);
///
///     late final total = computed(() =>
///       items().fold(0.0, (s, i) => s + i.price) * (1 - discount())
///     );
///
///     Future<void> addItem(CartItem item) async {
///       guard(() async {
///         isCartLoading.value = true;
///         items.update((list) => [...list, item]);
///         isCartLoading.value = false;
///       });
///     }
///   }
///
///   // Register globally:
///   final cart = CartStore()..register();
///
///   // Or scope to a widget subtree:
///   StoreScope(store: cart, child: CheckoutPage())
/// ```
abstract class DomainStore {
  // ── Static registry ──────────────────────────────────────────────

  static final Map<Type, DomainStore> _registry = {};

  /// Human-readable name for this store (used in devtools).
  String get storeName => runtimeType.toString();

  /// Register this store as a singleton accessible anywhere.
  /// Returns self for chaining: `final cart = CartStore()..register();`
  void register() {
    _registry[runtimeType] = this;
    _initIfNeeded();
  }

  /// Retrieve a registered store anywhere without BuildContext.
  ///
  /// Throws [StateError] if the store has not been registered.
  static T of<T extends DomainStore>() {
    final store = _registry[T];
    if (store == null) {
      throw StateError(
        'DomainStore.of<$T>() called but $T has not been registered. '
        'Call $T()..register() first.',
      );
    }
    return store as T;
  }

  /// Check if a store type has been registered.
  static bool isRegistered<T extends DomainStore>() {
    return _registry.containsKey(T);
  }

  // ── Instance state ───────────────────────────────────────────────

  bool _disposed = false;
  bool _initCalled = false;

  final Signal<Object?> _lastError = Signal<Object?>(null);
  final Signal<bool> _isLoading = Signal<bool>(false);

  /// The last error caught by [guard]. Null if no error.
  Signal<Object?> get lastError => _lastError;

  /// Whether any [guard] call is currently executing.
  Signal<bool> get isLoading => _isLoading;

  /// Whether this store has been disposed.
  bool get isDisposed => _disposed;

  // ── Actions ──────────────────────────────────────────────────────

  /// Execute an action with automatic error handling.
  ///
  /// On throw: runs [onError] callback if provided,
  /// otherwise stores error in [lastError] signal.
  Future<void> guard(
    Future<void> Function() action, {
    void Function(Object error, StackTrace stack)? onError,
  }) async {
    if (_disposed) return;
    _isLoading.value = true;
    _lastError.value = null;
    try {
      await action();
    } catch (e, st) {
      if (onError != null) {
        onError(e, st);
      } else {
        _lastError.value = e;
        debugPrint('[DomainStore:$storeName] guard() caught: $e\n$st');
      }
    } finally {
      if (!_disposed) {
        _isLoading.value = false;
      }
    }
  }

  /// Resets all signals in this store to their initial values.
  ///
  /// Subclasses must override this to reset their own signals.
  void reset() {
    _lastError.value = null;
    _isLoading.value = false;
  }

  /// Disposes all signals and unregisters the store.
  @mustCallSuper
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    onDispose();
    _lastError.dispose();
    _isLoading.dispose();
    _registry.remove(runtimeType);
  }

  /// Called on first [register]. Override to do async init.
  Future<void> onInit() async {}

  /// Called on [dispose]. Override to clean up resources.
  void onDispose() {}

  void _initIfNeeded() {
    if (!_initCalled) {
      _initCalled = true;
      onInit();
    }
  }

  /// Reset all registered stores. Primarily for testing.
  @visibleForTesting
  static void resetAll() {
    for (final store in List.from(_registry.values)) {
      store.dispose();
    }
    _registry.clear();
  }
}
