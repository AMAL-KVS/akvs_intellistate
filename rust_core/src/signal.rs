//! Rust Signal Engine — Thread-safe reactive value containers.
//!
//! Each signal stores a dynamic value (via `SignalValue` enum), tracks
//! metadata (write count, timestamps, value history), and maintains
//! a list of listener IDs for the scheduler to notify.

use parking_lot::RwLock;
use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{Instant, SystemTime, UNIX_EPOCH};

/// Unique identifier for a signal instance.
pub type SignalId = u64;

/// Unique identifier for a listener/subscriber.
pub type ListenerId = u64;

/// Type discriminant for signal values (matches Dart serialization).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(i32)]
pub enum SignalValueType {
    Int = 0,
    Float = 1,
    Str = 2,
    Bool = 3,
    Bytes = 4,
}

impl SignalValueType {
    pub fn from_i32(v: i32) -> Option<Self> {
        match v {
            0 => Some(Self::Int),
            1 => Some(Self::Float),
            2 => Some(Self::Str),
            3 => Some(Self::Bool),
            4 => Some(Self::Bytes),
            _ => None,
        }
    }
}

/// Dynamic value stored inside a signal.
#[derive(Debug, Clone, PartialEq)]
pub enum SignalValue {
    Int(i64),
    Float(f64),
    Str(String),
    Bool(bool),
    Bytes(Vec<u8>),
}

impl SignalValue {
    /// Returns the type discriminant.
    pub fn value_type(&self) -> SignalValueType {
        match self {
            Self::Int(_) => SignalValueType::Int,
            Self::Float(_) => SignalValueType::Float,
            Self::Str(_) => SignalValueType::Str,
            Self::Bool(_) => SignalValueType::Bool,
            Self::Bytes(_) => SignalValueType::Bytes,
        }
    }
}

/// Metadata tracked per signal for intelligence and behavior.
#[derive(Debug, Clone)]
pub struct SignalMetadata {
    /// Optional human-readable name.
    pub name: Option<String>,
    /// When the signal was created.
    pub created_at: Instant,
    /// Total number of writes.
    pub write_count: u64,
    /// Timestamp of the last write (millis since epoch).
    pub last_write_ms: u64,
    /// Total number of read accesses.
    pub read_count: u64,
    /// Total number of errors recorded against this signal.
    pub error_count: u64,
    /// Ring buffer of last N values for predictive fallback.
    pub value_history: Vec<SignalValue>,
    /// Maximum history size.
    pub max_history: usize,
}

impl SignalMetadata {
    pub fn new(name: Option<String>) -> Self {
        Self {
            name,
            created_at: Instant::now(),
            write_count: 0,
            last_write_ms: current_time_ms(),
            read_count: 0,
            error_count: 0,
            value_history: Vec::with_capacity(5),
            max_history: 5,
        }
    }

    /// Push a value into the history ring buffer.
    pub fn push_history(&mut self, value: SignalValue) {
        if self.value_history.len() >= self.max_history {
            self.value_history.remove(0);
        }
        self.value_history.push(value);
    }
}

/// A single signal instance in the registry.
#[derive(Debug)]
pub struct RustSignal {
    pub id: SignalId,
    pub value: SignalValue,
    pub metadata: SignalMetadata,
    /// IDs of listeners subscribed to this signal.
    pub listeners: Vec<ListenerId>,
    /// Whether updates to this signal are frozen (safe mode).
    pub frozen: bool,
}

impl RustSignal {
    pub fn new(id: SignalId, initial_value: SignalValue, name: Option<String>) -> Self {
        let mut metadata = SignalMetadata::new(name);
        metadata.push_history(initial_value.clone());
        Self {
            id,
            value: initial_value,
            metadata,
            listeners: Vec::new(),
            frozen: false,
        }
    }

    /// Set a new value. Returns `true` if the value actually changed.
    pub fn set_value(&mut self, new_value: SignalValue) -> bool {
        if self.frozen {
            return false;
        }
        if self.value == new_value {
            return false;
        }
        self.metadata.push_history(new_value.clone());
        self.metadata.write_count += 1;
        self.metadata.last_write_ms = current_time_ms();
        self.value = new_value;
        true
    }

    /// Record a read access.
    pub fn record_read(&mut self) {
        self.metadata.read_count += 1;
    }

    /// Record an error against this signal.
    pub fn record_error(&mut self) {
        self.metadata.error_count += 1;
    }

    /// Add a listener ID.
    pub fn add_listener(&mut self, listener_id: ListenerId) {
        if !self.listeners.contains(&listener_id) {
            self.listeners.push(listener_id);
        }
    }

    /// Remove a listener ID.
    pub fn remove_listener(&mut self, listener_id: ListenerId) {
        self.listeners.retain(|id| *id != listener_id);
    }
}

/// Central registry that owns all signal instances.
pub struct SignalRegistry {
    signals: RwLock<HashMap<SignalId, RustSignal>>,
    next_id: AtomicU64,
    next_listener_id: AtomicU64,
}

impl std::fmt::Debug for SignalRegistry {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("SignalRegistry")
            .field("count", &self.count())
            .finish()
    }
}

impl SignalRegistry {
    pub fn new() -> Self {
        Self {
            signals: RwLock::new(HashMap::new()),
            next_id: AtomicU64::new(1),
            next_listener_id: AtomicU64::new(1),
        }
    }

    /// Create a new signal and return its ID.
    pub fn create(&self, initial_value: SignalValue, name: Option<String>) -> SignalId {
        let id = self.next_id.fetch_add(1, Ordering::Relaxed);
        let signal = RustSignal::new(id, initial_value, name);
        self.signals.write().insert(id, signal);
        id
    }

    /// Get the current value of a signal.
    pub fn get_value(&self, id: SignalId) -> Option<SignalValue> {
        let mut signals = self.signals.write();
        if let Some(signal) = signals.get_mut(&id) {
            signal.record_read();
            Some(signal.value.clone())
        } else {
            None
        }
    }

    /// Set the value of a signal. Returns `true` if the value changed.
    pub fn set_value(&self, id: SignalId, new_value: SignalValue) -> Option<bool> {
        let mut signals = self.signals.write();
        signals
            .get_mut(&id)
            .map(|signal| signal.set_value(new_value))
    }

    /// Get a clone of a signal's metadata.
    pub fn get_metadata(&self, id: SignalId) -> Option<SignalMetadata> {
        self.signals.read().get(&id).map(|s| s.metadata.clone())
    }

    /// Get listener IDs for a signal.
    pub fn get_listeners(&self, id: SignalId) -> Vec<ListenerId> {
        self.signals
            .read()
            .get(&id)
            .map(|s| s.listeners.clone())
            .unwrap_or_default()
    }

    /// Subscribe a new listener to a signal. Returns the listener ID.
    pub fn subscribe(&self, signal_id: SignalId) -> Option<ListenerId> {
        let listener_id = self.next_listener_id.fetch_add(1, Ordering::Relaxed);
        let mut signals = self.signals.write();
        if let Some(signal) = signals.get_mut(&signal_id) {
            signal.add_listener(listener_id);
            Some(listener_id)
        } else {
            None
        }
    }

    /// Unsubscribe a listener from a signal.
    pub fn unsubscribe(&self, signal_id: SignalId, listener_id: ListenerId) {
        if let Some(signal) = self.signals.write().get_mut(&signal_id) {
            signal.remove_listener(listener_id);
        }
    }

    /// Record an error against a signal.
    pub fn record_error(&self, id: SignalId) {
        if let Some(signal) = self.signals.write().get_mut(&id) {
            signal.record_error();
        }
    }

    /// Freeze a signal (prevent writes).
    pub fn freeze(&self, id: SignalId) {
        if let Some(signal) = self.signals.write().get_mut(&id) {
            signal.frozen = true;
        }
    }

    /// Unfreeze a signal.
    pub fn unfreeze(&self, id: SignalId) {
        if let Some(signal) = self.signals.write().get_mut(&id) {
            signal.frozen = false;
        }
    }

    /// Check if a signal is frozen.
    pub fn is_frozen(&self, id: SignalId) -> bool {
        self.signals
            .read()
            .get(&id)
            .map(|s| s.frozen)
            .unwrap_or(false)
    }

    /// Dispose of a signal, removing it from the registry.
    pub fn dispose(&self, id: SignalId) -> bool {
        self.signals.write().remove(&id).is_some()
    }

    /// Get the total number of signals in the registry.
    pub fn count(&self) -> usize {
        self.signals.read().len()
    }

    /// Get the value history for predictive fallback.
    pub fn get_value_history(&self, id: SignalId) -> Vec<SignalValue> {
        self.signals
            .read()
            .get(&id)
            .map(|s| s.metadata.value_history.clone())
            .unwrap_or_default()
    }

    /// Get all signal IDs and their names (for DevTools).
    pub fn all_signal_info(&self) -> Vec<(SignalId, Option<String>, bool)> {
        self.signals
            .read()
            .values()
            .map(|s| (s.id, s.metadata.name.clone(), s.frozen))
            .collect()
    }
}

impl Default for SignalRegistry {
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
    fn test_create_and_read_signal() {
        let registry = SignalRegistry::new();
        let id = registry.create(SignalValue::Int(42), Some("counter".to_string()));
        assert_eq!(registry.get_value(id), Some(SignalValue::Int(42)));
    }

    #[test]
    fn test_set_value_equality_guard() {
        let registry = SignalRegistry::new();
        let id = registry.create(SignalValue::Int(10), None);

        // Same value → no change
        assert_eq!(registry.set_value(id, SignalValue::Int(10)), Some(false));

        // Different value → change
        assert_eq!(registry.set_value(id, SignalValue::Int(20)), Some(true));
        assert_eq!(registry.get_value(id), Some(SignalValue::Int(20)));
    }

    #[test]
    fn test_dispose_signal() {
        let registry = SignalRegistry::new();
        let id = registry.create(SignalValue::Str("hello".to_string()), None);
        assert_eq!(registry.count(), 1);

        assert!(registry.dispose(id));
        assert_eq!(registry.count(), 0);
        assert_eq!(registry.get_value(id), None);
    }

    #[test]
    fn test_subscribe_and_listeners() {
        let registry = SignalRegistry::new();
        let id = registry.create(SignalValue::Bool(true), None);

        let l1 = registry.subscribe(id).unwrap();
        let l2 = registry.subscribe(id).unwrap();
        assert_ne!(l1, l2);

        let listeners = registry.get_listeners(id);
        assert_eq!(listeners.len(), 2);

        registry.unsubscribe(id, l1);
        let listeners = registry.get_listeners(id);
        assert_eq!(listeners.len(), 1);
    }

    #[test]
    fn test_freeze_prevents_writes() {
        let registry = SignalRegistry::new();
        let id = registry.create(SignalValue::Int(1), None);

        registry.freeze(id);
        assert!(registry.is_frozen(id));
        assert_eq!(registry.set_value(id, SignalValue::Int(2)), Some(false));
        assert_eq!(registry.get_value(id), Some(SignalValue::Int(1))); // unchanged

        registry.unfreeze(id);
        assert_eq!(registry.set_value(id, SignalValue::Int(2)), Some(true));
    }

    #[test]
    fn test_value_history() {
        let registry = SignalRegistry::new();
        let id = registry.create(SignalValue::Int(1), None);

        registry.set_value(id, SignalValue::Int(2));
        registry.set_value(id, SignalValue::Int(3));

        let history = registry.get_value_history(id);
        assert_eq!(history.len(), 3);
        assert_eq!(history[0], SignalValue::Int(1));
        assert_eq!(history[2], SignalValue::Int(3));
    }

    #[test]
    fn test_metadata_tracking() {
        let registry = SignalRegistry::new();
        let id = registry.create(SignalValue::Float(3.14), Some("pi".to_string()));

        registry.set_value(id, SignalValue::Float(3.15));
        registry.get_value(id);
        registry.get_value(id);

        let meta = registry.get_metadata(id).unwrap();
        assert_eq!(meta.name, Some("pi".to_string()));
        assert_eq!(meta.write_count, 1);
        assert_eq!(meta.read_count, 2);
    }

    #[test]
    fn test_signal_value_types() {
        let registry = SignalRegistry::new();

        let id1 = registry.create(SignalValue::Int(42), None);
        let id2 = registry.create(SignalValue::Float(3.14), None);
        let id3 = registry.create(SignalValue::Str("hello".into()), None);
        let id4 = registry.create(SignalValue::Bool(true), None);
        let id5 = registry.create(SignalValue::Bytes(vec![1, 2, 3]), None);

        assert_eq!(
            registry.get_value(id1).unwrap().value_type(),
            SignalValueType::Int
        );
        assert_eq!(
            registry.get_value(id2).unwrap().value_type(),
            SignalValueType::Float
        );
        assert_eq!(
            registry.get_value(id3).unwrap().value_type(),
            SignalValueType::Str
        );
        assert_eq!(
            registry.get_value(id4).unwrap().value_type(),
            SignalValueType::Bool
        );
        assert_eq!(
            registry.get_value(id5).unwrap().value_type(),
            SignalValueType::Bytes
        );
    }
}
