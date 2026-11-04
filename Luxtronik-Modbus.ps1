<#
.SYNOPSIS
  Liest Werte direkt aus der Luxtronik-Steuerung über deren Smart-Home-Schnittstelle (Modbus TCP).

.NOTES
  Nur lesend: Es werden ausschließlich Input-Register gelesen (Modbus-Funktion 04).
  Voraussetzungen: Luxtronik ab Firmware 3.90.1 (Wärmezähler ab 3.92.0), im Regler unter
  Smart Home „ModBus TCP“ auf „Ein“. Die IP ist die der Steuerung selbst (MAC laut myUplink).
  Registerliste nach dem Projekt python-luxtronik (MIT).

  Nutzung:
    . .\Luxtronik-Modbus.ps1
    Get-LuxtronikModbusData -IP 192.168.178.33 | Format-Table
    Show-LuxtronikModbus -IP 192.168.178.33          # Übersicht mit COP und Arbeitszahlen
    Set-LuxtronikIP 192.168.178.33                   # IP merken, der Logger liest dann mit
#>

$script:LuxtronikIpPath = Join-Path $env:USERPROFILE '.myuplink\luxtronik-ip.txt'

# Register (ohne Offset 10000), Name, Typ (U16, S16, S32, VER), Teiler, Einheit
# Die ID im Log ist "MB" + Registeradresse, z. B. MB10301.
$script:LuxtronikRegister = @(
    @(  0, 'status bitmask (1 = VD1)',        'U16',  1, ''),
    @(  2, 'operation mode',                  'U16',  1, ''),
    @(  3, 'heating status',                  'U16',  1, ''),
    @(  4, 'DHW status',                      'U16',  1, ''),
    @(100, 'return',                          'U16', 10, '°C'),
    @(101, 'return target',                   'U16', 10, '°C'),
    @(102, 'return external',                 'U16', 10, '°C'),
    @(105, 'flow',                            'U16', 10, '°C'),
    @(108, 'outdoor temp.',                   'S16', 10, '°C'),
    @(109, 'outdoor temp. average',           'S16', 10, '°C'),
    @(112, 'max. flow temp.',                 'U16', 10, '°C'),
    @(120, 'DHW',                             'S16', 10, '°C'),
    @(121, 'DHW target',                      'S16', 10, '°C'),
    @(140, 'mix circ1 flow',                  'S16', 10, '°C'),
    @(141, 'mix circ1 target',                'S16', 10, '°C'),
    @(201, 'error number',                    'U16',  1, ''),
    @(202, 'buffer type (0 series, 1 separation, 2 multifunction)', 'U16', 1, ''),
    @(203, 'min. off time',                   'U16',  1, 'min'),
    @(204, 'min. run time',                   'U16',  1, 'min'),
    @(300, 'heating power actual',            'S16', 10, 'kW'),
    @(301, 'electric power actual',           'U16', 10, 'kW'),
    @(310, 'electric energy total',           'S32', 10, 'kWh'),
    @(312, 'electric energy heating',         'S32', 10, 'kWh'),
    @(314, 'electric energy DHW',             'S32', 10, 'kWh'),
    @(320, 'thermal energy total',            'S32', 10, 'kWh'),
    @(322, 'thermal energy heating',          'S32', 10, 'kWh'),
    @(324, 'thermal energy DHW',              'S32', 10, 'kWh'),
    @(400, 'firmware',                        'VER',  1, '')
)

function Get-LuxtronikIP {
    if (Test-Path $script:LuxtronikIpPath) { (Get-Content $script:LuxtronikIpPath -TotalCount 1).Trim() }
}

function Set-LuxtronikIP {
    param([string]$IP)
    $dir = Split-Path $script:LuxtronikIpPath
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    if ($IP) { Set-Content -Path $script:LuxtronikIpPath -Value $IP; Write-Host "Luxtronik-IP gespeichert: $IP" }
    elseif (Test-Path $script:LuxtronikIpPath) { Remove-Item $script:LuxtronikIpPath; Write-Host 'Luxtronik-IP entfernt, Modbus wird nicht mehr geloggt.' }
}

function Read-LuxBytes([System.IO.Stream]$Stream, [int]$Anzahl) {
    $buf = New-Object byte[] $Anzahl
    $got = 0
    while ($got -lt $Anzahl) {
        $n = $Stream.Read($buf, $got, $Anzahl - $got)
        if ($n -le 0) { throw 'Verbindung von der Steuerung beendet.' }
        $got += $n
    }
    return ,$buf
}

function Read-LuxModbusInput([System.IO.Stream]$Stream, [int]$UnitId, [int]$Adresse, [int]$Anzahl, [int]$Tid) {
    # Liefert die 16-Bit-Registerwerte oder $null bei einer Modbus-Fehlerantwort
    $req = [byte[]]@(
        [byte](($Tid -shr 8) -band 0xFF), [byte]($Tid -band 0xFF), 0, 0, 0, 6,
        [byte]$UnitId, 4,
        [byte]($Adresse -shr 8), [byte]($Adresse -band 0xFF),
        [byte]($Anzahl -shr 8), [byte]($Anzahl -band 0xFF))
    $Stream.Write($req, 0, $req.Length)
    $kopf = Read-LuxBytes $Stream 9
    if ($kopf[7] -band 0x80) { return $null }
    $daten = Read-LuxBytes $Stream $kopf[8]
    $werte = New-Object int[] $Anzahl
    for ($i = 0; $i -lt $Anzahl; $i++) { $werte[$i] = ([int]$daten[2 * $i] -shl 8) -bor [int]$daten[2 * $i + 1] }
    return ,$werte
}

function Get-LuxtronikModbusData {
    <#
    .SYNOPSIS
      Liest die Input-Register der Luxtronik und gibt sie im Format des Loggers aus.
    #>
    [CmdletBinding()]
    param(
        [string]$IP = (Get-LuxtronikIP),
        [int]$Port = 502,
        [int]$UnitId = 1,
        [int]$TimeoutMs = 5000
    )
    if (-not $IP) { throw 'Keine Luxtronik-IP angegeben (Set-LuxtronikIP oder -IP).' }

    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $ar = $client.BeginConnect($IP, $Port, $null, $null)
        if (-not $ar.AsyncWaitHandle.WaitOne($TimeoutMs)) { throw "Keine Verbindung zu ${IP}:$Port (Modbus aktiviert?)." }
        $client.EndConnect($ar)
        $client.ReceiveTimeout = 10000
        $s = $client.GetStream()
        $stamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
        $utc   = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss') + '+00:00'
        $tid = 0
        foreach ($r in $script:LuxtronikRegister) {
            $tid++
            $anz = switch ($r[2]) { 'S32' { 2 } 'VER' { 3 } default { 1 } }
            $roh = Read-LuxModbusInput $s $UnitId (10000 + $r[0]) $anz $tid
            if ($null -eq $roh) { continue }
            $wert = $null; $text = $null
            switch ($r[2]) {
                'U16' { $wert = $roh[0] / [double]$r[3] }
                'S16' { $v = $roh[0]; if ($v -ge 32768) { $v -= 65536 }; $wert = $v / [double]$r[3] }
                'S32' { $v = [long]$roh[0] * 65536 + $roh[1]; if ($v -ge 2147483648) { $v -= 4294967296 }; $wert = $v / [double]$r[3] }
                'VER' { $wert = [double]($roh[0] * 10000 + $roh[1] * 100 + $roh[2]); $text = '{0}.{1}.{2}' -f $roh[0], $roh[1], $roh[2] }
            }
            if ($null -eq $text) { $text = "$wert$($r[4])" }
            [pscustomobject]@{
                Abgerufen   = $stamp
                Geraet      = "luxtronik-$IP"
                ParameterId = "MB$(10000 + $r[0])"
                Name        = $r[1]
                Wert        = $wert
                Einheit     = $r[4]
                Text        = $text
                Zeitstempel = $utc      # Modbus liefert keinen Messzeitpunkt, daher Abrufzeit (UTC)
            }
        }
    }
    finally { $client.Close() }
}

function Show-LuxtronikModbus {
    <#
    .SYNOPSIS
      Zeigt die Luxtronik-Werte mit momentanem COP und Arbeitszahlen seit Zählerbeginn.
    #>
    [CmdletBinding()]
    param([string]$IP = (Get-LuxtronikIP), [int]$Port = 502)

    Write-Host "Lese Luxtronik ${IP}:$Port (Modbus TCP) ..."
    try { $d = @(Get-LuxtronikModbusData -IP $IP -Port $Port -ErrorAction Stop) }
    catch {
        Write-Host "Keine Verbindung: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host 'Prüfen: IP der Steuerung (nicht die eines anderen Moduls) und im Regler Smart Home „ModBus TCP“ = Ein.'
        return
    }
    $d | Format-Table ParameterId, Name, Text -AutoSize | Out-String -Width 200 | Write-Host
    $w = @{}; foreach ($x in $d) { $w[$x.ParameterId] = $x.Wert }
    if ($w['MB10301'] -gt 0 -and $w['MB10300'] -gt 0) {
        Write-Host ("Momentaner COP: {0:N2}  ({1} kW thermisch / {2} kW elektrisch)" -f ($w['MB10300'] / $w['MB10301']), $w['MB10300'], $w['MB10301']) -ForegroundColor Green
    } else { Write-Host 'Momentaner COP: Verdichter aus oder Werte nicht geliefert.' }
    foreach ($p in @(@('Heizen', 'MB10322', 'MB10312'), @('Warmwasser', 'MB10324', 'MB10314'), @('gesamt', 'MB10320', 'MB10310'))) {
        $q = $w[$p[1]]; $e = $w[$p[2]]
        if ($q -gt 0 -and $e -gt 0) { Write-Host ("Arbeitszahl {0} seit Zählerbeginn: {1:N2}  ({2:N1} kWh Wärme / {3:N1} kWh Strom)" -f $p[0], ($q / $e), $q, $e) -ForegroundColor Green }
    }
}
