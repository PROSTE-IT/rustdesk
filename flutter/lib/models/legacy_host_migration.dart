import 'dart:convert';

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

String _powerShellSingleQuoted(String value) => value.replaceAll("'", "''");

String _encodePowerShell(String script) {
  final utf16 = <int>[];
  for (final codeUnit in script.codeUnits) {
    utf16
      ..add(codeUnit & 0xff)
      ..add((codeUnit >> 8) & 0xff);
  }
  return base64Encode(utf16);
}

String buildLegacyHostMigrationPowerShell({
  required String migrationScriptUrl,
}) {
  final url = _powerShellSingleQuoted(migrationScriptUrl);
  final elevatedScript = "\$ErrorActionPreference='Stop';"
      "\$d=Join-Path \$env:ProgramData ('PROSTE IT\\HostMigration\\bootstrap-'+[guid]::NewGuid().ToString('N'));"
      "New-Item -ItemType Directory -Path \$d -Force|Out-Null;"
      "\$p=Join-Path \$d 'migration.ps1';"
      "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;"
      "Invoke-WebRequest -UseBasicParsing -Uri '$url' -OutFile \$p -TimeoutSec 60;"
      "if((Get-Item -LiteralPath \$p).Length -lt 1000){throw 'RDBK zwrocil nieprawidlowy skrypt migracji'};"
      "& (Join-Path \$env:SystemRoot 'System32\\WindowsPowerShell\\v1.0\\powershell.exe') -NoLogo -NoProfile -ExecutionPolicy Bypass -File \$p -Elevated;"
      "\$c=\$LASTEXITCODE;"
      "Remove-Item -LiteralPath \$d -Recurse -Force -ErrorAction SilentlyContinue;"
      "exit \$c";
  final elevatedEncoded = _encodePowerShell(elevatedScript);
  return "\$ErrorActionPreference='Stop';"
      "\$e='$elevatedEncoded';"
      "try{"
      "\$Host.UI.RawUI.WindowTitle='PROSTE IT Helpdesk - bezpieczna migracja';"
      "Write-Host 'Uruchamianie bezpiecznej migracji. Zaakceptuj monit UAC.' -ForegroundColor Yellow;"
      "\$proc=Start-Process -FilePath (Join-Path \$env:SystemRoot 'System32\\WindowsPowerShell\\v1.0\\powershell.exe') -Verb RunAs -ArgumentList ('-NoLogo -NoProfile -ExecutionPolicy Bypass -EncodedCommand '+\$e) -Wait -PassThru;"
      "if(\$proc.ExitCode -ne 0){throw ('Migracja zakonczyla sie kodem '+\$proc.ExitCode)};"
      "}catch{"
      "\$m='Nie udalo sie uruchomic bezpiecznej migracji: '+\$_.Exception.Message;"
      "Write-Host \$m -ForegroundColor Red;"
      "try{Add-Type -AssemblyName PresentationFramework;[void][System.Windows.MessageBox]::Show(\$m,'PROSTE IT Helpdesk - blad')}catch{};"
      "exit 1"
      "}";
}

String buildLegacyHostMigrationCommand({
  required String migrationScriptUrl,
}) {
  final script = buildLegacyHostMigrationPowerShell(
    migrationScriptUrl: migrationScriptUrl,
  );
  final commandScript = script.replaceAll('"', r'\"');
  return 'powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass '
      '-Command "$commandScript"';
}
