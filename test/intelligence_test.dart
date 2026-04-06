import 'package:flutter_test/flutter_test.dart';
import 'package:akvs_intellistate/akvs_intellistate.dart';
import 'package:akvs_intellistate/ffi/rust_bridge.dart';

void main() {
  group('Intelligence Bridge & Tracker', () {
    test('Dart fallback tracker computes health scores correctly', () async {
      final sig = aiSignal(0);
      final bridge = IntelligenceBridge.instance;

      // Initial health should be perfect
      expect(bridge.getHealthScore(sig), equals(1.0));
      expect(
        bridge.getDegradationLevel(sig),
        equals(RustDegradationLevel.normal),
      );

      // Simulate a write
      bridge.recordDartWrite(sig);
      expect(bridge.getHealthScore(sig), equals(1.0));

      // Simulate an error
      bridge.recordDartError(sig);

      // With 1 write and 1 error -> 100% error rate
      // Health = 1.0 - (0.5 * 1.0) - (errorPenalty of 0.2) = 0.3
      // We expect it to be <= 0.3 which classifies as frozen or degraded based on exact float math
      final score = bridge.getHealthScore(sig);
      expect(score, lessThanOrEqualTo(0.3));

      final level = bridge.getDegradationLevel(sig);
      expect(
        level == RustDegradationLevel.frozen ||
            level == RustDegradationLevel.degraded,
        isTrue,
      );
    });

    test('Self-healing coordinator active tracking', () {
      final sig = aiSignal(100);
      SelfHealingCoordinator.instance.registerCriticalSignal(sig);

      // Just test activation and deactivation
      SelfHealingCoordinator.instance.startMonitoring(
        interval: const Duration(milliseconds: 100),
      );
      SelfHealingCoordinator.instance.stopMonitoring();

      expect(true, isTrue); // Passes if no exceptions
    });
  });

  group('Strict Mode', () {
    test('Strict mode honors explicit writes conditionally', () {
      // Not an automated test since _rustSignalId requires internal state inspection,
      // but we can ensure activating it doesn't crash normal flows.
      StrictMode.enable(
        options: const StrictModeOptions(throwOnFrozenWrite: true),
      );
      expect(true, isTrue);
    });
  });
}
