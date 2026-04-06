/// Sealed class hierarchy for all behavior-tracking events.
///
/// All events are immutable and carry no PII — only signal names,
/// value type names, and aggregate metadata.
library;

import 'user_segment.dart';

/// Base sealed class for all behavior events.
sealed class BehaviorEvent {
  /// When the event occurred.
  final DateTime timestamp;

  /// Session in which the event occurred.
  final String sessionId;

  const BehaviorEvent({required this.timestamp, required this.sessionId});

  /// Serialize to a JSON-compatible map.
  Map<String, dynamic> toJson();
}

/// Fired when a new user session begins.
final class SessionStartEvent extends BehaviorEvent {
  /// Lifetime total sessions for this user.
  final int totalSessionCount;

  /// Duration since the previous session ended.
  final Duration sinceLastSession;

  const SessionStartEvent({
    required super.timestamp,
    required super.sessionId,
    required this.totalSessionCount,
    required this.sinceLastSession,
  });

  @override
  Map<String, dynamic> toJson() => {
    'type': 'session_start',
    'timestamp': timestamp.toIso8601String(),
    'session_id': sessionId,
    'total_session_count': totalSessionCount,
    'since_last_session_ms': sinceLastSession.inMilliseconds,
  };
}

/// Fired when a session ends (app backgrounded > sessionGapThreshold).
final class SessionEndEvent extends BehaviorEvent {
  /// Total session duration.
  final Duration sessionDuration;

  /// Screens visited during this session.
  final int screenViewCount;

  /// Total signal writes during this session.
  final int signalWriteCount;

  /// Engagement score computed for this session (0.0–1.0).
  final double engagementScore;

  const SessionEndEvent({
    required super.timestamp,
    required super.sessionId,
    required this.sessionDuration,
    required this.screenViewCount,
    required this.signalWriteCount,
    required this.engagementScore,
  });

  @override
  Map<String, dynamic> toJson() => {
    'type': 'session_end',
    'timestamp': timestamp.toIso8601String(),
    'session_id': sessionId,
    'session_duration_ms': sessionDuration.inMilliseconds,
    'screen_view_count': screenViewCount,
    'signal_write_count': signalWriteCount,
    'engagement_score': engagementScore,
  };
}

/// Fired when the active screen signal changes.
final class ScreenViewEvent extends BehaviorEvent {
  /// Name of the new screen.
  final String screenName;

  /// Name of the previous screen, if any.
  final String? previousScreen;

  /// How long the user was on the previous screen.
  final Duration timeOnPrevious;

  const ScreenViewEvent({
    required super.timestamp,
    required super.sessionId,
    required this.screenName,
    this.previousScreen,
    required this.timeOnPrevious,
  });

  @override
  Map<String, dynamic> toJson() => {
    'type': 'screen_view',
    'timestamp': timestamp.toIso8601String(),
    'session_id': sessionId,
    'screen_name': screenName,
    'previous_screen': previousScreen,
    'time_on_previous_ms': timeOnPrevious.inMilliseconds,
  };
}

/// Fired when a screen is left (forward or back navigation).
final class ScreenLeaveEvent extends BehaviorEvent {
  /// Name of the screen being left.
  final String screenName;

  /// Total time spent on this screen visit.
  final Duration timeOnScreen;

  /// Number of signal writes while on this screen.
  final int actionsOnScreen;

  const ScreenLeaveEvent({
    required super.timestamp,
    required super.sessionId,
    required this.screenName,
    required this.timeOnScreen,
    required this.actionsOnScreen,
  });

  @override
  Map<String, dynamic> toJson() => {
    'type': 'screen_leave',
    'timestamp': timestamp.toIso8601String(),
    'session_id': sessionId,
    'screen_name': screenName,
    'time_on_screen_ms': timeOnScreen.inMilliseconds,
    'actions_on_screen': actionsOnScreen,
  };
}

/// Fired when a behavioral signal is written (action category).
///
/// No PII — only the signal name and value *type* name are recorded.
final class UserActionEvent extends BehaviorEvent {
  /// Name of the signal that was written.
  final String signalName;

  /// The category assigned via `behaviorCategory`.
  final String actionCategory;

  /// Type name of the previous value (e.g. 'int', 'String').
  final String previousValueType;

  /// Type name of the new value.
  final String valueTypeName;

  const UserActionEvent({
    required super.timestamp,
    required super.sessionId,
    required this.signalName,
    required this.actionCategory,
    required this.previousValueType,
    required this.valueTypeName,
  });

  @override
  Map<String, dynamic> toJson() => {
    'type': 'user_action',
    'timestamp': timestamp.toIso8601String(),
    'session_id': sessionId,
    'signal_name': signalName,
    'action_category': actionCategory,
    'previous_value_type': previousValueType,
    'value_type_name': valueTypeName,
  };
}

/// Fired when >= 3 rapid writes to the same signal within 1 second.
///
/// Indicates user frustration (rage tap).
final class RageTapEvent extends BehaviorEvent {
  /// Signal being repeatedly written.
  final String signalName;

  /// Number of rapid taps detected.
  final int tapCount;

  /// The time window in which taps occurred.
  final Duration within;

  const RageTapEvent({
    required super.timestamp,
    required super.sessionId,
    required this.signalName,
    required this.tapCount,
    required this.within,
  });

  @override
  Map<String, dynamic> toJson() => {
    'type': 'rage_tap',
    'timestamp': timestamp.toIso8601String(),
    'session_id': sessionId,
    'signal_name': signalName,
    'tap_count': tapCount,
    'within_ms': within.inMilliseconds,
  };
}

/// Fired when a funnel step is completed.
final class FunnelStepEvent extends BehaviorEvent {
  /// Name of the funnel.
  final String funnelName;

  /// Name of the step that was completed.
  final String stepName;

  /// 0-based index of the step.
  final int stepIndex;

  /// Time since the funnel was entered.
  final Duration sinceStart;

  /// Time since the previous step completed.
  final Duration sinceLastStep;

  const FunnelStepEvent({
    required super.timestamp,
    required super.sessionId,
    required this.funnelName,
    required this.stepName,
    required this.stepIndex,
    required this.sinceStart,
    required this.sinceLastStep,
  });

  @override
  Map<String, dynamic> toJson() => {
    'type': 'funnel_step',
    'timestamp': timestamp.toIso8601String(),
    'session_id': sessionId,
    'funnel_name': funnelName,
    'step_name': stepName,
    'step_index': stepIndex,
    'since_start_ms': sinceStart.inMilliseconds,
    'since_last_step_ms': sinceLastStep.inMilliseconds,
  };
}

/// Fired when a funnel is completed end-to-end.
final class FunnelCompleteEvent extends BehaviorEvent {
  /// Name of the completed funnel.
  final String funnelName;

  /// Total time from first step to last step.
  final Duration totalDuration;

  /// Steps that were skipped (0 for clean completion).
  final int droppedSteps;

  const FunnelCompleteEvent({
    required super.timestamp,
    required super.sessionId,
    required this.funnelName,
    required this.totalDuration,
    required this.droppedSteps,
  });

  @override
  Map<String, dynamic> toJson() => {
    'type': 'funnel_complete',
    'timestamp': timestamp.toIso8601String(),
    'session_id': sessionId,
    'funnel_name': funnelName,
    'total_duration_ms': totalDuration.inMilliseconds,
    'dropped_steps': droppedSteps,
  };
}

/// Fired when a funnel is abandoned (session ends before completion).
final class FunnelAbandonEvent extends BehaviorEvent {
  /// Name of the abandoned funnel.
  final String funnelName;

  /// Name of the last step that was completed.
  final String lastCompletedStep;

  /// Number of steps completed before abandonment.
  final int completedSteps;

  /// Total steps in the funnel.
  final int totalSteps;

  const FunnelAbandonEvent({
    required super.timestamp,
    required super.sessionId,
    required this.funnelName,
    required this.lastCompletedStep,
    required this.completedSteps,
    required this.totalSteps,
  });

  @override
  Map<String, dynamic> toJson() => {
    'type': 'funnel_abandon',
    'timestamp': timestamp.toIso8601String(),
    'session_id': sessionId,
    'funnel_name': funnelName,
    'last_completed_step': lastCompletedStep,
    'completed_steps': completedSteps,
    'total_steps': totalSteps,
  };
}

/// Fired periodically (every 60 seconds) with a retention snapshot.
final class RetentionSnapshotEvent extends BehaviorEvent {
  /// Consecutive days the user has been active.
  final int dauStreak;

  /// Total lifetime sessions.
  final int totalLifetimeSessions;

  /// Current computed user segment.
  final UserSegment segment;

  /// Churn risk score (0.0 = no risk, 1.0 = churned).
  final double churnRiskScore;

  const RetentionSnapshotEvent({
    required super.timestamp,
    required super.sessionId,
    required this.dauStreak,
    required this.totalLifetimeSessions,
    required this.segment,
    required this.churnRiskScore,
  });

  @override
  Map<String, dynamic> toJson() => {
    'type': 'retention_snapshot',
    'timestamp': timestamp.toIso8601String(),
    'session_id': sessionId,
    'dau_streak': dauStreak,
    'total_lifetime_sessions': totalLifetimeSessions,
    'segment': segment.name,
    'churn_risk_score': churnRiskScore,
  };
}
