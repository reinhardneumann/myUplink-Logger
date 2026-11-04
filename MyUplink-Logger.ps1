<#
.SYNOPSIS
  Holt Werte aus der myUplink Public API und schreibt sie als CSV-Log.

.NOTES
  Voraussetzung: eine App unter https://dev.myuplink.com/apps (liefert Client ID + Client Secret).
  Dein normaler myUplink-Login (Mail/Passwort) funktioniert an der API NICHT.

  Nutzung:
    . .\MyUplink-Logger.ps1          # Funktionen laden (Dot-Sourcing)
    . .\MyUplink-Logger.ps1 -Dezimaltrennzeichen ','   # optional: Dezimaltrennzeichen vorgeben (Alias: -Dezimalkennzeichen)
    Save-MyUplinkCredential          # einmalig: Client ID als Benutzername, Secret als Kennwort
    Get-MyUplinkData | Format-Table  # alle Parameter ansehen
    Start-MyUplinkLogger -IntervalMinutes 5

  Hilfe:  Show-MyUplinkHilfe   bzw.   <Funktion> -Hilfe
#>

param(
    # Optional beim Laden des Skripts: Vorgabe für das Dezimaltrennzeichen der Spalte "Wert" in der CSV.
    # Gilt für Write-MyUplinkLog und Start-MyUplinkLogger, sofern dort nichts anderes angegeben wird.
    #   Auto = Einstellung von Windows (Standard), ',' = Komma, '.' = Punkt
    [Alias('Dezimalkennzeichen')]
    [ValidateSet('Auto', ',', '.')]
    [string]$Dezimaltrennzeichen = 'Auto'
)

$script:DefaultDezimaltrennzeichen = $Dezimaltrennzeichen
$script:MyUplinkToken        = $null
$script:MyUplinkTokenExpires = [datetime]::MinValue
$script:DefaultCredPath      = Join-Path $env:USERPROFILE '.myuplink\credential.xml'

function Show-MyUplinkHilfe {
    <#
    .SYNOPSIS
      Gibt deutsche Hilfetexte zu den Funktionen aus. Ohne Parameter: Übersicht.
    .EXAMPLE
      Show-MyUplinkHilfe
      Show-MyUplinkHilfe -Funktion Get-MyUplinkData
      Get-MyUplinkData -Hilfe
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Uebersicht','Save-MyUplinkCredential','Get-MyUplinkData','Write-MyUplinkLog','Start-MyUplinkLogger')]
        [string]$Funktion = 'Uebersicht'
    )

    $texte = @{
'Uebersicht' = @'
MyUplink-Logger: Hilfe

Funktionen:
  Save-MyUplinkCredential   Client ID und Secret einmalig verschlüsselt speichern
  Get-MyUplinkData          Aktuelle Messpunkte aus myUplink abrufen (Anzeige / Weiterverarbeitung)
  Write-MyUplinkLog         Ein Abrufzyklus: nur geänderte Werte an die CSV anhängen
  Start-MyUplinkLogger      Dauerschleife, ruft Write-MyUplinkLog im Intervall auf
  Show-MyUplinkHilfe        Diese Hilfe

Hilfe zu einer Funktion:  <Funktion> -Hilfe     oder     Show-MyUplinkHilfe -Funktion <Name>
Vollständige PowerShell-Hilfe: Get-Help <Funktion> -Examples

Dezimaltrennzeichen der CSV (Spalte Wert):
  Beim Laden vorgeben:  . .\MyUplink-Logger.ps1 -Dezimaltrennzeichen ','
  oder pro Aufruf:      Start-MyUplinkLogger -Dezimaltrennzeichen '.'
  (Alias: -Dezimalkennzeichen; Auto = Einstellung von Windows)

Typischer Ablauf:
  1. Save-MyUplinkCredential
  2. Get-MyUplinkData | Format-Table
  3. Start-MyUplinkLogger -IntervalMinutes 5 -Verbose
'@
'Save-MyUplinkCredential' = @'
Save-MyUplinkCredential [-Path <Datei>] [-Hilfe]

Fragt per Dialog nach den API-Zugangsdaten und speichert sie verschlüsselt.
  Benutzername = Client ID   (aus https://dev.myuplink.com/apps)
  Kennwort     = Client Secret
Standardpfad: %USERPROFILE%\.myuplink\credential.xml
Unter Windows ist die Datei nur für dein Benutzerkonto auf diesem Rechner lesbar (DPAPI).
Dein normaler myUplink-Login (Mail/Passwort) funktioniert an der API nicht.
'@
'Get-MyUplinkData' = @'
Get-MyUplinkData [-CredentialPath <Datei>] [-DeviceId <id,...>] [-ParameterId <id,...>] [-Name <muster,...>] [-Hilfe]

Ruft die aktuellen Messpunkte ab und gibt sie als Objekte aus (nichts wird gespeichert).
  -DeviceId     Gerät(e); ohne Angabe werden alle Geräte des Kontos abgefragt
  -ParameterId  Nur diese Parameter-IDs, z. B. 5674,70
  -Name         Namensfilter mit Platzhaltern, z. B. '*operating*','flow*'
Spalten: Abgerufen, Geraet, ParameterId, Name, Wert, Einheit, Text, Zeitstempel
         (Zeitstempel = Messzeitpunkt laut myUplink, nicht der Abrufzeitpunkt)

Beispiele:
  Get-MyUplinkData | Format-Table
  Get-MyUplinkData -ParameterId 5674,5668 | Format-Table Name,Wert,Einheit,Zeitstempel
'@
'Write-MyUplinkLog' = @'
Write-MyUplinkLog [-OutFile <csv>] [-CredentialPath <Datei>] [-ParameterId <id,...>] [-Name <muster,...>] [-Dezimaltrennzeichen <Auto|,|.>] [-Verbose] [-Hilfe]

Ein einzelner Abrufzyklus. Hängt nur Zeilen an die CSV an, deren Zeitstempel sich seit
dem letzten Eintrag geändert hat. Der letzte Stand wird beim ersten Aufruf aus der CSV
gelesen, sodass nach einem Neustart keine Duplikate entstehen.
  -OutFile      Standard: %USERPROFILE%\myuplink-log.csv (Trennzeichen ;, UTF-8)
  -ParameterId  Standard: 0,1,2,3,5,6,17,21,22,23,31,32,33,39,45,46,57,66,67,70,5001,5668,5674,5700,5728,5729
  -Dezimaltrennzeichen  Auto (Standard) = Einstellung von Windows, bei deutscher Einstellung also Komma,
                wie es deutsches Excel erwartet. Mit ',' oder '.' lässt es sich erzwingen.
                Alias: -Dezimalkennzeichen. Die Vorgabe lässt sich auch beim Laden des Skripts setzen:
                . .\MyUplink-Logger.ps1 -Dezimaltrennzeichen ','
  -Verbose      zeigt, wie viele neue Werte geschrieben wurden
Geeignet für die Windows-Aufgabenplanung (alle paar Minuten starten).
Die CSV ist ein Ereignisprotokoll: Für Diagramme jeden Wert bis zum nächsten auffüllen.
'@
'Start-MyUplinkLogger' = @'
Start-MyUplinkLogger [-IntervalMinutes <min>] [-OutFile <csv>] [-CredentialPath <Datei>] [-ParameterId <id,...>] [-Name <muster,...>] [-Dezimaltrennzeichen <Auto|,|.>] [-Verbose] [-Hilfe]

Dauerschleife: ruft alle -IntervalMinutes (Standard 5) Write-MyUplinkLog auf.
Fehler (z. B. Netzausfall) werden als Warnung ausgegeben, danach läuft die Schleife weiter.
Das Dezimaltrennzeichen in der Spalte Wert richtet sich nach -Dezimaltrennzeichen (Alias -Dezimalkennzeichen;
Standard: Einstellung von Windows, siehe Write-MyUplinkLog -Hilfe).
Abbruch mit Strg+C. Für den Dauerbetrieb im Hintergrund besser Write-MyUplinkLog per
Aufgabenplanung starten.

Beispiel:
  Start-MyUplinkLogger -IntervalMinutes 5 -Verbose
  Start-MyUplinkLogger -ParameterId 5674,70 -OutFile D:\wp-takt.csv
'@
    }

    Write-Host $texte[$Funktion]
}

function Save-MyUplinkCredential {
    [CmdletBinding()]
    param(
        [string]$Path = $script:DefaultCredPath,
        [switch]$Hilfe
    )

    if ($Hilfe) { Show-MyUplinkHilfe -Funktion Save-MyUplinkCredential; return }

    $dir = Split-Path $Path
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    $cred = Get-Credential -Message 'myUplink API: Benutzername = Client ID, Kennwort = Client Secret'
    $cred | Export-Clixml -Path $Path   # unter Windows per DPAPI an Benutzer+Rechner gebunden
    Write-Host "Gespeichert: $Path"
}

function Get-MyUplinkToken {
    [CmdletBinding()]
    param([string]$CredentialPath = $script:DefaultCredPath)

    if ($script:MyUplinkToken -and (Get-Date) -lt $script:MyUplinkTokenExpires) {
        return $script:MyUplinkToken
    }

    $cred   = Import-Clixml -Path $CredentialPath
    $id     = $cred.UserName
    $secret = $cred.GetNetworkCredential().Password
    $basic  = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("${id}:${secret}"))

    $resp = Invoke-RestMethod -Method Post -Uri 'https://api.myuplink.com/oauth/token' `
        -Headers @{ Authorization = "Basic $basic" } `
        -ContentType 'application/x-www-form-urlencoded' `
        -Body 'grant_type=client_credentials&scope=READSYSTEM'

    $script:MyUplinkToken        = $resp.access_token
    $script:MyUplinkTokenExpires = (Get-Date).AddSeconds([int]$resp.expires_in - 60)
    return $script:MyUplinkToken
}

function Invoke-MyUplink {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$CredentialPath = $script:DefaultCredPath
    )
    $token = Get-MyUplinkToken -CredentialPath $CredentialPath
    Invoke-RestMethod -Uri "https://api.myuplink.com$Path" `
        -Headers @{ Authorization = "Bearer $token"; Accept = 'application/json' }
}

function Get-MyUplinkData {
    <#
    .SYNOPSIS
      Liefert alle (oder gefilterte) Messpunkte aller Geräte als Objekte.
    .EXAMPLE
      Get-MyUplinkData -Name '*Verdichter*','*Betriebszeit*' | Format-Table
    #>
    [CmdletBinding()]
    param(
        [string]$CredentialPath = $script:DefaultCredPath,
        [string[]]$DeviceId,
        [string[]]$ParameterId,   # exakte IDs, z. B. 40004
        [string[]]$Name,          # Wildcards auf den Parameternamen erlaubt
        [switch]$Hilfe
    )

    if ($Hilfe) { Show-MyUplinkHilfe -Funktion Get-MyUplinkData; return }

    if (-not $DeviceId) {
        $sys      = Invoke-MyUplink -Path '/v2/systems/me' -CredentialPath $CredentialPath
        $DeviceId = @($sys.systems.devices.id)
    }

    $stamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')

    foreach ($d in $DeviceId) {
        $points = Invoke-MyUplink -Path "/v2/devices/$d/points" -CredentialPath $CredentialPath

        foreach ($p in $points) {
            if ($ParameterId -and ($ParameterId -notcontains [string]$p.parameterId)) { continue }
            if ($Name -and -not ($Name | Where-Object { $p.parameterName -like $_ })) { continue }

            [pscustomobject]@{
                Abgerufen   = $stamp
                Geraet      = $d
                ParameterId = $p.parameterId
                Name        = $p.parameterName
                Wert        = $p.value
                Einheit     = $p.parameterUnit
                Text        = $p.strVal
                Zeitstempel = $(if ($p.timestamp -is [datetime]) { $p.timestamp.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:sszzz') } else { [string]$p.timestamp })   # Messzeitpunkt laut myUplink
            }
        }
    }
}

# Standardauswahl für die Auswertung (Takt, Temperaturen, Leistung, Drücke, Zähler)
$script:DefaultLogParameterIds = @(0,1,2,3,5,6,17,21,22,23,31,32,33,39,45,46,57,66,67,70,5001,5668,5674,5700,5728,5729)
$script:LastSeen = $null

function Write-MyUplinkLog {
    <#
    .SYNOPSIS
      Ein Abrufzyklus: schreibt nur Zeilen, deren Zeitstempel sich seit dem letzten
      Eintrag in der CSV geändert hat. Auch für die Windows-Aufgabenplanung geeignet.
    #>
    [CmdletBinding()]
    param(
        [string]$OutFile = (Join-Path $env:USERPROFILE 'myuplink-log.csv'),
        [string]$CredentialPath = $script:DefaultCredPath,
        [string[]]$ParameterId = $script:DefaultLogParameterIds,
        [string[]]$Name,
        [Alias('Dezimalkennzeichen')]
        [ValidateSet('Auto', ',', '.')]
        [string]$Dezimaltrennzeichen = $script:DefaultDezimaltrennzeichen,   # Auto = Einstellung von Windows (wie in Excel)
        [switch]$Hilfe
    )

    if ($Hilfe) { Show-MyUplinkHilfe -Funktion Write-MyUplinkLog; return }

    # Zustand beim ersten Aufruf aus der vorhandenen CSV rekonstruieren (neustartsicher)
    if ($null -eq $script:LastSeen) {
        $script:LastSeen = @{}
        if (Test-Path $OutFile) {
            Import-Csv -Path $OutFile -Delimiter ';' | ForEach-Object {
                $script:LastSeen["$($_.Geraet)|$($_.ParameterId)"] = [string]$_.Zeitstempel
            }
        }
    }

    $neu = @(
        foreach ($row in Get-MyUplinkData -CredentialPath $CredentialPath -ParameterId $ParameterId -Name $Name) {
            $key = "$($row.Geraet)|$($row.ParameterId)"
            if ($script:LastSeen[$key] -ne [string]$row.Zeitstempel) {
                $script:LastSeen[$key] = [string]$row.Zeitstempel
                $row
            }
        }
    )

    # Dezimaltrennzeichen für die CSV (Excel liest "4.0" in deutscher Einstellung sonst als 40)
    $nfi = [Globalization.NumberFormatInfo](Get-Culture).NumberFormat.Clone()
    if ($Dezimaltrennzeichen -and $Dezimaltrennzeichen -ne 'Auto') { $nfi.NumberDecimalSeparator = $Dezimaltrennzeichen }
    foreach ($row in $neu) {
        if ($row.Wert -is [ValueType] -and $row.Wert -isnot [bool]) {
            $row.Wert = $row.Wert.ToString($nfi)
        }
    }

    if ($neu.Count -gt 0) {
        $neu | Export-Csv -Path $OutFile -Append -NoTypeInformation -Delimiter ';' -Encoding UTF8
    }
    Write-Verbose "$(Get-Date -Format s): $($neu.Count) neue Werte geschrieben"
}

function Start-MyUplinkLogger {
    <#
    .SYNOPSIS
      Fragt dauerhaft in festem Intervall ab (nur geänderte Werte landen in der CSV).
    .EXAMPLE
      Start-MyUplinkLogger -IntervalMinutes 5 -Verbose
    #>
    [CmdletBinding()]
    param(
        [int]$IntervalMinutes = 5,
        [string]$OutFile = (Join-Path $env:USERPROFILE 'myuplink-log.csv'),
        [string]$CredentialPath = $script:DefaultCredPath,
        [string[]]$ParameterId = $script:DefaultLogParameterIds,
        [string[]]$Name,
        [Alias('Dezimalkennzeichen')]
        [ValidateSet('Auto', ',', '.')]
        [string]$Dezimaltrennzeichen = $script:DefaultDezimaltrennzeichen,
        [switch]$Hilfe
    )

    if ($Hilfe) { Show-MyUplinkHilfe -Funktion Start-MyUplinkLogger; return }

    Write-Host "Logger läuft, Intervall $IntervalMinutes min, Datei $OutFile (Abbruch mit Strg+C)"
    while ($true) {
        try {
            Write-MyUplinkLog -OutFile $OutFile -CredentialPath $CredentialPath -ParameterId $ParameterId -Name $Name -Dezimaltrennzeichen $Dezimaltrennzeichen
        }
        catch {
            Write-Warning "$(Get-Date -Format s) Abruf fehlgeschlagen: $($_.Exception.Message)"
            $script:MyUplinkToken = $null   # beim nächsten Lauf neues Token holen
        }
        Start-Sleep -Seconds ($IntervalMinutes * 60)
    }
}
