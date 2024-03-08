#!/bin/bash

set -e

function usage
{
  echo "Usage: ${0} -o <Output Directory> [-v <Version (<Version Number>[-<Build Number>])>]"
  echo "\nOptions:"
  echo "  --notest\t create a release package but no tests needs to be run"
  echo "  --nocov\t create a release package, run tests but no code coverage zip"
  echo "  --nodocs\t create a release package without API docs"
}

function checkCrashLogs
{
  echo "Check for xctest crash logs ..."
  sh Scripts/xctest_crash_log.sh
  exit 1
}

while [[ $# -gt 0 ]]
do
  key=${1}
  case $key in
      -v)
      VERSION=${2}
      shift
      ;;
      -o)
      OUTPUT_DIR=${2}
      shift
      ;;
      -e)
      EDITION=${2}
      shift
      ;;
      --notest)
      NO_TEST=YES
      ;;
      --nocov)
      NO_COV=YES
      ;;
      --pretty)
      PRETTY=YES
      ;;
      --nodocs)
      NO_API_DOCS=YES
      ;;
      *)
      usage
      exit 3
      ;;
  esac
  shift
done

if [ -z "$OUTPUT_DIR" ]
then
  usage
  exit 4
fi

if [ "$EDITION" == "ce" ] || [ "$EDITION" == "community" ]
then
  SCHEME_PREFIX="CBL"
  CONFIGURATION="Release"
  CONFIGURATION_TEST="Debug"
  COVERAGE_NAME="swift_coverage"
  EDITION="community"
elif [ "$EDITION" == "ee" ] || [ "$EDITION" == "enterprise" ]
  SCHEME_PREFIX="CBL_EE"
  CONFIGURATION="Release_EE"
  CONFIGURATION_TEST="Debug_EE"
  COVERAGE_NAME="swift_coverage-ee"
  EDITION="enterprise"
  OPTS="--EE"
else
  echo "Invalid Edition"
  exit 4
fi

echo "Build Edition : ${EDITION}"

if [ -z "$PRETTY" ]
then
  XCPRETTY="cat"
else
  # Allow non-ascii text in output:
  export LC_CTYPE=en_US.UTF-8
  XCPRETTY="xcpretty"
fi

# Clean output directory:
echo "Clean output directory: $OUTPUT_DIR"
rm -rf "$OUTPUT_DIR"

# Check xcodebuild version:
echo "Check xcodebuild version ..."
xcodebuild -version

if [ -z "$NO_TEST" ]
then
  echo "Running unit tests ..."

  echo "Check devices ..."
  xcrun xctrace list devices

  echo "Run macOS tests ..."
  xcodebuild test \
    -project CouchbaseLite.xcodeproj \
    -scheme "${SCHEME_PREFIX}_Swift" \
    -configuration "$CONFIGURATION_TEST" \
    -sdk macosx

  # get the latest simulator
  TEST_SIMULATOR=$(xcrun simctl list devicetypes | grep \.iPhone- | tail -1 |  sed  "s/ (com.apple.*//g")
  echo "Run Swift iOS tests on ${TEST_SIMULATOR}..."
  
  xcodebuild clean test \
    -project CouchbaseLite.xcodeproj \
    -scheme "${SCHEME_PREFIX}_Swift_Tests_iOS_App" \
    -configuration "$CONFIGURATION_TEST" \
    -sdk iphonesimulator \
    -destination "platform=iOS Simulator,name=$TEST_SIMULATOR" \
    -enableCodeCoverage YES
  
  # Generage Code Coverage Reports:
  if [ -z "$NO_COV" ]
  then
    # Swift:
    echo "Generate coverage report for Swift ..."
    slather coverage --html \
        --scheme "${SCHEME_PREFIX}_Swift_Tests_iOS_App" \
        --binary-basename "CouchbaseLiteSwift" \
        --configuration "$CONFIGURATION_TEST"  \
        --ignore "vendor/*" --ignore "Objective-C/*" \
        --ignore "Swift/Tests/*" --ignore "../Sources/Objective-C/*" \
        --output-directory "$OUTPUT_DIR/$COVERAGE_NAME" \
        CouchbaseLite.xcodeproj > /dev/null
    
    # Zip reports:
    pushd "$OUTPUT_DIR" > /dev/null
    zip -ry $COVERAGE_NAME.zip $COVERAGE_NAME/*
    popd > /dev/null
    rm -rf "$OUTPUT_DIR/$COVERAGE_NAME"
  fi
fi

VERSION_SUFFIX=""
if [ -n "$VERSION" ]
then
  VERSION_SUFFIX="_$VERSION"
fi

# Build frameworks:
echo "Build CouchbaseLite release package..."

BUILD_DIR=$OUTPUT_DIR/build

OUTPUT_SWIFT_XC_DIR=$OUTPUT_DIR/swift_xc_$EDITION
OUTPUT_SWIFT_XC_ZIP=../couchbase-lite-swift_xc_$EDITION$VERSION_SUFFIX.zip

OUTPUT_DOCS_DIR=$OUTPUT_DIR/docs
OUTPUT_SWIFT_DOCS_DIR=$OUTPUT_DOCS_DIR/CouchbaseLiteSwift
OUTPUT_SWIFT_DOCS_ZIP=../../couchbase-lite-swift-documentation_$EDITION$VERSION_SUFFIX.zip

echo "Building xcframework..."
set -o pipefail && sh Scripts/build_xcframework.sh -s "${SCHEME_PREFIX}_Swift" -c "$CONFIGURATION" -o "$BUILD_DIR" -v "$VERSION" $OPTS | $XCPRETTY

echo "Make Swift xcframework zip file ..."
mkdir -p "$OUTPUT_SWIFT_XC_DIR"
cp -R "$BUILD_DIR/xc/${SCHEME_PREFIX}_Swift"/* "$OUTPUT_SWIFT_XC_DIR"
if [[ -n $WORKSPACE ]]; then
  cp ${WORKSPACE}/product-texts/mobile/couchbase-lite/license/LICENSE_${EDITION}.txt "$OUTPUT_SWIFT_XC_DIR"/LICENSE.txt
fi
pushd "$OUTPUT_SWIFT_XC_DIR" > /dev/null
zip -ry "$OUTPUT_SWIFT_XC_ZIP" *
popd > /dev/null

# Generate swift checksum file:
echo "Generate swift package checksum..."
sh Scripts/generate_package_manifest.sh -zip-path "$OUTPUT_DIR/couchbase-lite-swift_xc_$EDITION$VERSION_SUFFIX.zip" -o $OUTPUT_DIR $OPTS

if [[ -z $NO_API_DOCS ]]; then
  # Generate API docs:
  echo "Generate API docs ..."
  jazzy --clean --xcodebuild-arguments "clean,build,-scheme,${SCHEME_PREFIX}_Swift,-sdk,iphonesimulator,-destination,generic/platform=iOS Simulator" --module CouchbaseLiteSwift --theme Scripts/Support/Docs/Theme --readme README.md --output ${OUTPUT_DOCS_DIR}/CouchbaseLiteSwift
  
  # >> Swift API docs
  pushd "$OUTPUT_SWIFT_DOCS_DIR" > /dev/null
  zip -ry "$OUTPUT_SWIFT_DOCS_ZIP" *
  popd > /dev/null
fi

# Cleanup
rm -rf "$BUILD_DIR"
rm -rf "$OUTPUT_SWIFT_XC_DIR"
rm -rf "$OUTPUT_DOCS_DIR"

