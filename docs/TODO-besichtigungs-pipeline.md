# TODO: Besichtigungs-Pipeline (eigener Haupt-Tab)

Status: geplant  
Kontext: Produktentscheidung aus Produktgespräch (Juli 2026)

## Ziel

Eine **geführte Besichtigung** als eigener Haupt-Tab, die den kompletten Vor-Ort-Ablauf abdeckt — ohne „Flow in Flow“.

Der bestehende **Scanner-Tab** bleibt für die **manuelle Form** erhalten und steht weiterhin eigenständig bereit.

## Pipeline (Checkliste oben)

Reihenfolge der Bausteine:

1. **AE** – Abtretungserklärung (bestehender Mini-Funnel)
2. **BD** – Begleitdokument (eBD, neu/hybrid)
3. **Vollmacht** – RA-Vollmacht (anbindung analog bestehendem Dokumenten-/Signaturflow)
4. **Bilder** – Aufnehmen und direkt nach Google Drive hochladen

Jeder Baustein hat seinen **eigenen inneren Flow**. Nach Abschluss zurück zur Checkliste; erledigt = abgehakt. Überspringen bleibt möglich.

Keine verschachtelte Navigation à la „Schritt 3 von 4 und darin Schritt 5 von 8“.

## Navigation / Tabs

- **Neuer Haupt-Tab** für die Besichtigungs-Pipeline (Name offen, z. B. „Besichtigung“)
- **Scanner / Gutachten-Tab** bleibt separat für den manuellen Scan-/Upload-Pfad
- AE-Funnel und künftige eBD sollen sich in die Pipeline einhängen; manuell bleibt parallel nutzbar

## eBD (Begleitdokument)

Nicht 1:1 wie AE (reine Textfelder), sondern **Hybrid**:

- Formular-/Chip-Teil für Checkboxen und Kernfelder (KM, HU, WV, Dauer, Gutachten-Nr., …)
- Zeichnen nur wo nötig (Schadenbereich o. Ä.)
- Datenübernahme aus eAE wo sinnvoll (Nr., Kennzeichen, …)

## Explizit nicht Pflichtpfad

- **Schadenhergang-Skizze** bleibt optionales Hilfstool, nicht Baustein der Pipeline

## Abhängigkeiten / Reihenfolge (Umsetzung)

1. eAE + Bild-Upload nach Drive fertigstellen / anbinden (WIP)
2. eBD-Ausfüll-UX (Hybrid) bauen
3. Pipeline-Checkliste + neuer Haupt-Tab
4. Vollmacht in denselben Fall-Kontext hängen
5. Scanner-Tab auf die manuelle Variante fokussieren (kein Wegbrechen der bestehenden Nutzung)

## Akzeptanzkriterien (grob)

- [ ] Neuer Haupt-Tab mit Checkliste AE → BD → Vollmacht → Bilder
- [ ] Jeder Baustein startet seinen eigenen Flow und kehrt zur Checkliste zurück
- [ ] Scanner-Tab bleibt parallel für manuelle Scans nutzbar
- [ ] BD lässt sich strukturiert ausfüllen (nicht nur freies PDF-Zeichnen)
- [ ] Bilder landen im zugehörigen Drive-Ordner der Akte
- [ ] Skizze ist nicht Teil des Pflichtpfads
