#!/usr/bin/env node
/**
 * Adds firstRegistrationDate to an existing DocuPipe schema via API.
 *
 * Usage:
 *   DOCUPIPE_API_KEY=... SCHEMA_ID=... node scripts/patch-docupipe-schema-erstzulassung.mjs
 */

const baseUrl = "https://app.docupipe.ai";
const apiKey = String(process.env.DOCUPIPE_API_KEY ?? "").trim();
const schemaId = String(process.env.SCHEMA_ID ?? "").trim();

if (!apiKey || !schemaId) {
  console.error("Set DOCUPIPE_API_KEY and SCHEMA_ID.");
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
  console.log("Schema already contains firstRegistrationDate.");
  process.exit(0);
}

properties.firstRegistrationDate = {
  type: "string",
  description: "Date of first registration / Erstzulassung (field B), format YYYY-MM-DD",
};

const patchBody = {
  schemaName: existing.schemaName ?? "SVS German Vehicle Registration (Fahrzeugschein ZB I)",
  jsonSchema: {
    ...jsonSchema,
    properties,
  },
  guidelines: String(existing.guidelines ?? "").includes("Erstzulassung") ?
    existing.guidelines :
    `${existing.guidelines ?? ""} Include field B Erstzulassung as firstRegistrationDate (YYYY-MM-DD).`.trim(),
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
  console.error("");
  console.error("Fallback: add this field manually in the DocuPipe dashboard:");
  console.error("  firstRegistrationDate — Erstzulassung (Feld B), YYYY-MM-DD");
  process.exit(1);
}

console.log("Schema updated with firstRegistrationDate.");
console.log(patchText);
