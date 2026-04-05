import { closeSession, ensureLoggedIn, handleRunError, openSession } from "./ux-common.mjs";

async function main() {
  const session = await openSession();

  try {
    await ensureLoggedIn(session.page);
    await closeSession(session);
  } catch (error) {
    await handleRunError(error, session, "login-error");
  }
}

await main();
