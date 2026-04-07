//! Minimal Rust signal store scaffold for AKVS IntelliState.
//!
//! This crate provides a simple key-value store that the Dart FFI
//! layer can call into for high-performance signal storage.
//!
//! ## Building
//!
//! ```bash
//! cd rust
//! cargo build --release
//! ```
//!
//! The resulting `libakvs_signal_engine.dylib` (macOS) /
//! `libakvs_signal_engine.so` (Linux) / `akvs_signal_engine.dll` (Windows)
//! should be placed where the Flutter app can find it.

use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};

/// Global signal store: signal_id → serialized bytes.
static STORE: OnceLock<Mutex<HashMap<i64, Vec<u8>>>> = OnceLock::new();

fn store() -> &'static Mutex<HashMap<i64, Vec<u8>>> {
    STORE.get_or_init(|| Mutex::new(HashMap::new()))
}

/// Write raw bytes for a signal ID.
///
/// # Safety
/// `data` must point to a valid byte buffer of at least `len` bytes.
#[no_mangle]
pub extern "C" fn akvs_write(signal_id: i64, data: *const u8, len: usize) {
    if data.is_null() || len == 0 {
        return;
    }
    let bytes = unsafe { std::slice::from_raw_parts(data, len) }.to_vec();
    store().lock().unwrap().insert(signal_id, bytes);
}

/// Read raw bytes for a signal ID into the provided buffer.
/// Returns the number of bytes written to `out`.
///
/// # Safety
/// `out` must point to a valid buffer of at least `max_len` bytes.
#[no_mangle]
pub extern "C" fn akvs_read(signal_id: i64, out: *mut u8, max_len: usize) -> usize {
    if out.is_null() {
        return 0;
    }
    let store = store().lock().unwrap();
    if let Some(bytes) = store.get(&signal_id) {
        let len = bytes.len().min(max_len);
        unsafe {
            std::ptr::copy_nonoverlapping(bytes.as_ptr(), out, len);
        }
        len
    } else {
        0
    }
}

/// Delete a signal from the store.
#[no_mangle]
pub extern "C" fn akvs_delete(signal_id: i64) {
    store().lock().unwrap().remove(&signal_id);
}

/// Returns the number of signals currently stored.
#[no_mangle]
pub extern "C" fn akvs_count() -> usize {
    store().lock().unwrap().len()
}

/// Clear all signals from the store.
#[no_mangle]
pub extern "C" fn akvs_clear() {
    store().lock().unwrap().clear();
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_write_read_delete() {
        let data = b"hello";
        akvs_write(1, data.as_ptr(), data.len());

        let mut buf = [0u8; 32];
        let len = akvs_read(1, buf.as_mut_ptr(), buf.len());
        assert_eq!(len, 5);
        assert_eq!(&buf[..len], b"hello");

        akvs_delete(1);
        let len = akvs_read(1, buf.as_mut_ptr(), buf.len());
        assert_eq!(len, 0);
    }

    #[test]
    fn test_count_and_clear() {
        akvs_clear();
        assert_eq!(akvs_count(), 0);

        let data = b"test";
        akvs_write(10, data.as_ptr(), data.len());
        akvs_write(20, data.as_ptr(), data.len());
        assert_eq!(akvs_count(), 2);

        akvs_clear();
        assert_eq!(akvs_count(), 0);
    }
}
