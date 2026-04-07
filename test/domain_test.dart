import 'package:flutter_test/flutter_test.dart';
import 'package:akvs_intellistate/akvs_intellistate.dart';

void main() {
  group('DomainResult', () {
    test('ok() creates successful result', () {
      const res = DomainResult.ok('success');
      expect(res.isOk, isTrue);
      expect(res.isError, isFalse);
      expect(res.value, 'success');
      expect(res.error, isNull);
    });

    test('error() creates failure result', () {
      const err = DomainError('Failed', code: 'ERR_1');
      const res = DomainResult<String>.error(err);
      expect(res.isOk, isFalse);
      expect(res.isError, isTrue);
      expect(res.error, equals(err));
      expect(() => res.value, throwsA(isA<DomainError>()));
    });
  });

  group('DomainSignal', () {
    test('Updates successfully when valid', () {
      final sig = DomainSignal<int>(
        0,
        validators: [Validators.min(0), Validators.max(10)],
      );

      final res = sig.update(5);
      expect(res.isOk, isTrue);
      expect(sig.value, 5);
    });

    test('Rejects update and retains previous value when invalid', () {
      final sig = DomainSignal<int>(
        5,
        validators: [Validators.min(0), Validators.max(10)],
      );

      final res = sig.update(15);
      expect(res.isError, isTrue);
      expect(res.error!.code, 'VALIDATION_MAX');
      expect(sig.value, 5); // Remained unchanged
    });

    test('forceUpdate bypasses validation', () {
      final sig = DomainSignal<int>(
        5,
        validators: [Validators.min(0), Validators.max(10)],
      );

      sig.forceUpdate(15);
      expect(sig.value, 15);
    });

    test('New style validation function works', () {
      final sig = DomainSignal<String>(
        '',
        validate: (v) => v.isNotEmpty,
        validationMessage: (v) => 'Cannot be empty',
      );

      expect(sig.isValid, isFalse); // Initially empty which is invalid

      final res1 = sig.update('');
      expect(res1.isError, isTrue);
      expect(sig.lastValidationMessage, 'Cannot be empty');

      final res2 = sig.update('Hello');
      expect(res2.isOk, isTrue);
      expect(sig.isValid, isTrue);
      expect(sig.lastValidationMessage, null);
    });
  });

  group('DomainStore', () {
    setUp(() => DomainStore.resetAll());

    test('register and of work', () {
      final store = TestStore()..register();
      expect(DomainStore.isRegistered<TestStore>(), isTrue);
      expect(DomainStore.of<TestStore>(), equals(store));
    });

    test('guard handles errors and updates isLoading', () async {
      final store = TestStore()..register();
      expect(store.isLoading.value, isFalse);

      await store.guard(() async {
        throw Exception('Test Error');
      });

      expect(store.isLoading.value, isFalse);
      expect(store.lastError.value, isA<Exception>());
      expect(store.lastError.value.toString(), contains('Test Error'));
    });

    test('reset clears internal state', () async {
      final store = TestStore()..register();
      await store.guard(() async {
        throw Exception('Test Error');
      });
      expect(store.lastError.value, isNotNull);

      store.reset();
      expect(store.lastError.value, isNull);
    });
  });

  group('UseCase', () {
    test('isRunning and lastError update properly', () async {
      final useCase = TestUseCase();
      expect(useCase.isRunning.value, isFalse);
      
      // Execute the failing case
      try {
        await useCase.call(true);
      } catch (_) {}
      
      expect(useCase.isRunning.value, isFalse);
      expect(useCase.lastError.value, isA<Exception>());

      // Execute the succeeding case
      await useCase.call(false);
      expect(useCase.isRunning.value, isFalse);
      expect(useCase.lastError.value, isNull);
    });
  });

  group('SignalHistory', () {
    test('records and replays history correctly', () {
      final sig = aiSignal(0).withHistory(size: 3);
      final history = SignalHistory(sig, maxSize: 3);
      
      sig.value = 1;
      sig.value = 2;
      sig.value = 3;
      sig.value = 4; // should push out 0

      expect(history.entries.length, 3);
      expect(history.entries.last.value, 4);
      expect(history.entries.first.value, 2);

      history.ago(1); // One step ago from the end (index 1) which is 3
      expect(sig.value, 3);

      history.replayTo(0);
      expect(sig.value, 2);
    });
  });

  group('AkvsStrictMode', () {
    setUp(() => AkvsStrictMode.reset());

    test('checkReactiveRead throws when violations occur', () {
      AkvsStrictMode.enable();
      final sig = aiSignal(0, name: 'test_sig');
      
      expect(
        () => AkvsStrictMode.checkReactiveRead(sig, false),
        throwsA(isA<StateError>()),
      );
      
      // Passing true should not throw
      AkvsStrictMode.checkReactiveRead(sig, true);
    });
  });
}

class TestStore extends DomainStore {
  // Empty test store
}

class TestUseCase extends UseCase<bool, String> {
  @override
  Future<String> execute(bool shouldFail) async {
    if (shouldFail) {
      throw Exception('Failed');
    }
    return 'Success';
  }
}
