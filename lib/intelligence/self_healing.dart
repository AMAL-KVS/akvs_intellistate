import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/signal.dart';
import 'intelligence_bridge.dart';
import '../ffi/rust_bridge.dart';

/// Connects intelligence health checks to active recovery mechanisms.
class SelfHealingCoordinator {
  static final SelfHealingCoordinator instance = SelfHealingCoordinator._();
  SelfHealingCoordinator._();

  Timer? _monitorTimer;
  final List<Signal> _trackedSignals = [];

  /// Register a critical signal for periodic health monitoring.
  void registerCriticalSignal(Signal signal) {
    if (!_trackedSignals.contains(signal)) {
      _trackedSignals.add(signal);
    }
  }

  /// Start periodic monitoring of critical signals.
  void startMonitoring({Duration interval = const Duration(seconds: 15)}) {
    _monitorTimer?.cancel();
    _monitorTimer = Timer.periodic(interval, (_) => _evaluateHealth());
    debugPrint('[SelfHealing] Activated periodic monitoring.');
  }

  void stopMonitoring() {
    _monitorTimer?.cancel();
    _monitorTimer = null;
  }

  void _evaluateHealth() {
    for (final signal in _trackedSignals) {
      if (signal.isDisposed) continue;

      final level = IntelligenceBridge.instance.getDegradationLevel(signal);

      if (level == RustDegradationLevel.degraded) {
        debugPrint(
          '[SelfHealing] Unhealthy signal detected: ${signal.name}. Monitoring closely.',
        );
      } else if (level == RustDegradationLevel.frozen) {
        debugPrint(
          '[SelfHealing] CRITICAL: Signal ${signal.name} is completely frozen due to errors.',
        );
        _executeRecoveryPlan(signal);
      }
    }
    _trackedSignals.removeWhere((s) => s.isDisposed);
  }

  void _executeRecoveryPlan(Signal signal) {
    // In a full implementation, this might ask the DomainStore to
    // re-hydrate from a previous DomainSnapshot.
    debugPrint('[SelfHealing] Engaging safe-mode fallback for ${signal.name}.');
  }
}
