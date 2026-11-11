#!/bin/bash
# GeneralsX @feature iOS port 11/11/2026 Builds and runs the GXMouseTouch.h unit tests on the Mac.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${HERE}/../../.." && pwd)"
OUT="$(mktemp -d)"
trap 'rm -rf "${OUT}"' EXIT
clang++ -std=c++17 -Wall -Wextra -Werror -I"${ROOT}/Core/GameEngineDevice/Include" \
    "${HERE}/mouse_touch_test.cpp" -o "${OUT}/mouse_touch_test"
"${OUT}/mouse_touch_test"
