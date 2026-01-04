import * as admin from "firebase-admin";
import {onCall, HttpsError} from "firebase-functions/v2/https";

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
