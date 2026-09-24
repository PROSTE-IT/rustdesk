import 'dart:convert';

import 'package:flutter_hbb/models/legacy_host_migration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String decodePowerShell(String encoded) {
    final bytes = base64Decode(encoded);
    final codeUnits = <int>[
      for (var index = 0; index < bytes.length; index += 2)
        bytes[index] | (bytes[index + 1] << 8),
    ];
    return String.fromCharCodes(codeUnits);
  }

  test('reserves only one automatic prompt per remote session', () {
    final coordinator = LegacyHostMigrationCoordinator();

    expect(coordinator.reserveAutoPrompt('123:1'), isTrue);
    expect(coordinator.reserveAutoPrompt('123:1'), isFalse);
    expect(coordinator.reserveAutoPrompt('123:2'), isTrue);
  });

  test('prevents concurrent dispatch and allows retry after local failure', () {
    final coordinator = LegacyHostMigrationCoordinator();

    expect(coordinator.tryBegin('123:1'), isTrue);
    expect(coordinator.tryBegin('123:1'), isFalse);
    coordinator.markFailed('123:1');
    expect(coordinator.tryBegin('123:1'), isTrue);
    coordinator.markDispatched('123:1');
    expect(coordinator.isDispatched('123:1'), isTrue);
    expect(coordinator.tryBegin('123:1'), isFalse);
  });

  test('waits for ten idle seconds after the latest technician input', () {
    final coordinator = LegacyHostMigrationCoordinator();
    final startedAt = DateTime.utc(2026, 9, 24, 10);

    expect(
        coordinator.autoPromptDelayRemaining('123:1', now: startedAt), isNull);
    coordinator.noteTechnicianInput('123:1', at: startedAt);
    expect(
      coordinator.autoPromptDelayRemaining(
        '123:1',
        now: startedAt.add(const Duration(seconds: 4)),
      ),
      const Duration(seconds: 6),
    );

    coordinator.noteTechnicianInput(
      '123:1',
      at: startedAt.add(const Duration(seconds: 7)),
    );
    expect(
      coordinator.autoPromptDelayRemaining(
        '123:1',
        now: startedAt.add(const Duration(seconds: 12)),
      ),
      const Duration(seconds: 5),
    );
    expect(
      coordinator.autoPromptDelayRemaining(
        '123:1',
        now: startedAt.add(const Duration(seconds: 17)),
      ),
      Duration.zero,
    );
  });

  test('releasing a session clears its prompt and input state', () {
    final coordinator = LegacyHostMigrationCoordinator();
    final now = DateTime.utc(2026, 9, 24, 10);

    coordinator.noteTechnicianInput('123:1', at: now);
    expect(coordinator.reserveAutoPrompt('123:1'), isTrue);
    coordinator.releaseSession('123:1');

    expect(coordinator.autoPromptDelayRemaining('123:1', now: now), isNull);
    expect(coordinator.reserveAutoPrompt('123:1'), isTrue);
  });

  test('builds a short bootstrap for the signed RDBK migration plan', () {
    final script = buildLegacyHostMigrationPowerShell(
      migrationScriptUrl: "https://rdbk.example/download/a'b/script.ps1",
    );

    expect(script, contains('-Verb RunAs'));
    expect(script, contains('-EncodedCommand'));
    expect(script, contains('-Wait -PassThru'));
    expect(script, contains('System.Windows.MessageBox'));
    expect(script, isNot(contains('msiexec.exe')));
    expect(script, isNot(contains('--uninstall')));
    expect(script, isNot(contains('Invoke-WebRequest')));

    final nestedEncoded =
        RegExp(r"\$e='([^']+)'").firstMatch(script)!.group(1)!;
    final elevatedScript = decodePowerShell(nestedEncoded);
    expect(
      elevatedScript,
      contains("https://rdbk.example/download/a''b/script.ps1"),
    );
    expect(elevatedScript, contains('Invoke-WebRequest'));
    expect(elevatedScript, contains(r'$env:ProgramData'));
    expect(elevatedScript, contains('-Elevated'));
    expect(elevatedScript, isNot(contains(r'$env:TEMP')));

    final command = buildLegacyHostMigrationCommand(
      migrationScriptUrl:
          'https://rdbk.example/download/${List.filled(600, 'a').join()}/script.ps1',
    );
    expect(command, contains('-Command "'));
    expect(command, contains('-Verb RunAs'));
    expect(command, isNot(contains('https://rdbk.example')));
    expect(command.length, lessThan(8191));
  });
}
