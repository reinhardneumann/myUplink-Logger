# Changelog

## 2.3.0 – 2026-11-04

- Neu: `Luxtronik-Modbus.ps1` – liest die Luxtronik direkt über Modbus TCP (nur lesend): Leistungen, Strom- und Wärmezähler, Puffer, Mindestlauf-/Stillstandszeit
- Logger schreibt die Luxtronik-Werte optional in dieselbe CSV (IDs `MB…`, nur bei Änderung); IP per `Set-LuxtronikIP` bzw. Menüpunkt 7
- Auswertung: Strom, Wärme und Arbeitszahlen pro Tag (Heizen, Warmwasser, gesamt), COP je Lauf und je Einstellung „Temperatur + −“
- Menüpunkt 7 „Luxtronik direkt (Modbus)“

## 2.2.0 – 2026-11-04

- Auswertung nutzt jetzt auch Mischerkreis-Soll (22), Rücklauf extern (3), HUP (32) und ZUP (33)
- Neue Spalten: Mischerkreis Soll und Abweichung, Rücklauf extern, Laufzeit HUP/ZUP, ZUP ohne Verdichter
- Neu: Vergleich des Heizbetriebs je Wert von „Temperatur + −“ (Fenster und `myuplink-auswertung-einstellungen.csv`)

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
