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
const clientVariant = String.fromEnvironment('CLIENT_VARIANT');
const isQuickSupportBuild = clientVariant == 'quick_support';
const supportClientUpdateChannel =
    String.fromEnvironment('RDBK_UPDATE_CHANNEL');
const managedWindowsUpdateChannels = {
  'windows_support',
  'windows_helpdesk',
};
const supportClientBuildUuid = String.fromEnvironment('RDBK_BUILD_UUID');
const supportClientBuildRunId = int.fromEnvironment('RDBK_BUILD_RUN_ID');
const supportClientVersion = String.fromEnvironment('RDBK_APP_VERSION');
const supportWindowsSignerSubject =
    String.fromEnvironment('RDBK_WINDOWS_SIGNER_SUBJECT');
const _supportTechnicianDisplayNameOption = 'proste-it-technician-display-name';

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
  final bool? isHeadless;
  final bool? isInstalled;
  final int? displayWidth;
  final int? displayHeight;
  final DateTime? lastSeen;
  final DateTime? lastConnectedAt;
  final String lastConnectedByName;
  final bool isCritical;
  final String warning;
  final bool isShared;
  final SupportHostHealth? hostHealth;
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
    required this.isHeadless,
    required this.isInstalled,
    required this.displayWidth,
    required this.displayHeight,
    required this.lastSeen,
    required this.lastConnectedAt,
    required this.lastConnectedByName,
    required this.isCritical,
    required this.warning,
    required this.isShared,
    required this.hostHealth,
    this.online = false,
  });

  factory SupportDevice.fromJson(Map<String, dynamic> json) {
    DateTime? date(String key) =>
        DateTime.tryParse(json[key]?.toString() ?? '');
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
      isHeadless: json['is_headless'] as bool?,
      isInstalled: json['is_installed'] as bool?,
      displayWidth: json['display_width'] as int?,
      displayHeight: json['display_height'] as int?,
      lastSeen: date('last_seen'),
      lastConnectedAt: date('last_connected_at'),
      lastConnectedByName: json['last_connected_by_name']?.toString() ?? '',
      isCritical: json['is_critical'] == true,
      warning: json['warning']?.toString() ?? '',
      isShared: json['is_shared'] == true,
      hostHealth: json['host_health'] is Map
          ? SupportHostHealth.fromJson(
              Map<String, dynamic>.from(json['host_health'] as Map))
          : null,
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

double? _supportDouble(dynamic value) =>
    value == null ? null : double.tryParse(value.toString());

class SupportHostHealth {
  final double? cpuHourAverage;
  final double? memoryHourAverage;
  final bool cpuAlert;
  final bool memoryAlert;
  final List<String> diskAlerts;
  final List<Map<String, dynamic>> latestDisks;
  final bool pendingReboot;
  final DateTime? lastCriticalAt;
  final String lastCriticalSource;
  final int? lastCriticalEventId;
  final DateTime? criticalAcknowledgedAt;
  final DateTime? metricsUpdatedAt;

  const SupportHostHealth({
    required this.cpuHourAverage,
    required this.memoryHourAverage,
    required this.cpuAlert,
    required this.memoryAlert,
    required this.diskAlerts,
    required this.latestDisks,
    required this.pendingReboot,
    required this.lastCriticalAt,
    required this.lastCriticalSource,
    required this.lastCriticalEventId,
    required this.criticalAcknowledgedAt,
    required this.metricsUpdatedAt,
  });

  factory SupportHostHealth.fromJson(Map<String, dynamic> json) =>
      SupportHostHealth(
        cpuHourAverage: _supportDouble(json['cpu_hour_average']),
        memoryHourAverage: _supportDouble(json['memory_hour_average']),
        cpuAlert: json['cpu_alert'] == true,
        memoryAlert: json['memory_alert'] == true,
        diskAlerts: (json['disk_alerts'] as List? ?? const [])
            .map((item) => item.toString())
            .toList(),
        latestDisks: (json['latest_disks'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(),
        pendingReboot: json['pending_reboot'] == true,
        lastCriticalAt:
            DateTime.tryParse(json['last_critical_at']?.toString() ?? ''),
        lastCriticalSource: json['last_critical_source']?.toString() ?? '',
        lastCriticalEventId:
            int.tryParse(json['last_critical_event_id']?.toString() ?? ''),
        criticalAcknowledgedAt: DateTime.tryParse(
            json['critical_acknowledged_at']?.toString() ?? ''),
        metricsUpdatedAt:
            DateTime.tryParse(json['metrics_updated_at']?.toString() ?? ''),
      );

  bool get criticalUnacknowledged =>
      lastCriticalAt != null &&
      (criticalAcknowledgedAt == null ||
          criticalAcknowledgedAt!.isBefore(lastCriticalAt!));

  bool get hasAlert =>
      cpuAlert ||
      memoryAlert ||
      diskAlerts.isNotEmpty ||
      pendingReboot ||
      criticalUnacknowledged;
}

class SupportHostMetric {
  final DateTime? capturedAt;
  final double cpuAverage;
  final double cpuMaximum;
  final double memoryAverage;
  final double memoryMaximum;
  final List<Map<String, dynamic>> disks;

  const SupportHostMetric({
    required this.capturedAt,
    required this.cpuAverage,
    required this.cpuMaximum,
    required this.memoryAverage,
    required this.memoryMaximum,
    required this.disks,
  });

  factory SupportHostMetric.fromJson(Map<String, dynamic> json) =>
      SupportHostMetric(
        capturedAt: DateTime.tryParse(json['captured_at']?.toString() ?? ''),
        cpuAverage: _supportDouble(json['cpu_average_percent']) ?? 0,
        cpuMaximum: _supportDouble(json['cpu_maximum_percent']) ?? 0,
        memoryAverage: _supportDouble(json['memory_average_percent']) ?? 0,
        memoryMaximum: _supportDouble(json['memory_maximum_percent']) ?? 0,
        disks: (json['disks'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(),
      );
}

class SupportHostUser {
  final String identity;
  final String displayName;
  final DateTime? lastSeen;
  final int activeDayCount;
  final bool technical;

  const SupportHostUser({
    required this.identity,
    required this.displayName,
    required this.lastSeen,
    required this.activeDayCount,
    required this.technical,
  });

  factory SupportHostUser.fromJson(Map<String, dynamic> json) =>
      SupportHostUser(
        identity: json['normalized_identity']?.toString() ?? '',
        displayName: json['display_name']?.toString() ?? '',
        lastSeen: DateTime.tryParse(json['last_seen']?.toString() ?? ''),
        activeDayCount: (json['active_days'] as List? ?? const []).length,
        technical: json['ignored_as_technical'] == true,
      );
}

class SupportAutomationProposal {
  final String kind;
  final String status;
  final String value;
  final String customerName;
  final int confirmationCount;
  final DateTime? executeAfter;

  const SupportAutomationProposal({
    required this.kind,
    required this.status,
    required this.value,
    required this.customerName,
    required this.confirmationCount,
    required this.executeAfter,
  });

  factory SupportAutomationProposal.fromJson(Map<String, dynamic> json) =>
      SupportAutomationProposal(
        kind: json['kind']?.toString() ?? '',
        status: json['status']?.toString() ?? '',
        value: json['proposed_value']?.toString() ?? '',
        customerName: json['customer_name']?.toString() ?? '',
        confirmationCount:
            int.tryParse(json['confirmation_count']?.toString() ?? '') ?? 0,
        executeAfter:
            DateTime.tryParse(json['execute_after']?.toString() ?? ''),
      );

  bool get active => status == 'observing' || status == 'scheduled';
}

class SupportHostData {
  final String state;
  final String hostname;
  final String username;
  final String osName;
  final String osVersion;
  final String cpuName;
  final int? cpuLogicalCount;
  final int? memoryTotalBytes;
  final List<String> localIpAddresses;
  final String clientVersion;
  final bool pendingReboot;
  final List<SupportHostMetric> metrics;
  final List<SupportHostUser> users;
  final List<SupportAutomationProposal> proposals;

  const SupportHostData({
    required this.state,
    required this.hostname,
    required this.username,
    required this.osName,
    required this.osVersion,
    required this.cpuName,
    required this.cpuLogicalCount,
    required this.memoryTotalBytes,
    required this.localIpAddresses,
    required this.clientVersion,
    required this.pendingReboot,
    required this.metrics,
    required this.users,
    required this.proposals,
  });

  factory SupportHostData.fromJson(Map<String, dynamic> json) =>
      SupportHostData(
        state: json['state']?.toString() ?? '',
        hostname: json['hostname']?.toString() ?? '',
        username: json['username']?.toString() ?? '',
        osName: json['os_name']?.toString() ?? '',
        osVersion: json['os_version']?.toString() ?? '',
        cpuName: json['cpu_name']?.toString() ?? '',
        cpuLogicalCount:
            int.tryParse(json['cpu_logical_count']?.toString() ?? ''),
        memoryTotalBytes:
            int.tryParse(json['memory_total_bytes']?.toString() ?? ''),
        localIpAddresses: (json['local_ip_addresses'] as List? ?? const [])
            .map((item) => item.toString())
            .where((item) => item.isNotEmpty)
            .toList(),
        clientVersion: json['client_version']?.toString() ?? '',
        pendingReboot: json['pending_reboot'] == true,
        metrics: (json['metrics'] as List? ?? const [])
            .whereType<Map>()
            .map((item) =>
                SupportHostMetric.fromJson(Map<String, dynamic>.from(item)))
            .toList(),
        users: (json['users'] as List? ?? const [])
            .whereType<Map>()
            .map((item) =>
                SupportHostUser.fromJson(Map<String, dynamic>.from(item)))
            .toList(),
        proposals: (json['proposals'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => SupportAutomationProposal.fromJson(
                Map<String, dynamic>.from(item)))
            .toList(),
      );
}

class SupportTechnician {
  final String id;
  final String username;
  final String displayName;
  final bool canCloseSupportSessions;

  const SupportTechnician({
    required this.id,
    required this.username,
    required this.displayName,
    required this.canCloseSupportSessions,
  });

  factory SupportTechnician.fromJson(Map<String, dynamic> json) =>
      SupportTechnician(
        id: json['id']?.toString() ?? '',
        username: json['username']?.toString() ?? '',
        displayName: json['display_name']?.toString() ?? '',
        canCloseSupportSessions: json['can_close_support_sessions'] == true,
      );
}

class SupportSessionSummary {
  final String id;
  final String rustdeskId;
  final String customerName;
  final String deviceName;
  final SupportTechnician? technician;
  final String technicianDeviceName;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final String outcome;
  final String note;
  final bool active;
  final bool activityActive;
  final DateTime? lastActivityAt;
  final int durationSeconds;

  const SupportSessionSummary({
    required this.id,
    required this.rustdeskId,
    required this.customerName,
    required this.deviceName,
    required this.technician,
    required this.technicianDeviceName,
    required this.startedAt,
    required this.endedAt,
    required this.outcome,
    required this.note,
    required this.active,
    required this.activityActive,
    required this.lastActivityAt,
    required this.durationSeconds,
  });

  factory SupportSessionSummary.fromJson(Map<String, dynamic> json) {
    final technician = json['technician'];
    return SupportSessionSummary(
      id: json['id']?.toString() ?? '',
      rustdeskId: json['rustdesk_id']?.toString() ?? '',
      customerName: json['customer_name']?.toString() ?? '',
      deviceName: json['device_name']?.toString() ?? '',
      technician: technician is Map
          ? SupportTechnician.fromJson(Map<String, dynamic>.from(technician))
          : null,
      technicianDeviceName: json['technician_device_name']?.toString() ?? '',
      startedAt: DateTime.tryParse(json['started_at']?.toString() ?? ''),
      endedAt: DateTime.tryParse(json['ended_at']?.toString() ?? ''),
      outcome: json['outcome']?.toString() ?? '',
      note: json['note']?.toString() ?? '',
      active: json['active'] == true,
      activityActive: json['activity_active'] == true,
      lastActivityAt:
          DateTime.tryParse(json['last_activity_at']?.toString() ?? ''),
      durationSeconds: json['duration_seconds'] as int? ?? 0,
    );
  }
}

class SupportSessionHandle {
  final String id;
  final DateTime startedAt;

  const SupportSessionHandle({required this.id, required this.startedAt});
}

class SupportPostSessionPrompt {
  final String id;
  final String rustdeskId;
  final String? supportSessionId;
  final DateTime startedAt;
  final DateTime endedAt;
  final Map<String, dynamic> telemetry;

  const SupportPostSessionPrompt({
    required this.id,
    required this.rustdeskId,
    required this.supportSessionId,
    required this.startedAt,
    required this.endedAt,
    required this.telemetry,
  });

  Duration get duration {
    final value = endedAt.difference(startedAt);
    return value.isNegative ? Duration.zero : value;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'rustdesk_id': rustdeskId,
        'support_session_id': supportSessionId,
        'started_at': startedAt.toUtc().toIso8601String(),
        'ended_at': endedAt.toUtc().toIso8601String(),
        'telemetry': telemetry,
      };

  factory SupportPostSessionPrompt.fromJson(Map<String, dynamic> json) {
    final startedAt = DateTime.tryParse(json['started_at']?.toString() ?? '');
    final endedAt = DateTime.tryParse(json['ended_at']?.toString() ?? '');
    return SupportPostSessionPrompt(
      id: json['id']?.toString() ?? '',
      rustdeskId: json['rustdesk_id']?.toString() ?? '',
      supportSessionId: json['support_session_id']?.toString(),
      startedAt: startedAt ?? DateTime.now().toUtc(),
      endedAt: endedAt ?? DateTime.now().toUtc(),
      telemetry: json['telemetry'] is Map
          ? Map<String, dynamic>.from(json['telemetry'] as Map)
          : const {},
    );
  }
}

enum SupportSessionSyncStatus { waiting, syncing, synced, failed, signedOut }

enum SupportBackendConnectionState {
  disabled,
  signedOut,
  checking,
  connected,
  offline,
}

class SupportDeviceCardData {
  final SupportDevice device;
  final SupportHostData? host;
  final List<SupportSessionSummary> activeSessions;
  final List<SupportSessionSummary> sessions;

  const SupportDeviceCardData({
    required this.device,
    required this.host,
    required this.activeSessions,
    required this.sessions,
  });
}

class SupportPresence {
  final List<SupportSessionSummary> sessions;

  const SupportPresence(this.sessions);

  bool get occupied => sessions.isNotEmpty;
}

class SupportClientUpdate {
  final String channel;
  final String buildUuid;
  final int githubRunId;
  final String filename;
  final String version;
  final bool autoUpdate;
  final int? size;
  final String downloadUrl;
  final DateTime? markedAt;

  const SupportClientUpdate({
    required this.channel,
    required this.buildUuid,
    required this.githubRunId,
    required this.filename,
    required this.version,
    required this.autoUpdate,
    required this.size,
    required this.downloadUrl,
    required this.markedAt,
  });

  factory SupportClientUpdate.fromJson(Map<String, dynamic> json) {
    return SupportClientUpdate(
      channel: json['channel']?.toString() ?? '',
      buildUuid: json['build_uuid']?.toString() ?? '',
      githubRunId: int.tryParse(json['github_run_id']?.toString() ?? '') ?? 0,
      filename: json['filename']?.toString() ?? '',
      version: json['version']?.toString() ?? '',
      autoUpdate: json['auto_update'] == true,
      size: int.tryParse(json['size']?.toString() ?? ''),
      downloadUrl: json['download_url']?.toString() ?? '',
      markedAt: DateTime.tryParse(json['marked_at']?.toString() ?? ''),
    );
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
  static const _queueLimit = 1000;
  static const _syncFailureLimit = 1000;

  final List<Map<String, dynamic>> _eventQueue = [];
  final List<SupportPostSessionPrompt> _postSessionPrompts = [];
  final Map<String, String> _sessionSyncFailures = {};
  final Set<String> _administratorClosedSessionIds = {};
  Future<void> _queueWrite = Future.value();
  Future<void> _postSessionPromptWrite = Future.value();
  Future<void> _sessionSyncFailuresWrite = Future.value();
  final Uuid _uuid = const Uuid();
  Future<void>? _initializing;
  bool _initialized = false;
  bool _flushing = false;
  String _installationId = '';
  String _token = '';
  String _tokenType = 'Device';
  SupportTechnician? _technician;
  bool _loading = false;
  bool _refreshing = false;
  bool _activeSessionsRefreshing = false;
  DateTime? _lastActiveSessionsRefresh;
  bool _backendChecking = false;
  bool _backendReachable = false;
  bool _onlineHandlerRegistered = false;
  bool _clientUpdateChecking = false;
  String? _error;
  Timer? _retryTimer;
  DateTime? _lastClientUpdateCheck;
  SupportClientUpdate? _clientUpdate;
  List<SupportCustomer> _customers = const [];
  List<SupportDevice> _devices = const [];
  List<SupportSessionSummary> _activeSessions = const [];

  bool get enabled => supportAddressBookApiUrl.trim().isNotEmpty;
  bool get initialized => _initialized;
  bool get isAuthenticated => enabled && _token.isNotEmpty;
  bool get loading => _loading;
  int get pendingEventCount => _eventQueue.length;
  SupportBackendConnectionState get backendConnectionState {
    if (!enabled) return SupportBackendConnectionState.disabled;
    if (!isAuthenticated) return SupportBackendConnectionState.signedOut;
    if (_backendChecking && !_backendReachable) {
      return SupportBackendConnectionState.checking;
    }
    return _backendReachable
        ? SupportBackendConnectionState.connected
        : SupportBackendConnectionState.offline;
  }

  String? get error => _error;
  SupportTechnician? get technician => _technician;
  bool get canCloseSupportSessions =>
      _technician?.canCloseSupportSessions == true;
  List<SupportCustomer> get customers => _customers;
  List<SupportDevice> get devices => _devices;
  List<SupportSessionSummary> get activeSessions =>
      List.unmodifiable(_activeSessions);

  bool consumeAdministratorClosedSession(String sessionId) =>
      _administratorClosedSessionIds.remove(sessionId);

  List<SupportSessionSummary> otherActiveSessionsFor(String rustdeskId) {
    final normalizedId = rustdeskId.replaceAll(RegExp(r'\s+'), '');
    final currentTechnicianId = _technician?.id;
    return _activeSessions
        .where((session) =>
            session.rustdeskId.replaceAll(RegExp(r'\s+'), '') == normalizedId &&
            session.technician?.id != currentTechnicianId)
        .toList();
  }

  bool get clientUpdateChecking => _clientUpdateChecking;
  SupportClientUpdate? get availableClientUpdate {
    final update = _clientUpdate;
    if (update == null ||
        supportClientBuildUuid.isEmpty ||
        supportClientBuildRunId <= 0 ||
        (!isQuickSupportBuild &&
            update.githubRunId <= supportClientBuildRunId)) {
      return null;
    }
    return update;
  }

  List<SupportPostSessionPrompt> get postSessionPrompts =>
      List.unmodifiable(_postSessionPrompts);

  SupportSessionSyncStatus syncStatusForSession(String sessionId) {
    if (!isAuthenticated) return SupportSessionSyncStatus.signedOut;
    if (_sessionSyncFailures.containsKey(sessionId)) {
      return SupportSessionSyncStatus.failed;
    }
    if (_eventQueue.any((event) => event['session_id'] == sessionId)) {
      return _flushing
          ? SupportSessionSyncStatus.syncing
          : SupportSessionSyncStatus.waiting;
    }
    return SupportSessionSyncStatus.synced;
  }

  String? syncErrorForSession(String sessionId) =>
      _sessionSyncFailures[sessionId];

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
        // Keep queued session events so a renewed token for this installation
        // can safely retry them after the technician signs in again.
        unawaited(_clearAuthentication(clearQueue: false));
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
      _postSessionPrompts
        ..clear()
        ..addAll((await readSupportPostSessionPrompts())
            .map(SupportPostSessionPrompt.fromJson)
            .where((prompt) =>
                prompt.id.isNotEmpty && prompt.rustdeskId.isNotEmpty));
      _sessionSyncFailures
        ..clear()
        ..addAll(await readSupportSessionSyncFailures());
      final savedToken = await readSupportDeviceToken();
      if (savedToken != null && savedToken.isNotEmpty) {
        _token = savedToken;
        _backendChecking = true;
        try {
          var response = await http
              .post(
                _uri('api/auth/device/me/'),
                headers: _headers(),
                body: jsonEncode({
                  'machine_name': supportMachineName(),
                  'os_username': supportOsUsername(),
                  'client_version': await _reportedClientVersion(),
                }),
              )
              .timeout(const Duration(seconds: 3));
          if (response.statusCode == 405) {
            response = await http
                .get(
                  _uri('api/auth/device/me/'),
                  headers: _headers(),
                )
                .timeout(const Duration(seconds: 3));
          }
          final body = _requireSuccess(response);
          if (body is Map && body['technician'] is Map) {
            _technician = SupportTechnician.fromJson(
              Map<String, dynamic>.from(body['technician'] as Map),
            );
          }
          await _syncTechnicianDisplayName();
          _backendReachable = true;
          _error = null;
          _startRetryTimer();
          unawaited(flushEventQueue());
        } catch (error) {
          if (_token.isNotEmpty) {
            _backendReachable = false;
            _error = error.toString();
          }
        } finally {
          _backendChecking = false;
        }
      } else {
        await _syncTechnicianDisplayName();
      }
    } finally {
      _initialized = true;
      notifyListeners();
      if (managedWindowsUpdateChannels.contains(supportClientUpdateChannel)) {
        _startRetryTimer();
        unawaited(checkClientUpdate(force: true));
      }
    }
  }

  Future<void> login(String username, String password) async {
    if (!enabled) return;
    await ensureInitialized();
    _setLoading(true);
    _setBackendChecking(true);
    try {
      final reportedVersion = await _reportedClientVersion();
      final response = await http.post(
        _uri('api/auth/device/login/'),
        headers: _headers(authenticated: false),
        body: jsonEncode({
          'username': username,
          'password': password,
          'installation_id': _installationId,
          'machine_name': supportMachineName(),
          'os_username': supportOsUsername(),
          'client_version': reportedVersion,
        }),
      );
      final body = _requireSuccess(response);
      final token = body is Map ? body['token']?.toString() ?? '' : '';
      if (token.isEmpty) {
        throw const SupportAddressBookException(
            'Serwer nie zwrócił tokenu logowania.');
      }
      _token = token;
      _tokenType =
          body is Map ? body['token_type']?.toString() ?? 'Device' : 'Device';
      if (body is Map && body['technician'] is Map) {
        _technician = SupportTechnician.fromJson(
          Map<String, dynamic>.from(body['technician'] as Map),
        );
      }
      await _syncTechnicianDisplayName();
      await writeSupportDeviceToken(_token);
      _backendReachable = true;
      _error = null;
      _startRetryTimer();
      await flushEventQueue();
      await refresh();
      await checkClientUpdate(force: true);
    } catch (error) {
      _backendReachable = false;
      _error = error.toString();
      rethrow;
    } finally {
      _setBackendChecking(false);
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
    _backendChecking = false;
    _backendReachable = false;
    _customers = const [];
    _devices = const [];
    _activeSessions = const [];
    _administratorClosedSessionIds.clear();
    _lastActiveSessionsRefresh = null;
    _clientUpdate = null;
    _lastClientUpdateCheck = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    await _syncTechnicianDisplayName();
    await deleteSupportDeviceToken();
    if (clearQueue) {
      _eventQueue.clear();
      await _persistEventQueue();
      _postSessionPrompts.clear();
      await _persistPostSessionPrompts();
      _sessionSyncFailures.clear();
      await _persistSessionSyncFailures();
    }
    notifyListeners();
  }

  Future<void> _syncTechnicianDisplayName() async {
    final technician = _technician;
    final displayName = technician == null
        ? ''
        : (technician.displayName.trim().isNotEmpty
            ? technician.displayName.trim()
            : technician.username.trim());
    await bind.mainSetLocalOption(
      key: _supportTechnicianDisplayNameOption,
      value: displayName,
    );
  }

  Future<String> _reportedClientVersion() async {
    final managedVersion = supportClientVersion.trim();
    if (managedVersion.isNotEmpty) return managedVersion;
    return (await PackageInfo.fromPlatform()).version;
  }

  void _startRetryTimer() {
    _retryTimer ??= Timer.periodic(
      const Duration(seconds: 30),
      (_) {
        unawaited(flushEventQueue());
        unawaited(checkClientUpdate());
      },
    );
  }

  Future<void> checkClientUpdate({bool force = false}) async {
    await ensureInitialized();
    final requiresTechnicianToken =
        supportClientUpdateChannel == 'windows_support';
    if ((requiresTechnicianToken && !isAuthenticated) ||
        _clientUpdateChecking ||
        !managedWindowsUpdateChannels.contains(supportClientUpdateChannel)) {
      return;
    }
    final now = DateTime.now();
    if (!force &&
        _lastClientUpdateCheck != null &&
        now.difference(_lastClientUpdateCheck!) < const Duration(minutes: 15)) {
      return;
    }

    _clientUpdateChecking = true;
    _lastClientUpdateCheck = now;
    try {
      final response = await http
          .get(
            _uri(
              'api/v1/client-update/',
              {'channel': supportClientUpdateChannel},
            ),
            headers: _headers(authenticated: requiresTechnicianToken),
          )
          .timeout(const Duration(seconds: 10));
      final body = _requireSuccess(response);
      if (body is Map && body['configured'] == true) {
        final update = SupportClientUpdate.fromJson(
          Map<String, dynamic>.from(body),
        );
        _clientUpdate = update.channel == supportClientUpdateChannel &&
                update.buildUuid.isNotEmpty &&
                update.filename.toLowerCase().endsWith('.msi') &&
                update.downloadUrl.isNotEmpty
            ? update
            : null;
      } else {
        _clientUpdate = null;
      }
    } catch (error) {
      debugPrint('Support client update check failed: $error');
    } finally {
      _clientUpdateChecking = false;
      notifyListeners();
    }
  }

  Future<SupportClientUpdate> helpdeskMigrationUpdate() async {
    await ensureInitialized();
    if (!isAuthenticated) {
      throw const SupportAddressBookException(
          'Zaloguj technika przed migracją hosta.');
    }
    final response = await http
        .get(
          _uri(
            'api/v1/client-update/',
            {'channel': 'windows_helpdesk'},
          ),
          headers: _headers(),
        )
        .timeout(const Duration(seconds: 15));
    final body = _requireSuccess(response);
    if (body is! Map || body['configured'] != true) {
      throw const SupportAddressBookException(
          'Kanał aktualizacji Windows Helpdesk nie jest skonfigurowany.');
    }
    final update =
        SupportClientUpdate.fromJson(Map<String, dynamic>.from(body));
    if (update.channel != 'windows_helpdesk' ||
        update.buildUuid.isEmpty ||
        update.version.isEmpty ||
        !update.filename.toLowerCase().endsWith('.msi') ||
        update.downloadUrl.isEmpty) {
      throw const SupportAddressBookException(
          'Serwer zwrócił nieprawidłowy pakiet migracyjny.');
    }
    return update;
  }

  Future<void> recordLegacyMigration({
    required String rustdeskId,
    required String fromVersion,
    required SupportClientUpdate update,
  }) async {
    final response = await http
        .post(
          _uri('api/v1/legacy-migrations/'),
          headers: _headers(),
          body: jsonEncode({
            'rustdesk_id': rustdeskId,
            'from_version': fromVersion,
            'target_version': update.version,
            'target_build_uuid': update.buildUuid,
          }),
        )
        .timeout(const Duration(seconds: 10));
    _requireSuccess(response);
  }

  Future<void> refresh({bool silent = false}) async {
    await ensureInitialized();
    if (!isAuthenticated || _refreshing) return;
    _refreshing = true;
    if (!silent) _setLoading(true);
    if (!silent) _setBackendChecking(true);
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
      _backendReachable = true;
      _error = null;
      notifyListeners();
      await queryOnlineStates();
    } catch (error) {
      _backendReachable = false;
      _error = error.toString();
      notifyListeners();
      rethrow;
    } finally {
      _refreshing = false;
      if (!silent) _setBackendChecking(false);
      if (!silent) _setLoading(false);
    }
  }

  Future<void> refreshActiveSessions() async {
    await ensureInitialized();
    if (!isAuthenticated || _activeSessionsRefreshing) return;
    final now = DateTime.now();
    if (_lastActiveSessionsRefresh != null &&
        now.difference(_lastActiveSessionsRefresh!) <
            const Duration(seconds: 8)) {
      return;
    }
    _lastActiveSessionsRefresh = now;
    _activeSessionsRefreshing = true;
    try {
      final response = await http
          .get(
            _uri('api/v1/sessions/', {'active': 'true'}),
            headers: _headers(),
          )
          .timeout(const Duration(seconds: 10));
      final body = _requireSuccess(response);
      final items = body is Map ? body['results'] : body;
      final sessions = (items as List? ?? const [])
          .whereType<Map>()
          .map((item) =>
              SupportSessionSummary.fromJson(Map<String, dynamic>.from(item)))
          .where((session) => session.active)
          .toList()
        ..sort((left, right) {
          final leftStarted =
              left.startedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final rightStarted =
              right.startedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return leftStarted.compareTo(rightStarted);
        });
      _activeSessions = sessions;
      _backendReachable = true;
      _error = null;
      notifyListeners();
    } catch (error) {
      _backendReachable = false;
      _error = error.toString();
      notifyListeners();
      debugPrint('Support active sessions refresh failed: $error');
    } finally {
      _activeSessionsRefreshing = false;
    }
  }

  Future<void> forceCloseSupportSession(String sessionId) async {
    await ensureInitialized();
    if (!isAuthenticated || !canCloseSupportSessions) {
      throw const SupportAddressBookException(
        'Nie masz uprawnień do zamykania sesji techników.',
      );
    }
    final response = await http
        .post(
          _uri('api/v1/sessions/$sessionId/force-close/'),
          headers: _headers(),
          body: '{}',
        )
        .timeout(const Duration(seconds: 10));
    _requireSuccess(response);
    _activeSessions = _activeSessions
        .where((session) => session.id != sessionId)
        .toList(growable: false);
    _backendReachable = true;
    _error = null;
    notifyListeners();
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
    String? telemetrySessionId,
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
        if (telemetrySessionId != null && telemetrySessionId.isNotEmpty)
          'telemetry_session_id': telemetrySessionId,
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
            .map((item) =>
                SupportSessionSummary.fromJson(Map<String, dynamic>.from(item)))
            .toList();
    return SupportDeviceCardData(
      device: SupportDevice.fromJson(
          Map<String, dynamic>.from(body['device'] as Map)),
      host: body['host'] is Map
          ? SupportHostData.fromJson(
              Map<String, dynamic>.from(body['host'] as Map))
          : null,
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
          .map((item) =>
              SupportSessionSummary.fromJson(Map<String, dynamic>.from(item)))
          .where((item) => item.technician?.id != currentTechnicianId)
          .toList(),
    );
  }

  Future<SupportSessionHandle?> startSupportSession(
    String rustdeskId,
    Map<String, dynamic> telemetry,
  ) async {
    await ensureInitialized();
    if (!isAuthenticated) return null;
    final sessionId = _uuid.v4();
    final startedAt = DateTime.now().toUtc();
    await _enqueueEvent({
      'event_id': _uuid.v4(),
      'kind': 'start',
      'session_id': sessionId,
      'payload': {
        'session_id': sessionId,
        'rustdesk_id': rustdeskId,
        'started_at': startedAt.toIso8601String(),
        ...telemetry,
      },
    });
    unawaited(flushEventQueue());
    return SupportSessionHandle(id: sessionId, startedAt: startedAt);
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

  Future<void> enqueuePostSessionPrompt(
    SupportPostSessionPrompt prompt,
  ) async {
    await ensureInitialized();
    if (_postSessionPrompts.any((item) => item.id == prompt.id)) return;
    _postSessionPrompts.add(prompt);
    await _persistPostSessionPrompts();
    notifyListeners();
  }

  Future<void> reloadPostSessionState() async {
    await ensureInitialized();
    final prompts = (await readSupportPostSessionPrompts())
        .map(SupportPostSessionPrompt.fromJson)
        .where((prompt) => prompt.id.isNotEmpty && prompt.rustdeskId.isNotEmpty)
        .toList();
    final failures = await readSupportSessionSyncFailures();
    final promptsChanged = prompts.length != _postSessionPrompts.length ||
        prompts.any((prompt) =>
            !_postSessionPrompts.any((current) => current.id == prompt.id));
    final failuresChanged = !mapEquals(_sessionSyncFailures, failures);
    if (!promptsChanged && !failuresChanged) return;
    _postSessionPrompts
      ..clear()
      ..addAll(prompts);
    _sessionSyncFailures
      ..clear()
      ..addAll(failures);
    notifyListeners();
  }

  Future<void> completePostSessionPrompt(String promptId) async {
    final hasPrompt = _postSessionPrompts.any((item) => item.id == promptId);
    if (!hasPrompt) return;
    _postSessionPrompts.removeWhere((item) => item.id == promptId);
    await _persistPostSessionPrompts();
    notifyListeners();
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

  Future<void> _persistPostSessionPrompts() {
    final snapshot = _postSessionPrompts
        .map((prompt) => prompt.toJson())
        .toList(growable: false);
    _postSessionPromptWrite = _postSessionPromptWrite
        .catchError((_) {})
        .then((_) => writeSupportPostSessionPrompts(snapshot));
    return _postSessionPromptWrite;
  }

  Future<void> _persistSessionSyncFailures() {
    final snapshot = Map<String, String>.from(_sessionSyncFailures);
    _sessionSyncFailuresWrite = _sessionSyncFailuresWrite
        .catchError((_) {})
        .then((_) => writeSupportSessionSyncFailures(snapshot));
    return _sessionSyncFailuresWrite;
  }

  Future<void> _recordSessionSyncFailure(
    String sessionId,
    String kind,
    int statusCode,
  ) async {
    if (sessionId.isEmpty) return;
    if (!_sessionSyncFailures.containsKey(sessionId) &&
        _sessionSyncFailures.length >= _syncFailureLimit) {
      _sessionSyncFailures.remove(_sessionSyncFailures.keys.first);
    }
    _sessionSyncFailures[sessionId] =
        'Zdarzenie $kind odrzucone przez RDBK (HTTP $statusCode).';
    await _persistSessionSyncFailures();
    notifyListeners();
  }

  Future<void> _enqueueEvent(Map<String, dynamic> event) async {
    _eventQueue.add(event);
    if (_eventQueue.length > _queueLimit) {
      _eventQueue.removeRange(0, _eventQueue.length - _queueLimit);
    }
    await _persistEventQueue();
    notifyListeners();
  }

  Future<void> _removeProcessedEvent(
      Map<String, dynamic> processedEvent) async {
    final processedId = processedEvent['event_id']?.toString() ?? '';
    if (processedId.isEmpty) {
      _eventQueue.remove(processedEvent);
    } else {
      _eventQueue.removeWhere(
        (event) => event['event_id']?.toString() == processedId,
      );
    }
    await _persistEventQueue();
    notifyListeners();
  }

  Future<void> flushEventQueue() async {
    if (_flushing || !isAuthenticated || _eventQueue.isEmpty) return;
    _flushing = true;
    notifyListeners();
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
            response = await http
                .post(
                  _uri('api/v1/sessions/start/'),
                  headers: _headers(),
                  body: jsonEncode(payload),
                )
                .timeout(const Duration(seconds: 10));
          } else if (kind == 'heartbeat') {
            response = await http
                .post(
                  _uri('api/v1/sessions/$sessionId/heartbeat/'),
                  headers: _headers(),
                  body: jsonEncode(payload),
                )
                .timeout(const Duration(seconds: 10));
          } else if (kind == 'end') {
            response = await http
                .post(
                  _uri('api/v1/sessions/$sessionId/end/'),
                  headers: _headers(),
                  body: jsonEncode(payload),
                )
                .timeout(const Duration(seconds: 10));
          } else {
            await _removeProcessedEvent(event);
            continue;
          }
        } catch (error) {
          _backendReachable = false;
          _error = error.toString();
          debugPrint('Support event queue is offline: $error');
          break;
        }
        _backendReachable = true;
        if (response.statusCode >= 200 && response.statusCode < 300) {
          _error = null;
          if (kind == 'heartbeat') {
            final body = _decode(response);
            final session = body is Map ? body['session'] : null;
            if (body is Map &&
                body['closed'] == true &&
                session is Map &&
                session['end_reason'] == 'administrator' &&
                sessionId.isNotEmpty) {
              _administratorClosedSessionIds.add(sessionId);
            }
          }
          await _removeProcessedEvent(event);
          continue;
        }
        if (response.statusCode == 401) {
          await _clearAuthentication(clearQueue: false);
          break;
        }
        if (response.statusCode >= 500) break;
        await _recordSessionSyncFailure(sessionId, kind, response.statusCode);
        debugPrint(
            'Dropping rejected support event $kind/$processedEventId (${response.statusCode}).');
        await _removeProcessedEvent(event);
      }
    } finally {
      _flushing = false;
      notifyListeners();
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

  void _setBackendChecking(bool value) {
    if (_backendChecking == value) return;
    _backendChecking = value;
    notifyListeners();
  }
}

final supportAddressBookModel = SupportAddressBookModel();
