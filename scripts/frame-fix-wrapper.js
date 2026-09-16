// Superhuman Linux Frame Fix Wrapper
// Intercepts Electron's BrowserWindow to force native window frames on Linux
// OAuth popups use a browser User-Agent; the app itself keeps Electron's native identity
const Module = require('module');
const originalRequire = Module.prototype.require;

console.log('[Superhuman Frame Fix] Wrapper loaded');

// OAuth providers expect a browser User-Agent, while Superhuman's own pages
// require the native Superhuman and Electron tokens in Electron's default one.
const WINDOWS_USER_AGENT = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

Module.prototype.require = function(id) {
  const module = originalRequire.apply(this, arguments);

  if (id === 'electron') {
    console.log('[Superhuman Frame Fix] Intercepting electron module');
    const OriginalBrowserWindow = module.BrowserWindow;
    const OriginalMenu = module.Menu;

    if (module.app && process.platform === 'linux') {
      // OAuth popup windows created via window.open() don't go through our BrowserWindow
      // constructor - they're created internally by Chromium when setWindowOpenHandler
      // returns { action: "allow" }. We need to intercept these and set their User-Agent.
      // Track if we've already set up the handler to avoid duplicates
      if (!module.app._oauthPopupHandlerInstalled) {
        module.app._oauthPopupHandlerInstalled = true;

        module.app.on('web-contents-created', (event, webContents) => {
          // Listen for popup windows created from this webContents
          webContents.on('did-create-window', (newWindow) => {
            console.log('[Superhuman Frame Fix] Popup window created');

            // Set Windows User-Agent on the popup window's webContents
            // This ensures OAuth pages see a Windows browser
            try {
              newWindow.webContents.setUserAgent(WINDOWS_USER_AGENT);
              console.log('[Superhuman Frame Fix] Popup User-Agent set to Windows Chrome');
            } catch (e) {
              console.log('[Superhuman Frame Fix] Failed to set popup User-Agent:', e.message);
            }
          });
        });

        console.log('[Superhuman Frame Fix] OAuth popup handler installed');
      }
    }

    module.BrowserWindow = class BrowserWindowWithFrame extends OriginalBrowserWindow {
      constructor(options) {
        console.log('[Superhuman Frame Fix] BrowserWindow constructor called');
        if (process.platform === 'linux') {
          options = options || {};

          // Store original values for logging
          const originalFrame = options.frame;
          const originalTitleBarStyle = options.titleBarStyle;

          // Force native window frame on Linux
          options.frame = true;

          // Remove macOS/Windows-specific titlebar options
          // Superhuman uses titleBarStyle: 'hidden' which doesn't work well on Linux
          delete options.titleBarStyle;
          delete options.titleBarOverlay;

          // Hide the menu bar by default (Alt key will toggle it)
          options.autoHideMenuBar = true;

          console.log(`[Superhuman Frame Fix] Modified window options:`);
          console.log(`  frame: ${originalFrame} -> true`);
          console.log(`  titleBarStyle: ${originalTitleBarStyle} -> removed`);
        }
        super(options);

        // Hide menu bar after window creation on Linux
        if (process.platform === 'linux') {
          this.setMenuBarVisibility(false);
          console.log('[Superhuman Frame Fix] Menu bar visibility set to false');
        }
      }
    };

    // Copy static methods and properties (but NOT prototype, that's already set by extends)
    for (const key of Object.getOwnPropertyNames(OriginalBrowserWindow)) {
      if (key !== 'prototype' && key !== 'length' && key !== 'name') {
        try {
          const descriptor = Object.getOwnPropertyDescriptor(OriginalBrowserWindow, key);
          if (descriptor) {
            Object.defineProperty(module.BrowserWindow, key, descriptor);
          }
        } catch (e) {
          // Ignore errors for non-configurable properties
        }
      }
    }

    // Intercept Menu.setApplicationMenu to hide menu bar on Linux
    // This catches the app's later calls to setApplicationMenu that would show the menu
    const originalSetAppMenu = OriginalMenu.setApplicationMenu.bind(OriginalMenu);
    module.Menu.setApplicationMenu = function(menu) {
      console.log('[Superhuman Frame Fix] Intercepting setApplicationMenu');
      originalSetAppMenu(menu);
      if (process.platform === 'linux') {
        // Hide menu bar on all existing windows after menu is set
        for (const win of module.BrowserWindow.getAllWindows()) {
          win.setMenuBarVisibility(false);
        }
        console.log('[Superhuman Frame Fix] Menu bar hidden on all windows');
      }
    };

    // Intercept shell.openExternal to handle OAuth URLs in an internal window
    // This is needed because Superhuman's website checks User-Agent and blocks Linux
    if (module.shell && process.platform === 'linux') {
      const originalOpenExternal = module.shell.openExternal.bind(module.shell);

      // OAuth URL patterns that need User-Agent spoofing
      const OAUTH_PATTERNS = [
        'accounts.google.com',
        'login.microsoftonline.com',
        'mail.superhuman.com/api/auth',
        'mail.superhuman.com/~login',
        'superhuman.com/api/auth',
      ];

      module.shell.openExternal = async function(url, options) {
        const isOAuthUrl = OAUTH_PATTERNS.some(pattern => url.includes(pattern));

        if (isOAuthUrl) {
          console.log('[Superhuman Frame Fix] Intercepting OAuth URL');

          // Create a new window with spoofed User-Agent for OAuth
          const oauthWindow = new module.BrowserWindow({
            width: 600,
            height: 700,
            title: 'Sign in',
            webPreferences: {
              nodeIntegration: false,
              contextIsolation: true,
            }
          });

          // Set Windows User-Agent on this window's session
          oauthWindow.webContents.setUserAgent(WINDOWS_USER_AGENT);

          // Handle the OAuth callback - when it redirects to superhuman://
          oauthWindow.webContents.on('will-navigate', (event, navUrl) => {
            if (navUrl.startsWith('superhuman:') || navUrl.startsWith('superhuman-app:')) {
              console.log('[Superhuman Frame Fix] OAuth callback detected');
              event.preventDefault();
              oauthWindow.close();
              // Emit the URL to the app's protocol handler
              module.app.emit('open-url', event, navUrl);
            }
          });

          // Also handle redirects
          oauthWindow.webContents.on('will-redirect', (event, navUrl) => {
            if (navUrl.startsWith('superhuman:') || navUrl.startsWith('superhuman-app:')) {
              console.log('[Superhuman Frame Fix] OAuth redirect detected');
              event.preventDefault();
              oauthWindow.close();
              module.app.emit('open-url', event, navUrl);
            }
          });

          oauthWindow.loadURL(url);
          return;
        }

        // For non-OAuth URLs, use the original behavior
        return originalOpenExternal(url, options);
      };

      console.log('[Superhuman Frame Fix] shell.openExternal patched for OAuth');
    }
  }

  return module;
};
