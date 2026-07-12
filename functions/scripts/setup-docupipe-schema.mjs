#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import {fileURLToPath} from "node:url";

const baseUrl = "https://app.docupipe.ai";
const apiKey = String(process.env.DOCUPIPE_API_KEY ?? "").trim();

if (!apiKey) {
  console.error("Set DOCUPIPE_API_KEY before running this script.");
  process.exit(1);
}

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const schemaPath = path.resolve(
  scriptDir,
  "../docupipe/german-vehicle-registration.schema.json"
);
const schemaFile = JSON.parse(fs.readFileSync(schemaPath, "utf8"));

const response = await fetch(`${baseUrl}/schema`, {
  method: "POST",
  headers: {
    "accept": "application/json",
    "content-type": "application/json",
    "X-API-Key": apiKey,
  },
  body: JSON.stringify(schemaFile),
});

const bodyText = await response.text();
if (!response.ok) {
  console.error(`Schema creation failed (${response.status}): ${bodyText}`);
  process.exit(1);
}

const payload = JSON.parse(bodyText);
const schemaId = String(payload.schemaId ?? "").trim();
if (!schemaId) {
  console.error("Schema creation succeeded but no schemaId was returned.");
  console.error(bodyText);
  process.exit(1);
}

console.log("DocuPipe schema created.");
console.log(`schemaId: ${schemaId}`);
console.log("");
console.log("Next steps:");
console.log("1) firebase functions:secrets:set DOCUPIPE_API_KEY");
console.log(
  "2) firebase functions:secrets:set DOCUPIPE_VEHICLE_REGISTRATION_SCHEMA_ID"
);
console.log(
  "3) firebase deploy --only functions:recognizeVehicleRegistrationHttp"
);
