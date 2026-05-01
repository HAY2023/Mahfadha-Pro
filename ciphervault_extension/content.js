chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
  if (request.action === "fill_credentials") {
    fillCredentials(request.username, request.password);
    if (request.totp) {
      // Save TOTP for 2 minutes (120000 ms) in case the next page asks for it
      chrome.storage.local.set({ 
        ciphervault_totp: request.totp, 
        ciphervault_totp_expiry: Date.now() + 120000 
      });
    }
  }
});

// Auto-run on page load to check if there is a pending TOTP
chrome.storage.local.get(['ciphervault_totp', 'ciphervault_totp_expiry'], (result) => {
  if (result.ciphervault_totp && result.ciphervault_totp_expiry && Date.now() < result.ciphervault_totp_expiry) {
    injectTotpIfPossible(result.ciphervault_totp);
  }
});

function injectTotpIfPossible(totpCode) {
  // Look for common 2FA/TOTP input fields
  const totpInput = document.querySelector('input[name*="totp"], input[name*="code"], input[name*="auth"], input[name*="2fa"], input[id*="totp"], input[id*="code"], input[id*="auth"], input[id*="2fa"]');
  if (totpInput && totpInput.type !== "hidden") {
    simulateInput(totpInput, totpCode);
    console.log("CipherVault Pro: TOTP injected automatically.");
    // Clear it so we don't inject again randomly
    chrome.storage.local.remove(['ciphervault_totp', 'ciphervault_totp_expiry']);
  }
}

function fillCredentials(username, password) {
  // Find the password field
  const passwordInputs = document.querySelectorAll('input[type="password"]');
  if (passwordInputs.length === 0) {
    console.warn("CipherVault Pro: No password field found.");
    return;
  }
  
  // Assume the first password field is the correct one for login
  const passwordField = passwordInputs[0];
  
  // Find all text-like inputs
  const allInputs = Array.from(document.querySelectorAll('input:not([type="hidden"]):not([type="submit"]):not([type="button"]):not([type="checkbox"]):not([type="radio"])'));
  
  // Find the username field (usually the input immediately preceding the password field)
  const passwordIndex = allInputs.indexOf(passwordField);
  let usernameField = null;
  
  if (passwordIndex > 0) {
    usernameField = allInputs[passwordIndex - 1];
  } else {
    // Fallback: look for inputs with common username/email attributes
    usernameField = document.querySelector('input[name*="user"], input[name*="email"], input[name*="login"], input[id*="user"], input[id*="email"], input[id*="login"], input[type="email"]');
  }

  // Inject username
  if (usernameField && username) {
    simulateInput(usernameField, username);
  }

  // Inject password
  if (passwordField && password) {
    simulateInput(passwordField, password);
  }

  console.log("CipherVault Pro: Credentials injected successfully.");
}

function simulateInput(element, value) {
  // Focus the element
  element.focus();
  
  // Set the value directly
  element.value = value;
  
  // For React/Vue/Angular to pick up the change
  // React 15/16+ overrides the native setter, so we have to get the original setter
  const nativeInputValueSetter = Object.getOwnPropertyDescriptor(
    window.HTMLInputElement.prototype,
    "value"
  ).set;
  
  if (nativeInputValueSetter) {
    nativeInputValueSetter.call(element, value);
  }
  
  // Dispatch events to trigger JS frameworks
  element.dispatchEvent(new Event('input', { bubbles: true }));
  element.dispatchEvent(new Event('change', { bubbles: true }));
  
  // Blur the element
  element.blur();
}
