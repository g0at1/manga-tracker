#!/bin/zsh
# Builds the Mac app and replaces /Applications/MangaTracker.app with it.
# A running copy is asked to quit first (the normal ⌘Q path, so it flushes
# and closes sync) and relaunched afterwards.
#
#   scripts/install-mac.sh            # Release build
#   scripts/install-mac.sh Debug      # any other configuration
set -euo pipefail

cd "$(dirname "$0")/.."

app_name="MangaTracker"
configuration="${1:-Release}"
destination="/Applications/$app_name.app"
build_args=(
    -project MangaTracker.xcodeproj
    -scheme "$app_name"
    -configuration "$configuration"
    -destination 'platform=macOS'
    COMPILER_INDEX_STORE_ENABLE=NO
)

echo "Building $app_name ($configuration)…"
xcodebuild "${build_args[@]}" -quiet build

# Where this build landed; the default DerivedData keeps the package cache warm.
products_dir=$(xcodebuild "${build_args[@]}" -showBuildSettings 2>/dev/null \
    | awk '/^ *BUILT_PRODUCTS_DIR = / { print $3; exit }')
built_app="$products_dir/$app_name.app"
[[ -d "$built_app" ]] || { echo "Built app not found at $built_app" >&2; exit 1; }

relaunch=0
if pgrep -xq "$app_name"; then
    echo "Quitting the running $app_name…"
    osascript -e "tell application \"$app_name\" to quit"
    for _ in {1..100}; do
        pgrep -xq "$app_name" || break
        sleep 0.1
    done
    pgrep -xq "$app_name" && { echo "$app_name didn't quit; leaving $destination alone" >&2; exit 1; }
    relaunch=1
fi

echo "Installing to $destination…"
rm -rf "$destination"
ditto "$built_app" "$destination"

if (( relaunch )); then
    open "$destination"
fi
echo "Done: $(defaults read "$destination/Contents/Info.plist" CFBundleShortVersionString) ($configuration) installed."
