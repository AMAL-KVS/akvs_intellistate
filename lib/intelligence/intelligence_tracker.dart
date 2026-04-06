import '../core/signal.dart';

/// A simple pure-Dart fallback for intelligence tracking.
/// Used only when the high-performance Rust core is not loaded.
class DartIntelligenceTracker {
  final Map<int, _SignalStats> _stats = {};

  void recordWrite(Signal signal) {
    final stats = _getStats(signal);
    stats.writes++;
    stats.lastWrite = DateTime.now();
  }

  void recordError(Signal signal) {
    final stats = _getStats(signal);
    stats.errors++;
  }

  double getHealthScore(Signal signal) {
    final stats = _getStats(signal);

    // Very basic fallback formula simulating the Rust logic.
    final totalOps = stats.writes > 0 ? stats.writes : 1;
    final errorRate = (stats.errors / totalOps).clamp(0.0, 1.0);

    final stalenessSecs = DateTime.now().difference(stats.lastWrite).inSeconds;
    final stalenessFactor = (stalenessSecs / 300.0).clamp(0.0, 1.0);

    final errorPenalty = stats.errors == 0 ? 0.0 : 0.2;

    return (1.0 - (0.5 * errorRate) - (0.3 * stalenessFactor) - errorPenalty)
        .clamp(0.0, 1.0);
  }

  _SignalStats _getStats(Signal signal) {
    return _stats.putIfAbsent(signal.hashCode, () => _SignalStats());
  }
}

class _SignalStats {
  int writes = 0;
  int errors = 0;
  DateTime lastWrite = DateTime.now();
}
