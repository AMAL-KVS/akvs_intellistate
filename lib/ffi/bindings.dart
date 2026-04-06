/// Raw FFI bindings for the IntelliState Rust core engine.
///
/// This file contains the low-level `dart:ffi` typedefs and function lookups.
/// Use [RustBridge] for the high-level API.
library;

import 'dart:ffi' as ffi;
import 'dart:io' show Platform;
import 'package:ffi/ffi.dart' as pkg_ffi;

// ═══════════════════════════════════════════════════════════════════════
//  NATIVE FUNCTION TYPEDEFS
// ═══════════════════════════════════════════════════════════════════════

// Lifecycle
typedef IntellistateInitNative = ffi.Void Function();
typedef IntellistateInit = void Function();

typedef IntellistateShutdownNative = ffi.Void Function();
typedef IntellistateShutdown = void Function();

// Signal creation
typedef IntellistateCreateIntNative =
    ffi.Uint64 Function(ffi.Int64 value, ffi.Pointer<pkg_ffi.Utf8> name);
typedef IntellistateCreateInt =
    int Function(int value, ffi.Pointer<pkg_ffi.Utf8> name);

typedef IntellistateCreateFloatNative =
    ffi.Uint64 Function(ffi.Double value, ffi.Pointer<pkg_ffi.Utf8> name);
typedef IntellistateCreateFloat =
    int Function(double value, ffi.Pointer<pkg_ffi.Utf8> name);

typedef IntellistateCreateStringNative =
    ffi.Uint64 Function(
      ffi.Pointer<pkg_ffi.Utf8> value,
      ffi.Pointer<pkg_ffi.Utf8> name,
    );
typedef IntellistateCreateString =
    int Function(
      ffi.Pointer<pkg_ffi.Utf8> value,
      ffi.Pointer<pkg_ffi.Utf8> name,
    );

typedef IntellistateCreateBoolNative =
    ffi.Uint64 Function(ffi.Int32 value, ffi.Pointer<pkg_ffi.Utf8> name);
typedef IntellistateCreateBool =
    int Function(int value, ffi.Pointer<pkg_ffi.Utf8> name);

typedef IntellistateDisposeNative = ffi.Int32 Function(ffi.Uint64 id);
typedef IntellistateDispose = int Function(int id);

// Getters
typedef IntellistateGetTypeNative = ffi.Int32 Function(ffi.Uint64 id);
typedef IntellistateGetType = int Function(int id);

typedef IntellistateGetIntNative = ffi.Int64 Function(ffi.Uint64 id);
typedef IntellistateGetInt = int Function(int id);

typedef IntellistateGetFloatNative = ffi.Double Function(ffi.Uint64 id);
typedef IntellistateGetFloat = double Function(int id);

typedef IntellistateGetStringNative =
    ffi.Pointer<pkg_ffi.Utf8> Function(ffi.Uint64 id);
typedef IntellistateGetString = ffi.Pointer<pkg_ffi.Utf8> Function(int id);

typedef IntellistateGetBoolNative = ffi.Int32 Function(ffi.Uint64 id);
typedef IntellistateGetBool = int Function(int id);

typedef IntellistateFreeStringNative =
    ffi.Void Function(ffi.Pointer<pkg_ffi.Utf8> ptr);
typedef IntellistateFreeString = void Function(ffi.Pointer<pkg_ffi.Utf8> ptr);

// Setters
typedef IntellistateSetIntNative =
    ffi.Int32 Function(ffi.Uint64 id, ffi.Int64 value);
typedef IntellistateSetInt = int Function(int id, int value);

typedef IntellistateSetFloatNative =
    ffi.Int32 Function(ffi.Uint64 id, ffi.Double value);
typedef IntellistateSetFloat = int Function(int id, double value);

typedef IntellistateSetStringNative =
    ffi.Int32 Function(ffi.Uint64 id, ffi.Pointer<pkg_ffi.Utf8> value);
typedef IntellistateSetString =
    int Function(int id, ffi.Pointer<pkg_ffi.Utf8> value);

typedef IntellistateSetBoolNative =
    ffi.Int32 Function(ffi.Uint64 id, ffi.Int32 value);
typedef IntellistateSetBool = int Function(int id, int value);

// Subscriptions
typedef IntellistateSubscribeNative = ffi.Uint64 Function(ffi.Uint64 signalId);
typedef IntellistateSubscribe = int Function(int signalId);

typedef IntellistateUnsubscribeNative =
    ffi.Void Function(ffi.Uint64 signalId, ffi.Uint64 listenerId);
typedef IntellistateUnsubscribe = void Function(int signalId, int listenerId);

// Scheduler
typedef IntellistateBatchBeginNative = ffi.Void Function();
typedef IntellistateBatchBegin = void Function();

typedef IntellistateBatchEndNative = ffi.Void Function();
typedef IntellistateBatchEnd = void Function();

typedef IntellistateFlushNative = ffi.Int32 Function();
typedef IntellistateFlush = int Function();

// Intelligence
typedef IntellistateHealthScoreNative = ffi.Double Function(ffi.Uint64 id);
typedef IntellistateHealthScore = double Function(int id);

typedef IntellistateDegradationLevelNative = ffi.Int32 Function(ffi.Uint64 id);
typedef IntellistateDegradationLevel = int Function(int id);

// Resilience
typedef IntellistateRecordErrorNative =
    ffi.Void Function(ffi.Uint64 id, ffi.Pointer<pkg_ffi.Utf8> errorType);
typedef IntellistateRecordError =
    void Function(int id, ffi.Pointer<pkg_ffi.Utf8> errorType);

typedef IntellistateIsFrozenNative = ffi.Int32 Function(ffi.Uint64 id);
typedef IntellistateIsFrozen = int Function(int id);

typedef IntellistateIsSafeModeNative = ffi.Int32 Function();
typedef IntellistateIsSafeMode = int Function();

typedef IntellistateFreezeNative = ffi.Void Function(ffi.Uint64 id);
typedef IntellistateFreeze = void Function(int id);

typedef IntellistateUnfreezeNative = ffi.Void Function(ffi.Uint64 id);
typedef IntellistateUnfreeze = void Function(int id);

typedef IntellistateEnterSafeModeNative = ffi.Void Function();
typedef IntellistateEnterSafeMode = void Function();

typedef IntellistateExitSafeModeNative = ffi.Void Function();
typedef IntellistateExitSafeMode = void Function();

// Behavior
typedef IntellistateBehaviorCountNative = ffi.Uint64 Function();
typedef IntellistateBehaviorCount = int Function();

// Diagnostics
typedef IntellistateSignalCountNative = ffi.Uint64 Function();
typedef IntellistateSignalCount = int Function();

typedef IntellistateFlushCountNative = ffi.Uint64 Function();
typedef IntellistateFlushCount = int Function();

typedef IntellistateTotalCrashesNative = ffi.Uint64 Function();
typedef IntellistateTotalCrashes = int Function();

// ═══════════════════════════════════════════════════════════════════════
//  LIBRARY LOADER
// ═══════════════════════════════════════════════════════════════════════

/// Holds all resolved FFI function pointers.
class NativeBindings {
  final IntellistateInit init;
  final IntellistateShutdown shutdown;

  // Signal lifecycle
  final IntellistateCreateInt createInt;
  final IntellistateCreateFloat createFloat;
  final IntellistateCreateString createString;
  final IntellistateCreateBool createBool;
  final IntellistateDispose dispose;

  // Getters
  final IntellistateGetType getType;
  final IntellistateGetInt getInt;
  final IntellistateGetFloat getFloat;
  final IntellistateGetString getString;
  final IntellistateGetBool getBool;
  final IntellistateFreeString freeString;

  // Setters
  final IntellistateSetInt setInt;
  final IntellistateSetFloat setFloat;
  final IntellistateSetString setString;
  final IntellistateSetBool setBool;

  // Subscriptions
  final IntellistateSubscribe subscribe;
  final IntellistateUnsubscribe unsubscribe;

  // Scheduler
  final IntellistateBatchBegin batchBegin;
  final IntellistateBatchEnd batchEnd;
  final IntellistateFlush flush;

  // Intelligence
  final IntellistateHealthScore healthScore;
  final IntellistateDegradationLevel degradationLevel;

  // Resilience
  final IntellistateRecordError recordError;
  final IntellistateIsFrozen isFrozen;
  final IntellistateIsSafeMode isSafeMode;
  final IntellistateFreeze freeze;
  final IntellistateUnfreeze unfreeze;
  final IntellistateEnterSafeMode enterSafeMode;
  final IntellistateExitSafeMode exitSafeMode;

  // Behavior
  final IntellistateBehaviorCount behaviorCount;

  // Diagnostics
  final IntellistateSignalCount signalCount;
  final IntellistateFlushCount flushCount;
  final IntellistateTotalCrashes totalCrashes;

  NativeBindings._({
    required this.init,
    required this.shutdown,
    required this.createInt,
    required this.createFloat,
    required this.createString,
    required this.createBool,
    required this.dispose,
    required this.getType,
    required this.getInt,
    required this.getFloat,
    required this.getString,
    required this.getBool,
    required this.freeString,
    required this.setInt,
    required this.setFloat,
    required this.setString,
    required this.setBool,
    required this.subscribe,
    required this.unsubscribe,
    required this.batchBegin,
    required this.batchEnd,
    required this.flush,
    required this.healthScore,
    required this.degradationLevel,
    required this.recordError,
    required this.isFrozen,
    required this.isSafeMode,
    required this.freeze,
    required this.unfreeze,
    required this.enterSafeMode,
    required this.exitSafeMode,
    required this.behaviorCount,
    required this.signalCount,
    required this.flushCount,
    required this.totalCrashes,
  });

  /// Load all native bindings from the given [dylib].
  factory NativeBindings.load(ffi.DynamicLibrary dylib) {
    return NativeBindings._(
      init: dylib.lookupFunction<IntellistateInitNative, IntellistateInit>(
        'intellistate_init',
      ),
      shutdown: dylib
          .lookupFunction<IntellistateShutdownNative, IntellistateShutdown>(
            'intellistate_shutdown',
          ),
      createInt: dylib
          .lookupFunction<IntellistateCreateIntNative, IntellistateCreateInt>(
            'intellistate_create_int',
          ),
      createFloat: dylib.lookupFunction<
        IntellistateCreateFloatNative,
        IntellistateCreateFloat
      >('intellistate_create_float'),
      createString: dylib.lookupFunction<
        IntellistateCreateStringNative,
        IntellistateCreateString
      >('intellistate_create_string'),
      createBool: dylib
          .lookupFunction<IntellistateCreateBoolNative, IntellistateCreateBool>(
            'intellistate_create_bool',
          ),
      dispose: dylib
          .lookupFunction<IntellistateDisposeNative, IntellistateDispose>(
            'intellistate_dispose',
          ),
      getType: dylib
          .lookupFunction<IntellistateGetTypeNative, IntellistateGetType>(
            'intellistate_get_type',
          ),
      getInt: dylib
          .lookupFunction<IntellistateGetIntNative, IntellistateGetInt>(
            'intellistate_get_int',
          ),
      getFloat: dylib
          .lookupFunction<IntellistateGetFloatNative, IntellistateGetFloat>(
            'intellistate_get_float',
          ),
      getString: dylib
          .lookupFunction<IntellistateGetStringNative, IntellistateGetString>(
            'intellistate_get_string',
          ),
      getBool: dylib
          .lookupFunction<IntellistateGetBoolNative, IntellistateGetBool>(
            'intellistate_get_bool',
          ),
      freeString: dylib
          .lookupFunction<IntellistateFreeStringNative, IntellistateFreeString>(
            'intellistate_free_string',
          ),
      setInt: dylib
          .lookupFunction<IntellistateSetIntNative, IntellistateSetInt>(
            'intellistate_set_int',
          ),
      setFloat: dylib
          .lookupFunction<IntellistateSetFloatNative, IntellistateSetFloat>(
            'intellistate_set_float',
          ),
      setString: dylib
          .lookupFunction<IntellistateSetStringNative, IntellistateSetString>(
            'intellistate_set_string',
          ),
      setBool: dylib
          .lookupFunction<IntellistateSetBoolNative, IntellistateSetBool>(
            'intellistate_set_bool',
          ),
      subscribe: dylib
          .lookupFunction<IntellistateSubscribeNative, IntellistateSubscribe>(
            'intellistate_subscribe',
          ),
      unsubscribe: dylib.lookupFunction<
        IntellistateUnsubscribeNative,
        IntellistateUnsubscribe
      >('intellistate_unsubscribe'),
      batchBegin: dylib
          .lookupFunction<IntellistateBatchBeginNative, IntellistateBatchBegin>(
            'intellistate_batch_begin',
          ),
      batchEnd: dylib
          .lookupFunction<IntellistateBatchEndNative, IntellistateBatchEnd>(
            'intellistate_batch_end',
          ),
      flush: dylib.lookupFunction<IntellistateFlushNative, IntellistateFlush>(
        'intellistate_flush',
      ),
      healthScore: dylib.lookupFunction<
        IntellistateHealthScoreNative,
        IntellistateHealthScore
      >('intellistate_health_score'),
      degradationLevel: dylib.lookupFunction<
        IntellistateDegradationLevelNative,
        IntellistateDegradationLevel
      >('intellistate_degradation_level'),
      recordError: dylib.lookupFunction<
        IntellistateRecordErrorNative,
        IntellistateRecordError
      >('intellistate_record_error'),
      isFrozen: dylib
          .lookupFunction<IntellistateIsFrozenNative, IntellistateIsFrozen>(
            'intellistate_is_frozen',
          ),
      isSafeMode: dylib
          .lookupFunction<IntellistateIsSafeModeNative, IntellistateIsSafeMode>(
            'intellistate_is_safe_mode',
          ),
      freeze: dylib
          .lookupFunction<IntellistateFreezeNative, IntellistateFreeze>(
            'intellistate_freeze',
          ),
      unfreeze: dylib
          .lookupFunction<IntellistateUnfreezeNative, IntellistateUnfreeze>(
            'intellistate_unfreeze',
          ),
      enterSafeMode: dylib.lookupFunction<
        IntellistateEnterSafeModeNative,
        IntellistateEnterSafeMode
      >('intellistate_enter_safe_mode'),
      exitSafeMode: dylib.lookupFunction<
        IntellistateExitSafeModeNative,
        IntellistateExitSafeMode
      >('intellistate_exit_safe_mode'),
      behaviorCount: dylib.lookupFunction<
        IntellistateBehaviorCountNative,
        IntellistateBehaviorCount
      >('intellistate_behavior_count'),
      signalCount: dylib.lookupFunction<
        IntellistateSignalCountNative,
        IntellistateSignalCount
      >('intellistate_signal_count'),
      flushCount: dylib
          .lookupFunction<IntellistateFlushCountNative, IntellistateFlushCount>(
            'intellistate_flush_count',
          ),
      totalCrashes: dylib.lookupFunction<
        IntellistateTotalCrashesNative,
        IntellistateTotalCrashes
      >('intellistate_total_crashes'),
    );
  }
}

/// Returns the platform-specific library name for the Rust core.
String _libraryName() {
  if (Platform.isMacOS) return 'libintellistate_core.dylib';
  if (Platform.isLinux) return 'libintellistate_core.so';
  if (Platform.isWindows) return 'intellistate_core.dll';
  if (Platform.isAndroid) return 'libintellistate_core.so';
  if (Platform.isIOS) return 'intellistate_core.framework/intellistate_core';
  throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
}

/// Attempts to load the native library from known locations.
/// Returns null if library cannot be found.
ffi.DynamicLibrary? tryLoadLibrary() {
  final name = _libraryName();

  // Try multiple locations in order of likelihood
  final searchPaths = [
    name, // System path / bundled
    'native/$name', // Project native/ dir
    '../native/$name', // From example/
    'rust_core/target/release/$name',
    'rust_core/target/debug/$name',
  ];

  for (final path in searchPaths) {
    try {
      return ffi.DynamicLibrary.open(path);
    } catch (_) {
      continue;
    }
  }
  return null;
}
