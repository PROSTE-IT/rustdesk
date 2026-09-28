Future<String?> readSupportDeviceToken() async => null;

Future<void> writeSupportDeviceToken(String token) async {}

Future<void> deleteSupportDeviceToken() async {}

String supportMachineName() => '';

String supportOsUsername() => '';

Future<String> readOrCreateSupportInstallationId() async => '';

Future<List<Map<String, dynamic>>> readSupportEventQueue() async => const [];

Future<void> writeSupportEventQueue(List<Map<String, dynamic>> events) async {}

Future<List<Map<String, dynamic>>> readSupportPostSessionPrompts() async =>
    const [];

Future<void> writeSupportPostSessionPrompts(
    List<Map<String, dynamic>> prompts) async {}

Future<List<Map<String, dynamic>>> appendSupportPostSessionPrompt(
  Map<String, dynamic> prompt,
) async =>
    const [];

Future<List<Map<String, dynamic>>> removeSupportPostSessionPrompt(
  String promptId,
) async =>
    const [];

Future<Map<String, String>> readSupportSessionSyncFailures() async => const {};

Future<void> writeSupportSessionSyncFailures(
    Map<String, String> failures) async {}
