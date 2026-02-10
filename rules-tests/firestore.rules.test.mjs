import {readFileSync} from "node:fs";
import {dirname, resolve} from "node:path";
import {fileURLToPath} from "node:url";
import test from "node:test";

import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from "@firebase/rules-unit-testing";
import {
  Timestamp,
  deleteDoc,
  doc,
  getDoc,
  setDoc,
  updateDoc,
} from "firebase/firestore";

const __dirname = dirname(fileURLToPath(import.meta.url));
const RULES_PATH = resolve(__dirname, "./firestore.rules");
const rules = readFileSync(RULES_PATH, "utf8");

let testEnv;

function authedDb(uid, email, claims = {}) {
  return testEnv.authenticatedContext(uid, {email, ...claims}).firestore();
}

async function seedDoc(path, data) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, path), data);
  });
}

test.before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: `demo-svs-rules-${Date.now()}`,
    firestore: {rules},
  });
});

test.after(async () => {
  await testEnv.cleanup();
});

test.afterEach(async () => {
  await testEnv.clearFirestore();
});

test("users: eigener Nutzer darf nur Farbe updaten", async () => {
  await seedDoc("users/u1", {
    name: "User One",
    roleRaw: "employee",
    colorName: "blue",
    annualLeaveDays: 30,
    email: "u1@example.com",
    createdAt: Timestamp.now(),
    updatedAt: Timestamp.now(),
    fcmTokens: [],
  });

  const db = authedDb("u1", "u1@example.com");
  const myUserRef = doc(db, "users/u1");

  await assertSucceeds(updateDoc(myUserRef, {
    colorName: "red",
    updatedAt: Timestamp.now(),
  }));

  await assertFails(updateDoc(myUserRef, {
    roleRaw: "admin",
    updatedAt: Timestamp.now(),
  }));
});

test("users: Admin darf fremden Nutzer updaten", async () => {
  await seedDoc("users/u1", {
    name: "User One",
    roleRaw: "employee",
    colorName: "blue",
    annualLeaveDays: 30,
    email: "u1@example.com",
    createdAt: Timestamp.now(),
    updatedAt: Timestamp.now(),
    fcmTokens: [],
  });

  const adminDb = authedDb("admin1", "admin@example.com", {role: "admin"});
  await assertSucceeds(updateDoc(doc(adminDb, "users/u1"), {
    roleRaw: "expert",
    updatedAt: Timestamp.now(),
  }));
});

test("tasks: creator kann erstellen, falscher creator wird geblockt", async () => {
  const creatorDb = authedDb("u1", "u1@example.com");

  await assertSucceeds(setDoc(doc(creatorDb, "tasks/t1"), {
    title: "Task 1",
    details: "Details",
    statusRaw: "open",
    assignedUserId: "u2",
    creatorUserId: "u1",
    createdAt: Timestamp.now(),
  }));

  await assertFails(setDoc(doc(creatorDb, "tasks/t2"), {
    title: "Task 2",
    details: "Details",
    statusRaw: "open",
    assignedUserId: "u2",
    creatorUserId: "u2",
    createdAt: Timestamp.now(),
  }));
});

test("tasks: zugewiesener Nutzer darf bearbeiten und neu zuweisen", async () => {
  await seedDoc("tasks/t1", {
    title: "Task 1",
    details: "Details",
    statusRaw: "open",
    assignedUserId: "u2",
    creatorUserId: "u1",
    createdAt: Timestamp.now(),
  });

  const assignedDb = authedDb("u2", "u2@example.com");
  await assertSucceeds(updateDoc(doc(assignedDb, "tasks/t1"), {
    statusRaw: "done",
    assignedUserId: "u3",
    updatedAt: Timestamp.now(),
  }));
});

test("tasks: nur creator darf löschen", async () => {
  await seedDoc("tasks/t1", {
    title: "Task 1",
    details: "Details",
    statusRaw: "open",
    assignedUserId: "u2",
    creatorUserId: "u1",
    createdAt: Timestamp.now(),
  });

  const assignedDb = authedDb("u2", "u2@example.com");
  const creatorDb = authedDb("u1", "u1@example.com");

  await assertFails(deleteDoc(doc(assignedDb, "tasks/t1")));
  await assertSucceeds(deleteDoc(doc(creatorDb, "tasks/t1")));
});

test("meetingTopics: nicht-Ersteller darf nur Status-Update", async () => {
  await seedDoc("meetingTopics/m1", {
    title: "Punkt 1",
    statusRaw: "open",
    createdAt: Timestamp.now(),
    createdByUserId: "u1",
  });

  const user2Db = authedDb("u2", "u2@example.com");
  const topicRef = doc(user2Db, "meetingTopics/m1");

  await assertSucceeds(updateDoc(topicRef, {
    statusRaw: "done",
    updatedAt: Timestamp.now(),
    updatedByUserId: "u2",
  }));

  await assertFails(updateDoc(topicRef, {
    title: "Unzulässig geändert",
  }));
});

test("meetingMeta: nur Admin darf schreiben", async () => {
  const userDb = authedDb("u1", "u1@example.com");
  const adminDb = authedDb("admin1", "admin@example.com", {role: "admin"});

  await assertFails(setDoc(doc(userDb, "meetingMeta/schedule"), {
    nextMeetingAt: Timestamp.now(),
    updatedAt: Timestamp.now(),
  }));

  await assertSucceeds(setDoc(doc(adminDb, "meetingMeta/schedule"), {
    nextMeetingAt: Timestamp.now(),
    updatedAt: Timestamp.now(),
  }));
});

test("meetingArchives: lesen erlaubt, clientseitiges Löschen geblockt", async () => {
  await seedDoc("meetingArchives/a1", {
    meetingDate: Timestamp.now(),
    archivedAt: Timestamp.now(),
    archivedByUserId: "admin1",
    topics: [],
  });

  const userDb = authedDb("u1", "u1@example.com");
  const adminDb = authedDb("admin1", "admin@example.com", {role: "admin"});
  const archiveRefUser = doc(userDb, "meetingArchives/a1");
  const archiveRefAdmin = doc(adminDb, "meetingArchives/a1");

  await assertSucceeds(getDoc(archiveRefUser));
  await assertFails(deleteDoc(archiveRefAdmin));
});
