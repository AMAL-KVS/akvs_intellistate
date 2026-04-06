import 'dart:async';

/// Function that executes a reactive update (Computed recompute or Effect run).
typedef UpdateFunction = void Function();

/// A priority-based scheduler for reactive updates.
///
/// Ensures that updates are batched and executed in the correct order:
/// 1. Computed updates (dependency resolution).
/// 2. Side effects (rendering, logging, etc).
class UpdateScheduler {
  UpdateScheduler._();

  static final UpdateScheduler instance = UpdateScheduler._();

  /// Whether a batch is currently active.
  bool _isBatching = false;

  /// Set of signals that became dirty during the current batch or microtask.
  final Set<dynamic> _dirtySignals = {};

  /// Queue for [Computed] updates (priority 1).
  final Set<UpdateFunction> _computedQueue = {};

  /// Queue for [Effect] updates (priority 2).
  final Set<UpdateFunction> _effectQueue = {};

  /// Whether a microtask has already been scheduled to flush the queues.
  bool _isFlushScheduled = false;

  /// Runs [fn] in a batch.
  ///
  /// All write operations during [fn] will not trigger immediate updates.
  /// Instead, all affected observers will be notified once [fn] completes.
  void batch(void Function() fn) {
    final wasBatching = _isBatching;
    _isBatching = true;
    try {
      fn();
    } finally {
      _isBatching = wasBatching;
      if (!_isBatching) {
        flush();
      } else {
        // LearningMode: Report that an immediate update was prevented.
        // This only counts if we're nested inside another batch.
        // Actually, the simple implementation in markDirty handles it better.
      }
    }
  }

  /// Registers a signal as dirty.
  void markDirty(dynamic signal) {
    _dirtySignals.add(signal);
    if (!_isBatching && !_isFlushScheduled) {
      _isFlushScheduled = true;
      scheduleMicrotask(flush);
    }
  }

  /// Schedules a [Computed] update.
  void scheduleComputed(UpdateFunction update) {
    _computedQueue.add(update);
    if (!_isBatching && !_isFlushScheduled) {
      _isFlushScheduled = true;
      scheduleMicrotask(flush);
    }
  }

  /// Schedules an [Effect] update.
  void scheduleEffect(UpdateFunction update) {
    _effectQueue.add(update);
    if (!_isBatching && !_isFlushScheduled) {
      _isFlushScheduled = true;
      scheduleMicrotask(flush);
    }
  }

  /// Executes all pending updates in priority order.
  void flush() {
    _isFlushScheduled = false;

    // 1. Process Computed queue first (priority 1)
    // We use a temporary list to allow the queue to grow if Computed
    // triggers other Computed values.
    while (_computedQueue.isNotEmpty) {
      final updates = List<UpdateFunction>.from(_computedQueue);
      _computedQueue.clear();
      for (final update in updates) {
        update();
      }
    }

    // 2. Process Effect queue (priority 2)
    while (_effectQueue.isNotEmpty) {
      final updates = List<UpdateFunction>.from(_effectQueue);
      _effectQueue.clear();
      for (final update in updates) {
        update();
      }
    }

    _dirtySignals.clear();
  }
}
