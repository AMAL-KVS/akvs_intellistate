import 'package:flutter_test/flutter_test.dart';
import 'package:akvs_intellistate/akvs_intellistate.dart';

void main() {
  group('Signal', () {
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

    test('functional update', () {
      final s = aiSignal(10);
      s.update((v) => v + 5);
      expect(s.value, 15);
    });
  });

  group('Computed', () {
    test('lazy recomputation and caching', () {
      final count = aiSignal(0);
      int computeCount = 0;
      final doubled = computed(() {
        computeCount++;
        return count() * 2;
      });

      expect(computeCount, 0); // Not read yet
      expect(doubled(), 0);
      expect(computeCount, 1);

      expect(doubled(), 0); // Cached
      expect(computeCount, 1);

      count.value = 1;
      expect(computeCount, 1); // Still lazy
      expect(doubled(), 2);
      expect(computeCount, 2);
    });

    test('chained computed', () {
      final count = aiSignal(2);
      final doubled = computed(() => count() * 2);
      final quadrupled = computed(() => doubled() * 2);

      expect(quadrupled(), 8);
      count.value = 3;
      expect(quadrupled(), 12);
    });
  });

  group('Effect', () {
    test('auto-tracking and cleanup', () {
      final s = aiSignal(0);
      int runCount = 0;
      int cleanupCount = 0;

      final stop = effect(() {
        s();
        runCount++;
        return () => cleanupCount++;
      });

      expect(runCount, 1);
      expect(cleanupCount, 0);

      s.value = 1;
      UpdateScheduler.instance.flush(); // Effects are batched
      expect(runCount, 2);
      expect(cleanupCount, 1);

      stop();
      s.value = 2;
      UpdateScheduler.instance.flush();
      expect(runCount, 2); // Stopped
      expect(cleanupCount, 2); // Final cleanup
    });
  });

  group('Batching', () {
    test('coalesces multiple updates', () {
      final a = aiSignal(0);
      final b = aiSignal(0);
      int runCount = 0;

      effect(() {
        a();
        b();
        runCount++;
        return null;
      });

      expect(runCount, 1);

      batch(() {
        a.value = 1;
        b.value = 1;
        a.value = 2;
      });

      UpdateScheduler.instance.flush();
      expect(runCount, 2); // Only one re-run after batch
      expect(a.value, 2);
      expect(b.value, 1);
    });
  });

  group('AsyncSignal', () {
    test('loading, data, and error states', () async {
      int fetchCount = 0;
      final userId = aiSignal(1);

      final user = aiAsync(() async {
        fetchCount++;
        if (userId() == 0) throw Exception('User not found');
        return 'User ${userId()}';
      });

      // The initial value set in _execute should reach here before microtasks.
      expect(user.value, isA<AsyncLoading>());
      expect(fetchCount, 1);

      // Wait for first fetch
      await Future.delayed(const Duration(milliseconds: 10));
      expect(user.value, isA<AsyncData>());
      expect((user.value as AsyncData).value, 'User 1');

      // Trigger re-fetch
      userId.value = 2;
      UpdateScheduler.instance.flush();
      expect(user.value, isA<AsyncLoading>());
      await Future.delayed(const Duration(milliseconds: 10));
      expect((user.value as AsyncData).value, 'User 2');
      expect(fetchCount, 2);

      // Error state
      userId.value = 0;
      UpdateScheduler.instance.flush();
      await Future.delayed(const Duration(milliseconds: 10));
      expect(user.value, isA<AsyncError>());
      expect(fetchCount, 3);
    });
  });
}
