//! Intelligence Engine — Health scoring, predictive fallback, and degradation.
//!
//! Computes per-signal health scores (0.0–1.0) based on:
//! - Error rate (errors / total writes)
//! - Update staleness (time since last write)
//! - Crash penalty (recent crash count)
//!
//! Provides predictive fallback values using value history:
//! - Numeric → median of last N values
//! - String → last non-empty value
//! - Bytes → last non-empty buffer

use parking_lot::RwLock;
use std::collections::HashMap;
use std::time::{SystemTime, UNIX_EPOCH};

use crate::signal::{SignalId, SignalMetadata, SignalValue};

/// Degradation level of a signal based on its health score.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(i32)]
pub enum DegradationLevel {
    /// Health > 0.7 — operating normally.
    Normal = 0,
    /// Health 0.3–0.7 — performance degraded.
    Degraded = 1,
    /// Health < 0.3 — signal frozen, using fallback.
    Frozen = 2,
}

impl DegradationLevel {
    pub fn from_health(health: f64) -> Self {
        if health > 0.7 {
            Self::Normal
        } else if health > 0.3 {
            Self::Degraded
        } else {
            Self::Frozen
        }
    }

    pub fn as_i32(&self) -> i32 {
        *self as i32
    }

    pub fn from_i32(v: i32) -> Option<Self> {
        match v {
            0 => Some(Self::Normal),
            1 => Some(Self::Degraded),
            2 => Some(Self::Frozen),
            _ => None,
        }
    }
}

/// Health metrics for a single signal.
#[derive(Debug, Clone)]
pub struct HealthMetrics {
    /// Ratio of errors to total writes (0.0–1.0).
    pub error_rate: f64,
    /// Writes per second (rolling average).
    pub update_frequency: f64,
    /// Seconds since last write.
    pub staleness: f64,
    /// Total crash/error count.
    pub crash_count: u64,
    /// Computed health score (0.0–1.0).
    pub health_score: f64,
    /// Derived degradation level.
    pub degradation: DegradationLevel,
}

/// Intelligence engine — computes health and provides fallback values.
pub struct IntelligenceEngine {
    /// Cached health scores per signal.
    health_cache: RwLock<HashMap<SignalId, f64>>,
    /// Cached degradation levels per signal.
    degradation_cache: RwLock<HashMap<SignalId, DegradationLevel>>,
    /// Staleness threshold in seconds (signals older than this are penalized).
    staleness_threshold_secs: f64,
}

impl std::fmt::Debug for IntelligenceEngine {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("IntelligenceEngine")
            .field("tracked_signals", &self.health_cache.read().len())
            .finish()
    }
}

impl IntelligenceEngine {
    pub fn new() -> Self {
        Self {
            health_cache: RwLock::new(HashMap::new()),
            degradation_cache: RwLock::new(HashMap::new()),
            staleness_threshold_secs: 300.0, // 5 minutes
        }
    }

    /// Compute health score for a signal based on its metadata.
    ///
    /// Formula: `health = 1.0 - (0.4 * error_rate) - (0.3 * staleness_factor) - (0.3 * crash_penalty)`
    pub fn compute_health(&self, signal_id: SignalId, metadata: &SignalMetadata) -> HealthMetrics {
        // Error rate: errors / max(writes, 1)
        let total_ops = metadata.write_count.max(1) as f64;
        let error_rate = (metadata.error_count as f64 / total_ops).min(1.0);

        // Staleness: how old is the last write
        let now_ms = current_time_ms();
        let staleness_secs = (now_ms.saturating_sub(metadata.last_write_ms)) as f64 / 1000.0;
        let staleness_factor = (staleness_secs / self.staleness_threshold_secs).min(1.0);

        // Crash penalty: non-linear penalty for high error counts
        let crash_penalty = if metadata.error_count == 0 {
            0.0
        } else {
            (metadata.error_count as f64).ln().min(5.0) / 5.0
        };

        // Update frequency (writes per elapsed second)
        let elapsed_secs = metadata.created_at.elapsed().as_secs_f64().max(0.001);
        let update_frequency = metadata.write_count as f64 / elapsed_secs;

        // Weighted health score
        let health = (1.0 - (0.4 * error_rate) - (0.3 * staleness_factor) - (0.3 * crash_penalty))
            .clamp(0.0, 1.0);

        let degradation = DegradationLevel::from_health(health);

        // Cache results
        self.health_cache.write().insert(signal_id, health);
        self.degradation_cache
            .write()
            .insert(signal_id, degradation);

        HealthMetrics {
            error_rate,
            update_frequency,
            staleness: staleness_secs,
            crash_count: metadata.error_count,
            health_score: health,
            degradation,
        }
    }

    /// Get cached health score (without recomputing).
    pub fn cached_health(&self, signal_id: SignalId) -> Option<f64> {
        self.health_cache.read().get(&signal_id).copied()
    }

    /// Get cached degradation level.
    pub fn cached_degradation(&self, signal_id: SignalId) -> Option<DegradationLevel> {
        self.degradation_cache.read().get(&signal_id).copied()
    }

    /// Compute a predictive fallback value from signal history.
    ///
    /// Strategy:
    /// - Int → median of history values
    /// - Float → median of history values
    /// - String → last non-empty string
    /// - Bool → last value (no aggregation meaningful)
    /// - Bytes → last non-empty buffer
    pub fn predictive_fallback(history: &[SignalValue]) -> Option<SignalValue> {
        if history.is_empty() {
            return None;
        }

        match &history[0] {
            SignalValue::Int(_) => {
                let mut ints: Vec<i64> = history
                    .iter()
                    .filter_map(|v| {
                        if let SignalValue::Int(i) = v {
                            Some(*i)
                        } else {
                            None
                        }
                    })
                    .collect();
                if ints.is_empty() {
                    return None;
                }
                ints.sort();
                let median = ints[ints.len() / 2];
                Some(SignalValue::Int(median))
            }
            SignalValue::Float(_) => {
                let mut floats: Vec<f64> = history
                    .iter()
                    .filter_map(|v| {
                        if let SignalValue::Float(f) = v {
                            Some(*f)
                        } else {
                            None
                        }
                    })
                    .collect();
                if floats.is_empty() {
                    return None;
                }
                floats.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
                let median = floats[floats.len() / 2];
                Some(SignalValue::Float(median))
            }
            SignalValue::Str(_) => {
                // Last non-empty string
                history.iter().rev().find_map(|v| {
                    if let SignalValue::Str(s) = v {
                        if !s.is_empty() {
                            Some(SignalValue::Str(s.clone()))
                        } else {
                            None
                        }
                    } else {
                        None
                    }
                })
            }
            SignalValue::Bool(_) => {
                // Last value
                history.last().cloned()
            }
            SignalValue::Bytes(_) => {
                // Last non-empty buffer
                history.iter().rev().find_map(|v| {
                    if let SignalValue::Bytes(b) = v {
                        if !b.is_empty() {
                            Some(SignalValue::Bytes(b.clone()))
                        } else {
                            None
                        }
                    } else {
                        None
                    }
                })
            }
        }
    }

    /// Get all signals with their health scores and degradation levels.
    pub fn all_health_scores(&self) -> Vec<(SignalId, f64, DegradationLevel)> {
        let health = self.health_cache.read();
        let degradation = self.degradation_cache.read();
        health
            .iter()
            .map(|(id, score)| {
                let level = degradation
                    .get(id)
                    .copied()
                    .unwrap_or(DegradationLevel::Normal);
                (*id, *score, level)
            })
            .collect()
    }

    /// Get all degraded signal IDs (health < 0.7).
    pub fn degraded_signals(&self) -> Vec<SignalId> {
        self.degradation_cache
            .read()
            .iter()
            .filter(|(_, level)| **level != DegradationLevel::Normal)
            .map(|(id, _)| *id)
            .collect()
    }
}

impl Default for IntelligenceEngine {
    fn default() -> Self {
        Self::new()
    }
}

/// Get current time in milliseconds.
fn current_time_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64
}

// ─── Tests ───────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use crate::signal::SignalMetadata;

    fn make_metadata(writes: u64, errors: u64) -> SignalMetadata {
        let mut meta = SignalMetadata::new(Some("test".to_string()));
        meta.write_count = writes;
        meta.error_count = errors;
        meta.last_write_ms = current_time_ms(); // fresh write
        meta
    }

    #[test]
    fn test_healthy_signal() {
        let engine = IntelligenceEngine::new();
        let meta = make_metadata(100, 0);
        let health = engine.compute_health(1, &meta);

        assert!(health.health_score > 0.6, "Score: {}", health.health_score);
        assert_eq!(health.degradation, DegradationLevel::Normal);
    }

    #[test]
    fn test_degraded_signal() {
        let engine = IntelligenceEngine::new();
        let meta = make_metadata(10, 8); // 80% error rate → clearly degraded
        let health = engine.compute_health(1, &meta);

        assert!(health.health_score < 0.7, "Score: {}", health.health_score);
        assert!(health.degradation != DegradationLevel::Normal);
    }

    #[test]
    fn test_frozen_signal() {
        let engine = IntelligenceEngine::new();
        let meta = make_metadata(1, 500); // extreme error rate → clearly frozen
        let health = engine.compute_health(1, &meta);

        assert!(health.health_score <= 0.3, "Score: {}", health.health_score);
        assert_eq!(health.degradation, DegradationLevel::Frozen);
    }

    #[test]
    fn test_predictive_fallback_int_median() {
        let history = vec![
            SignalValue::Int(10),
            SignalValue::Int(20),
            SignalValue::Int(5),
            SignalValue::Int(15),
            SignalValue::Int(25),
        ];
        let fallback = IntelligenceEngine::predictive_fallback(&history);
        assert_eq!(fallback, Some(SignalValue::Int(15))); // median
    }

    #[test]
    fn test_predictive_fallback_float_median() {
        let history = vec![
            SignalValue::Float(1.0),
            SignalValue::Float(3.0),
            SignalValue::Float(2.0),
        ];
        let fallback = IntelligenceEngine::predictive_fallback(&history);
        assert_eq!(fallback, Some(SignalValue::Float(2.0)));
    }

    #[test]
    fn test_predictive_fallback_string_last_valid() {
        let history = vec![
            SignalValue::Str("hello".into()),
            SignalValue::Str("".into()),
            SignalValue::Str("world".into()),
            SignalValue::Str("".into()),
        ];
        let fallback = IntelligenceEngine::predictive_fallback(&history);
        assert_eq!(fallback, Some(SignalValue::Str("world".into())));
    }

    #[test]
    fn test_predictive_fallback_bytes_last_nonempty() {
        let history = vec![
            SignalValue::Bytes(vec![1, 2]),
            SignalValue::Bytes(vec![]),
            SignalValue::Bytes(vec![3, 4, 5]),
            SignalValue::Bytes(vec![]),
        ];
        let fallback = IntelligenceEngine::predictive_fallback(&history);
        assert_eq!(fallback, Some(SignalValue::Bytes(vec![3, 4, 5])));
    }

    #[test]
    fn test_predictive_fallback_empty_history() {
        let fallback = IntelligenceEngine::predictive_fallback(&[]);
        assert_eq!(fallback, None);
    }

    #[test]
    fn test_degradation_levels() {
        assert_eq!(DegradationLevel::from_health(0.9), DegradationLevel::Normal);
        assert_eq!(
            DegradationLevel::from_health(0.5),
            DegradationLevel::Degraded
        );
        assert_eq!(DegradationLevel::from_health(0.2), DegradationLevel::Frozen);
    }

    #[test]
    fn test_cached_scores() {
        let engine = IntelligenceEngine::new();
        let meta = make_metadata(100, 0);
        engine.compute_health(42, &meta);

        assert!(engine.cached_health(42).is_some());
        assert_eq!(
            engine.cached_degradation(42),
            Some(DegradationLevel::Normal)
        );
        assert!(engine.cached_health(999).is_none());
    }
}
