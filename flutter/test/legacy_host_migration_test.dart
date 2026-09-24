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

  test('builds a short command for an already transferred migration plan', () {
    final command = buildLegacyHostMigrationCommand(
      remoteScriptPath:
          r'C:\Users\Public\Documents\PROSTEIT-HostMigration-123.ps1',
    );
    expect(command, contains('-File "'));
    expect(command, contains('PROSTEIT-HostMigration-123.ps1'));
    expect(command, isNot(contains('Invoke-WebRequest')));
    expect(command, isNot(contains('-EncodedCommand')));
    expect(command.length, lessThan(256));
  });
}
