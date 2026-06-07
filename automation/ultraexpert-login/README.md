# UltraExpert Login Script

Dieses kleine Script oeffnet `https://ux.winvalue.de/ux/` mit Playwright und versucht, den Login automatisch auszufuellen.

## Setup

```bash
cd "/Users/husseinsouleiman/Documents/SVS App/SVS App/automation/ultraexpert-login"
npm install playwright
cp .env.example .env
```

Danach traegst du in `.env` mindestens diese Werte ein:

```dotenv
UX_USERNAME=deine-kundennummer
UX_PASSWORD=dein-passwort
```

Falls UltraExpert bei euch ein eigenes Mandanten-Feld zeigt, kannst du auch `UX_MANDANT=` setzen.

## Start

Fuer einen sichtbaren lokalen Test:

```bash
npm run login:debug
```

Fuer einen normalen Lauf:

```bash
npm run login
```

Eine neue Akte anlegen:

```bash
npm run create:akte
```

Sichtbar mit offenem Browser:

```bash
npm run create:akte:debug
```

Webhook-Server fuer Google Apps Script starten:

```bash
npm run server
```

## Was das Script macht

- oeffnet die UltraExpert-Login-Seite
- sucht Felder fuer `Kundennummer`, `Benutzername`, `E-Mail`, `Passwort` und optional `Mandant`
- klickt auf `Anmelden` oder sendet `Enter`
- speichert bei Erfolg oder Fehler einen Screenshot in `artifacts/`
- speichert eine Sitzung optional in `storage-state.json`
- kann ueber `create-akte.mjs` danach `Neu -> Akte` klicken und die neue Akten-URL auslesen
- kann ueber `server.mjs` Webhook-Aufrufe von Google Apps Script empfangen und pro Drive-Ordner genau eine Akte anlegen

## Verbindung Mit Google Apps Script

Ergaenze in deiner `.env` noch:

```dotenv
PORT=3000
WEBHOOK_SECRET=irgendein-langer-geheimer-wert
AKTE_FOLDER_NAME_MUST_INCLUDE=gutachten
```

Dann startest du den Server lokal:

```bash
npm run server
```

Dein Google Apps Script muss danach bei einem neuen Ordner diese URL aufrufen:

```text
https://DEINE-OEFFENTLICHE-URL/new-folder
```

Beispiel fuer `handleNewFolder_(folder)` im Apps Script:

```javascript
const WEBHOOK_URL = 'https://DEINE-OEFFENTLICHE-URL/new-folder';
const WEBHOOK_SECRET = 'derselbe-wert-wie-in-.env';

function handleNewFolder_(folder) {
  const response = UrlFetchApp.fetch(WEBHOOK_URL, {
    method: 'post',
    contentType: 'application/json',
    headers: {
      'X-Webhook-Secret': WEBHOOK_SECRET
    },
    payload: JSON.stringify({
      folderId: folder.id,
      folderName: folder.name,
      folderUrl: folder.url,
      detectedAt: new Date().toISOString()
    }),
    muteHttpExceptions: true
  });

  console.log(response.getResponseCode());
  console.log(response.getContentText());
}
```

Wichtig:

- Lokal funktioniert das nur mit einer oeffentlichen URL nach draussen, zum Beispiel ueber Cloudflare Tunnel.
- Wenn derselbe Drive-Ordner zweimal gemeldet wird, verhindert `processed-folders.json` doppelte Akten.
- Standardmaessig wird nur dann eine Akte angelegt, wenn der Ordnername `gutachten` enthaelt. `RB`, `KVA` und andere Ordner werden dadurch automatisch uebersprungen.
- Falls du spaeter andere Begriffe erlauben willst, kannst du `.env` anpassen, zum Beispiel `AKTE_FOLDER_NAME_MUST_INCLUDE=gutachten,schaden`.

## Deployment Auf Einen VPS

Empfohlene Zielstruktur:

- Ubuntu 24.04
- Docker + Docker Compose
- dieses Projekt als Ordner auf dem Server

Dateien fuer Produktion:

- `Dockerfile`
- `compose.yml`
- `nginx.conf`

### Vorbereitung

Auf dem Server:

```bash
mkdir -p /opt/ultraexpert-login-bot
cd /opt/ultraexpert-login-bot
```

Projektdateien dorthin kopieren und dann:

```bash
cp .env.example .env
cp processed-folders.example.json processed-folders.json
cp storage-state.example.json storage-state.json
mkdir -p artifacts
```

Danach `.env` mit deinen echten Werten fuellen:

```dotenv
UX_URL=https://ux.winvalue.de/ux/
UX_USERNAME=deine-kundennummer
UX_PASSWORD=dein-passwort
WEBHOOK_SECRET=neuer-geheimer-wert
PORT=3000
UX_HEADLESS=true
UX_KEEP_OPEN=false
UX_REUSE_SESSION=true
UX_SLOW_MO=0
UX_TIMEOUT_MS=30000
```

### Starten

```bash
docker compose up -d --build
```

Danach sollte lokal auf dem Server erreichbar sein:

```bash
curl http://localhost/new-folder
```

### Google Apps Script

Sobald die Server-IP oder Domain auf den VPS zeigt, kommt dort hinein:

```javascript
const WEBHOOK_URL = 'https://DEINE-SERVER-URL/new-folder';
```

### Hinweis Zu HTTPS

`compose.yml` liefert zunaechst HTTP auf Port 80. Fuer eine echte Produktions-Domain solltest du danach noch HTTPS davor setzen, zum Beispiel mit:

- Cloudflare Proxy
- oder spaeter Caddy/Nginx mit Zertifikat

## Hinweise

- Die Login-Seite ist eine JavaScript-App. Darum ist Playwright hier die richtige Wahl.
- Falls sich die Feldnamen in eurem Account unterscheiden, muessen wir die Selektoren noch einmal feinjustieren.
- Fuer spaeteren Serverbetrieb solltest du `UX_HEADLESS=true` und `UX_KEEP_OPEN=false` verwenden.
