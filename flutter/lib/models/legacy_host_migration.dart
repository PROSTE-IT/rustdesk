import 'dart:convert';

/// Keeps migration UI state outside the toolbar widget. The support toolbar can
/// be recreated when it moves between its embedded and floating layouts; UI
/// state stored in the widget would then schedule the same prompt again.
class LegacyHostMigrationCoordinator {
  final Set<String> _autoPromptedSessions = <String>{};
  final Set<String> _inFlightSessions = <String>{};
  final Set<String> _dispatchedSessions = <String>{};

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
}

final legacyHostMigrationCoordinator = LegacyHostMigrationCoordinator();

String _powerShellSingleQuoted(String value) => value.replaceAll("'", "''");

String buildLegacyHostMigrationPowerShell({
  required String downloadUrl,
  required String signerSubject,
}) {
  final url = _powerShellSingleQuoted(downloadUrl);
  final signer = _powerShellSingleQuoted(signerSubject);
  return "\$ErrorActionPreference='Stop';"
      "\$p=Join-Path \$env:TEMP 'proste-it-helpdesk-update.msi';"
      "try{"
      "\$Host.UI.RawUI.WindowTitle='Aktualizacja PROSTE IT Helpdesk';"
      "Write-Host 'PROSTE IT Helpdesk - przygotowanie migracji' -ForegroundColor Cyan;"
      "Write-Host '1/3 Pobieranie podpisanego instalatora...';"
      "Remove-Item -LiteralPath \$p -Force -ErrorAction SilentlyContinue;"
      "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;"
      "Invoke-WebRequest -UseBasicParsing -Uri '$url' -OutFile \$p;"
      "Write-Host '2/3 Sprawdzanie podpisu instalatora...';"
      "\$s=Get-AuthenticodeSignature -LiteralPath \$p;"
      "if(\$s.Status -ne 'Valid'){throw 'Nieprawidlowy podpis instalatora'};"
      "if('$signer' -and \$s.SignerCertificate.Subject -notlike ('*'+'$signer'+'*')){throw 'Nieprawidlowy wydawca instalatora'};"
      "Write-Host '3/3 Uruchamianie instalacji. Zaakceptuj monit UAC, jezeli sie pojawi.' -ForegroundColor Yellow;"
      "\$a=@('/i',('\"'+\$p+'\"'),'/passive','LAUNCH_TRAY_APP=N','REBOOT=ReallySuppress','/norestart');"
      "\$proc=Start-Process -FilePath (Join-Path \$env:SystemRoot 'System32\\msiexec.exe') -Verb RunAs -ArgumentList \$a -Wait -PassThru;"
      "if(@(0,1641,3010) -notcontains \$proc.ExitCode){throw ('Instalator zakonczyl sie kodem '+\$proc.ExitCode)};"
      "Write-Host 'Instalacja zakonczona. Helpdesk uruchomi sie ponownie.' -ForegroundColor Green;"
      "Remove-Item -LiteralPath \$p -Force -ErrorAction SilentlyContinue;"
      "}catch{"
      "\$m='Nie udalo sie zaktualizowac PROSTE IT Helpdesk: '+\$_.Exception.Message;"
      "Write-Host \$m -ForegroundColor Red;"
      "try{Add-Type -AssemblyName PresentationFramework;[void][System.Windows.MessageBox]::Show(\$m,'PROSTE IT Helpdesk - blad')}catch{};"
      "exit 1"
      "}";
}

String buildLegacyHostMigrationCommand({
  required String downloadUrl,
  required String signerSubject,
}) {
  final script = buildLegacyHostMigrationPowerShell(
    downloadUrl: downloadUrl,
    signerSubject: signerSubject,
  );
  final utf16 = <int>[];
  for (final codeUnit in script.codeUnits) {
    utf16
      ..add(codeUnit & 0xff)
      ..add((codeUnit >> 8) & 0xff);
  }
  return 'powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass '
      '-EncodedCommand ${base64Encode(utf16)}';
}
