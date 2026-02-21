/**
 * Normalizes a boolean user preference value with a default fallback.
 *
 * @param {unknown} raw Raw value from Firestore.
 * @param {boolean} defaultEnabled Fallback when value is missing/invalid.
 * @return {boolean} Final enabled state.
 */
export function isBooleanPreferenceEnabled(
  raw: unknown,
  defaultEnabled: boolean
): boolean {
  return typeof raw === "boolean" ? raw : defaultEnabled;
}

/**
 * Filters token refs by owner preference map.
 *
 * @template T
 * @param {T[]} tokenRefs Token refs containing ownerUserId.
 * @param {Map<string, boolean>} enabledByUid Resolved preference map per uid.
 * @param {boolean} defaultEnabled Fallback when uid is missing in map.
 * @return {T[]} Filtered refs.
 */
export function filterTokenRefsByPreference<T extends {ownerUserId: string}>(
  tokenRefs: T[],
  enabledByUid: Map<string, boolean>,
  defaultEnabled: boolean
): T[] {
  return tokenRefs.filter((tr) => {
    const uid = String(tr.ownerUserId ?? "").trim();
    if (!uid) return false;
    return enabledByUid.get(uid) ?? defaultEnabled;
  });
}

