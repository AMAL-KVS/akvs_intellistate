/// Screen journey tracking for AKVS Behavior Intelligence.
///
/// Automatically detects screen transitions by watching signals tagged
/// with `behaviorCategory: 'navigation'`. No Navigator instrumentation needed.
library;

import '../core/dependency_tracker.dart';
import 'behavior_config.dart';
import 'behavior_event.dart';
import 'behavior_reporter.dart';
import 'session_tracker.dart';

/// Tracks screen journeys based on navigation-tagged signals.
///
/// When a signal with `behaviorCategory: 'navigation'` changes, ScreenTracker
/// fires [ScreenViewEvent] and [ScreenLeaveEvent] automatically.
class ScreenTracker {
  ScreenTracker._();

  static String? _currentScreen;
  static DateTime? _screenEntryTime;
  static int _actionsOnCurrentScreen = 0;
  static final List<String> _sessionJourney = [];
  static final Map<String, List<Duration>> _timePerScreen = {};
  static final Map<String, int> _screenVisitCounts = {};

  static void Function()? _busUnsubscribe;

  /// The name of the current active screen.
  static String? get currentScreen => _currentScreen;

  /// Full ordered journey this session.
  static List<String> get sessionJourney => List.unmodifiable(_sessionJourney);

  /// Average time spent on each screen this session.
  static Map<String, Duration> get avgTimePerScreen {
    final result = <String, Duration>{};
    _timePerScreen.forEach((screen, durations) {
      if (durations.isEmpty) return;
      final totalMs = durations.fold<int>(
        0,
        (sum, d) => sum + d.inMilliseconds,
      );
      result[screen] = Duration(milliseconds: totalMs ~/ durations.length);
    });
    return result;
  }

  /// Most visited screen this session.
  static String? get mostVisitedScreen {
    if (_screenVisitCounts.isEmpty) return null;
    String? best;
    int bestCount = 0;
    _screenVisitCounts.forEach((screen, count) {
      if (count > bestCount) {
        bestCount = count;
        best = screen;
      }
    });
    return best;
  }

  /// Screens visited more than once this session.
  static List<String> get revisitedScreens {
    return _screenVisitCounts.entries
        .where((e) => e.value > 1)
        .map((e) => e.key)
        .toList();
  }

  /// Top 10 most common journey paths.
  ///
  /// Currently returns the session journey as the primary path.
  /// Future: aggregate across persisted sessions.
  static List<List<String>> get topJourneyPaths {
    if (_sessionJourney.isEmpty) return [];
    return [List.from(_sessionJourney)];
  }

  /// Initialize screen tracking.
  static void init() {
    _busUnsubscribe = DependencyTracker.instance.addBehaviorListener(({
      required String signalName,
      required String? behaviorCategory,
      required String previousValueType,
      required String newValueType,
    }) {
      if (AkvsBehavior.instance?.trackScreens != true) return;

      // Track actions on current screen (any signal write)
      _actionsOnCurrentScreen++;

      // Only handle navigation signals for screen changes
      if (behaviorCategory != 'navigation') return;

      // The signal name IS the screen name for navigation signals.
      // But we need the *value* — which we can't get from the bus
      // directly. Instead, the signal name serves as the tracker ID,
      // and the value change is inferred. We'll use a separate
      // mechanism: onScreenChange called from Signal's setter.
    });
  }

  /// Called when a navigation signal's value changes.
  ///
  /// This is invoked from Signal's set value when
  /// `behaviorCategory == 'navigation'`.
  static void onScreenChange(String signalName, String newScreen) {
    if (AkvsBehavior.instance?.trackScreens != true) return;

    final now = DateTime.now();
    final previousScreen = _currentScreen;

    // Fire leave event for previous screen
    if (previousScreen != null && _screenEntryTime != null) {
      final timeOnScreen = now.difference(_screenEntryTime!);
      _timePerScreen.putIfAbsent(previousScreen, () => []).add(timeOnScreen);

      BehaviorReporter.report(
        ScreenLeaveEvent(
          timestamp: now,
          sessionId: SessionTracker.currentSessionId,
          screenName: previousScreen,
          timeOnScreen: timeOnScreen,
          actionsOnScreen: _actionsOnCurrentScreen,
        ),
      );
    }

    // Fire view event for new screen
    final timeOnPrevious =
        _screenEntryTime != null
            ? now.difference(_screenEntryTime!)
            : Duration.zero;

    BehaviorReporter.report(
      ScreenViewEvent(
        timestamp: now,
        sessionId: SessionTracker.currentSessionId,
        screenName: newScreen,
        previousScreen: previousScreen,
        timeOnPrevious: timeOnPrevious,
      ),
    );

    // Update state
    _currentScreen = newScreen;
    _screenEntryTime = now;
    _actionsOnCurrentScreen = 0;
    _sessionJourney.add(newScreen);
    _screenVisitCounts[newScreen] = (_screenVisitCounts[newScreen] ?? 0) + 1;

    SessionTracker.incrementScreenViews();
  }

  /// Reset for testing.
  static void reset() {
    _busUnsubscribe?.call();
    _busUnsubscribe = null;
    _currentScreen = null;
    _screenEntryTime = null;
    _actionsOnCurrentScreen = 0;
    _sessionJourney.clear();
    _timePerScreen.clear();
    _screenVisitCounts.clear();
  }
}
