# Changelog

## 2.1.0 – 2026-11-04

- Neu: `MyUplink-Auswertung.ps1` mit `Invoke-MyUplinkAuswertung` – Verdichterzyklen, Tageswerte, Abtauungen, Warmwasser, Einstellungsänderungen und Einschätzung nach Faustregeln, Ausgabe zusätzlich als CSV
- Menüpunkt 6 „Logdatei auswerten“

## 2.0.0 – 2026-11-04

- Standardauswahl erweitert um 3 (return external), 22/23 (Mischerkreis 1 Soll/Ist), 32 (HUP) und 33 (ZUP)
- Dezimaltrennzeichen für die CSV wählbar (`-Dezimaltrennzeichen Auto|,|.`)
- Menü (`Start-MyUplink.bat`, `MyUplink-Menue.ps1`)
- Parameterreferenz `docs/parameter.md`, README auf Deutsch und Englisch

## 1.0.0 – 2026-11-03

- Erste Version: Abruf über die myUplink-API, Log nur geänderter Werte als CSV
