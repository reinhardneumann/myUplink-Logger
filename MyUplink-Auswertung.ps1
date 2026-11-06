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
    MischerSoll   = '22'
    RuecklaufExt  = '3'
    RuecklaufSoll = '2'
    HUP           = '32'
    ZUP           = '33'
    # Luxtronik direkt (Modbus TCP), ID = MB + Registeradresse
    LuxPth        = 'MB10300'
    LuxVL         = 'MB10105'
    LuxPel        = 'MB10301'
    LuxStromGes   = 'MB10310'
    LuxStromHz    = 'MB10312'
    LuxStromWW    = 'MB10314'
    LuxWaermeGes  = 'MB10320'
    LuxWaermeHz   = 'MB10322'
    LuxWaermeWW   = 'MB10324'
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
function Get-MuMittel($m, [int]$Stellen = 1) { if ($m.N -gt 0) { [math]::Round($m.S / $m.N, $Stellen) + 0.0 } else { $null } }   # + 0.0 vermeidet -0

function Get-MuMedian($werte, [int]$Stellen = 1) {
    $a = @($werte | Where-Object { $null -ne $_ } | ForEach-Object { [double]$_ } | Sort-Object)
    if ($a.Count -eq 0) { return $null }
    $m = if ($a.Count % 2) { $a[[int][math]::Floor($a.Count / 2)] } else { ($a[$a.Count / 2 - 1] + $a[$a.Count / 2]) / 2 }
    [math]::Round($m, $Stellen) + 0.0
}

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
        [string[]]$LogFile = (Join-Path $env:USERPROFILE 'myuplink-log*.csv'),   # mehrere Dateien und Platzhalter möglich
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
    # Dateien auflösen (Platzhalter, Monatsdateien), bei Von/Bis Monatsdateien außerhalb überspringen
    $dateien = @(foreach ($lf in $LogFile) { Get-ChildItem -Path $lf -File -ErrorAction SilentlyContinue })
    $dateien = @($dateien | Where-Object { $_.Name -notlike 'myuplink-auswertung-*' } | Sort-Object FullName -Unique)
    if ($PSBoundParameters.ContainsKey('Von') -or $PSBoundParameters.ContainsKey('Bis')) {
        $dateien = @($dateien | Where-Object {
            if ($_.Name -notmatch '-(\d{4})-(\d{2})\.csv$') { return $true }
            $mA = [datetime]::new([int]$Matches[1], [int]$Matches[2], 1); $mE = $mA.AddMonths(1)
            -not (($PSBoundParameters.ContainsKey('Von') -and $mE -le $Von.Date) -or ($PSBoundParameters.ContainsKey('Bis') -and $mA -gt $Bis.Date))
        })
    }
    if ($dateien.Count -eq 0) { throw "Logdatei nicht gefunden: $($LogFile -join ', ')" }

    $inv = [Globalization.CultureInfo]::InvariantCulture
    $tpm = [TimeSpan]::TicksPerMinute

    # ---- 1. CSV einlesen und Messreihen bilden -------------------------------------------
    if ($dateien.Count -eq 1) { Write-Host "Lese $($dateien[0].FullName) ..." }
    else { Write-Host "Lese $($dateien.Count) Dateien: $(($dateien | ForEach-Object Name) -join ', ') ..." }
    $zeilen = @(foreach ($d in $dateien) { Import-Csv -Path $d.FullName -Delimiter ';' -Encoding UTF8 })
    if ($zeilen.Count -eq 0) { throw 'Die Logdatei enthält keine Daten.' }

    $geraete = @($zeilen | Where-Object { [string]$_.ParameterId -notlike 'MB*' } | ForEach-Object { $_.Geraet } | Select-Object -Unique)
    if ($geraete.Count -eq 0) { $geraete = @($zeilen[0].Geraet) }
    if (-not $DeviceId) {
        $DeviceId = $geraete[0]
        if ($geraete.Count -gt 1) { Write-Warning "Mehrere Geräte in der Datei, ausgewertet wird $DeviceId (Auswahl mit -DeviceId)." }
    }

    $roh = @{}
    $abrufe = New-Object 'System.Collections.Generic.HashSet[long]'
    foreach ($z in $zeilen) {
        if ($z.Geraet -ne $DeviceId -and [string]$z.ParameterId -notlike 'MB*') { continue }
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
        $mMS = New-MuMittel; $mMA = New-MuMittel; $mRX = New-MuMittel
        $sumPth = 0.0; $sumPel = 0.0; $mPel = New-MuMittel
        $mWP = New-MuMittel; $mFD = New-MuMittel
        $ww = 0; $luecke = $false
        for ($k = [math]::Max($i0, 0); $k -lt [math]::Min($i1, $n); $k++) {
            $alter[$k] = $k - $i0
            if (-not $abgedeckt[$k]) { $luecke = $true; continue }
            $zu = $r.Zustand[$k]
            if ($zu -eq $script:MuZustandWW) { $ww++ }
            if ($zu -eq $script:MuZustandHeizen -and ($k - $i0) -ge $EinschwingMinuten) {
                Add-MuMittel $mVL $r.Vorlauf[$k]; Add-MuMittel $mRL $r.Ruecklauf[$k]
                Add-MuMittel $mMK $r.MischerIst[$k]; Add-MuMittel $mP $r.Leistung[$k]; Add-MuMittel $mQ $r.Durchfluss[$k]
                Add-MuMittel $mMS $r.MischerSoll[$k]; Add-MuMittel $mRX $r.RuecklaufExt[$k]
                Add-MuMittel $mMA ($r.MischerIst[$k] - $r.MischerSoll[$k])
                Add-MuMittel $mPel $r.LuxPel[$k]
                if (-not [double]::IsNaN($r.LuxPth[$k]) -and -not [double]::IsNaN($r.LuxPel[$k])) { $sumPth += $r.LuxPth[$k]; $sumPel += $r.LuxPel[$k] }
                Add-MuMittel $mWP ($r.Vorlauf[$k] - $r.RuecklaufExt[$k])
                Add-MuMittel $mFD ($r.Durchfluss[$k] * 1.163 * ($r.Vorlauf[$k] - $r.Ruecklauf[$k]) / 1000.0)
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
        # Schaltpunkte am Pufferfühler (Rücklauf extern) relativ zum Rücklauf-Soll
        $wert = { param($arr, $k) if ($k -ge 0 -and $k -lt $n -and $abgedeckt[$k] -and -not [double]::IsNaN($arr[$k])) { [math]::Round($arr[$k], 1) + 0.0 } else { $null } }
        $pufS = & $wert $r.RuecklaufExt ($i0 - 1); $solS = & $wert $r.RuecklaufSoll ($i0 - 1)
        $pufE = $null; $solE = $null; $vlE = $null
        if ($status -eq 'vollständig' -and $i1 - 1 -ge $i0) {
            $pufE = & $wert $r.RuecklaufExt ($i1 - 1); $solE = & $wert $r.RuecklaufSoll ($i1 - 1); $vlE = & $wert $r.Vorlauf ($i1 - 1)
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
            Mischer_Soll_C     = Get-MuMittel $mMS
            Mischer_Abw_K      = Get-MuMittel $mMA
            Ruecklauf_ext_C    = Get-MuMittel $mRX
            Abstand_WP_Puffer_K = Get-MuMittel $mWP
            Puffer_Start_C     = $pufS
            RL_Soll_Start_C    = $solS
            Schalt_Start_K     = $(if ($null -ne $pufS -and $null -ne $solS) { [math]::Round($pufS - $solS, 1) + 0.0 } else { $null })
            Puffer_Stopp_C     = $pufE
            Schalt_Stopp_K     = $(if ($null -ne $pufE -and $null -ne $solE) { [math]::Round($pufE - $solE, 1) + 0.0 } else { $null })
            Vorlauf_Stopp_C    = $vlE
            Leistung_kW        = Get-MuMittel $mP 2
            Leistung_el_kW     = Get-MuMittel $mPel 2
            COP                = $(if ($sumPel -gt 0) { [math]::Round($sumPth / $sumPel, 2) } else { $null })
            Durchfluss_lh      = Get-MuMittel $mQ 0
            Leistung_aus_Durchfluss_kW = Get-MuMittel $mFD 2
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
           Abst = (New-MuMittel); kWh = 0.0; Abtau = 0; WW = 0; First = -1; Last = -1; Offset = $null; HG = $null
           MS = (New-MuMittel); MA = (New-MuMittel); RX = (New-MuMittel)
           HUP = 0; HUPn = 0; HUPaus = 0; ZUP = 0; ZUPn = 0; ZUPaus = 0
           WPPuf = (New-MuMittel); PufMK = (New-MuMittel); Pref = (New-MuMittel); Fl = (New-MuMittel); Spr = (New-MuMittel)
           MKTn = 0; MKTx = 0; MKNn = 0; MKNx = 0 }
    }
    # COP nach Vorlauf-Klassen (Gesamtzeitraum, nur mit Luxtronik-Leistungswerten)
    $klassen = @(@{ Bis = 46; Name = 'bis 46 °C' }, @{ Bis = 48; Name = '46-48 °C' }, @{ Bis = 50; Name = '48-50 °C' },
                 @{ Bis = 52; Name = '50-52 °C' }, @{ Bis = 54; Name = '52-54 °C' }, @{ Bis = 999; Name = 'über 54 °C' })
    foreach ($kl in $klassen) { $kl.Min = 0; $kl.Pth = 0.0; $kl.Pel = 0.0; $kl.AT = (New-MuMittel) }
    $gesamt = & $neuerTag
    # Vergleich nach Einstellung "Temperatur + -": Heizminuten je Offset-Wert
    $proOffset = [ordered]@{}
    for ($k = 0; $k -lt $n; $k++) {
        $tag = ([datetime]($start + $k * $tpm)).Date
        if (-not $tage.Contains($tag)) { $tage[$tag] = & $neuerTag }
        if ($abgedeckt[$k] -and $r.Verdichter[$k] -ge 0.5 -and $r.Zustand[$k] -eq $script:MuZustandHeizen -and
            $alter[$k] -ge $EinschwingMinuten -and -not [double]::IsNaN($r.Offset[$k])) {
            $o = $r.Offset[$k]
            if (-not $proOffset.Contains($o)) {
                $proOffset[$o] = @{ Ab = [datetime]($start + $k * $tpm); Min = 0; AT = (New-MuMittel); VL = (New-MuMittel)
                                    RL = (New-MuMittel); MK = (New-MuMittel); MS = (New-MuMittel); Abst = (New-MuMittel); Pth = 0.0; Pel = 0.0 }
            }
            $g = $proOffset[$o]
            $g.Min++
            Add-MuMittel $g.AT $r.Aussen[$k]; Add-MuMittel $g.VL $r.Vorlauf[$k]; Add-MuMittel $g.RL $r.Ruecklauf[$k]
            Add-MuMittel $g.MK $r.MischerIst[$k]; Add-MuMittel $g.MS $r.MischerSoll[$k]
            Add-MuMittel $g.Abst ($r.Vorlauf[$k] - $r.MischerIst[$k])
            if (-not [double]::IsNaN($r.LuxPth[$k]) -and -not [double]::IsNaN($r.LuxPel[$k])) { $g.Pth += $r.LuxPth[$k]; $g.Pel += $r.LuxPel[$k] }
        }
        $heizMin = $abgedeckt[$k] -and $r.Verdichter[$k] -ge 0.5 -and $r.Zustand[$k] -eq $script:MuZustandHeizen -and $alter[$k] -ge $EinschwingMinuten
        # Vorlauf aus derselben Luxtronik-Abfrage wie die Leistungswerte (zeitgleich), sonst myUplink
        $vlK = if (-not [double]::IsNaN($r.LuxVL[$k])) { $r.LuxVL[$k] } else { $r.Vorlauf[$k] }
        if ($heizMin -and -not [double]::IsNaN($r.LuxPth[$k]) -and -not [double]::IsNaN($r.LuxPel[$k]) -and -not [double]::IsNaN($vlK)) {
            foreach ($kl in $klassen) { if ($vlK -lt $kl.Bis) { $kl.Min++; $kl.Pth += $r.LuxPth[$k]; $kl.Pel += $r.LuxPel[$k]; Add-MuMittel $kl.AT $r.Aussen[$k]; break } }
        }
        $stunde = ([datetime]($start + $k * $tpm)).Hour
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
                Add-MuMittel $acc.MS $r.MischerSoll[$k]; Add-MuMittel $acc.RX $r.RuecklaufExt[$k]
                Add-MuMittel $acc.MA ($r.MischerIst[$k] - $r.MischerSoll[$k])
                Add-MuMittel $acc.WPPuf ($r.Vorlauf[$k] - $r.RuecklaufExt[$k])
                $pr = if (-not [double]::IsNaN($r.LuxPth[$k])) { $r.LuxPth[$k] } else { $r.Leistung[$k] }
                $sp = $r.Vorlauf[$k] - $r.Ruecklauf[$k]
                if (-not [double]::IsNaN($pr) -and $pr -gt 0 -and $sp -gt 3 -and $r.Durchfluss[$k] -gt 0) {
                    Add-MuMittel $acc.Pref $pr; Add-MuMittel $acc.Spr $sp; Add-MuMittel $acc.Fl $r.Durchfluss[$k]
                }
            }
            Add-MuMittel $acc.PufMK ($r.RuecklaufExt[$k] - $r.MischerSoll[$k])
            $dev = $r.MischerIst[$k] - $r.MischerSoll[$k]
            if (-not [double]::IsNaN($dev)) {
                if ($stunde -ge 6 -and $stunde -lt 22) { $acc.MKTn++; if ([math]::Abs($dev) -gt 2) { $acc.MKTx++ } }
                else { $acc.MKNn++; if ([math]::Abs($dev) -gt 2) { $acc.MKNx++ } }
            }
            if (-not [double]::IsNaN($r.HUP[$k])) { $acc.HUPn++; if ($r.HUP[$k] -ge 0.5) { $acc.HUP++; if (-not $ein) { $acc.HUPaus++ } } }
            if (-not [double]::IsNaN($r.ZUP[$k])) {
                $acc.ZUPn++
                if ($r.ZUP[$k] -ge 0.5) { $acc.ZUP++; if (-not $ein) { $acc.ZUPaus++ } }
            }
            $p = $r.Leistung[$k]
            if ($ein -and -not [double]::IsNaN($p)) { $acc.kWh += $p / 60.0 }
            if (-not [double]::IsNaN($r.Offset[$k])) { $acc.Offset = $r.Offset[$k] }
            if (-not [double]::IsNaN($r.Heizgrenze[$k])) { $acc.HG = $r.Heizgrenze[$k] }
        }
    }

    $imp = $r.Impulse
    $delta = {
        # Zählerzuwachs im Bereich: letzter Wert minus Wert vor Bereichsbeginn (bzw. erster Wert im Bereich).
        # Streng (Tageszeilen): Beginnt der Zähler erst mehr als 60 min nach Bereichsbeginn, gibt es keinen Wert.
        param($arr, $acc, [bool]$streng)
        $ende = [double]::NaN; $anf = [double]::NaN; $iAnf = -1
        for ($k = $acc.Last; $k -ge $acc.First; $k--) { if (-not [double]::IsNaN($arr[$k])) { $ende = $arr[$k]; break } }
        if ($acc.First -gt 0 -and -not [double]::IsNaN($arr[$acc.First - 1])) { $anf = $arr[$acc.First - 1]; $iAnf = $acc.First }
        else { for ($k = $acc.First; $k -le $acc.Last; $k++) { if (-not [double]::IsNaN($arr[$k])) { $anf = $arr[$k]; $iAnf = $k; break } } }
        if ([double]::IsNaN($ende) -or [double]::IsNaN($anf)) { return $null }
        if ($streng -and ($iAnf - $acc.First) -gt 60) { return $null }
        if (($acc.Last - $iAnf) -lt 60) { return $null }      # weniger als eine Stunde Zählerdaten
        [math]::Round($ende - $anf, 1) + 0.0
    }
    $zaehlerAb = $null
    $zr = $reihe[$script:MuId.LuxStromGes]
    if ($null -ne $zr -and $zr.T.Length -gt 0 -and $zr.T[0] -gt $start + 60 * $tpm) { $zaehlerAb = [datetime]$zr.T[0] }
    $quote = { param($q, $e) if ($null -ne $q -and $null -ne $e -and $e -gt 0) { [math]::Round($q / $e, 2) } else { $null } }
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
        $streng = $bez -ne 'Gesamt'
        $eHz = & $delta $r.LuxStromHz $acc $streng; $qHz = & $delta $r.LuxWaermeHz $acc $streng
        $eWW = & $delta $r.LuxStromWW $acc $streng; $qWW = & $delta $r.LuxWaermeWW $acc $streng
        $eGs = & $delta $r.LuxStromGes $acc $streng; $qGs = & $delta $r.LuxWaermeGes $acc $streng
        $hinweis = @()
        if ($acc.Cov -lt ($acc.Last - $acc.First + 1)) { $hinweis += 'Lücken im Log' }
        if (-not $streng -and $null -ne $zaehlerAb -and $null -ne $eGs) { $hinweis += ('Zähler ab {0:dd.MM. HH:mm}' -f $zaehlerAb) }
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
            Abstand_WP_Puffer_K   = Get-MuMittel $acc.WPPuf
            Abstand_Puffer_Mischer_K = Get-MuMittel $acc.PufMK
            Mischer_Soll_C        = Get-MuMittel $acc.MS
            Mischer_Abw_K         = Get-MuMittel $acc.MA
            Ruecklauf_ext_C       = Get-MuMittel $acc.RX
            Mischer_ueber2K_Tag_Proz   = $(if ($acc.MKTn -gt 0) { [int][math]::Round(100.0 * $acc.MKTx / $acc.MKTn) } else { $null })
            Mischer_ueber2K_Nacht_Proz = $(if ($acc.MKNn -gt 0) { [int][math]::Round(100.0 * $acc.MKNx / $acc.MKNn) } else { $null })
            Schalt_Start_K        = Get-MuMedian @($zyk | ForEach-Object { $_.Schalt_Start_K })
            Schalt_Stopp_K        = Get-MuMedian @($zyk | ForEach-Object { $_.Schalt_Stopp_K })
            Durchfluss_angezeigt_lh   = Get-MuMittel $acc.Fl 0
            Durchfluss_rechnerisch_lh = $(if ($acc.Spr.N -gt 0 -and $acc.Spr.S -gt 0) { [int][math]::Round(1000.0 * $acc.Pref.S / $acc.Pref.N / (1.163 * $acc.Spr.S / $acc.Spr.N)) } else { $null })
            Abtauungen            = $abtauN
            Abtau_min             = $acc.Abtau
            WW_Ladungen           = $wwN
            WW_min                = $acc.WW
            HUP_h                 = $(if ($acc.HUPn -gt 0) { [math]::Round($acc.HUP / 60.0, 1) } else { $null })
            ZUP_h                 = $(if ($acc.ZUPn -gt 0) { [math]::Round($acc.ZUP / 60.0, 1) } else { $null })
            ZUP_ohne_Verdichter_h = $(if ($acc.ZUPn -gt 0) { [math]::Round($acc.ZUPaus / 60.0, 1) } else { $null })
            HUP_ohne_Verdichter_h = $(if ($acc.HUPn -gt 0) { [math]::Round($acc.HUPaus / 60.0, 1) } else { $null })
            Waerme_kWh            = [math]::Round($acc.kWh, 1)
            Strom_Heizen_kWh      = $eHz
            Waerme_Heizen_kWh     = $qHz
            AZ_Heizen             = & $quote $qHz $eHz
            Strom_WW_kWh          = $eWW
            Waerme_WW_kWh         = $qWW
            AZ_WW                 = & $quote $qWW $eWW
            Strom_gesamt_kWh      = $eGs
            Waerme_gesamt_kWh     = $qGs
            AZ_gesamt             = & $quote $qGs $eGs
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
        @{ n = 'WP-Puf K'; e = { if ($null -ne $_.Abstand_WP_Puffer_K) { $_.Abstand_WP_Puffer_K } else { $_.Abstand_WP_Mischer_K } } },
        @{ n = 'Puf-MK K'; e = { $_.Abstand_Puffer_Mischer_K } }, @{ n = 'Abtau'; e = { $_.Abtauungen } },
        @{ n = 'WW'; e = { $_.WW_Ladungen } }, @{ n = 'Strom kWh'; e = { $_.Strom_gesamt_kWh } },
        @{ n = 'Wärme kWh'; e = { if ($null -ne $_.Waerme_gesamt_kWh) { $_.Waerme_gesamt_kWh } else { '≈' + $_.Waerme_kWh } } },
        @{ n = 'AZ Hz'; e = { $_.AZ_Heizen } }, @{ n = 'AZ ges'; e = { $_.AZ_gesamt } }, Hinweis -AutoSize |
        Out-String -Width 220 | Write-Host

    if ($aenderungen.Count) {
        Write-Host 'Einstellungen (Zeitpunkt der Änderung):'
        foreach ($a in $aenderungen) { Write-Host ("  {0:dd.MM.yyyy HH:mm}  {1} = {2}" -f $a.Zeit, $a.Einstellung, $a.Wert) }
        Write-Host ''
    }

    # Vergleich der Heizphasen je Einstellung "Temperatur + -"
    $offsetZeilen = New-Object System.Collections.Generic.List[object]
    foreach ($o in $proOffset.Keys) {
        $x = $proOffset[$o]
        $offsetZeilen.Add([pscustomobject][ordered]@{
            Offset_K             = $o
            Erste_Heizminute     = $x.Ab
            Heizstunden          = [math]::Round($x.Min / 60.0, 1)
            Aussen_C             = Get-MuMittel $x.AT
            Vorlauf_C            = Get-MuMittel $x.VL
            Ruecklauf_C          = Get-MuMittel $x.RL
            Mischer_Soll_C       = Get-MuMittel $x.MS
            Mischer_Vorlauf_C    = Get-MuMittel $x.MK
            Abstand_WP_Mischer_K = Get-MuMittel $x.Abst
            COP                  = $(if ($x.Pel -gt 0) { [math]::Round($x.Pth / $x.Pel, 2) } else { $null })
        })
    }
    if ($offsetZeilen.Count -gt 1) {
        Write-Host 'Heizbetrieb je Einstellung "Temperatur + -" (Mittel während der Läufe):'
        $offsetZeilen | Format-Table @{ n = 'Offset K'; e = { $_.Offset_K } }, @{ n = 'ab'; e = { $_.Erste_Heizminute.ToString('dd.MM. HH:mm') } },
            @{ n = 'Heiz h'; e = { $_.Heizstunden } }, @{ n = 'AT °C'; e = { $_.Aussen_C } }, @{ n = 'VL °C'; e = { $_.Vorlauf_C } },
            @{ n = 'RL °C'; e = { $_.Ruecklauf_C } }, @{ n = 'MK Soll'; e = { $_.Mischer_Soll_C } }, @{ n = 'MK Ist'; e = { $_.Mischer_Vorlauf_C } },
            @{ n = 'WP-MK K'; e = { $_.Abstand_WP_Mischer_K } }, COP -AutoSize | Out-String -Width 200 | Write-Host
        Write-Host '  Außentemperatur beachten: Bei unterschiedlichem Wetter sind die Werte nur bedingt vergleichbar.'
        Write-Host ''
    }

    # Schaltpunkte, Durchfluss-Plausibilität, COP nach Vorlauf
    $sStart = @($zyklen | Where-Object { $null -ne $_.Schalt_Start_K } | ForEach-Object { $_.Schalt_Start_K })
    $sStopp = @($zyklen | Where-Object { $null -ne $_.Schalt_Stopp_K } | ForEach-Object { $_.Schalt_Stopp_K })
    if ($sStart.Count -ge 3 -and $sStopp.Count -ge 3) {
        Write-Host ('Schaltpunkte am Pufferfühler (Rücklauf extern minus Rücklauf-Soll, {0} Läufe):' -f [math]::Min($sStart.Count, $sStopp.Count))
        Write-Host ('  Start  Median {0:+0.0;-0.0} K  (Spanne {1:+0.0;-0.0} bis {2:+0.0;-0.0} K)' -f (Get-MuMedian $sStart), ($sStart | Measure-Object -Minimum).Minimum, ($sStart | Measure-Object -Maximum).Maximum)
        Write-Host ('  Stopp  Median {0:+0.0;-0.0} K  (Spanne {1:+0.0;-0.0} bis {2:+0.0;-0.0} K)' -f (Get-MuMedian $sStopp), ($sStopp | Measure-Object -Minimum).Minimum, ($sStopp | Measure-Object -Maximum).Maximum)
        Write-Host '  Liegen Start und Stopp eng um das Soll, regelt die WP auf diesen Fühler; der Abstand ist die Schaltdifferenz.'
        Write-Host ''
    }
    $kz = @($klassen | Where-Object { $_.Min -ge 15 -and $_.Pel -gt 0 })
    if ($kz.Count -ge 2) {
        Write-Host 'COP nach Vorlauftemperatur (Heizbetrieb, Leistungswerte der Luxtronik):'
        $kz | ForEach-Object { [pscustomobject]@{ Vorlauf = $_.Name; Minuten = $_.Min; COP = [math]::Round($_.Pth / $_.Pel, 2); 'AT °C' = Get-MuMittel $_.AT } } |
            Format-Table -AutoSize | Out-String -Width 120 | Write-Host
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
    if ($null -ne $g.Spreizung_K -and $g.Spreizung_K -gt 10) { Write-Host "  ! Spreizung WP-Vorlauf/Rücklauf $($g.Spreizung_K) K: groß (typisch 5 bis 8 K), Volumenstrom im Ladekreis prüfen lassen." -ForegroundColor Yellow }
    if ($null -ne $g.Abstand_WP_Puffer_K) {
        # Mit Pufferfühler: Abstand in Ladekreis (WP -> Puffer) und Abstimmung (Puffer -> Heizkreis) trennen
        if ($g.Abstand_WP_Puffer_K -gt 5) { Write-Host "  ! WP-Vorlauf liegt im Lauf $($g.Abstand_WP_Puffer_K) K über dem Puffer: Der Abstand entsteht im Ladekreis (Spreizung, Volumenstrom)." -ForegroundColor Yellow }
        if ($null -ne $g.Abstand_Puffer_Mischer_K) {
            if ($g.Abstand_Puffer_Mischer_K -gt 5) { Write-Host "  ! Puffer liegt im Mittel $($g.Abstand_Puffer_Mischer_K) K über dem Mischer-Soll: Rücklauf-Soll bzw. Heizkurve der WP prüfen." -ForegroundColor Yellow }
            else { Write-Host "  + Puffer liegt im Mittel $($g.Abstand_Puffer_Mischer_K) K über dem Mischer-Soll: Kurven gut aufeinander abgestimmt." -ForegroundColor Green }
        }
    }
    elseif ($null -ne $g.Abstand_WP_Mischer_K -and $g.Abstand_WP_Mischer_K -gt 5) { Write-Host "  ! WP-Vorlauf liegt $($g.Abstand_WP_Mischer_K) K über dem Mischerkreis-Vorlauf (Ursache: Spreizung, Puffer oder Heizkurve; ohne Pufferfühler nicht trennbar)." -ForegroundColor Yellow }
    if ($null -ne $g.Durchfluss_rechnerisch_lh -and $null -ne $g.Durchfluss_angezeigt_lh -and $g.Durchfluss_rechnerisch_lh -gt 0) {
        $verh = $g.Durchfluss_angezeigt_lh / $g.Durchfluss_rechnerisch_lh
        if ($verh -gt 1.5 -or $verh -lt 0.67) { Write-Host "  ! Durchflussanzeige $($g.Durchfluss_angezeigt_lh) l/h passt nicht zu Leistung und Spreizung (rechnerisch ca. $($g.Durchfluss_rechnerisch_lh) l/h). Anzeige oder tatsächlichen Volumenstrom prüfen lassen." -ForegroundColor Yellow }
        else { Write-Host "  + Durchflussanzeige $($g.Durchfluss_angezeigt_lh) l/h passt zu Leistung und Spreizung (rechnerisch ca. $($g.Durchfluss_rechnerisch_lh) l/h)." -ForegroundColor Green }
    }
    if ($null -ne $g.AZ_Heizen) {
        $txt = "Arbeitszahl Heizen $($g.AZ_Heizen) im Zeitraum (Ø Außentemperatur $($g.Aussen_C) °C)"
        if ($null -ne $g.AZ_WW -and $g.AZ_WW -gt $g.AZ_Heizen) { Write-Host "  ! ${txt}: niedriger als Warmwasser ($($g.AZ_WW)), Heiz-Vorlauf vermutlich zu hoch." -ForegroundColor Yellow }
        else { Write-Host "  i ${txt}." }
    }
    if ($null -ne $g.Mischer_Abw_K -and [math]::Abs($g.Mischer_Abw_K) -gt 2) { Write-Host "  ! Mischerkreis weicht im Mittel $($g.Mischer_Abw_K) K vom Soll ab." -ForegroundColor Yellow }
    if ($null -ne $g.Mischer_ueber2K_Tag_Proz -and $g.Mischer_ueber2K_Tag_Proz -gt 15) { Write-Host "  ! Mischerkreis tagsüber (6 bis 22 Uhr) in $($g.Mischer_ueber2K_Tag_Proz) % der Minuten mehr als 2 K neben dem Soll (nachts $($g.Mischer_ueber2K_Nacht_Proz) %)." -ForegroundColor Yellow }
    if ($null -ne $g.HUP_ohne_Verdichter_h -or $null -ne $g.ZUP_ohne_Verdichter_h) {
        Write-Host ("  i Pumpen in den Verdichterpausen: HUP {0} h, ZUP {1} h. Welche Pumpe welchen Kreis versorgt, hängt von der Hydraulik ab." -f $(if ($null -ne $g.HUP_ohne_Verdichter_h) { $g.HUP_ohne_Verdichter_h } else { '–' }), $(if ($null -ne $g.ZUP_ohne_Verdichter_h) { $g.ZUP_ohne_Verdichter_h } else { '–' }))
    }
    $offen = @($zyklen | Where-Object { $_.Status -eq 'Aus-Signal fehlt' }).Count
    if ($null -ne $g.Starts -and $g.Starts -gt $g.Starts_erkannt) { Write-Host "  i $($g.Starts - $g.Starts_erkannt) Starts nur im Zähler sichtbar (Läufe kürzer als das Abrufintervall oder Lücken)." }
    if ($offen) { Write-Host "  i $offen Läufe ohne Aus-Signal (Abrufintervall zu grob oder Lücke)." }
    if ($null -eq $g.Waerme_gesamt_kWh) { Write-Host '  Wärmemenge ist aus „Heating capacity“ geschätzt. Genauer: Luxtronik per Modbus mitloggen (Menüpunkt 7).' }
    else { Write-Host '  Strom, Wärme und Arbeitszahlen stammen aus den Zählern der Luxtronik (Modbus).' }

    if (-not $KeineDateien) {
        if (-not $OutDir) { $OutDir = $dateien[0].DirectoryName }
        $fTage = Join-Path $OutDir 'myuplink-auswertung-tage.csv'
        $fZyk  = Join-Path $OutDir 'myuplink-auswertung-zyklen.csv'
        $fOff  = Join-Path $OutDir 'myuplink-auswertung-einstellungen.csv'
        $tagZeilen | ForEach-Object { Format-MuCsvZeile $_ $Dezimaltrennzeichen } |
            Export-Csv -Path $fTage -NoTypeInformation -Delimiter ';' -Encoding UTF8
        $zyklen | ForEach-Object { Format-MuCsvZeile $_ $Dezimaltrennzeichen } |
            Export-Csv -Path $fZyk -NoTypeInformation -Delimiter ';' -Encoding UTF8
        $offsetZeilen | ForEach-Object { Format-MuCsvZeile $_ $Dezimaltrennzeichen } |
            Export-Csv -Path $fOff -NoTypeInformation -Delimiter ';' -Encoding UTF8
        Write-Host ''
        Write-Host "Gespeichert: $fTage"
        Write-Host "             $fZyk"
        Write-Host "             $fOff"
    }

    if ($PassThru) {
        [pscustomobject]@{ Tage = $tagZeilen; Zyklen = $zyklen; Einstellungen = $aenderungen; ProOffset = $offsetZeilen
                           CopNachVorlauf = @($kz | ForEach-Object { [pscustomobject]@{ Vorlauf = $_.Name; Minuten = $_.Min; COP = [math]::Round($_.Pth / $_.Pel, 2); Aussen_C = Get-MuMittel $_.AT } }) }
    }
}

function Show-MyUplinkAuswertungHilfe {
    Write-Host @'
Invoke-MyUplinkAuswertung [-LogFile <csv,...>] [-Von <Datum>] [-Bis <Datum>] [-OutDir <Ordner>]
                          [-Dezimaltrennzeichen <Auto|,|.>] [-EinschwingMinuten 10] [-LueckeMinuten 30]
                          [-DeviceId <id>] [-KeineDateien] [-PassThru] [-Hilfe]

Wertet die Logdatei(en) aus und zeigt eine Tagesübersicht im Fenster. Standard: alle Dateien
%USERPROFILE%\myuplink-log*.csv (Monatsdateien und die frühere myuplink-log.csv) zusammen.
Schreibt drei Dateien in den Ordner der Logdatei (oder -OutDir):
  myuplink-auswertung-tage.csv     eine Zeile pro Tag plus Gesamtzeile
  myuplink-auswertung-zyklen.csv   eine Zeile pro Verdichterlauf
  myuplink-auswertung-einstellungen.csv   Heizbetrieb je Wert von "Temperatur + -"

Kennzahlen:
  Starts              Verdichterstarts laut Zähler (5674)
  Lauf h / Ø Lauf     Laufzeit aus den Schaltzeiten von VD1 (70)
  Starts/Lh           Starts je Laufstunde (Faustregel: höchstens ca. 3)
  VL, RL, Spreiz      Mittel im Heizbetrieb, ohne die ersten -EinschwingMinuten jedes Laufs
  WP-Puf              Abstand WP-Vorlauf zum Pufferfühler "Rücklauf extern" (3) im Lauf = Anteil Ladekreis
                      (ohne Pufferfühler: Abstand zum Mischerkreis-Vorlauf 23)
  Puf-MK              Abstand Pufferfühler zum Mischerkreis-Soll (22) = Abstimmung der Heizkurven
  Schaltpunkte        Pufferfühler minus Rücklauf-Soll (2) bei Start und Stopp jedes Laufs
  Durchfluss          angezeigter Durchfluss (31) gegen rechnerischen aus Leistung und Spreizung
  COP nach Vorlauf    COP je Vorlauf-Klasse (nur mit Luxtronik-Leistungswerten)
  Mischer > 2 K       Anteil der Minuten mit mehr als 2 K Abweichung, Tag (6-22 Uhr) und Nacht
  Mischer Soll/Abw    Mischerkreis-Soll (22) und Abweichung Ist - Soll (nur in den CSV-Dateien)
  Rücklauf extern     Fühler 3 (nur in den CSV-Dateien)
  HUP/ZUP h           Laufzeit der Pumpen 32/33, auch ohne Verdichter (nur in der Tages-CSV)
  Je Einstellung      Mittelwerte im Heizbetrieb je Wert von "Temperatur + -" (5001),
                      zum Vergleich vor und nach einer Änderung
  Abtau, WW           Anzahl Abtauungen und Warmwasserladungen (Betriebszustand 17)
  kWh th              Wärmemenge geschätzt aus "Heating capacity" (21)
  Strom/Wärme/AZ      aus den Luxtronik-Zählern (MB10310 bis MB10324), falls per Modbus geloggt;
                      AZ = Wärme / Strom im Zeitraum, getrennt für Heizen, Warmwasser und gesamt
  COP (Lauf, Offset)  Heizleistung / Leistungsaufnahme der Luxtronik (MB10300 / MB10301)

-LueckeMinuten: Liegen zwei Abrufe weiter auseinander (z. B. PC aus), wird die Zeit dazwischen
nicht ausgewertet. Wer nur sehr wenige IDs loggt, setzt -LueckeMinuten 0.
Es wird nur die CSV gelesen, nicht auf myUplink zugegriffen.
'@
}
