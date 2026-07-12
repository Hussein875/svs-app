#!/usr/bin/env node
/**
 * Updates DocuPipe schema guidelines for correct Erstzulassung (field B only).
 *
 * Usage:
 *   DOCUPIPE_API_KEY=... SCHEMA_ID=V9jYCeWb node scripts/patch-docupipe-erstzulassung-guidelines.mjs
 */

const baseUrl = "https://app.docupipe.ai";
const apiKey = String(process.env.DOCUPIPE_API_KEY ?? "").trim();
const schemaId = String(process.env.SCHEMA_ID ?? "V9jYCeWb").trim();

const guidelines =
  "Extract data from a German Zulassungsbescheinigung Teil I (Fahrzeugschein). " +
  "Use official field codes when visible: C.1.1 Nachname, C.1.2 Vorname, C.1.3 Adresse, " +
  "B Erstzulassung, E Kennzeichen, A FIN. Return null for missing fields. " +
  "Dates as YYYY-MM-DD when possible. CRITICAL for firstRegistrationDate: use ONLY field B " +
  "(Datum der Erstzulassung des Fahrzeugs). NEVER use field 6, NEVER use production/" +
  "manufacturing date (Baudatum, Produktionsdatum, Datum zu 4), NEVER field I " +
  "(Datum dieser Zulassung), NEVER field K/HU dates.";

if (!apiKey) {
  console.error("Set DOCUPIPE_API_KEY.");
  process.exit(1);
}

const getResponse = await fetch(`${baseUrl}/schema/${schemaId}`, {
  headers: {
    accept: "application/json",
    "X-API-Key": apiKey,
  },
});

if (!getResponse.ok) {
  console.error(`Could not load schema (${getResponse.status}):`, await getResponse.text());
  process.exit(1);
}

const existing = await getResponse.json();
const jsonSchema = existing.jsonSchema ?? existing.schema ?? {};
const properties = jsonSchema.properties ?? {};

if (properties.firstRegistrationDate) {
  properties.firstRegistrationDate = {
    ...properties.firstRegistrationDate,
    description:
      "Field B only: Datum der Erstzulassung des Fahrzeugs " +
      "(NOT field 6 production date, NOT field I). Format YYYY-MM-DD",
  };
}

const patchBody = {
  schemaName: existing.schemaName ?? "SVS German Vehicle Registration (Fahrzeugschein ZB I)",
  jsonSchema: {
    ...jsonSchema,
    properties,
  },
  guidelines,
};

const patchResponse = await fetch(`${baseUrl}/schema/${schemaId}`, {
  method: "PUT",
  headers: {
    accept: "application/json",
    "content-type": "application/json",
    "X-API-Key": apiKey,
  },
  body: JSON.stringify(patchBody),
});

const patchText = await patchResponse.text();
if (!patchResponse.ok) {
  console.error(`Schema patch failed (${patchResponse.status}): ${patchText}`);
  process.exit(1);
}

console.log("Schema guidelines updated for Erstzulassung (field B only).");
console.log(patchText);
