import 'package:flutter/widgets.dart';
import '../core/signal.dart';
import '../core/dependency_tracker.dart';

/// Extension to allow watching signals directly from [BuildContext].
extension WatchExtension on BuildContext {
  /// Subscribes the current widget to the given [signal] and returns its value.
  ///
  /// The widget will automatically rebuild whenever the signal's value changes.
  /// This works in plain [StatelessWidget] or [StatefulWidget] build methods.
  T watch<T>(Signal<T> signal) {
    final element = this as Element;

    // We register the element to be rebuilt when the signal changes.
    DependencyTracker.instance.register(signal, _ElementObserver(element));

    return signal.value;
  }
}

/// Private observer that triggers a rebuild on a Flutter [Element].
class _ElementObserver implements SignalObserver {
  final Element element;
  _ElementObserver(this.element);

  @override
  void markDirty() {
    if (element.mounted) {
      element.markNeedsBuild();
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _ElementObserver &&
          runtimeType == other.runtimeType &&
          element == other.element;

  @override
  int get hashCode => element.hashCode;
}
