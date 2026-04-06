//! AKVS IntelliState — Rust Core Engine
//!
//! High-performance runtime for signals, scheduling, resilience,
//! intelligence, and behavior tracking. Exposed to Dart via C ABI (FFI).

pub mod behavior;
pub mod ffi;
pub mod intelligence;
pub mod resilience;
pub mod scheduler;
pub mod signal;

use parking_lot::RwLock;
use std::sync::OnceLock;

use behavior::BehaviorTracker;
use intelligence::IntelligenceEngine;
use resilience::ResilienceEngine;
use scheduler::RustScheduler;
use signal::SignalRegistry;

/// The global runtime that owns all subsystems.
pub struct Runtime {
    pub signals: SignalRegistry,
    pub scheduler: RustScheduler,
    pub resilience: ResilienceEngine,
    pub intelligence: IntelligenceEngine,
    pub behavior: BehaviorTracker,
}

impl Runtime {
    /// Create a new runtime with all subsystems initialized.
    pub fn new() -> Self {
        Self {
            signals: SignalRegistry::new(),
            scheduler: RustScheduler::new(),
            resilience: ResilienceEngine::new(),
            intelligence: IntelligenceEngine::new(),
            behavior: BehaviorTracker::new(),
        }
    }
}

impl Default for Runtime {
    fn default() -> Self {
        Self::new()
    }
}

/// Global runtime singleton, lazily initialized.
static RUNTIME: OnceLock<RwLock<Runtime>> = OnceLock::new();

/// Get a reference to the global runtime.
/// Panics if `init_runtime()` has not been called.
pub fn runtime() -> &'static RwLock<Runtime> {
    RUNTIME
        .get()
        .expect("IntelliState runtime not initialized. Call intellistate_init() first.")
}

/// Initialize the global runtime. Safe to call multiple times (no-op after first).
pub fn init_runtime() {
    RUNTIME.get_or_init(|| RwLock::new(Runtime::new()));
}

/// Shutdown and reset the runtime (primarily for testing).
pub fn shutdown_runtime() {
    // OnceLock doesn't support reset in stable Rust, so we clear internal state instead.
    if let Some(rt) = RUNTIME.get() {
        let mut runtime = rt.write();
        runtime.signals = SignalRegistry::new();
        runtime.scheduler = RustScheduler::new();
        runtime.resilience = ResilienceEngine::new();
        runtime.intelligence = IntelligenceEngine::new();
        runtime.behavior = BehaviorTracker::new();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_runtime_init_is_idempotent() {
        init_runtime();
        // Should not panic — runtime is available
        let _rt = runtime().read();
        // Call again — should be a no-op
        init_runtime();
        let _rt2 = runtime().read();
    }

    #[test]
    fn test_runtime_shutdown_resets_state() {
        init_runtime();
        // Add a signal
        {
            let rt = runtime().read();
            rt.signals.create(crate::signal::SignalValue::Int(1), None);
        }
        // Shutdown clears all signals
        shutdown_runtime();
        let rt = runtime().read();
        assert_eq!(rt.signals.count(), 0);
    }
}
