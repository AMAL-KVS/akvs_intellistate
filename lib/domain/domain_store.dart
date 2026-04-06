import 'package:flutter/foundation.dart';
import 'domain_snapshot.dart';
import '../core/scheduler.dart';

/// A `DomainStore` aggregates multiple `Signal`s or `DomainSignal`s into a
/// cohesive group representing a specific business domain (e.g. UserProfile, Cart).
///
/// It provides mechanisms for taking immutable snapshots of the entire domain
/// and restoring state from those snapshots.
abstract class DomainStore<T> {
  /// Extract current state into an immutable plain Dart object.
  T extractData();

  /// Hydrate the domain's signals from an immutable plain Dart object.
  ///
  /// Note: Hydration should usually bypass validation if the data is
  /// coming from a trusted source like local storage.
  void hydrateData(T data);

  /// Takes a complete snapshot of the current domain state.
  DomainSnapshot<T> takeSnapshot() {
    return DomainSnapshot<T>.withTime(extractData(), DateTime.now());
  }

  /// Restores the domain state from a snapshot safely.
  ///
  /// This operation is automatically batched so UI is bound only once
  /// after all signals have been successfully restored.
  void restoreSnapshot(DomainSnapshot<T> snapshot) {
    UpdateScheduler.instance.batch(() {
      try {
        hydrateData(snapshot.data);
      } catch (e, st) {
        debugPrint('[DomainStore] Failed to restore snapshot: $e\n$st');
        // If restoration fails, the batch ends and any partial updates
        // are still pushed. A robust implementation might keep an internal
        // backup before hydrating to achieve atomic rollbacks.
      }
    });
  }
}
