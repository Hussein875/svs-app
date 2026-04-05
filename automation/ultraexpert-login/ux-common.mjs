import fs from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

export const ARTIFACTS_DIR = path.join(__dirname, "artifacts");
export const STORAGE_STATE_PATH = path.join(__dirname, "storage-state.json");

export const config = {
  url: process.env.UX_URL || "https://ux.winvalue.de/ux/",
  username: process.env.UX_USERNAME || "",
  password: process.env.UX_PASSWORD || "",
  mandant: process.env.UX_MANDANT || "",
  headless: parseBoolean(process.env.UX_HEADLESS, false),
  keepOpen: parseBoolean(process.env.UX_KEEP_OPEN, false),
  reuseSession: parseBoolean(process.env.UX_REUSE_SESSION, true),
  slowMo: parseNumber(process.env.UX_SLOW_MO, 0),
  timeoutMs: parseNumber(process.env.UX_TIMEOUT_MS, 30000)
};

const usernameLocators = page => [
  page.locator("#customerNr").first(),
  page.locator('input[name="customerNr"]').first(),
  page.locator('input[name="username"]').first(),
  page.locator('input[name="email"]').first(),
  page.locator('input[type="email"]').first(),
  page.locator('input[type="text"]').first(),
  page.locator('input[autocomplete="username"]').first(),
  page.getByLabel(/Kundennummer|Benutzername|Nutzername|E-Mail|Email/i).first(),
  page.getByPlaceholder(/Kundennummer|Benutzername|Nutzername|E-Mail|Email/i).first()
];

const passwordLocators = page => [
  page.locator('input[name="password"]').first(),
  page.locator('input[type="password"]').first(),
  page.locator('input[autocomplete="current-password"]').first(),
  page.getByLabel(/Passwort|Password/i).first(),
  page.getByPlaceholder(/Passwort|Password/i).first()
];

const mandantLocators = page => [
  page.locator('input[name="mandant"]').first(),
  page.locator('input[name="mandator"]').first(),
  page.locator('input[name="mandatorNr"]').first(),
  page.locator('input[name="tenant"]').first(),
  page.getByLabel(/Mandant/i).first(),
  page.getByPlaceholder(/Mandant/i).first()
];

const loginButtonLocators = page => [
  page.getByRole("button", { name: /Anmelden|Login/i }).first(),
  page.locator('button[type="submit"]').first(),
  page.locator('input[type="submit"]').first(),
  page.locator('button:has-text("Anmelden")').first(),
  page.locator('button:has-text("Login")').first()
];

export async function openSession() {
  assertRequiredConfig();
  await fs.mkdir(ARTIFACTS_DIR, { recursive: true });

  const browser = await chromium.launch({
    headless: config.headless,
    slowMo: config.slowMo,
    args: ["--no-sandbox", "--disable-dev-shm-usage"]
  });

  const context = await browser.newContext(await createContextOptions());
  const page = await context.newPage();
  page.setDefaultTimeout(config.timeoutMs);

  return { browser, context, page };
}

export async function ensureLoggedIn(page) {
  console.log(`Oeffne ${config.url}`);
  await page.goto(config.url, { waitUntil: "domcontentloaded" });
  await page.waitForLoadState("networkidle", { timeout: 10000 }).catch(() => {});

  if (config.reuseSession && (await isLoggedIn(page))) {
    console.log("Bereits eingeloggt, vorhandene Sitzung wird weiterverwendet.");
    await saveArtifacts(page, "already-logged-in");
    return { reusedSession: true };
  }

  await fillLoginForm(page);
  await saveArtifacts(page, "login-filled");
  await submitLogin(page);
  await waitForLoginResult(page);

  console.log("Login erfolgreich.");
  await page.context().storageState({ path: STORAGE_STATE_PATH });
  await saveArtifacts(page, "login-success");
  return { reusedSession: false };
}

export async function saveArtifacts(page, name) {
  const safeName = `${new Date().toISOString().replaceAll(":", "-")}-${name}`;
  await page.screenshot({
    path: path.join(ARTIFACTS_DIR, `${safeName}.png`),
    fullPage: true
  });
}

export async function closeSession({ browser, context }) {
  if (config.keepOpen) {
    console.log("Browser bleibt offen. Beenden mit Ctrl+C.");
    await new Promise(() => {});
  }

  await context?.close().catch(() => {});
  await browser?.close().catch(() => {});
}

export async function handleRunError(error, { browser, context, page }, artifactName = "run-error") {
  if (page) {
    await saveArtifacts(page, artifactName).catch(() => {});
  }

  console.error("Ausfuehrung fehlgeschlagen.");
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;

  if (config.keepOpen) {
    console.error("Browser bleibt fuer Debugging offen. Beenden mit Ctrl+C.");
    await new Promise(() => {});
  }

  await context?.close().catch(() => {});
  await browser?.close().catch(() => {});
}

export function extractDossierId(url) {
  const match = url.match(/\/home\/dossiers\/edit\/([^/]+)/i);
  return match?.[1] || null;
}

async function createContextOptions() {
  const options = {
    viewport: { width: 1440, height: 960 },
    ignoreHTTPSErrors: true
  };

  if (config.reuseSession && (await fileExists(STORAGE_STATE_PATH))) {
    return { ...options, storageState: STORAGE_STATE_PATH };
  }

  return options;
}

async function fillLoginForm(page) {
  const usernameField = await firstVisibleLocator(usernameLocators(page));
  const passwordField = await firstVisibleLocator(passwordLocators(page));

  if (!usernameField) {
    throw new Error("Kein Feld fuer Kundennummer/Benutzername/E-Mail gefunden.");
  }

  if (!passwordField) {
    throw new Error("Kein Passwort-Feld gefunden.");
  }

  await usernameField.fill(config.username.trim());
  await passwordField.fill(config.password);
  console.log(`Login-Feld erkannt: ${await describeLocator(usernameField)}`);
  console.log(`Passwort-Feld erkannt: ${await describeLocator(passwordField)}`);

  if (config.mandant) {
    const mandantField = await firstVisibleLocator(mandantLocators(page));
    if (mandantField) {
      await mandantField.fill(config.mandant);
    } else {
      console.log("Hinweis: UX_MANDANT ist gesetzt, aber es wurde kein Mandant-Feld gefunden.");
    }
  }
}

async function submitLogin(page) {
  const loginButton = await firstVisibleLocator(loginButtonLocators(page));

  if (loginButton) {
    await loginButton.click();
    return;
  }

  const passwordField = await firstVisibleLocator(passwordLocators(page));
  if (!passwordField) {
    throw new Error("Weder Login-Button noch Passwort-Feld fuer Enter-Submit gefunden.");
  }

  await passwordField.press("Enter");
}

async function waitForLoginResult(page) {
  const start = Date.now();
  const timeoutMs = Math.max(config.timeoutMs, 15000);

  while (Date.now() - start < timeoutMs) {
    if (await isLoggedIn(page)) {
      return;
    }

    const errorLocator = await firstVisibleLocator([
      page.getByRole("alert").first(),
      page.locator(".ant-alert").first(),
      page.locator(".alert").first(),
      page.getByText(/fehl|ungueltig|ungültig|error|falsch|incorrect|invalid/i).first()
    ]);

    if (errorLocator) {
      const message = (await errorLocator.textContent())?.trim();
      throw new Error(`Login-Fehler auf der Seite: ${message || "Unbekannte Fehlermeldung"}`);
    }

    await page.waitForTimeout(500);
  }

  throw new Error("Nach dem Login konnte kein erfolgreicher Zustand erkannt werden.");
}

async function isLoggedIn(page) {
  const logoutLocator = await firstVisibleLocator([
    page.getByRole("button", { name: /Abmelden|Logout/i }).first(),
    page.getByText(/Abmelden|Logout/i).first(),
    page.locator('[href*="logout" i]').first()
  ]);

  if (logoutLocator) {
    return true;
  }

  const loginStillVisible = Boolean(
    await firstVisibleLocator([
      ...usernameLocators(page),
      ...passwordLocators(page),
      ...loginButtonLocators(page)
    ])
  );

  if (loginStillVisible) {
    return false;
  }

  return !/login/i.test(page.url());
}

async function firstVisibleLocator(locators) {
  for (const locator of locators) {
    try {
      if (await locator.isVisible()) {
        return locator;
      }
    } catch {
      // Try the next locator candidate.
    }
  }

  return null;
}

async function describeLocator(locator) {
  try {
    return await locator.evaluate(node => {
      const parts = [node.tagName.toLowerCase()];
      if (node.id) parts.push(`#${node.id}`);
      if (node.getAttribute("name")) parts.push(`[name="${node.getAttribute("name")}"]`);
      if (node.getAttribute("placeholder")) {
        parts.push(`[placeholder="${node.getAttribute("placeholder")}"]`);
      }
      return parts.join("");
    });
  } catch {
    return "unbekannt";
  }
}

function assertRequiredConfig() {
  if (!config.username) {
    throw new Error("UX_USERNAME fehlt. Lege ihn in .env fest.");
  }

  if (!config.password) {
    throw new Error("UX_PASSWORD fehlt. Lege ihn in .env fest.");
  }
}

function parseBoolean(value, fallback) {
  if (value === undefined || value === "") {
    return fallback;
  }

  return ["1", "true", "yes", "on"].includes(String(value).toLowerCase());
}

function parseNumber(value, fallback) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

async function fileExists(filePath) {
  try {
    await fs.access(filePath);
    return true;
  } catch {
    return false;
  }
}
