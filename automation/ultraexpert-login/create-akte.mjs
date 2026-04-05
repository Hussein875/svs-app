import {
  closeSession,
  ensureLoggedIn,
  handleRunError,
  openSession
} from "./ux-common.mjs";
import { createAkte } from "./ux-actions.mjs";

async function main() {
  const session = await openSession();

  try {
    await ensureLoggedIn(session.page);
    const dossier = await createAkte(session.page);
    console.log(`Neue Akte erstellt: ${dossier.id}`);
    console.log(dossier.url);
    await closeSession(session);
  } catch (error) {
    await handleRunError(error, session, "create-akte-error");
  }
}

await main();
