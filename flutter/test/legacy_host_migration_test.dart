import 'dart:convert';

import 'package:flutter_hbb/models/legacy_host_migration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

    expect(coordinator.autoPromptDelayRemaining('123:1', now: startedAt),
        isNull);
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

  test('builds visible passive installer command with pinned signer', () {
    const subject =
        'CN=PROSTE IT Sp. z o.o., O=PROSTE IT Sp. z o.o., L=Ożarów Mazowiecki, S=Mazowieckie, C=PL';
    final script = buildLegacyHostMigrationPowerShell(
      downloadUrl: "https://rdbk.example/download/a'b/",
      signerSubject: subject,
    );

    expect(script, contains("https://rdbk.example/download/a''b/"));
    expect(script, contains(subject));
    expect(script, contains("'/passive'"));
    expect(script, contains('-Wait -PassThru'));
    expect(script, contains('Get-AuthenticodeSignature'));
    expect(script, contains('System.Windows.MessageBox'));
    expect(script, isNot(contains("'/qn'")));

    final command = buildLegacyHostMigrationCommand(
      downloadUrl:
          'https://rdbk.example/download/${List.filled(600, 'a').join()}/',
      signerSubject: subject,
    );
    final encoded = command.split(' ').last;
    final bytes = base64Decode(encoded);
    final codeUnits = <int>[
      for (var index = 0; index < bytes.length; index += 2)
        bytes[index] | (bytes[index + 1] << 8),
    ];
    expect(String.fromCharCodes(codeUnits), contains('/passive'));
    expect(command.length, lessThan(8191));
  });
}
