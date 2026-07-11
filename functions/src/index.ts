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
import {google, drive_v3 as driveV3} from "googleapis";
import {Readable} from "stream";
import {
  filterTokenRefsByPreference,
  isBooleanPreferenceEnabled,
} from "./pushPreferences";

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
 * Normalizes role input to one of the supported role values.
 *
 * @param {unknown} rawRole Raw incoming role value.
 * @return {Role} Safe role value.
 */
function normalizeRole(rawRole: unknown): Role {
  const roleInput = String(rawRole ?? "employee").trim().toLowerCase();
  if (
    roleInput === "admin" ||
    roleInput === "employee" ||
    roleInput === "expert"
  ) {
    return roleInput;
  }
  return "employee";
}

/**
 * Ensures a caller uid belongs to an admin user in Firestore.
 *
 * @param {string} callerUid Auth uid of the callable invoker.
 * @return {Promise<void>} Resolves for admins, throws otherwise.
 */
async function ensureCallerIsAdmin(callerUid: string): Promise<void> {
  const callerSnap = await admin
    .firestore()
    .collection("users")
    .doc(callerUid)
    .get();

  const callerRole = String(callerSnap.data()?.roleRaw ?? "").trim();
  if (callerRole !== "admin") {
    throw new HttpsError("permission-denied", "Admin only.");
  }
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
  await ensureCallerIsAdmin(callerUid);

  // 3) Payload validieren
  const data = request.data ?? {};
  const email = normalizeEmail(data.email);
  const name = String(data.name ?? "").trim();
  const roleRaw = normalizeRole(data.roleRaw);
  const colorName = String(data.colorName ?? "blue");
  const annualLeaveDays = Number(data.annualLeaveDays ?? 30);
  const birthdayISO = String(data.birthdayISO ?? "").trim();

  if (!email || !email.includes("@")) {
    throw new HttpsError("invalid-argument", "Invalid email.");
  }
  if (!name) {
    throw new HttpsError("invalid-argument", "Name required.");
  }

  let birthdayTs: admin.firestore.Timestamp | null = null;
  if (birthdayISO) {
    const birthdayDate = new Date(birthdayISO);
    if (Number.isNaN(birthdayDate.getTime())) {
      throw new HttpsError("invalid-argument", "Invalid birthdayISO.");
    }
    // Normalize to 12:00 UTC to avoid day-shifts around timezones.
    const normalized = new Date(Date.UTC(
      birthdayDate.getUTCFullYear(),
      birthdayDate.getUTCMonth(),
      birthdayDate.getUTCDate(),
      12, 0, 0, 0
    ));
    birthdayTs = admin.firestore.Timestamp.fromDate(normalized);
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
    pushEnabled: true,
    ...(birthdayTs ? {birthday: birthdayTs} : {}),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    createdByUid: callerUid,
  };

  await admin
    .firestore()
    .collection("invites")
    .doc(email)
    .set(invite, {merge: true});

  // Also pre-create/update the concrete profile doc so first login does not
  // depend on client-side invite hydration.
  await admin
    .firestore()
    .collection("users")
    .doc(userRecord.uid)
    .set({
      name,
      roleRaw,
      colorName,
      annualLeaveDays,
      email,
      pushEnabled: true,
      ...(birthdayTs ? {birthday: birthdayTs} : {}),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

  return {
    ok: true,
    uid: userRecord.uid,
    email,
  };
});

/**
 * Callable Function (Admin-only):
 * - Checks caller is authenticated and admin.
 * - Deletes a Firebase Auth user by uid.
 * - Returns ok=true even if the user is already missing in Auth.
 */
export const adminDeleteUser = onCall(async (request) => {
  const callerUid = request.auth?.uid;
  if (!callerUid) {
    throw new HttpsError("unauthenticated", "Not signed in.");
  }

  await ensureCallerIsAdmin(callerUid);

  const uid = String(request.data?.uid ?? "").trim();
  if (!uid) {
    throw new HttpsError("invalid-argument", "uid required.");
  }
  if (uid === callerUid) {
    throw new HttpsError(
      "failed-precondition",
      "Admin cannot delete own account."
    );
  }

  try {
    await admin.auth().deleteUser(uid);
  } catch (e: unknown) {
    const code = String((e as {code?: unknown})?.code ?? "");
    if (code !== "auth/user-not-found") {
      const message = e instanceof Error ? e.message : String(e);
      throw new HttpsError("internal", "Auth delete failed: " + message);
    }
  }

  return {ok: true, uid};
});

/**
 * Callable (signed-in):
 * Hydrates users/<uid> from invites/<email> server-side and deletes invite.
 * This avoids client-side rule races
 * when a stub users/<uid> doc already exists.
 */
export const bootstrapMyProfileFromInvite = onCall(async (request) => {
  const callerUid = request.auth?.uid;
  if (!callerUid) {
    throw new HttpsError("unauthenticated", "Not signed in.");
  }

  const userRecord = await admin.auth().getUser(callerUid);
  const email = normalizeEmail(userRecord.email ?? "");
  if (!email) {
    throw new HttpsError("failed-precondition", "No email on auth user.");
  }

  const db = admin.firestore();
  const inviteRef = db.collection("invites").doc(email);
  const userRef = db.collection("users").doc(callerUid);

  await db.runTransaction(async (tx) => {
    const inviteSnap = await tx.get(inviteRef);
    if (!inviteSnap.exists) {
      throw new HttpsError("not-found", "No invite found for current email.");
    }

    const raw = (inviteSnap.data() ?? {}) as Record<string, unknown>;
    const name = String(raw.name ?? "").trim();
    const colorName = String(raw.colorName ?? "gray").trim() || "gray";
    const roleRaw = normalizeRole(raw.roleRaw);

    const annualRaw = Number(raw.annualLeaveDays ?? 30);
    const annualLeaveDays = Number.isFinite(annualRaw) ?
      Math.max(0, Math.floor(annualRaw)) : 30;

    if (!name) {
      throw new HttpsError("failed-precondition", "Invite missing name.");
    }

    const patch: Record<string, unknown> = {
      name,
      roleRaw,
      colorName,
      annualLeaveDays,
      email,
      pushEnabled: typeof raw.pushEnabled === "boolean" ?
        raw.pushEnabled :
        true,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (raw.birthday instanceof admin.firestore.Timestamp) {
      patch.birthday = raw.birthday;
    }

    tx.set(userRef, patch, {merge: true});
    tx.delete(inviteRef);
  });

  return {
    ok: true,
    uid: callerUid,
    email,
  };
});

/**
 * Returns true if a user document already has the required profile core.
 *
 * @param {unknown} raw Firestore document data.
 * @return {boolean} True when core fields are present with expected types.
 */
function hasUserProfileCore(raw: unknown): boolean {
  const d = (raw ?? {}) as Record<string, unknown>;
  return typeof d.name === "string" &&
    typeof d.roleRaw === "string" &&
    typeof d.colorName === "string" &&
    Number.isInteger(d.annualLeaveDays) &&
    typeof d.email === "string";
}

/**
 * Hydrates users/<uid> from invites/<email> if the user doc is only a stub.
 *
 * @param {string} uid Firebase Auth UID.
 * @return {Promise<void>} Resolves once hydration attempt finishes.
 */
async function hydrateUserFromInviteIfNeeded(uid: string): Promise<void> {
  const cleanUid = String(uid ?? "").trim();
  if (!cleanUid) return;

  const db = admin.firestore();
  const userRef = db.collection("users").doc(cleanUid);

  const userRecord = await admin.auth().getUser(cleanUid).catch(() => null);
  const email = normalizeEmail(userRecord?.email ?? "");
  if (!email) return;

  const inviteRef = db.collection("invites").doc(email);

  await db.runTransaction(async (tx) => {
    const userSnap = await tx.get(userRef);
    if (hasUserProfileCore(userSnap.data())) return;

    const inviteSnap = await tx.get(inviteRef);
    if (!inviteSnap.exists) return;

    const raw = (inviteSnap.data() ?? {}) as Record<string, unknown>;
    const name = String(raw.name ?? "").trim();
    if (!name) return;

    const colorName = String(raw.colorName ?? "gray").trim() || "gray";
    const roleRaw = normalizeRole(raw.roleRaw);
    const annualRaw = Number(raw.annualLeaveDays ?? 30);
    const annualLeaveDays = Number.isFinite(annualRaw) ?
      Math.max(0, Math.floor(annualRaw)) : 30;

    const patch: Record<string, unknown> = {
      name,
      roleRaw,
      colorName,
      annualLeaveDays,
      email,
      pushEnabled: typeof raw.pushEnabled === "boolean" ?
        raw.pushEnabled :
        true,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (raw.birthday instanceof admin.firestore.Timestamp) {
      patch.birthday = raw.birthday;
    }

    tx.set(userRef, patch, {merge: true});
    tx.delete(inviteRef);
  });
}

/**
 * Auto-hydrates a stub users/<uid> document from invite data.
 */
export const hydrateUserProfileFromInviteOnCreate = onDocumentCreated(
  "users/{uid}",
  async (event) => {
    const uid = String(event.params.uid ?? "").trim();
    if (!uid) return;
    await hydrateUserFromInviteIfNeeded(uid);
  }
);

/**
 * Also hydrate on updates because badge writes can create/update stubs first.
 */
export const hydrateUserProfileFromInviteOnUpdate = onDocumentUpdated(
  "users/{uid}",
  async (event) => {
    const uid = String(event.params.uid ?? "").trim();
    if (!uid) return;

    const afterData = event.data?.after.data();
    if (hasUserProfileCore(afterData)) return;
    await hydrateUserFromInviteIfNeeded(uid);
  }
);

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
 * Returns true when FCM reports APNs auth mismatch for a token.
 *
 * This usually indicates a stale token from another app/project config.
 *
 * @param {unknown} err The error object from FCM response.
 * @return {boolean} True if token likely belongs to wrong APNs credentials.
 */
function isThirdPartyAuthTokenError(err: unknown): boolean {
  const anyErr = err as {code?: unknown};
  const code = String(anyErr?.code ?? "");
  return code === "messaging/third-party-auth-error";
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
 * @param {boolean} removeThirdPartyAuthFailures Whether APNs auth failures
 * should also be removed as stale token docs.
 * @return {Promise<void>} Resolves when invalid tokens are removed.
 */
async function cleanupDeadTokens(
  tokenRefs: TokenRef[],
  responses: Array<{success: boolean; error?: unknown}>,
  removeThirdPartyAuthFailures = false
): Promise<void> {
  const toDelete: admin.firestore.DocumentReference[] = [];

  responses.forEach((r, i) => {
    const shouldDelete =
      !r.success && (
        isTokenGone(r.error) ||
        (removeThirdPartyAuthFailures && isThirdPartyAuthTokenError(r.error))
      );
    if (shouldDelete) {
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
 * Returns APNs config with badge disabled (always 0).
 *
 * App icon badges are intentionally not used because counts were unreliable.
 *
 * @return {admin.messaging.ApnsConfig} APNs config with badge set to 0.
 */
function appIconBadgeApnsConfig(): admin.messaging.ApnsConfig {
  return {
    payload: {
      aps: {
        badge: 0,
      },
    },
  };
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

  const admins = adminsSnap.docs.filter((u) => u.data()?.pushEnabled !== false);

  const out: TokenRef[] = [];
  const seen = new Set<string>();

  for (const u of admins) {
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
 * Fetches FCM token refs for admins that explicitly opted into
 * provision payout pushes.
 *
 * @return {Promise<TokenRef[]>} A deduplicated list of admin device tokens.
 */
async function getProvisionPushAdminTokenRefs(): Promise<TokenRef[]> {
  const adminsSnap = await admin.firestore()
    .collection("users")
    .where("roleRaw", "==", "admin")
    .where("receiveAdminPushes", "==", true)
    .get();

  const admins = adminsSnap.docs.filter((u) => u.data()?.pushEnabled !== false);

  const out: TokenRef[] = [];
  const seen = new Set<string>();

  for (const u of admins) {
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
 * Returns true when identity is not a plain Firebase UID.
 *
 * @param {string} identity Raw identity from Firestore.
 * @return {boolean} True for legacy invite/email identities.
 */
function isLegacyInviteIdentity(identity: string): boolean {
  const v = String(identity ?? "").trim().toLowerCase();
  if (!v) return false;
  return v.startsWith("invite:") || v.includes("@");
}

/**
 * Extracts a normalized email from legacy identity forms.
 *
 * @param {string} identity Raw id (uid, invite:email or email).
 * @return {string} Normalized email or empty string.
 */
function emailFromIdentity(identity: string): string {
  const v = String(identity ?? "").trim();
  if (!v) return "";
  if (v.toLowerCase().startsWith("invite:")) {
    return normalizeEmail(v.slice("invite:".length));
  }
  if (v.includes("@")) {
    return normalizeEmail(v);
  }
  return "";
}

/**
 * Fetches deduplicated token refs for one concrete UID.
 *
 * @param {string} uid Firebase Auth UID.
 * @return {Promise<TokenRef[]>} Device tokens for this user.
 */
async function getUserTokenRefsByUid(uid: string): Promise<TokenRef[]> {
  const cleanUid = String(uid ?? "").trim();
  if (!cleanUid) return [];

  const devicesSnap = await admin
    .firestore()
    .collection("users")
    .doc(cleanUid)
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
    out.push({token, ref: d.ref, ownerUserId: cleanUid});
  }

  return out;
}

/**
 * Resolves a concrete users/<uid> document id by email.
 *
 * @param {string} rawEmail Email candidate.
 * @return {Promise<string>} Resolved uid or empty string.
 */
async function resolveUidByEmail(rawEmail: string): Promise<string> {
  const email = normalizeEmail(rawEmail);
  if (!email) return "";

  const qs = await admin.firestore()
    .collection("users")
    .where("email", "==", email)
    .limit(1)
    .get();

  if (!qs.empty) {
    return String(qs.docs[0].id ?? "").trim();
  }

  try {
    const rec = await admin.auth().getUserByEmail(email);
    return String(rec.uid ?? "").trim();
  } catch {
    return "";
  }
}

/**
 * Fetches all FCM token refs for a given user.
 *
 * Supports legacy identities (`invite:<email>` / `<email>`) by resolving
 * them to a concrete users/<uid> profile first.
 *
 * @param {string} userId - Target identity (uid or legacy identity).
 * @param {string} userEmailHint Optional explicit email from document payload.
 * @return {Promise<TokenRef[]>} Deduplicated list of user device tokens.
 */
async function getUserTokenRefs(
  userId: string,
  userEmailHint = ""
): Promise<TokenRef[]> {
  const identity = String(userId ?? "").trim();
  if (!identity) return [];

  // Fast path for normal UIDs.
  if (!isLegacyInviteIdentity(identity)) {
    return getUserTokenRefsByUid(identity);
  }

  // Legacy path: invite:<email> or raw email -> resolve to real uid.
  const hint = normalizeEmail(userEmailHint);
  const email = hint || emailFromIdentity(identity);
  if (!email) return [];

  const resolvedUid = await resolveUidByEmail(email);
  if (!resolvedUid) return [];

  return getUserTokenRefsByUid(resolvedUid);
}

/**
 * Fetches FCM token refs for all users.
 *
 * @return {Promise<TokenRef[]>} Deduplicated list of all user device tokens.
 */
async function getAllUserTokenRefs(): Promise<TokenRef[]> {
  const usersSnap = await admin.firestore()
    .collection("users")
    .get();

  const out: TokenRef[] = [];
  const seen = new Set<string>();

  for (const u of usersSnap.docs) {
    if (u.data()?.pushEnabled === false) continue;

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
 * Filters token refs by a boolean user preference on users/<uid>.
 *
 * @param {TokenRef[]} tokenRefs Token refs to filter.
 * @param {string} fieldName Boolean preference field name.
 * @param {boolean} defaultEnabled Fallback when field is missing.
 * @return {Promise<TokenRef[]>} Filtered token refs.
 */
async function filterTokenRefsByUserBooleanPreference(
  tokenRefs: TokenRef[],
  fieldName: string,
  defaultEnabled: boolean
): Promise<TokenRef[]> {
  if (tokenRefs.length === 0) return tokenRefs;

  const ownerIds = Array.from(
    new Set(
      tokenRefs
        .map((tr) => String(tr.ownerUserId ?? "").trim())
        .filter((uid) => uid.length > 0)
    )
  );
  if (ownerIds.length === 0) return [];

  const enabledByUid = new Map<string, boolean>();

  await Promise.all(
    ownerIds.map(async (uid) => {
      try {
        const snap = await admin.firestore().collection("users").doc(uid).get();
        const raw = (
          snap.data() as Record<string, unknown> | undefined
        )?.[fieldName];
        const enabled = isBooleanPreferenceEnabled(raw, defaultEnabled);
        enabledByUid.set(uid, enabled);
      } catch {
        enabledByUid.set(uid, defaultEnabled);
      }
    })
  );

  return filterTokenRefsByPreference(tokenRefs, enabledByUid, defaultEnabled);
}

/**
 * Best-effort lookup of a user's name for push messages.
 *
 * @param {string} userId - Firebase Auth UID of the target user.
 */
async function getUserNameOrFallback(userId: string): Promise<string> {
  const identity = String(userId ?? "").trim();
  if (!identity) return "Jemand";

  const email = emailFromIdentity(identity);
  const uid = isLegacyInviteIdentity(identity) ?
    await resolveUidByEmail(email) :
    identity;

  if (!uid) {
    return email ? displayNameFromEmail(email) : "Jemand";
  }

  try {
    const snap = await admin.firestore()
      .collection("users")
      .doc(uid)
      .get();
    const name = String(snap.data()?.name ?? "").trim();
    if (name) return name;
    return email ? displayNameFromEmail(email) : "Jemand";
  } catch {
    return email ? displayNameFromEmail(email) : "Jemand";
  }
}

/**
 * Creates a human-readable fallback display name from an email address.
 *
 * @param {string} email The email to derive a name from.
 * @return {string} Display name fallback.
 */
function displayNameFromEmail(email: string): string {
  const local = normalizeEmail(email).split("@")[0] ?? "";
  const cleaned = local.replace(/[._-]+/g, " ").trim();
  if (!cleaned) return "Jemand";
  return cleaned
    .split(/\s+/)
    .map((part) => {
      if (!part) return "";
      return part.charAt(0).toUpperCase() + part.slice(1);
    })
    .join(" ")
    .trim() || "Jemand";
}

/**
 * Formats a Date using German locale.
 *
 * @param {Date} date Date to format.
 * @param {boolean} includeWeekday Whether weekday should be included.
 * @return {string} Formatted date label.
 */
function formatGermanDate(date: Date, includeWeekday = true): string {
  const opts: Intl.DateTimeFormatOptions = {
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    // Keep push dates aligned with the app's target locale.
    // Without a fixed zone, Cloud Functions defaults can shift dates by -1 day.
    timeZone: "Europe/Berlin",
  };
  if (includeWeekday) {
    opts.weekday = "short";
  }
  return new Intl.DateTimeFormat("de-DE", opts).format(date);
}

/**
 * Returns true if two dates fall on the same calendar day (UTC).
 *
 * @param {Date} a First date.
 * @param {Date} b Second date.
 * @return {boolean} True if same day.
 */
function isSameUtcDay(a: Date, b: Date): boolean {
  return a.getUTCFullYear() === b.getUTCFullYear() &&
    a.getUTCMonth() === b.getUTCMonth() &&
    a.getUTCDate() === b.getUTCDate();
}

/**
 * Builds a human-readable leave date label from Firestore timestamps.
 *
 * @param {unknown} startRaw startDate value.
 * @param {unknown} endRaw endDate value.
 * @param {boolean} includeWeekday Whether weekday should be included.
 * @return {string} Date label for push body.
 */
function leaveDateLabel(
  startRaw: unknown,
  endRaw: unknown,
  includeWeekday = true
): string {
  const startTs =
    startRaw instanceof admin.firestore.Timestamp ? startRaw : null;
  const endTs =
    endRaw instanceof admin.firestore.Timestamp ? endRaw : null;
  const startDate = startTs?.toDate() ?? null;
  const endDate = endTs?.toDate() ?? null;

  if (!startDate && !endDate) return "";

  if (startDate && endDate) {
    if (isSameUtcDay(startDate, endDate)) {
      return formatGermanDate(startDate, includeWeekday);
    }
    return `${formatGermanDate(startDate, includeWeekday)} - ` +
      `${formatGermanDate(endDate, includeWeekday)}`;
  }

  const single = startDate ?? endDate;
  return single ? formatGermanDate(single, includeWeekday) : "";
}

/**
 * Formats a meeting datetime for user-facing push notifications.
 *
 * @param {Date} date Meeting date and time.
 * @return {string} Formatted datetime label.
 */
function formatGermanDateTime(date: Date): string {
  return new Intl.DateTimeFormat("de-DE", {
    weekday: "short",
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    timeZone: "Europe/Berlin",
  }).format(date);
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

/**
 * Clears the unread badge counter for one user.
 *
 * @param {string} userId Firebase Auth UID.
 * @return {Promise<void>} Resolves when reset is written.
 */
async function clearUnreadBadgeForUser(userId: string): Promise<void> {
  const uid = String(userId ?? "").trim();
  if (!uid) return;

  await admin.firestore().collection("users").doc(uid).set({
    unreadNotificationCount: 0,
    unreadNotificationUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});
}

/**
 * Splits token refs by owner user id so each owner can receive its own badge.
 *
 * @param {TokenRef[]} tokenRefs Token refs to split.
 * @return {Map<string, TokenRef[]>} Grouped refs keyed by owner uid.
 */
function groupTokenRefsByOwner(tokenRefs: TokenRef[]): Map<string, TokenRef[]> {
  const out = new Map<string, TokenRef[]>();
  for (const tr of tokenRefs) {
    const owner = String(tr.ownerUserId ?? "").trim();
    if (!owner) continue;
    const list = out.get(owner) ?? [];
    list.push(tr);
    out.set(owner, list);
  }
  return out;
}

/**
 * Sends one logical push payload to many users.
 *
 * Badge counters are disabled; each push explicitly clears the app icon
 * badge via APNs badge=0.
 *
 * @param {string} tag Short logging tag.
 * @param {TokenRef[]} tokenRefs Recipient device token refs.
 * @param {admin.messaging.Notification} notification Notification payload.
 * @param {Record<string, string>} data Data payload.
 * @return {Promise<void>} Resolves after all owner groups are handled.
 */
async function sendBadgeCountedMulticast(
  tag: string,
  tokenRefs: TokenRef[],
  notification: admin.messaging.Notification,
  data: Record<string, string>
): Promise<void> {
  const byOwner = groupTokenRefsByOwner(tokenRefs);
  if (byOwner.size === 0) {
    console.log("[push][" + tag + "] no owner groups");
    return;
  }

  let totalSuccess = 0;
  let totalFailure = 0;

  for (const [, ownerRefs] of byOwner.entries()) {
    const tokens = ownerRefs.map((t) => t.token);
    if (tokens.length === 0) continue;

    const resp = await admin.messaging().sendEachForMulticast({
      tokens,
      apns: appIconBadgeApnsConfig(),
      notification,
      data,
    });

    totalSuccess += resp.successCount;
    totalFailure += resp.failureCount;

    logMulticastFailures(
      tag,
      tokens,
      resp.responses as Array<{success: boolean; error?: unknown}>
    );

    // If at least one token succeeded, remove third-party auth failures.
    // This cleans up stale tokens from wrong bundle/project APNs config
    // without risking a full wipe during a global APNs outage.
    const removeThirdPartyAuthFailures = resp.successCount > 0;
    await cleanupDeadTokens(
      ownerRefs,
      resp.responses as Array<{success: boolean; error?: unknown}>,
      removeThirdPartyAuthFailures
    );
  }

  console.log(
    "[push][" + tag + "] sent",
    totalSuccess,
    "ok,",
    totalFailure,
    "failed"
  );
}

export const clearMyUnreadBadge = onCall(async (request) => {
  const callerUid = request.auth?.uid;
  if (!callerUid) {
    throw new HttpsError("unauthenticated", "Not signed in.");
  }

  await clearUnreadBadgeForUser(callerUid);
  return {ok: true};
});

export const setMyPushEnabled = onCall(async (request) => {
  const callerUid = request.auth?.uid;
  if (!callerUid) {
    throw new HttpsError("unauthenticated", "Not signed in.");
  }

  const data = (request.data ?? {}) as Record<string, unknown>;
  const enabledRaw = data.enabled;
  if (typeof enabledRaw !== "boolean") {
    throw new HttpsError("invalid-argument", "enabled must be boolean.");
  }

  const enabled = enabledRaw;
  const patch: Record<string, unknown> = {
    pushEnabled: enabled,
    pushEnabledUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  if (!enabled) {
    patch.unreadNotificationCount = 0;
    patch.unreadNotificationUpdatedAt =
      admin.firestore.FieldValue.serverTimestamp();
  }

  await admin.firestore().collection("users").doc(callerUid)
    .set(patch, {merge: true});

  return {
    ok: true,
    pushEnabled: enabled,
  };
});

export const setMyReceiveAdminPushes = onCall(async (request) => {
  const callerUid = request.auth?.uid;
  if (!callerUid) {
    throw new HttpsError("unauthenticated", "Not signed in.");
  }

  await ensureCallerIsAdmin(callerUid);

  const data = (request.data ?? {}) as Record<string, unknown>;
  const enabledRaw = data.enabled;
  if (typeof enabledRaw !== "boolean") {
    throw new HttpsError("invalid-argument", "enabled must be boolean.");
  }

  const enabled = enabledRaw;

  await admin.firestore().collection("users").doc(callerUid).set({
    receiveAdminPushes: enabled,
    receiveAdminPushesUpdatedAt:
      admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});

  return {
    ok: true,
    receiveAdminPushes: enabled,
  };
});

export const setMyMeetingSchedulePushEnabled = onCall(async (request) => {
  const callerUid = request.auth?.uid;
  if (!callerUid) {
    throw new HttpsError("unauthenticated", "Not signed in.");
  }

  const data = (request.data ?? {}) as Record<string, unknown>;
  const enabledRaw = data.enabled;
  if (typeof enabledRaw !== "boolean") {
    throw new HttpsError("invalid-argument", "enabled must be boolean.");
  }

  const enabled = enabledRaw;

  await admin.firestore().collection("users").doc(callerUid).set({
    meetingSchedulePushEnabled: enabled,
    meetingSchedulePushUpdatedAt:
      admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});

  return {
    ok: true,
    meetingSchedulePushEnabled: enabled,
  };
});

export const adminDeleteMeetingArchive = onCall(async (request) => {
  const callerUid = request.auth?.uid;
  if (!callerUid) {
    throw new HttpsError("unauthenticated", "Not signed in.");
  }

  await ensureCallerIsAdmin(callerUid);

  const data = (request.data ?? {}) as Record<string, unknown>;
  const archiveId = String(data.archiveId ?? "").trim();
  if (!archiveId) {
    throw new HttpsError("invalid-argument", "archiveId required.");
  }

  await admin.firestore()
    .collection("meetingArchives")
    .doc(archiveId)
    .delete();

  return {
    ok: true,
    archiveId,
  };
});

export const adminUpdateMeetingArchiveProtocol = onCall(async (request) => {
  const callerUid = request.auth?.uid;
  if (!callerUid) {
    throw new HttpsError("unauthenticated", "Not signed in.");
  }

  await ensureCallerIsAdmin(callerUid);

  const data = (request.data ?? {}) as Record<string, unknown>;
  const archiveId = String(data.archiveId ?? "").trim();
  if (!archiveId) {
    throw new HttpsError("invalid-argument", "archiveId required.");
  }

  const protocolTextRaw = data.protocolText;
  if (typeof protocolTextRaw !== "string") {
    throw new HttpsError("invalid-argument", "protocolText must be string.");
  }

  const protocolText = protocolTextRaw.trim();
  if (protocolText.length > 20000) {
    throw new HttpsError(
      "invalid-argument",
      "protocolText too long (max 20000 chars)."
    );
  }

  await admin.firestore()
    .collection("meetingArchives")
    .doc(archiveId)
    .set({
      protocolText,
      protocolUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      protocolUpdatedByUserId: callerUid,
    }, {merge: true});

  return {
    ok: true,
    archiveId,
  };
});

/**
 * Sends a "meeting date set/changed" push to all users.
 *
 * @param {admin.firestore.Timestamp} meetingAtTs Timestamp of the next meeting.
 * @param {string} updatedByUid User who changed the date (excluded from push).
 * @param {string} tag Short log tag.
 */
async function pushMeetingDateChanged(
  meetingAtTs: admin.firestore.Timestamp,
  updatedByUid: string,
  tag: string
): Promise<void> {
  const meetingAt = meetingAtTs.toDate();
  const meetingDateLabel = formatGermanDateTime(meetingAt);

  const allTokenRefs = await getAllUserTokenRefs();
  const withoutSelf = filterOutUserTokenRefs(allTokenRefs, updatedByUid);
  const tokenRefs = await filterTokenRefsByUserBooleanPreference(
    withoutSelf,
    "meetingSchedulePushEnabled",
    true
  );
  if (tokenRefs.length === 0) {
    console.log("[push][" + tag + "] no user meeting-push tokens");
    return;
  }

  await sendBadgeCountedMulticast(
    tag,
    tokenRefs,
    {
      title: "Neuer Meeting-Termin",
      body: "Nächstes Meeting: " + meetingDateLabel,
    },
    {
      type: "meeting_schedule_updated",
      meetingDateLabel,
      meetingDateIso: meetingAt.toISOString(),
    }
  );
}

export const pushOnMeetingScheduleCreated = onDocumentCreated(
  "meetingMeta/schedule",
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const data = (snap.data() ?? {}) as Record<string, unknown>;
    const meetingAtTs = data.nextMeetingAt;
    if (!(meetingAtTs instanceof admin.firestore.Timestamp)) return;

    const updatedByUid = String(data.updatedByUserId ?? "").trim();
    await pushMeetingDateChanged(meetingAtTs, updatedByUid, "meeting_created");
  }
);

export const pushOnMeetingScheduleUpdated = onDocumentUpdated(
  "meetingMeta/schedule",
  async (event) => {
    const before = event.data?.before;
    const after = event.data?.after;
    if (!before || !after) return;

    const beforeData = (before.data() ?? {}) as Record<string, unknown>;
    const afterData = (after.data() ?? {}) as Record<string, unknown>;

    const beforeTs = beforeData.nextMeetingAt;
    const afterTs = afterData.nextMeetingAt;

    const beforeDate =
      beforeTs instanceof admin.firestore.Timestamp ? beforeTs.toDate() : null;
    const afterDate =
      afterTs instanceof admin.firestore.Timestamp ? afterTs.toDate() : null;

    // No push when the date was removed (e.g., meeting archived).
    if (!afterDate) return;

    // No push if timestamp did not change.
    if (beforeDate && beforeDate.getTime() === afterDate.getTime()) return;

    const updatedByUid = String(afterData.updatedByUserId ?? "").trim();
    const meetingAtTs = afterTs as admin.firestore.Timestamp;
    await pushMeetingDateChanged(meetingAtTs, updatedByUid, "meeting_updated");
  }
);

// Neuer Antrag -> Admins
export const pushOnNewLeaveRequest =
  onDocumentCreated(
    "leaveRequests/{requestId}",
    async (event) => {
      const snap = event.data;
      if (!snap) return;

      const data = (snap.data() ?? {}) as Record<string, unknown>;

      const typeRaw = String(data.typeRaw ?? "").trim() || "Antrag";
      const normalizedType = typeRaw.toLowerCase();
      const isOnCall = normalizedType === "bereitschaft";
      const isSick = normalizedType === "krankheit";
      const isVacation = normalizedType === "urlaub";
      const requestUserId = String(data.userId ?? "").trim();
      const requestUserEmail = normalizeEmail(String(data.userEmail ?? ""));
      const requestDate = leaveDateLabel(
        data.startDate,
        data.endDate,
        false
      );
      let requestUserName = requestUserId ?
        await getUserNameOrFallback(requestUserId) :
        "Jemand";
      if (requestUserName === "Jemand" && requestUserEmail) {
        requestUserName = displayNameFromEmail(requestUserEmail);
      }

      let notificationTitle = "Neuer Antrag";
      if (isOnCall) {
        notificationTitle = "Neue Bereitschaft";
      } else if (isSick) {
        notificationTitle = "Krankheit gemeldet";
      } else if (isVacation) {
        notificationTitle = "Neuer Urlaubsantrag";
      }
      let notificationBody = typeRaw;
      const hasName = requestUserName && requestUserName !== "Jemand";
      const hasDate = !!requestDate;
      let requesterAndDate = "";
      if (hasName && hasDate) {
        requesterAndDate = `${requestUserName} · ${requestDate}`;
      } else if (hasName) {
        requesterAndDate = requestUserName;
      } else if (hasDate) {
        requesterAndDate = requestDate;
      }

      if (isOnCall || isSick || isVacation) {
        if (requesterAndDate) {
          notificationBody = requesterAndDate;
        }
      } else if (requesterAndDate) {
        notificationBody = `${typeRaw} · ${requesterAndDate}`;
      }

      // Prevent self-notifications: if the creator is also an admin,
      // do not send the "new request" push to their own devices.
      const creatorUserId = String(
        data.createdByUid ??
        data.createdByUserId ??
        data.creatorUserId ??
        data.userId ??
        ""
      ).trim();
      const requestStatusRaw = String(data.statusRaw ?? "").trim();

      console.log(
        "[push][new] requestId=",
        String(event.params.requestId ?? "")
      );

      // When an admin directly assigns an on-call entry to another user,
      // notify that assignee on create (there is no later status change event).
      const shouldNotifyOnCallAssignee =
        isOnCall &&
        !!requestUserId &&
        !!creatorUserId &&
        requestUserId !== creatorUserId;

      if (shouldNotifyOnCallAssignee) {
        const assigneeTokenRefs = await getUserTokenRefs(
          requestUserId,
          requestUserEmail
        );
        const assigneeTargets = filterOutUserTokenRefs(
          assigneeTokenRefs,
          creatorUserId
        );

        if (assigneeTargets.length === 0) {
          console.log(
            "[push][oncall_assigned] no user tokens for",
            requestUserId
          );
        } else {
          const assignedTitle = requestStatusRaw === "Genehmigt" ?
            "Neue Bereitschaft" :
            "Bereitschaft eingetragen";
          const assignedBody = requestDate ?
            "Du wurdest für " + requestDate + " eingetragen." :
            "Du wurdest für eine Bereitschaft eingetragen.";

          await sendBadgeCountedMulticast(
            "oncall_assigned",
            assigneeTargets,
            {
              title: assignedTitle,
              body: assignedBody,
            },
            {
              type: "leave_request_oncall_assigned",
              requestId: String(event.params.requestId ?? ""),
              decision: "approved",
              leaveTypeRaw: typeRaw,
              requestDateLabel: requestDate,
            }
          );
        }
      }

      const allAdminTokenRefs = await getAdminTokenRefs();
      const tokenRefs = filterOutUserTokenRefs(
        allAdminTokenRefs,
        creatorUserId
      );
      if (tokenRefs.length === 0) {
        console.log("[push][new] no admin tokens");
        return;
      }

      await sendBadgeCountedMulticast(
        "new",
        tokenRefs,
        {
          title: notificationTitle,
          body: notificationBody,
        },
        {
          type: "leave_request_new",
          leaveTypeRaw: typeRaw,
          requesterName: requestUserName,
          requestDateLabel: requestDate,
          requestId: String(event.params.requestId ?? ""),
        }
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
    const userEmail = String(afterData.userEmail ?? "").trim();
    if (!userId && !userEmail) return;
    const leaveTypeRaw = String(afterData.typeRaw ?? "").trim() || "Antrag";
    const leaveTypeNormalized = leaveTypeRaw.toLowerCase();
    const requestDate = leaveDateLabel(
      afterData.startDate,
      afterData.endDate,
      false
    );

    let notificationTitle = isApproved ? "Antrag genehmigt" :
      "Antrag abgelehnt";

    if (leaveTypeNormalized === "urlaub") {
      notificationTitle = isApproved ? "Urlaubsantrag genehmigt" :
        "Urlaubsantrag abgelehnt";
    } else if (leaveTypeNormalized === "krankheit") {
      notificationTitle = isApproved ? "Krankmeldung bestätigt" :
        "Krankmeldung abgelehnt";
    } else if (leaveTypeNormalized === "bereitschaft") {
      notificationTitle = isApproved ? "Bereitschaft bestätigt" :
        "Bereitschaft abgelehnt";
    }

    let notificationBody = leaveTypeRaw;
    if (requestDate) {
      notificationBody = `${leaveTypeRaw} · ${requestDate}`;
    }

    console.log(
      "[push][decision] requestId=",
      String(event.params.requestId ?? ""),
      "before=",
      beforeStatus,
      "after=",
      afterStatus
    );

    const tokenRefs = await getUserTokenRefs(userId, userEmail);
    if (tokenRefs.length === 0) {
      console.log(
        "[push][decision] no user tokens for",
        userId || userEmail
      );
      return;
    }

    await sendBadgeCountedMulticast(
      isApproved ? "approved" : "rejected",
      tokenRefs,
      {
        title: notificationTitle,
        body: notificationBody,
      },
      {
        type: isApproved ? "leave_request_approved" : "leave_request_rejected",
        requestId: String(event.params.requestId ?? ""),
        decision: isApproved ? "approved" : "rejected",
        leaveTypeRaw,
        requestDateLabel: requestDate,
      }
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
    if (tokenRefs.length === 0) {
      console.log("[push][task_assigned] no user tokens for", assignedUserId);
      return;
    }

    await sendBadgeCountedMulticast(
      "task_assigned",
      tokenRefs,
      {
        title: "Neue Aufgabe",
        body: fromName + " hat dir eine Aufgabe zugeteilt: " + title,
      },
      {
        type: "task_assigned",
        taskId: String(event.params.taskId ?? ""),
        toUserId: assignedUserId,
        fromUserId: creatorUserId,
      }
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
    if (tokenRefs.length === 0) {
      console.log("[push][task_reassigned] no user tokens for", afterAssignee);
      return;
    }

    await sendBadgeCountedMulticast(
      "task_reassigned",
      tokenRefs,
      {
        title: "Aufgabe zugeteilt",
        body: fromName + " hat dir eine Aufgabe zugeteilt: " + title,
      },
      {
        type: "task_assigned",
        taskId: String(event.params.taskId ?? ""),
        toUserId: afterAssignee,
        fromUserId: creatorUserId,
        reassigned: "1",
      }
    );
  }
);

export const pushOnTaskCompleted = onDocumentUpdated(
  "tasks/{taskId}",
  async (event) => {
    const before = event.data?.before;
    const after = event.data?.after;
    if (!before || !after) return;

    const beforeData = (before.data() ?? {}) as Record<string, unknown>;
    const afterData = (after.data() ?? {}) as Record<string, unknown>;

    const beforeStatus = String(beforeData.statusRaw ?? "")
      .trim()
      .toLowerCase();
    const afterStatus = String(afterData.statusRaw ?? "")
      .trim()
      .toLowerCase();
    if (beforeStatus === afterStatus) return;
    if (afterStatus !== "done") return;

    const creatorUserId = String(afterData.creatorUserId ?? "").trim();
    const assignedUserId = String(afterData.assignedUserId ?? "").trim();
    const updatedByUserId = String(afterData.updatedByUserId ?? "").trim();
    const titleRaw = String(afterData.title ?? "").trim();
    const title = titleRaw || "Aufgabe";

    if (!creatorUserId) return;
    if (creatorUserId === updatedByUserId) return;
    if (creatorUserId === assignedUserId && !updatedByUserId) return;

    const doneByName = await getUserNameOrFallback(
      updatedByUserId || assignedUserId
    );

    console.log(
      "[push][task_completed] taskId=",
      String(event.params.taskId ?? ""),
      "to=",
      creatorUserId,
      "by=",
      updatedByUserId || assignedUserId || "<unknown>"
    );

    const tokenRefs = await getUserTokenRefs(creatorUserId);
    if (tokenRefs.length === 0) {
      console.log("[push][task_completed] no user tokens for", creatorUserId);
      return;
    }

    await sendBadgeCountedMulticast(
      "task_completed",
      tokenRefs,
      {
        title: "Aufgabe erledigt",
        body: doneByName + " hat eine Aufgabe abgeschlossen: " + title,
      },
      {
        type: "task_completed",
        taskId: String(event.params.taskId ?? ""),
        toUserId: creatorUserId,
        fromUserId: updatedByUserId || assignedUserId,
      }
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

/* eslint-disable require-jsdoc */
// ------------------------------------------------------------------
// Scanner sequence / reservation helpers
// ------------------------------------------------------------------

type UploadScanToDriveBody = {
  storagePath: string;
  fileName: string;
  reservationId?: string;
};

const SCANS_DRIVE_UPLOAD_FOLDER_ID = "19n1REUlYfwdzrj3NntMqgzoQ05jg2T9f";
const SCANNER_CASE_FOLDERS_ROOT_ID = "1FVnM3Y_ktIvXMUPuAQTpJ-sMB5yI1gYf";
const SCANNER_FOTOS_SUBFOLDER_NAME = "Fotos";
const SCANNER_META_DOC_PATH = "scannerMeta/current";
const SCANNER_RESERVATIONS_COLLECTION = "scannerReservations";
const SCANNER_SHEET_ID = "10mfm9SVVDiWcxnfK2QuUCj3msaVFBQIQx34NnPlUEo4";
const SCANNER_SHEET_URL =
  `https://docs.google.com/spreadsheets/d/${SCANNER_SHEET_ID}/gviz/tq?tqx=out:json`;

function buildDriveFolderUrl(folderId: string): string {
  const id = String(folderId ?? "").trim();
  if (!id) {
    return "";
  }
  return `https://drive.google.com/drive/folders/${id}`;
}

function getCurrentScannerYear2(now: Date = new Date()): string {
  return String(now.getFullYear() % 100).padStart(2, "0");
}

function stripScannerControlChars(value: string): string {
  return Array.from(value)
    .filter((char) => char.charCodeAt(0) >= 32)
    .join("");
}

function normalizeScannerDisplayName(rawValue: unknown): string {
  return stripScannerControlChars(String(rawValue ?? ""))
    .replace(/\s+/g, " ")
    .trim()
    .replace(/[<>:"\\|?*]/g, "")
    .replace(/\//g, "-");
}

function buildScannerDriveFolderName(
  number: number,
  year2: string,
  scanName: string,
  uploaderShortCode?: string
): string {
  const safeName = normalizeScannerDisplayName(scanName);
  const safeShortCode = normalizeScannerDisplayName(
    uploaderShortCode ?? ""
  ).toUpperCase();
  const shortCodeSuffix = safeShortCode ? ` (${safeShortCode})` : "";
  return `${number}/${year2} Unfallgutachten ${safeName}${shortCodeSuffix}`;
}

function parseGvizResponse(rawText: string): Record<string, unknown> {
  const start = rawText.indexOf("{");
  const end = rawText.lastIndexOf("}");
  if (start === -1 || end === -1) {
    throw new Error("GViz JSON nicht gefunden.");
  }
  return JSON.parse(rawText.slice(start, end + 1)) as Record<string, unknown>;
}

function extractScannerSequenceNumber(rawValue: unknown): number | null {
  const text = String(rawValue ?? "").trim();
  if (!text) return null;

  const match = text.match(/(?:RB|KVA)?\s*(\d{1,6})(?:\s*\/\s*\d{2})?/i);
  if (!match) return null;

  const parsed = Number.parseInt(match[1], 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : null;
}

async function fetchInitialScannerNextNumber(): Promise<number> {
  const response = await fetch(SCANNER_SHEET_URL, {
    method: "GET",
    cache: "no-store",
  });

  if (!response.ok) {
    throw new Error(`Sheet HTTP ${response.status}`);
  }

  const rawText = await response.text();
  const payload = parseGvizResponse(rawText);
  const table = payload.table as {rows?: unknown[]} | undefined;
  const rows = Array.isArray(table?.rows) ? table.rows : [];

  const activeNumbers: number[] = [];

  for (const row of rows) {
    const cells = Array.isArray((row as {c?: unknown[]})?.c) ?
      (row as {c: unknown[]}).c :
      [];
    const rawCase = (cells[0] as {v?: unknown} | undefined)?.v;
    const caseText = String(rawCase ?? "").trim();
    if (!caseText || caseText.toLowerCase() === "eingang") {
      continue;
    }

    const rawStatus = (cells[2] as {v?: unknown} | undefined)?.v;
    const statusText = String(rawStatus ?? "").trim().toLowerCase();
    if (/^versendet\b/i.test(statusText)) {
      continue;
    }

    const number = extractScannerSequenceNumber(caseText);
    if (!number) {
      continue;
    }

    activeNumbers.push(number);
  }

  if (activeNumbers.length === 0) {
    return 1;
  }

  return Math.max(...activeNumbers) + 1;
}

function sanitizeScannerNextNumber(
  rawValue: unknown,
  fallback: number
): number {
  const parsed = Number(rawValue ?? fallback);
  if (!Number.isFinite(parsed) || parsed < 1) {
    return fallback;
  }
  return Math.floor(parsed);
}

async function getScannerSequenceSeed(year2: string): Promise<number> {
  try {
    void year2;
    return await fetchInitialScannerNextNumber();
  } catch (e) {
    console.warn("[scannerSequence] Sheet seed failed", e);
    return 1;
  }
}

async function findNextFreeScannerNumber(
  tx: admin.firestore.Transaction,
  year2: string,
  startNumber: number,
  options?: {
    resetFloorNumber?: number | null;
    resetAt?: unknown;
  }
): Promise<number> {
  let candidate = Math.max(1, Math.floor(startNumber));
  const rawResetFloorNumber = options?.resetFloorNumber;
  const resetFloorNumber =
    typeof rawResetFloorNumber === "number" &&
    Number.isFinite(rawResetFloorNumber) ?
      Math.max(1, Math.floor(rawResetFloorNumber)) :
      null;
  const resetAtMillis = toMillisOrNull(options?.resetAt);

  for (let i = 0; i < 500; i += 1) {
    const reservationId = `${year2}_${candidate}`;
    const reservationRef = admin
      .firestore()
      .collection(SCANNER_RESERVATIONS_COLLECTION)
      .doc(reservationId);
    const reservationSnap = await tx.get(reservationRef);
    if (!reservationSnap.exists) {
      return candidate;
    }

    const reservationData = reservationSnap.data() ?? {};
    const reservationCreatedAtMillis = toMillisOrNull(
      reservationData.createdAt
    );
    const shouldIgnoreStaleReservation =
      resetFloorNumber !== null &&
      resetAtMillis !== null &&
      candidate >= resetFloorNumber &&
      reservationCreatedAtMillis !== null &&
      reservationCreatedAtMillis < resetAtMillis;

    if (shouldIgnoreStaleReservation) {
      return candidate;
    }

    candidate += 1;
  }

  throw new HttpsError(
    "resource-exhausted",
    "Keine freie Scanner-Nummer gefunden."
  );
}

function toMillisOrNull(rawValue: unknown): number | null {
  if (
    typeof rawValue === "object" &&
    rawValue !== null &&
    typeof (rawValue as {toMillis?: unknown}).toMillis === "function"
  ) {
    return Number((rawValue as {toMillis: () => number}).toMillis());
  }
  return null;
}

async function getScannerDriveClient(): Promise<driveV3.Drive> {
  const auth = new google.auth.GoogleAuth({
    scopes: ["https://www.googleapis.com/auth/drive"],
  });
  return google.drive({version: "v3", auth});
}

async function ensureDriveFolderAccessible(
  drive: driveV3.Drive,
  folderId: string,
  errorPrefix: string
): Promise<void> {
  try {
    await drive.files.get({
      fileId: folderId,
      fields: "id,name",
      supportsAllDrives: true,
    });
  } catch (e: unknown) {
    throw new Error(
      errorPrefix +
      " Bitte den Ordner mit dem Service Account als Bearbeiter teilen. " +
      `FolderId=${folderId}`
    );
  }
}

async function createScannerDriveFolder(
  drive: driveV3.Drive,
  folderName: string
): Promise<string> {
  const createResp = await drive.files.create({
    supportsAllDrives: true,
    requestBody: {
      name: folderName,
      mimeType: "application/vnd.google-apps.folder",
      parents: [SCANNER_CASE_FOLDERS_ROOT_ID],
    },
    fields: "id",
  });

  const driveFolderId = String(createResp.data.id ?? "").trim();
  if (!driveFolderId) {
    throw new Error("Drive-Ordner konnte nicht erstellt werden.");
  }

  return driveFolderId;
}

async function createScannerDriveSubfolder(
  drive: driveV3.Drive,
  parentFolderId: string,
  subfolderName: string
): Promise<string> {
  const createResp = await drive.files.create({
    supportsAllDrives: true,
    requestBody: {
      name: subfolderName,
      mimeType: "application/vnd.google-apps.folder",
      parents: [parentFolderId],
    },
    fields: "id",
  });

  const subfolderId = String(createResp.data.id ?? "").trim();
  if (!subfolderId) {
    throw new Error(
      `Drive-Unterordner "${subfolderName}" konnte nicht erstellt werden.`
    );
  }

  return subfolderId;
}

async function ensureScannerFotosSubfolder(
  reservationRef: FirebaseFirestore.DocumentReference,
  parentFolderId: string,
  data: FirebaseFirestore.DocumentData
): Promise<void> {
  const existingFotosFolderId = String(data.fotosFolderId ?? "").trim();
  if (existingFotosFolderId) {
    return;
  }

  const drive = await getScannerDriveClient();
  const fotosFolderId = await createScannerDriveSubfolder(
    drive,
    parentFolderId,
    SCANNER_FOTOS_SUBFOLDER_NAME
  );

  await reservationRef.set({
    fotosFolderId,
    fotosFolderUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});
}

async function ensureScannerReservationDriveFolder(
  reservationId: string
): Promise<{ driveFolderId: string; fotosFolderId: string }> {
  const reservationRef = admin
    .firestore()
    .collection(SCANNER_RESERVATIONS_COLLECTION)
    .doc(reservationId);
  const reservationSnap = await reservationRef.get();

  if (!reservationSnap.exists) {
    throw new Error("Scanner-Reservierung nicht gefunden.");
  }

  const data = reservationSnap.data() ?? {};
  const existingDriveFolderId = String(data.driveFolderId ?? "").trim();
  if (existingDriveFolderId) {
    await ensureScannerFotosSubfolder(
      reservationRef,
      existingDriveFolderId,
      data
    );
    const updatedSnap = await reservationRef.get();
    const updatedData = updatedSnap.data() ?? {};
    const fotosFolderId = String(updatedData.fotosFolderId ?? "").trim();
    if (!fotosFolderId) {
      throw new Error("Fotos-Ordner konnte nicht erstellt werden.");
    }
    return {
      driveFolderId: existingDriveFolderId,
      fotosFolderId,
    };
  }

  const driveFolderName = String(data.driveFolderName ?? "").trim();
  if (!driveFolderName) {
    throw new Error("Drive-Ordnername fehlt in der Reservierung.");
  }

  const drive = await getScannerDriveClient();
  await ensureDriveFolderAccessible(
    drive,
    SCANNER_CASE_FOLDERS_ROOT_ID,
    "Gutachten-Ordner-Root nicht gefunden/kein Zugriff."
  );
  const createdDriveFolderId = await createScannerDriveFolder(
    drive,
    driveFolderName
  );
  const fotosFolderId = await createScannerDriveSubfolder(
    drive,
    createdDriveFolderId,
    SCANNER_FOTOS_SUBFOLDER_NAME
  );

  await reservationRef.set({
    driveFolderId: createdDriveFolderId,
    fotosFolderId,
    driveFolderReady: true,
    driveFolderUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    fotosFolderUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    status: "reserved",
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});

  return {
    driveFolderId: createdDriveFolderId,
    fotosFolderId,
  };
}

async function rollbackScannerReservation(
  reservationId: string,
  year2: string,
  number: number
): Promise<void> {
  const db = admin.firestore();
  const metaRef = db.doc(SCANNER_META_DOC_PATH);
  const reservationRef = db
    .collection(SCANNER_RESERVATIONS_COLLECTION)
    .doc(reservationId);

  await db.runTransaction(async (tx) => {
    const metaSnap = await tx.get(metaRef);
    const reservationSnap = await tx.get(reservationRef);

    if (reservationSnap.exists) {
      tx.delete(reservationRef);
    }

    const metaData = metaSnap.data() ?? {};
    const storedYear2 = String(metaData.year2 ?? year2).trim() || year2;
    const currentNextNumber = sanitizeScannerNextNumber(
      metaData.nextNumber,
      number + 1
    );

    if (storedYear2 === year2 && currentNextNumber === number + 1) {
      tx.set(metaRef, {
        year2,
        nextNumber: number,
        lastReservedNumber: admin.firestore.FieldValue.delete(),
        lastReservationId: admin.firestore.FieldValue.delete(),
        lastReservedByUid: admin.firestore.FieldValue.delete(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
      return;
    }

    tx.set(metaRef, {
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
  });
}

async function deleteScannerDriveFolder(
  drive: driveV3.Drive,
  folderId: string
): Promise<void> {
  const id = String(folderId ?? "").trim();
  if (!id) {
    return;
  }

  let deleteError: unknown = null;
  try {
    await drive.files.delete({
      fileId: id,
      supportsAllDrives: true,
    });
    return;
  } catch (e: unknown) {
    deleteError = e;
    console.warn("[cancelScannerReservation] drive delete failed", e);
  }

  try {
    await drive.files.update({
      fileId: id,
      supportsAllDrives: true,
      requestBody: {
        trashed: true,
      },
    });
    return;
  } catch (trashError: unknown) {
    const deleteMsg = deleteError instanceof Error ?
      deleteError.message :
      String(deleteError ?? "unbekannt");
    const trashMsg = trashError instanceof Error ?
      trashError.message :
      String(trashError);
    throw new Error(
      "Drive-Ordner konnte nicht gelöscht werden. " +
      `delete=${deleteMsg}; trash=${trashMsg}`
    );
  }
}

async function cancelScannerReservationForCaller(
  callerUid: string,
  reservationId: string
): Promise<void> {
  const trimmedReservationId = String(reservationId ?? "").trim();
  if (!trimmedReservationId) {
    throw new Error("reservationId required");
  }

  const reservationRef = admin
    .firestore()
    .collection(SCANNER_RESERVATIONS_COLLECTION)
    .doc(trimmedReservationId);
  const reservationSnap = await reservationRef.get();

  if (!reservationSnap.exists) {
    throw new Error("Reservierung nicht gefunden.");
  }

  const data = reservationSnap.data() ?? {};
  const reservedByUid = String(data.reservedByUid ?? "").trim();
  if (reservedByUid !== callerUid) {
    throw new Error("Keine Berechtigung für diese Reservierung.");
  }

  const status = String(data.status ?? "").trim().toLowerCase();
  const uploadedFileId = String(data.uploadedFileId ?? "").trim();
  if (status === "uploaded" || uploadedFileId) {
    throw new Error(
      "Hochgeladene Reservierungen können nicht aufgehoben werden."
    );
  }

  const number = Number(data.number);
  const year2 = String(data.year2 ?? "").trim();
  if (!Number.isFinite(number) || number <= 0 || !year2) {
    throw new Error("Ungültige Reservierungsdaten.");
  }

  const driveFolderId = String(data.driveFolderId ?? "").trim();
  if (driveFolderId) {
    const drive = await getScannerDriveClient();
    await deleteScannerDriveFolder(drive, driveFolderId);
  }

  await rollbackScannerReservation(trimmedReservationId, year2, number);
}

async function readScannerSequencePreview(): Promise<{
  year2: string;
  nextNumber: number;
}> {
  const year2 = getCurrentScannerYear2();
  const seededNextNumber = await getScannerSequenceSeed(year2);
  const db = admin.firestore();
  const metaRef = db.doc(SCANNER_META_DOC_PATH);

  return db.runTransaction(async (tx) => {
    const metaSnap = await tx.get(metaRef);

    let nextNumber = seededNextNumber;
    if (metaSnap.exists) {
      const metaData = metaSnap.data() ?? {};
      const storedYear2 =
        String(metaData.year2 ?? year2).trim() || year2;
      if (storedYear2 === year2) {
        const storedNextNumber = sanitizeScannerNextNumber(
          metaData.nextNumber,
          seededNextNumber
        );
        nextNumber = Math.max(seededNextNumber, storedNextNumber);
      }
    }

    tx.set(metaRef, {
      year2,
      nextNumber,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    return {
      year2,
      nextNumber,
    };
  });
}

async function reserveScannerNumberForCaller(
  callerUid: string,
  callerEmail: string,
  scanName: string
): Promise<{
  reservationId: string;
  number: number;
  year2: string;
  driveFolderName: string;
  driveFolderId: string;
  driveFolderUrl: string;
  fotosFolderId: string;
  fotosFolderUrl: string;
}> {
  const callerUserSnap = await admin.firestore()
    .collection("users")
    .doc(callerUid)
    .get();
  const callerUserData = callerUserSnap.data() ?? {};
  const callerShortCode = String(
    callerUserData.shortCode ?? ""
  ).trim();

  const year2 = getCurrentScannerYear2();
  const seededNextNumber = await getScannerSequenceSeed(year2);
  const db = admin.firestore();
  const metaRef = db.doc(SCANNER_META_DOC_PATH);

  const result = await db.runTransaction(async (tx) => {
    const metaSnap = await tx.get(metaRef);

    let nextNumber = seededNextNumber;
    let resetFloorNumber: number | null = null;
    let resetAt: unknown = null;
    if (metaSnap.exists) {
      const metaData = metaSnap.data() ?? {};
      const storedYear2 =
        String(metaData.year2 ?? year2).trim() || year2;
      if (storedYear2 === year2) {
        const storedNextNumber = sanitizeScannerNextNumber(
          metaData.nextNumber,
          seededNextNumber
        );
        nextNumber = Math.max(seededNextNumber, storedNextNumber);
        if (metaData.resetFloorNumber != null) {
          resetFloorNumber = sanitizeScannerNextNumber(
            metaData.resetFloorNumber,
            nextNumber
          );
        }
        resetAt = metaData.resetAt ?? null;
      }
    }

    const freeNumber = await findNextFreeScannerNumber(
      tx,
      year2,
      nextNumber,
      {
        resetFloorNumber,
        resetAt,
      }
    );
    const reservationId = `${year2}_${freeNumber}`;
    const driveFolderName = buildScannerDriveFolderName(
      freeNumber,
      year2,
      scanName,
      callerShortCode
    );
    const reservationRef = db
      .collection(SCANNER_RESERVATIONS_COLLECTION)
      .doc(reservationId);

    tx.set(reservationRef, {
      number: freeNumber,
      year2,
      scanName,
      reservedByUid: callerUid,
      reservedByEmail: callerEmail,
      driveFolderName,
      driveFolderId: null,
      driveFolderReady: false,
      status: "creating_folder",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    tx.set(metaRef, {
      year2,
      nextNumber: freeNumber + 1,
      lastReservedNumber: freeNumber,
      lastReservationId: reservationId,
      lastReservedByUid: callerUid,
      resetFloorNumber: admin.firestore.FieldValue.delete(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    return {
      reservationId,
      number: freeNumber,
      year2,
      driveFolderName,
    };
  });

  try {
    const {driveFolderId, fotosFolderId} =
      await ensureScannerReservationDriveFolder(
        result.reservationId
      );
    return {
      ...result,
      driveFolderId,
      driveFolderUrl: buildDriveFolderUrl(driveFolderId),
      fotosFolderId,
      fotosFolderUrl: buildDriveFolderUrl(fotosFolderId),
    };
  } catch (e: unknown) {
    console.error("[reserveScannerNumber] drive folder create failed", e);

    try {
      await rollbackScannerReservation(
        result.reservationId,
        result.year2,
        result.number
      );
    } catch (rollbackError: unknown) {
      console.error(
        "[reserveScannerNumber] rollback failed",
        rollbackError
      );
    }

    throw new HttpsError(
      "internal",
      "Drive-Ordner konnte nicht erstellt werden. " +
      "Nummer wurde nicht reserviert."
    );
  }
}

export const getScannerSequencePreview = onCall(async (request) => {
  const callerUid = request.auth?.uid;
  if (!callerUid) {
    throw new HttpsError("unauthenticated", "Not signed in.");
  }

  const result = await readScannerSequencePreview();

  return {
    ok: true,
    ...result,
  };
});

export const getScannerSequencePreviewHttp = onRequest(async (req, res) => {
  try {
    res.set("Access-Control-Allow-Origin", "*");
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

    try {
      await admin.auth().verifyIdToken(idToken);
    } catch {
      res.status(401).json({ok: false, error: "Unauthorized"});
      return;
    }

    const result = await readScannerSequencePreview();
    res.status(200).json({ok: true, ...result});
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error("[getScannerSequencePreviewHttp] FAILED", e);
    res.status(500).json({ok: false, error: msg});
  }
});

async function performAdminResetScannerSequenceFromSheet(
  callerUid: string
): Promise<{
  year2: string;
  nextNumber: number;
  ignoredReservations: boolean;
}> {
  const year2 = getCurrentScannerYear2();
  const nextNumber = await getScannerSequenceSeed(year2);

  await admin.firestore()
    .doc(SCANNER_META_DOC_PATH)
    .set({
      year2,
      nextNumber,
      resetFloorNumber: nextNumber,
      resetSource: "google_sheet",
      resetByUid: callerUid,
      resetAt: admin.firestore.FieldValue.serverTimestamp(),
      lastReservedNumber: admin.firestore.FieldValue.delete(),
      lastReservationId: admin.firestore.FieldValue.delete(),
      lastReservedByUid: admin.firestore.FieldValue.delete(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

  return {
    year2,
    nextNumber,
    ignoredReservations: false,
  };
}

export const adminResetScannerSequenceFromSheet = onCall(async (request) => {
  const callerUid = request.auth?.uid;
  if (!callerUid) {
    throw new HttpsError("unauthenticated", "Not signed in.");
  }

  await ensureCallerIsAdmin(callerUid);
  const result = await performAdminResetScannerSequenceFromSheet(callerUid);
  return {
    ok: true,
    ...result,
  };
});

export const adminResetScannerSequenceFromSheetHttp = onRequest(
  async (req, res) => {
    try {
      res.set("Access-Control-Allow-Origin", "*");
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

      await ensureCallerIsAdmin(callerUid);
      const result = await performAdminResetScannerSequenceFromSheet(
        callerUid
      );
      res.status(200).json({ok: true, ...result});
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : String(e);
      console.error("[adminResetScannerSequenceFromSheetHttp] FAILED", e);
      res.status(500).json({ok: false, error: msg});
    }
  }
);

export const reserveScannerNumber = onCall(
  {
    region: "us-central1",
    serviceAccount: "svs-app-864ed@appspot.gserviceaccount.com",
  },
  async (request) => {
    const callerUid = request.auth?.uid;
    if (!callerUid) {
      throw new HttpsError("unauthenticated", "Not signed in.");
    }

    const scanName = normalizeScannerDisplayName(request.data?.scanName);
    if (!scanName) {
      throw new HttpsError("invalid-argument", "scanName required.");
    }

    const authEmail = normalizeEmail(request.auth?.token.email ?? "");
    let callerEmail = authEmail;
    if (!callerEmail) {
      const callerRecord = await admin.auth().getUser(callerUid);
      callerEmail = normalizeEmail(callerRecord.email ?? "");
    }

    const result = await reserveScannerNumberForCaller(
      callerUid,
      callerEmail,
      scanName
    );

    return {
      ok: true,
      ...result,
      driveFolderReady: true,
    };
  }
);

export const reserveScannerNumberHttp = onRequest(
  {
    region: "us-central1",
    serviceAccount: "svs-app-864ed@appspot.gserviceaccount.com",
  },
  async (req, res) => {
    try {
      res.set("Access-Control-Allow-Origin", "*");
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
      let callerEmail = "";
      try {
        const decoded = await admin.auth().verifyIdToken(idToken);
        callerUid = decoded.uid;
        callerEmail = normalizeEmail(decoded.email ?? "");
      } catch {
        res.status(401).json({ok: false, error: "Unauthorized"});
        return;
      }

      const body = (req.body ?? {}) as Partial<{scanName: string}>;
      const scanName = normalizeScannerDisplayName(body.scanName);
      if (!scanName) {
        res.status(400).json({ok: false, error: "scanName required"});
        return;
      }

      if (!callerEmail) {
        const callerRecord = await admin.auth().getUser(callerUid);
        callerEmail = normalizeEmail(callerRecord.email ?? "");
      }

      const result = await reserveScannerNumberForCaller(
        callerUid,
        callerEmail,
        scanName
      );

      res.status(200).json({
        ok: true,
        ...result,
        driveFolderReady: true,
      });
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : String(e);
      console.error("[reserveScannerNumberHttp] FAILED", e);
      res.status(500).json({ok: false, error: msg});
    }
  }
);

export const cancelScannerNumber = onCall(
  {
    region: "us-central1",
    serviceAccount: "svs-app-864ed@appspot.gserviceaccount.com",
  },
  async (request) => {
    const callerUid = request.auth?.uid;
    if (!callerUid) {
      throw new HttpsError("unauthenticated", "Not signed in.");
    }

    const reservationId = String(request.data?.reservationId ?? "").trim();
    if (!reservationId) {
      throw new HttpsError("invalid-argument", "reservationId required.");
    }

    await cancelScannerReservationForCaller(callerUid, reservationId);
    return {ok: true};
  }
);

export const cancelScannerNumberHttp = onRequest(
  {
    region: "us-central1",
    serviceAccount: "svs-app-864ed@appspot.gserviceaccount.com",
  },
  async (req, res) => {
    try {
      res.set("Access-Control-Allow-Origin", "*");
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

      const body = (req.body ?? {}) as Partial<{reservationId: string}>;
      const reservationId = String(body.reservationId ?? "").trim();
      if (!reservationId) {
        res.status(400).json({ok: false, error: "reservationId required"});
        return;
      }

      await cancelScannerReservationForCaller(callerUid, reservationId);
      res.status(200).json({ok: true});
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : String(e);
      console.error("[cancelScannerNumberHttp] FAILED", e);
      res.status(500).json({ok: false, error: msg});
    }
  }
);

// ------------------------------------------------------------------
// Scanner -> Upload Scan (PDF) to Google Drive
// POST /uploadScanToDrive
// Auth: Bearer <Firebase ID Token>
// Body: { storagePath: string, fileName: string, reservationId?: string }
// Returns:
// { ok, driveFileId, driveFolderId?, driveFolderUrl?,
//   fotosFolderId?, fotosFolderUrl? }
// ------------------------------------------------------------------

export const uploadScanToDrive = onRequest(
  {
    region: "us-central1",
    serviceAccount: "svs-app-864ed@appspot.gserviceaccount.com",
  },
  async (req, res) => {
    try {
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
      const reservationId = String(body.reservationId ?? "").trim();
      const fileName = String(body.fileName ?? "").trim();

      if (!storagePath) {
        res.status(400).json({ok: false, error: "storagePath required"});
        return;
      }
      if (!fileName) {
        res.status(400).json({ok: false, error: "fileName required"});
        return;
      }
      if (!storagePath.startsWith(`scans/${callerUid}/`)) {
        res.status(403).json({ok: false, error: "Forbidden"});
        return;
      }

      const bucket = admin.storage().bucket();
      const file = bucket.file(storagePath);

      const [exists] = await file.exists();
      if (!exists) {
        res.status(404).json({ok: false, error: "file not found"});
        return;
      }

      const [buf] = await file.download();

      const targetFolderId = SCANS_DRIVE_UPLOAD_FOLDER_ID;
      let reservationRef: admin.firestore.DocumentReference | null = null;
      let reservationDriveFolderId = "";
      let reservationFotosFolderId = "";

      if (reservationId) {
        reservationRef = admin.firestore()
          .collection(SCANNER_RESERVATIONS_COLLECTION)
          .doc(reservationId);
        const reservationSnap = await reservationRef.get();

        if (!reservationSnap.exists) {
          res.status(404).json({ok: false, error: "Reservation not found"});
          return;
        }

        const reservationData = reservationSnap.data() ?? {};
        const reservedByUid = String(
          reservationData.reservedByUid ?? ""
        ).trim();
        if (reservedByUid !== callerUid) {
          res.status(403).json({ok: false, error: "Forbidden"});
          return;
        }

        const folderIds = await ensureScannerReservationDriveFolder(
          reservationId
        );
        reservationDriveFolderId = folderIds.driveFolderId;
        reservationFotosFolderId = folderIds.fotosFolderId;
      }

      const drive = await getScannerDriveClient();
      try {
        await ensureDriveFolderAccessible(
          drive,
          targetFolderId,
          "PDF-Upload-Ordner nicht gefunden/kein Zugriff."
        );
      } catch (e: unknown) {
        const msg = e instanceof Error ? e.message : String(e);
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
          parents: [targetFolderId],
        },
        media,
        fields: "id",
      });

      const driveFileId = String(createResp.data.id ?? "").trim();
      if (!driveFileId) {
        res.status(500).json({ok: false, error: "Drive upload failed"});
        return;
      }

      if (reservationRef) {
        await reservationRef.set({
          uploadFolderId: targetFolderId,
          driveFolderReady: true,
          status: "uploaded",
          uploadedFileId: driveFileId,
          uploadedFileName: fileName,
          uploadedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});
      }

      try {
        await file.delete({ignoreNotFound: true});
      } catch (e) {
        console.warn("[uploadScanToDrive] temp storage cleanup failed", e);
      }

      res.status(200).json({
        ok: true,
        driveFileId,
        driveFolderId: reservationDriveFolderId,
        driveFolderUrl: buildDriveFolderUrl(reservationDriveFolderId),
        fotosFolderId: reservationFotosFolderId,
        fotosFolderUrl: buildDriveFolderUrl(reservationFotosFolderId),
      });
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : String(e);
      console.error("[uploadScanToDrive] FAILED", e);
      res.status(500).json({ok: false, error: msg});
    }
  }
);

/* eslint-enable require-jsdoc */

// ------------------------------------------------------------------
// Provision: Token prüfen (für Firebase Hosting Webformular)
// GET /getProvisionLink?token=<uuid>
// Returns: { ok, status, expiresAt?, usedAt?, amount?, gutachtenNumber? }
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

    const linkFields = {
      amount:
        typeof data.amount === "number" && Number.isFinite(data.amount) ?
          data.amount :
          null,
      gutachtenNumber: String(data.gutachtenNumber ?? "").trim() || null,
    };

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
        ...linkFields,
      });
      return;
    }

    if (status === "used" || usedAtTs) {
      res.status(200).json({
        ok: true,
        status: "used",
        expiresAt: expiresAtTs ? expiresAtTs.toDate().toISOString() : null,
        usedAt: usedAtTs ? usedAtTs.toDate().toISOString() : null,
        ...linkFields,
      });
      return;
    }

    res.status(200).json({
      ok: true,
      status: "valid",
      expiresAt: expiresAtTs ? expiresAtTs.toDate().toISOString() : null,
      ...linkFields,
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
      .text("Bestätigung über die Vereinbarung einer Vermittlungsprämie");
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
    doc.text(`Prämienbetrag: ${formatEurAmount(data.amount)}`);

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

      const tokenGutachtenNumber =
        String((tokenData as Record<string, unknown>).gutachtenNumber ?? "")
          .trim() || null;

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
        gutachtenNumber: tokenGutachtenNumber,

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
  gutachtenNumber?: string;
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

    const gutachtenNumber =
      String(body.gutachtenNumber ?? "").trim() || null;

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
        gutachtenNumber,
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
        const allAdminTokenRefs = await getProvisionPushAdminTokenRefs();
        const creatorUid = String(data.createdByUid ?? "").trim();
        const tokenRefs = filterOutUserTokenRefs(
          allAdminTokenRefs,
          creatorUid
        );
        if (tokenRefs.length === 0) {
          console.log("[push][commission_new] no provision-push admin tokens");
        } else {
          const name = String(data.recommenderName ?? "").trim();
          const amountTxt = formatEurAmount(data.amount);

          const bodyParts = [
            name || "Neue Anfrage",
            amountTxt !== "—" ? amountTxt : "",
          ].filter(Boolean);

          await sendBadgeCountedMulticast(
            "commission_new",
            tokenRefs,
            {
              title: "Prämie auszuzahlen",
              body: bodyParts.join(" · "),
            },
            {
              type: "commission_new",
              commissionId,
            }
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
      `Vermittlungsprämie übermittelt – ${safeStr(data.recommenderName)}`;

    const payoutMethod = String(data.payoutMethod ?? "").trim();
    let payoutLine = "";
    if (payoutMethod === "paypal") {
      payoutLine = `PayPal: ${safeStr(data.payoutPaypal)}`;
    } else {
      payoutLine = `IBAN: ${safeStr(data.payoutIban)}`;
    }

    const bodyText =
      "Eine Vermittlungsprämie wurde über das Webformular übermittelt.\n\n" +
      `Vermittler: ${safeStr(data.recommenderName)}\n` +
      `Adresse: ${safeStr(data.recommenderStreet)}, ` +
      `${safeStr(data.recommenderZip)} ` +
      `${safeStr(data.recommenderCity)}\n` +
      `Auszahlung: ${payoutLine}\n` +
      `Betrag: ${formatEurAmount(data.amount)}\n` +
      `Gutachten-Nr.: ${safeStr(data.gutachtenNumber)}\n` +
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
            filename: `Praemie_${commissionId}.pdf`,
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
export {
  createDocumentSigningLink,
  deleteDocumentSigningLink,
  getDocumentSigningDownload,
  getDocumentSigningLink,
  listDocumentSigningLinks,
  submitDocumentSigningForm,
  updateDocumentSigningSignedPdf,
} from "./documentSigning";

// Ensure all string literals use double quotes
