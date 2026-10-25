#!/bin/zsh
# Command & Conquer Generals Zero Hour(tm)
# Copyright 2025 Electronic Arts Inc.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# Builds the test host, installs it on the simulator, puts a fake <App>/GameSupport into the app
# (plus fake <App>/GameData unless --no-gamedata, like the published IPA), fake logs into Documents,
# optionally a fake retail game folder into Files > On My iPhone (--files), and launches it with
# stderr captured to ios/Launcher/build/host-stderr.log (git-ignored).
#   scripts/run-host.sh [udid] [--broken] [--no-gamedata] [--files] [-- KEY=VALUE ...]
#   DerivedData goes to ios/Launcher/build/dd; set GX_HOST_BUILD_DIR to build elsewhere.
set -euo pipefail
HERE=${0:A:h}/..
UDID=${1:-2210CEB1-C001-4FE0-93EE-249728954F25}
shift || true
BROKEN=""; BUNDLE_DATA=1; FILES=0
while [[ $# -gt 0 && "$1" != "--" ]]; do
  case "$1" in
    --broken) BROKEN="--broken" ;;
    --no-gamedata) BUNDLE_DATA=0 ;;
    --files) FILES=1 ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
  shift
done
[[ "${1:-}" == "--" ]] && shift
BUILD=${GX_HOST_BUILD_DIR:-$HERE/build}
cd "$HERE/HostApp"
[[ -d GXLauncherHost.xcodeproj ]] || /opt/homebrew/bin/xcodegen
xcodebuild -project GXLauncherHost.xcodeproj -scheme GXLauncherHost -destination "id=$UDID" \
  -derivedDataPath "$BUILD/dd" build -quiet
xcrun simctl install "$UDID" "$BUILD/dd/Build/Products/Debug-iphonesimulator/GXLauncherHost.app"
APP=$(xcrun simctl get_app_container "$UDID" dev.generalsx.launcherhost app)
DATA=$(xcrun simctl get_app_container "$UDID" dev.generalsx.launcherhost data)
python3 -I "$HERE/scripts/make-fake-gamedata.py" - --support "$APP/GameSupport" --logs "$DATA/Documents"
if [[ $BUNDLE_DATA == 1 ]]; then
  python3 -I "$HERE/scripts/make-fake-gamedata.py" "$APP/GameData" $BROKEN
fi
if [[ $FILES == 1 ]]; then
  # "On My iPhone" is the File Provider Storage of the group.com.apple.FileProvider.LocalStorage app group.
  for meta in ~/Library/Developer/CoreSimulator/Devices/$UDID/data/Containers/Shared/AppGroup/*/.com.apple.mobile_container_manager.metadata.plist; do
    if [[ "$(plutil -extract MCMMetadataIdentifier raw "$meta")" == group.com.apple.FileProvider.LocalStorage ]]; then
      LOCAL="${meta:h}/File Provider Storage"
      python3 -I "$HERE/scripts/make-fake-gamedata.py" "$LOCAL/Games/Command and Conquer Generals Zero Hour" $BROKEN --retail
    fi
  done
fi
LOG="$HERE/build/host-stderr.log"   # simctl's --stderr target must be reachable by the simulator
mkdir -p "${LOG:h}"
rm -f "$LOG"
for kv in "$@"; do export "SIMCTL_CHILD_$kv"; done
xcrun simctl launch --terminate-running-process --stderr="$LOG" "$UDID" dev.generalsx.launcherhost
echo "data container: $DATA"
