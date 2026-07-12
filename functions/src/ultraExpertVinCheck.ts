export type UltraExpertPriorDamageMatch = {
  gutachtenNumber: string;
  dossierId?: string;
  dossierUrl?: string;
};

export type UltraExpertPriorDamageResult = {
  ok: boolean;
  vin: string;
  matchCount: number;
  gutachtenNumbers: string[];
  matches: UltraExpertPriorDamageMatch[];
  error?: string;
};

type BotResponse = {
  ok?: boolean;
  error?: string;
  vin?: string;
  matchCount?: number;
  gutachtenNumbers?: string[];
  matches?: UltraExpertPriorDamageMatch[];
};

/**
 * Normalizes a vehicle identification number (FIN/VIN).
 *
 * @param {string} raw Raw FIN input.
 * @return {string} Normalized FIN.
 */
export function normalizeVin(raw: string): string {
  return String(raw ?? "")
    .toUpperCase()
    .replace(/[\s-]+/g, "")
    .trim();
}

/**
 * Calls the UltraExpert bot webhook to search prior dossiers by FIN.
 *
 * @param {object} config Bot URL and shared secret.
 * @param {string} vin Vehicle identification number.
 * @return {Promise<UltraExpertPriorDamageResult>} Search result.
 */
export async function checkUltraExpertPriorDamageByVin(
  config: {botUrl: string; botSecret: string},
  vin: string
): Promise<UltraExpertPriorDamageResult> {
  const normalizedVin = normalizeVin(vin);
  if (normalizedVin.length < 11) {
    return {
      ok: false,
      vin: normalizedVin,
      matchCount: 0,
      gutachtenNumbers: [],
      matches: [],
      error: "Invalid VIN",
    };
  }

  const botUrl = String(config.botUrl || "").trim();
  const botSecret = String(config.botSecret || "").trim();
  if (!botUrl || !botSecret) {
    return {
      ok: false,
      vin: normalizedVin,
      matchCount: 0,
      gutachtenNumbers: [],
      matches: [],
      error: "UltraExpert bot is not configured",
    };
  }

  const response = await fetch(botUrl, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-webhook-secret": botSecret,
    },
    body: JSON.stringify({vin: normalizedVin}),
    signal: AbortSignal.timeout(120_000),
  });

  const rawText = await response.text();
  let payload: BotResponse = {};
  try {
    payload = rawText ? JSON.parse(rawText) as BotResponse : {};
  } catch {
    return {
      ok: false,
      vin: normalizedVin,
      matchCount: 0,
      gutachtenNumbers: [],
      matches: [],
      error: `Unexpected bot response (HTTP ${response.status})`,
    };
  }

  if (!response.ok || payload.ok === false) {
    return {
      ok: false,
      vin: normalizedVin,
      matchCount: 0,
      gutachtenNumbers: [],
      matches: [],
      error: payload.error || `UltraExpert bot error (HTTP ${response.status})`,
    };
  }

  const matches = Array.isArray(payload.matches) ? payload.matches : [];
  const gutachtenNumbers = Array.isArray(payload.gutachtenNumbers) ?
    payload.gutachtenNumbers :
    matches.map((match) => match.gutachtenNumber).filter(Boolean);

  return {
    ok: true,
    vin: String(payload.vin || normalizedVin),
    matchCount: Number(payload.matchCount ?? matches.length),
    gutachtenNumbers,
    matches,
  };
}
