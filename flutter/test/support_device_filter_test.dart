import 'package:flutter_hbb/models/support_device_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  bool matches(
    Set<SupportDeviceFilter> filters, {
    bool online = false,
    bool isServer = false,
    bool isShared = false,
    bool needsAttention = false,
  }) =>
      matchesSupportDeviceFilters(
        filters: filters,
        online: online,
        isServer: isServer,
        isShared: isShared,
        needsAttention: needsAttention,
      );

  test('empty selection means all devices', () {
    expect(matches(const {}), isTrue);
  });

  test('status and type groups are combined with AND', () {
    const filters = {
      SupportDeviceFilter.online,
      SupportDeviceFilter.servers,
    };

    expect(matches(filters, online: true, isServer: true), isTrue);
    expect(matches(filters, online: false, isServer: true), isFalse);
    expect(matches(filters, online: true, isServer: false), isFalse);
  });

  test('choices inside one group are combined with OR', () {
    const filters = {
      SupportDeviceFilter.servers,
      SupportDeviceFilter.shared,
    };

    expect(matches(filters, isServer: true), isTrue);
    expect(matches(filters, isShared: true), isTrue);
    expect(matches(filters), isFalse);
  });

  test('attention is combined with selected status', () {
    const filters = {
      SupportDeviceFilter.attention,
      SupportDeviceFilter.online,
    };

    expect(matches(filters, online: true, needsAttention: true), isTrue);
    expect(matches(filters, online: true), isFalse);
  });
}
