//! FFI Layer — C ABI exports for Dart interop via `dart:ffi`.
//!
//! All functions are `#[no_mangle] extern "C"` and use only C-compatible types:
//! - `u64` for signal IDs
//! - `i64`, `f64` for numeric values
//! - `*const c_char` / `*mut c_char` for strings
//! - `i32` for error codes and enums
//!
use std::ffi::{c_char, CStr, CString};

use crate::signal::SignalValue;
use crate::{init_runtime, runtime, shutdown_runtime};

// ═══════════════════════════════════════════════════════════════════════
//  LIFECYCLE
// ═══════════════════════════════════════════════════════════════════════

/// Initialize the IntelliState runtime. Must be called before any other function.
/// Safe to call multiple times (no-op after first).
#[no_mangle]
pub extern "C" fn intellistate_init() {
    init_runtime();
}

/// Shutdown the runtime and release all resources.
#[no_mangle]
pub extern "C" fn intellistate_shutdown() {
    shutdown_runtime();
}

// ═══════════════════════════════════════════════════════════════════════
//  SIGNAL LIFECYCLE
// ═══════════════════════════════════════════════════════════════════════

/// Create an integer signal. Returns the signal ID.
#[no_mangle]
pub extern "C" fn intellistate_create_int(value: i64, name: *const c_char) -> u64 {
    let rt = runtime().read();
    let name = unsafe_str(name);
    rt.signals.create(SignalValue::Int(value), name)
}

/// Create a float signal. Returns the signal ID.
#[no_mangle]
pub extern "C" fn intellistate_create_float(value: f64, name: *const c_char) -> u64 {
    let rt = runtime().read();
    let name = unsafe_str(name);
    rt.signals.create(SignalValue::Float(value), name)
}

/// Create a string signal. Returns the signal ID.
#[no_mangle]
pub extern "C" fn intellistate_create_string(value: *const c_char, name: *const c_char) -> u64 {
    let rt = runtime().read();
    let val = unsafe_str(value).unwrap_or_default();
    let name = unsafe_str(name);
    rt.signals.create(SignalValue::Str(val), name)
}

/// Create a boolean signal. Returns the signal ID. `value`: 0 = false, 1 = true.
#[no_mangle]
pub extern "C" fn intellistate_create_bool(value: i32, name: *const c_char) -> u64 {
    let rt = runtime().read();
    let name = unsafe_str(name);
    rt.signals.create(SignalValue::Bool(value != 0), name)
}

/// Dispose of a signal. Returns 0 on success, -1 if not found.
#[no_mangle]
pub extern "C" fn intellistate_dispose(id: u64) -> i32 {
    let rt = runtime().read();
    rt.behavior.record_dispose(id);
    if rt.signals.dispose(id) {
        0
    } else {
        -1
    }
}

// ═══════════════════════════════════════════════════════════════════════
//  GETTERS
// ═══════════════════════════════════════════════════════════════════════

/// Get the value type of a signal. Returns -1 if not found.
#[no_mangle]
pub extern "C" fn intellistate_get_type(id: u64) -> i32 {
    let rt = runtime().read();
    match rt.signals.get_value(id) {
        Some(v) => v.value_type() as i32,
        None => -1,
    }
}

/// Get integer value. Returns 0 if not found or wrong type.
#[no_mangle]
pub extern "C" fn intellistate_get_int(id: u64) -> i64 {
    let rt = runtime().read();
    rt.behavior.record_read(id);
    match rt.signals.get_value(id) {
        Some(SignalValue::Int(v)) => v,
        _ => 0,
    }
}

/// Get float value.
#[no_mangle]
pub extern "C" fn intellistate_get_float(id: u64) -> f64 {
    let rt = runtime().read();
    rt.behavior.record_read(id);
    match rt.signals.get_value(id) {
        Some(SignalValue::Float(v)) => v,
        _ => 0.0,
    }
}

/// Get string value. Caller must free with `intellistate_free_string`.
/// Returns null pointer if not found.
#[no_mangle]
pub extern "C" fn intellistate_get_string(id: u64) -> *mut c_char {
    let rt = runtime().read();
    rt.behavior.record_read(id);
    match rt.signals.get_value(id) {
        Some(SignalValue::Str(s)) => CString::new(s)
            .map(|c| c.into_raw())
            .unwrap_or(std::ptr::null_mut()),
        _ => std::ptr::null_mut(),
    }
}

/// Get boolean value. Returns 0 (false) if not found.
#[no_mangle]
pub extern "C" fn intellistate_get_bool(id: u64) -> i32 {
    let rt = runtime().read();
    rt.behavior.record_read(id);
    match rt.signals.get_value(id) {
        Some(SignalValue::Bool(v)) => {
            if v {
                1
            } else {
                0
            }
        }
        _ => 0,
    }
}

/// Free a string returned by `intellistate_get_string`.
#[no_mangle]
pub extern "C" fn intellistate_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            let _ = CString::from_raw(ptr);
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════
//  SETTERS
// ═══════════════════════════════════════════════════════════════════════

/// Set integer value. Returns 0 if unchanged, 1 if changed, -1 if not found.
#[no_mangle]
pub extern "C" fn intellistate_set_int(id: u64, value: i64) -> i32 {
    let rt = runtime().read();
    if !rt.resilience.is_write_allowed(id) {
        return -2;
    }
    match rt.signals.set_value(id, SignalValue::Int(value)) {
        Some(true) => {
            rt.behavior.record_write(id);
            rt.scheduler.mark_dirty(id);
            1
        }
        Some(false) => 0,
        None => -1,
    }
}

/// Set float value.
#[no_mangle]
pub extern "C" fn intellistate_set_float(id: u64, value: f64) -> i32 {
    let rt = runtime().read();
    if !rt.resilience.is_write_allowed(id) {
        return -2;
    }
    match rt.signals.set_value(id, SignalValue::Float(value)) {
        Some(true) => {
            rt.behavior.record_write(id);
            rt.scheduler.mark_dirty(id);
            1
        }
        Some(false) => 0,
        None => -1,
    }
}

/// Set string value.
#[no_mangle]
pub extern "C" fn intellistate_set_string(id: u64, value: *const c_char) -> i32 {
    let rt = runtime().read();
    if !rt.resilience.is_write_allowed(id) {
        return -2;
    }
    let val = unsafe_str(value).unwrap_or_default();
    match rt.signals.set_value(id, SignalValue::Str(val)) {
        Some(true) => {
            rt.behavior.record_write(id);
            rt.scheduler.mark_dirty(id);
            1
        }
        Some(false) => 0,
        None => -1,
    }
}

/// Set boolean value. `value`: 0 = false, 1 = true.
#[no_mangle]
pub extern "C" fn intellistate_set_bool(id: u64, value: i32) -> i32 {
    let rt = runtime().read();
    if !rt.resilience.is_write_allowed(id) {
        return -2;
    }
    match rt.signals.set_value(id, SignalValue::Bool(value != 0)) {
        Some(true) => {
            rt.behavior.record_write(id);
            rt.scheduler.mark_dirty(id);
            1
        }
        Some(false) => 0,
        None => -1,
    }
}

// ═══════════════════════════════════════════════════════════════════════
//  SUBSCRIPTIONS
// ═══════════════════════════════════════════════════════════════════════

/// Subscribe to a signal. Returns the listener ID, or 0 on failure.
#[no_mangle]
pub extern "C" fn intellistate_subscribe(signal_id: u64) -> u64 {
    let rt = runtime().read();
    rt.signals.subscribe(signal_id).unwrap_or(0)
}

/// Unsubscribe a listener from a signal.
#[no_mangle]
pub extern "C" fn intellistate_unsubscribe(signal_id: u64, listener_id: u64) {
    let rt = runtime().read();
    rt.signals.unsubscribe(signal_id, listener_id);
}

// ═══════════════════════════════════════════════════════════════════════
//  SCHEDULER
// ═══════════════════════════════════════════════════════════════════════

/// Begin a batch — updates are queued until `intellistate_batch_end`.
#[no_mangle]
pub extern "C" fn intellistate_batch_begin() {
    let rt = runtime().read();
    rt.scheduler.batch_begin();
}

/// End a batch — flushes all queued updates.
#[no_mangle]
pub extern "C" fn intellistate_batch_end() {
    let rt = runtime().read();
    rt.scheduler.batch_end();
}

/// Manually flush all pending updates.
#[no_mangle]
pub extern "C" fn intellistate_flush() -> i32 {
    let rt = runtime().read();
    rt.scheduler.flush() as i32
}

// ═══════════════════════════════════════════════════════════════════════
//  INTELLIGENCE
// ═══════════════════════════════════════════════════════════════════════

/// Get the health score of a signal (0.0–1.0). Returns -1.0 if not found.
#[no_mangle]
pub extern "C" fn intellistate_health_score(id: u64) -> f64 {
    let rt = runtime().read();
    match rt.signals.get_metadata(id) {
        Some(meta) => {
            let metrics = rt.intelligence.compute_health(id, &meta);
            metrics.health_score
        }
        None => -1.0,
    }
}

/// Get the degradation level of a signal. Returns -1 if not found.
/// 0 = Normal, 1 = Degraded, 2 = Frozen.
#[no_mangle]
pub extern "C" fn intellistate_degradation_level(id: u64) -> i32 {
    let rt = runtime().read();
    match rt.signals.get_metadata(id) {
        Some(meta) => {
            let metrics = rt.intelligence.compute_health(id, &meta);
            metrics.degradation.as_i32()
        }
        None => -1,
    }
}

// ═══════════════════════════════════════════════════════════════════════
//  RESILIENCE
// ═══════════════════════════════════════════════════════════════════════

/// Record an error for a signal. May trigger auto-freeze or safe mode.
#[no_mangle]
pub extern "C" fn intellistate_record_error(id: u64, error_type: *const c_char) {
    let rt = runtime().read();
    let err = unsafe_str(error_type).unwrap_or_else(|| "unknown".to_string());
    rt.signals.record_error(id);
    rt.resilience.record_error(id, &err);
    rt.behavior.record_error(id);
}

/// Check if a signal is frozen. Returns 1 if frozen, 0 if not.
#[no_mangle]
pub extern "C" fn intellistate_is_frozen(id: u64) -> i32 {
    let rt = runtime().read();
    if rt.resilience.is_frozen(id) || rt.signals.is_frozen(id) {
        1
    } else {
        0
    }
}

/// Check if global safe mode is active. Returns 1 if active, 0 if not.
#[no_mangle]
pub extern "C" fn intellistate_is_safe_mode() -> i32 {
    let rt = runtime().read();
    if rt.resilience.is_safe_mode() {
        1
    } else {
        0
    }
}

/// Manually freeze a signal.
#[no_mangle]
pub extern "C" fn intellistate_freeze(id: u64) {
    let rt = runtime().read();
    rt.signals.freeze(id);
    rt.resilience.freeze_signal(id);
    rt.behavior.record_freeze(id);
}

/// Manually unfreeze a signal.
#[no_mangle]
pub extern "C" fn intellistate_unfreeze(id: u64) {
    let rt = runtime().read();
    rt.signals.unfreeze(id);
    rt.resilience.unfreeze_signal(id);
    rt.behavior.record_unfreeze(id);
}

/// Enter global safe mode manually.
#[no_mangle]
pub extern "C" fn intellistate_enter_safe_mode() {
    let rt = runtime().read();
    rt.resilience.enter_safe_mode();
}

/// Exit global safe mode manually.
#[no_mangle]
pub extern "C" fn intellistate_exit_safe_mode() {
    let rt = runtime().read();
    rt.resilience.exit_safe_mode();
}

// ═══════════════════════════════════════════════════════════════════════
//  BEHAVIOR
// ═══════════════════════════════════════════════════════════════════════

/// Get the number of buffered behavior events.
#[no_mangle]
pub extern "C" fn intellistate_behavior_count() -> u64 {
    let rt = runtime().read();
    rt.behavior.buffered_count() as u64
}

/// Drain behavior events into a caller-provided buffer.
/// Returns the number of events written (up to `max`).
///
/// `out_ptr` must point to an array of at least `max` BehaviorEvent structs.
/// Each struct is: { signal_id: u64, event_type: i32, timestamp_ms: u64 }
#[no_mangle]
pub extern "C" fn intellistate_drain_events(
    out_signal_ids: *mut u64,
    out_event_types: *mut i32,
    out_timestamps: *mut u64,
    max: u64,
) -> u64 {
    if out_signal_ids.is_null() || out_event_types.is_null() || out_timestamps.is_null() {
        return 0;
    }
    let rt = runtime().read();
    let events = rt.behavior.drain_events_max(max as usize);
    let count = events.len();

    for (i, event) in events.into_iter().enumerate() {
        unsafe {
            *out_signal_ids.add(i) = event.signal_id;
            *out_event_types.add(i) = event.event_type;
            *out_timestamps.add(i) = event.timestamp_ms;
        }
    }

    count as u64
}

// ═══════════════════════════════════════════════════════════════════════
//  DIAGNOSTICS
// ═══════════════════════════════════════════════════════════════════════

/// Get the total number of signals in the registry.
#[no_mangle]
pub extern "C" fn intellistate_signal_count() -> u64 {
    let rt = runtime().read();
    rt.signals.count() as u64
}

/// Get the total number of scheduler flushes.
#[no_mangle]
pub extern "C" fn intellistate_flush_count() -> u64 {
    let rt = runtime().read();
    rt.scheduler.total_flushes()
}

/// Get the total crash count.
#[no_mangle]
pub extern "C" fn intellistate_total_crashes() -> u64 {
    let rt = runtime().read();
    rt.resilience.stats.total()
}

// ═══════════════════════════════════════════════════════════════════════
//  HELPERS
// ═══════════════════════════════════════════════════════════════════════

/// Safely convert a C string pointer to a Rust `Option<String>`.
fn unsafe_str(ptr: *const c_char) -> Option<String> {
    if ptr.is_null() {
        return None;
    }
    unsafe { CStr::from_ptr(ptr).to_str().ok().map(|s| s.to_string()) }
}

// ─── Tests ───────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CString;

    fn setup() {
        init_runtime();
        shutdown_runtime(); // Reset state
        init_runtime();
    }

    #[test]
    fn test_ffi_create_and_get_int() {
        setup();
        let name = CString::new("counter").unwrap();
        let id = intellistate_create_int(42, name.as_ptr());
        assert!(id > 0);
        assert_eq!(intellistate_get_int(id), 42);
    }

    #[test]
    fn test_ffi_set_int() {
        setup();
        let id = intellistate_create_int(0, std::ptr::null());
        assert_eq!(intellistate_set_int(id, 10), 1); // changed
        assert_eq!(intellistate_get_int(id), 10);
        assert_eq!(intellistate_set_int(id, 10), 0); // unchanged
    }

    #[test]
    fn test_ffi_create_and_get_float() {
        setup();
        let id = intellistate_create_float(3.14, std::ptr::null());
        assert!((intellistate_get_float(id) - 3.14).abs() < f64::EPSILON);
    }

    #[test]
    fn test_ffi_create_and_get_string() {
        setup();
        let val = CString::new("hello").unwrap();
        let id = intellistate_create_string(val.as_ptr(), std::ptr::null());

        let result = intellistate_get_string(id);
        assert!(!result.is_null());
        let s = unsafe { CStr::from_ptr(result).to_str().unwrap().to_string() };
        assert_eq!(s, "hello");
        intellistate_free_string(result);
    }

    #[test]
    fn test_ffi_create_and_get_bool() {
        setup();
        let id = intellistate_create_bool(1, std::ptr::null());
        assert_eq!(intellistate_get_bool(id), 1);

        intellistate_set_bool(id, 0);
        assert_eq!(intellistate_get_bool(id), 0);
    }

    #[test]
    fn test_ffi_dispose() {
        setup();
        let id = intellistate_create_int(1, std::ptr::null());
        assert_eq!(intellistate_signal_count(), 1);

        assert_eq!(intellistate_dispose(id), 0);
        assert_eq!(intellistate_signal_count(), 0);
        assert_eq!(intellistate_dispose(id), -1); // already disposed
    }

    #[test]
    fn test_ffi_subscribe() {
        setup();
        let id = intellistate_create_int(1, std::ptr::null());
        let listener = intellistate_subscribe(id);
        assert!(listener > 0);

        intellistate_unsubscribe(id, listener);
    }

    #[test]
    fn test_ffi_batch() {
        setup();
        intellistate_batch_begin();
        let id = intellistate_create_int(0, std::ptr::null());
        intellistate_set_int(id, 1);
        intellistate_set_int(id, 2);
        intellistate_batch_end();

        assert_eq!(intellistate_get_int(id), 2);
    }

    #[test]
    fn test_ffi_health_score() {
        setup();
        let id = intellistate_create_int(42, std::ptr::null());
        let health = intellistate_health_score(id);
        assert!(health >= 0.0 && health <= 1.0, "Health: {}", health);
    }

    #[test]
    fn test_ffi_resilience() {
        setup();
        let id = intellistate_create_int(1, std::ptr::null());

        assert_eq!(intellistate_is_frozen(id), 0);
        intellistate_freeze(id);
        assert_eq!(intellistate_is_frozen(id), 1);

        // Frozen signal rejects writes
        assert_eq!(intellistate_set_int(id, 99), -2);

        intellistate_unfreeze(id);
        assert_eq!(intellistate_is_frozen(id), 0);
    }

    #[test]
    fn test_ffi_safe_mode() {
        setup();
        assert_eq!(intellistate_is_safe_mode(), 0);
        intellistate_enter_safe_mode();
        assert_eq!(intellistate_is_safe_mode(), 1);
        intellistate_exit_safe_mode();
        assert_eq!(intellistate_is_safe_mode(), 0);
    }

    #[test]
    fn test_ffi_behavior_events() {
        setup();
        let id = intellistate_create_int(0, std::ptr::null());
        intellistate_set_int(id, 1);
        intellistate_get_int(id);

        let count = intellistate_behavior_count();
        assert!(count > 0);
    }

    #[test]
    fn test_ffi_diagnostics() {
        setup();
        intellistate_create_int(1, std::ptr::null());
        intellistate_create_float(2.0, std::ptr::null());
        assert_eq!(intellistate_signal_count(), 2);
        assert_eq!(intellistate_total_crashes(), 0);
    }
}
