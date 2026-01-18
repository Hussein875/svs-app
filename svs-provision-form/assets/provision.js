(function () {
  const API = window.SVS_PROVISION_API || {};
  const token = new URLSearchParams(location.search).get("token") || "";

  const root = document.getElementById("svs-provision-root");
  if (!root) return;

  root.innerHTML = `
    <div class="svs-card">
      <h2 style="margin:0 0 6px;">Provision</h2>
      <p style="margin:0 0 14px;color:#5b6476;">
        Bitte ausfüllen und unterschreiben.
      </p>

      <div id="svs-badge" class="svs-badge svs-warn">Token wird geprüft …</div>
      <div style="height:1px;background:#e7e9f0;margin:18px 0;"></div>

      <form id="svs-form" style="display:none;">
        <div class="svs-row">
          <div>
            <label class="svs-label">Vorname *</label>
            <input class="svs-input" name="firstName" autocomplete="given-name" required>
          </div>
          <div>
            <label class="svs-label">Nachname *</label>
            <input class="svs-input" name="lastName" autocomplete="family-name" required>
          </div>
        </div>

        <label class="svs-label">Straße / Hausnr. *</label>
        <input class="svs-input" name="street" autocomplete="street-address" required>

        <div class="svs-row">
          <div>
            <label class="svs-label">PLZ *</label>
            <input class="svs-input" name="zip" autocomplete="postal-code" inputmode="numeric" required>
          </div>
          <div>
            <label class="svs-label">Ort *</label>
            <input class="svs-input" name="city" autocomplete="address-level2" required>
          </div>
        </div>

        <div class="svs-row">
          <div>
            <label class="svs-label">Auszahlungsart *</label>
            <select class="svs-select" name="payoutMethod" id="svs-payoutMethod" required>
              <option value="iban">Überweisung (IBAN)</option>
              <option value="paypal">PayPal</option>
            </select>
          </div>
          <div id="svs-payoutIbanWrap">
            <label class="svs-label">IBAN *</label>
            <input class="svs-input" name="payoutIban" id="svs-payoutIban" placeholder="DE00 …">
          </div>
          <div id="svs-payoutPaypalWrap" style="display:none;">
            <label class="svs-label">PayPal E-Mail *</label>
            <input class="svs-input" name="payoutPaypal" id="svs-payoutPaypal" type="email" autocomplete="email">
          </div>
        </div>

        <label class="svs-label">Referenz (optional, z. B. empfohlener Kunde/AZ)</label>
        <input class="svs-input" name="reference" placeholder="Optional">

        <div style="margin-top:14px;">
          <div style="font-weight:700;margin-bottom:6px;">Digitale Unterschrift *</div>
          <div class="svs-sigwrap">
            <canvas id="svs-sig" width="1200" height="440"></canvas>
            <div class="svs-sigbar">
              <button type="button" class="svs-smallbtn" id="svs-clearSig">Unterschrift löschen</button>
              <span style="color:#5b6476;font-size:13px;" id="svs-sigHint">Bitte unterschreiben.</span>
            </div>
          </div>
        </div>

        <label style="display:flex;gap:10px;align-items:flex-start;margin-top:12px;">
          <input type="checkbox" required style="margin-top:3px;">
          <span style="color:#5b6476;font-size:13px;">
            Ich bestätige den Erhalt der Vermittlungsprovision und die Richtigkeit meiner Angaben. *
          </span>
        </label>

        <div class="svs-actions">
          <button class="svs-btn svs-primary" id="svs-submit" type="submit">Absenden</button>
        </div>

        <div id="svs-msg" style="margin-top:10px;color:#5b6476;font-size:13px;"></div>
      </form>

      <div id="svs-success" style="display:none;">
        <div class="svs-badge svs-ok">Vielen Dank. Erfolgreich übermittelt.</div>
        <p style="margin:12px 0 0;color:#5b6476;">Du kannst diese Seite jetzt schließen.</p>
        <div id="svs-success-ref" style="margin-top:10px;color:#5b6476;font-size:13px;"></div>
      </div>
    </div>
  `;

  const badge = document.getElementById("svs-badge");
  const form = document.getElementById("svs-form");
  const msg = document.getElementById("svs-msg");
  const success = document.getElementById("svs-success");
  const successRef = document.getElementById("svs-success-ref");
  const submitBtn = document.getElementById("svs-submit");

  function setBadge(kind, text) {
    badge.className = `svs-badge ${kind}`;
    badge.textContent = text;
  }

  const pm = document.getElementById("svs-payoutMethod");
  const ibanWrap = document.getElementById("svs-payoutIbanWrap");
  const ppWrap = document.getElementById("svs-payoutPaypalWrap");
  const iban = document.getElementById("svs-payoutIban");
  const pp = document.getElementById("svs-payoutPaypal");

  function syncPayoutUI() {
    if (pm.value === "paypal") {
      ibanWrap.style.display = "none";
      ppWrap.style.display = "block";
      iban.value = "";
      pp.required = true;
      iban.required = false;
    } else {
      ppWrap.style.display = "none";
      ibanWrap.style.display = "block";
      pp.value = "";
      iban.required = true;
      pp.required = false;
    }
  }
  pm.addEventListener("change", syncPayoutUI);
  syncPayoutUI();

  // Signature
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

  async function checkToken() {
    if (!token) {
      setBadge("svs-err", "Kein Token gefunden. Bitte Link erneut anfordern.");
      return;
    }
    if (!API.getProvisionLink) {
      setBadge("svs-err", "API-Konfiguration fehlt (getProvisionLink).");
      return;
    }

    try {
      const r = await fetch(`${API.getProvisionLink}?token=${encodeURIComponent(token)}`);
      const j = await r.json();

      if (!j?.ok) {
        setBadge("svs-err", "Token-Prüfung fehlgeschlagen.");
        return;
      }

      if (j.status === "valid") {
        setBadge("svs-ok", "Link gültig. Bitte Formular ausfüllen.");
        form.style.display = "block";
        return;
      }
      if (j.status === "expired") {
        setBadge("svs-err", "Link abgelaufen. Bitte neuen Link anfordern.");
        return;
      }
      if (j.status === "used") {
        setBadge("svs-err", "Link bereits verwendet. Bitte neuen Link anfordern.");
        return;
      }

      setBadge("svs-err", "Token nicht gefunden. Bitte Link prüfen.");
    } catch (e) {
      setBadge("svs-err", "Token-Prüfung fehlgeschlagen (CORS/Netzwerk).");
    }
  }

  function lockForm(locked) {
    form.querySelectorAll("input,select,textarea,button").forEach((el) => {
      el.disabled = !!locked;
    });
  }

  form.addEventListener("submit", async (e) => {
    e.preventDefault();
    msg.textContent = "";

    if (!form.checkValidity()) {
      form.reportValidity();
      return;
    }

    try {
      if (!API.submitProvisionForm) throw new Error("API fehlt (submitProvisionForm).");
      if (!hasSig) throw new Error("Bitte unterschreiben, bevor du absendest.");

const fd = new FormData(form);
const firstName = String(fd.get("firstName") || "").trim();
const lastName = String(fd.get("lastName") || "").trim();
const street = String(fd.get("street") || "").trim();
const zip = String(fd.get("zip") || "").trim();
const city = String(fd.get("city") || "").trim();
const reference = String(fd.get("reference") || "").trim();

const payoutMethod = String(fd.get("payoutMethod") || "").trim();
const payoutIban = String(fd.get("payoutIban") || "").trim();
const payoutPaypal = String(fd.get("payoutPaypal") || "").trim();

// REQUIRED by backend:
const recommenderName = `${firstName} ${lastName}`.trim();
const customerName = reference || "Empfehlung";

const payload = {
  token,

  // REQUIRED
  recommenderName,
  customerName,

  // optional address fields in backend
  recommenderStreet: street,
  recommenderZip: zip,
  recommenderCity: city,

  // payout
  payoutMethod,
  payoutIban: payoutMethod === "iban" ? payoutIban : undefined,
  payoutPaypal: payoutMethod === "paypal" ? payoutPaypal : undefined,

  notes: reference ? `Referenz: ${reference}` : undefined,

  acceptedAtClientIso: new Date().toISOString(),
  signaturePngBase64: sigB64NoPrefix(),
};

      lockForm(true);
      submitBtn.textContent = "Sende …";

      const r = await fetch(API.submitProvisionForm, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });

      const j = await r.json().catch(() => ({}));
      if (!r.ok || !j?.ok) {
        throw new Error(j?.error || `Fehler (${r.status})`);
      }

      setBadge("svs-ok", "Übermittlung erfolgreich.");
      form.style.display = "none";
      success.style.display = "block";
      successRef.textContent = j?.commissionId ? `Referenz: ${j.commissionId}` : "";
      window.scrollTo({ top: 0, behavior: "smooth" });
    } catch (err) {
      setBadge("svs-err", "Übermittlung fehlgeschlagen.");
      msg.textContent = err?.message || "Übermittlung fehlgeschlagen.";
      lockForm(false);
      submitBtn.textContent = "Absenden";
    }
  });

  checkToken();
})();