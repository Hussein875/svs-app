import * as admin from "firebase-admin";
import * as crypto from "crypto";
import {setGlobalOptions} from "firebase-functions/v2";
import {
  onCall,
  onRequest,
  HttpsError,
} from "firebase-functions/v2/https";

admin.initializeApp();

setGlobalOptions({region: "us-central1"});

type Role = "admin" | "employee" | "expert";

/**
 * Normalisiert eine E-Mail-Adresse.
 *
 * @param {string} email - Die zu normalisierende E-Mail-Adresse
 * @return {string} Die normalisierte E-Mail-Adresse
 */
function normalizeEmail(email: string): string {
  return String(email ?? "").trim().toLowerCase();
}

/**
 * Callable Function (Admin-only):
 * - Checks caller is authenticated and has roleRaw==admin in Firestore/<uid>
 * - Creates (or fetches) Firebase Auth user by email.
 * - Stores an invite document in Firestore invites/<email>.
 */
export const adminCreateUserInvite = onCall(async (request) => {
  // 1) Muss eingeloggt sein
  const callerUid = request.auth?.uid;
  if (!callerUid) {
    throw new HttpsError("unauthenticated", "Not signed in.");
  }

  // 2) Admin-Rechte prüfen (Firestore users/<callerUid>.roleRaw)
  const callerSnap = await admin
    .firestore()
    .collection("users")
    .doc(callerUid)
    .get();

  const callerRole = callerSnap.data()?.roleRaw as string | undefined;
  if (callerRole !== "admin") {
    throw new HttpsError("permission-denied", "Admin only.");
  }

  // 3) Payload validieren
  const data = request.data ?? {};
  const email = normalizeEmail(data.email);
  const name = String(data.name ?? "").trim();
  const roleRaw = String(data.roleRaw ?? "employee") as Role;
  const colorName = String(data.colorName ?? "blue");
  const annualLeaveDays = Number(data.annualLeaveDays ?? 30);

  if (!email || !email.includes("@")) {
    throw new HttpsError("invalid-argument", "Invalid email.");
  }
  if (!name) {
    throw new HttpsError("invalid-argument", "Name required.");
  }

  // 4) Auth-User anlegen (falls nicht existiert)
  let userRecord: admin.auth.UserRecord;

  try {
    userRecord = await admin.auth().getUserByEmail(email);
  } catch {
    const tempPassword = `${Math.random().toString(36).slice(2)}A!9`;
    userRecord = await admin.auth().createUser({
      email,
      password: tempPassword,
      displayName: name,
    });
  }

  // Optional: Custom Claims setzen (für spätere Role-Checks)
  await admin.auth().setCustomUserClaims(userRecord.uid, {role: roleRaw});

  // 5) Invite in Firestore speichern
  const invite = {
    name,
    roleRaw,
    colorName,
    annualLeaveDays,
    email,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    createdByUid: callerUid,
  };

  await admin
    .firestore()
    .collection("invites")
    .doc(email)
    .set(invite, {merge: true});

  return {
    ok: true,
    uid: userRecord.uid,
    email,
  };
});

// ------------------------------------------------------------------
// Make.com Webhook -> Firestore automation status
// POST /automationStatusWebhook
// Optional Header:
//   x-svs-secret: <YOUR_SECRET>  (empfohlen)
// Body:
//   {
//     "automationId": "auto_gutachten_ablage",
//     "status": "ok" | "warn" | "error",
//     "lastMessage": "...",
//     "lastRunAt": "2026-01-07T11:45:00Z",  // optional ISO
//     "nextRunAt": "2026-01-07T12:15:00Z"  // optional ISO
//   }
// ------------------------------------------------------------------

type AutomationStatus = "ok" | "warn" | "error";

interface AutomationWebhookBody {
  automationId: string;
  status: AutomationStatus;
  lastMessage?: string;
  lastRunAt?: string;
  nextRunAt?: string;
}

/**
 * Parses an ISO date string into a Date.
 *
 * @param {unknown} v ISO date string or unknown input.
 * @return {Date|null} Parsed date or null if invalid.
 */
function parseISODateOrNull(v: unknown): Date | null {
  if (!v) return null;
  const s = String(v);
  const d = new Date(s);
  return Number.isNaN(d.getTime()) ? null : d;
}

/**
 * Make.com webhook endpoint that stores the current automation status in
 * `automations/<automationId>` and appends a run event to
 * `automations/<automationId>/events`.
 */
export const automationStatusWebhook = onRequest(async (req, res) => {
  try {
    if (req.method !== "POST") {
      res.status(405).json({ok: false, error: "Method not allowed"});
      return;
    }

    // Optional: shared-secret protection
    const expected = process.env.MAKE_WEBHOOK_SECRET;
    if (expected) {
      const got = String(req.header("x-svs-secret") ?? "");
      if (!got || got !== expected) {
        res.status(401).json({ok: false, error: "Unauthorized"});
        return;
      }
    }

    const body = (req.body ?? {}) as Partial<AutomationWebhookBody>;
    const automationId = String(body.automationId ?? "").trim();
    const status = String(body.status ?? "").trim() as AutomationStatus;
    const lastMessage = String(body.lastMessage ?? "").trim();

    if (!automationId) {
      res.status(400).json({ok: false, error: "automationId required"});
      return;
    }

    const allowedStatuses: AutomationStatus[] = ["ok", "warn", "error"];
    if (!allowedStatuses.includes(status)) {
      res.status(400).json({ok: false, error: "status must be ok|warn|error"});
      return;
    }

    const lastRunAtDate = parseISODateOrNull(body.lastRunAt);
    const nextRunAtDate = parseISODateOrNull(body.nextRunAt);

    const doc: Record<string, unknown> = {
      provider: "make",
      status,
      lastMessage,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (lastRunAtDate) {
      doc.lastRunAt = admin.firestore.Timestamp.fromDate(lastRunAtDate);
    }
    if (nextRunAtDate) {
      doc.nextRunAt = admin.firestore.Timestamp.fromDate(nextRunAtDate);
    }

    await admin
      .firestore()
      .collection("automations")
      .doc(automationId)
      .set(doc, {merge: true});

    // Append event log (last runs)
    const runAt = lastRunAtDate ?? new Date();
    await admin
      .firestore()
      .collection("automations")
      .doc(automationId)
      .collection("events")
      .add({
        status,
        message: lastMessage,
        runAt: admin.firestore.Timestamp.fromDate(runAt),
        nextRunAt: nextRunAtDate ?
          admin.firestore.Timestamp.fromDate(nextRunAtDate) :
          null,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

    res.status(200).json({ok: true});
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error("[automationStatusWebhook] FAILED", e);
    res.status(500).json({ok: false, error: msg});
  }
});

// ------------------------------------------------------------------
// Provision: Token prüfen (für Firebase Hosting Webformular)
// GET /getProvisionLink?token=<uuid>
// Returns: { ok, status: valid|expired|used|not_found, expiresAt?, usedAt? }
// ------------------------------------------------------------------

export const getProvisionLink = onRequest(async (req, res) => {
  try {
    // --- CORS
    res.set("Access-Control-Allow-Origin", "https://sv-souleiman.de");
    res.set("Vary", "Origin");
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
      .collection("provisionLinks")
      .doc(token)
      .get();

    if (!snap.exists) {
      res.status(200).json({ok: true, status: "not_found"});
      return;
    }

    const data = snap.data() ?? {};
    const status = String(data.status ?? "unused");

    const expiresAtTs =
      data.expiresAt as admin.firestore.Timestamp | undefined;
    const usedAtTs =
      data.usedAt as admin.firestore.Timestamp | null | undefined;

    const nowMs = Date.now();
    const expiresAtMs = expiresAtTs ? expiresAtTs.toDate().getTime() : 0;

    if (expiresAtTs && expiresAtMs < nowMs) {
      res.status(200).json({
        ok: true,
        status: "expired",
        expiresAt: expiresAtTs.toDate().toISOString(),
      });
      return;
    }

    if (status === "used" || usedAtTs) {
      res.status(200).json({
        ok: true,
        status: "used",
        expiresAt: expiresAtTs ? expiresAtTs.toDate().toISOString() : null,
        usedAt: usedAtTs ? usedAtTs.toDate().toISOString() : null,
      });
      return;
    }

    res.status(200).json({
      ok: true,
      status: "valid",
      expiresAt: expiresAtTs ? expiresAtTs.toDate().toISOString() : null,
    });
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error("[getProvisionLink] FAILED", e);
    res.status(500).json({ok: false, error: msg});
  }
});

// ------------------------------------------------------------------
// Provision: Formular absenden (Token wird EINMALIG verbraucht)
// POST /submitProvisionForm
// Returns: { ok: true, commissionId }
// ------------------------------------------------------------------

type PayoutMethod = "iban" | "paypal";

type SubmitProvisionBody = {
  token: string;

  // Empfehlender (Privatperson)
  recommenderName: string;
  recommenderStreet?: string;
  recommenderZip?: string;
  recommenderCity?: string;
  recommenderEmail?: string;
  recommenderPhone?: string;

  // Auszahlung
  payoutMethod: PayoutMethod;
  payoutIban?: string;
  payoutPaypal?: string;

  // Vermittlung / Fall
  customerName: string;
  customerPhone?: string;
  customerEmail?: string;
  caseNumber?: string;
  licensePlate?: string;

  // Provision
  amount?: number;
  notes?: string;

  // Unterschrift (PNG ohne Data-URL Prefix)
  signaturePngBase64: string;

  // Bestätigung / Metadaten
  acceptedAtClientIso?: string;
};

/**
 * Extracts the best-effort client IP from request headers / socket.
 *
 * @param {unknown} req The incoming HTTP request object.
 * @return {string|null} The IP string if available, otherwise null.
 */
function getHeaderIp(req: unknown): string | null {
  const r = req as {
    headers?: Record<string, unknown>;
    socket?: {remoteAddress?: unknown};
  };

  const fwd = r.headers?.["x-forwarded-for"];
  const fwdStr = typeof fwd === "string" ? fwd : undefined;

  const raw = String(fwdStr ?? r.socket?.remoteAddress ?? "").trim();
  return raw || null;
}

export const submitProvisionForm = onRequest(async (req, res) => {
  try {
    // --- CORS
    res.set("Access-Control-Allow-Origin", "https://sv-souleiman.de");
    res.set("Vary", "Origin");
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

    const body = (req.body ?? {}) as Partial<SubmitProvisionBody>;
    const bodyAny = body as unknown as Record<string, unknown>;

    const token = String(body.token ?? "").trim();
    const customerName = String(body.customerName ?? "").trim();

    const recommenderName =
      String(bodyAny.recommenderName ?? "").trim();
    const payoutMethodRaw =
      String(bodyAny.payoutMethod ?? "").trim();
    const signatureB64 =
      String(bodyAny.signaturePngBase64 ?? "").trim();

    if (!token) {
      res.status(400).json({ok: false, error: "token required"});
      return;
    }

    if (!customerName) {
      res.status(400).json({ok: false, error: "customerName required"});
      return;
    }

    if (!recommenderName) {
      res.status(400).json({ok: false, error: "recommenderName required"});
      return;
    }

    if (payoutMethodRaw !== "iban" && payoutMethodRaw !== "paypal") {
      res.status(400).json({
        ok: false,
        error: "payoutMethod must be iban|paypal",
      });
      return;
    }

    if (!signatureB64) {
      res.status(400).json({ok: false, error: "signature required"});
      return;
    }

    if (payoutMethodRaw === "iban") {
      const payoutIban = String(bodyAny.payoutIban ?? "").trim();
      if (!payoutIban) {
        res.status(400).json({ok: false, error: "payoutIban required"});
        return;
      }
    }

    if (payoutMethodRaw === "paypal") {
      const payoutPaypal = String(bodyAny.payoutPaypal ?? "").trim();
      if (!payoutPaypal) {
        res.status(400).json({
          ok: false,
          error: "payoutPaypal required",
        });
        return;
      }
    }

    const db = admin.firestore();
    const tokenRef = db.collection("provisionLinks").doc(token);
    const commissionsRef = db.collection("commissions");

    const result = await db.runTransaction(async (tx) => {
      const tokenSnap = await tx.get(tokenRef);
      if (!tokenSnap.exists) {
        return {ok: false as const, code: 404, error: "token not found"};
      }

      const tokenData = tokenSnap.data() ?? {};
      const status = String(tokenData.status ?? "unused");

      const expiresAtTs =
        tokenData.expiresAt as admin.firestore.Timestamp | undefined;
      const usedAtTs =
        tokenData.usedAt as admin.firestore.Timestamp | null | undefined;

      const nowMs = Date.now();
      const expiresMs = expiresAtTs ? expiresAtTs.toDate().getTime() : 0;

      if (expiresAtTs && expiresMs < nowMs) {
        return {ok: false as const, code: 410, error: "token expired"};
      }

      if (status === "used" || usedAtTs) {
        return {
          ok: false as const,
          code: 409,
          error: "token already used",
        };
      }

      const commissionId = crypto.randomUUID();

      const tokenAmountRaw = tokenData.amount as unknown;
      const tokenAmount =
        typeof tokenAmountRaw === "number" && Number.isFinite(tokenAmountRaw) ?
          tokenAmountRaw :
          null;

      const bodyAmountRaw = body.amount;
      const bodyAmount =
        typeof bodyAmountRaw === "number" && Number.isFinite(bodyAmountRaw) ?
          bodyAmountRaw :
          null;

      // Prefer amount set when link was created (server-trust).
      const amount = tokenAmount ?? bodyAmount;

      const createdByUid =
        String((tokenData as Record<string, unknown>).createdByUid ?? "")
          .trim() ||
        null;

      const payoutMethod = payoutMethodRaw as PayoutMethod;

      const commissionDoc: Record<string, unknown> = {
        token,

        // Empfehlender
        recommenderName,
        recommenderStreet:
          String(bodyAny.recommenderStreet ?? "").trim() || null,
        recommenderZip: String(bodyAny.recommenderZip ?? "").trim() || null,
        recommenderCity:
          String(bodyAny.recommenderCity ?? "").trim() || null,
        recommenderEmail:
          String(bodyAny.recommenderEmail ?? "").trim() || null,
        recommenderPhone:
          String(bodyAny.recommenderPhone ?? "").trim() || null,

        // Auszahlung
        payoutMethod,
        payoutIban:
          payoutMethod === "iban" ?
            String(bodyAny.payoutIban ?? "").trim() || null :
            null,
        payoutPaypal:
          payoutMethod === "paypal" ?
            String(bodyAny.payoutPaypal ?? "").trim() || null :
            null,

        // Fall
        customerName,
        customerPhone: String(body.customerPhone ?? "").trim() || null,
        customerEmail: String(body.customerEmail ?? "").trim() || null,
        caseNumber: String(body.caseNumber ?? "").trim() || null,
        licensePlate: String(body.licensePlate ?? "").trim() || null,

        // Provision
        amount,
        notes: String(body.notes ?? "").trim() || null,

        // Unterschrift
        signaturePngBase64: signatureB64,

        // Metadaten
        createdByUid,
        acceptedAtClientIso:
          String(bodyAny.acceptedAtClientIso ?? "").trim() || null,
        acceptedAtServer: admin.firestore.FieldValue.serverTimestamp(),
        userAgent: String(req.get("user-agent") ?? "").trim() || null,
        ip: getHeaderIp(req),

        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        status: "submitted",
      };

      tx.set(commissionsRef.doc(commissionId), commissionDoc);

      tx.update(tokenRef, {
        status: "used",
        usedAt: admin.firestore.FieldValue.serverTimestamp(),
        usedBy: "web",
      });

      return {ok: true as const, commissionId};
    });

    if (!result.ok) {
      res.status(result.code).json({ok: false, error: result.error});
      return;
    }

    res.status(200).json({ok: true, commissionId: result.commissionId});
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error("[submitProvisionForm] FAILED", e);
    res.status(500).json({ok: false, error: msg});
  }
});

// ------------------------------------------------------------------
// Provision: Einmal-Link erzeugen (Admin-only)
// POST /createProvisionLink
// Authorization: Bearer <Firebase ID Token>
// Body: { "ttlDays": 30 }
// Returns: { ok: true, token, url, expiresAt }
// ------------------------------------------------------------------

interface CreateProvisionLinkBody {
  ttlDays?: number;
  amount?: number;
}

/**
 * Creates a one-time provision form link for administrators.
 *
 * This endpoint validates the caller via Firebase ID token, checks
 * for admin privileges, generates a UUID token with a configurable TTL,
 * stores it in Firestore, and returns the full provision form URL.
 *
 * Method: POST
 * Auth: Bearer <Firebase ID Token>
 * Body: { ttlDays?: number }
 */
export const createProvisionLink = onRequest(async (req, res) => {
  try {
    if (req.method !== "POST") {
      res.status(405).json({ok: false, error: "Method not allowed"});
      return;
    }

    // --- Auth: Firebase ID Token (Bearer)
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

    // --- Admin-Check via Firestore users/<uid>.roleRaw
    const callerSnap = await admin
      .firestore()
      .collection("users")
      .doc(callerUid)
      .get();

    const callerRole = callerSnap.data()?.roleRaw as string | undefined;
    if (callerRole !== "admin") {
      res.status(403).json({ok: false, error: "Admin only"});
      return;
    }

    // --- TTL
    const body = (req.body ?? {}) as Partial<CreateProvisionLinkBody>;
    const ttlDaysRaw = Number(body.ttlDays ?? 30);
    const ttlDays =
      Number.isFinite(ttlDaysRaw) ?
        Math.max(1, Math.min(365, ttlDaysRaw)) :
        30;

    const expiresAtDate = new Date(
      Date.now() + ttlDays * 24 * 60 * 60 * 1000
    );

    const expiresAt = admin.firestore.Timestamp.fromDate(expiresAtDate);

    // --- Amount (optional, EUR)
    const amountRaw = body.amount;
    const amount =
      typeof amountRaw === "number" && Number.isFinite(amountRaw) ?
        Math.max(0, amountRaw) :
        null;

    // --- Token (Einmal-Link)
    const token = crypto.randomUUID();

    await admin
      .firestore()
      .collection("provisionLinks")
      .doc(token)
      .set({
        token,
        status: "unused",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        expiresAt,
        usedAt: null,
        createdByUid: callerUid,
        amount,
      });

    const url = `https://sv-souleiman.de/provision?token=${token}`;

    res.status(200).json({
      ok: true,
      token,
      url,
      expiresAt: expiresAtDate.toISOString(),
    });
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error("[createProvisionLink] FAILED", e);
    res.status(500).json({ok: false, error: msg});
  }
});
