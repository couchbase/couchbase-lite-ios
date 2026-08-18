#!/bin/bash -e

# Stages binary CouchbaseLite frameworks for the binary test targets.
#
# The binary test targets (CBL_*_Binary_Tests) have no dependency on the framework
# targets: they compile and link against the frameworks staged in
# BinaryTests/Frameworks, so that a test run always certifies a specific,
# known binary. This script downloads the specified CouchbaseLite release or
# internal build and stages its macOS framework. The CouchbaseLiteVectorSearch
# extension is staged as well, using the xcframework in Tests/Extensions
# (downloaded per Tests/Extensions/version.txt when needed).
#
# Note : Downloading requires Couchbase VPN.
#
# Usage:
#   prepare_binary_test.sh <objc | swift> <ce | ee> <version>[-<build>]
#
# Examples:
#   Scripts/prepare_binary_test.sh objc ee 4.2.0-3     (internal build)
#   Scripts/prepare_binary_test.sh objc ce 4.1.0       (release)

PLATFORM="$1"
EDITION="$2"
VERSION_BUILD="$3"

case "$PLATFORM" in
  objc|swift) ;;
  *) sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac

case "$EDITION" in
  ce) EDITION_NAME="community" ;;
  ee) EDITION_NAME="enterprise" ;;
  *) sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac

if [ -z "$VERSION_BUILD" ]; then
  sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 2
fi

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT_DIR="$SCRIPT_DIR/.."
DEST="$ROOT_DIR/BinaryTests/Frameworks"
EXTENSIONS_DIR="$ROOT_DIR/Tests/Extensions"

TMP_DIR=$(mktemp -d)
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

# Copies the whole xcframework to DEST and prints the staged xcframework's
# name, version, and build number (read from the macOS framework's Info.plist).
function stage_xcframework() {
  local xcframework="$1" source="$2"
  cp -R "$xcframework" "$DEST/"

  local name plist version build
  name=$(basename "$xcframework")
  plist=$(find "$DEST/$name" -path "*macos*" -name "Info.plist" | grep -E "framework/(Versions/A/Resources/)?Info.plist" | head -1)
  version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$plist" 2>/dev/null || echo "?")
  build=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$plist" 2>/dev/null || echo "?")
  echo "  $name  version $version-$build  from $source" | tee -a "$DEST/info.txt"
}

# Download the CouchbaseLite zip:
if [[ "$VERSION_BUILD" == *"-"* ]]; then
  VERSION="${VERSION_BUILD%-*}"
  BLD_NUM="${VERSION_BUILD##*-}"
  ZIP_FILENAME="couchbase-lite-${PLATFORM}_xc_${EDITION_NAME}_${VERSION}-${BLD_NUM}.zip"
  URL="https://latestbuilds.service.couchbase.com/builds/latestbuilds/couchbase-lite-ios/${VERSION}/${BLD_NUM}/${ZIP_FILENAME}"
else
  ZIP_FILENAME="couchbase-lite-${PLATFORM}_xc_${EDITION_NAME}_${VERSION_BUILD}.zip"
  URL="https://latestbuilds.service.couchbase.com/builds/releases/mobile/couchbase-lite-ios/${VERSION_BUILD}/${ZIP_FILENAME}"
fi
echo "Download CouchbaseLite from ${URL} ..."
curl -f -o "$TMP_DIR/$ZIP_FILENAME" "$URL"
unzip -q "$TMP_DIR/$ZIP_FILENAME" -d "$TMP_DIR/cbl"

# Download the vector search extension when needed:
"$SCRIPT_DIR/download_vector_search_extension.sh"

# Stage the xcframeworks:
rm -rf "$DEST"
mkdir -p "$DEST"
echo "Staged for binary testing in BinaryTests/Frameworks:" | tee "$DEST/info.txt"
for xcf in $(find "$TMP_DIR/cbl" -name "*.xcframework" -type d); do
  stage_xcframework "$xcf" "$ZIP_FILENAME"
done
stage_xcframework "$EXTENSIONS_DIR/CouchbaseLiteVectorSearch.xcframework" "Tests/Extensions ($(cat "$EXTENSIONS_DIR/version.txt"))"
