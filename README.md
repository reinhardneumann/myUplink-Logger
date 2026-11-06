# myUplink-Logger

🇩🇪 Deutsch · [🇬🇧 English](README.en.md)

PowerShell-Werkzeug, das Messwerte einer Wärmepumpe über die offizielle **myUplink-API** und optional direkt aus der **Luxtronik-Steuerung (Modbus TCP)** abruft und als CSV-Datei protokolliert. Entwickelt und getestet mit einer **alpha innotec Paros 4-2**, funktioniert grundsätzlich mit jedem Gerät, das in myUplink online ist.

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
| `MyUplink-Auswertung.ps1` | Auswertung der Logdatei (Takte, Tageswerte, Arbeitszahlen) |
| `auswertung/` | Auswertung im Browser für Handy, Tablet und PC (siehe unten) |
| `Luxtronik-Modbus.ps1` | Optional: Werte direkt aus der Luxtronik über Modbus TCP (Strom, Wärme, COP) |
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
7. **Menüpunkt 5:** zeigt die aktuelle Logdatei im Explorer (Standard: eine Datei pro Monat, `%USERPROFILE%\myuplink-log-JJJJ-MM.csv`).
8. **Menüpunkt 6:** wertet die Logdatei aus, optional für einen Zeitraum (siehe [Auswertung](#auswertung)).
9. **Menüpunkt 7:** IP der Luxtronik festlegen und Werte direkt anzeigen (siehe [Luxtronik direkt](#luxtronik-direkt-modbus-tcp)).
10. **Menüpunkt 8:** Monatsdateien ein- oder ausschalten (siehe [Monatsdateien](#monatsdateien)).

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

## Monatsdateien

Seit Version 2.6.0 schreibt der Logger **pro Monat eine eigene Datei**, z. B. `myuplink-log-2026-11.csv`, im selben Ordner wie bisher. Am Monatsanfang wird automatisch gewechselt; jede neue Datei beginnt mit einem vollständigen Satz aller Werte und ist dadurch auch allein auswertbar. Eine frühere `myuplink-log.csv` bleibt unverändert liegen.

- Die Auswertung (Menüpunkt 6 und Webseite) liest alle Dateien `myuplink-log*.csv` zusammen, die alte Datei eingeschlossen. Mit `-Von`/`-Bis` werden Monatsdateien außerhalb des Zeitraums gar nicht erst gelesen.
- Ausschalten (alles wieder in eine Datei): Menüpunkt 8 oder `Set-MyUplinkMonatsdateien -Ein $false`. Die Einstellung gilt auch für die Aufgabenplanung.
- Welche Datei gerade beschrieben wird: `Get-MyUplinkLogDatei`.

### Logdateien in die Cloud kopieren (z. B. für das Handy)

Den Logger **nicht direkt** in einen OneDrive- oder Google-Drive-Ordner schreiben lassen: Der Sync-Dienst lädt bei jeder Änderung die ganze Datei neu hoch (alle 5 Minuten) und sperrt sie dabei zeitweise, sodass Abrufe verloren gehen können. Besser eine zweite Aufgabe in der Aufgabenplanung, die z. B. alle 3 Stunden nur geänderte Dateien kopiert:

- Programm: `robocopy.exe`
- Argumente (Zielordner anpassen; bei Google Drive „Dateien spiegeln“ wählen):

  ```
  "%USERPROFILE%" "C:\Users\<Name>\Meine Ablage\Wärmepumpe" myuplink-log*.csv /R:2 /W:10 /NP /NJH /NJS
  ```

Robocopy kopiert nur Dateien, die sich geändert haben, also in der Regel nur die aktuelle Monatsdatei. Die Aufgabenplanung zeigt danach oft das Ergebnis `0x1` an: Das bedeutet bei Robocopy „Dateien kopiert“ und ist kein Fehler.

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

Jede Datei ist ein **Ereignisprotokoll**: Ein Wert wird nur geschrieben, wenn sich sein Zeitstempel in myUplink geändert hat. Für Diagramme jeden Wert bis zum nächsten Eintrag fortschreiben (in Excel z. B. per Pivot und „Leere Zellen mit vorherigem Wert füllen“, in Python mit `ffill()`).

**Dezimaltrennzeichen:** Standard ist die Windows-Einstellung (deutsch also Komma). Festlegen mit `Start-MyUplink.bat -Dezimaltrennzeichen ","` bzw. `"."` oder pro Aufruf `Write-MyUplinkLog -Dezimaltrennzeichen '.'`.

## Standard-Parameter

`0, 1, 2, 3, 5, 6, 17, 21, 22, 23, 31, 32, 33, 39, 45, 46, 57, 66, 67, 70, 5001, 5668, 5674, 5700, 5728, 5729`

Bedeutung und weitere verfügbare IDs: [docs/parameter.md](docs/parameter.md). Parameter-IDs können sich je nach Gerät und Firmware unterscheiden.

## Luxtronik direkt (Modbus TCP)

Viele alpha-innotec-Wärmepumpen (z. B. Paros) haben eine **Luxtronik**-Steuerung. Ab Firmware 3.90.1 bietet sie eine Smart-Home-Schnittstelle über Modbus TCP. Sie liefert Werte, die es in myUplink nicht gibt:

- elektrische Leistungsaufnahme und Heizleistung aktuell, daraus der **momentane COP**
- **Stromzähler** gesamt, Heizen, Warmwasser (ab 3.90.1) und **Wärmezähler** gesamt, Heizen, Warmwasser (ab 3.92.0), daraus die **Arbeitszahlen**
- Pufferkonfiguration, Mindestlauf- und Mindeststillstandszeit

**Einrichtung**

1. Im Regler unter **Smart Home** den Punkt **„ModBus TCP“ auf „Ein“** stellen. Der Status „Standby“ ist normal, solange nichts verbunden ist.
2. Die **IP-Adresse der Steuerung** ermitteln, z. B. im Router über die MAC-Adresse aus myUplink (Parameter 40011). Achtung: Neben der Steuerung kann ein weiteres Netzwerkmodul eine eigene IP haben.
3. **Menüpunkt 7**: IP eintragen. Die Werte erscheinen sofort, die IP wird gespeichert (`%USERPROFILE%\.myuplink\luxtronik-ip.txt`).
4. Logger neu starten (Menüpunkt 3 bzw. Aufgabenplanung). Die Luxtronik-Werte landen mit IDs wie `MB10301` in derselben CSV, jeweils nur bei Änderung.

In PowerShell direkt:

```powershell
. C:\Tools\myuplink-logger\MyUplink-Logger.ps1      # lädt Luxtronik-Modbus.ps1 mit
Set-LuxtronikIP 192.168.178.33
Show-LuxtronikModbus
```

Die Abfrage **liest nur** (Modbus-Funktion 04, Input-Register) und schreibt nichts in die Steuerung. Strom- und Wärmezähler berechnet die Steuerung selbst; sie sind kein geeichter Zähler, eignen sich aber gut für Vergleiche. Registerliste: [docs/parameter.md](docs/parameter.md#luxtronik-modbus-tcp).

## Auswertung

`MyUplink-Auswertung.ps1` liest die Logdatei und erstellt eine Tagesübersicht. Es greift nicht auf myUplink zu und kann jederzeit laufen, auch während der Logger aktiv ist.

```powershell
. C:\Tools\myuplink-logger\MyUplink-Auswertung.ps1
Invoke-MyUplinkAuswertung                                   # gesamte Logdatei
Invoke-MyUplinkAuswertung -Von 2026-11-05 -Bis 2026-11-11   # Zeitraum
Invoke-MyUplinkAuswertung -Hilfe
```

Im Fenster erscheint eine Tabelle pro Tag plus Gesamtzeile, darunter die Einstellungsänderungen (Offset, Heizgrenze), ein Vergleich des Heizbetriebs je Wert von „Temperatur + −“ und eine Einschätzung nach Faustregeln. Zusätzlich entstehen drei Dateien im Ordner der Logdatei:

| Datei | Inhalt |
| --- | --- |
| `myuplink-auswertung-tage.csv` | Pro Tag: Abdeckung, Außentemperatur, Starts, Laufzeit, Ø/min/max Lauf, Ø Pause, Starts je Laufstunde, Vorlauf, Rücklauf, Spreizung, Mischerkreis Ist/Soll/Abweichung, Abstand WP-Mischer, Rücklauf extern, Abtauungen, Warmwasser, Laufzeit HUP/ZUP (ZUP auch ohne Verdichter), Wärmemenge, Offset, Heizgrenze |
| `myuplink-auswertung-zyklen.csv` | Pro Verdichterlauf: Start, Ende, Dauer, Pause davor, Mittelwerte (inkl. Mischerkreis Soll/Abweichung, Rücklauf extern), Abtauungen, Warmwasser-Minuten, Status |
| `myuplink-auswertung-einstellungen.csv` | Pro Wert von „Temperatur + −“: ab wann, Heizstunden, Außentemperatur, Vorlauf, Rücklauf, Mischerkreis Soll/Ist, Abstand WP-Mischer. Zeigt, wie eine Änderung wirkt. |

So wird gerechnet:

- **Laufzeit und Zyklen** aus den Schaltzeitpunkten von VD1 (70), **Starts** aus dem Zähler 5674. Weichen beide ab, gab es Läufe, die kürzer als das Abrufintervall waren.
- **Temperaturmittel** nur im Heizbetrieb (Betriebszustand 0), ohne die ersten 10 Minuten jedes Laufs (`-EinschwingMinuten`) und ohne Abtau- und Warmwasserphasen.
- **Lücken:** Liegen zwei Abrufe mehr als 30 Minuten auseinander (z. B. PC aus), wird die Zeit dazwischen nicht ausgewertet (`-LueckeMinuten`, 0 = aus). Betroffene Tage und Läufe sind markiert.
- **Wärmemenge** aus „Heating capacity“ (21) hochgerechnet, daher nur ein Schätzwert. Wird die Luxtronik per Modbus mitgeloggt, kommen Strom, Wärme und **Arbeitszahlen pro Tag** (Heizen, Warmwasser, gesamt) aus deren Zählern, dazu der **COP je Lauf** und **je Einstellung „Temperatur + −“**.

Weitere Prüfungen (seit 2.4.0):

- **Ladekreis und Heizkurve getrennt:** Bei einem Puffer mit Fühler „Rücklauf extern“ (3) zeigt die Auswertung zwei Abstände: WP-Vorlauf zum Puffer (`WP-Puf`, entsteht im Ladekreis durch Spreizung und Volumenstrom) und Puffer zum Mischerkreis-Soll (`Puf-MK`, Abstimmung der Heizkurven). Ohne Pufferfühler bleibt es beim Abstand zum Mischerkreis.
- **Schaltpunkte:** Pufferfühler minus Rücklauf-Soll (2) bei Start und Stopp jedes Laufs, im Fenster als Median über alle Läufe. Daraus lässt sich die Schaltdifferenz ablesen und prüfen, ob eine Änderung wirkt.
- **Durchfluss-Plausibilität:** angezeigter Durchfluss (31) gegen den rechnerischen aus Heizleistung und Spreizung. Weicht beides stark ab, stimmt entweder die Anzeige oder der tatsächliche Volumenstrom nicht.
- **COP nach Vorlauftemperatur** in 2-K-Klassen (nur mit Luxtronik-Leistungswerten).
- **Stabilität des Mischerkreises:** Anteil der Minuten mit mehr als 2 K Abweichung vom Soll, getrennt nach Tag (6 bis 22 Uhr) und Nacht.
- **Pumpen:** Laufzeit von HUP und ZUP in den Verdichterpausen, ohne Deutung, weil die Zuordnung von der Hydraulik abhängt.

Ein Monat Log wird in etwa 20 Sekunden ausgewertet.

## Auswertung auf dem Handy (Browser)

**[https://reinhardneumann.github.io/myUplink-Logger/auswertung/](https://reinhardneumann.github.io/myUplink-Logger/auswertung/)**

Die gleiche Auswertung wie Menüpunkt 6 als Webseite, mit Diagrammen: Tagesverlauf (WP-Vorlauf, Puffer, Mischerkreis-Soll, Heiz-, Warmwasser- und Abtauphasen), Tageswerte als Balken (Arbeitszahl, Laufzeit, Starts und mehr), COP nach Vorlauftemperatur, Schaltpunkte, Tabellen und CSV-Export.

- **Die Logdatei bleibt auf dem Gerät.** Sie wird im Browser ausgewertet und nirgends hochgeladen; die Seite hat keinen Server-Teil.
- Dateien aufs Handy: die Logdateien regelmäßig in einen OneDrive- oder Google-Drive-Ordner kopieren (siehe [Logdateien in die Cloud kopieren](#logdateien-in-die-cloud-kopieren-z-b-für-das-handy)) und auf dem Handy über „Logdateien öffnen“ auswählen. Mehrere Monatsdateien lassen sich auf einmal markieren und werden zusammen ausgewertet.
- Auf Android in Chrome über das Menü „Zum Startbildschirm hinzufügen“ bzw. „App installieren“ wie eine App ablegen; die Seite funktioniert danach auch offline.
- Ergebnisse sind identisch mit `Invoke-MyUplinkAuswertung` (gleiche Rechenregeln, gegen die PowerShell-Version getestet).

## Auswertungstipps

- **Takten:** Verdichterstarts (5674) und Laufzeit aus den Wechseln von VD1 (70) „On“/„Off“. Faustregel: Läufe ab 20 bis 30 min und höchstens etwa 3 Starts pro Stunde gelten als gesund.
- **Spreizung:** Vorlauf (0) minus Rücklauf (1), nur während der Verdichter läuft. In den Pausen steht die Pumpe oft, die Werte sind dann nicht aussagekräftig.
- **Mischerkreis:** Abstand zwischen WP-Vorlauf (0) und Mischerkreis (23). Mit Puffer lohnt die Aufteilung: Ein großer Abstand WP–Puffer liegt am Ladekreis, ein großer Abstand Puffer–Mischerkreis an der Heizkurve.
- **Versuche markieren:** „temperature + −“ (5001) und Heizgrenze (5700) werden mitgeloggt. So ist im Log sichtbar, ab wann eine Einstellung geändert wurde.
- **COP:** Die myUplink-API liefert keine elektrische Leistung. Über die Luxtronik (Modbus) gibt es Leistung und Zähler direkt, siehe oben.

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
