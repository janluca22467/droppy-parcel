# droppy-parcel

Paket-Tracking für [Droppy](https://getdroppy.app): DHL- und DPD-Sendungen als Live-Aktivität in der Notch. Kommt ein Paket heute, erscheint „heute“ neben der Notch. Die Übersicht liegt im Shelf.

## Funktionen

- DHL und DPD, mehrere Sendungen gleichzeitig
- Live-Aktivität in der Notch, sobald ein Paket in Zustellung ist oder für heute angekündigt wird
- Shelf-Widget mit Status je Sendung, solo und im Paar
- Automatische Aktualisierung (5 bis 60 Minuten), zugestellte Pakete verschwinden nach drei Tagen
- Optional dauerhaft in der Notch fixierbar

## Voraussetzungen

- Droppy 15.3 oder neuer, oder Droppy Playground
- DHL: kostenloser API-Schlüssel von [developer.dhl.com](https://developer.dhl.com) (Produkt „Shipment Tracking – Unified“)
- DPD: kein Schlüssel nötig

## Installation

```bash
droppykit build
```

Die Datei `.build/PaketTracking.droplet` in Droppy unter Einstellungen, Store, Lokale Droplets freigeben. Für Droppy Playground nach
`~/Library/Application Support/Droppy Playground/Droplets/paket-tracking/` kopieren und das Playground neu starten.

## Einrichtung

In den Einstellungen des Droplets Paketdienst und Sendungsnummer eintragen, optional eine Bezeichnung. Für DHL den API-Schlüssel hinterlegen.

## Datenschutz

Sendungsnummern und der DHL-Schlüssel werden nur lokal in den Droplet-Einstellungen gespeichert. Abfragen gehen direkt an `api-eu.dhl.com` und `tracking.dpd.de`.

## Hinweise

- Der DPD-Abruf nutzt den öffentlichen Endpunkt der DPD-Sendungsverfolgung. Er ist nicht offiziell dokumentiert und kann sich ändern.
- „Kommt heute“ gilt bei Status „In Zustellung“ oder wenn die voraussichtliche Zustellung heute ist.

## Lizenz

MIT
