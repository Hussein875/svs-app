import * as admin from "firebase-admin";
import {onCall, onRequest, HttpsError} from "firebase-functions/v2/https";

admin.initializeApp();

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

    if (!( ["ok", "warn", "error"] as string[] ).includes(status)) {
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
