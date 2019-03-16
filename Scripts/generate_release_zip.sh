#!/bin/bash

set -e

function usage
{
  echo "Usage: ${0} -o <Output Directory> [-v <Version (<Version Number>[-<Build Number>])>] [--EE] [--notest] [--nocov] [--pretty]"
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
  COVERAGE_ZIP_FILE="coverage.zip"
  EDITION="community"
  EXTRA_CMD_OPTIONS=""
  TEST_SIMULATOR="platform=iOS Simulator,name=iPhone 6"
else
  SCHEME_PREFIX="CBL-EE"
  CONFIGURATION="Release-EE"
  CONFIGURATION_TEST="Debug-EE"
  COVERAGE_ZIP_FILE="coverage-ee.zip"
  EDITION="enterprise"
  EXTRA_CMD_OPTIONS="--EE"
  TEST_SIMULATOR="platform=iOS Simulator,name=iPhone X"
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
rm -rf "$OUTPUT_DIR"

# Clean OBJROOT and SYSROOT Directory:
OBJROOT_DIR=`xcodebuild -showBuildSettings|grep -w OBJROOT|head -n 1|awk '{ print $3 }'`
rm -rf "${OBJROOT_DIR}"
SYMROOT_DIR=`xcodebuild -showBuildSettings|grep -w SYMROOT|head -n 1|awk '{ print $3 }'`
rm -rf "${SYMROOT_DIR}"

# Check xcodebuild version:
echo "Check xcodebuild version ..."
xcodebuild -version

if [ -z "$NO_TEST" ]
then
  echo "Check devices ..."
  instruments -s devices

  echo "Run ObjC macOS Test ..."
  set -o pipefail && xcodebuild test -project CouchbaseLite.xcodeproj -scheme "$SCHEME_PREFIX ObjC" -configuration "${CONFIGURATION_TEST}" -sdk macosx | $XCPRETTY

  echo "Run ObjC iOS Test ..."
  set -o pipefail && xcodebuild test -project CouchbaseLite.xcodeproj -scheme "$SCHEME_PREFIX ObjC" -configuration "${CONFIGURATION_TEST}" -sdk iphonesimulator -destination "$TEST_SIMULATOR" -enableCodeCoverage YES | $XCPRETTY

  if [ -z "$NO_COV" ]
  then
    # Objective-C:
    echo "Generate Coverage Report for ObjC ..."
    slather coverage --html --scheme "$SCHEME_PREFIX ObjC" --configuration "${CONFIGURATION_TEST}" --ignore "vendor/*" --ignore "Swift/*" --output-directory "$OUTPUT_DIR/coverage/Objective-C" CouchbaseLite.xcodeproj > /dev/null
  fi

  echo "Run Swift macOS Test ..."
  set -o pipefail && xcodebuild test -project CouchbaseLite.xcodeproj -scheme "$SCHEME_PREFIX Swift" -configuration "${CONFIGURATION_TEST}" -sdk macosx | $XCPRETTY

  echo "Run Swift iOS Test ..."
  set -o pipefail && xcodebuild test -project CouchbaseLite.xcodeproj -scheme "$SCHEME_PREFIX Swift" -configuration "${CONFIGURATION_TEST}" -sdk iphonesimulator -destination "$TEST_SIMULATOR" -enableCodeCoverage YES | $XCPRETTY
  
  # Generage Code Coverage Reports:
  if [ -z "$NO_COV" ]
  then
    # Swift:
    echo "Generate Coverage Report for Swift ..."
    slather coverage --html --scheme "$SCHEME_PREFIX Swift" --configuration "${CONFIGURATION_TEST}"  --ignore "vendor/*" --ignore "Objective-C/*" --output-directory "$OUTPUT_DIR/coverage/Swift" CouchbaseLite.xcodeproj > /dev/null
    
    # Zip reports:
    pushd "$OUTPUT_DIR" > /dev/null
    zip -ry "$COVERAGE_ZIP_FILE" coverage/*
    popd > /dev/null
    rm -rf "$OUTPUT_DIR/coverage"
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

sh Scripts/build_framework.sh -s "$SCHEME_PREFIX ObjC" -c "$CONFIGURATION" -p iOS -o "$BUILD_DIR" -v "$VERSION" | $XCPRETTY
sh Scripts/build_framework.sh -s "$SCHEME_PREFIX ObjC" -c "$CONFIGURATION" -p macOS -o "$BUILD_DIR" -v "$VERSION" | $XCPRETTY
sh Scripts/build_framework.sh -s "$SCHEME_PREFIX Swift" -c "$CONFIGURATION" -p iOS -o "$BUILD_DIR" -v "$VERSION" | $XCPRETTY
sh Scripts/build_framework.sh -s "$SCHEME_PREFIX Swift" -c "$CONFIGURATION" -p macOS -o "$BUILD_DIR" -v "$VERSION" | $XCPRETTY

# Objective-C
echo "Make Objective-C framework zip file ..."
mkdir -p "$OUTPUT_OBJC_DIR"
cp -R "$BUILD_DIR/$SCHEME_PREFIX ObjC"/* "$OUTPUT_OBJC_DIR"
if [[ -z ${WORKSPACE} ]]; then
    cp Scripts/Support/License/LICENSE_${EDITION}.txt "$OUTPUT_OBJC_DIR"/LICENSE.txt
else # official Jenkins build's license
    cp ${WORKSPACE}/product-texts/mobile/couchbase-lite/license/LICENSE_${EDITION}.txt "$OUTPUT_OBJC_DIR"/LICENSE.txt
fi
pushd "$OUTPUT_OBJC_DIR"
zip -ry "$OUTPUT_OBJC_ZIP" *
popd

# Swift
echo "Make Swift framework zip file ..."
mkdir -p "$OUTPUT_SWIFT_DIR"
cp -R "$BUILD_DIR/$SCHEME_PREFIX Swift"/* "$OUTPUT_SWIFT_DIR"
if [[ -z ${WORKSPACE} ]]; then
    cp Scripts/Support/License/LICENSE_${EDITION}.txt "$OUTPUT_SWIFT_DIR"/LICENSE.txt
else # official Jenkins build's license
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
