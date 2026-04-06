//! Resilience Engine — Crash tracking, safe mode, and signal throttling.
//!
//! Monitors signal errors and automatically activates protective measures:
//! - Freeze signals that crash repeatedly
//! - Throttle update frequency for degraded signals
//! - Activate global safe mode when system health is critical

use parking_lot::{Mutex, RwLock};
use std::collections::{HashMap, HashSet, VecDeque};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::time::{Duration, Instant};

use crate::signal::SignalId;

/// Sliding window crash statistics.
#[derive(Debug)]
pub struct CrashStats {
    /// Total crashes recorded since initialization.
    pub total_crashes: AtomicU64,
    /// Timestamps of recent crashes (sliding window).
    crash_timestamps: Mutex<VecDeque<Instant>>,
    /// Count of crashes per error type.
    error_types: Mutex<HashMap<String, u64>>,
    /// Size of the sliding window.
    window_duration: Duration,
}

impl CrashStats {
    pub fn new() -> Self {
        Self {
            total_crashes: AtomicU64::new(0),
            crash_timestamps: Mutex::new(VecDeque::with_capacity(100)),
            error_types: Mutex::new(HashMap::new()),
            window_duration: Duration::from_secs(60), // 1-minute window
        }
    }

    /// Record a crash with its error type.
    pub fn record(&self, error_type: &str) {
        self.total_crashes.fetch_add(1, Ordering::Relaxed);

        let now = Instant::now();
        let mut timestamps = self.crash_timestamps.lock();
        timestamps.push_back(now);

        // Prune old timestamps outside the window
        let cutoff = now - self.window_duration;
        while timestamps.front().is_some_and(|t| *t < cutoff) {
            timestamps.pop_front();
        }

        *self
            .error_types
            .lock()
            .entry(error_type.to_string())
            .or_insert(0) += 1;
    }

    /// Get the crash frequency (crashes per minute) in the current window.
    pub fn frequency(&self) -> f64 {
        let timestamps = self.crash_timestamps.lock();
        let now = Instant::now();
        let cutoff = now - self.window_duration;
        let recent = timestamps.iter().filter(|t| **t >= cutoff).count();
        recent as f64
    }

    /// Get total crash count.
    pub fn total(&self) -> u64 {
        self.total_crashes.load(Ordering::Relaxed)
    }

    /// Get error type distribution.
    pub fn error_distribution(&self) -> HashMap<String, u64> {
        self.error_types.lock().clone()
    }
}

impl Default for CrashStats {
    fn default() -> Self {
        Self::new()
    }
}

/// Per-signal crash tracking.
#[derive(Debug)]
struct SignalCrashRecord {
    error_count: u64,
    recent_errors: VecDeque<Instant>,
    last_error_type: Option<String>,
}

impl SignalCrashRecord {
    fn new() -> Self {
        Self {
            error_count: 0,
            recent_errors: VecDeque::with_capacity(20),
            last_error_type: None,
        }
    }
}

/// Configuration for resilience thresholds.
#[derive(Debug, Clone)]
pub struct ResilienceConfig {
    /// Number of errors in window before auto-freezing a signal.
    pub freeze_threshold: u64,
    /// Duration of the error window.
    pub error_window: Duration,
    /// Number of errors before activating global safe mode.
    pub safe_mode_threshold: u64,
    /// Minimum duration between updates for throttled signals.
    pub throttle_interval: Duration,
}

impl Default for ResilienceConfig {
    fn default() -> Self {
        Self {
            freeze_threshold: 5,
            error_window: Duration::from_secs(30),
            safe_mode_threshold: 10,
            throttle_interval: Duration::from_millis(500),
        }
    }
}

/// The resilience engine — monitors and protects the signal system.
pub struct ResilienceEngine {
    /// Global crash statistics.
    pub stats: CrashStats,
    /// Per-signal crash records.
    signal_records: RwLock<HashMap<SignalId, SignalCrashRecord>>,
    /// Set of currently frozen signals.
    frozen_signals: RwLock<HashSet<SignalId>>,
    /// Throttle intervals per signal.
    throttled_signals: RwLock<HashMap<SignalId, Instant>>,
    /// Whether global safe mode is active.
    safe_mode_active: AtomicBool,
    /// Configuration.
    config: ResilienceConfig,
}

impl std::fmt::Debug for ResilienceEngine {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ResilienceEngine")
            .field("safe_mode", &self.is_safe_mode())
            .field("frozen_count", &self.frozen_signals.read().len())
            .finish()
    }
}

impl ResilienceEngine {
    pub fn new() -> Self {
        Self::with_config(ResilienceConfig::default())
    }

    pub fn with_config(config: ResilienceConfig) -> Self {
        Self {
            stats: CrashStats::new(),
            signal_records: RwLock::new(HashMap::new()),
            frozen_signals: RwLock::new(HashSet::new()),
            throttled_signals: RwLock::new(HashMap::new()),
            safe_mode_active: AtomicBool::new(false),
            config,
        }
    }

    /// Record an error for a specific signal.
    /// Automatically freezes the signal if threshold exceeded.
    /// Automatically activates safe mode if global threshold exceeded.
    pub fn record_error(&self, signal_id: SignalId, error_type: &str) {
        // Update global stats
        self.stats.record(error_type);

        // Update per-signal record
        let mut records = self.signal_records.write();
        let record = records
            .entry(signal_id)
            .or_insert_with(SignalCrashRecord::new);

        record.error_count += 1;
        record.last_error_type = Some(error_type.to_string());

        let now = Instant::now();
        record.recent_errors.push_back(now);

        // Prune old errors outside window
        let cutoff = now - self.config.error_window;
        while record.recent_errors.front().is_some_and(|t| *t < cutoff) {
            record.recent_errors.pop_front();
        }

        // Check freeze threshold for this signal
        if record.recent_errors.len() as u64 >= self.config.freeze_threshold {
            drop(records);
            self.freeze_signal(signal_id);
        }

        // Check global safe mode threshold
        if self.stats.frequency() >= self.config.safe_mode_threshold as f64 {
            self.enter_safe_mode();
        }
    }

    /// Freeze a signal (prevent all writes).
    pub fn freeze_signal(&self, signal_id: SignalId) {
        self.frozen_signals.write().insert(signal_id);
    }

    /// Unfreeze a signal.
    pub fn unfreeze_signal(&self, signal_id: SignalId) {
        self.frozen_signals.write().remove(&signal_id);
    }

    /// Check if a signal is frozen.
    pub fn is_frozen(&self, signal_id: SignalId) -> bool {
        self.frozen_signals.read().contains(&signal_id)
    }

    /// Get all frozen signal IDs.
    pub fn frozen_signal_ids(&self) -> Vec<SignalId> {
        self.frozen_signals.read().iter().copied().collect()
    }

    /// Check if a write should be allowed for a signal.
    /// Takes into account: frozen state, throttling, and safe mode.
    pub fn is_write_allowed(&self, signal_id: SignalId) -> bool {
        // Check frozen
        if self.is_frozen(signal_id) {
            return false;
        }

        // Check safe mode throttling
        if self.is_safe_mode() {
            let mut throttled = self.throttled_signals.write();
            let now = Instant::now();
            if let Some(last) = throttled.get(&signal_id) {
                if now.duration_since(*last) < self.config.throttle_interval {
                    return false;
                }
            }
            throttled.insert(signal_id, now);
        }

        true
    }

    /// Activate global safe mode.
    pub fn enter_safe_mode(&self) {
        self.safe_mode_active.store(true, Ordering::Release);
    }

    /// Deactivate global safe mode.
    pub fn exit_safe_mode(&self) {
        self.safe_mode_active.store(false, Ordering::Release);
        self.throttled_signals.write().clear();
    }

    /// Check if safe mode is active.
    pub fn is_safe_mode(&self) -> bool {
        self.safe_mode_active.load(Ordering::Acquire)
    }

    /// Get error count for a specific signal.
    pub fn signal_error_count(&self, signal_id: SignalId) -> u64 {
        self.signal_records
            .read()
            .get(&signal_id)
            .map(|r| r.error_count)
            .unwrap_or(0)
    }

    /// Get summary stats for diagnostics.
    pub fn summary(&self) -> ResilienceSummary {
        ResilienceSummary {
            total_crashes: self.stats.total(),
            crash_frequency: self.stats.frequency(),
            frozen_count: self.frozen_signals.read().len(),
            safe_mode: self.is_safe_mode(),
            error_types: self.stats.error_distribution(),
        }
    }
}

impl Default for ResilienceEngine {
    fn default() -> Self {
        Self::new()
    }
}

/// Snapshot of resilience state for reporting.
#[derive(Debug, Clone)]
pub struct ResilienceSummary {
    pub total_crashes: u64,
    pub crash_frequency: f64,
    pub frozen_count: usize,
    pub safe_mode: bool,
    pub error_types: HashMap<String, u64>,
}

// ─── Tests ───────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    fn engine_with_low_threshold() -> ResilienceEngine {
        ResilienceEngine::with_config(ResilienceConfig {
            freeze_threshold: 3,
            error_window: Duration::from_secs(60),
            safe_mode_threshold: 5,
            throttle_interval: Duration::from_millis(100),
        })
    }

    #[test]
    fn test_error_recording() {
        let engine = engine_with_low_threshold();
        engine.record_error(1, "TypeError");
        engine.record_error(1, "NullError");

        assert_eq!(engine.stats.total(), 2);
        assert_eq!(engine.signal_error_count(1), 2);
    }

    #[test]
    fn test_auto_freeze_on_threshold() {
        let engine = engine_with_low_threshold();
        let signal_id: SignalId = 42;

        assert!(!engine.is_frozen(signal_id));
        engine.record_error(signal_id, "err");
        engine.record_error(signal_id, "err");
        assert!(!engine.is_frozen(signal_id));

        engine.record_error(signal_id, "err"); // hits threshold (3)
        assert!(engine.is_frozen(signal_id));
        assert!(!engine.is_write_allowed(signal_id));
    }

    #[test]
    fn test_unfreeze() {
        let engine = engine_with_low_threshold();
        engine.freeze_signal(1);
        assert!(engine.is_frozen(1));

        engine.unfreeze_signal(1);
        assert!(!engine.is_frozen(1));
        assert!(engine.is_write_allowed(1));
    }

    #[test]
    fn test_safe_mode_activation() {
        let engine = engine_with_low_threshold();

        // Not active initially
        assert!(!engine.is_safe_mode());

        // Record enough errors to trigger safe mode (threshold = 5/minute)
        for i in 0..5 {
            engine.record_error(100 + i, "err");
        }
        assert!(engine.is_safe_mode());

        engine.exit_safe_mode();
        assert!(!engine.is_safe_mode());
    }

    #[test]
    fn test_manual_safe_mode() {
        let engine = ResilienceEngine::new();
        engine.enter_safe_mode();
        assert!(engine.is_safe_mode());
        engine.exit_safe_mode();
        assert!(!engine.is_safe_mode());
    }

    #[test]
    fn test_summary() {
        let engine = engine_with_low_threshold();
        engine.record_error(1, "TypeError");
        engine.record_error(2, "NullError");
        engine.record_error(1, "TypeError");

        let summary = engine.summary();
        assert_eq!(summary.total_crashes, 3);
        assert_eq!(summary.error_types.get("TypeError"), Some(&2));
        assert_eq!(summary.error_types.get("NullError"), Some(&1));
    }

    #[test]
    fn test_crash_stats_frequency() {
        let stats = CrashStats::new();
        stats.record("err");
        stats.record("err");
        stats.record("err");
        // All within the last minute
        assert!(stats.frequency() >= 3.0);
    }
}
