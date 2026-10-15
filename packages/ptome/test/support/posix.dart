/// What the tests ask of a POSIX system, in this process through the C
/// library (no `chmod` to run): a file's permissions. For tests on POSIX
/// systems only (`testOn: 'posix'`).
library;

import 'dart:convert';
import 'dart:ffi';

final DynamicLibrary _libc = DynamicLibrary.process();

final Pointer<Uint8> Function(int) _malloc = _libc
    .lookupFunction<
      Pointer<Uint8> Function(IntPtr),
      Pointer<Uint8> Function(int)
    >('malloc');

final void Function(Pointer<Uint8>) _free = _libc
    .lookupFunction<
      Void Function(Pointer<Uint8>),
      void Function(Pointer<Uint8>)
    >('free');

final int Function(Pointer<Uint8>, int) _chmod = _libc
    .lookupFunction<
      Int32 Function(Pointer<Uint8>, Uint32),
      int Function(Pointer<Uint8>, int)
    >('chmod');

/// Sets the permissions of the file at [path] to [mode] (`0x1a4`: octal
/// 644).
void chmod(String path, int mode) {
  final bytes = utf8.encode(path);
  final native = _malloc(bytes.length + 1);
  try {
    native.asTypedList(bytes.length + 1)
      ..setAll(0, bytes)
      ..[bytes.length] = 0;
    if (_chmod(native, mode) != 0) throw StateError('chmod $path failed');
  } finally {
    _free(native);
  }
}
