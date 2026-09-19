#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root/apps/android"

java -version
./gradlew --version
./gradlew --no-daemon --stacktrace lintDebug testDebugUnitTest assembleDebug
