# Superhuman for Linux

An unofficial Linux port of [Superhuman](https://superhuman.com/), the fastest email experience ever made.

This project repackages the official Windows version of Superhuman for Debian-based Linux distributions, producing either `.deb` packages or AppImages.

**Note:** This is an unofficial build script. For official support, please visit [Superhuman's website](https://superhuman.com/). For issues with the build script or Linux implementation, please [open an issue](https://github.com/aaddrick/superhuman-linux/issues) in this repository.

## Features

- **Native Linux Support**: Run Superhuman without virtualization or Wine
- **Native Window Frames**: Uses GTK window decorations for proper Linux desktop integration
- **System Integration**:
  - Desktop environment integration
  - Protocol handlers for `superhuman://` and `mailto:` URLs
  - Application icons in all standard sizes

## Installation

### Using Pre-built Releases

Download the latest `.deb` or `.AppImage` from the [Releases page](https://github.com/aaddrick/superhuman-linux/releases).

### Building from Source

#### Prerequisites

- Debian-based Linux distribution (Debian, Ubuntu, Linux Mint, MX Linux, etc.)
- Git
- Basic build tools (automatically installed by the script)

#### Build Instructions

```bash
# Clone the repository
git clone https://github.com/aaddrick/superhuman-linux.git
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

**Note:** AppImage login requires proper desktop integration for the `superhuman://` protocol handler. Use [Gear Lever](https://flathub.org/apps/it.mijorus.gearlever) or manually install the provided `.desktop` file to `~/.local/share/applications/`.

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

1. Downloads the official Windows installer
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

A GitHub Actions workflow runs daily to check for new Superhuman releases:

1. Fetches version information from Superhuman's public update channel
2. Compares with the version in `build.sh`
3. If a new version is detected:
   - Updates `build.sh` with the new version
   - Creates a new release tag
   - Triggers automated builds for both architectures

This ensures the repository stays up-to-date with official releases automatically.

### Manual Updates

If you need to build with a specific version before the automation catches it:

1. **Use a local installer**: Download the latest installer from [superhuman.com/download](https://superhuman.com/download) and build with:
   ```bash
   ./build.sh --exe /path/to/Superhuman.exe
   ```

2. **Update the URL**: Modify the `superhuman_download_url` variables in `build.sh`.

## License

The build scripts in this repository are licensed under the MIT License (see [LICENSE-MIT](LICENSE-MIT)).

Superhuman is a product of Superhuman, Inc. This project is an unofficial port and is not affiliated with or endorsed by Superhuman, Inc.

## Contributing

Contributions are welcome! By submitting a contribution, you agree to license it under the same terms as this project.
