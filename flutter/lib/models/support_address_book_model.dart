import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/support_secure_storage.dart';
import 'package:flutter_hbb/utils/http_service.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:uuid/uuid.dart';

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
  final String hostname;
  final String remoteUsername;
  final String platform;
  final String rustdeskVersion;
  final int? displayCount;
  final DateTime? lastSeen;
  final DateTime? lastConnectedAt;
  final String lastConnectedByName;
  final bool isCritical;
  final String warning;
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
    required this.hostname,
    required this.remoteUsername,
    required this.platform,
    required this.rustdeskVersion,
    required this.displayCount,
    required this.lastSeen,
    required this.lastConnectedAt,
    required this.lastConnectedByName,
    required this.isCritical,
    required this.warning,
    this.online = false,
  });

  factory SupportDevice.fromJson(Map<String, dynamic> json) {
    DateTime? date(String key) => DateTime.tryParse(json[key]?.toString() ?? '');
    return SupportDevice(
      id: json['id']?.toString() ?? '',
      customerId: json['customer']?.toString() ?? '',
      customerName: json['customer_name']?.toString() ?? '',
      rustdeskId: json['rustdesk_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      note: json['note']?.toString() ?? '',
      deviceType: json['device_type']?.toString() ?? 'computer',
      version: json['version'] as int? ?? 1,
      hostname: json['hostname']?.toString() ?? '',
      remoteUsername: json['remote_username']?.toString() ?? '',
      platform: json['platform']?.toString() ?? '',
      rustdeskVersion: json['rustdesk_version']?.toString() ?? '',
      displayCount: json['display_count'] as int?,
      lastSeen: date('last_seen'),
      lastConnectedAt: date('last_connected_at'),
      lastConnectedByName: json['last_connected_by_name']?.toString() ?? '',
      isCritical: json['is_critical'] == true,
      warning: json['warning']?.toString() ?? '',
    );
  }

  Peer toPeer() {
    final peer = Peer(
      id: rustdeskId,
      hash: '',
      password: '',
      username: customerName,
      hostname: deviceType == 'server' ? 'Serwer' : 'Komputer',
      platform: platform.isEmpty ? 'Windows' : platform,
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

class SupportTechnician {
  final String id;
  final String username;
  final String displayName;

  const SupportTechnician({
    required this.id,
    required this.username,
    required this.displayName,
  });

  factory SupportTechnician.fromJson(Map<String, dynamic> json) =>
      SupportTechnician(
        id: json['id']?.toString() ?? '',
        username: json['username']?.toString() ?? '',
        displayName: json['display_name']?.toString() ?? '',
      );
}

class SupportSessionSummary {
  final String id;
  final String rustdeskId;
  final SupportTechnician? technician;
  final String technicianDeviceName;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final String outcome;
  final String note;
  final bool active;

  const SupportSessionSummary({
    required this.id,
    required this.rustdeskId,
    required this.technician,
    required this.technicianDeviceName,
    required this.startedAt,
    required this.endedAt,
    required this.outcome,
    required this.note,
    required this.active,
  });

  factory SupportSessionSummary.fromJson(Map<String, dynamic> json) {
    final technician = json['technician'];
    return SupportSessionSummary(
      id: json['id']?.toString() ?? '',
      rustdeskId: json['rustdesk_id']?.toString() ?? '',
      technician: technician is Map
          ? SupportTechnician.fromJson(Map<String, dynamic>.from(technician))
          : null,
      technicianDeviceName:
          json['technician_device_name']?.toString() ?? '',
      startedAt: DateTime.tryParse(json['started_at']?.toString() ?? ''),
      endedAt: DateTime.tryParse(json['ended_at']?.toString() ?? ''),
      outcome: json['outcome']?.toString() ?? '',
      note: json['note']?.toString() ?? '',
      active: json['active'] == true,
    );
  }
}

class SupportDeviceCardData {
  final SupportDevice device;
  final List<SupportSessionSummary> activeSessions;
  final List<SupportSessionSummary> sessions;

  const SupportDeviceCardData({
    required this.device,
    required this.activeSessions,
    required this.sessions,
  });
}

class SupportPresence {
  final List<SupportSessionSummary> sessions;

  const SupportPresence(this.sessions);

  bool get occupied => sessions.isNotEmpty;
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
  static const _queueLimit = 1000;

  final List<Map<String, dynamic>> _eventQueue = [];
  Future<void> _queueWrite = Future.value();
  final Uuid _uuid = const Uuid();
  Future<void>? _initializing;
  bool _initialized = false;
  bool _flushing = false;
  String _installationId = '';
  String _token = '';
  String _tokenType = 'Device';
  SupportTechnician? _technician;
  bool _loading = false;
  bool _onlineHandlerRegistered = false;
  String? _error;
  Timer? _retryTimer;
  List<SupportCustomer> _customers = const [];
  List<SupportDevice> _devices = const [];

  bool get enabled => supportAddressBookApiUrl.trim().isNotEmpty;
  bool get initialized => _initialized;
  bool get isAuthenticated => enabled && _token.isNotEmpty;
  bool get loading => _loading;
  String? get error => _error;
  SupportTechnician? get technician => _technician;
  List<SupportCustomer> get customers => _customers;
  List<SupportDevice> get devices => _devices;

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = supportAddressBookApiUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base/$path').replace(queryParameters: query);
  }

  Map<String, String> _headers({bool authenticated = true}) => {
        'Accept': 'application/json',
        'Content-Type': 'application/json; charset=utf-8',
        if (authenticated && _token.isNotEmpty)
          'Authorization': '$_tokenType $_token',
      };

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
      if (response.statusCode == 401) {
        unawaited(_clearAuthentication(clearQueue: true));
      }
      throw SupportAddressBookException(_errorMessage(response, body));
    }
    return body;
  }

  Future<void> ensureInitialized() {
    if (!enabled || _initialized) return Future.value();
    return _initializing ??= _initialize();
  }

  Future<void> _initialize() async {
    try {
      _installationId = await readOrCreateSupportInstallationId();
      _eventQueue
        ..clear()
        ..addAll(await readSupportEventQueue());
      final savedToken = await readSupportDeviceToken();
      if (savedToken != null && savedToken.isNotEmpty) {
        _token = savedToken;
        try {
          final response = await http.get(
            _uri('api/auth/device/me/'),
            headers: _headers(),
          ).timeout(const Duration(seconds: 3));
          final body = _requireSuccess(response);
          if (body is Map && body['technician'] is Map) {
            _technician = SupportTechnician.fromJson(
              Map<String, dynamic>.from(body['technician'] as Map),
            );
          }
          _startRetryTimer();
          unawaited(flushEventQueue());
        } catch (error) {
          if (_token.isNotEmpty) _error = error.toString();
        }
      }
    } finally {
      _initialized = true;
      notifyListeners();
    }
  }

  Future<void> login(String username, String password) async {
    if (!enabled) return;
    await ensureInitialized();
    _setLoading(true);
    try {
      final info = await PackageInfo.fromPlatform();
      final response = await http.post(
        _uri('api/auth/device/login/'),
        headers: _headers(authenticated: false),
        body: jsonEncode({
          'username': username,
          'password': password,
          'installation_id': _installationId,
          'machine_name': supportMachineName(),
          'os_username': supportOsUsername(),
          'client_version': info.version,
        }),
      );
      final body = _requireSuccess(response);
      final token = body is Map ? body['token']?.toString() ?? '' : '';
      if (token.isEmpty) {
        throw const SupportAddressBookException(
            'Serwer nie zwrócił tokenu logowania.');
      }
      _token = token;
      _tokenType = body is Map
          ? body['token_type']?.toString() ?? 'Device'
          : 'Device';
      if (body is Map && body['technician'] is Map) {
        _technician = SupportTechnician.fromJson(
          Map<String, dynamic>.from(body['technician'] as Map),
        );
      }
      await writeSupportDeviceToken(_token);
      _error = null;
      _startRetryTimer();
      await flushEventQueue();
      await refresh();
    } catch (error) {
      _error = error.toString();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> logout() async {
    await ensureInitialized();
    if (_token.isNotEmpty) {
      try {
        await http.post(
          _uri('api/auth/device/logout/'),
          headers: _headers(),
        );
      } catch (error) {
        debugPrint('Support device logout request failed: $error');
      }
    }
    await _clearAuthentication(clearQueue: true);
  }

  Future<void> _clearAuthentication({required bool clearQueue}) async {
    _token = '';
    _tokenType = 'Device';
    _technician = null;
    _customers = const [];
    _devices = const [];
    _retryTimer?.cancel();
    _retryTimer = null;
    await deleteSupportDeviceToken();
    if (clearQueue) {
      _eventQueue.clear();
      await _persistEventQueue();
    }
    notifyListeners();
  }

  void _startRetryTimer() {
    _retryTimer ??= Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(flushEventQueue()),
    );
  }

  Future<void> refresh() async {
    await ensureInitialized();
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
    await ensureInitialized();
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

  Future<SupportDeviceCardData> deviceCard(String deviceId) async {
    final response = await http.get(
      _uri('api/v1/devices/$deviceId/card/'),
      headers: _headers(),
    );
    final body = _requireSuccess(response);
    if (body is! Map || body['device'] is! Map) {
      throw const SupportAddressBookException(
          'Serwer zwrócił nieprawidłową kartę urządzenia.');
    }
    List<SupportSessionSummary> sessions(String key) =>
        (body[key] as List? ?? const [])
            .whereType<Map>()
            .map((item) => SupportSessionSummary.fromJson(
                Map<String, dynamic>.from(item)))
            .toList();
    return SupportDeviceCardData(
      device: SupportDevice.fromJson(
          Map<String, dynamic>.from(body['device'] as Map)),
      activeSessions: sessions('active_sessions'),
      sessions: sessions('sessions'),
    );
  }

  Future<SupportPresence> presence(String rustdeskId) async {
    await ensureInitialized();
    if (!isAuthenticated) return const SupportPresence([]);
    final response = await http.get(
      _uri('api/v1/sessions/presence/', {'rustdesk_id': rustdeskId}),
      headers: _headers(),
    );
    final body = _requireSuccess(response);
    final sessions = body is Map ? body['sessions'] as List? : null;
    final currentTechnicianId = _technician?.id;
    return SupportPresence(
      (sessions ?? const [])
          .whereType<Map>()
          .map((item) => SupportSessionSummary.fromJson(
              Map<String, dynamic>.from(item)))
          .where((item) => item.technician?.id != currentTechnicianId)
          .toList(),
    );
  }

  Future<String?> startSupportSession(
    String rustdeskId,
    Map<String, dynamic> telemetry,
  ) async {
    await ensureInitialized();
    if (!isAuthenticated) return null;
    final sessionId = _uuid.v4();
    await _enqueueEvent({
      'event_id': _uuid.v4(),
      'kind': 'start',
      'session_id': sessionId,
      'payload': {
        'session_id': sessionId,
        'rustdesk_id': rustdeskId,
        'started_at': DateTime.now().toUtc().toIso8601String(),
        ...telemetry,
      },
    });
    unawaited(flushEventQueue());
    return sessionId;
  }

  Future<void> heartbeatSupportSession(
    String sessionId,
    Map<String, dynamic> telemetry,
  ) async {
    if (!isAuthenticated) return;
    _eventQueue.removeWhere((event) =>
        event['kind'] == 'heartbeat' && event['session_id'] == sessionId);
    await _enqueueEvent({
      'event_id': _uuid.v4(),
      'kind': 'heartbeat',
      'session_id': sessionId,
      'payload': {
        'occurred_at': DateTime.now().toUtc().toIso8601String(),
        ...telemetry,
      },
    });
    unawaited(flushEventQueue());
  }

  Future<void> endSupportSession(
    String sessionId,
    Map<String, dynamic> telemetry, {
    String reason = 'disconnected',
  }) async {
    if (!isAuthenticated) return;
    _eventQueue.removeWhere((event) =>
        event['kind'] == 'heartbeat' && event['session_id'] == sessionId);
    await _enqueueEvent({
      'event_id': _uuid.v4(),
      'kind': 'end',
      'session_id': sessionId,
      'payload': {
        'ended_at': DateTime.now().toUtc().toIso8601String(),
        'end_reason': reason,
        ...telemetry,
      },
    });
    unawaited(flushEventQueue());
  }

  Future<void> updateSupportSessionResult(
    String sessionId, {
    required String outcome,
    required String note,
    required String ticketReference,
  }) async {
    final normalizedNote = note.trim();
    final normalizedTicketReference = ticketReference.trim();
    final safeNote = normalizedNote.length > 4000
        ? normalizedNote.substring(0, 4000)
        : normalizedNote;
    final safeTicketReference = normalizedTicketReference.length > 100
        ? normalizedTicketReference.substring(0, 100)
        : normalizedTicketReference;
    if (!isAuthenticated) return;
    await _enqueueEvent({
      'event_id': _uuid.v4(),
      'kind': 'end',
      'session_id': sessionId,
      'payload': {
        'outcome': outcome,
        'note': safeNote,
        'ticket_reference': safeTicketReference,
      },
    });
    unawaited(flushEventQueue());
  }

  Future<void> _persistEventQueue() {
    final snapshot = _eventQueue
        .map((event) => Map<String, dynamic>.from(event))
        .toList(growable: false);
    _queueWrite = _queueWrite
        .catchError((_) {})
        .then((_) => writeSupportEventQueue(snapshot));
    return _queueWrite;
  }

  Future<void> _enqueueEvent(Map<String, dynamic> event) async {
    _eventQueue.add(event);
    if (_eventQueue.length > _queueLimit) {
      _eventQueue.removeRange(0, _eventQueue.length - _queueLimit);
    }
    await _persistEventQueue();
  }

  Future<void> _removeProcessedEvent(Map<String, dynamic> processedEvent) async {
    final processedId = processedEvent['event_id']?.toString() ?? '';
    if (processedId.isEmpty) {
      _eventQueue.remove(processedEvent);
    } else {
      _eventQueue.removeWhere(
        (event) => event['event_id']?.toString() == processedId,
      );
    }
    await _persistEventQueue();
  }

  Future<void> flushEventQueue() async {
    if (_flushing || !isAuthenticated || _eventQueue.isEmpty) return;
    _flushing = true;
    try {
      while (isAuthenticated && _eventQueue.isNotEmpty) {
        final event = _eventQueue.first;
        final processedEventId = event['event_id']?.toString() ?? '';
        final kind = event['kind']?.toString() ?? '';
        final sessionId = event['session_id']?.toString() ?? '';
        final payload = event['payload'];
        late http.Response response;
        try {
          if (kind == 'start') {
            response = await http.post(
              _uri('api/v1/sessions/start/'),
              headers: _headers(),
              body: jsonEncode(payload),
            ).timeout(const Duration(seconds: 10));
          } else if (kind == 'heartbeat') {
            response = await http.post(
              _uri('api/v1/sessions/$sessionId/heartbeat/'),
              headers: _headers(),
              body: jsonEncode(payload),
            ).timeout(const Duration(seconds: 10));
          } else if (kind == 'end') {
            response = await http.post(
              _uri('api/v1/sessions/$sessionId/end/'),
              headers: _headers(),
              body: jsonEncode(payload),
            ).timeout(const Duration(seconds: 10));
          } else {
            await _removeProcessedEvent(event);
            continue;
          }
        } catch (error) {
          debugPrint('Support event queue is offline: $error');
          break;
        }
        if (response.statusCode >= 200 && response.statusCode < 300) {
          await _removeProcessedEvent(event);
          continue;
        }
        if (response.statusCode == 401) {
          await _clearAuthentication(clearQueue: true);
          break;
        }
        if (response.statusCode >= 500) break;
        debugPrint(
            'Dropping rejected support event $kind/$processedEventId (${response.statusCode}).');
        await _removeProcessedEvent(event);
      }
    } finally {
      _flushing = false;
    }
  }

  void startOnlineTracking() {
    if (!enabled || _onlineHandlerRegistered) return;
    _onlineHandlerRegistered = platformFFI.registerEventHandler(
      _onlineEvent,
      _onlineHandler,
      (event) async => _updateOnlineStates(event),
    );
  }

  Future<void> queryOnlineStates() async {
    if (!enabled || _devices.isEmpty) return;
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
    if (onlines.isNotEmpty && isAuthenticated) {
      unawaited(_markDevicesOnline(onlines.toList()));
    }
  }


  Future<void> _markDevicesOnline(List<String> rustdeskIds) async {
    try {
      final response = await http.post(
        _uri('api/v1/devices/online/'),
        headers: _headers(),
        body: jsonEncode({'rustdesk_ids': rustdeskIds}),
      );
      _requireSuccess(response);
    } catch (error) {
      debugPrint('Failed to update RDBK online timestamps: $error');
    }
  }
  void _setLoading(bool value) {
    if (_loading == value) return;
    _loading = value;
    notifyListeners();
  }
}

final supportAddressBookModel = SupportAddressBookModel();
