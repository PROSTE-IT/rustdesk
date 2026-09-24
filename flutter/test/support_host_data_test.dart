import 'package:flutter_hbb/models/support_address_book_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
}
