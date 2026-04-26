/**
 * Mahfadha Pro — Background Service Worker
 * Receives credentials from content script, forwards via Native Messaging,
 * then wipes all data from RAM immediately.
 */

const NATIVE_HOST_NAME = "com.mahfadha.bridge";
const blockedSites = new Set();

function sendToNativeApp(payload) {
  return new Promise((resolve, reject) => {
    try {
      chrome.runtime.sendNativeMessage(NATIVE_HOST_NAME, payload, (response) => {
        if (chrome.runtime.lastError) {
          reject(new Error(chrome.runtime.lastError.message));
        } else {
          resolve(response);
        }
      });
    } catch (err) {
      reject(err);
    }
  });
}

function secureWipe(obj) {
  if (!obj || typeof obj !== "object") return;
  for (const key of Object.keys(obj)) {
    if (typeof obj[key] === "string") {
      obj[key] = crypto.getRandomValues(new Uint8Array(obj[key].length))
        .reduce((acc, b) => acc + String.fromCharCode(b), "");
      obj[key] = null;
    }
    delete obj[key];
  }
}

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (!sender.tab) {
    sendResponse({ status: "error", reason: "Untrusted origin" });
    return false;
  }

  if (message.action === "SAVE_CREDENTIAL") {
    let payload = {
      cmd: "store_credential",
      url: message.data?.url || "",
      username: message.data?.username || "",
      password: message.data?.password || "",
      timestamp: new Date().toISOString(),
    };

    sendToNativeApp(payload)
      .then((nativeResponse) => {
        secureWipe(payload);
        payload = null;
        sendResponse({ status: "success", nativeResponse });
      })
      .catch((err) => {
        secureWipe(payload);
        payload = null;
        sendResponse({ status: "error", message: err.message });
      });

    return true; // async sendResponse
  }

  if (message.action === "BLOCK_SITE") {
    const hostname = message.data?.hostname;
    if (hostname) blockedSites.add(hostname);
    sendResponse({ status: "success", blocked: true });
    return false;
  }

  if (message.action === "CHECK_BLOCKED") {
    const hostname = message.data?.hostname;
    sendResponse({ blocked: blockedSites.has(hostname) });
    return false;
  }

  sendResponse({ status: "error", reason: "Unknown action" });
  return false;
});

chrome.runtime.onInstalled.addListener((details) => {
  if (details.reason === "install") {
    console.log("[Mahfadha Pro] Installed. Zero-storage mode active.");
  }
});
