const test = require("node:test");
const assert = require("node:assert/strict");
const {
  isBooleanPreferenceEnabled,
  filterTokenRefsByPreference,
} = require("../lib/pushPreferences.js");

test("isBooleanPreferenceEnabled uses fallback for missing values", () => {
  assert.equal(isBooleanPreferenceEnabled(undefined, true), true);
  assert.equal(isBooleanPreferenceEnabled(undefined, false), false);
  assert.equal(isBooleanPreferenceEnabled("true", true), true);
  assert.equal(isBooleanPreferenceEnabled(1, false), false);
});

test("isBooleanPreferenceEnabled keeps explicit booleans", () => {
  assert.equal(isBooleanPreferenceEnabled(true, false), true);
  assert.equal(isBooleanPreferenceEnabled(false, true), false);
});

test("filterTokenRefsByPreference honors per-user flag", () => {
  const refs = [
    {ownerUserId: "u1", token: "t1"},
    {ownerUserId: "u2", token: "t2"},
    {ownerUserId: "u3", token: "t3"},
  ];
  const enabledByUid = new Map([
    ["u1", true],
    ["u2", false],
  ]);

  const out = filterTokenRefsByPreference(refs, enabledByUid, true);
  assert.deepEqual(out.map((r) => r.ownerUserId), ["u1", "u3"]);
});

test("meeting schedule default stays enabled when field is absent", () => {
  const refs = [
    {ownerUserId: "u1", token: "t1"},
    {ownerUserId: "u2", token: "t2"},
  ];
  const enabledByUid = new Map([
    ["u1", false],
  ]);

  const out = filterTokenRefsByPreference(refs, enabledByUid, true);
  assert.deepEqual(out.map((r) => r.ownerUserId), ["u2"]);
});

test("invalid empty owner ids are ignored", () => {
  const refs = [
    {ownerUserId: "", token: "t1"},
    {ownerUserId: "   ", token: "t2"},
    {ownerUserId: "u1", token: "t3"},
  ];
  const enabledByUid = new Map([["u1", true]]);

  const out = filterTokenRefsByPreference(refs, enabledByUid, false);
  assert.deepEqual(out.map((r) => r.ownerUserId), ["u1"]);
});

