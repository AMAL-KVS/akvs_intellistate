//! Behavior Hooks — Lightweight event tracking for the Dart layer.
//!
//! Records signal read/write/error events in a ring buffer.
//! The Dart layer periodically drains this buffer for analytics integration.
//! Designed for zero-allocation in the hot path (pre-allocated buffer).

use parking_lot::Mutex;
use std::collections::VecDeque;
use std::time::{SystemTime, UNIX_EPOCH};

use crate::signal::SignalId;

/// Type of behavior event.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(i32)]
pub enum EventType {
    /// Signal value was written.
    Write = 0,
    /// Signal value was read.
    Read = 1,
    /// An error occurred on this signal.
    Error = 2,
    /// Signal was frozen (safe mode).
    Freeze = 3,
    /// Signal was unfrozen.
    Unfreeze = 4,
    /// Signal was disposed.
    Dispose = 5,
}

impl EventType {
    pub fn from_i32(v: i32) -> Option<Self> {
        match v {
            0 => Some(Self::Write),
            1 => Some(Self::Read),
            2 => Some(Self::Error),
            3 => Some(Self::Freeze),
            4 => Some(Self::Unfreeze),
            5 => Some(Self::Dispose),
            _ => None,
        }
    }
}

/// A lightweight behavior event record.
#[derive(Debug, Clone)]
#[repr(C)]
pub struct BehaviorEvent {
    /// The signal that generated this event.
    pub signal_id: u64,
    /// Type of event.
    pub event_type: i32,
    /// Timestamp in milliseconds since Unix epoch.
    pub timestamp_ms: u64,
}

impl BehaviorEvent {
    pub fn new(signal_id: SignalId, event_type: EventType) -> Self {
        Self {
            signal_id,
            event_type: event_type as i32,
            timestamp_ms: current_time_ms(),
        }
    }
}

/// Ring-buffer event tracker for behavior analytics.
pub struct BehaviorTracker {
    /// Pre-allocated ring buffer of events.
    event_buffer: Mutex<VecDeque<BehaviorEvent>>,
    /// Maximum buffer capacity.
    max_capacity: usize,
    /// Total events recorded (including evicted ones).
    total_events: Mutex<u64>,
}

impl std::fmt::Debug for BehaviorTracker {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("BehaviorTracker")
            .field("buffered", &self.event_buffer.lock().len())
            .field("total", &*self.total_events.lock())
            .finish()
    }
}

impl BehaviorTracker {
    pub fn new() -> Self {
        Self::with_capacity(1000)
    }

    pub fn with_capacity(max_capacity: usize) -> Self {
        Self {
            event_buffer: Mutex::new(VecDeque::with_capacity(max_capacity)),
            max_capacity,
            total_events: Mutex::new(0),
        }
    }

    /// Record a write event for a signal.
    pub fn record_write(&self, signal_id: SignalId) {
        self.push_event(BehaviorEvent::new(signal_id, EventType::Write));
    }

    /// Record a read event for a signal.
    pub fn record_read(&self, signal_id: SignalId) {
        self.push_event(BehaviorEvent::new(signal_id, EventType::Read));
    }

    /// Record an error event for a signal.
    pub fn record_error(&self, signal_id: SignalId) {
        self.push_event(BehaviorEvent::new(signal_id, EventType::Error));
    }

    /// Record a freeze event for a signal.
    pub fn record_freeze(&self, signal_id: SignalId) {
        self.push_event(BehaviorEvent::new(signal_id, EventType::Freeze));
    }

    /// Record an unfreeze event for a signal.
    pub fn record_unfreeze(&self, signal_id: SignalId) {
        self.push_event(BehaviorEvent::new(signal_id, EventType::Unfreeze));
    }

    /// Record a dispose event for a signal.
    pub fn record_dispose(&self, signal_id: SignalId) {
        self.push_event(BehaviorEvent::new(signal_id, EventType::Dispose));
    }

    /// Push an event into the ring buffer.
    fn push_event(&self, event: BehaviorEvent) {
        let mut buffer = self.event_buffer.lock();
        if buffer.len() >= self.max_capacity {
            buffer.pop_front(); // Evict oldest
        }
        buffer.push_back(event);
        *self.total_events.lock() += 1;
    }

    /// Drain all events from the buffer (Dart calls this periodically).
    /// Returns the events in chronological order.
    pub fn drain_events(&self) -> Vec<BehaviorEvent> {
        self.event_buffer.lock().drain(..).collect()
    }

    /// Drain up to `max` events from the buffer.
    pub fn drain_events_max(&self, max: usize) -> Vec<BehaviorEvent> {
        let mut buffer = self.event_buffer.lock();
        let count = buffer.len().min(max);
        buffer.drain(..count).collect()
    }

    /// Get the current number of buffered events.
    pub fn buffered_count(&self) -> usize {
        self.event_buffer.lock().len()
    }

    /// Get the total number of events recorded since initialization.
    pub fn total_events(&self) -> u64 {
        *self.total_events.lock()
    }

    /// Get write count for a specific signal from the current buffer.
    pub fn write_count_for(&self, signal_id: SignalId) -> usize {
        self.event_buffer
            .lock()
            .iter()
            .filter(|e| e.signal_id == signal_id && e.event_type == EventType::Write as i32)
            .count()
    }
}

impl Default for BehaviorTracker {
    fn default() -> Self {
        Self::new()
    }
}

/// Get current time in milliseconds since Unix epoch.
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

    #[test]
    fn test_record_and_drain() {
        let tracker = BehaviorTracker::new();

        tracker.record_write(1);
        tracker.record_read(1);
        tracker.record_error(2);

        assert_eq!(tracker.buffered_count(), 3);
        assert_eq!(tracker.total_events(), 3);

        let events = tracker.drain_events();
        assert_eq!(events.len(), 3);
        assert_eq!(events[0].event_type, EventType::Write as i32);
        assert_eq!(events[1].event_type, EventType::Read as i32);
        assert_eq!(events[2].signal_id, 2);

        // Buffer should be empty after drain
        assert_eq!(tracker.buffered_count(), 0);
    }

    #[test]
    fn test_ring_buffer_eviction() {
        let tracker = BehaviorTracker::with_capacity(3);

        tracker.record_write(1);
        tracker.record_write(2);
        tracker.record_write(3);
        tracker.record_write(4); // evicts event for signal 1

        assert_eq!(tracker.buffered_count(), 3);

        let events = tracker.drain_events();
        assert_eq!(events[0].signal_id, 2); // signal 1 was evicted
        assert_eq!(events[2].signal_id, 4);
        assert_eq!(tracker.total_events(), 4); // total still counts all
    }

    #[test]
    fn test_drain_max() {
        let tracker = BehaviorTracker::new();
        for i in 0..10 {
            tracker.record_write(i);
        }

        let batch = tracker.drain_events_max(5);
        assert_eq!(batch.len(), 5);
        assert_eq!(tracker.buffered_count(), 5);
    }

    #[test]
    fn test_write_count_for_signal() {
        let tracker = BehaviorTracker::new();
        tracker.record_write(1);
        tracker.record_write(1);
        tracker.record_read(1);
        tracker.record_write(2);

        assert_eq!(tracker.write_count_for(1), 2);
        assert_eq!(tracker.write_count_for(2), 1);
        assert_eq!(tracker.write_count_for(3), 0);
    }

    #[test]
    fn test_all_event_types() {
        let tracker = BehaviorTracker::new();
        tracker.record_write(1);
        tracker.record_read(1);
        tracker.record_error(1);
        tracker.record_freeze(1);
        tracker.record_unfreeze(1);
        tracker.record_dispose(1);

        let events = tracker.drain_events();
        assert_eq!(events.len(), 6);
        assert_eq!(events[0].event_type, EventType::Write as i32);
        assert_eq!(events[1].event_type, EventType::Read as i32);
        assert_eq!(events[2].event_type, EventType::Error as i32);
        assert_eq!(events[3].event_type, EventType::Freeze as i32);
        assert_eq!(events[4].event_type, EventType::Unfreeze as i32);
        assert_eq!(events[5].event_type, EventType::Dispose as i32);
    }
}
