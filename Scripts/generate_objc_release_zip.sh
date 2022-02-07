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
      --EE)
      EE=YES
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

if [ -z "$EE" ]
then
  SCHEME_PREFIX="CBL"
  CONFIGURATION="Release"
  CONFIGURATION_TEST="Debug"
  COVERAGE_NAME="coverage"
  EDITION="community"
  TEST_SIMULATOR="platform=iOS Simulator,name=iPhone 11"
else
  SCHEME_PREFIX="CBL_EE"
  CONFIGURATION="Release_EE"
  CONFIGURATION_TEST="Debug_EE"
  COVERAGE_NAME="coverage-ee"
  EDITION="enterprise"
  EXTRA_CMD_OPTIONS="--EE"
  TEST_SIMULATOR="platform=iOS Simulator,name=iPhone 11"
  OPTS="--EE"
fi

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

if [ -z "$NO_TEST" ] || [ -n "$TEST_ONLY" ]
then
  echo "Running unit tests ..."

  echo "Check devices ..."
  xcrun xctrace list devices

  echo "Run ObjC macOS tests ..."
  sh Scripts/xctest_crash_log.sh --delete-all
  xcodebuild test \
    -project CouchbaseLite.xcodeproj \
    -scheme "${SCHEME_PREFIX}_ObjC" \
    -configuration "$CONFIGURATION_TEST" \
    -sdk macosx || checkCrashLogs
  
  echo "Run ObjC iOS tests ..."
  # iOS-App target runs Keychain-Accessing tests
  sh Scripts/xctest_crash_log.sh --delete-all
  xcodebuild clean test \
    -project CouchbaseLite.xcodeproj \
    -scheme "${SCHEME_PREFIX}_ObjC_Tests_iOS_App" \
    -configuration "$CONFIGURATION_TEST" \
    -sdk iphonesimulator \
    -destination "$TEST_SIMULATOR" \
    -enableCodeCoverage YES || checkCrashLogs
  
  
  if [ -z "$NO_COV" ]
  then
    # Objective-C:
    echo "Generate coverage report for ObjC ..."
    slather coverage --html \
        --scheme "${SCHEME_PREFIX}_ObjC_Tests_iOS_App" \
        --configuration "$CONFIGURATION_TEST" \
        --ignore "vendor/*" --ignore "Swift/*" \
        --ignore "Objective-C/Tests/*" --ignore "../Sources/Swift/*" \
        --output-directory "$OUTPUT_DIR/$COVERAGE_NAME/Objective-C" \
        --binary-basename "CouchbaseLite.framework"  \
        --binary-basename "CBL_EE_Tests" \
        CouchbaseLite.xcodeproj > /dev/null
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

OUTPUT_OBJC_XC_DIR=$OUTPUT_DIR/objc_xc_$EDITION
OUTPUT_OBJC_XC_ZIP=../couchbase-lite-objc_xc_$EDITION$VERSION_SUFFIX.zip

OUTPUT_DOCS_DIR=$OUTPUT_DIR/docs
OUTPUT_OBJC_DOCS_DIR=$OUTPUT_DOCS_DIR/CouchbaseLite
OUTPUT_OBJC_DOCS_ZIP=../../couchbase-lite-objc-documentation_$EDITION$VERSION_SUFFIX.zip

echo "Building xcframework..."
set -o pipefail && sh Scripts/build_xcframework.sh -s "${SCHEME_PREFIX}_ObjC" -c "$CONFIGURATION" -o "$BUILD_DIR" -v "$VERSION" $OPTS | $XCPRETTY

echo "Make ObjC XCFramework zip file ..."
mkdir -p "$OUTPUT_OBJC_XC_DIR"
cp -R "$BUILD_DIR/xc/${SCHEME_PREFIX}_ObjC"/* "$OUTPUT_OBJC_XC_DIR"
if [[ -n $WORKSPACE ]]; then
  cp ${WORKSPACE}/product-texts/mobile/couchbase-lite/license/LICENSE_${EDITION}.txt "$OUTPUT_OBJC_XC_DIR"/LICENSE.txt
fi
pushd "$OUTPUT_OBJC_XC_DIR" > /dev/null
zip -ry "$OUTPUT_OBJC_XC_ZIP" *
popd > /dev/null

if [[ -z $NO_API_DOCS ]]; then
  # Generate API docs:
  echo "Generate API docs ..."
  OBJC_UMBRELLA_HEADER=`find $OUTPUT_OBJC_XC_DIR -name "CouchbaseLite.h"`
  jazzy --clean --objc --umbrella-header ${OBJC_UMBRELLA_HEADER} --module CouchbaseLite --theme Scripts/Support/Docs/Theme --readme README.md --output ${OUTPUT_DOCS_DIR}/CouchbaseLite
  
  # >> Objective-C API
  pushd "$OUTPUT_OBJC_DOCS_DIR" > /dev/null
  zip -ry "$OUTPUT_OBJC_DOCS_ZIP" *
  popd > /dev/null
fi

# Cleanup
rm -rf "$BUILD_DIR"
rm -rf "$OUTPUT_OBJC_XC_DIR"
rm -rf "$OUTPUT_DOCS_DIR"

