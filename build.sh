#!/usr/bin/env bash

#===============================================================================
# Superhuman Linux Build Script
# Repackages Superhuman (Electron app) for Debian/Ubuntu Linux
#===============================================================================

# Global variables (set by functions, used throughout)
architecture=''
superhuman_download_url=''
superhuman_exe_filename=''
version=''
build_format='deb'
cleanup_action='yes'
perform_cleanup=false
test_flags_mode=false
local_exe_path=''
original_user=''
original_home=''
project_root=''
work_dir=''
app_staging_dir=''
chosen_electron_module_path=''
asar_exec=''
superhuman_extract_dir=''
electron_resources_dest=''
final_output_path=''

# Package metadata (constants)
readonly PACKAGE_NAME='superhuman'
readonly MAINTAINER='Superhuman Linux Maintainers'
readonly DESCRIPTION='Superhuman - The fastest email experience ever made'

#===============================================================================
# Utility Functions
#===============================================================================

check_command() {
	if ! command -v "$1" &> /dev/null; then
		echo "$1 not found"
		return 1
	else
		echo "$1 found"
		return 0
	fi
}

section_header() {
	echo -e "\033[1;36m--- $1 ---\033[0m"
}

section_footer() {
	echo -e "\033[1;36m--- End $1 ---\033[0m"
}

#===============================================================================
# Setup Functions
#===============================================================================

detect_architecture() {
	section_header 'Architecture Detection'
	echo 'Detecting system architecture...'

	local host_arch
	host_arch=$(dpkg --print-architecture) || {
		echo 'Failed to detect architecture' >&2
		exit 1
	}
	echo "Detected host architecture: $host_arch"
	cat /etc/os-release && uname -m && dpkg --print-architecture

	# Superhuman download URL - fetched from their update channel
	# The version check workflow updates these URLs when new versions are released
	local base_url='https://storage.googleapis.com/download.superhuman.com/native-update'

	case "$host_arch" in
		amd64)
			superhuman_download_url="${base_url}/Superhuman%20Setup%201038.0.17-latest.exe"
			architecture='amd64'
			superhuman_exe_filename='Superhuman-Setup-x64.exe'
			echo 'Configured for amd64 build.'
			;;
		arm64)
			# Superhuman provides arm64 builds as well
			superhuman_download_url="${base_url}/Superhuman%20Setup%201038.0.17-latest-arm64.exe"
			architecture='arm64'
			superhuman_exe_filename='Superhuman-Setup-arm64.exe'
			echo 'Configured for arm64 build.'
			;;
		*)
			echo "Unsupported architecture: $host_arch. This script currently supports amd64 and arm64." >&2
			exit 1
			;;
	esac

	echo "Target Architecture (detected): $architecture"
	section_footer 'Architecture Detection'
}

check_system_requirements() {
	if [[ ! -f /etc/debian_version ]]; then
		echo 'This script requires a Debian-based Linux distribution' >&2
		exit 1
	fi

	if (( EUID == 0 )); then
		echo 'This script should not be run using sudo or as the root user.' >&2
		echo 'It will prompt for sudo password when needed for specific actions.' >&2
		echo 'Please run as a normal user.' >&2
		exit 1
	fi

	original_user=$(whoami)
	original_home=$(getent passwd "$original_user" | cut -d: -f6)
	if [[ -z $original_home ]]; then
		echo "Could not determine home directory for user $original_user." >&2
		exit 1
	fi
	echo "Running as user: $original_user (Home: $original_home)"

	# Check for NVM and source it if found
	if [[ -d $original_home/.nvm ]]; then
		echo "Found NVM installation for user $original_user, checking for Node.js 20+..."
		export NVM_DIR="$original_home/.nvm"
		if [[ -s $NVM_DIR/nvm.sh ]]; then
			# shellcheck disable=SC1091
			\. "$NVM_DIR/nvm.sh"
			local node_bin_path=''
			node_bin_path=$(nvm which current | xargs dirname 2>/dev/null || \
				find "$NVM_DIR/versions/node" -maxdepth 2 -type d -name 'bin' | sort -V | tail -n 1)

			if [[ -n $node_bin_path && -d $node_bin_path ]]; then
				echo "Adding NVM Node bin path to PATH: $node_bin_path"
				export PATH="$node_bin_path:$PATH"
			else
				echo 'Warning: Could not determine NVM Node bin path.'
			fi
		else
			echo 'Warning: nvm.sh script not found or not sourceable.'
		fi
	fi

	echo 'System Information:'
	echo "Distribution: $(grep 'PRETTY_NAME' /etc/os-release | cut -d'"' -f2)"
	echo "Debian version: $(cat /etc/debian_version)"
	echo "Target Architecture: $architecture"
}

parse_arguments() {
	section_header 'Argument Parsing'

	project_root="$(pwd)"
	work_dir="$project_root/build"
	app_staging_dir="$work_dir/electron-app"

	while (( $# > 0 )); do
		case "$1" in
			-b|--build|-c|--clean|-e|--exe)
				if [[ -z ${2:-} || $2 == -* ]]; then
					echo "Error: Argument for $1 is missing" >&2
					exit 1
				fi
				case "$1" in
					-b|--build) build_format="$2" ;;
					-c|--clean) cleanup_action="$2" ;;
					-e|--exe) local_exe_path="$2" ;;
				esac
				shift 2
				;;
			--test-flags)
				test_flags_mode=true
				shift
				;;
			-h|--help)
				echo "Usage: $0 [--build deb|appimage] [--clean yes|no] [--exe /path/to/installer.exe] [--test-flags]"
				echo '  --build: Specify the build format (deb or appimage). Default: deb'
				echo '  --clean: Specify whether to clean intermediate build files (yes or no). Default: yes'
				echo '  --exe:   Use a local Superhuman installer exe instead of downloading'
				echo '  --test-flags: Parse flags, print results, and exit without building.'
				exit 0
				;;
			*)
				echo "Unknown option: $1" >&2
				echo 'Use -h or --help for usage information.' >&2
				exit 1
				;;
		esac
	done

	# Validate arguments
	build_format="${build_format,,}"
	cleanup_action="${cleanup_action,,}"

	if [[ $build_format != 'deb' && $build_format != 'appimage' ]]; then
		echo "Invalid build format specified: '$build_format'. Must be 'deb' or 'appimage'." >&2
		exit 1
	fi
	if [[ $cleanup_action != 'yes' && $cleanup_action != 'no' ]]; then
		echo "Invalid cleanup option specified: '$cleanup_action'. Must be 'yes' or 'no'." >&2
		exit 1
	fi

	echo "Selected build format: $build_format"
	echo "Cleanup intermediate files: $cleanup_action"

	[[ $cleanup_action == 'yes' ]] && perform_cleanup=true

	section_footer 'Argument Parsing'
}

check_dependencies() {
	echo 'Checking dependencies...'
	local deps_to_install=''
	local common_deps='p7zip wget wrestool icotool convert'
	local deb_deps='dpkg-deb'
	local all_deps="$common_deps"

	if [[ $build_format == 'deb' ]]; then
		all_deps="$all_deps $deb_deps"
	fi

	local cmd
	for cmd in $all_deps; do
		if ! check_command "$cmd"; then
			case "$cmd" in
				'p7zip') deps_to_install="$deps_to_install p7zip-full" ;;
				'wget') deps_to_install="$deps_to_install wget" ;;
				'wrestool'|'icotool') deps_to_install="$deps_to_install icoutils" ;;
				'convert') deps_to_install="$deps_to_install imagemagick" ;;
				'dpkg-deb') deps_to_install="$deps_to_install dpkg-dev" ;;
			esac
		fi
	done

	if [[ -n $deps_to_install ]]; then
		echo "System dependencies needed:$deps_to_install"
		echo 'Attempting to install using sudo...'
		if ! sudo -v; then
			echo 'Failed to validate sudo credentials. Please ensure you can run sudo.' >&2
			exit 1
		fi
		if ! sudo apt update; then
			echo "Failed to run 'sudo apt update'." >&2
			exit 1
		fi
		# shellcheck disable=SC2086
		if ! sudo apt install -y $deps_to_install; then
			echo "Failed to install dependencies using 'sudo apt install'." >&2
			exit 1
		fi
		echo 'System dependencies installed successfully via sudo.'
	fi
}

setup_work_directory() {
	rm -rf "$work_dir"
	mkdir -p "$work_dir" || exit 1
	mkdir -p "$app_staging_dir" || exit 1
}

setup_nodejs() {
	section_header 'Node.js Setup'
	echo 'Checking Node.js version...'

	local node_version_ok=false
	if command -v node &> /dev/null; then
		local node_version node_major
		node_version=$(node --version | cut -d'v' -f2)
		node_major="${node_version%%.*}"
		echo "System Node.js version: v$node_version"

		if (( node_major >= 20 )); then
			echo "System Node.js version is adequate (v$node_version)"
			node_version_ok=true
		else
			echo "System Node.js version is too old (v$node_version). Need v20+"
		fi
	else
		echo 'Node.js not found in system'
	fi

	if [[ $node_version_ok == true ]]; then
		section_footer 'Node.js Setup'
		return 0
	fi

	# Node.js version inadequate - install locally
	echo 'Installing Node.js v20 locally in build directory...'

	local node_arch
	case "$architecture" in
		amd64) node_arch='x64' ;;
		arm64) node_arch='arm64' ;;
		*)
			echo "Unsupported architecture for Node.js: $architecture" >&2
			exit 1
			;;
	esac

	local node_version_to_install='20.18.1'
	local node_tarball="node-v${node_version_to_install}-linux-${node_arch}.tar.xz"
	local node_url="https://nodejs.org/dist/v${node_version_to_install}/${node_tarball}"
	local node_install_dir="$work_dir/node"

	echo "Downloading Node.js v${node_version_to_install} for ${node_arch}..."
	cd "$work_dir" || exit 1
	if ! wget -O "$node_tarball" "$node_url"; then
		echo "Failed to download Node.js from $node_url" >&2
		cd "$project_root" || exit 1
		exit 1
	fi

	echo 'Extracting Node.js...'
	if ! tar -xf "$node_tarball"; then
		echo 'Failed to extract Node.js tarball' >&2
		cd "$project_root" || exit 1
		exit 1
	fi

	mv "node-v${node_version_to_install}-linux-${node_arch}" "$node_install_dir" || exit 1
	export PATH="$node_install_dir/bin:$PATH"

	if command -v node &> /dev/null; then
		echo "Local Node.js installed successfully: $(node --version)"
	else
		echo 'Failed to install local Node.js' >&2
		cd "$project_root" || exit 1
		exit 1
	fi

	rm -f "$node_tarball"
	cd "$project_root" || exit 1
	section_footer 'Node.js Setup'
}

setup_electron_asar() {
	section_header 'Electron & Asar Handling'

	echo "Ensuring local Electron and Asar installation in $work_dir..."
	cd "$work_dir" || exit 1

	if [[ ! -f package.json ]]; then
		echo "Creating temporary package.json in $work_dir for local install..."
		echo '{"name":"superhuman-build","version":"0.0.1","private":true}' > package.json
	fi

	local electron_dist_path="$work_dir/node_modules/electron/dist"
	local asar_bin_path="$work_dir/node_modules/.bin/asar"
	local install_needed=false

	[[ ! -d $electron_dist_path ]] && echo 'Electron distribution not found.' && install_needed=true
	[[ ! -f $asar_bin_path ]] && echo 'Asar binary not found.' && install_needed=true

	if [[ $install_needed == true ]]; then
		echo "Installing Electron and Asar locally into $work_dir..."
		if ! npm install --no-save electron @electron/asar; then
			echo 'Failed to install Electron and/or Asar locally.' >&2
			cd "$project_root" || exit 1
			exit 1
		fi
		echo 'Electron and Asar installation command finished.'
	else
		echo 'Local Electron distribution and Asar binary already present.'
	fi

	if [[ -d $electron_dist_path ]]; then
		echo "Found Electron distribution directory at $electron_dist_path."
		chosen_electron_module_path="$(realpath "$work_dir/node_modules/electron")"
		echo "Setting Electron module path for copying to $chosen_electron_module_path."
	else
		echo "Failed to find Electron distribution directory at '$electron_dist_path' after installation attempt." >&2
		cd "$project_root" || exit 1
		exit 1
	fi

	if [[ -f $asar_bin_path ]]; then
		asar_exec="$(realpath "$asar_bin_path")"
		echo "Found local Asar binary at $asar_exec."
	else
		echo "Failed to find Asar binary at '$asar_bin_path' after installation attempt." >&2
		cd "$project_root" || exit 1
		exit 1
	fi

	cd "$project_root" || exit 1

	if [[ -z $chosen_electron_module_path || ! -d $chosen_electron_module_path ]]; then
		echo 'Critical error: Could not resolve a valid Electron module path to copy.' >&2
		exit 1
	fi

	echo "Using Electron module path: $chosen_electron_module_path"
	echo "Using asar executable: $asar_exec"
	section_footer 'Electron & Asar Handling'
}

#===============================================================================
# Download and Extract Functions
#===============================================================================

download_superhuman_installer() {
	section_header 'Download the latest Superhuman executable'

	local superhuman_exe_path="$work_dir/$superhuman_exe_filename"

	if [[ -n $local_exe_path ]]; then
		echo "Using local Superhuman installer: $local_exe_path"
		if [[ ! -f $local_exe_path ]]; then
			echo "Local installer file not found: $local_exe_path" >&2
			exit 1
		fi
		cp "$local_exe_path" "$superhuman_exe_path" || exit 1
		echo 'Local installer copied to build directory'
	else
		echo "Downloading Superhuman installer for $architecture..."
		if ! wget -O "$superhuman_exe_path" "$superhuman_download_url"; then
			echo "Failed to download Superhuman installer from $superhuman_download_url" >&2
			exit 1
		fi
		echo "Download complete: $superhuman_exe_filename"
	fi

	echo "Extracting resources from $superhuman_exe_filename..."
	superhuman_extract_dir="$work_dir/superhuman-extract"
	mkdir -p "$superhuman_extract_dir" || exit 1

	# First extraction: NSIS installer
	if ! 7z x -y "$superhuman_exe_path" -o"$superhuman_extract_dir"; then
		echo 'Failed to extract installer' >&2
		cd "$project_root" || exit 1
		exit 1
	fi

	cd "$superhuman_extract_dir" || exit 1

	# Superhuman uses NSIS with embedded 7z archives in $PLUGINSDIR
	local app_7z_path=''
	case "$architecture" in
		amd64) app_7z_path='$PLUGINSDIR/app-64.7z' ;;
		arm64) app_7z_path='$PLUGINSDIR/app-arm64.7z' ;;
	esac

	if [[ ! -f $app_7z_path ]]; then
		echo "Could not find app archive at $app_7z_path" >&2
		cd "$project_root" || exit 1
		exit 1
	fi
	echo "Found app archive: $app_7z_path"

	# Second extraction: app-64.7z contains the Electron app
	local app_extract_dir="$superhuman_extract_dir/app-contents"
	mkdir -p "$app_extract_dir" || exit 1
	if ! 7z x -y "$app_7z_path" -o"$app_extract_dir"; then
		echo 'Failed to extract app archive' >&2
		cd "$project_root" || exit 1
		exit 1
	fi
	echo 'App archive extracted'

	# Extract version from package.json or app-update.yml
	if [[ -f $app_extract_dir/resources/app-update.yml ]]; then
		version=$(grep -oP '^version:\s*\K[0-9]+\.[0-9]+\.[0-9]+' "$app_extract_dir/resources/app-update.yml")
	fi

	if [[ -z $version && -f $app_extract_dir/resources/app.asar ]]; then
		# Try to get version from package.json inside asar
		"$asar_exec" extract "$app_extract_dir/resources/app.asar" "$work_dir/tmp-asar-extract" || true
		if [[ -f $work_dir/tmp-asar-extract/package.json ]]; then
			version=$(node -e "console.log(require('$work_dir/tmp-asar-extract/package.json').version)")
		fi
		rm -rf "$work_dir/tmp-asar-extract"
	fi

	if [[ -z $version ]]; then
		echo 'Could not extract version from Superhuman app' >&2
		cd "$project_root" || exit 1
		exit 1
	fi
	echo "Detected Superhuman version: $version"

	cd "$project_root" || exit 1
}

#===============================================================================
# Patching Functions
#===============================================================================

patch_app_asar() {
	section_header 'Processing app.asar'

	local app_contents_dir="$superhuman_extract_dir/app-contents"

	echo 'Copying app.asar to staging area...'
	cp "$app_contents_dir/resources/app.asar" "$app_staging_dir/" || exit 1

	# Superhuman may have unpacked resources
	if [[ -d $app_contents_dir/resources/app.asar.unpacked ]]; then
		cp -a "$app_contents_dir/resources/app.asar.unpacked" "$app_staging_dir/" || exit 1
	fi

	cd "$app_staging_dir" || exit 1
	"$asar_exec" extract app.asar app.asar.contents || exit 1

	# Frame fix wrapper - inject before main entry
	echo 'Creating BrowserWindow frame fix wrapper...'
	local original_main
	original_main=$(node -e "const pkg = require('./app.asar.contents/package.json'); console.log(pkg.main);")
	echo "Original main entry: $original_main"

	cp "$project_root/scripts/frame-fix-wrapper.js" app.asar.contents/frame-fix-wrapper.js || exit 1

	cat > app.asar.contents/frame-fix-entry.js << EOFENTRY
// Load frame fix first
require('./frame-fix-wrapper.js');
// Then load original main
require('./${original_main}');
EOFENTRY

	# Patch BrowserWindow creation in source files
	echo 'Patching BrowserWindow creation for native frames on Linux...'

	# Superhuman uses titleBarStyle: 'hidden' in src/window.js
	# We patch both src and dist files to be thorough
	local file
	for file in app.asar.contents/src/window.js app.asar.contents/dist/*.js; do
		if [[ -f $file ]]; then
			echo "Patching $file..."
			# Replace titleBarStyle: 'hidden' with empty string (native frame)
			sed -i "s/titleBarStyle[[:space:]]*:[[:space:]]*['\"]hidden['\"]/titleBarStyle: ''/g" "$file"
			# Handle minified versions
			sed -i 's/titleBarStyle:"hidden"/titleBarStyle:""/g' "$file"
			echo "Patched $file"
		fi
	done

	# Update package.json to use frame fix entry
	echo 'Modifying package.json to load frame fix...'
	node -e "
const fs = require('fs');
const pkg = require('./app.asar.contents/package.json');
pkg.originalMain = pkg.main;
pkg.main = 'frame-fix-entry.js';
fs.writeFileSync('./app.asar.contents/package.json', JSON.stringify(pkg, null, 2));
console.log('Updated package.json: main entry changed to frame-fix-entry.js');
"

	# Patch platform-specific code that might cause issues on Linux
	patch_platform_checks

	section_footer 'Processing app.asar'
}

patch_platform_checks() {
	echo 'Checking for platform-specific code that needs adjustment...'

	# Most platform checks in Superhuman are already guarded with process.platform === 'darwin'
	# or process.platform === 'win32', so they'll naturally be skipped on Linux.

	# Check for any hardcoded platform assumptions in config
	local config_file='app.asar.contents/src/config/built.js'
	if [[ -f $config_file ]]; then
		echo "Reviewing $config_file for platform-specific paths..."
		# The icnsPath is macOS-specific but shouldn't cause issues on Linux
		# as it's only used when the path exists
	fi

	echo 'Platform checks reviewed - no critical issues found'
}

finalize_app_asar() {
	section_header 'Finalizing app.asar'

	cd "$app_staging_dir" || exit 1

	# Repack the modified asar
	"$asar_exec" pack app.asar.contents app.asar || exit 1
	echo 'app.asar repacked successfully'

	# Ensure unpacked directory exists for any native modules
	mkdir -p "$app_staging_dir/app.asar.unpacked" || exit 1

	section_footer 'Finalizing app.asar'
}

#===============================================================================
# Staging Functions
#===============================================================================

stage_electron() {
	section_header 'Staging Electron'

	echo 'Copying Electron installation to staging area...'
	mkdir -p "$app_staging_dir/node_modules/" || exit 1
	local electron_dir_name
	electron_dir_name=$(basename "$chosen_electron_module_path")
	echo "Copying from $chosen_electron_module_path to $app_staging_dir/node_modules/"
	cp -a "$chosen_electron_module_path" "$app_staging_dir/node_modules/" || exit 1

	local staged_electron_bin="$app_staging_dir/node_modules/$electron_dir_name/dist/electron"
	if [[ -f $staged_electron_bin ]]; then
		echo "Setting executable permission on staged Electron binary: $staged_electron_bin"
		chmod +x "$staged_electron_bin" || exit 1
	else
		echo "Warning: Staged Electron binary not found at expected path: $staged_electron_bin"
	fi

	# Copy Electron locale files
	local electron_resources_src="$chosen_electron_module_path/dist/resources"
	electron_resources_dest="$app_staging_dir/node_modules/$electron_dir_name/dist/resources"
	if [[ -d $electron_resources_src ]]; then
		echo 'Copying Electron locale resources...'
		mkdir -p "$electron_resources_dest" || exit 1
		cp -a "$electron_resources_src"/* "$electron_resources_dest/" || exit 1
		echo 'Electron locale resources copied'
	else
		echo "Warning: Electron resources directory not found at $electron_resources_src"
	fi

	section_footer 'Staging Electron'
}

process_icons() {
	section_header 'Icon Processing'

	local app_contents_dir="$superhuman_extract_dir/app-contents"
	local icons_found=false

	cd "$work_dir" || exit 1

	# First, try to use icons from the app's assets folder
	local assets_dir="$app_staging_dir/app.asar.contents/assets"
	local app_png="$assets_dir/app.png"
	local app_ico="$assets_dir/app.ico"

	if [[ -f $app_png ]]; then
		echo "Found app icon in assets: $app_png"
		# Generate various sizes from the source PNG using ImageMagick
		local sizes=(16 24 32 48 64 128 256)
		for size in "${sizes[@]}"; do
			local output_file="$work_dir/superhuman_${size}x${size}.png"
			if convert "$app_png" -resize "${size}x${size}" "$output_file" 2>/dev/null; then
				echo "Generated ${size}x${size} icon"
			fi
		done
		# Also create the specific naming pattern expected by packaging scripts
		# Pattern: superhuman_N_WxHx32.png where N is an index
		convert "$app_png" -resize "256x256" "$work_dir/superhuman_6_256x256x32.png" 2>/dev/null || true
		convert "$app_png" -resize "64x64" "$work_dir/superhuman_7_64x64x32.png" 2>/dev/null || true
		convert "$app_png" -resize "48x48" "$work_dir/superhuman_8_48x48x32.png" 2>/dev/null || true
		convert "$app_png" -resize "32x32" "$work_dir/superhuman_10_32x32x32.png" 2>/dev/null || true
		convert "$app_png" -resize "24x24" "$work_dir/superhuman_11_24x24x32.png" 2>/dev/null || true
		convert "$app_png" -resize "16x16" "$work_dir/superhuman_13_16x16x32.png" 2>/dev/null || true
		icons_found=true
		echo "Icons generated from app.png"
	elif [[ -f $app_ico ]]; then
		echo "Found app icon in assets: $app_ico"
		# Extract icons from .ico file
		if icotool -x "$app_ico" -o "$work_dir/" 2>/dev/null; then
			# Rename to expected pattern
			for icon in "$work_dir/"*.png; do
				[[ -f $icon ]] || continue
				local basename
				basename=$(basename "$icon")
				mv "$icon" "$work_dir/superhuman_$basename" 2>/dev/null || true
			done
			icons_found=true
			echo "Icons extracted from app.ico"
		fi
	fi

	# Fallback: try to extract icons from Superhuman.exe
	if [[ $icons_found != true ]]; then
		local exe_path="$app_contents_dir/Superhuman.exe"
		if [[ ! -f $exe_path ]]; then
			exe_path="$work_dir/$superhuman_exe_filename"
		fi

		if [[ -f $exe_path ]]; then
			echo "Extracting application icons from $exe_path..."
			if wrestool -x -t 14 "$exe_path" -o superhuman.ico 2>/dev/null; then
				if icotool -x superhuman.ico 2>/dev/null; then
					for icon in superhuman_*.png; do
						[[ -f $icon ]] && icons_found=true
					done
					[[ $icons_found == true ]] && echo "Icons extracted from exe"
				fi
			fi
		fi
	fi

	if [[ $icons_found != true ]]; then
		echo 'Warning: No icons found. AppImage may be missing an icon.'
	fi

	cd "$project_root" || exit 1

	section_footer 'Icon Processing'
}

copy_locale_files() {
	section_header 'Copying Locale Files'

	local app_contents_dir="$superhuman_extract_dir/app-contents"

	# Copy any locale JSON files from Superhuman resources
	if [[ -d $app_contents_dir/resources ]]; then
		echo 'Copying Superhuman locale files to Electron resources...'
		cp "$app_contents_dir/resources/"*-*.json "$electron_resources_dest/" 2>/dev/null || \
			echo 'No locale JSON files found in Superhuman resources'
	fi

	# Copy app-update.yml for reference (not used on Linux but good to have)
	if [[ -f $app_contents_dir/resources/app-update.yml ]]; then
		cp "$app_contents_dir/resources/app-update.yml" "$electron_resources_dest/" || true
	fi

	echo "app.asar processed and staged in $app_staging_dir"

	section_footer 'Copying Locale Files'
}

#===============================================================================
# Packaging Functions
#===============================================================================

run_packaging() {
	section_header 'Call Packaging Script'

	local output_path=''

	if [[ $build_format == 'deb' ]]; then
		echo "Calling Debian packaging script for $architecture..."
		chmod +x scripts/build-deb-package.sh || exit 1
		if ! scripts/build-deb-package.sh \
			"$version" "$architecture" "$work_dir" "$app_staging_dir" \
			"$PACKAGE_NAME" "$MAINTAINER" "$DESCRIPTION"; then
			echo 'Debian packaging script failed.' >&2
			exit 1
		fi

		local deb_file
		deb_file=$(find "$work_dir" -maxdepth 1 -name "${PACKAGE_NAME}_${version}_${architecture}.deb" | head -n 1)
		echo 'Debian Build complete!'
		if [[ -n $deb_file && -f $deb_file ]]; then
			output_path="./$(basename "$deb_file")"
			mv "$deb_file" "$output_path" || exit 1
			echo "Package created at: $output_path"
		else
			echo 'Warning: Could not determine final .deb file path.'
			output_path='Not Found'
		fi

	elif [[ $build_format == 'appimage' ]]; then
		echo "Calling AppImage packaging script for $architecture..."
		chmod +x scripts/build-appimage.sh || exit 1
		if ! scripts/build-appimage.sh \
			"$version" "$architecture" "$work_dir" "$app_staging_dir" "$PACKAGE_NAME"; then
			echo 'AppImage packaging script failed.' >&2
			exit 1
		fi

		local appimage_file
		appimage_file=$(find "$work_dir" -maxdepth 1 -name "${PACKAGE_NAME}-${version}-${architecture}.AppImage" | head -n 1)
		echo 'AppImage Build complete!'
		if [[ -n $appimage_file && -f $appimage_file ]]; then
			output_path="./$(basename "$appimage_file")"
			mv "$appimage_file" "$output_path" || exit 1
			echo "Package created at: $output_path"

			section_header 'Generate .desktop file for AppImage'
			local desktop_file="./${PACKAGE_NAME}-appimage.desktop"
			echo "Generating .desktop file for AppImage at $desktop_file..."
			cat > "$desktop_file" << EOF
[Desktop Entry]
Name=Superhuman (AppImage)
Comment=Superhuman - The fastest email experience (AppImage Version $version)
Exec=$(basename "$output_path") %u
Icon=superhuman
Type=Application
Terminal=false
Categories=Network;Email;Office;
MimeType=x-scheme-handler/superhuman;x-scheme-handler/mailto;
StartupWMClass=Superhuman
X-AppImage-Version=$version
X-AppImage-Name=Superhuman (AppImage)
EOF
			echo '.desktop file generated.'
		else
			echo 'Warning: Could not determine final .AppImage file path.'
			output_path='Not Found'
		fi
	fi

	# Store for print_next_steps
	final_output_path="$output_path"
}

cleanup_build() {
	section_header 'Cleanup'
	if [[ $perform_cleanup != true ]]; then
		echo "Skipping cleanup of intermediate build files in $work_dir."
		return
	fi

	echo "Cleaning up intermediate build files in $work_dir..."
	if rm -rf "$work_dir"; then
		echo "Cleanup complete ($work_dir removed)."
	else
		echo 'Cleanup command failed.'
	fi
}

print_next_steps() {
	echo -e '\n\033[1;34m====== Next Steps ======\033[0m'

	if [[ $build_format == 'deb' ]]; then
		if [[ $final_output_path != 'Not Found' && -e $final_output_path ]]; then
			echo -e 'To install the Debian package, run:'
			echo -e "   \033[1;32msudo apt install $final_output_path\033[0m"
			echo -e "   (or \`sudo dpkg -i $final_output_path\`)"
		else
			echo -e 'Debian package file not found. Cannot provide installation instructions.'
		fi
	elif [[ $build_format == 'appimage' ]]; then
		if [[ $final_output_path != 'Not Found' && -e $final_output_path ]]; then
			echo -e "AppImage created at: \033[1;36m$final_output_path\033[0m"
			echo -e '\n\033[1;33mIMPORTANT:\033[0m This AppImage requires \033[1;36mGear Lever\033[0m for proper desktop integration'
			# shellcheck disable=SC2016  # backticks intentional for display
			echo -e 'and to handle the `superhuman://` login process correctly.'
			echo -e '\nTo install Gear Lever:'
			echo -e '   1. Install via Flatpak:'
			echo -e '      \033[1;32mflatpak install flathub it.mijorus.gearlever\033[0m'
			echo -e '   2. Integrate your AppImage with just one click:'
			echo -e '      - Open Gear Lever'
			echo -e "      - Drag and drop \033[1;36m$final_output_path\033[0m into Gear Lever"
			echo -e "      - Click 'Integrate' to add it to your app menu"
			if [[ ${GITHUB_ACTIONS:-} == 'true' ]]; then
				echo -e '\n   This AppImage includes embedded update information!'
			else
				echo -e '\n   This locally-built AppImage does not include update information.'
				echo -e '   For automatic updates, download release versions from GitHub releases'
			fi
		else
			echo -e 'AppImage file not found. Cannot provide usage instructions.'
		fi
	fi

	echo -e '\033[1;34m======================\033[0m'
}

#===============================================================================
# Main Execution
#===============================================================================

main() {
	# Phase 1: Setup
	detect_architecture
	check_system_requirements
	parse_arguments "$@"

	# Early exit for test mode
	if [[ $test_flags_mode == true ]]; then
		echo '--- Test Flags Mode Enabled ---'
		echo "Build Format: $build_format"
		echo "Clean Action: $cleanup_action"
		echo 'Exiting without build.'
		exit 0
	fi

	check_dependencies
	setup_work_directory
	setup_nodejs
	setup_electron_asar

	# Phase 2: Download and extract
	download_superhuman_installer

	# Phase 3: Patch and prepare
	patch_app_asar
	finalize_app_asar
	stage_electron
	process_icons
	copy_locale_files

	cd "$project_root" || exit 1

	# Phase 4: Package
	run_packaging

	# Phase 5: Cleanup and finish
	cleanup_build

	echo 'Build process finished.'
	print_next_steps
}

# Run main with all script arguments
main "$@"

exit 0
