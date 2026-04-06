// AKVS IntelliState — Reactive state management with behavior intelligence.

export 'core/signal.dart' show aiSignal, Signal;
export 'core/computed.dart' show computed, Computed;
export 'core/effect.dart' show effect;
export 'core/scheduler.dart' show UpdateScheduler;
export 'async/ai_async.dart'
    show aiAsync, AsyncValue, AsyncData, AsyncLoading, AsyncError;
export 'flutter/signal_builder.dart' show SignalBuilder, Watch;
export 'flutter/watch_extension.dart' show WatchExtension;
export 'devtools/learning_mode.dart' show enableLearningMode;

// Behavior intelligence
export 'behavior/behavior_config.dart';
export 'behavior/behavior_event.dart';
export 'behavior/session_tracker.dart';
export 'behavior/screen_tracker.dart';
export 'behavior/interaction_tracker.dart';
export 'behavior/funnel_tracker.dart'
    show AkvsFunnel, FunnelStep, FunnelStatus, FunnelTracker;
export 'behavior/feature_tracker.dart';
export 'behavior/user_segment.dart';
export 'behavior/retention_tracker.dart';
export 'behavior/ab_test.dart';
export 'behavior/behavior_reporter.dart';

// Hybrid Core & FFI
export 'core/engine_mode.dart' show EngineMode, IntelliStateEngine;
export 'core/strict_mode.dart' show StrictMode, StrictModeOptions;

// Domain & Architecture Layer
export 'domain/domain_result.dart' show DomainResult, DomainError;
export 'domain/domain_signal.dart' show DomainSignal, Validator, Validators;
export 'domain/domain_snapshot.dart' show DomainSnapshot;
export 'domain/domain_store.dart' show DomainStore;
export 'application/usecase.dart' show UseCase, NoInputUseCase;
export 'application/controller.dart' show SignalController;
export 'application/coordinator.dart' show FlowCoordinator, FlowResult;

// Intelligence & Self-Healing
export 'intelligence/intelligence_bridge.dart' show IntelligenceBridge;
export 'intelligence/intelligence_tracker.dart' show DartIntelligenceTracker;
export 'intelligence/self_healing.dart' show SelfHealingCoordinator;

import 'core/scheduler.dart';

/// Runs [fn] in a batch, coalescing all signal updates.
///
/// Observers are only notified once the batch completes.
void batch(void Function() fn) {
  UpdateScheduler.instance.batch(fn);
}
