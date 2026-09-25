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

List<String> legacyHostMigrationStageDirectories({
  required String remoteHome,
  required String remoteCurrentDirectory,
}) {
  String? usableDirectory(String value) {
    var candidate = value.trim().replaceAll('/', r'\');
    if (!RegExp(r'^[a-zA-Z]:\\').hasMatch(candidate)) return null;
    while (candidate.length > 3 && candidate.endsWith(r'\')) {
      candidate = candidate.substring(0, candidate.length - 1);
    }
    // Do not stage in a drive root. Apart from requiring elevated write access,
    // it would leave update payloads in a needlessly broad location.
    if (candidate.length <= 3) return null;
    return candidate;
  }

  final drive =
      RegExp(r'^([a-zA-Z]:)').firstMatch(remoteHome.trim())?.group(1) ??
          RegExp(r'^([a-zA-Z]:)')
              .firstMatch(remoteCurrentDirectory.trim())
              ?.group(1) ??
          'C:';
  final directories = <String>{'$drive\\Users\\Public\\Documents'};
  final home = usableDirectory(remoteHome);
  if (home != null) directories.add(home);
  final current = usableDirectory(remoteCurrentDirectory);
  if (current != null) directories.add(current);
  return directories.toList(growable: false);
}

String buildLegacyHostMigrationCommand({
  required String remoteScriptPath,
}) {
  final path = remoteScriptPath.replaceAll('"', '');
  return 'powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass '
      '-File "$path"';
}
