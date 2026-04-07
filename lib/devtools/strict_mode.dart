import 'package:flutter/foundation.dart';
import '../core/signal.dart';

/// Configuration for strict architectural enforcement.
class StrictRules {
  /// Throws if a signal is read directly inside a widget build method
  /// without using a [Watch] or `context.watch()`.
  final bool enforceReactiveReads;

  /// Throws if a signal is mutated from a UI callback without being wrapped
  /// in a UseCase or `batch()` (if attempting strict MVI).
  final bool enforceActionLocality;

  /// Throws if a Computed signal creates a dependency cycle.
  final bool detectCycles;

  const StrictRules({
    this.enforceReactiveReads = true,
    this.enforceActionLocality = true,
    this.detectCycles = true,
  });
}

/// Broader devtools layer for strict architecture rules.
///
/// Ensures code adheres to IntelliState best practices.
/// ALL checks are stripped in release builds.
class AkvsStrictMode {
  AkvsStrictMode._();

  static bool _enabled = false;
  static StrictRules _rules = const StrictRules();

  /// Whether strict mode is enabled.
  static bool get isEnabled => _enabled;

  /// Enable strict mode with specific rules.
  static void enable({StrictRules rules = const StrictRules()}) {
    if (!kDebugMode) return;
    _enabled = true;
    _rules = rules;
  }

  /// Internal: check for a reactive read violation.
  static void checkReactiveRead(Signal signal, bool isInsideReactiveContext) {
    if (!kDebugMode || !_enabled || !_rules.enforceReactiveReads) return;
    if (!isInsideReactiveContext) {
      throw StateError(
        'Strict Mode: Signal ${signal.name ?? 'unnamed'} read outside '
        'of a reactive context. Wrap with Watch() or context.watch().',
      );
    }
  }

  /// Internal: check for action locality violation.
  static void checkActionLocality(Signal signal, bool isInsideBatchOrUseCase) {
    if (!kDebugMode || !_enabled || !_rules.enforceActionLocality) return;
    if (!isInsideBatchOrUseCase) {
      throw StateError(
        'Strict Mode: Signal ${signal.name ?? 'unnamed'} mutated '
        'directly from UI. Use a DomainStore or UseCase.',
      );
    }
  }

  /// Internal: check for computation cycle.
  static void checkCycle(String path) {
    if (!kDebugMode || !_enabled || !_rules.detectCycles) return;
    throw StateError('Strict Mode: Dependency cycle detected!\nPath: $path');
  }

  /// Reset for testing.
  static void reset() {
    _enabled = false;
    _rules = const StrictRules();
  }
}
