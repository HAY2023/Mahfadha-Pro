let ws = null;
let reconnectInterval = null;

function connectWebSocket() {
  if (ws && (ws.readyState === WebSocket.CONNECTING || ws.readyState === WebSocket.OPEN)) {
    return;
  }

  console.log("Attempting to connect to CipherVault Pro...");
  ws = new WebSocket("ws://127.0.0.1:8765");

  ws.onopen = () => {
    console.log("Connected to CipherVault Pro!");
    if (reconnectInterval) {
      clearInterval(reconnectInterval);
      reconnectInterval = null;
    }
  };

  ws.onmessage = (event) => {
    try {
      const data = JSON.parse(event.data);
      if (data.action === "inject" && data.username && data.password) {
        injectCredentials(data.username, data.password, data.totp);
      }
    } catch (e) {
      console.error("Failed to parse message from CipherVault Pro:", e);
    }
  };

  ws.onclose = () => {
    console.log("Disconnected from CipherVault Pro. Retrying in 3 seconds...");
    scheduleReconnect();
  };

  ws.onerror = (err) => {
    console.error("WebSocket error:", err);
    ws.close();
  };
}

function scheduleReconnect() {
  if (!reconnectInterval) {
    reconnectInterval = setInterval(connectWebSocket, 3000);
  }
}

function injectCredentials(username, password, totp) {
  chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
    if (tabs.length === 0) return;
    const activeTab = tabs[0];

    chrome.scripting.executeScript({
      target: { tabId: activeTab.id },
      files: ["content.js"]
    }, () => {
      chrome.tabs.sendMessage(activeTab.id, {
        action: "fill_credentials",
        username: username,
        password: password,
        totp: totp
      });
    });
  });
}

// Initial connection
connectWebSocket();
