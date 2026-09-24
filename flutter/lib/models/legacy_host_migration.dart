import 'package:flutter/foundation.dart';

/// Keeps migration UI state outside the toolbar widget. The support toolbar can
/// be recreated when it moves between its embedded and floating layouts; UI
/// state stored in the widget would then schedule the same prompt again.
class LegacyHostMigrationCoordinator extends ChangeNotifier {
  static const autoPromptIdleDelay = Duration(seconds: 10);

  final Set<String> _autoPromptedSessions = <String>{};
  final Set<String> _inFlightSessions = <String>{};
  final Set<String> _dispatchedSessions = <String>{};
  final Map<String, DateTime> _lastTechnicianInput = <String, DateTime>{};

  void noteTechnicianInput(String sessionKey, {DateTime? at}) {
    _lastTechnicianInput[sessionKey] = at ?? DateTime.now();
    notifyListeners();
  }

  Duration? autoPromptDelayRemaining(
    String sessionKey, {
    DateTime? now,
  }) {
    final lastInput = _lastTechnicianInput[sessionKey];
    if (lastInput == null) return null;
    final elapsed = (now ?? DateTime.now()).difference(lastInput);
    if (elapsed >= autoPromptIdleDelay) return Duration.zero;
    if (elapsed.isNegative) return autoPromptIdleDelay;
    return autoPromptIdleDelay - elapsed;
  }

  bool reserveAutoPrompt(String sessionKey) {
    if (_dispatchedSessions.contains(sessionKey)) return false;
    return _autoPromptedSessions.add(sessionKey);
  }

  bool tryBegin(String sessionKey) {
    if (_dispatchedSessions.contains(sessionKey) ||
        _inFlightSessions.contains(sessionKey)) {
      return false;
    }
    _inFlightSessions.add(sessionKey);
    return true;
  }

  void markDispatched(String sessionKey) {
    _inFlightSessions.remove(sessionKey);
    _dispatchedSessions.add(sessionKey);
  }

  void markFailed(String sessionKey) {
    _inFlightSessions.remove(sessionKey);
  }

  bool isInFlight(String sessionKey) => _inFlightSessions.contains(sessionKey);

  bool isDispatched(String sessionKey) =>
      _dispatchedSessions.contains(sessionKey);

  void releaseSession(String sessionKey) {
    _autoPromptedSessions.remove(sessionKey);
    _inFlightSessions.remove(sessionKey);
    _dispatchedSessions.remove(sessionKey);
    _lastTechnicianInput.remove(sessionKey);
  }
}

final legacyHostMigrationCoordinator = LegacyHostMigrationCoordinator();

String buildLegacyHostMigrationCommand({
  required String remoteScriptPath,
}) {
  final path = remoteScriptPath.replaceAll('"', '');
  return 'powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass '
      '-File "$path"';
}
