#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT

mkdir -p "$test_root/bin" "$test_root/staging/node_modules/electron/dist" "$test_root/staging/app.asar.unpacked" "$test_root/work"

cat > "$test_root/bin/appimagetool" << 'EOF'
#!/usr/bin/env bash
: > "${@: -1}"
EOF
chmod +x "$test_root/bin/appimagetool"

cat > "$test_root/staging/node_modules/electron/dist/electron" << 'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$TEST_ELECTRON_ARGS"
EOF
chmod +x "$test_root/staging/node_modules/electron/dist/electron"
: > "$test_root/staging/app.asar"

GITHUB_ACTIONS=false PATH="$test_root/bin:$PATH" \
  bash "$repo_root/scripts/build-appimage.sh" 1.2.3 amd64 "$test_root/work" "$test_root/staging" superhuman \
  > "$test_root/appimage-build.log"

log_dir="$test_root/cache/superhuman"
mkdir -p "$log_dir"
chmod 755 "$log_dir"
printf 'existing log\n' > "$log_dir/launcher.log"
chmod 644 "$log_dir/launcher.log"

callback='superhuman://auth/callback?code=secret-code#access_token=secret-fragment'
XDG_CACHE_HOME="$test_root/cache" TEST_ELECTRON_ARGS="$test_root/electron-args" DISPLAY=:99 WAYLAND_DISPLAY='' \
  "$test_root/work/io.github.aaddrick.superhuman-linux.AppDir/AppRun" "$callback"

grep -Fxq -- "$callback" "$test_root/electron-args"
if grep -Fq -- 'secret-' "$log_dir/launcher.log"; then
  echo 'AppImage launcher logged an OAuth secret' >&2
  exit 1
fi
[[ $(stat -c %a "$log_dir") == 700 ]]
[[ $(stat -c %a "$log_dir/launcher.log") == 600 ]]

bash "$repo_root/scripts/build-deb-package.sh" 1.2.3 amd64 "$test_root/work" "$test_root/staging" superhuman Maintainer Description \
  > "$test_root/deb-build.log"
deb_launcher="$test_root/work/package/usr/bin/superhuman"
if grep -Fq 'Arguments:' "$deb_launcher" || grep -Fq ' $*' "$deb_launcher"; then
  echo 'Debian launcher template logs application arguments' >&2
  exit 1
fi
grep -Fq '"$@"' "$deb_launcher"
