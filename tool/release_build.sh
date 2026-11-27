#!/usr/bin/env bash
# One release build for one platform, stamped with a build number and the
# commit, so every distributed binary says where it came from.
#   bash tool/release_build.sh <platform> <build-number> [flutter args...]
set -euo pipefail
platform=$1
number=$2
shift 2
case "$number" in
  ''|*[!0-9]*)
    echo "::error::build number must be digits, got '$number'"
    exit 1
    ;;
esac
commit=$(git rev-parse --short=7 HEAD)
echo "build number: $number, commit: $commit"
exec flutter build "$platform" --release \
  --build-number="$number" \
  --dart-define=ANISCHED_BUILD="$number" \
  --dart-define=ANISCHED_COMMIT="$commit" \
  "$@"
