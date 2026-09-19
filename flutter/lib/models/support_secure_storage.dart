import 'support_secure_storage_stub.dart'
    if (dart.library.io) 'support_secure_storage_io.dart' as implementation;

Future<String?> readSupportDeviceToken() =>
    implementation.readSupportDeviceToken();

Future<void> writeSupportDeviceToken(String token) =>
    implementation.writeSupportDeviceToken(token);

Future<void> deleteSupportDeviceToken() =>
    implementation.deleteSupportDeviceToken();

String supportMachineName() => implementation.supportMachineName();

String supportOsUsername() => implementation.supportOsUsername();

Future<String> readOrCreateSupportInstallationId() =>
    implementation.readOrCreateSupportInstallationId();

Future<List<Map<String, dynamic>>> readSupportEventQueue() =>
    implementation.readSupportEventQueue();

Future<void> writeSupportEventQueue(List<Map<String, dynamic>> events) =>
    implementation.writeSupportEventQueue(events);
