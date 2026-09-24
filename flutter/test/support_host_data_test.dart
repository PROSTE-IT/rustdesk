import 'package:flutter_hbb/models/support_address_book_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses local IP addresses reported by a managed host', () {
    final host = SupportHostData.fromJson({
      'local_ip_addresses': ['192.168.10.25', 'fd00::25'],
    });

    expect(host.localIpAddresses, ['192.168.10.25', 'fd00::25']);
  });
}
