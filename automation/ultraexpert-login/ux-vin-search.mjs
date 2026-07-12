import {
  config,
  dedupeMatches,
  normalizeVin,
  saveArtifacts
} from "./ux-common.mjs";

/**
 * Searches UltraExpert dossiers by FIN/VIN via the dossiers info API.
 *
 * @param {import("playwright").Page} page
 * @param {string} vin
 * @returns {Promise<Array<{gutachtenNumber: string, dossierId?: string, dossierUrl?: string}>>}
 */
export async function searchDossiersByVin(page, vin) {
  const normalizedVin = normalizeVin(vin);
  if (normalizedVin.length < 11) {
    throw new Error("Ungueltige FIN. Mindestens 11 Zeichen erwartet.");
  }

  const base = config.url.replace(/\/?$/, "/");
  await page.goto(`${base}home/dossiers`, { waitUntil: "domcontentloaded" });
  await page.waitForLoadState("networkidle", { timeout: 8000 }).catch(() => {});

  const apiUrl =
    `${base}api/v1/dossiers/info?page=0&size=50&sort=createDate,DESC&query=` +
    encodeURIComponent(normalizedVin);

  const response = await page.request.get(apiUrl);
  if (!response.ok()) {
    throw new Error(
      `UltraExpert API-Antwort fehlgeschlagen (HTTP ${response.status()}).`
    );
  }

  const payload = await response.json();
  await saveArtifacts(page, `vin-search-${normalizedVin.slice(-6)}`);

  const content = Array.isArray(payload?.content) ? payload.content : [];
  const matches = content
    .map(item => mapDossierToMatch(item, base))
    .filter(Boolean);

  return dedupeMatches(matches);
}

function mapDossierToMatch(item, base) {
  const gutachtenNumber = String(
    item?.referenceNr ||
    item?.aktenzeichen ||
    item?.fileNumber ||
    item?.dossierNumber ||
    ""
  ).trim();

  if (!gutachtenNumber) {
    return null;
  }

  const dossierId = item?.id ? String(item.id) : undefined;
  const dossierUrl = dossierId
    ? `${base}home/dossiers/edit/${dossierId}/order/general`
    : undefined;

  return {
    gutachtenNumber,
    dossierId,
    dossierUrl
  };
}
