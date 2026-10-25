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

# Builds the test host, installs it on the simulator, fills the bundle with fake game data and
# Documents with fake logs, and launches it with stderr captured to build/host-stderr.log.
#   scripts/run-host.sh [udid] [--broken] [-- KEY=VALUE ...]   (env vars passed to the app)
set -euo pipefail
HERE=${0:A:h}/..
UDID=${1:-2210CEB1-C001-4FE0-93EE-249728954F25}
shift || true
BROKEN=""
if [[ "${1:-}" == "--broken" ]]; then BROKEN="--broken"; shift; fi
[[ "${1:-}" == "--" ]] && shift
cd "$HERE/HostApp"
[[ -d GXLauncherHost.xcodeproj ]] || /opt/homebrew/bin/xcodegen
xcodebuild -project GXLauncherHost.xcodeproj -scheme GXLauncherHost -destination "id=$UDID" \
  -derivedDataPath "$HERE/build/dd" build -quiet
xcrun simctl install "$UDID" "$HERE/build/dd/Build/Products/Debug-iphonesimulator/GXLauncherHost.app"
APP=$(xcrun simctl get_app_container "$UDID" dev.generalsx.launcherhost app)
DATA=$(xcrun simctl get_app_container "$UDID" dev.generalsx.launcherhost data)
python3 -I "$HERE/scripts/make-fake-gamedata.py" "$APP/GameData" $BROKEN --logs "$DATA/Documents"
rm -f "$HERE/build/host-stderr.log"
for kv in "$@"; do export "SIMCTL_CHILD_$kv"; done
xcrun simctl launch --terminate-running-process --stderr="$HERE/build/host-stderr.log" "$UDID" dev.generalsx.launcherhost
echo "data container: $DATA"
