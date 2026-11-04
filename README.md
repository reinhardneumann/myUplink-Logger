# myUplink-Logger

🇩🇪 Deutsch · [🇬🇧 English](README.en.md)

PowerShell-Werkzeug, das Messwerte einer Wärmepumpe über die offizielle **myUplink-API** abruft und als CSV-Datei protokolliert. Entwickelt und getestet mit einer **alpha innotec Paros 4-2**, funktioniert grundsätzlich mit jedem Gerät, das in myUplink online ist.

Wozu? Die myUplink-App zeigt aktuelle Werte, aber kaum Verläufe. Mit dem Log lassen sich Taktverhalten (Verdichterstarts, Laufzeiten, Pausen), Vor- und Rücklauf, Spreizung, Abtauungen und Warmwasserzyklen über Tage und Wochen auswerten, z. B. in Excel.

- Nur lesend: Das Programm ändert nichts an der Anlage.
- Keine Zusatzsoftware: Windows PowerShell 5.1 oder PowerShell 7 genügt.
- Zugangsdaten werden verschlüsselt pro Windows-Benutzer gespeichert, nie im Klartext.

> Dies ist ein privates Projekt und steht in keiner Verbindung zu alpha innotec, ait-deutschland oder myUplink.

## Inhalt

| Datei | Zweck |
| --- | --- |
| `Start-MyUplink.bat` | Startet das Menü per Doppelklick |
| `MyUplink-Menue.ps1` | Textmenü (Zugangsdaten, Test, Logger, Hilfe) |
| `MyUplink-Logger.ps1` | Die eigentlichen Funktionen |
| `MyUplink-Auswertung.ps1` | Auswertung der Logdatei (Takte, Tageswerte) |
| `docs/parameter.md` | Parameterreferenz einer Paros 4-2 |

Alle Dateien gehören in denselben Ordner.

## Voraussetzungen

1. Windows mit PowerShell 5.1 oder 7.
2. Ein myUplink-Konto, in dem die Wärmepumpe online ist.
3. Eine eigene API-Anwendung unter <https://dev.myuplink.com/apps>. Sie liefert **Client ID** und **Client Secret**.
   - Der normale myUplink-Login (Mail und Passwort) funktioniert an der API **nicht**.
   - Falls das Formular eine Callback-URL verlangt: Sie wird hier nicht benutzt, ein beliebiger Wert genügt.
   - Jeder Nutzer legt seine eigene Anwendung an. Zugangsdaten bitte nicht weitergeben.

## Schnellstart (Menü)

1. Repository als ZIP herunterladen (grüner Button „Code“ → „Download ZIP“) und entpacken, z. B. nach `C:\Tools\myuplink-logger`.
2. Falls Windows den Start blockiert: Dateien per Rechtsklick → Eigenschaften → „Zulassen“ freigeben, oder in PowerShell `Get-ChildItem C:\Tools\myuplink-logger | Unblock-File`.
3. `Start-MyUplink.bat` per Doppelklick starten.
4. **Menüpunkt 1:** Client ID als Benutzername, Client Secret als Kennwort eingeben.
5. **Menüpunkt 2:** Verbindung testen. Es erscheinen alle Messpunkte der Anlage. Die Liste lässt sich als CSV auf dem Desktop speichern.
6. **Menüpunkt 3:** Logger starten. Intervall (Standard 5 min) und optional eigene Parameter-IDs angeben. Das Fenster muss offen bleiben, Beenden mit Strg+C.
7. **Menüpunkt 5:** zeigt die Logdatei `%USERPROFILE%\myuplink-log.csv` im Explorer.
8. **Menüpunkt 6:** wertet die Logdatei aus, optional für einen Zeitraum (siehe [Auswertung](#auswertung)).

> Die Standardauswahl der Parameter passt zur Paros 4-2 des Autors. Bei einer anderen Anlage zuerst Menüpunkt 2 ausführen und die gewünschten IDs bei Menüpunkt 3 eingeben.

## Dauerbetrieb über die Windows-Aufgabenplanung

Für den Betrieb im Hintergrund ohne offenes Fenster:

1. Aufgabenplanung öffnen → „Aufgabe erstellen“. Sie muss unter **demselben Windows-Benutzer** laufen, mit dem die Zugangsdaten gespeichert wurden.
2. Trigger: täglich, „Aufgabe wiederholen jede: 5 Minuten“, Dauer „Unbegrenzt“.
3. Aktion: Programm `powershell.exe`, Argumente:

   ```
   -NoProfile -ExecutionPolicy Bypass -Command ". 'C:\Tools\myuplink-logger\MyUplink-Logger.ps1'; Write-MyUplinkLog"
   ```

4. Optional unter „Bedingungen“ die Option „Nur starten, falls Computer im Netzbetrieb“ abwählen.

Jeder Start liest den letzten Stand aus der CSV und schreibt nur neue Werte. Duplikate entstehen nicht.

## Nutzung direkt in PowerShell

```powershell
. C:\Tools\myuplink-logger\MyUplink-Logger.ps1      # Funktionen laden (Punkt + Leerzeichen)
Save-MyUplinkCredential                              # einmalig
Get-MyUplinkData | Format-Table                      # alle Messpunkte anzeigen
Get-MyUplinkData -ParameterId 5674,70 | Format-Table # nur bestimmte IDs
Start-MyUplinkLogger -IntervalMinutes 5 -Verbose     # Dauerschleife
Show-MyUplinkHilfe                                   # Hilfe zu allen Funktionen
```

| Funktion | Zweck |
| --- | --- |
| `Save-MyUplinkCredential` | Client ID und Secret verschlüsselt speichern |
| `Get-MyUplinkData` | Aktuelle Messpunkte abrufen (`-ParameterId`, `-Name` mit Platzhaltern, `-DeviceId`) |
| `Write-MyUplinkLog` | Ein Abrufzyklus, hängt nur geänderte Werte an die CSV an |
| `Start-MyUplinkLogger` | Dauerschleife im Intervall, läuft bei Netzfehlern weiter |
| `Show-MyUplinkHilfe` | Deutsche Hilfetexte, auch per `<Funktion> -Hilfe` |

## CSV-Format

Trennzeichen Semikolon, UTF-8. Eine Zeile pro Messpunkt und Änderung:

| Spalte | Inhalt |
| --- | --- |
| `Abgerufen` | Zeitpunkt des Abrufs (lokale Zeit) |
| `Geraet` | Geräte-ID in myUplink |
| `ParameterId` | ID des Messpunkts |
| `Name` | Name laut myUplink (englisch) |
| `Wert` | Zahlenwert |
| `Einheit` | z. B. °C, kW, l/h, bar |
| `Text` | Klartext, z. B. „heating operation“, „On“ |
| `Zeitstempel` | Messzeitpunkt laut myUplink (UTC) |

Die Datei ist ein **Ereignisprotokoll**: Ein Wert wird nur geschrieben, wenn sich sein Zeitstempel in myUplink geändert hat. Für Diagramme jeden Wert bis zum nächsten Eintrag fortschreiben (in Excel z. B. per Pivot und „Leere Zellen mit vorherigem Wert füllen“, in Python mit `ffill()`).

**Dezimaltrennzeichen:** Standard ist die Windows-Einstellung (deutsch also Komma). Festlegen mit `Start-MyUplink.bat -Dezimaltrennzeichen ","` bzw. `"."` oder pro Aufruf `Write-MyUplinkLog -Dezimaltrennzeichen '.'`.

## Standard-Parameter

`0, 1, 2, 3, 5, 6, 17, 21, 22, 23, 31, 32, 33, 39, 45, 46, 57, 66, 67, 70, 5001, 5668, 5674, 5700, 5728, 5729`

Bedeutung und weitere verfügbare IDs: [docs/parameter.md](docs/parameter.md). Parameter-IDs können sich je nach Gerät und Firmware unterscheiden.

## Auswertung

`MyUplink-Auswertung.ps1` liest die Logdatei und erstellt eine Tagesübersicht. Es greift nicht auf myUplink zu und kann jederzeit laufen, auch während der Logger aktiv ist.

```powershell
. C:\Tools\myuplink-logger\MyUplink-Auswertung.ps1
Invoke-MyUplinkAuswertung                                   # gesamte Logdatei
Invoke-MyUplinkAuswertung -Von 2026-11-05 -Bis 2026-11-11   # Zeitraum
Invoke-MyUplinkAuswertung -Hilfe
```

Im Fenster erscheint eine Tabelle pro Tag plus Gesamtzeile, darunter die Einstellungsänderungen (Offset, Heizgrenze) und eine Einschätzung nach Faustregeln. Zusätzlich entstehen zwei Dateien im Ordner der Logdatei:

| Datei | Inhalt |
| --- | --- |
| `myuplink-auswertung-tage.csv` | Pro Tag: Abdeckung, Außentemperatur, Starts, Laufzeit, Ø/min/max Lauf, Ø Pause, Starts je Laufstunde, Vorlauf, Rücklauf, Spreizung, Mischerkreis, Abstand WP-Mischer, Abtauungen, Warmwasser, Wärmemenge, Offset, Heizgrenze |
| `myuplink-auswertung-zyklen.csv` | Pro Verdichterlauf: Start, Ende, Dauer, Pause davor, Mittelwerte, Abtauungen, Warmwasser-Minuten, Status |

So wird gerechnet:

- **Laufzeit und Zyklen** aus den Schaltzeitpunkten von VD1 (70), **Starts** aus dem Zähler 5674. Weichen beide ab, gab es Läufe, die kürzer als das Abrufintervall waren.
- **Temperaturmittel** nur im Heizbetrieb (Betriebszustand 0), ohne die ersten 10 Minuten jedes Laufs (`-EinschwingMinuten`) und ohne Abtau- und Warmwasserphasen.
- **Lücken:** Liegen zwei Abrufe mehr als 30 Minuten auseinander (z. B. PC aus), wird die Zeit dazwischen nicht ausgewertet (`-LueckeMinuten`, 0 = aus). Betroffene Tage und Läufe sind markiert.
- **Wärmemenge** aus „Heating capacity“ (21) hochgerechnet, daher nur ein Schätzwert.

Ein Monat Log wird in etwa 20 Sekunden ausgewertet.

## Auswertungstipps

- **Takten:** Verdichterstarts (5674) und Laufzeit aus den Wechseln von VD1 (70) „On“/„Off“. Faustregel: Läufe ab 20 bis 30 min und höchstens etwa 3 Starts pro Stunde gelten als gesund.
- **Spreizung:** Vorlauf (0) minus Rücklauf (1), nur während der Verdichter läuft. In den Pausen steht die Pumpe oft, die Werte sind dann nicht aussagekräftig.
- **Mischerkreis:** Abstand zwischen WP-Vorlauf (0) und Mischerkreis-Vorlauf (23). Ein großer Abstand heißt, die WP erzeugt höher als die Heizkörper brauchen.
- **Versuche markieren:** „temperature + −“ (5001) und Heizgrenze (5700) werden mitgeloggt. So ist im Log sichtbar, ab wann eine Einstellung geändert wurde.
- **COP:** Die myUplink-API liefert bei der Paros keine elektrische Leistung. Für einen COP braucht es einen separaten Stromzähler.

## Datenschutz

Die CSV enthält die Geräte-ID (und Teile davon entsprechen der MAC-Adresse). Beim Teilen von Logs die Spalte `Geraet` entfernen. Die Zugangsdaten liegen per Windows-DPAPI verschlüsselt in `%USERPROFILE%\.myuplink\credential.xml` und sind nur für denselben Benutzer auf demselben Rechner lesbar.

## Fehlerbehebung

| Problem | Lösung |
| --- | --- |
| Skript startet nicht, Sicherheitswarnung | Dateien freigeben (`Unblock-File`), siehe Schnellstart |
| `401 Unauthorized` | Client ID/Secret prüfen, mit Menüpunkt 1 neu speichern |
| Keine Geräte gefunden | Wärmepumpe in der myUplink-App online? Ist die API-App mit demselben Konto angelegt? |
| Aufgabenplanung schreibt nichts | Aufgabe läuft unter einem anderen Benutzer als die gespeicherten Zugangsdaten |
| Excel zeigt 40 statt 4,0 | Dezimaltrennzeichen festlegen, siehe CSV-Format |

## Mitmachen

Rückmeldungen mit anderen Geräten sind willkommen, besonders Parameterlisten (Menüpunkt 2, Spalte `Geraet` vorher entfernen). Fehler und Wünsche bitte als [Issue](../../issues) melden.

## Lizenz

[MIT](LICENSE)
