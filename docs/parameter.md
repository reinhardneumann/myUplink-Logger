# Parameterreferenz: alpha innotec Paros 4-2

Alle Messpunkte, die die myUplink-API für eine Paros 4-2 (Steuerung `hp24`) liefert, Stand November 2026. Die Namen kommen englisch von myUplink. Die Bedeutung ist aus Luxtronik-Kürzeln und Beobachtung abgeleitet; Einträge mit „vermutlich“ sind nicht bestätigt. Bei anderen Geräten oder Firmwareständen können IDs fehlen oder anders belegt sein. Eigene Liste: Menüpunkt 2 bzw. `Get-MyUplinkData | Format-Table`.

**Standard** = wird ohne eigene Auswahl geloggt.

## Temperaturen

| ID | Name | Einheit | Bedeutung | Standard |
| --- | --- | --- | --- | --- |
| 0 | flow | °C | Vorlauf Wärmepumpe | ✔ |
| 1 | return | °C | Rücklauf Wärmepumpe | ✔ |
| 2 | return target | °C | Rücklauf-Soll (aus der Heizkurve) | ✔ |
| 3 | return external | °C | Externer Rücklauffühler (Position anlagenabhängig, z. B. Puffer) | ✔ |
| 5 | outdoor temp. | °C | Außentemperatur | ✔ |
| 39 | outdoor temp. ø | °C | Außentemperatur gemittelt | ✔ |
| 6 | DHW | °C | Warmwasser-Ist | ✔ |
| 7 | DHW target | °C | Warmwasser-Soll | |
| 40010 | DHW | °C | Warmwasser-Ist (zweiter Messpunkt, gleicher Wert wie 6) | |
| 22 | mix circ1 target | °C | Mischerkreis 1 Vorlauf-Soll | ✔ |
| 23 | mix circ1 flow | °C | Mischerkreis 1 Vorlauf-Ist | ✔ |

## Leistung, Durchfluss, Kältekreis

| ID | Name | Einheit | Bedeutung | Standard |
| --- | --- | --- | --- | --- |
| 21 | Heating capacity | kW | Thermische Heizleistung laut WP (Plausibilität prüfen) | ✔ |
| 31 | flow rate | l/h | Volumenstrom Ladekreis | ✔ |
| 66 | HD | bar | Hochdruck Kältekreis | ✔ |
| 67 | ND | bar | Niederdruck Kältekreis | ✔ |

## Betriebszustand

| ID | Name | Werte (Text) | Bedeutung | Standard |
| --- | --- | --- | --- | --- |
| 17 | operation mode | heating operation, domestic hot water, forced defrosting, no request | Aktueller Betriebszustand | ✔ |
| 45 | Status Heating | On, request, no request | Status Heizen | ✔ |
| 46 | Status DHW | On, request, no request | Status Warmwasser | ✔ |
| 57 | error | OK | Störungsstatus | ✔ |
| 58 | running time | hh:mm | Laufzeit (vermutlich aktueller Zyklus bzw. Störungs-Zeit) | |
| 5003, 5004 | mode of operation | automatic | Betriebsart Heizen / Warmwasser (vermutlich) | |
| 40001, 40007, 40009 | mode of operation | heat, off | Weitere Betriebsart-Punkte (Bedeutung unklar) | |

## Ausgänge und Eingänge

| ID | Name | Bedeutung | Standard |
| --- | --- | --- | --- |
| 70 | VD1 | Verdichter 1 an/aus | ✔ |
| 32 | HUP | Heizungsumwälzpumpe | ✔ |
| 33 | ZUP | Zusatzumwälzpumpe (z. B. Mischerkreis) | ✔ |
| 68 | BUP - DHW pump | Brauchwasser-Umwälzpumpe bzw. Umschaltventil | |
| 72 | ZIP | Zirkulationspumpe | |
| 69 | VBO | Ventilator (bei Luft-WP) | |
| 73 | ZWE 1 | Zweiter Wärmeerzeuger (Heizstab) | |
| 51 | el. heater | Elektroheizung | |
| 52 | immers. heater active | Heizstab aktiv | |
| 42 | EVU | EVU-Sperrkontakt (On = keine Sperre, vermutlich) | |
| 43 | EVU 2 | Zweiter EVU-Kontakt | |
| 63 | ASD | Eingang Abtau-/Durchflussschalter (vermutlich) | |
| 64 | HD | Hochdruckpressostat (Eingang, nicht der Druck) | |
| 65 | MOT | Motorschutz | |
| 78, 79 | AO 1, AO 2 | Analogausgänge in V (vermutlich Pumpensteuerung) | |

## Zähler

| ID | Name | Einheit | Bedeutung | Standard |
| --- | --- | --- | --- | --- |
| 5674 | impulse VD1 | – | Verdichterstarts | ✔ |
| 5668 | operating hours HP | h | Betriebsstunden Wärmepumpe | ✔ |
| 5669 | operating hours VD1 | h | Betriebsstunden Verdichter | |
| 5728 | operat. hours heat. | h | Betriebsstunden Heizen | ✔ |
| 5729 | operating hours DHW | h | Betriebsstunden Warmwasser | ✔ |
| 5671 | operating hours ZWE1 | h | Betriebsstunden Zusatzheizung | |

Die Stundenzähler zählen nur volle Stunden.

## Einstellungen

| ID | Name | Einheit | Bedeutung | Standard |
| --- | --- | --- | --- | --- |
| 5001 | temperature + - | °C | Parallelverschiebung Heizkurve (wirkt auf das WP-Rücklauf-Soll) | ✔ |
| 5700 | heating limit | °C | Heizgrenze | ✔ |
| 5002 | coverage HP | °C | Bedeutung unklar | |
| 5105 | desired value | °C | Warmwasser-Soll (vermutlich) | |
| 6146 | targ.value | °C | Soll für Extra-Warmwasser (vermutlich) | |
| 6147 | duration extra DHW | s | Dauer Extra-Warmwasser | |
| 25000 | high-speed charge | on/off | Schnellladung Warmwasser | |
| 25001 | Extra DHW | on/off | Extra-Warmwasser | |

## Gerät

| ID | Name | Bedeutung |
| --- | --- | --- |
| 40011 | MAC | MAC-Adresse der Steuerung (nicht teilen) |

## Nicht verfügbar

Elektrische Leistung und elektrische Energie liefert die API bei der Paros nicht. Für einen COP ist ein separater Stromzähler nötig.

Ergänzungen und Korrekturen bitte als Issue oder Pull Request.
