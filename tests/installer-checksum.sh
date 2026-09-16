#!/usr/bin/env bash
# The dynamic source below hides build.sh's use of these globals and mock commands from ShellCheck.
# shellcheck disable=SC1090,SC2034,SC2154,SC2317,SC2329
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT

# Load the build functions without invoking the full build.
source <(sed '/^main "\$@"$/,$d' "$repo_root/build.sh")

if (
  architecture='amd64'
  superhuman_exe_filename='installer.exe'
  superhuman_download_url='https://example.invalid/installer.exe'
  work_dir="$test_root/mismatch"
  mkdir -p "$work_dir"
  wget() { printf 'tampered installer' > "$2"; }
  7z() { : > "$test_root/extraction-started"; }
  download_superhuman_installer
) > "$test_root/mismatch.log" 2>&1; then
  echo 'Mismatched installer was accepted' >&2
  exit 1
fi
grep -Fq 'checksum does not match' "$test_root/mismatch.log"
[[ ! -e $test_root/extraction-started ]]
[[ ! -e $test_root/mismatch/installer.exe ]]

printf 'trusted local installer' > "$test_root/local.exe"
(
  architecture='amd64'
  superhuman_exe_filename='installer.exe'
  local_exe_path="$test_root/local.exe"
  work_dir="$test_root/local"
  project_root="$repo_root"
  mkdir -p "$work_dir"
  wget() { echo 'Local installer unexpectedly downloaded' >&2; return 1; }
  7z() {
    local output_arg=''
    for arg in "$@"; do
      [[ $arg == -o* ]] && output_arg=${arg#-o}
    done
    if [[ $3 == *.exe ]]; then
      mkdir -p "$output_arg/\$PLUGINSDIR"
      : > "$output_arg/\$PLUGINSDIR/app-64.7z"
    else
      mkdir -p "$output_arg/resources"
      printf 'version: 9.9.9\n' > "$output_arg/resources/app-update.yml"
    fi
  }
  download_superhuman_installer
  [[ $version == '9.9.9' ]]
) > "$test_root/local.log" 2>&1
