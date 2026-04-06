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
  });
}
