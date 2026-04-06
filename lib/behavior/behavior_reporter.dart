/// Unified behavior reporting for AKVS Behavior Intelligence.
///
/// Aggregates all behavior data into snapshots, provides GA4 bridge,
/// and handles local persistence with GDPR compliance.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'ab_test.dart';
import 'behavior_config.dart';
import 'behavior_event.dart';
import 'feature_tracker.dart';
import 'funnel_tracker.dart';
import 'interaction_tracker.dart';
import 'retention_tracker.dart';
import 'screen_tracker.dart';
import 'session_tracker.dart';
import 'user_segment.dart';

/// A point-in-time snapshot of all behavior data.
class BehaviorSnapshot {
  final String sessionId;
  final Duration sessionDuration;
  final double engagementScore;
  final double frustrationScore;
  final double churnRiskScore;
  final UserSegment segment;
  final String? currentScreen;
  final List<String> sessionJourney;
  final Map<String, int> featureUsage;
  final List<RageTapEvent> rageTaps;
  final Map<String, FunnelStatus> funnelStatuses;
  final Map<String, String> abTestVariants;
  final int dauStreak;

  const BehaviorSnapshot({
    required this.sessionId,
    required this.sessionDuration,
    required this.engagementScore,
    required this.frustrationScore,
    required this.churnRiskScore,
    required this.segment,
    this.currentScreen,
    required this.sessionJourney,
    required this.featureUsage,
    required this.rageTaps,
    required this.funnelStatuses,
    required this.abTestVariants,
    required this.dauStreak,
  });

  /// Serialize to JSON-compatible map.
  Map<String, dynamic> toJson() => {
    'session_id': sessionId,
    'session_duration_ms': sessionDuration.inMilliseconds,
    'engagement_score': engagementScore,
    'frustration_score': frustrationScore,
    'churn_risk_score': churnRiskScore,
    'segment': segment.name,
    'current_screen': currentScreen,
    'session_journey': sessionJourney,
    'feature_usage': featureUsage,
    'rage_taps': rageTaps.map((e) => e.toJson()).toList(),
    'funnel_statuses': {
      for (final e in funnelStatuses.entries) e.key: e.value.name,
    },
    'ab_test_variants': abTestVariants,
    'dau_streak': dauStreak,
  };
}

/// Unified reporter for all behavior events.
///
/// Handles event routing, GA4 bridging, and local persistence.
class BehaviorReporter {
  BehaviorReporter._();

  /// Internal event log for this session.
  static final List<BehaviorEvent> _sessionEvents = [];

  /// Unified snapshot of all behavior data for the current session.
  static BehaviorSnapshot get currentSnapshot {
    return BehaviorSnapshot(
      sessionId: SessionTracker.currentSessionId,
      sessionDuration: SessionTracker.currentSessionDuration,
      engagementScore: SessionTracker.engagementScore,
      frustrationScore: InteractionTracker.frustrationScore,
      churnRiskScore: RetentionTracker.churnRiskScore,
      segment: UserSegmentEngine.current,
      currentScreen: ScreenTracker.currentScreen,
      sessionJourney: ScreenTracker.sessionJourney,
      featureUsage: FeatureTracker.featureUsageThisSession,
      rageTaps: InteractionTracker.rageTapsThisSession,
      funnelStatuses: AkvsFunnel.allStatuses,
      abTestVariants: AkvsABTest.allVariants,
      dauStreak: RetentionTracker.dauStreak,
    );
  }

  /// Report a behavior event.
  ///
  /// This is the central dispatch point. Events are:
  /// 1. Stored in the session log
  /// 2. Sent to GA4 if analytics are configured
  /// 3. Persisted to local storage if configured
  static void report(BehaviorEvent event) {
    if (AkvsBehavior.instance?.enabled != true) return;

    _sessionEvents.add(event);
    sendToGa4(event);

    if (AkvsBehavior.instance?.localStoragePrefix != null) {
      // Fire-and-forget persistence
      // ignore: discarded_futures
      persist(event);
    }
  }

  /// Send behavior events to GA4 via AkvsAnalytics (if configured).
  ///
  /// Maps BehaviorEvent subtypes to GA4 event names:
  /// - SessionStartEvent     → akvs_session_start
  /// - SessionEndEvent       → akvs_session_end
  /// - ScreenViewEvent       → akvs_screen_view
  /// - UserActionEvent       → akvs_user_action
  /// - RageTapEvent          → akvs_rage_tap
  /// - FunnelStepEvent       → akvs_funnel_step
  /// - FunnelCompleteEvent   → akvs_funnel_complete
  /// - FunnelAbandonEvent    → akvs_funnel_abandon
  /// - RetentionSnapshotEvent → akvs_retention_snapshot
  static void sendToGa4(BehaviorEvent event) {
    // GA4 bridge — currently logs to debug console.
    // When AkvsAnalytics is available, this will use its API.
    final eventName = switch (event) {
      SessionStartEvent() => 'akvs_session_start',
      SessionEndEvent() => 'akvs_session_end',
      ScreenViewEvent() => 'akvs_screen_view',
      ScreenLeaveEvent() => 'akvs_screen_leave',
      UserActionEvent() => 'akvs_user_action',
      RageTapEvent() => 'akvs_rage_tap',
      FunnelStepEvent() => 'akvs_funnel_step',
      FunnelCompleteEvent() => 'akvs_funnel_complete',
      FunnelAbandonEvent() => 'akvs_funnel_abandon',
      RetentionSnapshotEvent() => 'akvs_retention_snapshot',
    };

    // Placeholder: when AkvsAnalytics module is present, route here
    // ignore: unused_local_variable
    final ga4EventName = eventName;
  }

  /// Persist a behavior event to local storage (shared_preferences).
  static Future<void> persist(BehaviorEvent event) async {
    final prefix = AkvsBehavior.instance?.localStoragePrefix;
    if (prefix == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '${prefix}_events';
      final existing = prefs.getStringList(key) ?? [];
      existing.add(jsonEncode(event.toJson()));

      // Cap at 1000 events to prevent unbounded growth
      if (existing.length > 1000) {
        existing.removeRange(0, existing.length - 1000);
      }

      await prefs.setStringList(key, existing);
    } catch (_) {
      // Fire-and-forget — never block UI
    }
  }

  /// Load all persisted events from local storage.
  static Future<List<Map<String, dynamic>>> loadPersisted() async {
    final prefix = AkvsBehavior.instance?.localStoragePrefix;
    if (prefix == null) return [];

    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '${prefix}_events';
      final stored = prefs.getStringList(key) ?? [];
      return stored.map((s) => jsonDecode(s) as Map<String, dynamic>).toList();
    } catch (_) {
      return [];
    }
  }

  /// Clear all persisted behavior data (for GDPR/privacy compliance).
  ///
  /// Wipes every persisted key with the configured localStoragePrefix.
  /// This includes: events, session data, retention daily maps,
  /// A/B test conversions, and any other behavior data.
  static Future<void> clearAll() async {
    final prefix = AkvsBehavior.instance?.localStoragePrefix;
    if (prefix == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final keysToRemove =
          prefs.getKeys().where((k) => k.startsWith(prefix)).toList();
      for (final key in keysToRemove) {
        await prefs.remove(key);
      }
    } catch (_) {
      // Best-effort cleanup
    }

    _sessionEvents.clear();
  }

  /// Get all events this session.
  static List<BehaviorEvent> get sessionEvents =>
      List.unmodifiable(_sessionEvents);
}
