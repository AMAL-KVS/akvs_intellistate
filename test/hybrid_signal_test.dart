import 'package:flutter_test/flutter_test.dart';
import 'package:akvs_intellistate/akvs_intellistate.dart';

void main() {
  setUp(() {
    // Reset any strict mode enforcement
    IntelliStateEngine.reset();
  });

  group('Hybrid Signal Core Tests', () {
    test('Default mode should use Dart implementation entirely', () {
      IntelliStateEngine.init(mode: EngineMode.dart);
      expect(IntelliStateEngine.activeMode, equals(EngineMode.dart));
      expect(IntelliStateEngine.isRustActive, isFalse);

      final counter = aiSignal(0);
      expect(counter.value, 0);
      counter.value = 10;
      expect(counter.value, 10);
    });

    test(
      'Rust mode attempts FFI integration but handles silent fallback if missing',
      () {
        // In a unit test environment without the .dylib/.so built, it will gracefully fallback.
        IntelliStateEngine.init(mode: EngineMode.rust);

        final counter = aiSignal(0, name: 'hybrid_counter');
        expect(counter.value, 0);
        counter.value = 42;
        expect(counter.value, 42);
      },
    );
  });
}
