#!/usr/bin/env bash
# Common launcher functions for Superhuman (AppImage and deb)
# This file is sourced by both launchers to avoid code duplication

# Setup logging directory and file
# Sets: log_dir, log_file
setup_logging() {
	log_dir="${XDG_CACHE_HOME:-$HOME/.cache}/superhuman"
	mkdir -p "$log_dir" || return 1
	chmod 700 "$log_dir" || return 1
	log_file="$log_dir/launcher.log"
	(umask 077; : >> "$log_file") || return 1
	chmod 600 "$log_file" || return 1
}

# Log a message to the log file
# Usage: log_message "message"
log_message() {
	echo "$1" >> "$log_file"
}

# Detect display backend (Wayland vs X11)
# Sets: is_wayland, use_x11_on_wayland
detect_display_backend() {
	# Detect if Wayland is running
	is_wayland=false
	[[ -n $WAYLAND_DISPLAY ]] && is_wayland=true

	# Default: Use X11/XWayland on Wayland for compatibility
	# Set SUPERHUMAN_USE_WAYLAND=1 to use native Wayland
	use_x11_on_wayland=true
	[[ $SUPERHUMAN_USE_WAYLAND == '1' ]] && use_x11_on_wayland=false
}

# Check if we have a valid display (not running from TTY)
# Returns: 0 if display available, 1 if not
check_display() {
	[[ -n $DISPLAY || -n $WAYLAND_DISPLAY ]]
}

# An AppArmor user namespace grant can apply to unshare but not the AppImage's
# Electron binary. Treat a host-wide restriction as incompatible with AppImage.
appimage_apparmor_userns_restricted() {
	local setting=/proc/sys/kernel/apparmor_restrict_unprivileged_userns
	[[ -r $setting && $(< "$setting") == 1 ]]
}

# Build Electron arguments array based on display backend
# Requires: is_wayland, use_x11_on_wayland to be set
#           (call detect_display_backend first)
# Sets: electron_args array
# Arguments: $1 = "appimage" or "deb"
build_electron_args() {
	local package_type="${1:-deb}"

	electron_args=()

	# FUSE mounts cannot use Electron's bundled setuid helper. A successful
	# unshare probe is insufficient when AppArmor restricts the Electron path.
	if [[ $package_type == 'appimage' ]] && \
		{ appimage_apparmor_userns_restricted || ! command -v unshare > /dev/null 2>&1 || ! unshare --user --map-root-user true > /dev/null 2>&1; }; then
		log_message 'AppImage user namespace sandbox unavailable; Chromium sandbox disabled'
		echo 'Warning: AppImage user namespace sandbox unavailable; launching without the Chromium sandbox.' >&2
		electron_args+=('--no-sandbox')
	fi

	# Disable CustomTitlebar for better Linux integration
	electron_args+=('--disable-features=CustomTitlebar')

	# X11 session - no special flags needed
	if [[ $is_wayland != true ]]; then
		log_message 'X11 session detected'
		return
	fi

	if [[ $use_x11_on_wayland == true ]]; then
		# Default: Use X11 via XWayland for compatibility
		log_message 'Using X11 backend via XWayland'
		electron_args+=('--ozone-platform=x11')
	else
		# Native Wayland mode (user opted in via SUPERHUMAN_USE_WAYLAND=1)
		log_message 'Using native Wayland backend'
		electron_args+=('--enable-features=UseOzonePlatform,WaylandWindowDecorations')
		electron_args+=('--ozone-platform=wayland')
		electron_args+=('--enable-wayland-ime')
		electron_args+=('--wayland-text-input-version=3')
	fi
}

# Set common environment variables
setup_electron_env() {
	export ELECTRON_FORCE_IS_PACKAGED=true
	export ELECTRON_USE_SYSTEM_TITLE_BAR=1
	# Force production mode - electron-is-dev checks for node_modules/electron in path
	# which matches our AppImage/deb structure and incorrectly triggers dev mode
	export ELECTRON_IS_DEV=0
}
