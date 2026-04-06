import '../domain/domain_result.dart';

/// Base class for all Application-level UseCases.
///
/// Use Cases encapsulate a single, highly-cohesive piece of business logic.
/// They orchestrate operations across DomainStores, Repositories, and
/// Services, keeping the presentation layer clear of orchestration logic.
///
/// [Input] represents the parameters required to execute the logic.
/// [Output] represents the strongly typed result.
abstract class UseCase<Input, Output> {
  const UseCase();

  /// Execute the business logic with the provided [input].
  ///
  /// Always returns a [DomainResult] ensuring predictable error handling
  /// and avoiding unhandled exceptions from creeping into the UI.
  Future<DomainResult<Output>> execute(Input input);

  /// Helper to wrap execution in a try-catch and output a predictable DomainError.
  Future<DomainResult<Output>> safeExecute(
    Input input,
    Future<Output> Function(Input i) operation,
  ) async {
    try {
      final res = await operation(input);
      return DomainResult.ok(res);
    } on DomainError catch (e) {
      return DomainResult.error(e);
    } catch (e, stack) {
      return DomainResult.error(
        DomainError(
          'An unexpected error occurred during execution.',
          code: 'UNEXPECTED_ERROR',
          details: {'error': e.toString(), 'stack': stack.toString()},
        ),
      );
    }
  }
}

/// A simpler UseCase that doesn't strictly require explicit input parameters.
abstract class NoInputUseCase<Output> extends UseCase<void, Output> {
  const NoInputUseCase();

  @override
  Future<DomainResult<Output>> execute([void input]) => perform();

  Future<DomainResult<Output>> perform();
}
