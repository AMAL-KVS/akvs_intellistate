import 'dependency_tracker.dart';
import 'scheduler.dart';

/// Function that is called to dispose of an effect or cleanup before re-run.
typedef CleanupFunction = void Function();

/// Function that defines an effect's side-effect.
typedef EffectFunction = CleanupFunction? Function();

/// Represents a reactive side-effect.
///
/// Effects run immediately to capture dependencies and re-run whenever
/// those dependencies change.
class Effect implements SignalObserver {
  final EffectFunction _job;
  CleanupFunction? _cleanup;
  bool _isDisposed = false;

  /// Signals that this effect currently depends on.
  final Set<dynamic> _dependencies = {};

  /// Creates and runs a new [Effect].
  Effect(this._job) {
    _run();
  }

  /// Manually triggers the effect to run.
  void _run() {
    if (_isDisposed) return;

    // Call cleanup from previous run if any.
    _cleanup?.call();
    _cleanup = null;

    // Clear old dependencies from the tracker.
    for (final _ in _dependencies) {
      DependencyTracker.instance.unregister(this);
    }
    _dependencies.clear();

    DependencyTracker.instance.track(
      () {
        _cleanup = _job();
      },
      (signal) {
        _dependencies.add(signal);
        DependencyTracker.instance.register(signal, this);
      },
    );
  }

  @override
  void markDirty() {
    if (!_isDisposed) {
      UpdateScheduler.instance.scheduleEffect(_run);
    }
  }

  /// Disposes of the effect, stopping it from responding to dependency changes.
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _cleanup?.call();
    _cleanup = null;

    for (final _ in _dependencies) {
      DependencyTracker.instance.unregister(this);
    }
    _dependencies.clear();
  }
}

/// Creates a new [Effect] that reactively executes side-effects.
///
/// Returns a [DisposeFunction] to stop the effect.
void Function() effect(EffectFunction job) {
  final e = Effect(job);
  return e.dispose;
}
