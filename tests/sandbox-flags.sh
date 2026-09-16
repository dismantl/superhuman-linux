#!/usr/bin/env bash
# ShellCheck cannot follow the dynamic source or see the injected namespace probe.
# shellcheck disable=SC1091,SC2034,SC2154,SC2317,SC2329
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT

# shellcheck source=../scripts/launcher-common.sh
source "$repo_root/scripts/launcher-common.sh"
log_file="$test_root/launcher.log"

unshare() {
  [[ $1 == '--user' && $2 == '--map-root-user' && $3 == 'true' ]] || return 2
  return "$namespace_status"
}

appimage_apparmor_userns_restricted() {
  [[ $apparmor_restricted == true ]]
}

has_no_sandbox() {
  local flag
  for flag in "${electron_args[@]}"; do
    [[ $flag == '--no-sandbox' ]] && return 0
  done
  return 1
}

for mode in x11 xwayland wayland; do
  DISPLAY=:99
  WAYLAND_DISPLAY=''
  SUPERHUMAN_USE_WAYLAND=0
  if [[ $mode != x11 ]]; then WAYLAND_DISPLAY='wayland-0'; fi
  if [[ $mode == wayland ]]; then SUPERHUMAN_USE_WAYLAND=1; fi
  detect_display_backend || true

  apparmor_restricted=false
  namespace_status=0
  build_electron_args appimage
  if has_no_sandbox; then
    echo "AppImage disabled the sandbox on $mode with working namespaces" >&2
    exit 1
  fi

  namespace_status=1
  build_electron_args appimage 2> "$test_root/warning"
  has_no_sandbox
  grep -Fq 'launching without the Chromium sandbox' "$test_root/warning"
  grep -Fq 'AppImage user namespace sandbox unavailable; Chromium sandbox disabled' "$log_file"

  build_electron_args deb
  if has_no_sandbox; then
    echo "Debian package disabled the sandbox on $mode" >&2
    exit 1
  fi
done

apparmor_restricted=true
namespace_status=0
build_electron_args appimage 2> "$test_root/warning-apparmor"
has_no_sandbox
grep -Fq 'launching without the Chromium sandbox' "$test_root/warning-apparmor"

apparmor_restricted=false
unset -f unshare
(
  PATH="$test_root"
  build_electron_args appimage 2> "$test_root/warning-no-probe"
  has_no_sandbox
)
grep -Fq 'launching without the Chromium sandbox' "$test_root/warning-no-probe"
