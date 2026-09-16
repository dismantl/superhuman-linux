# Superhuman for Linux

An unofficial Linux port of [Superhuman](https://superhuman.com/), the fastest email experience ever made.

This project repackages the official Windows version of Superhuman for Debian-based Linux distributions, producing either `.deb` packages or AppImages.

**Note:** This is an unofficial build script. For official support, please visit [Superhuman's website](https://superhuman.com/). For issues with the build script or Linux implementation, please [open an issue](https://github.com/dismantl/superhuman-linux/issues) in this repository.

## Features

- **Native Linux Support**: Run Superhuman without virtualization or Wine
- **Native Window Frames**: Uses GTK window decorations for proper Linux desktop integration
- **System Integration**:
  - Desktop environment integration
  - Protocol handlers for `superhuman://` and `mailto:` URLs
  - Application icons in all standard sizes

## Installation

### Using Pre-built Releases

Once the first release is published, download the latest amd64 `.deb` or `.AppImage` from the [Releases page](https://github.com/dismantl/superhuman-linux/releases). Until then, build from source using the instructions below.

### Building from Source

#### Prerequisites

- Debian-based Linux distribution (Debian, Ubuntu, Linux Mint, MX Linux, etc.)
- Git
- Node.js 22.12 or newer (the script downloads a local Node.js runtime if needed)
- Basic build tools (automatically installed by the script)

#### Build Instructions

```bash
# Clone the repository
git clone https://github.com/dismantl/superhuman-linux.git
cd superhuman-linux

# Build a .deb package (default)
./build.sh

# Build an AppImage
./build.sh --build appimage

# Build with custom options
./build.sh --build deb --clean no  # Keep intermediate files

# Build using a locally downloaded installer
./build.sh --exe /path/to/Superhuman.exe
```

The default amd64 build checks the downloaded installer against the SHA-512 pinned with its version before extracting it. `--exe` uses the local file you provide and skips that upstream checksum check.

#### Installing the Built Package

**For .deb packages:**
```bash
sudo apt install ./superhuman_VERSION_ARCHITECTURE.deb

# Or using dpkg:
sudo dpkg -i ./superhuman_VERSION_ARCHITECTURE.deb
sudo apt --fix-broken install  # If needed for dependencies
```

**For AppImages:**
```bash
# Make executable
chmod +x ./superhuman-*.AppImage

# Run directly
./superhuman-*.AppImage

# Or integrate with your system using Gear Lever
```

**Note:** AppImage login requires desktop integration for the `superhuman://` protocol handler. [Gear Lever](https://flathub.org/apps/it.mijorus.gearlever) can integrate the AppImage. To install it manually, download `superhuman-appimage.desktop` and `superhuman-appimage.png` from the same release (or use the files produced by a local build), then:

1. Edit the desktop file's `Exec=` line, replacing `/absolute/path/to/` with the absolute path to the directory containing your AppImage.
2. Install the desktop file and icon, then register the protocol handler:

   ```bash
   install -Dm644 superhuman-appimage.desktop ~/.local/share/applications/superhuman-appimage.desktop
   install -Dm644 superhuman-appimage.png ~/.local/share/icons/hicolor/256x256/apps/superhuman.png
   xdg-mime default superhuman-appimage.desktop x-scheme-handler/superhuman
   ```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SUPERHUMAN_USE_WAYLAND` | unset | Set to `1` to use native Wayland instead of XWayland. |

**Wayland Note:** By default, Superhuman uses X11 mode (via XWayland) on Wayland sessions for maximum compatibility:

```bash
# One-time launch in native Wayland mode
SUPERHUMAN_USE_WAYLAND=1 superhuman

# Or add to your environment permanently
export SUPERHUMAN_USE_WAYLAND=1
```

### Application Logs

Runtime logs are available at:
```
~/.cache/superhuman/launcher.log
```

Or check `$XDG_CACHE_HOME/superhuman/launcher.log` if you've customized XDG paths.

## Uninstallation

**For .deb packages:**
```bash
# Remove package
sudo dpkg -r superhuman

# Remove package and configuration
sudo dpkg -P superhuman
```

**For AppImages:**
1. Delete the `.AppImage` file
2. Remove the `.desktop` file from `~/.local/share/applications/`
3. If using Gear Lever, use its uninstall option

**Remove user configuration (both formats):**
```bash
rm -rf ~/.config/Superhuman
```

## Troubleshooting

### Window Scaling Issues

If the window doesn't scale correctly on first launch:
1. Close and restart the application
2. This allows the application to save display settings properly

### OAuth Login Not Working

If clicking login redirects don't open in Superhuman:

1. Verify the protocol handler is registered:
   ```bash
   xdg-mime query default x-scheme-handler/superhuman
   ```

2. For AppImages, ensure you've integrated with the desktop using Gear Lever or manually installed the `.desktop` file.

### AppImage Sandbox Warning

AppImages run with `--no-sandbox` due to Electron's chrome-sandbox requiring root privileges for unprivileged namespace creation. This is a known limitation of AppImage format with Electron applications.

For enhanced security, consider:
- Using the .deb package instead
- Running the AppImage within a separate sandbox (e.g., bubblewrap)
- Using Gear Lever's integrated AppImage management

## Technical Details

### How It Works

Superhuman is an Electron application distributed for Windows and macOS. This project:

1. Downloads the official Windows installer and verifies its pinned SHA-512 checksum
2. Extracts the NSIS installer to get the embedded 7z archive
3. Extracts the Electron app from the 7z archive
4. Injects a frame-fix wrapper to force native window frames on Linux
5. Replaces Windows Electron binaries with Linux versions
6. Packages as either:
   - **Debian package**: Standard system package with full integration
   - **AppImage**: Portable, self-contained executable

### Key Differences from Windows/macOS

- **Native window frames**: Superhuman uses `titleBarStyle: 'hidden'` on Windows/macOS for a custom titlebar. On Linux, this is replaced with native GTK window decorations.
- **macOS features disabled**: Features like "Move to Applications" and "Add to Dock" are not applicable on Linux.

### Automated Version Detection

A GitHub Actions workflow checks daily for new amd64 Superhuman releases:

1. Fetches version information from Superhuman's public update channel
2. Compares with the version in `build.sh`
3. If a new version is detected, updates the version in `build.sh` and dispatches CI to build the amd64 `.deb` and AppImage. CI creates the tag and publishes the release only after both packages are built.

The workflow can also be run manually from GitHub Actions. Fork owners must enable the scheduled workflow in their fork before daily checks will run. ARM64 packages are not published automatically because Superhuman's current update channel does not provide a working Windows ARM64 installer URL.

### Manual Updates

If you need to build with a specific version before the automation catches it:

1. **Use a local installer**: Download the latest installer from [superhuman.com/download](https://superhuman.com/download) and build with:
   ```bash
   ./build.sh --exe /path/to/Superhuman.exe
   ```

2. **Update the pinned version and checksum**: Run `python3 scripts/resolve-download-url.py amd64 --format release`, then update both `SUPERHUMAN_VERSION` and `SUPERHUMAN_AMD64_SHA512` in `build.sh` from its output.

## License

The build scripts in this repository are licensed under the MIT License (see [LICENSE-MIT](LICENSE-MIT)).

Superhuman is a product of Superhuman, Inc. This project is an unofficial port and is not affiliated with or endorsed by Superhuman, Inc.

## Contributing

Contributions are welcome! By submitting a contribution, you agree to license it under the same terms as this project.
