/// Multi-step funnel tracking for AKVS Behavior Intelligence.
///
/// Developers define funnels declaratively using signal conditions.
/// FunnelTracker watches all signal writes and advances steps automatically.
library;

import '../core/dependency_tracker.dart';
import '../core/signal.dart';
import 'behavior_config.dart';
import 'behavior_event.dart';
import 'behavior_reporter.dart';
import 'session_tracker.dart';

/// Completion status of a funnel.
enum FunnelStatus {
  /// Funnel has not been entered yet.
  notStarted,

  /// User is partway through the funnel.
  inProgress,

  /// All steps completed successfully.
  completed,

  /// Session ended before funnel was completed.
  abandoned,

  /// Funnel timed out before completion.
  timedOut,
}

/// A single step in a funnel definition.
class FunnelStep {
  /// Human-readable name for this step.
  final String name;

  /// The signal to watch for this step.
  final Signal signal;

  /// Condition that must return true for the step to be complete.
  final bool Function(dynamic value) condition;

  /// Creates a funnel step.
  const FunnelStep({
    required this.name,
    required this.signal,
    required this.condition,
  });
}

/// Internal state for an active funnel instance.
class _FunnelState {
  final String name;
  final List<FunnelStep> steps;
  final Duration? timeoutDuration;
  final DateTime definedAt;

  FunnelStatus status = FunnelStatus.notStarted;
  int lastCompletedStep = -1;
  DateTime? startTime;
  DateTime? lastStepTime;

  // Persisted stats
  int completionCount = 0;
  int abandonCount = 0;
  int totalAttempts = 0;
  final Map<String, int> dropOffCounts = {};
  final List<Duration> completionTimes = [];

  _FunnelState({required this.name, required this.steps, this.timeoutDuration})
    : definedAt = DateTime.now();
}

/// Declarative funnel tracking engine.
///
/// Usage:
/// ```dart
/// AkvsFunnel.define(
///   name: 'checkout_flow',
///   steps: [
///     FunnelStep(name: 'view_cart', signal: cartItems,
///       condition: (v) => (v as List).isNotEmpty),
///     FunnelStep(name: 'enter_payment', signal: paymentState,
///       condition: (v) => v == PaymentState.entering),
///     FunnelStep(name: 'order_placed', signal: orderStatus,
///       condition: (v) => v == OrderStatus.confirmed),
///   ],
/// );
/// ```
class AkvsFunnel {
  AkvsFunnel._();

  static final Map<String, _FunnelState> _funnels = {};
  static void Function()? _busUnsubscribe;

  /// Register a funnel definition.
  ///
  /// Can be called at any point before the user reaches the first step.
  static void define({
    required String name,
    required List<FunnelStep> steps,
    Duration? timeoutDuration,
  }) {
    _funnels[name] = _FunnelState(
      name: name,
      steps: steps,
      timeoutDuration: timeoutDuration,
    );
  }

  /// Current completion status of a funnel.
  static FunnelStatus statusOf(String funnelName) {
    return _funnels[funnelName]?.status ?? FunnelStatus.notStarted;
  }

  /// Index of the last completed step (0-based). -1 = not started.
  static int lastCompletedStepOf(String funnelName) {
    return _funnels[funnelName]?.lastCompletedStep ?? -1;
  }

  /// Percentage of attempts that complete this funnel.
  static double completionRate(String funnelName) {
    final state = _funnels[funnelName];
    if (state == null || state.totalAttempts == 0) return 0.0;
    return state.completionCount / state.totalAttempts;
  }

  /// Most common drop-off step (step name where most users abandon).
  static String? topDropOffStep(String funnelName) {
    final state = _funnels[funnelName];
    if (state == null || state.dropOffCounts.isEmpty) return null;
    String? top;
    int topCount = 0;
    state.dropOffCounts.forEach((step, count) {
      if (count > topCount) {
        topCount = count;
        top = step;
      }
    });
    return top;
  }

  /// Average time to complete the funnel end-to-end.
  static Duration? avgCompletionTime(String funnelName) {
    final state = _funnels[funnelName];
    if (state == null || state.completionTimes.isEmpty) return null;
    final totalMs = state.completionTimes.fold<int>(
      0,
      (sum, d) => sum + d.inMilliseconds,
    );
    return Duration(milliseconds: totalMs ~/ state.completionTimes.length);
  }

  /// Check all funnel conditions against a signal write.
  static void _checkFunnels() {
    if (AkvsBehavior.instance?.enabled != true) return;

    final now = DateTime.now();

    for (final state in _funnels.values) {
      if (state.status == FunnelStatus.completed ||
          state.status == FunnelStatus.abandoned ||
          state.status == FunnelStatus.timedOut) {
        continue;
      }

      // Check timeout
      if (state.timeoutDuration != null &&
          state.startTime != null &&
          now.difference(state.startTime!) > state.timeoutDuration!) {
        state.status = FunnelStatus.timedOut;
        state.totalAttempts++;
        final lastStep =
            state.lastCompletedStep >= 0
                ? state.steps[state.lastCompletedStep].name
                : 'none';
        state.dropOffCounts[lastStep] =
            (state.dropOffCounts[lastStep] ?? 0) + 1;
        continue;
      }

      // Check next step
      final nextStepIndex = state.lastCompletedStep + 1;
      if (nextStepIndex >= state.steps.length) continue;

      final step = state.steps[nextStepIndex];
      bool stepComplete;
      try {
        stepComplete = step.condition(step.signal.value);
      } catch (_) {
        stepComplete = false;
      }

      if (stepComplete) {
        // Mark step complete
        if (state.status == FunnelStatus.notStarted) {
          state.status = FunnelStatus.inProgress;
          state.startTime = now;
          state.totalAttempts++;
        }

        final sinceStart =
            state.startTime != null
                ? now.difference(state.startTime!)
                : Duration.zero;
        final sinceLastStep =
            state.lastStepTime != null
                ? now.difference(state.lastStepTime!)
                : Duration.zero;

        state.lastCompletedStep = nextStepIndex;
        state.lastStepTime = now;

        BehaviorReporter.report(
          FunnelStepEvent(
            timestamp: now,
            sessionId: SessionTracker.currentSessionId,
            funnelName: state.name,
            stepName: step.name,
            stepIndex: nextStepIndex,
            sinceStart: sinceStart,
            sinceLastStep: sinceLastStep,
          ),
        );

        // Check if funnel is now complete
        if (nextStepIndex == state.steps.length - 1) {
          state.status = FunnelStatus.completed;
          state.completionCount++;
          final totalDuration = now.difference(state.startTime!);
          state.completionTimes.add(totalDuration);

          BehaviorReporter.report(
            FunnelCompleteEvent(
              timestamp: now,
              sessionId: SessionTracker.currentSessionId,
              funnelName: state.name,
              totalDuration: totalDuration,
              droppedSteps: 0,
            ),
          );
        }
      }
    }
  }

  /// Mark all in-progress funnels as abandoned.
  ///
  /// Called on session end.
  static void onSessionEnd() {
    final now = DateTime.now();

    for (final state in _funnels.values) {
      if (state.status == FunnelStatus.inProgress) {
        state.status = FunnelStatus.abandoned;
        final lastStep =
            state.lastCompletedStep >= 0
                ? state.steps[state.lastCompletedStep].name
                : 'none';
        state.dropOffCounts[lastStep] =
            (state.dropOffCounts[lastStep] ?? 0) + 1;

        BehaviorReporter.report(
          FunnelAbandonEvent(
            timestamp: now,
            sessionId: SessionTracker.currentSessionId,
            funnelName: state.name,
            lastCompletedStep: lastStep,
            completedSteps: state.lastCompletedStep + 1,
            totalSteps: state.steps.length,
          ),
        );
      }
    }
  }

  /// Initialize funnel tracking.
  static void init() {
    _busUnsubscribe = DependencyTracker.instance.addBehaviorListener(({
      required String signalName,
      required String? behaviorCategory,
      required String previousValueType,
      required String newValueType,
    }) {
      _checkFunnels();
    });
  }

  /// Get all funnel statuses.
  static Map<String, FunnelStatus> get allStatuses {
    return {
      for (final entry in _funnels.entries) entry.key: entry.value.status,
    };
  }

  /// Get completion percentage for a specific funnel (0.0 – 1.0).
  static double completionPercentage(String funnelName) {
    final state = _funnels[funnelName];
    if (state == null || state.steps.isEmpty) return 0.0;
    return (state.lastCompletedStep + 1) / state.steps.length;
  }

  /// Reset for testing.
  static void reset() {
    _busUnsubscribe?.call();
    _busUnsubscribe = null;
    _funnels.clear();
  }
}

/// Alias for backward compatibility and cleaner imports.
typedef FunnelTracker = AkvsFunnel;
