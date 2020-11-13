#!/bin/bash

set -e

function usage
{
  echo "Usage: ${0} -o <Output Directory> [-v <Version (<Version Number>[-<Build Number>])>]"
  echo "\nOptions:"
  echo "  --xcframework\t create a release package with .xcframework"
  echo "  --combined\t\t create a release package with .xcframework and .framework"
  echo "  --notest\t create a release package but no tests needs to be run"
  echo "  --nocov\t create a release package, run tests but no code coverage zip"
  echo "  --testonly\t run tests but no release package"
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
      --xcframework)
      XCFRAMEWORK=YES
      ;;
      --combined)
      COMBINED=YES
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
      --testonly)
      TEST_ONLY=YES
      ;;
      --pretty)
      PRETTY=YES
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

# As long as we support `.framework`, we will create .framework as well as .xcframework zips.
COMBINED=YES

if [ -z "$EE" ]
then
  SCHEME_PREFIX="CBL"
  CONFIGURATION="Release"
  CONFIGURATION_TEST="Debug"
  COVERAGE_NAME="coverage"
  EDITION="community"
  EXTRA_CMD_OPTIONS=""
  TEST_SIMULATOR="platform=iOS Simulator,name=iPhone 11"
else
  SCHEME_PREFIX="CBL_EE"
  CONFIGURATION="Release_EE"
  CONFIGURATION_TEST="Debug_EE"
  COVERAGE_NAME="coverage-ee"
  EDITION="enterprise"
  EXTRA_CMD_OPTIONS="--EE"
  TEST_SIMULATOR="platform=iOS Simulator,name=iPhone 11"
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
  instruments -s devices

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

  echo "Run Swift macOS tests ..."
  xcodebuild test \
    -project CouchbaseLite.xcodeproj \
    -scheme "${SCHEME_PREFIX}_Swift" \
    -configuration "$CONFIGURATION_TEST" \
    -sdk macosx

  echo "Run Swift iOS tests ..."
  xcodebuild clean test \
    -project CouchbaseLite.xcodeproj \
    -scheme "${SCHEME_PREFIX}_Swift_Tests_iOS_App" \
    -configuration "$CONFIGURATION_TEST" \
    -sdk iphonesimulator \
    -destination "$TEST_SIMULATOR" \
    -enableCodeCoverage YES
  
  # Generage Code Coverage Reports:
  if [ -z "$NO_COV" ]
  then
    # Swift:
    echo "Generate coverage report for Swift ..."
    slather coverage --html \
        --scheme "${SCHEME_PREFIX}_Swift_Tests_iOS_App" \
        --configuration "$CONFIGURATION_TEST"  \
        --ignore "vendor/*" --ignore "Objective-C/*" \
        --ignore "Swift/Tests/*" --ignore "../Sources/Objective-C/*" \
        --output-directory "$OUTPUT_DIR/$COVERAGE_NAME/Swift" \
        CouchbaseLite.xcodeproj > /dev/null
    
    # Zip reports:
    pushd "$OUTPUT_DIR" > /dev/null
    zip -ry $COVERAGE_NAME.zip $COVERAGE_NAME/*
    popd > /dev/null
    rm -rf "$OUTPUT_DIR/$COVERAGE_NAME"
  fi
fi
if [  -n "$TEST_ONLY" ]
then
    echo "--testonly is specified."
    echo "skipping the rest of build."
    exit
fi


VERSION_SUFFIX=""
if [ ! -z "$VERSION" ]
then
  VERSION_SUFFIX="_$VERSION"
fi

# Build frameworks:
echo "Build CouchbaseLite release package..."

BUILD_DIR=$OUTPUT_DIR/build

OUTPUT_OBJC_DIR=$OUTPUT_DIR/objc_$EDITION
OUTPUT_OBJC_ZIP=../couchbase-lite-objc_$EDITION$VERSION_SUFFIX.zip

OUTPUT_SWIFT_DIR=$OUTPUT_DIR/swift_$EDITION
OUTPUT_SWIFT_ZIP=../couchbase-lite-swift_$EDITION$VERSION_SUFFIX.zip

OUTPUT_SWIFT_XC_DIR=$OUTPUT_DIR/swift_xc_$EDITION
OUTPUT_SWIFT_XC_ZIP=../couchbase-lite-swift_xc_$EDITION$VERSION_SUFFIX.zip
OUTPUT_OBJC_XC_DIR=$OUTPUT_DIR/objc_xc_$EDITION
OUTPUT_OBJC_XC_ZIP=../couchbase-lite-objc_xc_$EDITION$VERSION_SUFFIX.zip

OUTPUT_DOCS_DIR=$OUTPUT_DIR/docs
OUTPUT_OBJC_DOCS_DIR=$OUTPUT_DOCS_DIR/CouchbaseLite
OUTPUT_OBJC_DOCS_ZIP=../../couchbase-lite-objc-documentation_$EDITION$VERSION_SUFFIX.zip
OUTPUT_SWIFT_DOCS_DIR=$OUTPUT_DOCS_DIR/CouchbaseLiteSwift
OUTPUT_SWIFT_DOCS_ZIP=../../couchbase-lite-swift-documentation_$EDITION$VERSION_SUFFIX.zip

if [[ ! -z $COMBINED ]] || [[ -z $XCFRAMEWORK ]]
then
  echo "Building framework..."
  set -o pipefail && sh Scripts/build_framework.sh -s "${SCHEME_PREFIX}_ObjC" -c "$CONFIGURATION" -p iOS -o "$BUILD_DIR" -v "$VERSION" | $XCPRETTY
  set -o pipefail && sh Scripts/build_framework.sh -s "${SCHEME_PREFIX}_ObjC" -c "$CONFIGURATION" -p macOS -o "$BUILD_DIR" -v "$VERSION" | $XCPRETTY
  set -o pipefail && sh Scripts/build_framework.sh -s "${SCHEME_PREFIX}_Swift" -c "$CONFIGURATION" -p iOS -o "$BUILD_DIR" -v "$VERSION" | $XCPRETTY
  set -o pipefail && sh Scripts/build_framework.sh -s "${SCHEME_PREFIX}_Swift" -c "$CONFIGURATION" -p macOS -o "$BUILD_DIR" -v "$VERSION" | $XCPRETTY

  # Objective-C
  echo "Make Objective-C framework zip file ..."
  mkdir -p "$OUTPUT_OBJC_DIR"
  cp -R "$BUILD_DIR/${SCHEME_PREFIX}_ObjC"/* "$OUTPUT_OBJC_DIR"
  if [[ -n $WORKSPACE ]]; then
      cp ${WORKSPACE}/product-texts/mobile/couchbase-lite/license/LICENSE_${EDITION}.txt "$OUTPUT_OBJC_DIR"/LICENSE.txt
  fi
  pushd "$OUTPUT_OBJC_DIR"
  zip -ry "$OUTPUT_OBJC_ZIP" *
  popd

  # Swift
  echo "Make Swift framework zip file ..."
  mkdir -p "$OUTPUT_SWIFT_DIR"
  cp -R "$BUILD_DIR/${SCHEME_PREFIX}_Swift"/* "$OUTPUT_SWIFT_DIR"
  if [[ -n $WORKSPACE ]]; then
      cp ${WORKSPACE}/product-texts/mobile/couchbase-lite/license/LICENSE_${EDITION}.txt "$OUTPUT_SWIFT_DIR"/LICENSE.txt
  fi
  pushd "$OUTPUT_SWIFT_DIR" > /dev/null
  zip -ry "$OUTPUT_SWIFT_ZIP" *
  popd > /dev/null

  # Generate API docs:
  echo "Generate API docs ..."
  OBJC_UMBRELLA_HEADER=`find $OUTPUT_OBJC_DIR -name "CouchbaseLite.h"`
  sh Scripts/generate_api_docs.sh -o "$OUTPUT_DOCS_DIR" -h "$OBJC_UMBRELLA_HEADER" $EXTRA_CMD_OPTIONS
  # >> Objective-C API
  pushd "$OUTPUT_OBJC_DOCS_DIR" > /dev/null
  zip -ry "$OUTPUT_OBJC_DOCS_ZIP" *
  popd > /dev/null
  # >> Swift API docs
  pushd "$OUTPUT_SWIFT_DOCS_DIR" > /dev/null
  zip -ry "$OUTPUT_SWIFT_DOCS_ZIP" *
  popd > /dev/null
fi

if [[ ! -z $COMBINED ]] || [[ ! -z $XCFRAMEWORK ]]
then
  echo "Building xcframework..."
  set -o pipefail && sh Scripts/build_xcframework.sh -s "${SCHEME_PREFIX}_Swift" -c "$CONFIGURATION" -o "$BUILD_DIR" -v "$VERSION" | $XCPRETTY
  set -o pipefail && sh Scripts/build_xcframework.sh -s "${SCHEME_PREFIX}_ObjC" -c "$CONFIGURATION" -o "$BUILD_DIR" -v "$VERSION" | $XCPRETTY

  echo "Make Swift xcframework zip file ..."
  mkdir -p "$OUTPUT_SWIFT_XC_DIR"
  cp -R "$BUILD_DIR/xc/${SCHEME_PREFIX}_Swift"/* "$OUTPUT_SWIFT_XC_DIR"
  if [[ -n $WORKSPACE ]]; then
      cp ${WORKSPACE}/product-texts/mobile/couchbase-lite/license/LICENSE_${EDITION}.txt "$OUTPUT_SWIFT_XC_DIR"/LICENSE.txt
  fi
  pushd "$OUTPUT_SWIFT_XC_DIR" > /dev/null
  zip -ry "$OUTPUT_SWIFT_XC_ZIP" *
  popd > /dev/null
  
  echo "Make ObjC XCFramework zip file ..."
  mkdir -p "$OUTPUT_OBJC_XC_DIR"
  cp -R "$BUILD_DIR/xc/${SCHEME_PREFIX}_ObjC"/* "$OUTPUT_OBJC_XC_DIR"
  if [[ -n $WORKSPACE ]]; then
      cp ${WORKSPACE}/product-texts/mobile/couchbase-lite/license/LICENSE_${EDITION}.txt "$OUTPUT_OBJC_XC_DIR"/LICENSE.txt
  fi
  pushd "$OUTPUT_OBJC_XC_DIR" > /dev/null
  zip -ry "$OUTPUT_OBJC_XC_ZIP" *
  popd > /dev/null

  # Generate swift checksum file:
  echo "Generate swift package checksum..."
  sh Scripts/generate_package_manifest.sh -zip-path "$OUTPUT_DIR/couchbase-lite-swift_xc_$EDITION$VERSION_SUFFIX.zip" -o $OUTPUT_DIR $EXTRA_CMD_OPTIONS
  sh Scripts/generate_package_manifest.sh -zip-path "$OUTPUT_DIR/couchbase-lite-objc_xc_$EDITION$VERSION_SUFFIX.zip" -o $OUTPUT_DIR $EXTRA_CMD_OPTIONS
fi

# Cleanup
rm -rf "$BUILD_DIR"
rm -rf "$OUTPUT_OBJC_DIR"
rm -rf "$OUTPUT_SWIFT_DIR"
rm -rf "$OUTPUT_SWIFT_XC_DIR"
rm -rf "$OUTPUT_DOCS_DIR"
