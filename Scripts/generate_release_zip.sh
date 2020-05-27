#!/bin/bash

set -e

function usage
{
  echo "Usage: ${0} -o <Output Directory> [-v <Version (<Version Number>[-<Build Number>])>] [--xcframework] [--EE] [--notest] [--nocov] [--pretty]"
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

# Clean DerivedData
DERIVED_DATA_DIR=`xcodebuild -showBuildSettings|grep -w OBJROOT|head -n 1|awk '{ print $3 }'|grep -o '.*CouchbaseLite-[^\/]*'`
echo "Clean DerivedData directory: $DERIVED_DATA_DIR"
rm -rf "$DERIVED_DATA_DIR"

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
  instruments -s devices

  echo "Run ObjC macOS tests ..."
  xcodebuild test -project CouchbaseLite.xcodeproj -scheme "${SCHEME_PREFIX}_ObjC" -configuration "$CONFIGURATION_TEST" -sdk macosx

  echo "Run ObjC iOS tests ..."
  xcodebuild test -project CouchbaseLite.xcodeproj -scheme "${SCHEME_PREFIX}_ObjC" -configuration "$CONFIGURATION_TEST" -sdk iphonesimulator -destination "$TEST_SIMULATOR" -enableCodeCoverage YES

  if [ -z "$NO_COV" ]
  then
    # Objective-C:
    echo "Generate coverage report for ObjC ..."
    slather coverage --html --scheme "${SCHEME_PREFIX}_ObjC" --configuration "$CONFIGURATION_TEST" --ignore "vendor/*" --ignore "Swift/*" --ignore "Objective-C/Tests/*" --ignore "../Sources/Swift/*" --output-directory "$OUTPUT_DIR/$COVERAGE_NAME/Objective-C" CouchbaseLite.xcodeproj > /dev/null
  fi

  echo "Run Swift macOS tests ..."
  xcodebuild test -project CouchbaseLite.xcodeproj -scheme "${SCHEME_PREFIX}_Swift" -configuration "$CONFIGURATION_TEST" -sdk macosx

  echo "Run Swift iOS tests ..."
  xcodebuild test -project CouchbaseLite.xcodeproj -scheme "${SCHEME_PREFIX}_Swift" -configuration "$CONFIGURATION_TEST" -sdk iphonesimulator -destination "$TEST_SIMULATOR" -enableCodeCoverage YES
  
  # Generage Code Coverage Reports:
  if [ -z "$NO_COV" ]
  then
    # Swift:
    echo "Generate coverage report for Swift ..."
    slather coverage --html --scheme "${SCHEME_PREFIX}_Swift" --configuration "$CONFIGURATION_TEST"  --ignore "vendor/*" --ignore "Objective-C/*" --ignore "Swift/Tests/*" --ignore "../Sources/Objective-C/*" --output-directory "$OUTPUT_DIR/$COVERAGE_NAME/Swift" CouchbaseLite.xcodeproj > /dev/null
    
    # Zip reports:
    pushd "$OUTPUT_DIR" > /dev/null
    zip -ry $COVERAGE_NAME.zip $COVERAGE_NAME/*
    popd > /dev/null
    rm -rf "$OUTPUT_DIR/$COVERAGE_NAME"
  fi
fi

VERSION_SUFFIX=""
if [ ! -z "$VERSION" ]
then
  VERSION_SUFFIX="_$VERSION"
fi

# Build frameworks:
echo "Build CouchbaseLite framework ..."

BUILD_DIR=$OUTPUT_DIR/build

OUTPUT_OBJC_DIR=$OUTPUT_DIR/objc_$EDITION
OUTPUT_OBJC_ZIP=../couchbase-lite-objc_$EDITION$VERSION_SUFFIX.zip

OUTPUT_SWIFT_DIR=$OUTPUT_DIR/swift_$EDITION
OUTPUT_SWIFT_ZIP=../couchbase-lite-swift_$EDITION$VERSION_SUFFIX.zip

OUTPUT_DOCS_DIR=$OUTPUT_DIR/docs
OUTPUT_OBJC_DOCS_DIR=$OUTPUT_DOCS_DIR/CouchbaseLite
OUTPUT_OBJC_DOCS_ZIP=../../couchbase-lite-objc-documentation_$EDITION$VERSION_SUFFIX.zip
OUTPUT_SWIFT_DOCS_DIR=$OUTPUT_DOCS_DIR/CouchbaseLiteSwift
OUTPUT_SWIFT_DOCS_ZIP=../../couchbase-lite-swift-documentation_$EDITION$VERSION_SUFFIX.zip

if [[ -z $XCFRAMEWORK ]]
then
  sh Scripts/build_framework.sh -s "${SCHEME_PREFIX}_ObjC" -c "$CONFIGURATION" -p iOS -o "$BUILD_DIR" -v "$VERSION" | $XCPRETTY
  sh Scripts/build_framework.sh -s "${SCHEME_PREFIX}_ObjC" -c "$CONFIGURATION" -p macOS -o "$BUILD_DIR" -v "$VERSION" | $XCPRETTY
  sh Scripts/build_framework.sh -s "${SCHEME_PREFIX}_Swift" -c "$CONFIGURATION" -p iOS -o "$BUILD_DIR" -v "$VERSION" | $XCPRETTY
  sh Scripts/build_framework.sh -s "${SCHEME_PREFIX}_Swift" -c "$CONFIGURATION" -p macOS -o "$BUILD_DIR" -v "$VERSION" | $XCPRETTY
else
  # xcframework
  sh Scripts/build_xcframework.sh -s "${SCHEME_PREFIX}_ObjC" -c "$CONFIGURATION" -o "$BUILD_DIR" -v "$VERSION" | $XCPRETTY
  sh Scripts/build_xcframework.sh -s "${SCHEME_PREFIX}_Swift" -c "$CONFIGURATION" -o "$BUILD_DIR" -v "$VERSION" | $XCPRETTY
fi

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

# Generate MD5 files:
echo "Generate MD5 files ..."
pushd "$OUTPUT_DIR" > /dev/null
md5 couchbase-lite-objc_$EDITION$VERSION_SUFFIX.zip > couchbase-lite-objc_$EDITION$VERSION_SUFFIX.zip.md5
md5 couchbase-lite-swift_$EDITION$VERSION_SUFFIX.zip > couchbase-lite-swift_$EDITION$VERSION_SUFFIX.zip.md5
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

# Cleanup
rm -rf "$BUILD_DIR"
rm -rf "$OUTPUT_OBJC_DIR"
rm -rf "$OUTPUT_SWIFT_DIR"
rm -rf "$OUTPUT_DOCS_DIR"
