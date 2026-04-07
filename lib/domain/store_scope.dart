import 'package:flutter/widgets.dart';
import 'domain_store.dart';

/// Scopes a [DomainStore] to a widget subtree.
/// The store is disposed when the widget is removed from the tree.
/// Signals inside the store continue to work normally within the scope.
///
/// Usage:
/// ```dart
///   StoreScope(
///     store: CartStore(),
///     child: CheckoutPage(),
///   )
/// ```
///
/// Access within the subtree (no BuildContext needed after init):
/// ```dart
///   CartStore.of()
/// ```
class StoreScope<T extends DomainStore> extends StatefulWidget {
  /// The store to scope.
  final T store;

  /// The child widget tree.
  final Widget child;

  const StoreScope({required this.store, required this.child, super.key});

  @override
  State<StoreScope<T>> createState() => _StoreScopeState<T>();
}

class _StoreScopeState<T extends DomainStore> extends State<StoreScope<T>> {
  @override
  void initState() {
    super.initState();
    widget.store.register();
  }

  @override
  void dispose() {
    widget.store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
