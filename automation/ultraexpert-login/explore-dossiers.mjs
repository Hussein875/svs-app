import fs from "node:fs/promises";
import path from "node:path";
import {
  ARTIFACTS_DIR,
  closeSession,
  config,
  ensureLoggedIn,
  openSession,
  saveArtifacts
} from "./ux-common.mjs";

async function main() {
  const session = await openSession();

  try {
    await ensureLoggedIn(session.page);
    const base = config.url.replace(/\/?$/, "/");
    const candidates = [
      `${base}home/dossiers`,
      `${base}home/dossiers/list`,
      `${base}home/dossiers/search`,
      `${base}home`,
      `${base}home/dashboard`
    ];

    const report = [];

    for (const url of candidates) {
      await session.page.goto(url, { waitUntil: "domcontentloaded" });
      await session.page.waitForLoadState("networkidle", { timeout: 8000 }).catch(() => {});
      await saveArtifacts(session.page, `explore-${url.split("/").pop() || "root"}`);

      const inputs = await session.page.locator("input").evaluateAll(nodes =>
        nodes
          .filter(node => node instanceof HTMLInputElement)
          .map(node => ({
            type: node.type,
            name: node.name,
            id: node.id,
            placeholder: node.placeholder,
            ariaLabel: node.getAttribute("aria-label"),
            visible: node.offsetParent !== null
          }))
          .filter(item => item.visible)
      );

      const buttons = await session.page.locator("button").evaluateAll(nodes =>
        nodes
          .map(node => (node.textContent || "").trim())
          .filter(Boolean)
          .slice(0, 40)
      );

      report.push({
        url: session.page.url(),
        inputs,
        buttons
      });
    }

    const reportPath = path.join(ARTIFACTS_DIR, "explore-report.json");
    await fs.writeFile(reportPath, `${JSON.stringify(report, null, 2)}\n`, "utf8");
    console.log(reportPath);
    console.log(JSON.stringify(report, null, 2));

    await closeSession(session);
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 1;
    await session.browser?.close().catch(() => {});
  }
}

await main();
