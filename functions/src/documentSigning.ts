import * as admin from "firebase-admin";
import * as crypto from "crypto";
import {onRequest} from "firebase-functions/v2/https";
import {PDFDocument, StandardFonts, rgb} from "pdf-lib";
import {
  DocumentSigningTemplate,
  NormalizedPlacement,
  getDocumentSigningTemplate,
} from "./documentSigningPlacements";

const COLLECTION = "documentSigningLinks";
const STORAGE_PREFIX = "document-signing";
const PUBLIC_FORM_BASE_URL =
  "https://svs-app-864ed.web.app/document-sign";
const ALLOWED_CORS_ORIGINS = new Set([
  "https://svs-app-864ed.web.app",
  "https://svs-app-864ed.firebaseapp.com",
  "https://sv-souleiman.de",
]);

type LinkStatus = "unused" | "signed" | "expired" | "not_found";

interface CreateDocumentSigningLinkBody {
  documentId?: string;
  accidentDateIso?: string;
  customerName?: string;
  notes?: string;
  ttlDays?: number;
  prefilledPdfBase64?: string;
}

interface SubmitDocumentSigningBody {
  token?: string;
  signaturePngBase64?: string;
  signingDateIso?: string;
}

interface UpdateSignedPdfBody {
  token?: string;
  signedPdfBase64?: string;
  labelPlacements?: Record<string, NormalizedPlacement>;
}

/**
 * Applies CORS headers for the public web form.
 *
 * @param {Object} res Express response.
 * @param {Object} req HTTP request.
 */
function applyDocumentSigningCors(
  res: {set: (k: string, v: string) => void},
  req: {get?: (name: string) => string | undefined}
): void {
  const origin = String(req.get?.("origin") ?? "").trim();
  if (ALLOWED_CORS_ORIGINS.has(origin)) {
    res.set("Access-Control-Allow-Origin", origin);
  }
  res.set("Vary", "Origin");
}

/**
 * Reads client IP from proxy headers when available.
 *
 * @param {unknown} req HTTP request.
 * @return {string | null} IP address.
 */
function getHeaderIp(req: unknown): string | null {
  const request = req as {
    get?: (name: string) => string | undefined;
    ip?: string;
  };
  const forwarded = String(request.get?.("x-forwarded-for") ?? "").trim();
  if (forwarded) {
    return forwarded.split(",")[0]?.trim() || null;
  }
  const ip = String(request.ip ?? "").trim();
  return ip || null;
}

/**
 * Formats an ISO date as dd.MM.yyyy (de-DE).
 *
 * @param {string} iso ISO date string.
 * @return {string} German date label.
 */
function formatGermanDate(iso: string): string {
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) {
    return "";
  }
  const day = String(date.getUTCDate()).padStart(2, "0");
  const month = String(date.getUTCMonth() + 1).padStart(2, "0");
  const year = date.getUTCFullYear();
  return `${day}.${month}.${year}`;
}

/**
 * Converts normalized top-left placement to pdf-lib coordinates.
 *
 * @param {NormalizedPlacement} placement Normalized placement.
 * @param {number} pageWidth Page width in points.
 * @param {number} pageHeight Page height in points.
 * @return {object} Absolute rectangle in PDF space.
 */
function placementToPdfRect(
  placement: NormalizedPlacement,
  pageWidth: number,
  pageHeight: number
): {x: number; y: number; width: number; height: number} {
  const width = pageWidth * placement.width;
  const height = pageHeight * placement.height;
  const x = pageWidth * placement.x;
  const y = pageHeight * (1 - placement.y - placement.height);
  return {x, y, width, height};
}

/**
 * Draws left-aligned text inside a normalized placement.
 *
 * @param {Object} page PDF page.
 * @param {string} text Text to draw.
 * @param {NormalizedPlacement} placement Normalized placement.
 * @param {Object} font Embedded PDF font.
 */
function drawPlacementText(
  page: import("pdf-lib").PDFPage,
  text: string,
  placement: NormalizedPlacement,
  font: import("pdf-lib").PDFFont
): void {
  const trimmed = String(text ?? "").trim();
  if (!trimmed) return;

  const {width: pageWidth, height: pageHeight} = page.getSize();
  const rect = placementToPdfRect(placement, pageWidth, pageHeight);
  const fontSize = Math.max(7, Math.min(12, rect.height * 0.72));

  page.drawText(trimmed, {
    font,
    x: rect.x,
    y: rect.y + Math.max(0, (rect.height - fontSize) / 2),
    size: fontSize,
    color: rgb(0, 0, 0),
    maxWidth: rect.width,
  });
}

/**
 * Embeds a PNG signature and draws it into the placement rect.
 *
 * @param {PDFDocument} pdfDoc PDF document.
 * @param {Object} page Target page.
 * @param {Buffer} pngBuffer Signature PNG bytes.
 * @param {NormalizedPlacement} placement Signature placement.
 */
async function drawSignaturePng(
  pdfDoc: PDFDocument,
  page: import("pdf-lib").PDFPage,
  pngBuffer: Buffer,
  placement: NormalizedPlacement
): Promise<void> {
  const image = await pdfDoc.embedPng(pngBuffer);
  const {width: pageWidth, height: pageHeight} = page.getSize();
  const rect = placementToPdfRect(placement, pageWidth, pageHeight);
  const scale = Math.min(rect.width / image.width, rect.height / image.height);
  const width = image.width * scale;
  const height = image.height * scale;
  const x = rect.x + (rect.width - width) / 2;
  const y = rect.y + (rect.height - height) / 2;

  page.drawImage(image, {x, y, width, height});
}

/**
 * Returns signed read URL for a storage object.
 *
 * @param {string} storagePath Firebase Storage path.
 * @return {Promise<string | null>} Signed URL.
 */
async function signedReadUrl(storagePath: string): Promise<string | null> {
  try {
    const bucket = admin.storage().bucket();
    const file = bucket.file(storagePath);
    const [url] = await file.getSignedUrl({
      action: "read",
      expires: Date.now() + 60 * 60 * 1000,
    });
    return url;
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    console.warn("[signedReadUrl] FAILED", storagePath, msg);
    return null;
  }
}

/**
 * Resolves the storage path for a signed PDF, with a conventional fallback.
 *
 * @param {string} token Link token.
 * @param {FirebaseFirestore.DocumentData | undefined} data Firestore data.
 * @return {Promise<string | null>} Existing storage path.
 */
async function resolveSignedStoragePath(
  token: string,
  data: FirebaseFirestore.DocumentData | undefined
): Promise<string | null> {
  const explicit = String(data?.signedStoragePath ?? "").trim();
  const candidates = [
    explicit,
    `${STORAGE_PREFIX}/${token}/signed.pdf`,
  ].filter(Boolean);

  const bucket = admin.storage().bucket();
  for (const path of candidates) {
    const [exists] = await bucket.file(path).exists();
    if (exists) {
      return path;
    }
  }
  return null;
}

/**
 * Returns a signed PDF either as a short-lived URL or base64 payload.
 *
 * @param {string} storagePath Firebase Storage path.
 * @return {Promise<object>} Download payload.
 */
async function signedPdfDownloadPayload(
  storagePath: string
): Promise<{signedPdfUrl?: string; signedPdfBase64?: string}> {
  const signedPdfUrl = await signedReadUrl(storagePath);
  if (signedPdfUrl) {
    return {signedPdfUrl};
  }

  const bucket = admin.storage().bucket();
  const [pdfBytes] = await bucket.file(storagePath).download();
  if (!pdfBytes.length) {
    throw new Error("signed pdf empty");
  }
  return {signedPdfBase64: pdfBytes.toString("base64")};
}

/**
 * Resolves the public link status for a token document.
 *
 * @param {FirebaseFirestore.DocumentData | undefined} data Firestore data.
 * @return {LinkStatus} Resolved status.
 */
function resolveLinkStatus(
  data: FirebaseFirestore.DocumentData | undefined
): LinkStatus {
  const status = String(data?.status ?? "unused");
  const expiresAtTs = data?.expiresAt as admin.firestore.Timestamp | undefined;
  const signedAtTs = data?.signedAt as admin.firestore.Timestamp | undefined;
  const nowMs = Date.now();
  const expiresMs = expiresAtTs ? expiresAtTs.toDate().getTime() : 0;

  if (status === "signed" || signedAtTs) {
    return "signed";
  }
  if (expiresAtTs && expiresMs < nowMs) {
    return "expired";
  }
  return "unused";
}

/**
 * Stamps customer signature and signing date onto the prefilled PDF.
 *
 * @param {Buffer} prefilledPdf Prefilled PDF bytes.
 * @param {DocumentSigningTemplate} template Placement template.
 * @param {Buffer} signaturePng Signature PNG bytes.
 * @param {string} signingDateText German signing date label.
 * @return {Promise<Buffer>} Signed PDF bytes.
 */
async function buildSignedPdf(
  prefilledPdf: Buffer,
  template: DocumentSigningTemplate,
  signaturePng: Buffer,
  signingDateText: string
): Promise<Buffer> {
  const pdfDoc = await PDFDocument.load(prefilledPdf);
  const page = pdfDoc.getPage(template.signature.pageIndex);
  const font = await pdfDoc.embedFont(StandardFonts.Helvetica);

  await drawSignaturePng(pdfDoc, page, signaturePng, template.signature);
  drawPlacementText(page, signingDateText, template.signingDate, font);

  const bytes = await pdfDoc.save({useObjectStreams: false});
  return Buffer.from(bytes);
}

// ------------------------------------------------------------------
// POST /createDocumentSigningLink
// Auth: Bearer Firebase ID token
// Body: documentId, accidentDateIso, customerName?, notes?, ttlDays?,
// prefilledPdfBase64
// ------------------------------------------------------------------

export const createDocumentSigningLink = onRequest(async (req, res) => {
  try {
    if (req.method !== "POST") {
      res.status(405).json({ok: false, error: "Method not allowed"});
      return;
    }

    const authHeader = String(req.header("authorization") ?? "");
    if (!authHeader.startsWith("Bearer ")) {
      res.status(401).json({ok: false, error: "Unauthorized"});
      return;
    }

    const idToken = authHeader.slice("Bearer ".length).trim();
    if (!idToken) {
      res.status(401).json({ok: false, error: "Unauthorized"});
      return;
    }

    const decoded = await admin.auth().verifyIdToken(idToken);
    const callerUid = decoded.uid;

    const body = (req.body ?? {}) as Partial<CreateDocumentSigningLinkBody>;
    const documentId = String(body.documentId ?? "").trim();
    const template = getDocumentSigningTemplate(documentId);
    if (!template) {
      res.status(400).json({ok: false, error: "unsupported documentId"});
      return;
    }

    const accidentDateIso = String(body.accidentDateIso ?? "").trim();
    if (!accidentDateIso || Number.isNaN(Date.parse(accidentDateIso))) {
      res.status(400).json({ok: false, error: "accidentDateIso required"});
      return;
    }

    const prefilledPdfBase64 = String(body.prefilledPdfBase64 ?? "").trim();
    if (!prefilledPdfBase64) {
      res.status(400).json({ok: false, error: "prefilledPdfBase64 required"});
      return;
    }

    const prefilledPdf = Buffer.from(prefilledPdfBase64, "base64");
    if (!prefilledPdf.length) {
      res.status(400).json({ok: false, error: "invalid prefilledPdfBase64"});
      return;
    }

    const ttlDaysRaw = Number(body.ttlDays ?? 14);
    const ttlDays =
      Number.isFinite(ttlDaysRaw) ?
        Math.max(1, Math.min(90, ttlDaysRaw)) :
        14;
    const expiresAtDate = new Date(
      Date.now() + ttlDays * 24 * 60 * 60 * 1000
    );
    const expiresAt = admin.firestore.Timestamp.fromDate(expiresAtDate);

    const token = crypto.randomUUID();
    const prefilledStoragePath = `${STORAGE_PREFIX}/${token}/prefilled.pdf`;

    const bucket = admin.storage().bucket();
    await bucket.file(prefilledStoragePath).save(prefilledPdf, {
      contentType: "application/pdf",
      resumable: false,
      metadata: {
        cacheControl: "private, max-age=0, no-transform",
      },
    });

    const customerName = String(body.customerName ?? "").trim() || null;
    const notes = String(body.notes ?? "").trim() || null;

    await admin.firestore().collection(COLLECTION).doc(token).set({
      token,
      documentId,
      documentTitle: template.title,
      status: "unused",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt,
      signedAt: null,
      createdByUid: callerUid,
      customerName,
      notes,
      accidentDateIso,
      prefilledStoragePath,
      signedStoragePath: null,
    });

    const url = `${PUBLIC_FORM_BASE_URL}?token=${token}`;

    res.status(200).json({
      ok: true,
      token,
      url,
      expiresAt: expiresAtDate.toISOString(),
      documentId,
      documentTitle: template.title,
    });
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error("[createDocumentSigningLink] FAILED", e);
    res.status(500).json({ok: false, error: msg});
  }
});

// ------------------------------------------------------------------
// GET /getDocumentSigningLink?token=<uuid>
// ------------------------------------------------------------------

export const getDocumentSigningLink = onRequest(async (req, res) => {
  try {
    applyDocumentSigningCors(res, req);
    res.set("Access-Control-Allow-Methods", "GET,OPTIONS");
    res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");

    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }

    if (req.method !== "GET") {
      res.status(405).json({ok: false, error: "Method not allowed"});
      return;
    }

    const token = String(req.query.token ?? "").trim();
    if (!token) {
      res.status(400).json({ok: false, error: "token required"});
      return;
    }

    const snap = await admin
      .firestore()
      .collection(COLLECTION)
      .doc(token)
      .get();
    if (!snap.exists) {
      res.status(200).json({ok: true, status: "not_found"});
      return;
    }

    const data = snap.data() ?? {};
    const status = resolveLinkStatus(data);
    const expiresAtTs =
      data.expiresAt as admin.firestore.Timestamp | undefined;
    const signedAtTs = data.signedAt as admin.firestore.Timestamp | undefined;

    const basePayload = {
      ok: true,
      status,
      documentId: String(data.documentId ?? ""),
      documentTitle: String(data.documentTitle ?? ""),
      customerName: String(data.customerName ?? "") || null,
      accidentDateIso: String(data.accidentDateIso ?? "") || null,
      expiresAt: expiresAtTs ? expiresAtTs.toDate().toISOString() : null,
      signedAt: signedAtTs ? signedAtTs.toDate().toISOString() : null,
    };

    if (status === "signed") {
      const signedStoragePath = await resolveSignedStoragePath(token, data);
      if (signedStoragePath) {
        const payload = await signedPdfDownloadPayload(signedStoragePath);
        res.status(200).json({...basePayload, ...payload});
        return;
      }
      res.status(200).json({...basePayload, signedPdfUrl: null});
      return;
    }

    if (status === "expired") {
      res.status(200).json(basePayload);
      return;
    }

    const prefilledStoragePath = String(data.prefilledStoragePath ?? "").trim();
    const pdfUrl = prefilledStoragePath ?
      await signedReadUrl(prefilledStoragePath) :
      null;

    let prefilledPdfBase64: string | null = null;
    if (prefilledStoragePath) {
      try {
        const bucket = admin.storage().bucket();
        const [pdfBytes] = await bucket.file(prefilledStoragePath).download();
        if (pdfBytes.length) {
          prefilledPdfBase64 = pdfBytes.toString("base64");
        }
      } catch (e: unknown) {
        const msg = e instanceof Error ? e.message : String(e);
        console.warn(
          "[getDocumentSigningLink] prefilled base64 read failed",
          msg
        );
      }
    }

    res.status(200).json({...basePayload, pdfUrl, prefilledPdfBase64});
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error("[getDocumentSigningLink] FAILED", e);
    res.status(500).json({ok: false, error: msg});
  }
});

// ------------------------------------------------------------------
// POST /submitDocumentSigningForm
// ------------------------------------------------------------------

export const submitDocumentSigningForm = onRequest(async (req, res) => {
  try {
    applyDocumentSigningCors(res, req);
    res.set("Access-Control-Allow-Methods", "POST,OPTIONS");
    res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");

    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }

    if (req.method !== "POST") {
      res.status(405).json({ok: false, error: "Method not allowed"});
      return;
    }

    const body = (req.body ?? {}) as Partial<SubmitDocumentSigningBody>;
    const token = String(body.token ?? "").trim();
    const signatureB64 = String(body.signaturePngBase64 ?? "").trim();

    if (!token) {
      res.status(400).json({ok: false, error: "token required"});
      return;
    }
    if (!signatureB64) {
      res.status(400).json({ok: false, error: "signature required"});
      return;
    }

    const signingDateIso = String(body.signingDateIso ?? "").trim();
    const signingDateText =
      signingDateIso && !Number.isNaN(Date.parse(signingDateIso)) ?
        formatGermanDate(signingDateIso) :
        formatGermanDate(new Date().toISOString());

    const signaturePng = Buffer.from(signatureB64, "base64");
    if (!signaturePng.length) {
      res.status(400).json({ok: false, error: "invalid signature"});
      return;
    }

    const db = admin.firestore();
    const tokenRef = db.collection(COLLECTION).doc(token);
    const snap = await tokenRef.get();

    if (!snap.exists) {
      res.status(404).json({ok: false, error: "token not found"});
      return;
    }

    const data = snap.data() ?? {};
    const status = resolveLinkStatus(data);
    if (status === "signed") {
      res.status(409).json({ok: false, error: "token already used"});
      return;
    }
    if (status === "expired") {
      res.status(410).json({ok: false, error: "token expired"});
      return;
    }

    const documentId = String(data.documentId ?? "").trim();
    const template = getDocumentSigningTemplate(documentId);
    if (!template) {
      res.status(500).json({ok: false, error: "template missing"});
      return;
    }

    const prefilledStoragePath = String(data.prefilledStoragePath ?? "").trim();
    if (!prefilledStoragePath) {
      res.status(500).json({ok: false, error: "prefilled pdf missing"});
      return;
    }

    const bucket = admin.storage().bucket();
    const [prefilledPdf] = await bucket.file(prefilledStoragePath).download();
    const signedPdf = await buildSignedPdf(
      prefilledPdf,
      template,
      signaturePng,
      signingDateText
    );

    const signedStoragePath = `${STORAGE_PREFIX}/${token}/signed.pdf`;
    await bucket.file(signedStoragePath).save(signedPdf, {
      contentType: "application/pdf",
      resumable: false,
      metadata: {
        cacheControl: "private, max-age=0, no-transform",
      },
    });

    await db.runTransaction(async (tx) => {
      const latest = await tx.get(tokenRef);
      if (!latest.exists) {
        throw new Error("token not found");
      }
      const latestData = latest.data() ?? {};
      const latestStatus = resolveLinkStatus(latestData);
      if (latestStatus === "signed") {
        throw new Error("token already used");
      }
      if (latestStatus === "expired") {
        throw new Error("token expired");
      }

      tx.update(tokenRef, {
        status: "signed",
        signedAt: admin.firestore.FieldValue.serverTimestamp(),
        signingDateIso: signingDateIso || new Date().toISOString(),
        signedStoragePath,
        signedBy: "web",
        userAgent: String(req.get("user-agent") ?? "").trim() || null,
        ip: getHeaderIp(req),
      });
    });

    res.status(200).json({ok: true, token});
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error("[submitDocumentSigningForm] FAILED", e);
    res.status(500).json({ok: false, error: msg});
  }
});

// ------------------------------------------------------------------
// GET /listDocumentSigningLinks?documentId=av-wessels
// Auth: Bearer Firebase ID token
// ------------------------------------------------------------------

export const listDocumentSigningLinks = onRequest(async (req, res) => {
  try {
    if (req.method !== "GET") {
      res.status(405).json({ok: false, error: "Method not allowed"});
      return;
    }

    const authHeader = String(req.header("authorization") ?? "");
    if (!authHeader.startsWith("Bearer ")) {
      res.status(401).json({ok: false, error: "Unauthorized"});
      return;
    }

    const idToken = authHeader.slice("Bearer ".length).trim();
    if (!idToken) {
      res.status(401).json({ok: false, error: "Unauthorized"});
      return;
    }

    const decoded = await admin.auth().verifyIdToken(idToken);
    const callerUid = decoded.uid;
    const documentId = String(req.query.documentId ?? "").trim();

    const snap = await admin
      .firestore()
      .collection(COLLECTION)
      .where("createdByUid", "==", callerUid)
      .limit(50)
      .get();

    const links = await Promise.all(
      snap.docs.map(async (doc) => {
        const data = doc.data() ?? {};
        const token = String(data.token ?? doc.id);
        const expiresAtTs =
          data.expiresAt as admin.firestore.Timestamp | undefined;
        const signedAtTs =
          data.signedAt as admin.firestore.Timestamp | undefined;
        const createdAtTs =
          data.createdAt as admin.firestore.Timestamp | undefined;
        const status = resolveLinkStatus(data);
        const signedStoragePath = status === "signed" ?
          await resolveSignedStoragePath(token, data) :
          null;
        return {
          token,
          documentId: String(data.documentId ?? ""),
          documentTitle: String(data.documentTitle ?? ""),
          customerName: String(data.customerName ?? "") || null,
          status,
          signedPdfAvailable: Boolean(signedStoragePath),
          accidentDateIso: String(data.accidentDateIso ?? "") || null,
          signingDateIso: String(data.signingDateIso ?? "") || null,
          labelPlacements: data.labelPlacements ?? null,
          createdAt: createdAtTs ? createdAtTs.toDate().toISOString() : null,
          signedAt: signedAtTs ? signedAtTs.toDate().toISOString() : null,
          expiresAt: expiresAtTs ? expiresAtTs.toDate().toISOString() : null,
        };
      })
    );
    const sortedLinks = links
      .filter((row) => !documentId || row.documentId === documentId)
      .sort((a, b) => {
        const aMs = a.createdAt ? Date.parse(a.createdAt) : 0;
        const bMs = b.createdAt ? Date.parse(b.createdAt) : 0;
        return bMs - aMs;
      });

    res.status(200).json({ok: true, links: sortedLinks});
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error("[listDocumentSigningLinks] FAILED", e);
    res.status(500).json({ok: false, error: msg});
  }
});

// ------------------------------------------------------------------
// GET /getDocumentSigningDownload?token=<uuid>
// Auth: Bearer Firebase ID token (link creator)
// ------------------------------------------------------------------

export const getDocumentSigningDownload = onRequest(async (req, res) => {
  try {
    if (req.method !== "GET") {
      res.status(405).json({ok: false, error: "Method not allowed"});
      return;
    }

    const authHeader = String(req.header("authorization") ?? "");
    if (!authHeader.startsWith("Bearer ")) {
      res.status(401).json({ok: false, error: "Unauthorized"});
      return;
    }

    const idToken = authHeader.slice("Bearer ".length).trim();
    if (!idToken) {
      res.status(401).json({ok: false, error: "Unauthorized"});
      return;
    }

    const decoded = await admin.auth().verifyIdToken(idToken);
    const callerUid = decoded.uid;

    const token = String(req.query.token ?? "").trim();
    if (!token) {
      res.status(400).json({ok: false, error: "token required"});
      return;
    }

    const snap = await admin
      .firestore()
      .collection(COLLECTION)
      .doc(token)
      .get();
    if (!snap.exists) {
      res.status(404).json({ok: false, error: "token not found"});
      return;
    }

    const data = snap.data() ?? {};
    const createdByUid = String(data.createdByUid ?? "").trim();
    if (createdByUid !== callerUid) {
      res.status(403).json({ok: false, error: "Forbidden"});
      return;
    }

    const status = resolveLinkStatus(data);
    const prefilledPath = String(data.prefilledStoragePath ?? "").trim();
    const signedStoragePath = status === "signed" ?
      await resolveSignedStoragePath(token, data) :
      null;

    if (status === "signed" && signedStoragePath) {
      const payload = await signedPdfDownloadPayload(signedStoragePath);
      res.status(200).json({
        ok: true,
        status,
        ...payload,
        prefilledPdfUrl: prefilledPath ?
          await signedReadUrl(prefilledPath) :
          null,
      });
      return;
    }

    res.status(200).json({
      ok: true,
      status,
      signedPdfUrl: null,
      signedPdfBase64: null,
      prefilledPdfUrl: prefilledPath ?
        await signedReadUrl(prefilledPath) :
        null,
    });
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error("[getDocumentSigningDownload] FAILED", e);
    res.status(500).json({ok: false, error: msg});
  }
});

/**
 * Deletes storage objects for a signing link when present.
 *
 * @param {string} token Link token.
 * @param {FirebaseFirestore.DocumentData | undefined} data Firestore data.
 */
async function deleteSigningLinkStorage(
  token: string,
  data: FirebaseFirestore.DocumentData | undefined
): Promise<void> {
  const bucket = admin.storage().bucket();
  const paths = new Set<string>([
    String(data?.prefilledStoragePath ?? "").trim(),
    String(data?.signedStoragePath ?? "").trim(),
    `${STORAGE_PREFIX}/${token}/prefilled.pdf`,
    `${STORAGE_PREFIX}/${token}/signed.pdf`,
  ].filter(Boolean));

  await Promise.all(
    [...paths].map(async (path) => {
      try {
        await bucket.file(path).delete({ignoreNotFound: true});
      } catch (e: unknown) {
        const msg = e instanceof Error ? e.message : String(e);
        console.warn("[deleteSigningLinkStorage] skip", path, msg);
      }
    })
  );
}

// ------------------------------------------------------------------
// POST /deleteDocumentSigningLink  { token }
// Auth: Bearer Firebase ID token (link creator)
// ------------------------------------------------------------------

export const deleteDocumentSigningLink = onRequest(async (req, res) => {
  try {
    if (req.method !== "POST") {
      res.status(405).json({ok: false, error: "Method not allowed"});
      return;
    }

    const authHeader = String(req.header("authorization") ?? "");
    if (!authHeader.startsWith("Bearer ")) {
      res.status(401).json({ok: false, error: "Unauthorized"});
      return;
    }

    const idToken = authHeader.slice("Bearer ".length).trim();
    if (!idToken) {
      res.status(401).json({ok: false, error: "Unauthorized"});
      return;
    }

    const decoded = await admin.auth().verifyIdToken(idToken);
    const callerUid = decoded.uid;

    const body = (req.body ?? {}) as {token?: string};
    const token = String(body.token ?? req.query.token ?? "").trim();
    if (!token) {
      res.status(400).json({ok: false, error: "token required"});
      return;
    }

    const tokenRef = admin.firestore().collection(COLLECTION).doc(token);
    const snap = await tokenRef.get();
    if (!snap.exists) {
      res.status(404).json({ok: false, error: "token not found"});
      return;
    }

    const data = snap.data() ?? {};
    const createdByUid = String(data.createdByUid ?? "").trim();
    if (createdByUid !== callerUid) {
      res.status(403).json({ok: false, error: "Forbidden"});
      return;
    }

    await deleteSigningLinkStorage(token, data);
    await tokenRef.delete();

    res.status(200).json({ok: true, token});
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error("[deleteDocumentSigningLink] FAILED", e);
    res.status(500).json({ok: false, error: msg});
  }
});

// ------------------------------------------------------------------
// POST /updateDocumentSigningSignedPdf
// Auth: Bearer Firebase ID token (link creator)
// ------------------------------------------------------------------

export const updateDocumentSigningSignedPdf = onRequest(async (req, res) => {
  try {
    if (req.method !== "POST") {
      res.status(405).json({ok: false, error: "Method not allowed"});
      return;
    }

    const authHeader = String(req.header("authorization") ?? "");
    if (!authHeader.startsWith("Bearer ")) {
      res.status(401).json({ok: false, error: "Unauthorized"});
      return;
    }

    const idToken = authHeader.slice("Bearer ".length).trim();
    if (!idToken) {
      res.status(401).json({ok: false, error: "Unauthorized"});
      return;
    }

    const decoded = await admin.auth().verifyIdToken(idToken);
    const callerUid = decoded.uid;

    const body = (req.body ?? {}) as Partial<UpdateSignedPdfBody>;
    const token = String(body.token ?? "").trim();
    const signedPdfBase64 = String(body.signedPdfBase64 ?? "").trim();

    if (!token) {
      res.status(400).json({ok: false, error: "token required"});
      return;
    }
    if (!signedPdfBase64) {
      res.status(400).json({ok: false, error: "signedPdfBase64 required"});
      return;
    }

    const pdfBytes = Buffer.from(signedPdfBase64, "base64");
    if (!pdfBytes.length) {
      res.status(400).json({ok: false, error: "invalid pdf"});
      return;
    }

    const tokenRef = admin.firestore().collection(COLLECTION).doc(token);
    const snap = await tokenRef.get();
    if (!snap.exists) {
      res.status(404).json({ok: false, error: "token not found"});
      return;
    }

    const data = snap.data() ?? {};
    const createdByUid = String(data.createdByUid ?? "").trim();
    if (createdByUid !== callerUid) {
      res.status(403).json({ok: false, error: "Forbidden"});
      return;
    }

    const status = resolveLinkStatus(data);
    if (status !== "signed") {
      res.status(409).json({ok: false, error: "document not signed yet"});
      return;
    }

    const signedStoragePath = `${STORAGE_PREFIX}/${token}/signed.pdf`;
    const bucket = admin.storage().bucket();
    await bucket.file(signedStoragePath).save(pdfBytes, {
      contentType: "application/pdf",
      resumable: false,
      metadata: {
        cacheControl: "private, max-age=0, no-transform",
      },
    });

    const updatePayload:
    FirebaseFirestore.UpdateData<FirebaseFirestore.DocumentData> = {
      signedStoragePath,
      labelPlacementsUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (body.labelPlacements && typeof body.labelPlacements === "object") {
      updatePayload.labelPlacements = body.labelPlacements;
    }

    await tokenRef.update(updatePayload);

    res.status(200).json({ok: true, token, signedStoragePath});
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error("[updateDocumentSigningSignedPdf] FAILED", e);
    res.status(500).json({ok: false, error: msg});
  }
});
