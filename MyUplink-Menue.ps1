<#
.SYNOPSIS
  Einfaches Textmenü für den myUplink-Logger (wird von Start-MyUplink.bat aufgerufen).
.PARAMETER Dezimaltrennzeichen
  Optional: Dezimaltrennzeichen für die Spalte Wert in der CSV. Auto (Standard) = Einstellung von
  Windows, ',' = Komma, '.' = Punkt. Alias: -Dezimalkennzeichen. Wird an MyUplink-Logger.ps1 weitergegeben.
.EXAMPLE
  .\MyUplink-Menue.ps1 -Dezimaltrennzeichen ','
#>

param(
    [Alias('Dezimalkennzeichen')]
    [ValidateSet('Auto', ',', '.')]
    [string]$Dezimaltrennzeichen = 'Auto'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'MyUplink-Logger.ps1') -Dezimaltrennzeichen $Dezimaltrennzeichen

$logDatei = Join-Path $env:USERPROFILE 'myuplink-log.csv'

function Show-Menue {
    Clear-Host
    Write-Host '=============================================' -ForegroundColor Cyan
    Write-Host '  myUplink-Logger' -ForegroundColor Cyan
    Write-Host '=============================================' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  1  Zugangsdaten speichern (einmalig)'
    Write-Host '  2  Verbindung testen / Werte anzeigen'
    Write-Host '  3  Logger starten (schreibt in eine CSV-Datei)'
    Write-Host '  4  Hilfe'
    Write-Host '  5  Logdatei im Explorer zeigen'
    Write-Host '  0  Beenden'
    Write-Host ''
}

function Warte { Write-Host ''; Read-Host 'Weiter mit Eingabetaste' | Out-Null }

while ($true) {
    Show-Menue
    $wahl = Read-Host 'Auswahl'

    try {
        switch ($wahl) {
            '1' {
                Write-Host ''
                Write-Host 'Im folgenden Fenster eingeben:'
                Write-Host '  Benutzername = Client ID'
                Write-Host '  Kennwort     = Client Secret'
                Write-Host '(beides von https://dev.myuplink.com/apps)'
                Write-Host ''
                Save-MyUplinkCredential
                Warte
            }
            '2' {
                Write-Host ''
                Write-Host 'Rufe Werte ab ...'
                $daten = @(Get-MyUplinkData)
                $daten | Format-Table ParameterId, Name, Wert, Einheit, Zeitstempel -AutoSize |
                    Out-String -Width 200 | Write-Host
                Write-Host "$($daten.Count) Messpunkte gefunden."
                $ziel = Join-Path ([Environment]::GetFolderPath('Desktop')) 'myuplink-parameterliste.csv'
                $frage = Read-Host "Liste als Datei auf dem Desktop speichern? (j/n)"
                if ($frage -eq 'j') {
                    $daten | Export-Csv -Path $ziel -NoTypeInformation -Delimiter ';' -Encoding UTF8
                    Write-Host "Gespeichert: $ziel"
                }
                Warte
            }
            '3' {
                Write-Host ''
                $min = Read-Host 'Abfrage-Intervall in Minuten [5]'
                if (-not $min) { $min = 5 }
                Write-Host ''
                Write-Host 'Welche Parameter-IDs sollen geloggt werden?'
                Write-Host 'Leer lassen = Standardauswahl (passend für die Wärmepumpe des Autors).'
                Write-Host 'Eigene Auswahl: IDs mit Komma trennen, z. B. 5674,70,0,1'
                $ids = Read-Host 'IDs'
                $param = @{ IntervalMinutes = [int]$min; OutFile = $logDatei; Dezimaltrennzeichen = $Dezimaltrennzeichen }
                if ($ids) { $param.ParameterId = @($ids -split '[,; ]+' | Where-Object { $_ }) }
                Write-Host ''
                Write-Host "Logdatei: $logDatei"
                $dezAnzeige = if ($Dezimaltrennzeichen -eq 'Auto') { 'Auto (Einstellung von Windows)' } else { "'$Dezimaltrennzeichen'" }
                Write-Host "Dezimaltrennzeichen: $dezAnzeige"
                Write-Host 'Zum Beenden das Fenster schließen oder Strg+C drücken.'
                Write-Host ''
                Start-MyUplinkLogger @param -Verbose
            }
            '4' {
                Show-MyUplinkHilfe
                Warte
            }
            '5' {
                if (Test-Path $logDatei) {
                    Start-Process explorer.exe -ArgumentList "/select,`"$logDatei`""
                } else {
                    Write-Host ''
                    Write-Host "Noch keine Logdatei vorhanden: $logDatei"
                    Warte
                }
            }
            '0' { return }
            default { }
        }
    }
    catch {
        Write-Host ''
        Write-Host "Fehler: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host 'Tipp: Zugangsdaten mit Punkt 1 neu speichern und Internetverbindung prüfen.'
        Warte
    }
}
