# Firestore Rules Tests

Diese Tests prüfen die produktiven Firestore-Regeln aus `../firestore.rules` (werden beim Testlauf automatisch nach `./firestore.rules` kopiert).

## Voraussetzungen

- Node.js (bereits vorhanden)
- Firebase CLI (bereits vorhanden)
- Java Runtime (für den Firestore Emulator erforderlich)

## Ausführen

```bash
npm --prefix "/Users/husseinsouleiman/Documents/SVS App/SVS App/rules-tests" install
npm --prefix "/Users/husseinsouleiman/Documents/SVS App/SVS App/rules-tests" test
```

## Abgedeckte Bereiche

- Rollen-Logik bei `users/*` (Admin vs. eigener Nutzer)
- Task-Regeln bei `tasks/*` (Create/Update/Delete für Creator/Assigned)
- Meeting-Regeln bei `meetingTopics/*`, `meetingMeta/*`, `meetingArchives/*`
