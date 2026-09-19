Future<String?> readSupportDeviceToken() async => null;

Future<void> writeSupportDeviceToken(String token) async {}

Future<void> deleteSupportDeviceToken() async {}

String supportMachineName() => '';

String supportOsUsername() => '';

Future<String> readOrCreateSupportInstallationId() async => '';

Future<List<Map<String, dynamic>>> readSupportEventQueue() async => const [];

Future<void> writeSupportEventQueue(List<Map<String, dynamic>> events) async {}
