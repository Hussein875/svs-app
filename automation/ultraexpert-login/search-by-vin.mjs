import {
  closeSession,
  ensureLoggedIn,
  handleRunError,
  normalizeVin,
  openSession
} from "./ux-common.mjs";
import { searchDossiersByVin } from "./ux-vin-search.mjs";

const vin = process.argv[2] || process.env.UX_SEARCH_VIN || "";

async function main() {
  if (!vin.trim()) {
    console.error("Bitte FIN angeben: npm run search:vin -- WVWZZZCD3PW104182");
    process.exitCode = 1;
    return;
  }

  const session = await openSession();

  try {
    await ensureLoggedIn(session.page);
    const matches = await searchDossiersByVin(session.page, vin);
    const normalizedVin = normalizeVin(vin);

    console.log(
      JSON.stringify(
        {
          ok: true,
          vin: normalizedVin,
          matchCount: matches.length,
          gutachtenNumbers: matches.map(match => match.gutachtenNumber),
          matches
        },
        null,
        2
      )
    );

    await closeSession(session);
  } catch (error) {
    await handleRunError(error, session, "search-vin-error");
  }
}

await main();
