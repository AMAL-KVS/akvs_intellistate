/// Retention tracking for AKVS Behavior Intelligence.
///
/// Computes DAU streak, WAU/MAU approximations, churn risk score,
/// and last-7-days activity patterns — all on-device.
library;

import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/signal.dart';
import 'behavior_config.dart';
import 'interaction_tracker.dart';
import 'session_tracker.dart';

/// Tracks retention metrics: DAU streak, churn risk, WAU/MAU.
///
/// Provides a reactive [Signal<double>] for churn risk score that
/// can be watched in the UI for re-engagement prompts:
/// ```dart
/// Watch((ctx) =>
///   RetentionTracker.asSignal()() > 0.7
///     ? RetentionPromptWidget() : SizedBox()
/// )
/// ```
class RetentionTracker {
  RetentionTracker._();

  static Signal<double>? _churnSignal;
  static Timer? _snapshotTimer;

  /// Persisted map: date string (yyyy-MM-dd) → session count.
  static final Map<String, int> _dailySessionMap = {};

  /// Number of consecutive days the user has been active.
  static int get dauStreak {
    if (_dailySessionMap.isEmpty) return 0;

    final today = _dateKey(DateTime.now());
    if (!_dailySessionMap.containsKey(today)) {
      // Check if yesterday was active (user may not have opened today yet)
      final yesterday = _dateKey(
        DateTime.now().subtract(const Duration(days: 1)),
      );
      if (!_dailySessionMap.containsKey(yesterday)) return 0;
    }

    int streak = 0;
    var date = DateTime.now();
    for (int i = 0; i < 365; i++) {
      final key = _dateKey(date);
      if (_dailySessionMap.containsKey(key)) {
        streak++;
        date = date.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }
    return streak;
  }

  /// Whether the user was active on each of the last 7 days.
  static List<bool> get last7DaysActivity {
    final result = <bool>[];
    final today = DateTime.now();
    for (int i = 6; i >= 0; i--) {
      final date = today.subtract(Duration(days: i));
      result.add(_dailySessionMap.containsKey(_dateKey(date)));
    }
    return result;
  }

  /// Days since the last session started.
  static int get daysSinceLastActive {
    if (_dailySessionMap.isEmpty) return 999;

    final sortedDates = _dailySessionMap.keys.toList()..sort();
    if (sortedDates.isEmpty) return 999;

    try {
      final lastDate = DateTime.parse(sortedDates.last);
      return DateTime.now().difference(lastDate).inDays;
    } catch (_) {
      return 999;
    }
  }

  /// Churn risk score (0.0 = no risk, 1.0 = churned).
  ///
  /// Formula:
  ///   base = (daysSinceLastActive / churnRiskDays).clamp(0.0, 1.0)
  ///   boosted by: low engagementScore, high frustrationScore
  static double get churnRiskScore {
    final config = AkvsBehavior.instance;
    if (config == null) return 0.0;

    final base = (daysSinceLastActive / config.churnRiskDays).clamp(0.0, 1.0);

    // Boost by low engagement and high frustration
    final engagement = SessionTracker.engagementScore;
    final frustration = InteractionTracker.frustrationScore;

    final boosted = base * 0.6 + (1.0 - engagement) * 0.2 + frustration * 0.2;
    return boosted.clamp(0.0, 1.0);
  }

  /// Returns a reactive `Signal<double>` for churnRiskScore.
  static Signal<double> asSignal() {
    _churnSignal ??= Signal<double>(0.0);
    return _churnSignal!;
  }

  /// Persisted map: date string → session count.
  static Map<String, int> get dailySessionMap =>
      Map.unmodifiable(_dailySessionMap);

  /// Rolling 7-day active day count (WAU approximation).
  static int get wauCount {
    final today = DateTime.now();
    int count = 0;
    for (int i = 0; i < 7; i++) {
      final date = today.subtract(Duration(days: i));
      if (_dailySessionMap.containsKey(_dateKey(date))) {
        count++;
      }
    }
    return count;
  }

  /// Rolling 28-day active day count (MAU approximation).
  static int get mauCount {
    final today = DateTime.now();
    int count = 0;
    for (int i = 0; i < 28; i++) {
      final date = today.subtract(Duration(days: i));
      if (_dailySessionMap.containsKey(_dateKey(date))) {
        count++;
      }
    }
    return count;
  }

  /// Initialize retention tracking.
  static void init() {
    _churnSignal = Signal<double>(0.0);

    // Record today's activity
    _recordToday();

    // Load persisted data
    _loadPersistedData();

    // Start periodic snapshot (every 60 seconds)
    _snapshotTimer?.cancel();
    _snapshotTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _updateChurnSignal();
    });
  }

  /// Record a session for today.
  static void _recordToday() {
    final today = _dateKey(DateTime.now());
    _dailySessionMap[today] = (_dailySessionMap[today] ?? 0) + 1;
    _persistData();
  }

  /// Update the churn signal value.
  static void _updateChurnSignal() {
    _churnSignal?.value = churnRiskScore;
  }

  /// Load persisted retention data.
  static Future<void> _loadPersistedData() async {
    final prefix = AkvsBehavior.instance?.localStoragePrefix;
    if (prefix == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where(
        (k) => k.startsWith('${prefix}_daily_'),
      );
      for (final key in keys) {
        final dateStr = key.replaceFirst('${prefix}_daily_', '');
        final count = prefs.getInt(key) ?? 0;
        _dailySessionMap[dateStr] = count;
      }
    } catch (_) {
      // Silently fail
    }
  }

  /// Persist retention data (fire-and-forget).
  static void _persistData() {
    final prefix = AkvsBehavior.instance?.localStoragePrefix;
    if (prefix == null) return;
    // ignore: discarded_futures
    _persistAsync(prefix);
  }

  static Future<void> _persistAsync(String prefix) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final entry in _dailySessionMap.entries) {
        await prefs.setInt('${prefix}_daily_${entry.key}', entry.value);
      }
    } catch (_) {
      // Fire-and-forget
    }
  }

  /// Format a DateTime to a date key string (yyyy-MM-dd).
  static String _dateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// Reset for testing.
  static void reset() {
    _snapshotTimer?.cancel();
    _snapshotTimer = null;
    _churnSignal = null;
    _dailySessionMap.clear();
  }
}
