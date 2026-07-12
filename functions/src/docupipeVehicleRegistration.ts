const DOCUPIPE_BASE_URL = "https://app.docupipe.ai";

type DocuPipeJobStatus = "processing" | "completed" | "error";

export type VehicleRegistrationRecognitionResult = {
  clientLastName: string | null;
  clientFirstName: string | null;
  clientName: string | null;
  streetAndNumber: string | null;
  postalCode: string | null;
  city: string | null;
  licensePlate: string | null;
  vin: string | null;
  firstRegistrationDate: string | null;
  rawText: string;
};

type DocuPipeConfig = {
  apiKey: string;
  schemaId: string;
};

/**
 * Reads a string from a nested object using dot-separated paths.
 *
 * @param {Record<string, unknown>} data Source object.
 * @param {string[]} paths Candidate paths.
 * @return {string | null} First non-empty string value.
 */
function pickString(
  data: Record<string, unknown>,
  paths: string[]
): string | null {
  for (const path of paths) {
    const parts = path.split(".");
    let current: unknown = data;
    for (const part of parts) {
      if (!current || typeof current !== "object") {
        current = null;
        break;
      }
      current = (current as Record<string, unknown>)[part];
    }
    if (typeof current === "string") {
      const trimmed = current.trim();
      if (trimmed) return trimmed;
    }
  }
  return null;
}

/**
 * Normalizes Erstzulassung dates to ISO YYYY-MM-DD.
 *
 * @param {string | null} raw Raw date string from extraction.
 * @return {string | null} ISO date or null.
 */
function parseFirstRegistrationDate(raw: string | null): string | null {
  if (!raw) return null;
  const trimmed = raw.trim();
  if (!trimmed) return null;

  if (/^\d{4}-\d{2}-\d{2}$/.test(trimmed)) {
    return trimmed;
  }

  const germanMatch = trimmed.match(/(\d{2})\.(\d{2})\.(\d{4})/);
  if (germanMatch) {
    return `${germanMatch[3]}-${germanMatch[2]}-${germanMatch[1]}`;
  }

  const slashMatch = trimmed.match(/(\d{2})\/(\d{2})\/(\d{4})/);
  if (slashMatch) {
    return `${slashMatch[3]}-${slashMatch[2]}-${slashMatch[1]}`;
  }

  return null;
}

/**
 * Collects all string values from a nested object.
 *
 * @param {unknown} node Source node.
 * @param {string[]} out Accumulator.
 * @return {string[]} Collected strings.
 */
function collectStrings(node: unknown, out: string[] = []): string[] {
  if (typeof node === "string") {
    out.push(node);
    return out;
  }
  if (Array.isArray(node)) {
    node.forEach((item) => collectStrings(item, out));
    return out;
  }
  if (node && typeof node === "object") {
    Object.values(node).forEach((value) => collectStrings(value, out));
  }
  return out;
}

/**
 * Returns true when a text snippet refers to a non-Erstzulassung date field.
 *
 * @param {string} snippet Text around a date candidate.
 * @return {boolean} Whether the snippet should be ignored.
 */
function isForbiddenRegistrationDateContext(snippet: string): boolean {
  const lowered = snippet.toLowerCase();
  if (/datum\s+zu\s*4/.test(lowered)) return true;
  if (/produktion/.test(lowered)) return true;
  if (/baujahr/.test(lowered)) return true;
  if (/baudatum/.test(lowered)) return true;
  if (/nächste\s+hu/.test(lowered)) return true;
  if (/datum\s+dieser\s+zulassung/.test(lowered)) return true;
  if (/\bzu\s*k\b/.test(lowered)) return true;
  if (/(?:^|\s)6\b/.test(snippet) && /datum/.test(lowered)) return true;
  return false;
}

/**
 * Extracts Erstzulassung (field B) from German registration OCR text.
 *
 * @param {string} text OCR or document text.
 * @return {string | null} ISO date or null.
 */
export function extractErstzulassungDateFromText(text: string): string | null {
  const normalized = text.replace(/\s+/g, " ");
  const patterns = [
    /(?:feld\s*)?b\b[^0-9]{0,80}(\d{2}\.\d{2}\.\d{4})/i,
    /erstzulassung(?:\s+des\s+fahrzeugs)?[^0-9]{0,60}(\d{2}\.\d{2}\.\d{4})/i,
    /datum\s+der\s+erstzulassung[^0-9]{0,40}(\d{2}\.\d{2}\.\d{4})/i,
  ];

  for (const pattern of patterns) {
    const match = normalized.match(pattern);
    if (!match?.[1]) continue;
    if (isForbiddenRegistrationDateContext(match[0])) {
      continue;
    }
    const iso = parseFirstRegistrationDate(match[1]);
    if (iso) return iso;
  }

  return null;
}

/**
 * Resolves Erstzulassung preferring field-B text extraction over schema value.
 *
 * @param {Record<string, unknown>} data Standardized extraction payload.
 * @param {string | null} docuPipeValue Value from DocuPipe field mapping.
 * @param {string} ocrText Optional OCR text from the parsed document.
 * @return {string | null} ISO date or null.
 */
function resolveFirstRegistrationDate(
  data: Record<string, unknown>,
  docuPipeValue: string | null,
  ocrText: string
): string | null {
  const corpus = [ocrText, ...collectStrings(data)].filter(Boolean).join("\n");
  const fromFieldB = extractErstzulassungDateFromText(corpus);
  if (fromFieldB) {
    return fromFieldB;
  }
  return docuPipeValue;
}

/**
 * Extracts plain text from a DocuPipe document payload.
 *
 * @param {Record<string, unknown>} payload Document payload.
 * @return {string} Combined OCR text.
 */
function extractTextFromDocuPipeDocument(
  payload: Record<string, unknown>
): string {
  const parts: string[] = [];
  const pages = payload.pages;
  if (Array.isArray(pages)) {
    for (const page of pages) {
      if (!page || typeof page !== "object") continue;
      const pageRecord = page as Record<string, unknown>;
      if (typeof pageRecord.text === "string") {
        parts.push(pageRecord.text);
      }
      if (typeof pageRecord.markdown === "string") {
        parts.push(pageRecord.markdown);
      }
    }
  }
  if (typeof payload.text === "string") {
    parts.push(payload.text);
  }
  if (typeof payload.markdown === "string") {
    parts.push(payload.markdown);
  }
  return parts.join("\n");
}

/**
 * Fetches OCR text for a parsed DocuPipe document.
 *
 * @param {string} apiKey DocuPipe API key.
 * @param {string} documentId Parsed document id.
 * @return {Promise<string>} OCR text if available.
 */
async function fetchDocumentText(
  apiKey: string,
  documentId: string
): Promise<string> {
  const response = await fetch(`${DOCUPIPE_BASE_URL}/document/${documentId}`, {
    headers: {
      "accept": "application/json",
      "X-API-Key": apiKey,
    },
  });

  if (!response.ok) {
    return "";
  }

  const payload = await response.json() as Record<string, unknown>;
  return extractTextFromDocuPipeDocument(payload);
}

/**
 * Polls a DocuPipe job until it completes or fails.
 *
 * @param {string} apiKey DocuPipe API key.
 * @param {string} jobId Job identifier.
 * @param {number} maxAttempts Maximum poll attempts.
 * @return {Promise<Record<string, unknown>>} Completed job payload.
 */
async function pollDocuPipeJob(
  apiKey: string,
  jobId: string,
  maxAttempts = 20
): Promise<Record<string, unknown>> {
  let waitMs = 1500;

  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    const response = await fetch(`${DOCUPIPE_BASE_URL}/job/${jobId}`, {
      headers: {
        "accept": "application/json",
        "X-API-Key": apiKey,
      },
    });

    if (!response.ok) {
      const body = await response.text();
      throw new Error(`DocuPipe job poll failed (${response.status}): ${body}`);
    }

    const payload = await response.json() as Record<string, unknown>;
    const status = String(payload.status ?? "") as DocuPipeJobStatus;
    if (status === "completed") {
      return payload;
    }
    if (status === "error") {
      const message = String(payload.errorMessage ?? "DocuPipe job failed");
      throw new Error(message);
    }

    await new Promise((resolve) => setTimeout(resolve, waitMs));
    waitMs = Math.min(waitMs * 2, 8000);
  }

  throw new Error("DocuPipe job timed out");
}

/**
 * Uploads an image buffer to DocuPipe for parsing.
 *
 * @param {DocuPipeConfig} config DocuPipe credentials.
 * @param {Buffer} imageBuffer Image bytes.
 * @param {string} fileExtension File extension.
 * @return {Promise<{documentId: string, jobId: string}>} Upload identifiers.
 */
async function uploadDocumentToDocuPipe(
  config: DocuPipeConfig,
  imageBuffer: Buffer,
  fileExtension: "jpeg" | "png" | "webp"
): Promise<{documentId: string; jobId: string}> {
  const response = await fetch(`${DOCUPIPE_BASE_URL}/document`, {
    method: "POST",
    headers: {
      "accept": "application/json",
      "content-type": "application/json",
      "X-API-Key": config.apiKey,
    },
    body: JSON.stringify({
      document: {
        file: {
          contents: imageBuffer.toString("base64"),
          filename: `fahrzeugschein.${fileExtension}`,
          fileExtension,
          fileType: "image",
        },
      },
      dataset: "svs-fahrzeugschein",
      processingMethod: "asImage",
    }),
  });

  if (!response.ok) {
    const body = await response.text();
    throw new Error(`DocuPipe upload failed (${response.status}): ${body}`);
  }

  const payload = await response.json() as Record<string, unknown>;
  const documentId = String(payload.documentId ?? "").trim();
  const jobId = String(payload.jobId ?? "").trim();
  if (!documentId || !jobId) {
    throw new Error("DocuPipe upload returned incomplete payload");
  }
  return {documentId, jobId};
}

/**
 * Standardizes a parsed DocuPipe document with the configured schema.
 *
 * @param {DocuPipeConfig} config DocuPipe credentials.
 * @param {string} documentId Parsed document id.
 * @return {Promise<string>} Standardization id.
 */
async function standardizeDocument(
  config: DocuPipeConfig,
  documentId: string
): Promise<string> {
  const response = await fetch(`${DOCUPIPE_BASE_URL}/v3/standardize`, {
    method: "POST",
    headers: {
      "accept": "application/json",
      "content-type": "application/json",
      "X-API-Key": config.apiKey,
    },
    body: JSON.stringify({
      documentId,
      schemaId: config.schemaId,
      effortLevel: "standard",
      stdVersion: 3,
    }),
  });

  if (!response.ok) {
    const body = await response.text();
    throw new Error(
      `DocuPipe standardize failed (${response.status}): ${body}`
    );
  }

  const payload = await response.json() as Record<string, unknown>;
  const standardizationId = String(payload.standardizationId ?? "").trim();
  const jobId = String(payload.jobId ?? "").trim();
  if (!standardizationId || !jobId) {
    throw new Error("DocuPipe standardize returned incomplete payload");
  }

  await pollDocuPipeJob(config.apiKey, jobId);
  return standardizationId;
}

/**
 * Fetches standardized extraction data for a document.
 *
 * @param {DocuPipeConfig} config DocuPipe credentials.
 * @param {string} standardizationId Standardization id.
 * @return {Promise<Record<string, unknown>>} Extracted field object.
 */
async function fetchStandardizationData(
  config: DocuPipeConfig,
  standardizationId: string
): Promise<Record<string, unknown>> {
  const response = await fetch(
    `${DOCUPIPE_BASE_URL}/standardization/${standardizationId}`,
    {
      headers: {
        "accept": "application/json",
        "X-API-Key": config.apiKey,
      },
    }
  );

  if (!response.ok) {
    const body = await response.text();
    throw new Error(
      `DocuPipe standardization fetch failed (${response.status}): ${body}`
    );
  }

  const payload = await response.json() as Record<string, unknown>;
  const data = payload.data;
  if (!data || typeof data !== "object") {
    throw new Error("DocuPipe standardization returned no data");
  }
  return data as Record<string, unknown>;
}

/**
 * Maps DocuPipe extraction output to app OCR fields.
 *
 * @param {Record<string, unknown>} data Standardized extraction payload.
 * @param {string} ocrText Optional OCR text from DocuPipe document parse.
 * @return {VehicleRegistrationRecognitionResult} Normalized OCR result.
 */
export function mapDocuPipeVehicleRegistrationData(
  data: Record<string, unknown>,
  ocrText = ""
): VehicleRegistrationRecognitionResult {
  const ownerLastName = pickString(data, [
    "ownerLastName",
    "holderLastName",
    "lastName",
    "nachname",
    "owner.lastName",
    "holder.lastName",
    "ownerInformation.lastName",
    "renterInformation.tenantLastName",
  ]);
  const ownerFirstName = pickString(data, [
    "ownerFirstName",
    "holderFirstName",
    "firstName",
    "vorname",
    "owner.firstName",
    "holder.firstName",
    "ownerInformation.firstName",
    "renterInformation.tenantFirstName",
  ]);

  const streetAndNumber = pickString(data, [
    "ownerAddressStreet",
    "streetAndNumber",
    "street",
    "addressStreet",
    "ownerAddress.street",
    "ownerInformation.rentalAddress.street",
    "renterInformation.rentalAddress.street",
  ]);
  const postalCode = pickString(data, [
    "ownerAddressPostalCode",
    "postalCode",
    "zip",
    "plz",
    "ownerAddress.postalCode",
    "ownerInformation.rentalAddress.zip",
    "renterInformation.rentalAddress.zip",
  ]);
  const city = pickString(data, [
    "ownerAddressCity",
    "city",
    "ort",
    "ownerAddress.city",
    "ownerInformation.rentalAddress.city",
    "renterInformation.rentalAddress.city",
  ]);

  const combinedAddress = pickString(data, [
    "ownerAddress",
    "address",
    "holderAddress",
    "ownerInformation.address",
  ]);

  let resolvedStreet = streetAndNumber;
  let resolvedPostalCode = postalCode;
  let resolvedCity = city;

  if (combinedAddress && !resolvedStreet) {
    resolvedStreet = combinedAddress;
  }

  if ((!resolvedPostalCode || !resolvedCity) && combinedAddress) {
    const plzCityMatch = combinedAddress.match(/(\d{5})\s+(.+)$/);
    if (plzCityMatch) {
      resolvedPostalCode = resolvedPostalCode ?? plzCityMatch[1];
      resolvedCity = resolvedCity ?? plzCityMatch[2].trim();
    }
  }

  const licensePlate = pickString(data, [
    "licensePlate",
    "registrationNumber",
    "registrationMark",
    "kennzeichen",
    "officialLicensePlate",
    "vehicle.licensePlate",
    "vehicle.registrationMark",
  ]);
  const vin = pickString(data, [
    "vin",
    "vehicleIdentificationNumber",
    "fin",
    "vehicle.vin",
  ]);
  const docuPipeFirstRegistrationDate = parseFirstRegistrationDate(
    pickString(data, [
      "firstRegistrationDate",
      "dateOfFirstRegistration",
      "erstzulassung",
      "firstRegistration",
      "vehicle.firstRegistrationDate",
      "vehicle.dateOfFirstRegistration",
    ])
  );
  const firstRegistrationDate = resolveFirstRegistrationDate(
    data,
    docuPipeFirstRegistrationDate,
    ocrText
  );

  const clientName = [ownerLastName, ownerFirstName]
    .filter((part): part is string => Boolean(part))
    .join(" ")
    .trim();

  return {
    clientLastName: ownerLastName,
    clientFirstName: ownerFirstName,
    clientName: clientName || null,
    streetAndNumber: resolvedStreet,
    postalCode: resolvedPostalCode,
    city: resolvedCity,
    licensePlate,
    vin,
    firstRegistrationDate,
    rawText: ocrText || JSON.stringify(data),
  };
}

/**
 * Returns true when at least one business-relevant field was extracted.
 *
 * @param {VehicleRegistrationRecognitionResult} result OCR result.
 * @return {boolean} Whether extraction looks useful.
 */
export function hasUsefulVehicleRegistrationData(
  result: VehicleRegistrationRecognitionResult
): boolean {
  return Boolean(
    result.clientLastName ||
    result.clientFirstName ||
    result.clientName ||
    result.streetAndNumber ||
    result.postalCode ||
    result.city ||
    result.licensePlate
  );
}

/**
 * Runs DocuPipe upload, parse, and standardize for a vehicle image.
 *
 * @param {DocuPipeConfig} config DocuPipe credentials.
 * @param {Buffer} imageBuffer Image bytes.
 * @param {string} mimeType Image mime type.
 * @return {Promise<VehicleRegistrationRecognitionResult>} Mapped OCR result.
 */
export async function recognizeVehicleRegistrationWithDocuPipe(
  config: DocuPipeConfig,
  imageBuffer: Buffer,
  mimeType: string
): Promise<VehicleRegistrationRecognitionResult> {
  const normalizedMime = mimeType.toLowerCase();
  const fileExtension = normalizedMime.includes("png") ?
    "png" :
    normalizedMime.includes("webp") ?
      "webp" :
      "jpeg";

  const upload = await uploadDocumentToDocuPipe(
    config,
    imageBuffer,
    fileExtension
  );
  await pollDocuPipeJob(config.apiKey, upload.jobId);

  const standardizationId = await standardizeDocument(
    config,
    upload.documentId
  );
  const data = await fetchStandardizationData(config, standardizationId);
  const ocrText = await fetchDocumentText(config.apiKey, upload.documentId);
  const mapped = mapDocuPipeVehicleRegistrationData(data, ocrText);

  if (!hasUsefulVehicleRegistrationData(mapped)) {
    throw new Error("DocuPipe returned no usable vehicle registration fields");
  }

  return mapped;
}
