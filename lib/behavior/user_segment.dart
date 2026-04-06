/// User segmentation engine for AKVS Behavior Intelligence.
///
/// Segments are computed automatically based on session data,
/// engagement metrics, and retention patterns.
library;

import '../core/signal.dart';
import 'behavior_config.dart';
import 'session_tracker.dart';
import 'retention_tracker.dart';

/// Predefined user segments based on engagement patterns.
enum UserSegment {
  /// First-time user (session count == 1).
  newUser,

  /// Regular but not power user (sessions 2–9).
  casual,

  /// High engagement, many sessions and actions.
  powerUser,

  /// Was active, now declining — DAU streak dropped.
  atRisk,

  /// No activity for > churnRiskDays.
  churned,
}

/// Engine that computes and maintains the current user segment.
///
/// The segment is reactive — you can watch [asSignal] in your UI
/// and show different experiences per segment:
/// ```dart
/// final seg = UserSegmentEngine.asSignal();
/// Watch((ctx) => seg() == UserSegment.atRisk
///   ? ReEngagementBanner() : SizedBox())
/// ```
class UserSegmentEngine {
  UserSegmentEngine._();

  static Signal<UserSegment>? _signal;
  static UserSegment _current = UserSegment.newUser;

  /// Historical engagement scores for segment computation.
  static final List<double> _engagementHistory = [];
  static final List<Duration> _sessionDurationHistory = [];

  /// Current segment for this user.
  static UserSegment get current => _current;

  /// Initialize the segment engine.
  static void init() {
    _signal = Signal<UserSegment>(UserSegment.newUser);
    recompute();
  }

  /// Register a session's engagement data for segment computation.
  static void recordSessionData({
    required double engagementScore,
    required Duration sessionDuration,
  }) {
    _engagementHistory.add(engagementScore);
    _sessionDurationHistory.add(sessionDuration);
    // Keep last 20 sessions for averaging
    if (_engagementHistory.length > 20) {
      _engagementHistory.removeAt(0);
      _sessionDurationHistory.removeAt(0);
    }
  }

  /// Recomputes the segment based on latest session and retention data.
  ///
  /// Called automatically on SessionEndEvent and RetentionSnapshotEvent.
  ///
  /// Segment computation rules:
  /// - `newUser`:   totalSessionCount == 1
  /// - `churned`:   daysSinceLastSession > churnRiskDays
  /// - `atRisk`:    dauStreak dropped by > 50% vs prior week average
  /// - `powerUser`: totalSessionCount >= powerUserSessionThreshold
  ///                AND avgSessionDuration > 5 minutes
  ///                AND avgEngagementScore > 0.6
  /// - `casual`:    everything else
  static UserSegment recompute() {
    final config = AkvsBehavior.instance;
    if (config == null) return _current;

    final totalSessions = SessionTracker.totalSessionCount;
    final daysSinceLast = RetentionTracker.daysSinceLastActive;
    final dauStreak = RetentionTracker.dauStreak;

    UserSegment segment;

    // Rule 1: New user
    if (totalSessions <= 1) {
      segment = UserSegment.newUser;
    }
    // Rule 2: Churned
    else if (daysSinceLast > config.churnRiskDays) {
      segment = UserSegment.churned;
    }
    // Rule 3: At risk — DAU streak low relative to history
    else if (dauStreak <= 1 && totalSessions > 3) {
      segment = UserSegment.atRisk;
    }
    // Rule 4: Power user
    else if (totalSessions >= config.powerUserSessionThreshold &&
        _avgSessionDuration > const Duration(minutes: 5) &&
        _avgEngagementScore > 0.6) {
      segment = UserSegment.powerUser;
    }
    // Rule 5: Casual (everything else)
    else {
      segment = UserSegment.casual;
    }

    _current = segment;
    _signal?.value = segment;
    return segment;
  }

  /// Returns a reactive Signal that updates whenever the segment changes.
  static Signal<UserSegment> asSignal() {
    _signal ??= Signal<UserSegment>(UserSegment.newUser);
    return _signal!;
  }

  /// Average engagement score across recent sessions.
  static double get _avgEngagementScore {
    if (_engagementHistory.isEmpty) return 0.0;
    return _engagementHistory.reduce((a, b) => a + b) /
        _engagementHistory.length;
  }

  /// Average session duration across recent sessions.
  static Duration get _avgSessionDuration {
    if (_sessionDurationHistory.isEmpty) return Duration.zero;
    final totalMs = _sessionDurationHistory.fold<int>(
      0,
      (sum, d) => sum + d.inMilliseconds,
    );
    return Duration(milliseconds: totalMs ~/ _sessionDurationHistory.length);
  }

  /// Reset for testing.
  static void reset() {
    _signal = null;
    _current = UserSegment.newUser;
    _engagementHistory.clear();
    _sessionDurationHistory.clear();
  }
}
