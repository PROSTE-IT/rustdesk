import 'package:flutter_hbb/models/support_address_book_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  SupportDevice device({
    bool online = false,
    String deviceType = 'computer',
    bool shared = false,
    bool attention = false,
  }) {
    final item = SupportDevice.fromJson({
      'device_type': deviceType,
      'is_shared': shared,
      if (attention) 'host_health': {'cpu_alert': true},
    });
    item.online = online;
    return item;
  }

  test('empty device filter selection means all devices', () {
    expect(
      matchesSupportDeviceFilters(device(), const <SupportDeviceFilter>{}),
      isTrue,
    );
  });

  test('device filters combine status and type groups with AND', () {
    const filters = {
      SupportDeviceFilter.online,
      SupportDeviceFilter.servers,
    };

    expect(
      matchesSupportDeviceFilters(
        device(online: true, deviceType: 'server'),
        filters,
      ),
      isTrue,
    );
    expect(
      matchesSupportDeviceFilters(
        device(online: false, deviceType: 'server'),
        filters,
      ),
      isFalse,
    );
    expect(
      matchesSupportDeviceFilters(device(online: true), filters),
      isFalse,
    );
  });

  test('device filters combine choices inside one group with OR', () {
    const filters = {
      SupportDeviceFilter.servers,
      SupportDeviceFilter.shared,
    };

    expect(
      matchesSupportDeviceFilters(device(deviceType: 'server'), filters),
      isTrue,
    );
    expect(
      matchesSupportDeviceFilters(device(shared: true), filters),
      isTrue,
    );
    expect(matchesSupportDeviceFilters(device(), filters), isFalse);
  });

  test('attention filter is combined with selected status', () {
    const filters = {
      SupportDeviceFilter.attention,
      SupportDeviceFilter.online,
    };

    expect(
      matchesSupportDeviceFilters(
        device(online: true, attention: true),
        filters,
      ),
      isTrue,
    );
    expect(
      matchesSupportDeviceFilters(device(online: true), filters),
      isFalse,
    );
  });

  test('parses local IP addresses reported by a managed host', () {
    final host = SupportHostData.fromJson({
      'local_ip_addresses': ['192.168.10.25', 'fd00::25'],
    });

    expect(host.localIpAddresses, ['192.168.10.25', 'fd00::25']);
  });

  test('pending reboot alone does not require attention', () {
    final health = SupportHostHealth.fromJson({
      'pending_reboot': true,
      'critical_alert': false,
      'requires_attention': false,
    });

    expect(health.pendingReboot, isTrue);
    expect(health.hasAlert, isFalse);
  });

  test('parses hardware specification used by the device card', () {
    final health = SupportHostHealth.fromJson({
      'cpu_name': 'Intel Xeon E5-2690',
      'cpu_logical_count': 16,
      'memory_total_bytes': 32 * 1024 * 1024 * 1024,
      'local_ip_addresses': ['192.168.10.25', '10.0.0.25'],
      'latest_disks': [
        {
          'name': 'C:',
          'total_bytes': 512 * 1024 * 1024 * 1024,
          'free_bytes': 128 * 1024 * 1024 * 1024,
          'used_percent': 75,
        },
      ],
    });

    expect(health.cpuName, 'Intel Xeon E5-2690');
    expect(health.cpuLogicalCount, 16);
    expect(health.memoryTotalBytes, 32 * 1024 * 1024 * 1024);
    expect(health.localIpAddresses, ['192.168.10.25', '10.0.0.25']);
    expect(
      health.latestDisks.single['total_bytes'],
      512 * 1024 * 1024 * 1024,
    );
  });

  test('critical older than 24 hours does not require attention', () {
    final occurredAt = DateTime.now()
        .toUtc()
        .subtract(const Duration(hours: 25))
        .toIso8601String();
    final health = SupportHostHealth.fromJson({
      'last_critical_at': occurredAt,
    });

    expect(health.criticalUnacknowledged, isTrue);
    expect(health.criticalAlert, isFalse);
    expect(health.hasAlert, isFalse);
  });

  test('recent critical and resource alerts require attention', () {
    final occurredAt = DateTime.now()
        .toUtc()
        .subtract(const Duration(hours: 2))
        .toIso8601String();
    final recentCritical = SupportHostHealth.fromJson({
      'last_critical_at': occurredAt,
    });
    final resourceAlert = SupportHostHealth.fromJson({
      'cpu_alert': true,
    });

    expect(recentCritical.criticalAlert, isTrue);
    expect(recentCritical.hasAlert, isTrue);
    expect(resourceAlert.hasAlert, isTrue);
  });

  test('parses both Helpdesk installer formats for host migration', () {
    final update = SupportClientUpdate.fromJson({
      'channel': 'windows_helpdesk',
      'build_uuid': '11111111-1111-1111-1111-111111111111',
      'version': '1.4.9-pit.21',
      'installers': {
        'exe': {
          'filename': 'proste_IT_Helpdesk.exe',
          'size': 24000000,
          'download_url': 'https://rdbk.example/helpdesk.exe',
        },
        'msi': {
          'filename': 'proste_IT_Helpdesk.msi',
          'size': 25000000,
          'download_url': 'https://rdbk.example/helpdesk.msi',
        },
      },
    });

    expect(update.exeInstaller?.filename, 'proste_IT_Helpdesk.exe');
    expect(update.exeInstaller?.size, 24000000);
    expect(update.msiInstaller?.filename, 'proste_IT_Helpdesk.msi');
    expect(update.msiInstaller?.size, 25000000);
  });

  test('parses the staged migration plan returned by RDBK', () {
    final dispatch = SupportLegacyMigrationDispatch.fromJson({
      'id': '22222222-2222-2222-2222-222222222222',
      'migration_script_url': 'https://rdbk.example/legacy.ps1',
      'staged_migration_script_url': 'https://rdbk.example/legacy.ps1?staged=1',
      'verification_url': 'https://rdbk.example/status',
    });

    expect(dispatch.attemptId, '22222222-2222-2222-2222-222222222222');
    expect(dispatch.stagedMigrationScriptUrl, contains('staged=1'));
  });
}
