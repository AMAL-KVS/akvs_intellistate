//! Rust Batch Scheduler — Priority-based update scheduling.
//!
//! Three-tier priority system:
//! 1. Computed updates (dependency resolution)
//! 2. Effect updates (side-effects)
//! 3. UI callbacks (widget rebuilds)
//!
//! Supports batching: during a batch, updates are queued and only
//! flushed when the batch completes.

use parking_lot::Mutex;
use std::collections::VecDeque;
use std::sync::atomic::{AtomicBool, Ordering};

use crate::signal::SignalId;

/// A scheduled update callback identifier.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct UpdateId {
    pub signal_id: SignalId,
    pub priority: UpdatePriority,
}

/// Priority levels for reactive updates.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
#[repr(i32)]
pub enum UpdatePriority {
    /// Computed values — must resolve first.
    Computed = 0,
    /// Side-effects — run after computed.
    Effect = 1,
    /// UI rebuilds — run last.
    Ui = 2,
}

/// Batch update scheduler with priority queues.
pub struct RustScheduler {
    /// Whether a batch is currently active.
    is_batching: AtomicBool,
    /// Priority 1: computed value recomputation.
    computed_queue: Mutex<VecDeque<SignalId>>,
    /// Priority 2: effect re-execution.
    effect_queue: Mutex<VecDeque<SignalId>>,
    /// Priority 3: UI rebuild notifications.
    ui_queue: Mutex<VecDeque<SignalId>>,
    /// Signals marked dirty during the current cycle.
    dirty_signals: Mutex<Vec<SignalId>>,
    /// Total flush count (for diagnostics).
    flush_count: Mutex<u64>,
}

impl std::fmt::Debug for RustScheduler {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("RustScheduler")
            .field("is_batching", &self.is_batching.load(Ordering::Relaxed))
            .field("flush_count", &*self.flush_count.lock())
            .finish()
    }
}

impl RustScheduler {
    pub fn new() -> Self {
        Self {
            is_batching: AtomicBool::new(false),
            computed_queue: Mutex::new(VecDeque::new()),
            effect_queue: Mutex::new(VecDeque::new()),
            ui_queue: Mutex::new(VecDeque::new()),
            dirty_signals: Mutex::new(Vec::new()),
            flush_count: Mutex::new(0),
        }
    }

    /// Begin a batch — updates will be queued until `batch_end()`.
    pub fn batch_begin(&self) {
        self.is_batching.store(true, Ordering::Release);
    }

    /// End a batch — flushes all queued updates.
    pub fn batch_end(&self) {
        self.is_batching.store(false, Ordering::Release);
        self.flush();
    }

    /// Whether a batch is currently active.
    pub fn is_batching(&self) -> bool {
        self.is_batching.load(Ordering::Acquire)
    }

    /// Mark a signal as dirty (needs update propagation).
    pub fn mark_dirty(&self, signal_id: SignalId) {
        self.dirty_signals.lock().push(signal_id);
        if !self.is_batching() {
            // Outside batch — auto-flush
            self.flush();
        }
    }

    /// Schedule a computed update.
    pub fn schedule_computed(&self, signal_id: SignalId) {
        let mut queue = self.computed_queue.lock();
        if !queue.contains(&signal_id) {
            queue.push_back(signal_id);
        }
        if !self.is_batching() {
            drop(queue);
            self.flush();
        }
    }

    /// Schedule an effect update.
    pub fn schedule_effect(&self, signal_id: SignalId) {
        let mut queue = self.effect_queue.lock();
        if !queue.contains(&signal_id) {
            queue.push_back(signal_id);
        }
        if !self.is_batching() {
            drop(queue);
            self.flush();
        }
    }

    /// Schedule a UI rebuild notification.
    pub fn schedule_ui(&self, signal_id: SignalId) {
        let mut queue = self.ui_queue.lock();
        if !queue.contains(&signal_id) {
            queue.push_back(signal_id);
        }
        if !self.is_batching() {
            drop(queue);
            self.flush();
        }
    }

    /// Flush all queues in priority order: computed → effects → UI.
    ///
    /// Returns the total number of updates processed.
    pub fn flush(&self) -> usize {
        let mut total = 0;

        // Priority 1: Computed
        loop {
            let batch: Vec<SignalId> = {
                let mut queue = self.computed_queue.lock();
                if queue.is_empty() {
                    break;
                }
                queue.drain(..).collect()
            };
            total += batch.len();
            // In the Rust core, we track which signals were flushed.
            // Actual recomputation is driven by the Dart side or FFI callbacks.
        }

        // Priority 2: Effects
        loop {
            let batch: Vec<SignalId> = {
                let mut queue = self.effect_queue.lock();
                if queue.is_empty() {
                    break;
                }
                queue.drain(..).collect()
            };
            total += batch.len();
        }

        // Priority 3: UI
        loop {
            let batch: Vec<SignalId> = {
                let mut queue = self.ui_queue.lock();
                if queue.is_empty() {
                    break;
                }
                queue.drain(..).collect()
            };
            total += batch.len();
        }

        // Clear dirty set
        self.dirty_signals.lock().clear();

        if total > 0 {
            *self.flush_count.lock() += 1;
        }

        total
    }

    /// Get the total number of flushes since initialization.
    pub fn total_flushes(&self) -> u64 {
        *self.flush_count.lock()
    }

    /// Get the total pending update count across all queues.
    pub fn pending_count(&self) -> usize {
        self.computed_queue.lock().len()
            + self.effect_queue.lock().len()
            + self.ui_queue.lock().len()
    }
}

impl Default for RustScheduler {
    fn default() -> Self {
        Self::new()
    }
}

// ─── Tests ───────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_batch_coalesces_updates() {
        let scheduler = RustScheduler::new();

        scheduler.batch_begin();
        assert!(scheduler.is_batching());

        scheduler.schedule_computed(1);
        scheduler.schedule_computed(2);
        scheduler.schedule_effect(1);
        scheduler.schedule_ui(1);

        // Nothing flushed yet
        assert_eq!(scheduler.pending_count(), 4);

        scheduler.batch_end();
        assert!(!scheduler.is_batching());
        assert_eq!(scheduler.pending_count(), 0);
        assert_eq!(scheduler.total_flushes(), 1);
    }

    #[test]
    fn test_auto_flush_outside_batch() {
        let scheduler = RustScheduler::new();

        scheduler.schedule_computed(1);
        // Auto-flushed immediately
        assert_eq!(scheduler.pending_count(), 0);
    }

    #[test]
    fn test_deduplication() {
        let scheduler = RustScheduler::new();

        scheduler.batch_begin();
        scheduler.schedule_computed(1);
        scheduler.schedule_computed(1); // duplicate
        scheduler.schedule_computed(1); // duplicate
        assert_eq!(scheduler.pending_count(), 1);
        scheduler.batch_end();
    }

    #[test]
    fn test_priority_order() {
        let scheduler = RustScheduler::new();

        scheduler.batch_begin();
        // Add in reverse priority order
        scheduler.schedule_ui(3);
        scheduler.schedule_effect(2);
        scheduler.schedule_computed(1);

        assert_eq!(scheduler.pending_count(), 3);
        let flushed = scheduler.flush();
        assert_eq!(flushed, 3);
        scheduler.batch_end();
    }

    #[test]
    fn test_mark_dirty() {
        let scheduler = RustScheduler::new();

        scheduler.batch_begin();
        scheduler.mark_dirty(1);
        scheduler.mark_dirty(2);
        // Dirty signals don't count as pending (they're separate tracking)
        scheduler.batch_end();
    }
}
