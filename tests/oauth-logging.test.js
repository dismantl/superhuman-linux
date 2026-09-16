const assert = require('node:assert/strict');
const { EventEmitter } = require('node:events');
const Module = require('node:module');
const test = require('node:test');

test('Native app identity is preserved while OAuth URLs stay out of wrapper logs', async () => {
  const originalRequire = Module.prototype.require;
  const originalLog = console.log;
  const logs = [];
  const windows = [];
  const externalUrls = [];
  const callbackUrls = [];

  class FakeBrowserWindow {
    constructor() {
      this.webContents = new EventEmitter();
      this.webContents.setUserAgent = userAgent => { this.webContents.userAgent = userAgent; };
      windows.push(this);
    }

    setMenuBarVisibility() {}
    loadURL(url) { this.loadedUrl = url; }
    close() { this.closed = true; }
  }

  const app = new EventEmitter();
  app.isReady = () => true;
  app.on('open-url', (_event, url) => callbackUrls.push(url));
  const nativeUserAgent = 'Mozilla/5.0 Chrome/1.0 Electron/2.0 Superhuman/3.0';
  const defaultSession = {
    userAgent: nativeUserAgent,
    getUserAgent() { return this.userAgent; },
    setUserAgent(userAgent) { this.userAgent = userAgent; },
  };

  const electron = {
    app,
    BrowserWindow: FakeBrowserWindow,
    Menu: { setApplicationMenu() {} },
    session: { defaultSession },
    shell: {
      async openExternal(url) {
        externalUrls.push(url);
        return 'delegated';
      },
    },
  };

  Module.prototype.require = function(id) {
    if (id === 'electron') return electron;
    return originalRequire.apply(this, arguments);
  };
  console.log = (...args) => logs.push(args.join(' '));

  const wrapperPath = require.resolve('../scripts/frame-fix-wrapper.js');
  try {
    delete require.cache[wrapperPath];
    require(wrapperPath);
    require('electron');
    assert.equal(defaultSession.getUserAgent(), nativeUserAgent);

    const popupUrl = 'https://accounts.google.com/o/oauth2/auth?redirect_uri=superhuman%3A%2F%2Fsecret-popup';
    const source = new EventEmitter();
    const popupWindow = new FakeBrowserWindow();
    app.emit('web-contents-created', {}, source);
    source.emit('did-create-window', popupWindow, { url: popupUrl });
    assert.match(popupWindow.webContents.userAgent, /Windows NT/);
    assert.doesNotMatch(popupWindow.webContents.userAgent, /Electron|Superhuman/);

    const authUrl = 'https://accounts.google.com/o/oauth2/auth?state=secret-state';
    await electron.shell.openExternal(authUrl);
    const oauthWindow = windows.at(-1);
    assert.equal(oauthWindow.loadedUrl, authUrl);
    assert.match(oauthWindow.webContents.userAgent, /Windows NT/);
    assert.doesNotMatch(oauthWindow.webContents.userAgent, /Electron|Superhuman/);

    const callbackUrl = 'superhuman://auth/callback?code=secret-code#access_token=secret-fragment';
    for (const eventName of ['will-navigate', 'will-redirect']) {
      let prevented = false;
      oauthWindow.webContents.emit(eventName, { preventDefault() { prevented = true; } }, callbackUrl);
      assert.equal(prevented, true);
    }
    assert.deepEqual(callbackUrls, [callbackUrl, callbackUrl]);

    const nonOauthUrl = 'https://example.com/help';
    assert.equal(await electron.shell.openExternal(nonOauthUrl), 'delegated');
    assert.deepEqual(externalUrls, [nonOauthUrl]);

    const output = logs.join('\n');
    for (const secret of ['secret-popup', 'secret-state', 'secret-code', 'secret-fragment']) {
      assert.equal(output.includes(secret), false, `logged ${secret}`);
    }
    assert.match(output, /OAuth callback detected/);
    assert.match(output, /OAuth redirect detected/);
  } finally {
    Module.prototype.require = originalRequire;
    console.log = originalLog;
    delete require.cache[wrapperPath];
  }
});
