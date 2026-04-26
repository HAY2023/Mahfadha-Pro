/**
 * Mahfadha Pro — Content Script (The Observer)
 * Detects login forms, intercepts submission, injects Shadow DOM overlay.
 * Zero browser storage. All data lives in volatile RAM only.
 */

(() => {
  "use strict";

  // Prevent double-injection in iframes
  if (window.__mahfadhaProInjected) return;
  window.__mahfadhaProInjected = true;

  // ─── Configuration ──────────────────────────────────────────────────
  const USERNAME_SELECTORS = [
    'input[type="email"]',
    'input[type="text"][name*="user" i]',
    'input[type="text"][name*="login" i]',
    'input[type="text"][name*="email" i]',
    'input[type="text"][id*="user" i]',
    'input[type="text"][id*="login" i]',
    'input[type="text"][id*="email" i]',
    'input[type="text"][autocomplete="username"]',
    'input[type="text"][autocomplete="email"]',
    'input[autocomplete="username"]',
    'input[name*="identifier" i]',
    'input[name*="account" i]',
    'input[type="tel"][name*="phone" i]',
  ];

  const PASSWORD_SELECTOR = 'input[type="password"]';

  // ─── Heuristic: Find Username Field Near a Password Field ─────────
  function findUsernameField(passwordField) {
    const form = passwordField.closest("form");
    const scope = form || passwordField.closest("div[class]") || document;

    // Strategy 1: Query known selectors within the same form/scope
    for (const sel of USERNAME_SELECTORS) {
      const candidate = scope.querySelector(sel);
      if (candidate && candidate !== passwordField && isVisible(candidate)) {
        return candidate;
      }
    }

    // Strategy 2: Walk backwards through all inputs to find the nearest text-like input
    const allInputs = Array.from(scope.querySelectorAll("input"));
    const pwdIndex = allInputs.indexOf(passwordField);
    for (let i = pwdIndex - 1; i >= 0; i--) {
      const inp = allInputs[i];
      const t = (inp.type || "text").toLowerCase();
      if (["text", "email", "tel"].includes(t) && isVisible(inp)) {
        return inp;
      }
    }

    return null;
  }

  function isVisible(el) {
    if (!el) return false;
    const s = getComputedStyle(el);
    return s.display !== "none" && s.visibility !== "hidden" && s.opacity !== "0"
      && el.offsetWidth > 0 && el.offsetHeight > 0;
  }

  // ─── Detect and Attach to Login Forms ─────────────────────────────
  const processedForms = new WeakSet();

  function scanForLoginForms() {
    const passwordFields = document.querySelectorAll(PASSWORD_SELECTOR);

    passwordFields.forEach((pwdField) => {
      const form = pwdField.closest("form");
      const target = form || pwdField;

      if (processedForms.has(target)) return;
      processedForms.add(target);

      if (form) {
        form.addEventListener("submit", (e) => handleFormSubmit(e, pwdField), { capture: true, once: true });
      }

      // Also intercept Enter key and button clicks for JS-driven forms
      pwdField.addEventListener("keydown", (e) => {
        if (e.key === "Enter") handleFormSubmit(e, pwdField);
      }, { capture: true, once: true });

      // Find nearby submit buttons
      const scope = form || pwdField.parentElement?.parentElement?.parentElement || document;
      const submitBtns = scope.querySelectorAll(
        'button[type="submit"], input[type="submit"], button:not([type])'
      );
      submitBtns.forEach((btn) => {
        if (processedForms.has(btn)) return;
        processedForms.add(btn);
        btn.addEventListener("click", () => handleFormSubmit(null, pwdField), { capture: true, once: true });
      });
    });
  }

  // ─── Handle Form Submission ───────────────────────────────────────
  function handleFormSubmit(event, pwdField) {
    const usernameField = findUsernameField(pwdField);
    const username = usernameField?.value?.trim() || "";
    const password = pwdField?.value || "";

    if (!password) return; // No password entered, skip

    // Check if this site is blocked before showing overlay
    const hostname = window.location.hostname;

    chrome.runtime.sendMessage(
      { action: "CHECK_BLOCKED", data: { hostname } },
      (response) => {
        if (response?.blocked) return;
        showSaveOverlay({ url: window.location.href, hostname, username, password });
      }
    );
  }

  // ─── Shadow DOM Overlay (Glassmorphism Prompt) ────────────────────
  function showSaveOverlay(credentials) {
    // Remove any existing overlay
    const existing = document.getElementById("mahfadha-pro-host");
    if (existing) existing.remove();

    const host = document.createElement("div");
    host.id = "mahfadha-pro-host";
    host.style.cssText = "all:initial; position:fixed; top:0; left:0; width:100vw; height:100vh; z-index:2147483647; pointer-events:none;";
    document.documentElement.appendChild(host);

    const shadow = host.attachShadow({ mode: "closed" });

    const style = document.createElement("style");
    style.textContent = getOverlayCSS();
    shadow.appendChild(style);

    const overlay = document.createElement("div");
    overlay.className = "mhf-overlay";
    overlay.innerHTML = getOverlayHTML(credentials);
    shadow.appendChild(overlay);

    // Animate in
    requestAnimationFrame(() => {
      overlay.classList.add("mhf-visible");
      const card = shadow.querySelector(".mhf-card");
      if (card) card.classList.add("mhf-card-visible");
    });

    // ── Button Handlers ───────────────────────────────────────────
    const btnSave = shadow.querySelector("#mhf-btn-save");
    const btnNever = shadow.querySelector("#mhf-btn-never");
    const btnDismiss = shadow.querySelector("#mhf-btn-dismiss");

    btnSave.addEventListener("click", () => {
      btnSave.textContent = "Sending…";
      btnSave.disabled = true;

      chrome.runtime.sendMessage(
        { action: "SAVE_CREDENTIAL", data: credentials },
        (response) => {
          if (response?.status === "success") {
            showFeedback(shadow, "✓ Saved to Hardware Vault", "success");
          } else {
            showFeedback(shadow, "✗ Bridge unavailable", "error");
          }
          wipeCredentials(credentials);
          setTimeout(() => destroyOverlay(host), 1800);
        }
      );
    });

    btnNever.addEventListener("click", () => {
      chrome.runtime.sendMessage(
        { action: "BLOCK_SITE", data: { hostname: credentials.hostname } }
      );
      wipeCredentials(credentials);
      destroyOverlay(host);
    });

    btnDismiss.addEventListener("click", () => {
      wipeCredentials(credentials);
      destroyOverlay(host);
    });
  }

  function showFeedback(shadow, message, type) {
    const card = shadow.querySelector(".mhf-card");
    if (!card) return;
    card.innerHTML = `
      <div class="mhf-feedback mhf-feedback-${type}">
        <span class="mhf-feedback-icon">${type === "success" ? "🛡️" : "⚠️"}</span>
        <span>${message}</span>
      </div>`;
  }

  function destroyOverlay(host) {
    const overlay = host?.shadowRoot?.querySelector(".mhf-overlay") || null;
    if (overlay) overlay.classList.remove("mhf-visible");
    setTimeout(() => host?.remove(), 350);
  }

  function wipeCredentials(obj) {
    if (!obj) return;
    for (const k of Object.keys(obj)) {
      if (typeof obj[k] === "string") obj[k] = "";
      obj[k] = null;
      delete obj[k];
    }
  }

  // ─── Overlay HTML ─────────────────────────────────────────────────
  function getOverlayHTML(creds) {
    const domain = creds.hostname || new URL(creds.url).hostname;
    const maskedUser = creds.username
      ? creds.username.substring(0, 3) + "•••"
      : "(no username)";
    return `
      <div class="mhf-card">
        <button class="mhf-close" id="mhf-btn-dismiss" aria-label="Close">✕</button>
        <div class="mhf-header">
          <div class="mhf-shield">
            <svg viewBox="0 0 24 24" width="32" height="32" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
              <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>
              <rect x="9" y="10" width="6" height="5" rx="1"/>
              <path d="M10 10V8a2 2 0 1 1 4 0v2"/>
            </svg>
          </div>
          <div class="mhf-title">Mahfadha Pro</div>
          <div class="mhf-subtitle">Hardware Vault Detected</div>
        </div>
        <div class="mhf-body">
          <p class="mhf-prompt">Save this password to your<br><strong>hardware device</strong>?</p>
          <div class="mhf-meta">
            <div class="mhf-meta-row">
              <span class="mhf-label">Site</span>
              <span class="mhf-value">${escapeHtml(domain)}</span>
            </div>
            <div class="mhf-meta-row">
              <span class="mhf-label">User</span>
              <span class="mhf-value">${escapeHtml(maskedUser)}</span>
            </div>
          </div>
        </div>
        <div class="mhf-actions">
          <button class="mhf-btn mhf-btn-primary" id="mhf-btn-save">
            <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2"><path d="M20 6L9 17l-5-5"/></svg>
            Save to Hardware
          </button>
          <button class="mhf-btn mhf-btn-ghost" id="mhf-btn-never">Never for this site</button>
        </div>
        <div class="mhf-footer">🔒 Zero-storage · Data sent via encrypted bridge</div>
      </div>`;
  }

  function escapeHtml(str) {
    const d = document.createElement("div");
    d.textContent = str;
    return d.innerHTML;
  }

  // ─── Overlay CSS (Glassmorphism) ──────────────────────────────────
  function getOverlayCSS() {
    return `
      @import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap');

      *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

      .mhf-overlay {
        position: fixed; inset: 0;
        display: flex; align-items: flex-start; justify-content: flex-end;
        padding: 20px 24px;
        background: rgba(0,0,0,0);
        transition: background 0.35s ease;
        pointer-events: all;
        font-family: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;
        z-index: 2147483647;
      }
      .mhf-overlay.mhf-visible {
        background: rgba(0,0,0,0.18);
      }

      .mhf-card {
        position: relative;
        width: 340px;
        background: linear-gradient(135deg,
          rgba(15, 23, 42, 0.82),
          rgba(30, 41, 59, 0.78));
        backdrop-filter: blur(24px) saturate(1.6);
        -webkit-backdrop-filter: blur(24px) saturate(1.6);
        border: 1px solid rgba(99, 220, 255, 0.15);
        border-radius: 20px;
        padding: 28px 24px 20px;
        color: #e2e8f0;
        box-shadow:
          0 8px 32px rgba(0,0,0,0.45),
          0 0 0 1px rgba(99,220,255,0.06),
          inset 0 1px 0 rgba(255,255,255,0.05);
        transform: translateY(-20px) scale(0.96);
        opacity: 0;
        transition: transform 0.4s cubic-bezier(.21,1.02,.73,1), opacity 0.35s ease;
      }
      .mhf-card.mhf-card-visible {
        transform: translateY(0) scale(1);
        opacity: 1;
      }

      .mhf-close {
        position: absolute; top: 12px; right: 14px;
        background: none; border: none; color: rgba(148,163,184,0.6);
        font-size: 16px; cursor: pointer; padding: 4px 6px; border-radius: 6px;
        transition: color 0.2s, background 0.2s;
        line-height: 1;
      }
      .mhf-close:hover { color: #f1f5f9; background: rgba(255,255,255,0.08); }

      .mhf-header { text-align: center; margin-bottom: 20px; }

      .mhf-shield {
        display: inline-flex; align-items: center; justify-content: center;
        width: 56px; height: 56px; border-radius: 16px; margin-bottom: 10px;
        background: linear-gradient(135deg, rgba(6,182,212,0.18), rgba(59,130,246,0.14));
        border: 1px solid rgba(99,220,255,0.12);
        color: #67e8f9;
        animation: mhf-pulse 2.5s ease-in-out infinite;
      }
      @keyframes mhf-pulse {
        0%, 100% { box-shadow: 0 0 0 0 rgba(6,182,212,0.25); }
        50% { box-shadow: 0 0 16px 4px rgba(6,182,212,0.15); }
      }

      .mhf-title {
        font-size: 17px; font-weight: 700; letter-spacing: -0.3px;
        background: linear-gradient(90deg, #67e8f9, #a5b4fc);
        -webkit-background-clip: text; -webkit-text-fill-color: transparent;
        background-clip: text;
      }
      .mhf-subtitle {
        font-size: 11px; color: rgba(148,163,184,0.7); margin-top: 3px;
        text-transform: uppercase; letter-spacing: 1.2px; font-weight: 500;
      }

      .mhf-body { margin-bottom: 20px; }
      .mhf-prompt {
        text-align: center; font-size: 14px; color: #cbd5e1; line-height: 1.55;
        margin-bottom: 16px;
      }
      .mhf-prompt strong { color: #f1f5f9; font-weight: 600; }

      .mhf-meta {
        background: rgba(0,0,0,0.22); border-radius: 12px; padding: 12px 14px;
        border: 1px solid rgba(255,255,255,0.04);
      }
      .mhf-meta-row {
        display: flex; justify-content: space-between; align-items: center;
        padding: 5px 0; font-size: 12.5px;
      }
      .mhf-meta-row + .mhf-meta-row { border-top: 1px solid rgba(255,255,255,0.05); }
      .mhf-label { color: rgba(148,163,184,0.7); font-weight: 500; text-transform: uppercase; letter-spacing: 0.5px; font-size: 10.5px; }
      .mhf-value { color: #e2e8f0; font-weight: 500; font-family: 'SF Mono', 'Fira Code', monospace; font-size: 12px; }

      .mhf-actions { display: flex; flex-direction: column; gap: 8px; margin-bottom: 14px; }

      .mhf-btn {
        display: inline-flex; align-items: center; justify-content: center; gap: 8px;
        padding: 11px 18px; border-radius: 12px; font-size: 13.5px; font-weight: 600;
        cursor: pointer; border: none; transition: all 0.2s ease; font-family: inherit;
      }
      .mhf-btn-primary {
        background: linear-gradient(135deg, #0891b2, #3b82f6);
        color: #fff;
        box-shadow: 0 2px 12px rgba(6,182,212,0.3);
      }
      .mhf-btn-primary:hover {
        transform: translateY(-1px);
        box-shadow: 0 4px 20px rgba(6,182,212,0.4);
        filter: brightness(1.1);
      }
      .mhf-btn-primary:active { transform: translateY(0); }
      .mhf-btn-primary:disabled { opacity: 0.6; cursor: not-allowed; transform: none; }

      .mhf-btn-ghost {
        background: rgba(255,255,255,0.04); color: rgba(148,163,184,0.8);
        border: 1px solid rgba(255,255,255,0.06);
      }
      .mhf-btn-ghost:hover { background: rgba(255,255,255,0.08); color: #cbd5e1; }

      .mhf-footer {
        text-align: center; font-size: 10px; color: rgba(100,116,139,0.7);
        letter-spacing: 0.3px;
      }

      .mhf-feedback {
        display: flex; align-items: center; justify-content: center; gap: 10px;
        padding: 32px 16px; font-size: 15px; font-weight: 600;
      }
      .mhf-feedback-success { color: #34d399; }
      .mhf-feedback-error { color: #f87171; }
      .mhf-feedback-icon { font-size: 28px; }
    `;
  }

  // ─── MutationObserver for SPAs ────────────────────────────────────
  const observer = new MutationObserver(() => scanForLoginForms());
  observer.observe(document.documentElement, { childList: true, subtree: true });

  // Initial scan
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", scanForLoginForms);
  } else {
    scanForLoginForms();
  }
})();
