/// Session lifecycle tracking for AKVS Behavior Intelligence.
///
/// Manages session IDs, duration, signal write counts, and engagement scoring.
/// Sessions are automatically started/ended based on app lifecycle events.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/dependency_tracker.dart';
import 'behavior_config.dart';
import 'behavior_event.dart';
import 'behavior_reporter.dart';
import 'user_segment.dart';

/// Generates a simple unique session ID without external packages.
String _generateSessionId() {
  final now = DateTime.now();
  final hash = Object.hash(now.microsecondsSinceEpoch, identityHashCode(now));
  return '${now.millisecondsSinceEpoch}-${hash.toRadixString(36)}';
}

/// Tracks session lifecycle: start, end, duration, engagement.
///
/// Implements [WidgetsBindingObserver] to detect app lifecycle changes.
/// Sessions are separated by [AkvsBehavior.sessionGapThreshold].
class SessionTracker with WidgetsBindingObserver {
  SessionTracker._();

  static SessionTracker? _instance;

  static String _currentSessionId = '';
  static DateTime _sessionStartTime = DateTime.now();
  static DateTime? _pauseTime;
  static int _totalSessionCount = 0;
  static int _sessionSignalWriteCount = 0;
  static int _sessionScreenViewCount = 0;
  static DateTime? _lastSessionTimestamp;

  static void Function()? _busUnsubscribe;

  /// Current session ID.
  static String get currentSessionId => _currentSessionId;

  /// Duration of the current session so far.
  static Duration get currentSessionDuration =>
      DateTime.now().difference(_sessionStartTime);

  /// Number of lifetime sessions for this user.
  static int get totalSessionCount => _totalSessionCount;

  /// Number of signal writes in the current session.
  static int get sessionSignalWriteCount => _sessionSignalWriteCount;

  /// Number of screen views in the current session.
  static int get sessionScreenViewCount => _sessionScreenViewCount;

  /// Increment screen view count. Called by ScreenTracker.
  static void incrementScreenViews() => _sessionScreenViewCount++;

  /// Engagement score for the current session (0.0–1.0).
  ///
  /// Formula:
  ///   score = clamp(
  ///     (screenViews * 0.3 + signalWrites * 0.4 + sessionMinutes * 0.3) / 100,
  ///     0.0, 1.0
  ///   )
  static double get engagementScore {
    final minutes = currentSessionDuration.inSeconds / 60.0;
    final raw =
        (_sessionScreenViewCount * 0.3 +
            _sessionSignalWriteCount * 0.4 +
            minutes * 0.3) /
        100.0;
    return raw.clamp(0.0, 1.0);
  }

  /// Starts session tracking. Called automatically by [AkvsBehavior.init].
  static void start() {
    _instance = SessionTracker._();
    WidgetsBinding.instance.addObserver(_instance!);

    // Load persisted data
    _loadPersistedData();

    // Subscribe to behavior bus for signal write counting
    _busUnsubscribe = DependencyTracker.instance.addBehaviorListener(({
      required String signalName,
      required String? behaviorCategory,
      required String previousValueType,
      required String newValueType,
    }) {
      _sessionSignalWriteCount++;
    });

    _beginNewSession();
  }

  /// Begin a new session.
  static void _beginNewSession() {
    _currentSessionId = _generateSessionId();
    _sessionStartTime = DateTime.now();
    _sessionSignalWriteCount = 0;
    _sessionScreenViewCount = 0;
    _totalSessionCount++;

    final sinceLastSession =
        _lastSessionTimestamp != null
            ? DateTime.now().difference(_lastSessionTimestamp!)
            : Duration.zero;

    _persistData();

    BehaviorReporter.report(
      SessionStartEvent(
        timestamp: DateTime.now(),
        sessionId: _currentSessionId,
        totalSessionCount: _totalSessionCount,
        sinceLastSession: sinceLastSession,
      ),
    );
  }

  /// Manually ends the current session. Fires [SessionEndEvent].
  /// Called automatically on `AppLifecycleState.paused`.
  static void end() {
    final duration = currentSessionDuration;
    final score = engagementScore;

    UserSegmentEngine.recordSessionData(
      engagementScore: score,
      sessionDuration: duration,
    );

    BehaviorReporter.report(
      SessionEndEvent(
        timestamp: DateTime.now(),
        sessionId: _currentSessionId,
        sessionDuration: duration,
        screenViewCount: _sessionScreenViewCount,
        signalWriteCount: _sessionSignalWriteCount,
        engagementScore: score,
      ),
    );

    _lastSessionTimestamp = DateTime.now();
    _persistData();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (AkvsBehavior.instance?.enabled != true) return;

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _pauseTime = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      if (_pauseTime != null) {
        final gap = DateTime.now().difference(_pauseTime!);
        final threshold =
            AkvsBehavior.instance?.sessionGapThreshold ??
            const Duration(minutes: 30);
        if (gap > threshold) {
          // End old session, start new one
          end();
          _beginNewSession();
        }
        _pauseTime = null;
      }
    }
  }

  /// Load persisted session data from shared_preferences.
  static Future<void> _loadPersistedData() async {
    final prefix = AkvsBehavior.instance?.localStoragePrefix;
    if (prefix == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      _totalSessionCount = prefs.getInt('${prefix}_total_sessions') ?? 0;
      final lastMs = prefs.getInt('${prefix}_last_session_timestamp');
      if (lastMs != null) {
        _lastSessionTimestamp = DateTime.fromMillisecondsSinceEpoch(lastMs);
      }
    } catch (_) {
      // Silently fail — never block main thread
    }
  }

  /// Persist session data (fire-and-forget, never blocks UI).
  static void _persistData() {
    final prefix = AkvsBehavior.instance?.localStoragePrefix;
    if (prefix == null) return;

    // ignore: discarded_futures
    _persistAsync(prefix);
  }

  static Future<void> _persistAsync(String prefix) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('${prefix}_total_sessions', _totalSessionCount);
      if (_lastSessionTimestamp != null) {
        await prefs.setInt(
          '${prefix}_last_session_timestamp',
          _lastSessionTimestamp!.millisecondsSinceEpoch,
        );
      }
    } catch (_) {
      // Fire-and-forget
    }
  }

  /// Reset for testing.
  static void reset() {
    if (_instance != null) {
      WidgetsBinding.instance.removeObserver(_instance!);
    }
    _busUnsubscribe?.call();
    _busUnsubscribe = null;
    _instance = null;
    _currentSessionId = '';
    _sessionStartTime = DateTime.now();
    _pauseTime = null;
    _totalSessionCount = 0;
    _sessionSignalWriteCount = 0;
    _sessionScreenViewCount = 0;
    _lastSessionTimestamp = null;
  }
}
