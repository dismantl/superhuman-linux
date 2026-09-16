# Superhuman Linux - Development Notes

## Project Overview

This project repackages Superhuman (Electron app) for Debian/Ubuntu Linux, applying necessary patches for Linux compatibility.

## GitHub Workflow

### General Approach

- Use `gh` CLI for all GitHub interactions
- Create branches based on issue numbers: `fix/123-description` or `feature/123-description`
- Reference issues in commits and PRs with `#123` or `Fixes #123`
- After creating a PR, add a comment to the related issue with a summary and link to the PR

### Attribution

**For PR descriptions and issues**, include full attribution:

```
---
Generated with [Claude Code](https://claude.ai/code)
Co-Authored-By: Claude <model> <noreply@anthropic.com>
<XX>% AI / <YY>% Human
Claude: <what AI did>
Human: <what human did>
```

Example:
```
---
Generated with [Claude Code](https://claude.ai/code)
Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
85% AI / 15% Human
Claude: Implementation, testing, documentation
Human: Requirements, review, direction
```

**For commits**, include a Co-Authored-By trailer:

```
Co-Authored-By: Claude <claude@anthropic.com>
```

## Superhuman App Structure

### Key Differences from Claude Desktop

Unlike Claude Desktop, Superhuman's source code is **not minified**:

- Source files in `src/` are human-readable
- `dist/` contains bundled code but is still relatively readable
- No need for dynamic variable extraction or beautification

### Main Files

- `main.js` - Entry point, loads `./src/main.js`
- `src/main.js` - Application startup, window management
- `src/window.js` - BrowserWindow configuration
- `src/login_item.js` - macOS login items (not applicable on Linux)
- `src/config/` - Application configuration

### Platform-Specific Code

Most platform checks are already guarded:

```javascript
// Example from src/main.js
if (process.platform === "darwin") {
  // macOS-only code
}
```

These naturally skip on Linux, so minimal patching is needed.

## Frame Fix Wrapper

The app uses a wrapper system to intercept and fix Electron behavior for Linux:

- **`frame-fix-wrapper.js`** - Intercepts `require('electron')` to patch BrowserWindow defaults
- **`frame-fix-entry.js`** - Entry point that loads the wrapper before the main app

### What It Patches

Superhuman uses `titleBarStyle: 'hidden'` for a custom titlebar. The wrapper:

1. Removes `titleBarStyle` option on Linux
2. Forces `frame: true` for native GTK window decorations
3. Hides the menu bar by default (Alt key toggles it)

## Setting Up for Development

### Prerequisites

```bash
# Install required tools
sudo apt install p7zip-full wget nodejs npm icoutils imagemagick

# Install asar and prettier globally (or use npx)
npm install -g @electron/asar prettier
```

### Extracting the App (Already Done)

The app has been extracted to `extracted/app-64/resources/app/`:

```
extracted/
└── app-64/
    ├── Superhuman.exe          # Windows Electron binary
    └── resources/
        ├── app.asar            # Application archive
        └── app/                # Extracted source
            ├── main.js         # Entry point
            ├── package.json
            ├── src/            # Main process source
            ├── dist/           # Bundled renderer code
            ├── assets/         # Static assets
            └── node_modules/   # Dependencies
```

### Formatting Source Files

The source files have been formatted with prettier:

```bash
cd extracted/app-64/resources/app
npx prettier --write "src/**/*.js" "dist/**/*.js" "main.js"
```

## CI/CD

### Triggering Builds

```bash
# Trigger CI on a branch
gh workflow run CI --ref branch-name

# Watch the run
gh run watch RUN_ID

# Download artifacts
gh run download RUN_ID -n artifact-name
```

### Build Artifacts

- `superhuman-VERSION-amd64.deb` - Debian package for x86_64
- `superhuman-VERSION-amd64.AppImage` - AppImage for x86_64
- `superhuman-VERSION-arm64.deb` - Debian package for ARM64
- `superhuman-VERSION-arm64.AppImage` - AppImage for ARM64

## Testing

### Local Build

```bash
# Build with local exe (skip download)
./build.sh --exe ./Superhuman.exe --clean no

# Build AppImage
./build.sh --build appimage --clean no
```

### Testing the Built Package

```bash
# Test AppImage
./superhuman-*.AppImage 2>&1 | tee ~/.cache/superhuman/launcher.log

# Install and test .deb
sudo apt install ./superhuman_*.deb
superhuman
```

## Debugging

### Log Locations

- Launcher log: `~/.cache/superhuman/launcher.log`
- App logs: `~/.config/Superhuman/logs/` (if any)

### Inspecting the Running App

```bash
# Find the mounted AppImage path
mount | grep superhuman

# Extract for inspection
npx asar extract /tmp/.mount_superh*/usr/lib/node_modules/electron/dist/resources/app.asar /tmp/superhuman-inspect
```

## Common Gotchas

- **AppImage mount points** - Running AppImages mount to `/tmp/.mount_superh*`
- **Killing the app** - Must kill all electron child processes:
  ```bash
  pkill -9 -f "mount_superh"
  ```
- **SingletonLock** - If app won't start, check for stale lock: `~/.config/Superhuman/SingletonLock`
- **Node version** - Build requires Node.js 22.12+; the script downloads its own if needed
- **Version updates** - A GitHub Action automatically checks Superhuman's update channel and updates `build.sh` when new versions are detected

## Useful Commands

```bash
# Check current version in build.sh
grep '^readonly SUPERHUMAN_VERSION=' build.sh

# Fetch latest version from update channel
curl -s https://storage.googleapis.com/download.superhuman.com/native-update/latest.yml | grep version

# Run URL resolver
python scripts/resolve-download-url.py all --format both
```
