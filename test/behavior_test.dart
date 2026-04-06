import 'package:flutter_test/flutter_test.dart';
import 'package:akvs_intellistate/akvs_intellistate.dart';

void main() {
  // Ensure Flutter binding is available for WidgetsBindingObserver
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Reset all state before each test
    AkvsBehavior.reset();
  });

  group('SessionTracker', () {
    test('starts a new session on init', () {
      AkvsBehavior.init(
        enabled: true,
        trackScreens: false,
        trackInteractions: false,
        trackSegments: false,
        trackRetention: false,
      );

      expect(SessionTracker.currentSessionId, isNotEmpty);
      expect(SessionTracker.totalSessionCount, greaterThanOrEqualTo(1));
      expect(SessionTracker.sessionSignalWriteCount, 0);
      expect(SessionTracker.sessionScreenViewCount, 0);
    });

    test('engagement score is 0 at start', () {
      AkvsBehavior.init(
        enabled: true,
        trackScreens: false,
        trackInteractions: false,
        trackSegments: false,
        trackRetention: false,
      );

      // At start: 0 screen views, 0 writes, ~0 minutes
      expect(SessionTracker.engagementScore, closeTo(0.0, 0.01));
    });
  });

  group('ScreenTracker', () {
    test('detects navigation signal changes', () {
      AkvsBehavior.init(
        enabled: true,
        trackInteractions: false,
        trackSegments: false,
        trackRetention: false,
      );

      final screen = aiSignal(
        'home',
        name: 'screen',
        behavioral: true,
        behaviorCategory: 'navigation',
      );

      expect(ScreenTracker.currentScreen, isNull);

      // Change screen
      screen.value = 'product';
      expect(ScreenTracker.currentScreen, 'product');

      screen.value = 'cart';
      expect(ScreenTracker.currentScreen, 'cart');

      // Journey should contain all screens visited
      expect(ScreenTracker.sessionJourney, ['product', 'cart']);
    });
  });

  group('InteractionTracker', () {
    test('detects rage tap (3+ writes in 1s)', () {
      AkvsBehavior.init(
        enabled: true,
        trackScreens: false,
        trackSegments: false,
        trackRetention: false,
      );

      final button = aiSignal(
        0,
        name: 'rapidButton',
        behavioral: true,
        behaviorCategory: 'action',
      );

      expect(InteractionTracker.rageTapsThisSession, isEmpty);

      // Rapid writes — 4 in quick succession
      button.value = 1;
      button.value = 2;
      button.value = 3;
      button.value = 4;

      // Should have detected at least one rage tap
      expect(InteractionTracker.rageTapsThisSession, isNotEmpty);
      expect(InteractionTracker.isFrustrationSignal('rapidButton'), true);
      expect(InteractionTracker.frustrationScore, greaterThan(0.0));
    });
  });

  group('FunnelTracker', () {
    test('advances steps in order', () {
      AkvsBehavior.init(
        enabled: true,
        trackScreens: false,
        trackInteractions: false,
        trackSegments: false,
        trackRetention: false,
      );

      final step1Signal = aiSignal(
        false,
        name: 'step1',
        behavioral: true,
        behaviorCategory: 'action',
      );
      final step2Signal = aiSignal(
        false,
        name: 'step2',
        behavioral: true,
        behaviorCategory: 'action',
      );

      AkvsFunnel.define(
        name: 'test_funnel',
        steps: [
          FunnelStep(
            name: 'first',
            signal: step1Signal,
            condition: (v) => v == true,
          ),
          FunnelStep(
            name: 'second',
            signal: step2Signal,
            condition: (v) => v == true,
          ),
        ],
      );

      expect(AkvsFunnel.statusOf('test_funnel'), FunnelStatus.notStarted);
      expect(AkvsFunnel.lastCompletedStepOf('test_funnel'), -1);

      // Complete step 1
      step1Signal.value = true;
      expect(AkvsFunnel.lastCompletedStepOf('test_funnel'), 0);
      expect(AkvsFunnel.statusOf('test_funnel'), FunnelStatus.inProgress);

      // Complete step 2
      step2Signal.value = true;
      expect(AkvsFunnel.lastCompletedStepOf('test_funnel'), 1);
      expect(AkvsFunnel.statusOf('test_funnel'), FunnelStatus.completed);
    });

    test('marks abandoned on session end', () {
      AkvsBehavior.init(
        enabled: true,
        trackScreens: false,
        trackInteractions: false,
        trackSegments: false,
        trackRetention: false,
      );

      final funnelSignal = aiSignal(
        false,
        name: 'abandonStep',
        behavioral: true,
        behaviorCategory: 'action',
      );

      AkvsFunnel.define(
        name: 'abandon_funnel',
        steps: [
          FunnelStep(
            name: 'step_one',
            signal: funnelSignal,
            condition: (v) => v == true,
          ),
          FunnelStep(
            name: 'step_two',
            signal: funnelSignal,
            condition: (v) => false, // never completes
          ),
        ],
      );

      // Complete first step
      funnelSignal.value = true;
      expect(AkvsFunnel.statusOf('abandon_funnel'), FunnelStatus.inProgress);

      // End session — should mark as abandoned
      AkvsFunnel.onSessionEnd();
      expect(AkvsFunnel.statusOf('abandon_funnel'), FunnelStatus.abandoned);
    });
  });

  group('UserSegmentEngine', () {
    test('returns newUser on first session', () {
      AkvsBehavior.init(
        enabled: true,
        trackScreens: false,
        trackInteractions: false,
        trackRetention: false,
      );

      // First session → newUser
      expect(UserSegmentEngine.current, UserSegment.newUser);
    });
  });

  group('AkvsABTest', () {
    test('assigns same variant for same sessionId (deterministic)', () {
      AkvsBehavior.init(
        enabled: true,
        trackScreens: false,
        trackInteractions: false,
        trackSegments: false,
        trackRetention: false,
      );

      AkvsABTest.define(
        testId: 'test_experiment',
        variants: {
          'control': {'color': 'blue'},
          'variant_a': {'color': 'green'},
        },
        weights: [0.5, 0.5],
      );

      final first = AkvsABTest.assignedVariant('test_experiment');
      final second = AkvsABTest.assignedVariant('test_experiment');

      // Same session → same variant
      expect(first, second);
      expect(first, anyOf('control', 'variant_a'));
    });

    test('recordConversion increments conversion count', () {
      AkvsBehavior.init(
        enabled: true,
        trackScreens: false,
        trackInteractions: false,
        trackSegments: false,
        trackRetention: false,
      );

      AkvsABTest.define(
        testId: 'conversion_test',
        variants: {
          'control': {'cta': 'Buy'},
          'variant_a': {'cta': 'Order'},
        },
      );

      AkvsABTest.recordConversion('conversion_test');
      AkvsABTest.recordConversion('conversion_test');

      final rates = AkvsABTest.conversionRates('conversion_test');
      // One variant should have 100% conversion rate (since single user)
      expect(rates.values.any((r) => r > 0), true);
    });
  });

  group('RetentionTracker', () {
    test('churnRiskScore starts low for active user', () {
      AkvsBehavior.init(
        enabled: true,
        trackScreens: false,
        trackInteractions: false,
        trackSegments: false,
      );

      // Active today → churn risk should be low
      expect(RetentionTracker.churnRiskScore, lessThan(0.5));
      expect(RetentionTracker.daysSinceLastActive, lessThanOrEqualTo(0));
    });

    test('WAU and MAU counts include today', () {
      AkvsBehavior.init(
        enabled: true,
        trackScreens: false,
        trackInteractions: false,
        trackSegments: false,
      );

      expect(RetentionTracker.wauCount, greaterThanOrEqualTo(1));
      expect(RetentionTracker.mauCount, greaterThanOrEqualTo(1));
    });
  });

  group('FeatureTracker', () {
    test('tracks signal write counts', () {
      AkvsBehavior.init(
        enabled: true,
        trackScreens: false,
        trackInteractions: false,
        trackSegments: false,
        trackRetention: false,
      );

      final feature = aiSignal(
        0,
        name: 'testFeature',
        behavioral: true,
        behaviorCategory: 'action',
      );

      feature.value = 1;
      feature.value = 2;
      feature.value = 3;

      final usage = FeatureTracker.featureUsageThisSession;
      expect(usage['testFeature'], 3);
    });

    test('detects unused signals', () {
      AkvsBehavior.init(
        enabled: true,
        trackScreens: false,
        trackInteractions: false,
        trackSegments: false,
        trackRetention: false,
      );

      // Register but never write
      aiSignal(
        'unused',
        name: 'deadFeature',
        behavioral: true,
        behaviorCategory: 'action',
      );

      expect(FeatureTracker.unusedSignalsThisSession, contains('deadFeature'));
    });
  });

  group('BehaviorReporter', () {
    test('currentSnapshot contains all data', () {
      AkvsBehavior.init(
        enabled: true,
        trackScreens: false,
        trackInteractions: false,
        trackSegments: false,
        trackRetention: false,
      );

      final snap = BehaviorReporter.currentSnapshot;
      expect(snap.sessionId, isNotEmpty);
      expect(snap.engagementScore, isA<double>());
      expect(snap.frustrationScore, isA<double>());
      expect(snap.segment, isA<UserSegment>());
      expect(snap.toJson(), isA<Map<String, dynamic>>());
    });

    test('clearAll wipes session events', () async {
      AkvsBehavior.init(
        enabled: true,
        trackScreens: false,
        trackInteractions: false,
        trackSegments: false,
        trackRetention: false,
        localStoragePrefix: 'test_clear',
      );

      await BehaviorReporter.clearAll();
      expect(BehaviorReporter.sessionEvents, isEmpty);
    });
  });

  // ── Original Signal tests (ensure no regressions) ──

  group('Signal (no regression)', () {
    test('read and write', () {
      final s = aiSignal(0);
      expect(s.value, 0);
      expect(s(), 0);

      s.value = 1;
      expect(s.value, 1);
    });

    test('equality guard prevents unnecessary notifications', () {
      final s = aiSignal(0);
      int count = 0;
      effect(() {
        s();
        count++;
        return null;
      });

      expect(count, 1);
      s.value = 0; // Unchanged
      UpdateScheduler.instance.flush();
      expect(count, 1);
      s.value = 1; // Changed
      UpdateScheduler.instance.flush();
      expect(count, 2);
    });

    test('behavioral params default to false/null', () {
      final s = aiSignal(42);
      expect(s.behavioral, false);
      expect(s.behaviorCategory, isNull);
      expect(s.name, isNull);
    });

    test('behavioral params can be set', () {
      final s = aiSignal(
        0,
        name: 'mySignal',
        behavioral: true,
        behaviorCategory: 'action',
      );
      expect(s.behavioral, true);
      expect(s.behaviorCategory, 'action');
      expect(s.name, 'mySignal');
    });
  });
}
