import { extractDossierId, saveArtifacts } from "./ux-common.mjs";

export async function createAkte(page) {
  const neuButton = page.getByRole("button", { name: /^Neu$/i }).first();
  await neuButton.waitFor({ state: "visible" });
  await neuButton.click();

  const akteItem = page
    .locator("a, button, [role=button]")
    .filter({ hasText: /^Akte$/ })
    .first();
  await akteItem.waitFor({ state: "visible" });
  await akteItem.click();

  await page.waitForURL(/\/home\/dossiers\/edit\/[^/]+\/order\/general/i, {
    timeout: 20000
  });
  await page.waitForTimeout(2000);
  await saveArtifacts(page, "create-akte-success");

  const url = page.url();
  const id = extractDossierId(url);

  if (!id) {
    throw new Error(
      `Neue Akte wurde geoeffnet, aber die Akten-ID konnte nicht aus der URL gelesen werden: ${url}`
    );
  }

  return { id, url };
}
