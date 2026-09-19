import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

final class _DataBlob extends Struct {
  @Uint32()
  external int length;

  external Pointer<Uint8> data;
}

typedef _CryptProtectDataNative = Int32 Function(
  Pointer<_DataBlob>,
  Pointer<Utf16>,
  Pointer<_DataBlob>,
  Pointer<Void>,
  Pointer<Void>,
  Uint32,
  Pointer<_DataBlob>,
);
typedef _CryptProtectDataDart = int Function(
  Pointer<_DataBlob>,
  Pointer<Utf16>,
  Pointer<_DataBlob>,
  Pointer<Void>,
  Pointer<Void>,
  int,
  Pointer<_DataBlob>,
);
typedef _CryptUnprotectDataNative = Int32 Function(
  Pointer<_DataBlob>,
  Pointer<Pointer<Utf16>>,
  Pointer<_DataBlob>,
  Pointer<Void>,
  Pointer<Void>,
  Uint32,
  Pointer<_DataBlob>,
);
typedef _CryptUnprotectDataDart = int Function(
  Pointer<_DataBlob>,
  Pointer<Pointer<Utf16>>,
  Pointer<_DataBlob>,
  Pointer<Void>,
  Pointer<Void>,
  int,
  Pointer<_DataBlob>,
);
typedef _LocalFreeNative = Pointer<Void> Function(Pointer<Void>);
typedef _LocalFreeDart = Pointer<Void> Function(Pointer<Void>);

const _cryptProtectUiForbidden = 0x1;
const _tokenFileName = 'rdbk-device-token.dpapi';
const _installationFileName = 'rdbk-installation-id';
const _queueFileName = 'rdbk-event-queue.json';

Future<Directory> _supportDirectory() async {
  final base = await getApplicationSupportDirectory();
  final directory = Directory('${base.path}${Platform.pathSeparator}rdbk');
  if (!await directory.exists()) {
    await directory.create(recursive: true);
  }
  return directory;
}

Future<File> _file(String name) async =>
    File('${(await _supportDirectory()).path}${Platform.pathSeparator}$name');

Uint8List _runDpapi(Uint8List input, {required bool protect}) {
  if (!Platform.isWindows) {
    throw UnsupportedError('DPAPI jest dostępne tylko na Windows.');
  }
  final crypt32 = DynamicLibrary.open('crypt32.dll');
  final kernel32 = DynamicLibrary.open('kernel32.dll');
  final localFree = kernel32.lookupFunction<_LocalFreeNative, _LocalFreeDart>(
    'LocalFree',
  );
  final inputBytes = calloc<Uint8>(input.length);
  final inputBlob = calloc<_DataBlob>();
  final outputBlob = calloc<_DataBlob>();
  final description = calloc<Pointer<Utf16>>();
  try {
    inputBytes.asTypedList(input.length).setAll(0, input);
    inputBlob.ref
      ..length = input.length
      ..data = inputBytes;
    final result = protect
        ? crypt32.lookupFunction<_CryptProtectDataNative,
                _CryptProtectDataDart>('CryptProtectData')(
            inputBlob,
            nullptr,
            nullptr,
            nullptr,
            nullptr,
            _cryptProtectUiForbidden,
            outputBlob,
          )
        : crypt32.lookupFunction<_CryptUnprotectDataNative,
                _CryptUnprotectDataDart>('CryptUnprotectData')(
            inputBlob,
            description,
            nullptr,
            nullptr,
            nullptr,
            _cryptProtectUiForbidden,
            outputBlob,
          );
    if (result == 0) {
      throw const FileSystemException('Windows DPAPI operation failed.');
    }
    return Uint8List.fromList(
      outputBlob.ref.data.asTypedList(outputBlob.ref.length),
    );
  } finally {
    if (outputBlob.ref.data != nullptr) {
      localFree(outputBlob.ref.data.cast<Void>());
    }
    if (description.value != nullptr) {
      localFree(description.value.cast<Void>());
    }
    calloc.free(description);
    calloc.free(outputBlob);
    calloc.free(inputBlob);
    inputBytes.asTypedList(input.length).fillRange(0, input.length, 0);
    calloc.free(inputBytes);
  }
}

String supportMachineName() => Platform.localHostname;

String supportOsUsername() =>
    Platform.environment['USERNAME'] ?? Platform.environment['USER'] ?? '';

Future<String?> readSupportDeviceToken() async {
  if (!Platform.isWindows) return null;
  final file = await _file(_tokenFileName);
  if (!await file.exists()) return null;
  try {
    final protected = base64Decode(await file.readAsString());
    return utf8.decode(_runDpapi(protected, protect: false));
  } catch (_) {
    // A token copied from another account/computer must be treated as absent.
    return null;
  }
}

Future<void> writeSupportDeviceToken(String token) async {
  if (!Platform.isWindows) return;
  final file = await _file(_tokenFileName);
  final protected = _runDpapi(Uint8List.fromList(utf8.encode(token)),
      protect: true);
  await file.writeAsString(base64Encode(protected), flush: true);
}

Future<void> deleteSupportDeviceToken() async {
  final file = await _file(_tokenFileName);
  if (await file.exists()) await file.delete();
}

Future<String> readOrCreateSupportInstallationId() async {
  final file = await _file(_installationFileName);
  if (await file.exists()) {
    final existing = (await file.readAsString()).trim();
    if (existing.isNotEmpty) return existing;
  }
  final value = const Uuid().v4();
  await file.writeAsString(value, flush: true);
  return value;
}

Future<List<Map<String, dynamic>>> readSupportEventQueue() async {
  final file = await _file(_queueFileName);
  if (!await file.exists()) return [];
  try {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! List) return [];
    return decoded
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  } catch (_) {
    return [];
  }
}

Future<void> writeSupportEventQueue(List<Map<String, dynamic>> events) async {
  final file = await _file(_queueFileName);
  await file.writeAsString(jsonEncode(events), flush: true);
}
