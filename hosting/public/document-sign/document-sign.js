(function () {
  const API = window.SVS_DOCUMENT_SIGN_API || {};
  const token = new URLSearchParams(location.search).get("token") || "";

  const root = document.getElementById("svs-document-sign-root");
  if (!root) return;

  root.innerHTML = `
    <div class="svs-card">
      <h2 style="margin:0 0 6px;">Dokument unterschreiben</h2>
      <p class="svs-meta" id="svs-doc-title" style="margin:0 0 12px;">…</p>

      <div id="svs-badge" class="svs-badge svs-warn">Token wird geprüft …</div>
      <div style="height:1px;background:#e7e9f0;margin:18px 0;"></div>

      <form id="svs-form" style="display:none;">
        <p class="svs-meta" id="svs-accident-meta" style="margin:0 0 14px;"></p>

        <div style="margin-top:4px;">
          <div style="font-weight:700;margin-bottom:6px;">Digitale Unterschrift *</div>
          <div class="svs-sigwrap">
            <canvas id="svs-sig" width="1200" height="440"></canvas>
            <div class="svs-sigbar">
              <button type="button" class="svs-smallbtn" id="svs-clearSig">Unterschrift löschen</button>
              <span style="color:#5b6476;font-size:13px;" id="svs-sigHint">Bitte unterschreiben.</span>
            </div>
          </div>
        </div>

        <details class="svs-doc-details" id="svs-doc-details">
          <summary class="svs-doc-summary">
            <span class="svs-doc-summary-main">Vollmacht anzeigen</span>
            <span class="svs-doc-summary-sub">Zum Lesen aufklappen</span>
          </summary>
          <div class="svs-pdfwrap">
            <div id="svs-pdf-loading" class="svs-pdf-loading" style="display:none;">
              PDF wird geladen …
            </div>
            <div id="svs-pdf-pages"></div>
          </div>
          <p class="svs-pdf-fallback">
            <a id="svs-pdf-open" href="#" target="_blank" rel="noopener noreferrer">
              PDF in neuem Tab öffnen
            </a>
          </p>
        </details>

        <div id="svs-pdf-missing" class="svs-badge svs-warn svs-pdf-missing" style="display:none;">
          Dokumentvorschau konnte nicht geladen werden. Bitte neuen Link anfordern
          oder die Vollmacht beim Team erhalten, bevor du unterschreibst.
        </div>

        <label class="svs-consent">
          <input type="checkbox" id="svs-readConfirm" required>
          <span>
            Ich habe die Vollmacht gelesen, bestätige die Richtigkeit meiner Angaben
            und unterschreibe dieses Dokument verbindlich. *
          </span>
        </label>

        <div class="svs-actions">
          <button class="svs-btn svs-primary" id="svs-submit" type="submit">Unterschrift absenden</button>
        </div>

        <div id="svs-msg" style="margin-top:10px;color:#5b6476;font-size:13px;"></div>
      </form>

      <div id="svs-success" style="display:none;">
        <div class="svs-badge svs-ok">Vielen Dank. Dokument erfolgreich unterschrieben.</div>
        <p style="margin:12px 0 0;color:#5b6476;">Du kannst diese Seite jetzt schließen.</p>
      </div>
    </div>
  `;

  const badge = document.getElementById("svs-badge");
  const form = document.getElementById("svs-form");
  const msg = document.getElementById("svs-msg");
  const success = document.getElementById("svs-success");
  const submitBtn = document.getElementById("svs-submit");
  const docTitle = document.getElementById("svs-doc-title");
  const accidentMeta = document.getElementById("svs-accident-meta");
  const docDetails = document.getElementById("svs-doc-details");
  const pdfMissing = document.getElementById("svs-pdf-missing");
  const pdfPages = document.getElementById("svs-pdf-pages");
  const pdfLoading = document.getElementById("svs-pdf-loading");
  const pdfOpenLink = document.getElementById("svs-pdf-open");

  const PDFJS_VERSION = "3.11.174";
  let pdfObjectUrl = null;
  let pdfBytesForRender = null;
  let pdfRenderToken = 0;
  let pdfJsLoadPromise = null;
  let resizeTimer = null;

  function setBadge(kind, text) {
    badge.className = `svs-badge ${kind}`;
    badge.textContent = text;
  }

  function formatGermanDate(iso) {
    if (!iso) return "";
    const date = new Date(iso);
    if (Number.isNaN(date.getTime())) return "";
    return date.toLocaleDateString("de-DE");
  }

  function revokePdfObjectUrl() {
    if (pdfObjectUrl) {
      URL.revokeObjectURL(pdfObjectUrl);
      pdfObjectUrl = null;
    }
  }

  function base64ToBytes(base64) {
    const binary = atob(base64);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i += 1) {
      bytes[i] = binary.charCodeAt(i);
    }
    return bytes;
  }

  function loadPdfJs() {
    if (window.pdfjsLib) {
      return Promise.resolve(window.pdfjsLib);
    }
    if (!pdfJsLoadPromise) {
      pdfJsLoadPromise = new Promise((resolve, reject) => {
        const script = document.createElement("script");
        script.src =
          `https://cdnjs.cloudflare.com/ajax/libs/pdf.js/${PDFJS_VERSION}/pdf.min.js`;
        script.onload = () => {
          const lib = window.pdfjsLib;
          if (!lib) {
            reject(new Error("pdf.js missing"));
            return;
          }
          lib.GlobalWorkerOptions.workerSrc =
            `https://cdnjs.cloudflare.com/ajax/libs/pdf.js/${PDFJS_VERSION}/pdf.worker.min.js`;
          resolve(lib);
        };
        script.onerror = () => reject(new Error("pdf.js load failed"));
        document.head.appendChild(script);
      });
    }
    return pdfJsLoadPromise;
  }

  function pdfContainerWidth() {
    const width = pdfPages.clientWidth;
    return width > 0 ? width : Math.min(880, window.innerWidth - 72);
  }

  async function renderPdfPages(bytes) {
    const renderToken = pdfRenderToken;
    pdfLoading.style.display = "block";
    pdfPages.innerHTML = "";

    try {
      const pdfjs = await loadPdfJs();
      if (renderToken !== pdfRenderToken) return;

      const pdf = await pdfjs.getDocument({ data: bytes.slice(0) }).promise;
      if (renderToken !== pdfRenderToken) return;

      pdfLoading.style.display = "none";
      const width = pdfContainerWidth();

      for (let pageNum = 1; pageNum <= pdf.numPages; pageNum += 1) {
        const page = await pdf.getPage(pageNum);
        if (renderToken !== pdfRenderToken) return;

        const baseViewport = page.getViewport({ scale: 1 });
        const scale = width / baseViewport.width;
        const viewport = page.getViewport({ scale });

        const pageWrap = document.createElement("div");
        pageWrap.className = "svs-pdf-page";
        const canvas = document.createElement("canvas");
        canvas.width = Math.floor(viewport.width);
        canvas.height = Math.floor(viewport.height);
        pageWrap.appendChild(canvas);
        pdfPages.appendChild(pageWrap);

        await page.render({
          canvasContext: canvas.getContext("2d"),
          viewport,
        }).promise;
      }
    } catch (e) {
      if (renderToken !== pdfRenderToken) return;
      console.warn("PDF render failed", e);
      pdfLoading.style.display = "none";
      pdfPages.innerHTML = "";
      throw e;
    }
  }

  function schedulePdfRerender() {
    if (!pdfBytesForRender || !docDetails.open) return;
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(() => {
      renderPdfPages(pdfBytesForRender).catch(() => {});
    }, 150);
  }

  async function setPdfPreview(pdfUrl, prefilledPdfBase64) {
    revokePdfObjectUrl();
    pdfBytesForRender = null;
    pdfRenderToken += 1;
    pdfPages.innerHTML = "";
    pdfOpenLink.removeAttribute("href");
    pdfMissing.style.display = "none";
    docDetails.style.display = "block";

    let bytes = null;

    if (prefilledPdfBase64) {
      try {
        bytes = base64ToBytes(prefilledPdfBase64);
      } catch (e) {
        console.warn("PDF base64 decode failed", e);
      }
    } else if (pdfUrl) {
      try {
        const response = await fetch(pdfUrl);
        if (response.ok) {
          bytes = new Uint8Array(await response.arrayBuffer());
        }
      } catch (e) {
        console.warn("PDF fetch failed", e);
      }
    }

    if (!bytes || !bytes.length) {
      docDetails.style.display = "none";
      pdfMissing.style.display = "inline-block";
      return false;
    }

    try {
      const blob = new Blob([bytes], { type: "application/pdf" });
      pdfObjectUrl = URL.createObjectURL(blob);
      pdfOpenLink.href = pdfObjectUrl;
      pdfBytesForRender = bytes;
      await renderPdfPages(bytes);
      return true;
    } catch (e) {
      docDetails.style.display = "none";
      pdfMissing.style.display = "inline-block";
      return false;
    }
  }

  docDetails.addEventListener("toggle", () => {
    if (docDetails.open) {
      schedulePdfRerender();
    }
  });
  window.addEventListener("resize", schedulePdfRerender);

  const canvas = document.getElementById("svs-sig");
  const ctx = canvas.getContext("2d");
  ctx.lineWidth = 4;
  ctx.lineCap = "round";
  ctx.lineJoin = "round";
  ctx.strokeStyle = "#0b1220";

  let drawing = false;
  let hasSig = false;

  function pos(e) {
    const r = canvas.getBoundingClientRect();
    const t = e.touches && e.touches[0];
    const x = ((t ? t.clientX : e.clientX) - r.left) * (canvas.width / r.width);
    const y = ((t ? t.clientY : e.clientY) - r.top) * (canvas.height / r.height);
    return { x, y };
  }

  function start(e) {
    drawing = true;
    const p = pos(e);
    ctx.beginPath();
    ctx.moveTo(p.x, p.y);
    e.preventDefault?.();
  }

  function move(e) {
    if (!drawing) return;
    const p = pos(e);
    ctx.lineTo(p.x, p.y);
    ctx.stroke();
    hasSig = true;
    document.getElementById("svs-sigHint").textContent = "Unterschrift erfasst.";
    e.preventDefault?.();
  }

  function end() {
    drawing = false;
  }

  canvas.addEventListener("mousedown", start);
  canvas.addEventListener("mousemove", move);
  window.addEventListener("mouseup", end);
  canvas.addEventListener("touchstart", start, { passive: false });
  canvas.addEventListener("touchmove", move, { passive: false });
  canvas.addEventListener("touchend", end);

  document.getElementById("svs-clearSig").addEventListener("click", () => {
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    hasSig = false;
    document.getElementById("svs-sigHint").textContent = "Bitte unterschreiben.";
  });

  function sigB64NoPrefix() {
    return canvas.toDataURL("image/png").replace(/^data:image\/png;base64,/, "");
  }

  function lockForm(locked) {
    form.querySelectorAll("input,button").forEach((el) => {
      el.disabled = !!locked;
    });
  }

  async function checkToken() {
    if (!token) {
      setBadge("svs-err", "Kein Token gefunden. Bitte Link erneut anfordern.");
      return;
    }
    if (!API.getDocumentSigningLink) {
      setBadge("svs-err", "API-Konfiguration fehlt (getDocumentSigningLink).");
      return;
    }

    try {
      const r = await fetch(`${API.getDocumentSigningLink}?token=${encodeURIComponent(token)}`);
      const j = await r.json();

      if (!j?.ok) {
        setBadge("svs-err", "Token-Prüfung fehlgeschlagen.");
        return;
      }

      const title = j.documentTitle || "Anwaltsvollmacht";
      docTitle.textContent = title;

      if (j.status === "unused") {
        setBadge("svs-ok", "Link gültig. Bitte Vollmacht lesen und unterschreiben.");

        if (j.customerName) {
          accidentMeta.textContent = `Kunde: ${j.customerName}`;
        } else if (j.accidentDateIso) {
          accidentMeta.textContent = `Unfalldatum: ${formatGermanDate(j.accidentDateIso)}`;
        } else {
          accidentMeta.textContent =
            "Bitte unterschreiben. Die Vollmacht kannst du darunter aufklappen und lesen.";
        }

        await setPdfPreview(j.pdfUrl, j.prefilledPdfBase64);
        form.style.display = "block";
        return;
      }

      if (j.status === "expired") {
        setBadge("svs-err", "Link abgelaufen. Bitte neuen Link anfordern.");
        return;
      }

      if (j.status === "signed") {
        setBadge("svs-ok", "Dieses Dokument wurde bereits unterschrieben.");
        success.style.display = "block";
        return;
      }

      setBadge("svs-err", "Token nicht gefunden. Bitte Link prüfen.");
    } catch (e) {
      setBadge("svs-err", "Token-Prüfung fehlgeschlagen (CORS/Netzwerk).");
    }
  }

  form.addEventListener("submit", async (e) => {
    e.preventDefault();
    msg.textContent = "";

    if (!form.checkValidity()) {
      form.reportValidity();
      return;
    }

    try {
      if (!API.submitDocumentSigningForm) {
        throw new Error("API fehlt (submitDocumentSigningForm).");
      }
      if (!hasSig) {
        throw new Error("Bitte unterschreiben, bevor du absendest.");
      }

      const payload = {
        token,
        signingDateIso: new Date().toISOString(),
        signaturePngBase64: sigB64NoPrefix(),
      };

      lockForm(true);
      submitBtn.textContent = "Sende …";

      const r = await fetch(API.submitDocumentSigningForm, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });

      const j = await r.json().catch(() => ({}));
      if (!r.ok || !j?.ok) {
        throw new Error(j?.error || `Fehler (${r.status})`);
      }

      setBadge("svs-ok", "Unterschrift übermittelt.");
      form.style.display = "none";
      success.style.display = "block";
      revokePdfObjectUrl();
      window.scrollTo({ top: 0, behavior: "smooth" });
    } catch (err) {
      setBadge("svs-err", "Übermittlung fehlgeschlagen.");
      msg.textContent = err?.message || "Übermittlung fehlgeschlagen.";
      lockForm(false);
      submitBtn.textContent = "Unterschrift absenden";
    }
  });

  window.addEventListener("beforeunload", revokePdfObjectUrl);
  checkToken();
})();
