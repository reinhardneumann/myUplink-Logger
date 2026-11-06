# myUplink-Logger

[🇩🇪 Deutsch](README.md) · 🇬🇧 English

A PowerShell tool that reads heat pump values from the official **myUplink API** and optionally directly from the **Luxtronik controller (Modbus TCP)**, and logs them to a CSV file. Developed and tested with an **alpha innotec Paros 4-2**; it should work with any device that is online in myUplink.

Why? The myUplink app shows current values but hardly any history. With the log you can analyse cycling (compressor starts, run times, pauses), flow and return temperatures, temperature spread, defrosts and hot water cycles over days and weeks, e.g. in Excel.

- Read-only: the tool never changes anything on the heat pump.
- No extra software: Windows PowerShell 5.1 or PowerShell 7 is enough.
- Credentials are stored encrypted per Windows user, never in plain text.

> This is a private project, not affiliated with alpha innotec, ait-deutschland or myUplink.

**Note:** the menu and the built-in help texts are in German. The commands and this README cover everything you need.

## Contents

| File | Purpose |
| --- | --- |
| `Start-MyUplink.bat` | Starts the menu by double-click |
| `MyUplink-Menue.ps1` | Text menu (credentials, test, logger, help) |
| `MyUplink-Logger.ps1` | The actual functions |
| `MyUplink-Auswertung.ps1` | Log analysis (cycles, daily figures, seasonal performance) |
| `auswertung/` | Browser analysis for phone, tablet and PC (see below) |
| `Luxtronik-Modbus.ps1` | Optional: values directly from the Luxtronik via Modbus TCP (electricity, heat, COP) |
| `docs/parameter.md` | Parameter reference of a Paros 4-2 (German) |

Keep all files in the same folder.

## Requirements

1. Windows with PowerShell 5.1 or 7.
2. A myUplink account with the heat pump online.
3. Your own API application at <https://dev.myuplink.com/apps>. It provides a **Client ID** and a **Client Secret**.
   - Your normal myUplink login (email and password) does **not** work with the API.
   - If the form asks for a callback URL: it is not used here, any value will do.
   - Every user creates their own application. Do not share your credentials.

## Quick start (menu)

1. Download the repository as ZIP ("Code" → "Download ZIP") and extract it, e.g. to `C:\Tools\myuplink-logger`.
2. If Windows blocks the scripts: right-click each file → Properties → "Unblock", or run `Get-ChildItem C:\Tools\myuplink-logger | Unblock-File` in PowerShell.
3. Double-click `Start-MyUplink.bat`.
4. **Option 1** (Zugangsdaten speichern): enter the Client ID as user name and the Client Secret as password.
5. **Option 2** (Verbindung testen): lists all data points of your system. You can save the list as CSV on the desktop.
6. **Option 3** (Logger starten): enter the interval (default 5 min) and optionally your own parameter IDs. Keep the window open, stop with Ctrl+C.
7. **Option 5** (Logdatei zeigen): shows the log file `%USERPROFILE%\myuplink-log.csv` in Explorer.
8. **Option 6** (Logdatei auswerten): analyses the log, optionally for a date range (see [Analysis](#analysis)).
9. **Option 7** (Luxtronik direkt): set the Luxtronik IP and show its values (see [Luxtronik direct](#luxtronik-direct-modbus-tcp)).

> The default parameter selection matches the author's Paros 4-2. For other devices run option 2 first and enter the IDs you want in option 3.

## Background operation with Windows Task Scheduler

1. Open Task Scheduler → "Create Task". It must run as the **same Windows user** that saved the credentials.
2. Trigger: daily, "Repeat task every: 5 minutes", duration "Indefinitely".
3. Action: program `powershell.exe`, arguments:

   ```
   -NoProfile -ExecutionPolicy Bypass -Command ". 'C:\Tools\myuplink-logger\MyUplink-Logger.ps1'; Write-MyUplinkLog"
   ```

4. Optionally, under "Conditions", untick "Start the task only if the computer is on AC power".

Each run reads the last state from the CSV and appends new values only, so no duplicates are created.

## Using the functions in PowerShell

```powershell
. C:\Tools\myuplink-logger\MyUplink-Logger.ps1      # load functions (dot + space)
Save-MyUplinkCredential                              # once
Get-MyUplinkData | Format-Table                      # show all data points
Get-MyUplinkData -ParameterId 5674,70 | Format-Table # selected IDs only
Start-MyUplinkLogger -IntervalMinutes 5 -Verbose     # endless loop
Show-MyUplinkHilfe                                   # help (German)
```

| Function | Purpose |
| --- | --- |
| `Save-MyUplinkCredential` | Store Client ID and Secret encrypted |
| `Get-MyUplinkData` | Read current data points (`-ParameterId`, `-Name` with wildcards, `-DeviceId`) |
| `Write-MyUplinkLog` | One polling cycle, appends changed values only |
| `Start-MyUplinkLogger` | Endless loop at a fixed interval, keeps running on network errors |
| `Show-MyUplinkHilfe` | Help texts, also via `<Function> -Hilfe` |

## CSV format

Semicolon-separated, UTF-8. One row per data point and change. Column names are German:

| Column | Content |
| --- | --- |
| `Abgerufen` | Time of the request (local time) |
| `Geraet` | Device ID in myUplink |
| `ParameterId` | ID of the data point |
| `Name` | Name as reported by myUplink |
| `Wert` | Numeric value |
| `Einheit` | Unit, e.g. °C, kW, l/h, bar |
| `Text` | Text value, e.g. "heating operation", "On" |
| `Zeitstempel` | Measurement time as reported by myUplink (UTC) |

The file is an **event log**: a value is written only when its myUplink timestamp has changed. For charts, carry each value forward until the next entry (e.g. `ffill()` in pandas).

**Decimal separator:** defaults to the Windows setting (comma on German systems). Force it with `Start-MyUplink.bat -Dezimaltrennzeichen "."` or per call `Write-MyUplinkLog -Dezimaltrennzeichen '.'`.

## Default parameters

`0, 1, 2, 3, 5, 6, 17, 21, 22, 23, 31, 32, 33, 39, 45, 46, 57, 66, 67, 70, 5001, 5668, 5674, 5700, 5728, 5729`

Meaning and other available IDs: [docs/parameter.md](docs/parameter.md). IDs may differ between devices and firmware versions.

## Luxtronik direct (Modbus TCP)

Many alpha innotec heat pumps (e.g. Paros) use a **Luxtronik** controller. From firmware 3.90.1 it offers a smart home interface via Modbus TCP with values myUplink does not provide:

- current electrical power input and heat output, giving the **instantaneous COP**
- **electricity counters** total, heating, hot water (3.90.1+) and **heat counters** total, heating, hot water (3.92.0+), giving the **seasonal performance factors**
- buffer configuration, minimum run time and minimum off time

**Setup**

1. On the controller, under **Smart Home**, set **"ModBus TCP" to "Ein" (on)**. Status "Standby" is normal while nothing is connected.
2. Find the **IP address of the controller**, e.g. in your router via the MAC address shown in myUplink (parameter 40011). Note: a separate network module may have its own IP.
3. **Option 7**: enter the IP. Values are shown immediately and the IP is saved (`%USERPROFILE%\.myuplink\luxtronik-ip.txt`).
4. Restart the logger (option 3 or Task Scheduler). Luxtronik values are written to the same CSV with IDs like `MB10301`, only when they change.

In PowerShell:

```powershell
. C:\Tools\myuplink-logger\MyUplink-Logger.ps1      # also loads Luxtronik-Modbus.ps1
Set-LuxtronikIP 192.168.178.33
Show-LuxtronikModbus
```

The tool **only reads** (Modbus function 04, input registers) and never writes to the controller. Electricity and heat counters are calculated by the controller itself, not by a calibrated meter, but they are well suited for comparisons. Register list: [docs/parameter.md](docs/parameter.md#luxtronik-modbus-tcp).

## Analysis

`MyUplink-Auswertung.ps1` reads the log file and builds a daily summary. It does not contact myUplink and can run at any time, even while the logger is active.

```powershell
. C:\Tools\myuplink-logger\MyUplink-Auswertung.ps1
Invoke-MyUplinkAuswertung                                   # whole log
Invoke-MyUplinkAuswertung -Von 2026-11-05 -Bis 2026-11-11   # date range (Von = from, Bis = to)
Invoke-MyUplinkAuswertung -Hilfe
```

The console shows one row per day plus a total row, the setting changes (offset, heating limit), a comparison of heating operation per value of "temperature + -" and a rule-of-thumb assessment. Three files are written next to the log file:

| File | Content |
| --- | --- |
| `myuplink-auswertung-tage.csv` | Per day: coverage, outdoor temperature, starts, run time, avg/min/max run, avg pause, starts per run hour, flow, return, spread, mixing circuit actual/target/deviation, heat pump vs. mixing circuit gap, external return, defrosts, hot water, HUP/ZUP pump run time (ZUP also without compressor), heat, offset, heating limit |
| `myuplink-auswertung-zyklen.csv` | Per compressor run: start, end, duration, preceding pause, averages (incl. mixing circuit target/deviation, external return), defrosts, hot water minutes, status |
| `myuplink-auswertung-einstellungen.csv` | Per value of "temperature + -": since when, heating hours, outdoor temperature, flow, return, mixing circuit target/actual, heat pump vs. mixing circuit gap. Shows the effect of a change. |

How it works:

- **Run time and cycles** from the switching times of VD1 (70), **starts** from counter 5674. If they differ, some runs were shorter than the polling interval.
- **Temperature averages** in heating mode only (operation mode 0), skipping the first 10 minutes of each run (`-EinschwingMinuten`) as well as defrost and hot water phases.
- **Gaps:** if two polls are more than 30 minutes apart (e.g. PC switched off), that time is excluded (`-LueckeMinuten`, 0 = off). Affected days and runs are marked.
- **Heat** is integrated from "Heating capacity" (21), so it is an estimate only. If the Luxtronik is logged via Modbus, electricity, heat and **daily performance factors** (heating, hot water, total) come from its counters, plus the **COP per run** and **per "temperature + -" setting**.

Additional checks (since 2.4.0):

- **Charging circuit vs. heating curve:** with a buffer sensor "return external" (3), the analysis shows two gaps: heat pump flow to buffer (`WP-Puf`, caused by the charging circuit's spread and flow rate) and buffer to mixing circuit target (`Puf-MK`, alignment of the heating curves). Without a buffer sensor it falls back to the gap to the mixing circuit.
- **Switching points:** buffer sensor minus return target (2) at start and stop of each run, shown as median over all runs. This reveals the switching hysteresis and whether a change takes effect.
- **Flow plausibility:** displayed flow rate (31) against the flow calculated from heat output and spread. A large mismatch means either the display or the actual flow is off.
- **COP by flow temperature** in 2 K classes (requires Luxtronik power values).
- **Mixing circuit stability:** share of minutes more than 2 K off target, day (6 am to 10 pm) and night.
- **Pumps:** run time of HUP and ZUP during compressor pauses, without interpretation, since their role depends on the hydraulics.

One month of log data takes about 20 seconds.

## Analysis on your phone (browser)

**[https://reinhardneumann.github.io/myUplink-Logger/auswertung/](https://reinhardneumann.github.io/myUplink-Logger/auswertung/)**

The same analysis as menu option 6 as a web page with charts: daily course (flow, buffer, mixing circuit target, heating/hot water/defrost phases), daily values as bars (performance factor, run time, starts and more), COP by flow temperature, switching points, tables and CSV export. The page is in German.

- **The log file stays on your device.** It is processed in the browser and never uploaded; the page has no server part.
- Getting the file onto the phone: e.g. let the logger write into a OneDrive or Google Drive folder and pick the file via "Logdatei öffnen".
- On Android in Chrome use "Add to Home screen" / "Install app"; afterwards the page also works offline.
- Results are identical to `Invoke-MyUplinkAuswertung` (same rules, tested against the PowerShell version).

## Analysis tips

- **Cycling:** compressor starts (5674) and run times from the On/Off changes of VD1 (70). Rule of thumb: runs of at least 20 to 30 minutes and no more than about 3 starts per hour are healthy.
- **Spread:** flow (0) minus return (1), only while the compressor runs. During pauses the pump often stops, so those values are not meaningful.
- **Mixing circuit:** the gap between heat pump flow (0) and mixing circuit (23). With a buffer, split it: a large heat-pump-to-buffer gap points to the charging circuit, a large buffer-to-mixing-circuit gap to the heating curve.
- **Mark experiments:** "temperature + -" (5001) and heating limit (5700) are logged, so setting changes are visible in the log.
- **COP:** the myUplink API provides no electrical power. The Luxtronik (Modbus) provides power and counters directly, see above.

## Privacy

The CSV contains the device ID (part of which matches the MAC address). Remove the `Geraet` column before sharing logs. Credentials are encrypted with Windows DPAPI in `%USERPROFILE%\.myuplink\credential.xml` and can only be read by the same user on the same computer.

## Troubleshooting

| Problem | Fix |
| --- | --- |
| Script does not start, security warning | Unblock the files (`Unblock-File`), see quick start |
| `401 Unauthorized` | Check Client ID/Secret, save them again with option 1 |
| No devices found | Is the heat pump online in the myUplink app? Was the API app created with the same account? |
| Scheduled task writes nothing | The task runs as a different user than the one who saved the credentials |
| Excel shows 40 instead of 4.0 | Set the decimal separator, see CSV format |

## Contributing

Feedback from other devices is welcome, especially parameter lists (option 2, remove the `Geraet` column first). Please report bugs and ideas as an [issue](../../issues).

## License

[MIT](LICENSE)
