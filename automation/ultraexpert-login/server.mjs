import fs from "node:fs/promises";
import http from "node:http";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import {
  closeSession,
  ensureLoggedIn,
  handleRunError,
  normalizeVin,
  openSession
} from "./ux-common.mjs";
import { createAkte } from "./ux-actions.mjs";
import { searchDossiersByVin } from "./ux-vin-search.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PORT = Number(process.env.PORT || 3000);
const WEBHOOK_SECRET = process.env.WEBHOOK_SECRET || "";
const STATE_PATH = path.join(__dirname, "processed-folders.json");
const AKTE_FOLDER_NAME_MUST_INCLUDE = parseCsv(process.env.AKTE_FOLDER_NAME_MUST_INCLUDE || "gutachten");

if (!WEBHOOK_SECRET) {
  throw new Error("WEBHOOK_SECRET fehlt. Bitte in .env setzen.");
}

let queue = Promise.resolve();

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url || "/", `http://${req.headers.host || "localhost"}`);

    if (req.method === "GET" && url.pathname === "/health") {
      return sendJson(res, 200, { ok: true });
    }

    if (req.method === "GET" && url.pathname === "/new-folder") {
      return sendJson(res, 200, {
        ok: true,
        message: "Webhook erreichbar. Bitte per POST mit X-Webhook-Secret aufrufen."
      });
    }

    if (req.method === "POST" && url.pathname === "/new-folder") {
      const providedSecret = req.headers["x-webhook-secret"];
      if (providedSecret !== WEBHOOK_SECRET) {
        return sendJson(res, 401, { ok: false, error: "unauthorized" });
      }

      const payload = await readJsonBody(req);
      const result = await enqueue(() => processFolder(payload));
      return sendJson(res, 200, { ok: true, ...result });
    }

    if (req.method === "POST" && url.pathname === "/vorschaden-check") {
      const providedSecret = req.headers["x-webhook-secret"];
      if (providedSecret !== WEBHOOK_SECRET) {
        return sendJson(res, 401, { ok: false, error: "unauthorized" });
      }

      const payload = await readJsonBody(req);
      const result = await enqueue(() => processVinCheck(payload));
      return sendJson(res, 200, { ok: true, ...result });
    }

    return sendJson(res, 404, { ok: false, error: "not-found" });
  } catch (error) {
    console.error("Webhook-Fehler:", error instanceof Error ? error.message : String(error));
    return sendJson(res, 500, { ok: false, error: "internal-error" });
  }
});

server.listen(PORT, () => {
  console.log(`UltraExpert Webhook Server laeuft auf Port ${PORT}`);
  console.log(`Healthcheck: http://localhost:${PORT}/health`);
});

async function processFolder(payload) {
  const folderId = String(payload?.folderId || "").trim();
  const folderName = String(payload?.folderName || "").trim();
  const folderUrl = String(payload?.folderUrl || "").trim();

  if (!folderId) {
    throw new Error("folderId fehlt im Webhook-Payload.");
  }

  const state = await readState();
  const existing = state[folderId];
  if (existing) {
    console.log(`Ordner ${folderId} wurde bereits verarbeitet.`);
    return {
      duplicate: true,
      folderId,
      folderName,
      folderUrl,
      skipped: existing.action === "skipped",
      skippedReason: existing.skippedReason,
      dossierId: existing.dossierId,
      dossierUrl: existing.dossierUrl
    };
  }

  const eligibility = classifyFolderForAkte(folderName);
  if (!eligibility.allowed) {
    console.log(`Ordner ${folderId} wird uebersprungen: ${eligibility.reason}`);

    state[folderId] = {
      action: "skipped",
      folderId,
      folderName,
      folderUrl,
      skippedReason: eligibility.reason,
      processedAt: new Date().toISOString()
    };
    await writeState(state);

    return {
      duplicate: false,
      skipped: true,
      skippedReason: eligibility.reason,
      folderId,
      folderName,
      folderUrl
    };
  }

  console.log(`Verarbeite neuen Drive-Ordner: ${folderName || folderId}`);

  const session = await openSession();

  try {
    await ensureLoggedIn(session.page);
    const dossier = await createAkte(session.page);

    state[folderId] = {
      action: "created",
      folderId,
      folderName,
      folderUrl,
      dossierId: dossier.id,
      dossierUrl: dossier.url,
      processedAt: new Date().toISOString()
    };
    await writeState(state);

    console.log(`Akte erstellt fuer Ordner ${folderId}: ${dossier.id}`);
    await closeSession(session);

    return {
      duplicate: false,
      folderId,
      folderName,
      folderUrl,
      dossierId: dossier.id,
      dossierUrl: dossier.url
    };
  } catch (error) {
    await handleRunError(error, session, "server-create-akte-error");
    throw error;
  }
}

async function processVinCheck(payload) {
  const vin = normalizeVin(payload?.vin || payload?.fin || "");
  if (!vin) {
    throw new Error("vin fehlt im Payload.");
  }

  console.log(`Vorschaden-Check fuer FIN ${vin}`);

  const session = await openSession();

  try {
    await ensureLoggedIn(session.page);
    const matches = await searchDossiersByVin(session.page, vin);
    await closeSession(session);

    const gutachtenNumbers = matches.map(match => match.gutachtenNumber);
    console.log(
      `Vorschaden-Check abgeschlossen: ${gutachtenNumbers.length} Treffer (${gutachtenNumbers.join(", ") || "keine"})`
    );

    return {
      vin,
      matchCount: matches.length,
      gutachtenNumbers,
      matches
    };
  } catch (error) {
    await handleRunError(error, session, "server-vin-search-error");
    throw error;
  }
}

async function enqueue(job) {
  const next = queue.then(job, job);
  queue = next.catch(() => {});
  return next;
}

async function readState() {
  try {
    const raw = await fs.readFile(STATE_PATH, "utf8");
    return JSON.parse(raw);
  } catch (error) {
    if (error && typeof error === "object" && "code" in error && error.code === "ENOENT") {
      return {};
    }
    throw error;
  }
}

async function writeState(state) {
  await fs.writeFile(STATE_PATH, `${JSON.stringify(state, null, 2)}\n`, "utf8");
}

async function readJsonBody(req) {
  const chunks = [];
  for await (const chunk of req) {
    chunks.push(chunk);
  }

  const raw = Buffer.concat(chunks).toString("utf8");
  return raw ? JSON.parse(raw) : {};
}

function sendJson(res, statusCode, payload) {
  res.writeHead(statusCode, { "content-type": "application/json; charset=utf-8" });
  res.end(JSON.stringify(payload));
}

function classifyFolderForAkte(folderName) {
  const normalized = folderName.toLowerCase().trim();
  if (!normalized) {
    return {
      allowed: false,
      reason: "Ordnername fehlt."
    };
  }

  const matchesRequiredText = AKTE_FOLDER_NAME_MUST_INCLUDE.some((part) => normalized.includes(part));
  if (!matchesRequiredText) {
    return {
      allowed: false,
      reason: `Kein Gutachten-Ordner. Erforderlicher Text: ${AKTE_FOLDER_NAME_MUST_INCLUDE.join(", ")}`
    };
  }

  return { allowed: true };
}

function parseCsv(value) {
  return String(value)
    .split(",")
    .map((part) => part.trim().toLowerCase())
    .filter(Boolean);
}
