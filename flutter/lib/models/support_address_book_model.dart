import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/utils/http_service.dart' as http;

const supportAddressBookApiUrl = String.fromEnvironment('RDBK_API_URL');

class SupportCustomer {
  final String id;
  final String name;
  final String note;
  final int version;

  const SupportCustomer({
    required this.id,
    required this.name,
    required this.note,
    required this.version,
  });

  factory SupportCustomer.fromJson(Map<String, dynamic> json) {
    return SupportCustomer(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      note: json['note']?.toString() ?? '',
      version: json['version'] as int? ?? 1,
    );
  }
}

class SupportDevice {
  final String id;
  final String customerId;
  final String customerName;
  final String rustdeskId;
  final String name;
  final String note;
  final String deviceType;
  final int version;
  bool online;

  SupportDevice({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.rustdeskId,
    required this.name,
    required this.note,
    required this.deviceType,
    required this.version,
    this.online = false,
  });

  factory SupportDevice.fromJson(Map<String, dynamic> json) {
    return SupportDevice(
      id: json['id']?.toString() ?? '',
      customerId: json['customer']?.toString() ?? '',
      customerName: json['customer_name']?.toString() ?? '',
      rustdeskId: json['rustdesk_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      note: json['note']?.toString() ?? '',
      deviceType: json['device_type']?.toString() ?? 'computer',
      version: json['version'] as int? ?? 1,
    );
  }

  Peer toPeer() {
    final peer = Peer(
      id: rustdeskId,
      hash: '',
      password: '',
      username: customerName,
      hostname: deviceType == 'server' ? 'Serwer' : 'Komputer',
      platform: kPeerPlatformWindows,
      alias: name,
      tags: const [],
      forceAlwaysRelay: false,
      rdpPort: '',
      rdpUsername: '',
      loginName: '',
      device_group_name: customerName,
      note: note,
    );
    peer.online = online;
    return peer;
  }
}

class SupportAddressBookException implements Exception {
  final String message;

  const SupportAddressBookException(this.message);

  @override
  String toString() => message;
}

class SupportAddressBookModel with ChangeNotifier {
  static const _onlineEvent = 'callback_query_onlines';
  static const _onlineHandler = 'proste_it_support_address_book';

  String _token = '';
  bool _loading = false;
  bool _onlineHandlerRegistered = false;
  String? _error;
  List<SupportCustomer> _customers = const [];
  List<SupportDevice> _devices = const [];

  bool get isAuthenticated => _token.isNotEmpty;
  bool get loading => _loading;
  String? get error => _error;
  List<SupportCustomer> get customers => _customers;
  List<SupportDevice> get devices => _devices;

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = supportAddressBookApiUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base/$path').replace(queryParameters: query);
  }

  Map<String, String> _headers({bool authenticated = true}) {
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json; charset=utf-8',
      if (authenticated && _token.isNotEmpty) 'Authorization': 'Token $_token',
    };
  }

  dynamic _decode(http.Response response) {
    if (response.bodyBytes.isEmpty) return null;
    return jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
  }

  String _errorMessage(http.Response response, dynamic body) {
    if (body is Map && body['detail'] != null) {
      return body['detail'].toString();
    }
    if (body is Map) {
      return body.entries
          .map((entry) => '${entry.key}: ${entry.value}')
          .join('\n');
    }
    return 'Błąd serwera (${response.statusCode}).';
  }

  dynamic _requireSuccess(http.Response response) {
    final body = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SupportAddressBookException(_errorMessage(response, body));
    }
    return body;
  }

  Future<void> login(String username, String password) async {
    _setLoading(true);
    try {
      final response = await http.post(
        _uri('api/auth/token/'),
        headers: _headers(authenticated: false),
        body: jsonEncode({'username': username, 'password': password}),
      );
      final body = _requireSuccess(response);
      final token = body is Map ? body['token']?.toString() ?? '' : '';
      if (token.isEmpty) {
        throw const SupportAddressBookException(
            'Serwer nie zwrócił tokenu logowania.');
      }
      _token = token;
      _error = null;
      await refresh();
    } catch (error) {
      _error = error.toString();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  void logout() {
    _token = '';
    _customers = const [];
    _devices = const [];
    _error = null;
    notifyListeners();
  }

  Future<void> refresh() async {
    if (!isAuthenticated) return;
    _setLoading(true);
    try {
      final response = await http.get(
        _uri('api/v1/changes/'),
        headers: _headers(),
      );
      final body = _requireSuccess(response);
      if (body is! Map<String, dynamic>) {
        throw const SupportAddressBookException(
            'Serwer zwrócił nieprawidłową odpowiedź.');
      }
      final onlineById = {
        for (final device in _devices) device.rustdeskId: device.online,
      };
      _customers = (body['customers'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .where((item) => item['deleted_at'] == null)
          .map(SupportCustomer.fromJson)
          .toList()
        ..sort((left, right) =>
            left.name.toLowerCase().compareTo(right.name.toLowerCase()));
      final activeCustomers = _customers.map((item) => item.id).toSet();
      _devices = (body['devices'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .where((item) =>
              item['deleted_at'] == null &&
              activeCustomers.contains(item['customer']?.toString()))
          .map(SupportDevice.fromJson)
          .toList();
      for (final device in _devices) {
        device.online = onlineById[device.rustdeskId] ?? false;
      }
      _devices.sort((left, right) =>
          left.name.toLowerCase().compareTo(right.name.toLowerCase()));
      _error = null;
      notifyListeners();
      await queryOnlineStates();
    } catch (error) {
      _error = error.toString();
      notifyListeners();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  List<SupportDevice> devicesFor(String customerId) =>
      _devices.where((device) => device.customerId == customerId).toList();

  Future<SupportCustomer> createCustomer(String name) async {
    final response = await http.post(
      _uri('api/v1/customers/'),
      headers: _headers(),
      body: jsonEncode({'name': name.trim(), 'note': ''}),
    );
    final body = _requireSuccess(response);
    return SupportCustomer.fromJson(Map<String, dynamic>.from(body as Map));
  }

  Future<void> createDevice({
    required String customerId,
    required String rustdeskId,
    required String name,
    required String note,
    required String deviceType,
  }) async {
    final response = await http.post(
      _uri('api/v1/devices/'),
      headers: _headers(),
      body: jsonEncode({
        'customer': customerId,
        'rustdesk_id': rustdeskId.trim(),
        'name': name.trim(),
        'note': note.trim(),
        'device_type': deviceType,
      }),
    );
    _requireSuccess(response);
    await refresh();
  }

  Future<void> updateDevice({
    required SupportDevice device,
    required String customerId,
    required String rustdeskId,
    required String name,
    required String note,
    required String deviceType,
  }) async {
    final response = await http.put(
      _uri('api/v1/devices/${device.id}/'),
      headers: _headers(),
      body: jsonEncode({
        'customer': customerId,
        'rustdesk_id': rustdeskId.trim(),
        'name': name.trim(),
        'note': note.trim(),
        'device_type': deviceType,
        'version': device.version,
      }),
    );
    _requireSuccess(response);
    await refresh();
  }

  Future<void> deleteDevice(SupportDevice device) async {
    final response = await http.delete(
      _uri('api/v1/devices/${device.id}/'),
      headers: _headers(),
    );
    _requireSuccess(response);
    await refresh();
  }

  Future<void> deleteCustomer(SupportCustomer customer) async {
    final response = await http.delete(
      _uri('api/v1/customers/${customer.id}/'),
      headers: _headers(),
    );
    _requireSuccess(response);
    await refresh();
  }

  Future<SupportDevice?> lookup(String rustdeskId) async {
    if (!isAuthenticated) return null;
    final response = await http.get(
      _uri('api/v1/lookup/', {'rustdesk_id': rustdeskId}),
      headers: _headers(),
    );
    final body = _requireSuccess(response);
    if (body is Map && body['exists'] == true && body['device'] is Map) {
      return SupportDevice.fromJson(
          Map<String, dynamic>.from(body['device'] as Map));
    }
    return null;
  }

  void startOnlineTracking() {
    if (_onlineHandlerRegistered) return;
    _onlineHandlerRegistered = platformFFI.registerEventHandler(
      _onlineEvent,
      _onlineHandler,
      (event) async => _updateOnlineStates(event),
    );
  }

  Future<void> queryOnlineStates() async {
    if (_devices.isEmpty) return;
    await bind.queryOnlines(
      ids: _devices.map((device) => device.rustdeskId).toList(growable: false),
    );
  }

  void _updateOnlineStates(Map<String, dynamic> event) {
    final onlines = (event['onlines']?.toString() ?? '')
        .split(',')
        .where((id) => id.isNotEmpty)
        .toSet();
    final offlines = (event['offlines']?.toString() ?? '')
        .split(',')
        .where((id) => id.isNotEmpty)
        .toSet();
    var changed = false;
    for (final device in _devices) {
      final previous = device.online;
      if (onlines.contains(device.rustdeskId)) {
        device.online = true;
      } else if (offlines.contains(device.rustdeskId)) {
        device.online = false;
      }
      changed = changed || previous != device.online;
    }
    if (changed) notifyListeners();
  }

  void _setLoading(bool value) {
    if (_loading == value) return;
    _loading = value;
    notifyListeners();
  }
}

final supportAddressBookModel = SupportAddressBookModel();
