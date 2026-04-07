import 'dart:ffi' as ffi;
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'signal_engine.dart';
import 'dart_engine.dart';

// FFI Signatures
typedef SetIntC = ffi.Int32 Function(ffi.Uint64 id, ffi.Int64 value);
typedef SetIntDart = int Function(int id, int value);

typedef GetIntC = ffi.Int64 Function(ffi.Uint64 id);
typedef GetIntDart = int Function(int id);

typedef SetFloatC = ffi.Int32 Function(ffi.Uint64 id, ffi.Double value);
typedef SetFloatDart = int Function(int id, double value);

typedef GetFloatC = ffi.Double Function(ffi.Uint64 id);
typedef GetFloatDart = double Function(int id);

typedef DisposeC = ffi.Int32 Function(ffi.Uint64 id);
typedef DisposeDart = int Function(int id);

/// Rust FFI engine stub.
///
/// Uses dart:ffi to call into a native Rust library.
/// Falls back to [DartSignalEngine] silently if native lib is unavailable.
class RustSignalEngine implements SignalEngine {
  RustSignalEngine._();

  static final RustSignalEngine instance = RustSignalEngine._();

  /// The Dart fallback engine used when FFI calls fail.
  final DartSignalEngine _fallback = DartSignalEngine.instance;

  static ffi.DynamicLibrary? _dylib;
  static SetIntDart? _setInt;
  static GetIntDart? _getInt;
  static SetFloatDart? _setFloat;
  static GetFloatDart? _getFloat;
  static DisposeDart? _dispose;

  /// Whether the native Rust library was successfully loaded.
  static bool get isAvailable {
    if (_dylib != null) return true;
    try {
      _loadLib();
      return _dylib != null;
    } catch (_) {
      return false;
    }
  }

  static void _loadLib() {
    if (_dylib != null) return;
    
    try {
      if (Platform.isMacOS) {
        _dylib = ffi.DynamicLibrary.open('libakvs_signal_engine.dylib');
      } else if (Platform.isWindows) {
        _dylib = ffi.DynamicLibrary.open('akvs_signal_engine.dll');
      } else if (Platform.isLinux) {
        _dylib = ffi.DynamicLibrary.open('libakvs_signal_engine.so');
      }
      
      if (_dylib != null) {
        _setInt = _dylib!.lookupFunction<SetIntC, SetIntDart>('intellistate_set_int');
        _getInt = _dylib!.lookupFunction<GetIntC, GetIntDart>('intellistate_get_int');
        _setFloat = _dylib!.lookupFunction<SetFloatC, SetFloatDart>('intellistate_set_float');
        _getFloat = _dylib!.lookupFunction<GetFloatC, GetFloatDart>('intellistate_get_float');
        _dispose = _dylib!.lookupFunction<DisposeC, DisposeDart>('intellistate_dispose');
      }
    } catch (e) {
      // Missing binary -> silent fallback
      _dylib = null;
    }
  }

  // ── SignalEngine interface ─────────────────────────────────────────

  @override
  void write<T>(int signalId, T value) {
    if (isAvailable && _dylib != null) {
      try {
        if (value is int && _setInt != null) {
          final res = _setInt!(signalId, value);
          if (res >= 0) return; // 1 = changed, 0 = unchanged
        } else if (value is double && _setFloat != null) {
          final res = _setFloat!(signalId, value);
          if (res >= 0) return;
        }
        // Fallthrough if not found in rust dict or unsupported type
      } catch (e) {
        debugPrint('[RustEngine] FFI write failed, falling back to Dart: $e');
      }
    }
    _fallback.write(signalId, value);
  }

  @override
  T read<T>(int signalId) {
    if (isAvailable && _dylib != null) {
      try {
        if (T == int && _getInt != null) {
          return _getInt!(signalId) as T;
        } else if (T == double && _getFloat != null) {
          return _getFloat!(signalId) as T;
        }
      } catch (e) {
        debugPrint('[RustEngine] FFI read failed, falling back to Dart: $e');
      }
    }
    return _fallback.read<T>(signalId);
  }

  @override
  void subscribe(int signalId, void Function() listener) {
    _fallback.subscribe(signalId, listener);
  }

  @override
  void unsubscribe(int signalId, void Function() listener) {
    _fallback.unsubscribe(signalId, listener);
  }

  @override
  void batch(void Function() writes) {
    _fallback.batch(writes);
  }

  @override
  void dispose(int signalId) {
    if (isAvailable && _dispose != null) {
      try {
        _dispose!(signalId);
      } catch (_) {}
    }
    _fallback.dispose(signalId);
  }

  @override
  SignalEngineMode get mode => SignalEngineMode.rust;

  @override
  int get signalCount => _fallback.signalCount;
}
