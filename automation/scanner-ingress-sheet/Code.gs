/**
 * Scanner-Eingangsliste: Zeile löschen (ohne Google Sheets API im Firebase-Projekt).
 *
 * Einrichtung:
 * 1. In diesem Sheet: Erweiterungen → Apps Script → diesen Code einfügen
 * 2. Projekt-Einstellungen → Skripteigenschaften:
 *    SVS_ADMIN_SECRET = ein langes Geheimnis (z. B. zufällig 32 Zeichen)
 * 3. Bereitstellen → Neue Bereitstellung → Web-App
 *    - Ausführen als: Ich
 *    - Zugriff: Nur ich (reicht für Server-Aufruf mit Secret)
 * 4. Web-App-URL in Firestore speichern:
 *    scannerMeta/current → ingressAdminWebappUrl + ingressAdminWebappSecret
 *
 * Alternative (einfacher): Google Sheets API im Firebase-Projekt aktivieren.
 */

const SPREADSHEET_ID = "10mfm9SVVDiWcxnfK2QuUCj3msaVFBQIQx34NnPlUEo4";

function doPost(e) {
  try {
    const expected = PropertiesService.getScriptProperties()
      .getProperty("SVS_ADMIN_SECRET");
    const body = JSON.parse((e && e.postData && e.postData.contents) || "{}");
    if (!expected || body.secret !== expected) {
      return jsonResponse({ok: false, error: "Unauthorized"});
    }

    const rowNumber = Number(body.rowNumber);
    if (!Number.isFinite(rowNumber) || rowNumber < 2) {
      return jsonResponse({ok: false, error: "Ungültige Zeilennummer."});
    }

    const sheet = SpreadsheetApp.openById(SPREADSHEET_ID).getSheets()[0];
    sheet.deleteRow(Math.floor(rowNumber));
    return jsonResponse({ok: true});
  } catch (err) {
    const message = err && err.message ? String(err.message) : String(err);
    return jsonResponse({ok: false, error: message});
  }
}

function jsonResponse(payload) {
  return ContentService
    .createTextOutput(JSON.stringify(payload))
    .setMimeType(ContentService.MimeType.JSON);
}
