import * as admin from "firebase-admin";
import * as crypto from "crypto";
import {setGlobalOptions} from "firebase-functions/v2";
import {defineSecret} from "firebase-functions/params";
import {
  onCall,
  onRequest,
  HttpsError,
} from "firebase-functions/v2/https";
import {
  onDocumentCreated,
  onDocumentUpdated,
} from "firebase-functions/v2/firestore";
import nodemailer from "nodemailer";
import PDFDocument from "pdfkit";
import {google} from "googleapis";
import {Readable} from "stream";

admin.initializeApp();

setGlobalOptions({region: "us-central1"});

// Gen2 Secrets (Firebase Functions)
const SMTP_HOST_SECRET = defineSecret("SMTP_HOST");
const SMTP_USER_SECRET = defineSecret("SMTP_USER");
const SMTP_PASS_SECRET = defineSecret("SMTP_PASS");

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
// Push Notifications (FCM)
// - Neuer Antrag: leaveRequests/{requestId} onCreate -> Push an alle Admins
// - Antrag genehmigt: leaveRequests/{requestId}
// onUpdate statusRaw -> Push an Antragsteller
// ------------------------------------------------------------------

/**
 * Represents an FCM token with its owning Firestore device document reference.
 */
type TokenRef = {
  token: string;
  ref: admin.firestore.DocumentReference;
  ownerUserId: string;
};

/**
 * Returns true if an FCM error indicates that a token is invalid/unregistered.
 *
 * @param {unknown} err The error object from FCM response.
 * @return {boolean} True if the token should be removed.
 */
function isTokenGone(err: unknown): boolean {
  const anyErr = err as {code?: unknown};
  const code = String(anyErr?.code ?? "");
  return code === "messaging/registration-token-not-registered" ||
    code === "messaging/invalid-registration-token";
}

/**
 * Removes invalid or unregistered FCM tokens from Firestore.
 *
 * Iterates over multicast send responses and deletes device documents
 * whose tokens are reported by FCM as invalid or unregistered. This keeps
 * the users/<uid>/devices subcollection clean and up to date.
 *
 * @param {TokenRef[]} tokenRefs - Token refs aligned with multicast order.
 * @param {Array<Object>} responses - Multicast send responses from FCM.
 * @return {Promise<void>} Resolves when invalid tokens are removed.
 */
async function cleanupDeadTokens(
  tokenRefs: TokenRef[],
  responses: Array<{success: boolean; error?: unknown}>
): Promise<void> {
  const toDelete: admin.firestore.DocumentReference[] = [];

  responses.forEach((r, i) => {
    if (!r.success && isTokenGone(r.error)) {
      const tr = tokenRefs[i];
      if (tr?.ref) toDelete.push(tr.ref);
    }
  });

  if (toDelete.length === 0) return;

  await Promise.all(
    toDelete.map(async (ref) => {
      try {
        await ref.delete();
      } catch (e) {
        console.warn("[push][cleanup] delete failed", ref.path, e);
      }
    })
  );
}

/**
 * Logs per-token errors from an FCM multicast send response.
 *
 * @param {string} tag - Short tag like "new" or "approved".
 * @param {string[]} tokens - Tokens used for the multicast send.
 * @param {Array<Object>} responses - Multicast send responses from FCM.
 * @return {void} Nothing.
 */
function logMulticastFailures(
  tag: string,
  tokens: string[],
  responses: Array<{success: boolean; error?: unknown}>
): void {
  responses.forEach((r, i) => {
    if (r.success) return;

    const tok = String(tokens[i] ?? "");
    const tokShort =
      tok.length > 12 ? `${tok.slice(0, 6)}…${tok.slice(-6)}` : tok;

    const anyErr = r.error as {code?: unknown; message?: unknown} | undefined;
    const code = String(anyErr?.code ?? "unknown");
    const msg = String(anyErr?.message ?? "no message");

    console.warn("[push][" + tag + "] token failed", tokShort, code, msg);
  });
}

/**
 * Fetches all FCM token refs for users with roleRaw == "admin".
 *
 * @return {Promise<TokenRef[]>} A deduplicated list of admin device tokens.
 */
async function getAdminTokenRefs(): Promise<TokenRef[]> {
  const adminsSnap = await admin.firestore()
    .collection("users")
    .where("roleRaw", "==", "admin")
    .get();

  const out: TokenRef[] = [];
  const seen = new Set<string>();

  for (const u of adminsSnap.docs) {
    const devicesSnap = await admin.firestore()
      .collection("users")
      .doc(u.id)
      .collection("devices")
      .get();

    for (const d of devicesSnap.docs) {
      const t = d.data()?.fcmToken;
      const token = typeof t === "string" ? t.trim() : "";
      if (!token) continue;
      if (seen.has(token)) continue;
      seen.add(token);
      out.push({token, ref: d.ref, ownerUserId: u.id});
    }
  }

  return out;
}

/**
 * Fetches all FCM token refs for a given user.
 *
 * @param {string} userId - Firebase Auth UID of the target user.
 * @return {Promise<TokenRef[]>} Deduplicated list of user device tokens.
 */
async function getUserTokenRefs(userId: string): Promise<TokenRef[]> {
  const devicesSnap = await admin
    .firestore()
    .collection("users")
    .doc(userId)
    .collection("devices")
    .get();

  const out: TokenRef[] = [];
  const seen = new Set<string>();

  for (const d of devicesSnap.docs) {
    const t = d.data()?.fcmToken;
    const token = typeof t === "string" ? t.trim() : "";
    if (!token) continue;
    if (seen.has(token)) continue;
    seen.add(token);
    out.push({token, ref: d.ref, ownerUserId: userId});
  }

  return out;
}

/**
 * Best-effort lookup of a user's name for push messages.
 *
 * @param {string} userId - Firebase Auth UID of the target user.
 */
async function getUserNameOrFallback(userId: string): Promise<string> {
  if (!userId) return "Jemand";
  try {
    const snap = await admin.firestore()
      .collection("users")
      .doc(userId)
      .get();
    const name = String(snap.data()?.name ?? "").trim();
    return name || "Jemand";
  } catch {
    return "Jemand";
  }
}

/**
 * Filters out all token refs that belong to a specific user.
 * Useful to prevent self-notifications (e.g. creator is also an admin).
 *
 * @param {TokenRef[]} tokenRefs Token refs to filter.
 * @param {string} userId Firebase Auth UID whose tokens should be excluded.
 * @return {TokenRef[]} Token refs excluding those owned by the given user.
 */
function filterOutUserTokenRefs(
  tokenRefs: TokenRef[],
  userId: string
): TokenRef[] {
  const uid = String(userId ?? "").trim();
  if (!uid) return tokenRefs;
  return tokenRefs.filter((tr) => tr.ownerUserId !== uid);
}

// Neuer Antrag -> Admins
export const pushOnNewLeaveRequest =
  onDocumentCreated(
    "leaveRequests/{requestId}",
    async (event) => {
      const snap = event.data;
      if (!snap) return;

      const data = (snap.data() ?? {}) as Record<string, unknown>;

      const typeRaw = String(data.typeRaw ?? "").trim() || "Antrag";

      // Prevent self-notifications: if the creator is also an admin,
      // do not send the "new request" push to their own devices.
      const creatorUserId = String(
        data.createdByUid ??
        data.createdByUserId ??
        data.creatorUserId ??
        data.userId ??
        ""
      ).trim();

      console.log(
        "[push][new] requestId=",
        String(event.params.requestId ?? "")
      );

      const allAdminTokenRefs = await getAdminTokenRefs();
      const tokenRefs = filterOutUserTokenRefs(
        allAdminTokenRefs,
        creatorUserId
      );
      const tokens = tokenRefs.map((t) => t.token);
      if (tokens.length === 0) {
        console.log("[push][new] no admin tokens");
        return;
      }

      const resp = await admin.messaging().sendEachForMulticast({
        tokens,
        notification: {
          title: "Neuer Antrag",
          body: `${typeRaw}`,
        },
        data: {
          type: "leave_request_new",
          requestId: String(event.params.requestId ?? ""),
        },
      });

      console.log(
        "[push][new] sent",
        resp.successCount,
        "ok,",
        resp.failureCount,
        "failed"
      );

      logMulticastFailures(
        "new",
        tokens,
        resp.responses as Array<{success: boolean; error?: unknown}>
      );
      await cleanupDeadTokens(
        tokenRefs,
        resp.responses as Array<{success: boolean; error?: unknown}>
      );
    }
  );

// Antrag genehmigt oder abgelehnt -> Antragsteller
export const pushOnLeaveRequestApproved = onDocumentUpdated(
  "leaveRequests/{requestId}",
  async (event) => {
    const before = event.data?.before;
    const after = event.data?.after;
    if (!before || !after) return;

    const beforeData = (before.data() ?? {}) as Record<string, unknown>;
    const afterData = (after.data() ?? {}) as Record<string, unknown>;

    const beforeStatus = String(beforeData.statusRaw ?? "").trim();
    const afterStatus = String(afterData.statusRaw ?? "").trim();

    // Nur wenn sich statusRaw ändert
    if (beforeStatus === afterStatus) return;

    const isApproved = afterStatus === "Genehmigt";
    const isRejected = afterStatus === "Abgelehnt";
    if (!isApproved && !isRejected) return;

    const userId = String(afterData.userId ?? "").trim();
    if (!userId) return;

    console.log(
      "[push][decision] requestId=",
      String(event.params.requestId ?? ""),
      "before=",
      beforeStatus,
      "after=",
      afterStatus
    );

    const tokenRefs = await getUserTokenRefs(userId);
    const tokens = tokenRefs.map((t) => t.token);
    if (tokens.length === 0) {
      console.log("[push][decision] no user tokens for", userId);
      return;
    }

    const resp = await admin.messaging().sendEachForMulticast({
      tokens,
      notification: {
        title: isApproved ? "Antrag genehmigt" : "Antrag abgelehnt",
        body: isApproved ? "Dein Antrag wurde genehmigt." :
          "Dein Antrag wurde abgelehnt.",
      },
      data: {
        type: isApproved ? "leave_request_approved" : "leave_request_rejected",
        requestId: String(event.params.requestId ?? ""),
        decision: isApproved ? "approved" : "rejected",
      },
    });

    const tag = isApproved ? "approved" : "rejected";

    console.log(
      "[push][decision] sent",
      tag,
      resp.successCount,
      "ok,",
      resp.failureCount,
      "failed"
    );

    logMulticastFailures(
      tag,
      tokens,
      resp.responses as Array<{success: boolean; error?: unknown}>
    );
    await cleanupDeadTokens(
      tokenRefs,
      resp.responses as Array<{success: boolean; error?: unknown}>
    );
  }
);

// ------------------------------------------------------------------
// Tasks -> Push an zuständigen Nutzer
// - Neue Aufgabe: tasks/{taskId} onCreate
// - Neu zugeteilt: tasks/{taskId} onUpdate (assignedUserId changed)
// ------------------------------------------------------------------

export const pushOnTaskAssigned = onDocumentCreated(
  "tasks/{taskId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const data = (snap.data() ?? {}) as Record<string, unknown>;

    const assignedUserId = String(data.assignedUserId ?? "").trim();
    const creatorUserId = String(data.creatorUserId ?? "").trim();
    const titleRaw = String(data.title ?? "").trim();
    const title = titleRaw || "Neue Aufgabe";

    if (!assignedUserId) return;
    if (assignedUserId === creatorUserId) return;

    console.log(
      "[push][task_assigned] taskId=",
      String(event.params.taskId ?? ""),
      "to=",
      assignedUserId,
      "from=",
      creatorUserId
    );

    const fromName = await getUserNameOrFallback(creatorUserId);

    const tokenRefs = await getUserTokenRefs(assignedUserId);
    const tokens = tokenRefs.map((t) => t.token);
    if (tokens.length === 0) {
      console.log("[push][task_assigned] no user tokens for", assignedUserId);
      return;
    }

    const resp = await admin.messaging().sendEachForMulticast({
      tokens,
      notification: {
        title: "Neue Aufgabe",
        body: fromName + " hat dir eine Aufgabe zugeteilt: " + title,
      },
      data: {
        type: "task_assigned",
        taskId: String(event.params.taskId ?? ""),
        toUserId: assignedUserId,
        fromUserId: creatorUserId,
      },
    });

    console.log(
      "[push][task_assigned] sent",
      resp.successCount,
      "ok,",
      resp.failureCount,
      "failed"
    );

    logMulticastFailures(
      "task_assigned",
      tokens,
      resp.responses as Array<{success: boolean; error?: unknown}>
    );
    await cleanupDeadTokens(
      tokenRefs,
      resp.responses as Array<{success: boolean; error?: unknown}>
    );
  }
);

export const pushOnTaskReassigned = onDocumentUpdated(
  "tasks/{taskId}",
  async (event) => {
    const before = event.data?.before;
    const after = event.data?.after;
    if (!before || !after) return;

    const beforeData = (before.data() ?? {}) as Record<string, unknown>;
    const afterData = (after.data() ?? {}) as Record<string, unknown>;

    const beforeAssignee = String(beforeData.assignedUserId ?? "").trim();
    const afterAssignee = String(afterData.assignedUserId ?? "").trim();

    if (beforeAssignee === afterAssignee) return;
    if (!afterAssignee) return;

    const creatorUserId = String(afterData.creatorUserId ?? "").trim();
    if (afterAssignee === creatorUserId) return;

    const titleRaw = String(afterData.title ?? "").trim();
    const title = titleRaw || "Neue Aufgabe";

    console.log(
      "[push][task_reassigned] taskId=",
      String(event.params.taskId ?? ""),
      "to=",
      afterAssignee,
      "from=",
      creatorUserId
    );

    const fromName = await getUserNameOrFallback(creatorUserId);

    const tokenRefs = await getUserTokenRefs(afterAssignee);
    const tokens = tokenRefs.map((t) => t.token);
    if (tokens.length === 0) {
      console.log("[push][task_reassigned] no user tokens for", afterAssignee);
      return;
    }

    const resp = await admin.messaging().sendEachForMulticast({
      tokens,
      notification: {
        title: "Aufgabe zugeteilt",
        body: fromName + " hat dir eine Aufgabe zugeteilt: " + title,
      },
      data: {
        type: "task_assigned",
        taskId: String(event.params.taskId ?? ""),
        toUserId: afterAssignee,
        fromUserId: creatorUserId,
        reassigned: "1",
      },
    });

    console.log(
      "[push][task_reassigned] sent",
      resp.successCount,
      "ok,",
      resp.failureCount,
      "failed"
    );

    logMulticastFailures(
      "task_reassigned",
      tokens,
      resp.responses as Array<{success: boolean; error?: unknown}>
    );
    await cleanupDeadTokens(
      tokenRefs,
      resp.responses as Array<{success: boolean; error?: unknown}>
    );
  }
);

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
// Scanner -> Upload Scan (PDF) to Google Drive
// POST /uploadScanToDrive
// Auth: Bearer <Firebase ID Token>
// Body: { storagePath: string, fileName: string }
// Returns: { ok: true, driveFileId }
// ------------------------------------------------------------------

type UploadScanToDriveBody = {
  storagePath: string;
  fileName: string;
};

const SCANS_DRIVE_FOLDER_ID = "19n1REUlYfwdzrj3NntMqgzoQ05jg2T9f";

export const uploadScanToDrive = onRequest(
  {
    region: "us-central1",
    serviceAccount: "svs-app-864ed@appspot.gserviceaccount.com",
  },
  async (req, res) => {
    try {
      // CORS (mobile app typically doesn't need it, but harmless)
      res.set("Access-Control-Allow-Origin", "*");
      res.set("Access-Control-Allow-Methods", "POST,OPTIONS");
      res.set(
        "Access-Control-Allow-Headers",
        "Content-Type, Authorization"
      );

      if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
      }

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

      let callerUid = "";
      try {
        const decoded = await admin.auth().verifyIdToken(idToken);
        callerUid = decoded.uid;
      } catch {
        res.status(401).json({ok: false, error: "Unauthorized"});
        return;
      }

      const body = (req.body ?? {}) as Partial<UploadScanToDriveBody>;
      const storagePath = String(body.storagePath ?? "").trim();
      const fileName = String(body.fileName ?? "").trim();

      if (!storagePath) {
        res.status(400).json({ok: false, error: "storagePath required"});
        return;
      }
      if (!fileName) {
        res.status(400).json({ok: false, error: "fileName required"});
        return;
      }

      // Basic safety: only allow uploads from the caller's own scans path.
      // Expected: scans/<uid>/...
      if (!storagePath.startsWith(`scans/${callerUid}/`)) {
        res.status(403).json({ok: false, error: "Forbidden"});
        return;
      }

      // --- Download from Firebase Storage
      const bucket = admin.storage().bucket();
      const file = bucket.file(storagePath);

      const [exists] = await file.exists();
      if (!exists) {
        res.status(404).json({ok: false, error: "file not found"});
        return;
      }

      const [buf] = await file.download();

      // --- Upload to Google Drive
      // Uses Application Default Credentials
      // (the Cloud Functions service account).
      // Make sure Drive API is enabled and the target
      // folder is shared with the SA (drive.file scope is too limited here).
      const auth = new google.auth.GoogleAuth({
        scopes: ["https://www.googleapis.com/auth/drive"],
      });

      // Log which identity (service account) is being used.
      try {
        const creds = await auth.getCredentials();
        const clientEmail =
          (creds as {client_email?: unknown}).client_email ?? "";
        const email = String(clientEmail);
        if (email) {
          console.log("[uploadScanToDrive] ADC identity:", email);
        }
      } catch (e) {
        console.warn(
          "[uploadScanToDrive] Could not read ADC credentials",
          e
        );
      }

      const drive = google.drive({version: "v3", auth});

      // Preflight: ensure the target folder is accessible
      // to this service account.
      try {
        await drive.files.get({
          fileId: SCANS_DRIVE_FOLDER_ID,
          fields: "id,name",
          supportsAllDrives: true,
        });
      } catch (e: unknown) {
        const msg =
          "Drive-Ordner nicht gefunden/kein Zugriff. " +
          "Bitte den Ordner mit dem in den Logs angezeigten Service Account " +
          "als Bearbeiter teilen. FolderId=" +
          SCANS_DRIVE_FOLDER_ID;
        console.error("[uploadScanToDrive] folder access FAILED", e);
        res.status(403).json({ok: false, error: msg});
        return;
      }

      const media = {
        mimeType: "application/pdf",
        body: Readable.from(buf),
      };

      const createResp = await drive.files.create({
        supportsAllDrives: true,
        requestBody: {
          name: fileName,
          parents: [SCANS_DRIVE_FOLDER_ID],
        },
        media,
        fields: "id",
      });

      const driveFileId = String(createResp.data.id ?? "").trim();
      if (!driveFileId) {
        res.status(500).json({ok: false, error: "Drive upload failed"});
        return;
      }

      res.status(200).json({ok: true, driveFileId});
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : String(e);
      console.error("[uploadScanToDrive] FAILED", e);
      res.status(500).json({ok: false, error: msg});
    }
  }
);

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

// ------------------------------------------------------------------
// Provision: PDF + Storage + E-Mail (automatisch nach Übermittlung)
// Trigger: commissions/{commissionId} onCreate
// - PDF inkl. Unterschrift (signaturePngBase64)
// - Upload nach Firebase Storage: provision_pdfs/<commissionId>.pdf
// - E-Mail an info@sv-souleiman.de (SMTP via ENV)
// ------------------------------------------------------------------

type ProvisionMailConfig = {
  host: string;
  port: number;
  user: string;
  pass: string;
  from: string;
  to: string;
  secure: boolean;
};

/**
 * Reads SMTP configuration for provision notifications.
 *
 * Host/user/pass are read from Gen2 Secrets first, then fall back to env.
 *
 * @return {ProvisionMailConfig} SMTP config.
 */
function getProvisionMailConfig(): ProvisionMailConfig {
  const host = String(
    SMTP_HOST_SECRET.value() || process.env.SMTP_HOST || ""
  ).trim();

  const portRaw = Number(process.env.SMTP_PORT ?? "587");
  const port = Number.isFinite(portRaw) ? portRaw : 587;

  const user = String(
    SMTP_USER_SECRET.value() || process.env.SMTP_USER || ""
  ).trim();

  const pass = String(
    SMTP_PASS_SECRET.value() || process.env.SMTP_PASS || ""
  ).trim();

  const from = String(
    process.env.SMTP_FROM ?? "info@sv-souleiman.de"
  ).trim();

  const to = String(
    process.env.PROVISION_NOTIFY_TO ?? "info@sv-souleiman.de"
  ).trim();

  const secure = String(process.env.SMTP_SECURE ?? "").trim() === "true";

  if (!host || !user || !pass) {
    throw new Error(
      "SMTP config missing. Set secrets SMTP_HOST, SMTP_USER, SMTP_PASS."
    );
  }

  return {host, port, user, pass, from, to, secure};
}

/**
 * Returns a safe printable string for PDF/mail output.
 *
 * @param {unknown} v Any value.
 * @return {string} Trimmed string or em dash.
 */
function safeStr(v: unknown): string {
  return String(v ?? "").trim() || "—";
}

/**
 * Formats a number as EUR for German locale.
 *
 * @param {unknown} v Any value.
 * @return {string} Formatted amount or em dash.
 */
function formatEurAmount(v: unknown): string {
  const n = typeof v === "number" ? v : Number(v);
  if (!Number.isFinite(n)) return "—";
  return new Intl.NumberFormat("de-DE", {
    style: "currency",
    currency: "EUR",
    maximumFractionDigits: 2,
  }).format(n);
}

/**
 * Builds the provision confirmation PDF including the signature.
 *
 * @param {object} args Function arguments.
 * @param {string} args.commissionId Firestore document id.
 * @param {Object<string, unknown>} args.data Firestore document data.
 * @return {Promise<Buffer>} The PDF as buffer.
 */
async function buildProvisionPdfBuffer(args: {
  commissionId: string;
  data: Record<string, unknown>;
}): Promise<Buffer> {
  const {data} = args;

  const doc = new PDFDocument({size: "A4", margin: 50});
  const chunks: Buffer[] = [];

  return await new Promise<Buffer>((resolve, reject) => {
    doc.on("data", (c: Buffer) => {
      chunks.push(Buffer.isBuffer(c) ? c : Buffer.from(c));
    });
    doc.on("end", () => resolve(Buffer.concat(chunks)));
    doc.on("error", reject);

    // Header
    doc
      .fontSize(16)
      .font("Helvetica-Bold")
      .text("Bestätigung über die Vereinbarung einer Vermittlungsprovision");
    doc.moveDown(0.6);

    // Vermittler
    doc.fontSize(12).font("Helvetica-Bold").text("Vermittler");
    doc.moveDown(0.2);
    doc.fontSize(11).font("Helvetica")
      .text(`Name: ${safeStr(data.recommenderName)}`);

    const street = safeStr(data.recommenderStreet);
    const zip = safeStr(data.recommenderZip);
    const city = safeStr(data.recommenderCity);
    doc.text(`Adresse: ${street}, ${zip} ${city}`);
    doc.moveDown(0.8);

    // Auszahlung
    doc.fontSize(12).font("Helvetica-Bold").text("Auszahlung");
    doc.moveDown(0.2);

    const payoutMethod = String(data.payoutMethod ?? "").trim();
    if (payoutMethod === "paypal") {
      doc.text(`PayPal: ${safeStr(data.payoutPaypal)}`);
    } else {
      doc.text(`IBAN: ${safeStr(data.payoutIban)}`);
    }
    doc.text(`Provisionsbetrag: ${formatEurAmount(data.amount)}`);

    const notes = safeStr(data.notes);
    if (notes !== "—") {
      doc.text(`Referenz/Notiz: ${notes}`);
    }


    const acceptedIsoRaw = data.acceptedAtClientIso;
    const acceptedIso = typeof acceptedIsoRaw === "string" ?
      acceptedIsoRaw : "";
    const acceptedDate = acceptedIso ? new Date(acceptedIso) : null;

    let acceptedLabel = safeStr(acceptedIsoRaw);
    if (acceptedDate && !Number.isNaN(acceptedDate.getTime())) {
      acceptedLabel = new Intl.DateTimeFormat("de-DE", {
        dateStyle: "short",
        timeStyle: "short",
        timeZone: "Europe/Berlin",
      }).format(acceptedDate);
    }

    doc.text(`Bestätigt am: ${acceptedLabel}`);

    doc.moveDown(1);

    // Signature
    doc.fontSize(12).font("Helvetica-Bold").text("Unterschrift Vermittler");
    doc.moveDown(0.2);

    const sigB64 = String(data.signaturePngBase64 ?? "").trim();
    if (sigB64) {
      try {
        const sigBuf = Buffer.from(sigB64, "base64");
        const x = doc.x;
        const y = doc.y;
        doc.rect(x, y, 500, 160).strokeColor("#d0d3dc").stroke();
        doc.image(sigBuf, x + 10, y + 10, {fit: [480, 140]});
        doc.moveDown(8);
      } catch {
        doc.fontSize(10).font("Helvetica").fillColor("#b00020")
          .text("Unterschrift konnte nicht eingebettet werden.");
        doc.fillColor("#000");
      }
    } else {
      doc.fontSize(10).font("Helvetica").fillColor("#b00020")
        .text("Keine Unterschrift übermittelt.");
      doc.fillColor("#000");
    }

    doc.moveDown(1);
    doc
      .fontSize(9)
      .fillColor("#666")
      .text(
        "Dieses Dokument wurde digital erstellt und ist mit der oben " +
          "dargestellten Unterschrift gültig."
      );
    doc.moveDown(0.4);
    doc.text(
      "Aussteller: Sachverständigenbüro Souleiman, Leerkämpe 12, " +
        "28259 Bremen"
    );
    doc.end();
  });
}

/**
 * Uploads the provision PDF to Firebase Storage.
 *
 * @param {object} args Upload arguments.
 * @param {string} args.commissionId Firestore document id.
 * @param {Buffer} args.pdf The PDF buffer.
 * @return {Promise<object>} Result with storage path and optional signed URL.
 */
async function uploadProvisionPdf(args: {
  commissionId: string;
  pdf: Buffer;
}): Promise<{path: string; url: string | null}> {
  const bucket = admin.storage().bucket();
  const path = `provision_pdfs/${args.commissionId}.pdf`;
  const file = bucket.file(path);

  await file.save(args.pdf, {
    contentType: "application/pdf",
    resumable: false,
    metadata: {
      cacheControl: "private, max-age=0, no-transform",
    },
  });

  // Optional Signed URL (7 Tage)
  try {
    const [url] = await file.getSignedUrl({
      action: "read",
      expires: Date.now() + 7 * 24 * 60 * 60 * 1000,
    });
    return {path, url};
  } catch {
    return {path, url: null};
  }
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
// Provision: Einmal-Link erzeugen (signed-in)
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
 * Creates a one-time provision form link for signed-in users.
 *
 * This endpoint validates the caller via Firebase ID token,
 * generates a UUID token with a configurable TTL,
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

    // Any signed-in user may create a provision link.

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


export const commissionCreatedSendPdf = onDocumentCreated(
  {
    document: "commissions/{commissionId}",
    secrets: [SMTP_HOST_SECRET, SMTP_USER_SECRET, SMTP_PASS_SECRET],
  },
  async (event) => {
    const commissionId = String(event.params.commissionId ?? "").trim();
    const snap = event.data;
    if (!snap) return;

    const data = (snap.data() ?? {}) as Record<string, unknown>;

    // Push an Admins: Neue Provisionsanfrage (idempotent)
    if (!data.adminPushSentAt) {
      try {
        const allAdminTokenRefs = await getAdminTokenRefs();
        const creatorUid = String(data.createdByUid ?? "").trim();
        const tokenRefs = filterOutUserTokenRefs(
          allAdminTokenRefs,
          creatorUid
        );
        const tokens = tokenRefs.map((t) => t.token);

        if (tokens.length === 0) {
          console.log("[push][commission_new] no admin tokens");
        } else {
          const name = String(data.recommenderName ?? "").trim();
          const amountTxt = formatEurAmount(data.amount);

          const bodyParts = [
            name || "Neue Anfrage",
            amountTxt !== "—" ? amountTxt : "",
          ].filter(Boolean);

          const resp = await admin.messaging().sendEachForMulticast({
            tokens,
            notification: {
              title: "Provision auszuzahlen",
              body: bodyParts.join(" · "),
            },
            data: {
              type: "commission_new",
              commissionId,
            },
          });

          console.log(
            "[push][commission_new] sent",
            resp.successCount,
            "ok,",
            resp.failureCount,
            "failed"
          );

          logMulticastFailures(
            "commission_new",
            tokens,
            resp.responses as Array<{success: boolean; error?: unknown}>
          );

          await cleanupDeadTokens(
            tokenRefs,
            resp.responses as Array<{success: boolean; error?: unknown}>
          );
        }

        await snap.ref.set(
          {adminPushSentAt: admin.firestore.FieldValue.serverTimestamp()},
          {merge: true}
        );
      } catch (e) {
        console.warn("[push][commission_new] FAILED", e);
      }
    }

    // Avoid double send
    if (data.mailSentAt) return;

    // Only for submitted commissions
    const status = String(data.status ?? "").trim();
    if (status && status !== "submitted") return;

    let pdf: Buffer;
    try {
      pdf = await buildProvisionPdfBuffer({commissionId, data});
    } catch (e) {
      console.error("[commissionCreatedSendPdf] PDF failed", e);
      await snap.ref.set(
        {
          mailError: "pdf_failed",
          mailErrorAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true}
      );
      return;
    }

    // Upload to Storage
    const uploaded = await uploadProvisionPdf({commissionId, pdf});

    let cfg: ProvisionMailConfig;
    try {
      cfg = getProvisionMailConfig();
    } catch (e) {
      console.error("[commissionCreatedSendPdf] SMTP config missing", e);
      await snap.ref.set(
        {
          pdfPath: uploaded.path,
          pdfUrl: uploaded.url,
          mailError: "smtp_config_missing",
          mailErrorAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true}
      );
      return;
    }

    const transport = nodemailer.createTransport({
      host: cfg.host,
      port: cfg.port,
      secure: cfg.secure,
      auth: {user: cfg.user, pass: cfg.pass},
    });

    const subject =
      `Provision übermittelt – ${safeStr(data.recommenderName)}`;

    const payoutMethod = String(data.payoutMethod ?? "").trim();
    let payoutLine = "";
    if (payoutMethod === "paypal") {
      payoutLine = `PayPal: ${safeStr(data.payoutPaypal)}`;
    } else {
      payoutLine = `IBAN: ${safeStr(data.payoutIban)}`;
    }

    const bodyText =
      "Eine Vermittlungsprovision wurde über das Webformular übermittelt.\n\n" +
      `Vermittler: ${safeStr(data.recommenderName)}\n` +
      `Adresse: ${safeStr(data.recommenderStreet)}, ` +
      `${safeStr(data.recommenderZip)} ` +
      `${safeStr(data.recommenderCity)}\n` +
      `Auszahlung: ${payoutLine}\n` +
      `Betrag: ${formatEurAmount(data.amount)}\n` +
      `Referenz/Notiz: ${safeStr(data.notes)}\n\n` +
      "PDF ist im Anhang.\n" +
      `Storage-Pfad: ${uploaded.path}` +
      (uploaded.url ? `\nSigned-URL (7 Tage): ${uploaded.url}` : "");

    try {
      await transport.sendMail({
        from: cfg.from,
        to: cfg.to,
        subject,
        text: bodyText,
        attachments: [
          {
            filename: `Provision_${commissionId}.pdf`,
            content: pdf,
            contentType: "application/pdf",
          },
        ],
      });

      await snap.ref.set(
        {
          pdfPath: uploaded.path,
          pdfUrl: uploaded.url,
          mailSentAt: admin.firestore.FieldValue.serverTimestamp(),
          mailTo: cfg.to,
          mailSubject: subject,
        },
        {merge: true}
      );
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : String(e);
      console.error("[commissionCreatedSendPdf] mail failed", e);
      await snap.ref.set(
        {
          pdfPath: uploaded.path,
          pdfUrl: uploaded.url,
          mailError: msg,
          mailErrorAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true}
      );
    }
  }
);
// Ensure all string literals use double quotes
