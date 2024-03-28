#!/bin/bash

set -e

function usage
{
  echo -e "Usage: ${0} -o <Output Directory> -e <Edition; ce, community, ee, enterprise> [-v <Version (<Version Number>[-<Build Number>])>]"
  echo -e "\nOptions:"
  echo -e "  --notest\t create a release package but no tests needs to be run"
  echo -e "  --nocov\t create a release package, run tests but no code coverage zip"
  echo -e "  --nodocs\t create a release package without API docs"
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

if [ -z "$EDITION" ]
then
  usage
  exit 4
fi

if [ "$EDITION" == "ce" ] || [ "$EDITION" == "community" ]
then
  SCHEME_PREFIX="CBL"
  CONFIGURATION="Release"
  CONFIGURATION_TEST="Debug"
  COVERAGE_NAME="objc_coverage"
  EDITION="community"
elif [ "$EDITION" == "ee" ] || [ "$EDITION" == "enterprise" ]
then
  SCHEME_PREFIX="CBL_EE"
  CONFIGURATION="Release_EE"
  CONFIGURATION_TEST="Debug_EE"
  COVERAGE_NAME="objc_coverage-ee"
  EDITION="enterprise"
  EXTRA_CMD_OPTIONS="--EE"
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
  
  # get the latest simulator
  TEST_SIMULATOR=$(xcrun simctl list devicetypes | grep \.iPhone- | tail -1 |  sed  "s/ (com.apple.*//g")
  
  echo "Run ObjC iOS tests on ${TEST_SIMULATOR}..."
  # iOS-App target runs Keychain-Accessing tests
  sh Scripts/xctest_crash_log.sh --delete-all
  xcodebuild clean test \
    -project CouchbaseLite.xcodeproj \
    -scheme "${SCHEME_PREFIX}_ObjC_Tests_iOS_App" \
    -configuration "$CONFIGURATION_TEST" \
    -sdk iphonesimulator \
    -destination "platform=iOS Simulator,name=$TEST_SIMULATOR" \
    -enableCodeCoverage YES || checkCrashLogs
  
  
  if [ -z "$NO_COV" ]
  then
    # Objective-C:
    echo "Generate coverage report for ObjC ..."
    slather coverage --html \
        --scheme "${SCHEME_PREFIX}_ObjC_Tests_iOS_App" \
        --binary-basename "CouchbaseLite" \
        --configuration "$CONFIGURATION_TEST" \
        --ignore "vendor/*" --ignore "Swift/*" \
        --ignore "Objective-C/Tests/*" --ignore "../Sources/Swift/*" \
        --output-directory "$OUTPUT_DIR/$COVERAGE_NAME" \
        --binary-basename "CouchbaseLite.framework"  \
        --binary-basename "CBL_EE_Tests" \
        CouchbaseLite.xcodeproj > /dev/null
        
        # Zip reports:
        pushd "$OUTPUT_DIR" > /dev/null
        zip -ry $COVERAGE_NAME.zip $COVERAGE_NAME/*
        popd > /dev/null
        rm -rf "$OUTPUT_DIR/$COVERAGE_NAME"
  fi
fi

VERSION_SUFFIX=""
API_DOC_VERSION=""
if [ -n "$VERSION" ]
then
  VERSION_SUFFIX="_$VERSION"
  API_DOC_VERSION="$VERSION"
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
  jazzy --clean --objc --umbrella-header ${OBJC_UMBRELLA_HEADER} --module CouchbaseLite --module-version "${API_DOC_VERSION}" --theme Scripts/Support/Docs/Theme --readme README.md --output ${OUTPUT_DOCS_DIR}/CouchbaseLite
  
  # >> Objective-C API
  pushd "$OUTPUT_OBJC_DOCS_DIR" > /dev/null
  zip -ry "$OUTPUT_OBJC_DOCS_ZIP" *
  popd > /dev/null
fi

# Cleanup
rm -rf "$BUILD_DIR"
rm -rf "$OUTPUT_OBJC_XC_DIR"
rm -rf "$OUTPUT_DOCS_DIR"

