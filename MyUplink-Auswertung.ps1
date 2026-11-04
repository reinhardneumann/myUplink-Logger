<#
.SYNOPSIS
  Wertet die CSV des myUplink-Loggers aus: Verdichterzyklen, Tageswerte, Abtauungen, Warmwasser.

.NOTES
  Nutzung:
    . .\MyUplink-Auswertung.ps1                       # Funktion laden (Dot-Sourcing)
    Invoke-MyUplinkAuswertung                         # Standard-Logdatei auswerten
    Invoke-MyUplinkAuswertung -Von 2026-11-05 -Bis 2026-11-11
    Invoke-MyUplinkAuswertung -PassThru               # Ergebnis zusätzlich als Objekte

  Ergebnis: Übersicht im Fenster und zwei CSV-Dateien neben der Logdatei:
    myuplink-auswertung-tage.csv     eine Zeile pro Tag plus Gesamtzeile
    myuplink-auswertung-zyklen.csv   eine Zeile pro Verdichterlauf

  Benötigte Parameter-IDs im Log: 70 (VD1), 5674 (Starts), 17 (Betriebszustand).
  Weitere werden genutzt, wenn vorhanden: 0, 1, 5, 21, 23, 31, 5001, 5700.
  Liest nur die CSV, greift nicht auf myUplink zu.
#>

# Parameter-IDs der Paros 4-2 (siehe docs/parameter.md)
$script:MuId = @{
    Vorlauf       = '0'
    Ruecklauf     = '1'
    Aussen        = '5'
    Zustand       = '17'
    Leistung      = '21'
    MischerIst    = '23'
    Durchfluss    = '31'
    Verdichter    = '70'
    Impulse       = '5674'
    Offset        = '5001'
    Heizgrenze    = '5700'
}
# Betriebszustand (ID 17), Werte laut Luxtronik
$script:MuZustandHeizen  = 0
$script:MuZustandWW      = 1
$script:MuZustandAbtauen = 4

function ConvertTo-MuZahl {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return [double]::NaN }
    $t = $Text.Trim()
    if ($t.Contains(',') -and -not $t.Contains('.')) { $t = $t.Replace(',', '.') }
    $d = 0.0
    if ([double]::TryParse($t, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { return $d }
    return [double]::NaN
}

function Get-MuRaster {
    # Treppenfunktion einer Messreihe auf ein Minutenraster legen (Wert gilt bis zum nächsten Eintrag)
    param($Reihe, [long]$StartTicks, [int]$Anzahl)
    $out = New-Object double[] $Anzahl
    if ($null -eq $Reihe) {
        for ($k = 0; $k -lt $Anzahl; $k++) { $out[$k] = [double]::NaN }
        return ,$out
    }
    $zeiten = $Reihe.T; $werte = $Reihe.V; $anz = $zeiten.Length
    $i = 0; $cur = [double]::NaN
    $tpm = [TimeSpan]::TicksPerMinute
    for ($k = 0; $k -lt $Anzahl; $k++) {
        $jetzt = $StartTicks + $k * $tpm
        while ($i -lt $anz -and $zeiten[$i] -le $jetzt) { $cur = $werte[$i]; $i++ }
        $out[$k] = $cur
    }
    return ,$out
}

function New-MuMittel { @{ S = 0.0; N = 0 } }
function Add-MuMittel($m, [double]$x) { if (-not [double]::IsNaN($x)) { $m.S += $x; $m.N++ } }
function Get-MuMittel($m, [int]$Stellen = 1) { if ($m.N -gt 0) { [math]::Round($m.S / $m.N, $Stellen) } else { $null } }

function Format-MuCsvZeile {
    # Zahlen mit dem gewünschten Dezimaltrennzeichen in Text umwandeln (wie im Logger)
    param($Objekt, [string]$Dezimaltrennzeichen)
    $nfi = [Globalization.NumberFormatInfo](Get-Culture).NumberFormat.Clone()
    if ($Dezimaltrennzeichen -and $Dezimaltrennzeichen -ne 'Auto') { $nfi.NumberDecimalSeparator = $Dezimaltrennzeichen }
    $h = [ordered]@{}
    foreach ($p in $Objekt.PSObject.Properties) {
        $v = $p.Value
        if ($v -is [double] -or $v -is [int] -or $v -is [decimal]) { $h[$p.Name] = $v.ToString($nfi) }
        elseif ($v -is [datetime]) { $h[$p.Name] = $v.ToString('yyyy-MM-dd HH:mm') }
        else { $h[$p.Name] = $v }
    }
    [pscustomobject]$h
}

function Invoke-MyUplinkAuswertung {
    <#
    .SYNOPSIS
      Wertet die Logdatei aus (Zyklen, Tageswerte, Hinweise) und schreibt zwei CSV-Dateien.
    .EXAMPLE
      Invoke-MyUplinkAuswertung
      Invoke-MyUplinkAuswertung -Von 2026-11-05 -Bis 2026-11-11 -Dezimaltrennzeichen ','
    #>
    [CmdletBinding()]
    param(
        [string]$LogFile = (Join-Path $env:USERPROFILE 'myuplink-log.csv'),
        [string]$OutDir,                         # Standard: Ordner der Logdatei
        [datetime]$Von,                          # erster Tag (einschließlich)
        [datetime]$Bis,                          # letzter Tag (einschließlich)
        [string]$DeviceId,                       # Standard: erstes Gerät in der Datei
        [int]$EinschwingMinuten = 10,            # Anfang jedes Laufs für Temperaturmittel ignorieren
        [int]$LueckeMinuten = 30,                # Abstand zwischen Abrufen, ab dem eine Lücke gilt (0 = aus)
        [Alias('Dezimalkennzeichen')]
        [ValidateSet('Auto', ',', '.')]
        [string]$Dezimaltrennzeichen = $(if ($script:DefaultDezimaltrennzeichen) { $script:DefaultDezimaltrennzeichen } else { 'Auto' }),
        [switch]$KeineDateien,
        [switch]$PassThru,
        [switch]$Hilfe
    )

    if ($Hilfe) { Show-MyUplinkAuswertungHilfe; return }
    if (-not (Test-Path $LogFile)) { throw "Logdatei nicht gefunden: $LogFile" }

    $inv = [Globalization.CultureInfo]::InvariantCulture
    $tpm = [TimeSpan]::TicksPerMinute

    # ---- 1. CSV einlesen und Messreihen bilden -------------------------------------------
    Write-Host "Lese $LogFile ..."
    $zeilen = @(Import-Csv -Path $LogFile -Delimiter ';' -Encoding UTF8)
    if ($zeilen.Count -eq 0) { throw 'Die Logdatei enthält keine Daten.' }

    $geraete = @($zeilen | ForEach-Object { $_.Geraet } | Select-Object -Unique)
    if (-not $DeviceId) {
        $DeviceId = $geraete[0]
        if ($geraete.Count -gt 1) { Write-Warning "Mehrere Geräte in der Datei, ausgewertet wird $DeviceId (Auswahl mit -DeviceId)." }
    }

    $roh = @{}
    $abrufe = New-Object 'System.Collections.Generic.HashSet[long]'
    foreach ($z in $zeilen) {
        if ($z.Geraet -ne $DeviceId) { continue }
        try {
            $a = [datetime]::Parse($z.Abgerufen, $inv)
            $t = [DateTimeOffset]::Parse($z.Zeitstempel, $inv).LocalDateTime
        } catch { continue }
        [void]$abrufe.Add($a.Ticks - ($a.Ticks % $tpm))
        $parId = [string]$z.ParameterId
        if (-not $roh.ContainsKey($parId)) { $roh[$parId] = @{} }
        $roh[$parId][$t.Ticks] = (ConvertTo-MuZahl $z.Wert)    # gleicher Zeitstempel = gleicher Messwert
    }

    $reihe = @{}
    foreach ($parId in $roh.Keys) {
        $keys = [long[]]@($roh[$parId].Keys)
        [Array]::Sort($keys)
        $vals = New-Object double[] $keys.Length
        for ($i = 0; $i -lt $keys.Length; $i++) { $vals[$i] = $roh[$parId][$keys[$i]] }
        $reihe[$parId] = @{ T = $keys; V = $vals }
    }

    foreach ($pflicht in @($script:MuId.Verdichter, $script:MuId.Impulse, $script:MuId.Zustand)) {
        if (-not $reihe.ContainsKey($pflicht)) { throw "Parameter-ID $pflicht fehlt im Log. Bitte mit der Standardauswahl loggen." }
    }

    # ---- 2. Minutenraster über den geloggten Zeitraum -----------------------------------------
    $abrufListe = [long[]]@($abrufe)
    [Array]::Sort($abrufListe)
    $start = $abrufListe[0]
    $ende  = $abrufListe[$abrufListe.Length - 1]
    if ($PSBoundParameters.ContainsKey('Von')) { $start = [math]::Max($start, $Von.Date.Ticks) }
    if ($PSBoundParameters.ContainsKey('Bis')) { $ende  = [math]::Min($ende, $Bis.Date.AddDays(1).Ticks - $tpm) }
    if ($ende -le $start) { throw 'Im gewählten Zeitraum liegen keine Daten.' }
    $n = [int](($ende - $start) / $tpm) + 1

    # Abdeckung: Minuten zwischen zwei Abrufen mit zu großem Abstand gelten als unbekannt
    $abgedeckt = New-Object bool[] $n
    $j = 0
    for ($k = 0; $k -lt $n; $k++) {
        $t = $start + $k * $tpm
        while ($j + 1 -lt $abrufListe.Length -and $abrufListe[$j + 1] -le $t) { $j++ }
        if ($LueckeMinuten -le 0) { $abgedeckt[$k] = $true; continue }
        $vor = $abrufListe[$j]
        $nach = if ($j + 1 -lt $abrufListe.Length) { $abrufListe[$j + 1] } else { $vor }
        $abgedeckt[$k] = ($t -ge $vor) -and (($nach - $vor) -le $LueckeMinuten * $tpm)
    }

    $r = @{}
    foreach ($name in $script:MuId.Keys) { $r[$name] = Get-MuRaster $reihe[$script:MuId[$name]] $start $n }

    # ---- 3. Verdichterläufe aus den Schaltzeitpunkten von VD1 ------------------------------------
    $vd = $reihe[$script:MuId.Verdichter]
    $laeufe = New-Object System.Collections.Generic.List[object]
    $an = $null
    for ($i = 0; $i -lt $vd.T.Length; $i++) {
        $ein = $vd.V[$i] -ge 0.5
        if ($ein) {
            if ($null -ne $an) { $laeufe.Add(@{ A = $an; E = $null; Status = 'Aus-Signal fehlt' }) }
            $an = $vd.T[$i]
        } elseif ($null -ne $an) {
            $laeufe.Add(@{ A = $an; E = $vd.T[$i]; Status = 'vollständig' })
            $an = $null
        }
    }
    if ($null -ne $an) { $laeufe.Add(@{ A = $an; E = $null; Status = 'läuft noch' }) }

    # Laufalter je Minute (für die Einschwingzeit) und Zyklenauswertung
    $alter = New-Object int[] $n
    for ($k = 0; $k -lt $n; $k++) { $alter[$k] = -1 }

    $zyklen = New-Object System.Collections.Generic.List[object]
    $vorEnde = $null
    foreach ($l in $laeufe) {
        if ($null -eq $l.E) { $endeL = $ende } else { $endeL = $l.E }
        if ($endeL -lt $start -or $l.A -gt $ende) { $vorEnde = $l.E; continue }

        $i0 = [int][math]::Ceiling(($l.A - $start) / $tpm)
        $i1 = [int][math]::Floor(($endeL - $start) / $tpm)
        $status = $l.Status
        if ($l.A -lt $start -or ($null -ne $l.E -and $l.E -gt $ende)) { $status = 'außerhalb Zeitraum' }

        $mVL = New-MuMittel; $mRL = New-MuMittel; $mAT = New-MuMittel; $mMK = New-MuMittel; $mP = New-MuMittel; $mQ = New-MuMittel
        $ww = 0; $luecke = $false
        for ($k = [math]::Max($i0, 0); $k -lt [math]::Min($i1, $n); $k++) {
            $alter[$k] = $k - $i0
            if (-not $abgedeckt[$k]) { $luecke = $true; continue }
            $zu = $r.Zustand[$k]
            if ($zu -eq $script:MuZustandWW) { $ww++ }
            if ($zu -eq $script:MuZustandHeizen -and ($k - $i0) -ge $EinschwingMinuten) {
                Add-MuMittel $mVL $r.Vorlauf[$k]; Add-MuMittel $mRL $r.Ruecklauf[$k]
                Add-MuMittel $mMK $r.MischerIst[$k]; Add-MuMittel $mP $r.Leistung[$k]; Add-MuMittel $mQ $r.Durchfluss[$k]
            }
            Add-MuMittel $mAT $r.Aussen[$k]
        }
        if ($luecke -and $status -eq 'vollständig') { $status = 'Lücke im Log' }

        $abtau = 0
        $zs = $reihe[$script:MuId.Zustand]
        for ($i = 0; $i -lt $zs.T.Length; $i++) {
            if ($zs.T[$i] -ge $l.A -and $zs.T[$i] -le $endeL -and $zs.V[$i] -eq $script:MuZustandAbtauen -and
                ($i -eq 0 -or $zs.V[$i - 1] -ne $script:MuZustandAbtauen)) { $abtau++ }
        }

        $dauer = if ($null -ne $l.E) { [int][math]::Round(($l.E - $l.A) / $tpm, 0) } else { $null }
        $pause = $null
        if ($null -ne $vorEnde -and $l.A -ge $start) {
            $pIdx0 = [int][math]::Max(0, [math]::Floor(($vorEnde - $start) / $tpm))
            $pIdx1 = [int][math]::Min($n - 1, $i0)
            $ok = $true
            for ($k = $pIdx0; $k -le $pIdx1; $k++) { if (-not $abgedeckt[$k]) { $ok = $false; break } }
            if ($ok) { $pause = [int][math]::Round(($l.A - $vorEnde) / $tpm, 0) }
        }
        $vlm = Get-MuMittel $mVL; $rlm = Get-MuMittel $mRL
        $zyklen.Add([pscustomobject][ordered]@{
            Start              = [datetime]$l.A
            Ende               = $(if ($null -ne $l.E) { [datetime]$l.E } else { $null })
            Dauer_min          = $dauer
            Pause_vorher_min   = $pause
            Aussen_C           = Get-MuMittel $mAT
            Vorlauf_C          = $vlm
            Ruecklauf_C        = $rlm
            Spreizung_K        = $(if ($null -ne $vlm -and $null -ne $rlm) { [math]::Round($vlm - $rlm, 1) } else { $null })
            Mischer_Vorlauf_C  = Get-MuMittel $mMK
            Leistung_kW        = Get-MuMittel $mP 2
            Durchfluss_lh      = Get-MuMittel $mQ 0
            Abtauungen         = $abtau
            WW_min             = $ww
            Status             = $status
        })
        $vorEnde = $l.E
    }

    # ---- 4. Abtau- und Warmwasserphasen aus dem Betriebszustand ----------------------------------
    $phasen = New-Object System.Collections.Generic.List[object]
    $zs = $reihe[$script:MuId.Zustand]
    for ($i = 0; $i -lt $zs.T.Length; $i++) {
        $v = $zs.V[$i]
        if (($v -eq $script:MuZustandAbtauen -or $v -eq $script:MuZustandWW) -and ($i -eq 0 -or $zs.V[$i - 1] -ne $v)) {
            if ($zs.T[$i] -ge $start -and $zs.T[$i] -le $ende) {
                $phasen.Add(@{ Art = $(if ($v -eq $script:MuZustandWW) { 'WW' } else { 'Abtau' }); Tag = ([datetime]$zs.T[$i]).Date })
            }
        }
    }

    # ---- 5. Tageswerte --------------------------------------------------------------------------
    $tage = [ordered]@{}
    $neuerTag = {
        @{ Cov = 0; AT = (New-MuMittel); An = 0; VL = (New-MuMittel); RL = (New-MuMittel); MK = (New-MuMittel)
           Abst = (New-MuMittel); kWh = 0.0; Abtau = 0; WW = 0; First = -1; Last = -1; Offset = $null; HG = $null }
    }
    $gesamt = & $neuerTag
    for ($k = 0; $k -lt $n; $k++) {
        $tag = ([datetime]($start + $k * $tpm)).Date
        if (-not $tage.Contains($tag)) { $tage[$tag] = & $neuerTag }
        foreach ($acc in @($tage[$tag], $gesamt)) {
            if ($acc.First -lt 0) { $acc.First = $k }
            $acc.Last = $k
            if (-not $abgedeckt[$k]) { continue }
            $acc.Cov++
            Add-MuMittel $acc.AT $r.Aussen[$k]
            $ein = $r.Verdichter[$k] -ge 0.5
            if ($ein) { $acc.An++ }
            $zu = $r.Zustand[$k]
            if ($ein -and $zu -eq $script:MuZustandAbtauen) { $acc.Abtau++ }
            if ($ein -and $zu -eq $script:MuZustandWW) { $acc.WW++ }
            if ($ein -and $zu -eq $script:MuZustandHeizen -and $alter[$k] -ge $EinschwingMinuten) {
                Add-MuMittel $acc.VL $r.Vorlauf[$k]; Add-MuMittel $acc.RL $r.Ruecklauf[$k]; Add-MuMittel $acc.MK $r.MischerIst[$k]
                if (-not [double]::IsNaN($r.MischerIst[$k]) -and -not [double]::IsNaN($r.Vorlauf[$k])) { Add-MuMittel $acc.Abst ($r.Vorlauf[$k] - $r.MischerIst[$k]) }
            }
            $p = $r.Leistung[$k]
            if ($ein -and -not [double]::IsNaN($p)) { $acc.kWh += $p / 60.0 }
            if (-not [double]::IsNaN($r.Offset[$k])) { $acc.Offset = $r.Offset[$k] }
            if (-not [double]::IsNaN($r.Heizgrenze[$k])) { $acc.HG = $r.Heizgrenze[$k] }
        }
    }

    $imp = $r.Impulse
    $baueZeile = {
        param($bez, $acc, $zyk, $abtauN, $wwN)
        $iA = if ($acc.First -gt 0) { $acc.First - 1 } else { $acc.First }
        $starts = $null
        if (-not [double]::IsNaN($imp[$acc.Last]) -and -not [double]::IsNaN($imp[$iA])) { $starts = [int]($imp[$acc.Last] - $imp[$iA]) }
        $voll = @($zyk | Where-Object { $_.Status -eq 'vollständig' -and $null -ne $_.Dauer_min })
        $dauern = @($voll | ForEach-Object { [double]$_.Dauer_min })
        $pausen = @($zyk | Where-Object { $null -ne $_.Pause_vorher_min } | ForEach-Object { [double]$_.Pause_vorher_min })
        $lzh = [math]::Round($acc.An / 60.0, 1)
        $vl = Get-MuMittel $acc.VL; $rl = Get-MuMittel $acc.RL
        $hinweis = @()
        if ($acc.Cov -lt ($acc.Last - $acc.First + 1)) { $hinweis += 'Lücken im Log' }
        if ($bez -ne 'Gesamt' -and $acc.Cov -lt 1380) { $hinweis += 'Tag unvollständig' }
        [pscustomobject][ordered]@{
            Datum                 = $bez
            Abdeckung_h           = [math]::Round($acc.Cov / 60.0, 1)
            Aussen_C              = Get-MuMittel $acc.AT
            Starts                = $starts
            Starts_erkannt        = $zyk.Count
            Laufzeit_h            = $lzh
            Lauf_Mittel_min       = $(if ($dauern.Count) { [int][math]::Round(($dauern | Measure-Object -Average).Average, 0) } else { $null })
            Lauf_Min_min          = $(if ($dauern.Count) { [int]($dauern | Measure-Object -Minimum).Minimum } else { $null })
            Lauf_Max_min          = $(if ($dauern.Count) { [int]($dauern | Measure-Object -Maximum).Maximum } else { $null })
            Pause_Mittel_min      = $(if ($pausen.Count) { [int][math]::Round(($pausen | Measure-Object -Average).Average, 0) } else { $null })
            Starts_je_Laufstunde  = $(if ($null -ne $starts -and $lzh -gt 0) { [math]::Round($starts / $lzh, 2) } else { $null })
            Vorlauf_C             = $vl
            Ruecklauf_C           = $rl
            Spreizung_K           = $(if ($null -ne $vl -and $null -ne $rl) { [math]::Round($vl - $rl, 1) } else { $null })
            Mischer_Vorlauf_C     = Get-MuMittel $acc.MK
            Abstand_WP_Mischer_K  = Get-MuMittel $acc.Abst
            Abtauungen            = $abtauN
            Abtau_min             = $acc.Abtau
            WW_Ladungen           = $wwN
            WW_min                = $acc.WW
            Waerme_kWh            = [math]::Round($acc.kWh, 1)
            Offset_K              = $acc.Offset
            Heizgrenze_C          = $acc.HG
            Hinweis               = ($hinweis -join ', ')
        }
    }

    $tagZeilen = New-Object System.Collections.Generic.List[object]
    foreach ($tag in $tage.Keys) {
        $zyk = @($zyklen | Where-Object { $_.Start.Date -eq $tag })
        $ab = @($phasen | Where-Object { $_.Art -eq 'Abtau' -and $_.Tag -eq $tag }).Count
        $wwn = @($phasen | Where-Object { $_.Art -eq 'WW' -and $_.Tag -eq $tag }).Count
        $tagZeilen.Add((& $baueZeile $tag.ToString('yyyy-MM-dd') $tage[$tag] $zyk $ab $wwn))
    }
    $gesamtZeile = & $baueZeile 'Gesamt' $gesamt @($zyklen | Where-Object { $_.Status -ne 'außerhalb Zeitraum' }) `
        @($phasen | Where-Object { $_.Art -eq 'Abtau' }).Count @($phasen | Where-Object { $_.Art -eq 'WW' }).Count
    $tagZeilen.Add($gesamtZeile)

    # Einstellungsänderungen im Zeitraum
    $aenderungen = New-Object System.Collections.Generic.List[object]
    foreach ($e in @(@{ Id = $script:MuId.Offset; Name = 'Temperatur + -' }, @{ Id = $script:MuId.Heizgrenze; Name = 'Heizgrenze' })) {
        $s = $reihe[$e.Id]
        if ($null -eq $s) { continue }
        for ($i = 0; $i -lt $s.T.Length; $i++) {
            if ($i -gt 0 -and $s.V[$i] -eq $s.V[$i - 1]) { continue }
            $aenderungen.Add([pscustomobject]@{ Zeit = [datetime]$s.T[$i]; Einstellung = $e.Name; Wert = $s.V[$i] })
        }
    }

    # ---- 6. Ausgabe ---------------------------------------------------------------------------
    $von = [datetime]$start; $bis = [datetime]$ende
    Write-Host ''
    Write-Host ("Zeitraum: {0:dd.MM.yyyy HH:mm} bis {1:dd.MM.yyyy HH:mm}  ({2:N1} h, davon {3:N1} h mit Daten)" -f $von, $bis, ($n / 60.0), $gesamtZeile.Abdeckung_h) -ForegroundColor Cyan
    Write-Host ''
    $tagZeilen | Format-Table @{ n = 'Tag'; e = { $_.Datum } }, @{ n = 'AT °C'; e = { $_.Aussen_C } },
        Starts, @{ n = 'Lauf h'; e = { $_.Laufzeit_h } }, @{ n = 'Ø Lauf min'; e = { $_.Lauf_Mittel_min } },
        @{ n = 'Starts/Lh'; e = { $_.Starts_je_Laufstunde } }, @{ n = 'VL °C'; e = { $_.Vorlauf_C } },
        @{ n = 'RL °C'; e = { $_.Ruecklauf_C } }, @{ n = 'Spreiz K'; e = { $_.Spreizung_K } },
        @{ n = 'WP-MK K'; e = { $_.Abstand_WP_Mischer_K } }, @{ n = 'Abtau'; e = { $_.Abtauungen } },
        @{ n = 'WW'; e = { $_.WW_Ladungen } }, @{ n = 'kWh th'; e = { $_.Waerme_kWh } }, Hinweis -AutoSize |
        Out-String -Width 220 | Write-Host

    if ($aenderungen.Count) {
        Write-Host 'Einstellungen (Zeitpunkt der Änderung):'
        foreach ($a in $aenderungen) { Write-Host ("  {0:dd.MM.yyyy HH:mm}  {1} = {2}" -f $a.Zeit, $a.Einstellung, $a.Wert) }
        Write-Host ''
    }

    # Einfache Bewertung des Gesamtzeitraums
    Write-Host 'Einschätzung (Faustregeln):'
    $g = $gesamtZeile
    if ($null -ne $g.Starts_je_Laufstunde) {
        if ($g.Starts_je_Laufstunde -gt 3) { Write-Host "  ! $($g.Starts_je_Laufstunde) Starts je Laufstunde: deutliches Takten (Ziel: höchstens ca. 3)." -ForegroundColor Yellow }
        else { Write-Host "  + $($g.Starts_je_Laufstunde) Starts je Laufstunde: unkritisch." -ForegroundColor Green }
    }
    if ($null -ne $g.Lauf_Mittel_min) {
        if ($g.Lauf_Mittel_min -lt 20) { Write-Host "  ! Ø Laufzeit $($g.Lauf_Mittel_min) min: kurze Läufe (Ziel: mindestens 20 bis 30 min)." -ForegroundColor Yellow }
        else { Write-Host "  + Ø Laufzeit $($g.Lauf_Mittel_min) min: gut." -ForegroundColor Green }
    }
    if ($null -ne $g.Spreizung_K -and $g.Spreizung_K -gt 10) { Write-Host "  ! Spreizung $($g.Spreizung_K) K: groß (typisch 5 bis 8 K), Volumenstrom prüfen lassen." -ForegroundColor Yellow }
    if ($null -ne $g.Abstand_WP_Mischer_K -and $g.Abstand_WP_Mischer_K -gt 5) { Write-Host "  ! WP-Vorlauf liegt $($g.Abstand_WP_Mischer_K) K über dem Mischerkreis: WP erzeugt höher als nötig, Heizkurve prüfen lassen." -ForegroundColor Yellow }
    $offen = @($zyklen | Where-Object { $_.Status -eq 'Aus-Signal fehlt' }).Count
    if ($null -ne $g.Starts -and $g.Starts -gt $g.Starts_erkannt) { Write-Host "  i $($g.Starts - $g.Starts_erkannt) Starts nur im Zähler sichtbar (Läufe kürzer als das Abrufintervall oder Lücken)." }
    if ($offen) { Write-Host "  i $offen Läufe ohne Aus-Signal (Abrufintervall zu grob oder Lücke)." }
    Write-Host '  Wärmemenge (kWh th) ist aus „Heating capacity“ geschätzt, Plausibilität beachten.'

    if (-not $KeineDateien) {
        if (-not $OutDir) { $OutDir = Split-Path -Parent (Resolve-Path $LogFile) }
        $fTage = Join-Path $OutDir 'myuplink-auswertung-tage.csv'
        $fZyk  = Join-Path $OutDir 'myuplink-auswertung-zyklen.csv'
        $tagZeilen | ForEach-Object { Format-MuCsvZeile $_ $Dezimaltrennzeichen } |
            Export-Csv -Path $fTage -NoTypeInformation -Delimiter ';' -Encoding UTF8
        $zyklen | ForEach-Object { Format-MuCsvZeile $_ $Dezimaltrennzeichen } |
            Export-Csv -Path $fZyk -NoTypeInformation -Delimiter ';' -Encoding UTF8
        Write-Host ''
        Write-Host "Gespeichert: $fTage"
        Write-Host "             $fZyk"
    }

    if ($PassThru) {
        [pscustomobject]@{ Tage = $tagZeilen; Zyklen = $zyklen; Einstellungen = $aenderungen }
    }
}

function Show-MyUplinkAuswertungHilfe {
    Write-Host @'
Invoke-MyUplinkAuswertung [-LogFile <csv>] [-Von <Datum>] [-Bis <Datum>] [-OutDir <Ordner>]
                          [-Dezimaltrennzeichen <Auto|,|.>] [-EinschwingMinuten 10] [-LueckeMinuten 30]
                          [-DeviceId <id>] [-KeineDateien] [-PassThru] [-Hilfe]

Wertet die Logdatei aus und zeigt eine Tagesübersicht im Fenster.
Schreibt zwei Dateien in den Ordner der Logdatei (oder -OutDir):
  myuplink-auswertung-tage.csv     eine Zeile pro Tag plus Gesamtzeile
  myuplink-auswertung-zyklen.csv   eine Zeile pro Verdichterlauf

Kennzahlen:
  Starts              Verdichterstarts laut Zähler (5674)
  Lauf h / Ø Lauf     Laufzeit aus den Schaltzeiten von VD1 (70)
  Starts/Lh           Starts je Laufstunde (Faustregel: höchstens ca. 3)
  VL, RL, Spreiz      Mittel im Heizbetrieb, ohne die ersten -EinschwingMinuten jedes Laufs
  WP-MK               Abstand WP-Vorlauf zu Mischerkreis-Vorlauf (23), falls geloggt
  Abtau, WW           Anzahl Abtauungen und Warmwasserladungen (Betriebszustand 17)
  kWh th              Wärmemenge geschätzt aus "Heating capacity" (21)

-LueckeMinuten: Liegen zwei Abrufe weiter auseinander (z. B. PC aus), wird die Zeit dazwischen
nicht ausgewertet. Wer nur sehr wenige IDs loggt, setzt -LueckeMinuten 0.
Es wird nur die CSV gelesen, nicht auf myUplink zugegriffen.
'@
}
