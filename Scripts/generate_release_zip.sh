#!/bin/bash

set -e

function usage
{
  echo "Usage: ${0} -o <Output Directory> [-v <Version (<Version Number>[-<Build Number>])>] [--EE] [--notest] [--pretty]"
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
  EDITION="community"
  EXTRA_CMD_OPTIONS=""
  TEST_SIMULATOR="platform=iOS Simulator,name=iPhone 6"
else
  SCHEME_PREFIX="CBL-EE"
  CONFIGURATION="Release-EE"
  EDITION="enterprise"
  EXTRA_CMD_OPTIONS="--EE"
  TEST_SIMULATOR="platform=iOS Simulator,name=iPhone X"
fi

if [ -z "$PRETTY" ]
then
  XCPRETTY="cat"
  PRETTY_OPT=""
else
  XCPRETTY="xcpretty"
  PRETTY_OPT="pretty"
fi

#Clean output directory:
rm -rf "$OUTPUT_DIR"

# Check xcodebuild version:
echo "Check xcodebuild version ..."
xcodebuild -version

if [ -z "$NO_TEST" ]
then
  echo "Check devices ..."
  instruments -s devices

  # Create test logs folder
  rm -rf TestLogs && mkdir TestLogs

  echo "Run ObjC macOS Test ..."
  set -o pipefail && xcodebuild test -project CouchbaseLite.xcodeproj -scheme "$SCHEME_PREFIX ObjC" -sdk macosx | tee TestLogs/ObjC_MacOS.log | "$XCPRETTY"

  echo "Run ObjC iOS Test ..."
  set -o pipefail && xcodebuild test -project CouchbaseLite.xcodeproj -scheme "$SCHEME_PREFIX ObjC" -sdk iphonesimulator -destination "$TEST_SIMULATOR" | tee TestLogs/ObjC_iOS.log | "$XCPRETTY"

  echo "Run Swift macOS Test ..."
  set -o pipefail && xcodebuild test -project CouchbaseLite.xcodeproj -scheme "$SCHEME_PREFIX Swift" -sdk macosx | tee TestLogs/Swift_MacOS.log | "$XCPRETTY"

  echo "Run Swift iOS Test ..."
  set -o pipefail && xcodebuild test -project CouchbaseLite.xcodeproj -scheme "$SCHEME_PREFIX Swift" -sdk iphonesimulator -destination "$TEST_SIMULATOR" | tee TestLogs/Swift_iOS.log | "$XCPRETTY"
  
  # Zip test logs
  zip TestLogs.zip TestLogs && rm -rf TestLogs

  echo "Generate Test Coverage Reports ..."
  OUTPUT_COVERAGE_DIR=$OUTPUT_DIR/test_coverage
  sh Scripts/generate_coverage.sh -o "$OUTPUT_COVERAGE_DIR" $EXTRA_CMD_OPTIONS
  zip -ry "$OUTPUT_DIR/test_coverage.zip" "$OUTPUT_COVERAGE_DIR"
  rm -rf "$OUTPUT_COVERAGE_DIR"
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

sh Scripts/build_framework.sh -s "$SCHEME_PREFIX ObjC" -c "$CONFIGURATION" -p iOS -o "$BUILD_DIR" -v "$VERSION" | "$XCPRETTY"
sh Scripts/build_framework.sh -s "$SCHEME_PREFIX ObjC" -c "$CONFIGURATION" -p macOS -o "$BUILD_DIR" -v "$VERSION" | "$XCPRETTY"
sh Scripts/build_framework.sh -s "$SCHEME_PREFIX Swift" -c "$CONFIGURATION" -p iOS -o "$BUILD_DIR" -v "$VERSION" | "$XCPRETTY"
sh Scripts/build_framework.sh -s "$SCHEME_PREFIX Swift" -c "$CONFIGURATION" -p macOS -o "$BUILD_DIR" -v "$VERSION" | "$XCPRETTY"

# Objective-C
echo "Make Objective-C framework zip file ..."
mkdir -p "$OUTPUT_OBJC_DIR"
cp -R "$BUILD_DIR/$SCHEME_PREFIX ObjC"/* "$OUTPUT_OBJC_DIR"
if [[ -z ${WORKSPACE} ]]; then
    cp Scripts/Support/License/LICENSE_${EDITION}.txt "$OUTPUT_OBJC_DIR"/LICENSE.txt
else # official Jenkins build's license
    cp ${WORKSPACE}/build/license/couchbase-lite/LICENSE_${EDITION}.txt "$OUTPUT_OBJC_DIR"/LICENSE.txt
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
    cp ${WORKSPACE}/build/license/couchbase-lite/LICENSE_${EDITION}.txt "$OUTPUT_SWIFT_DIR"/LICENSE.txt
fi
pushd "$OUTPUT_SWIFT_DIR"
zip -ry "$OUTPUT_SWIFT_ZIP" *
popd

# Generate MD5 files:
echo "Generate MD5 files ..."
pushd "$OUTPUT_DIR"
md5 couchbase-lite-objc_$EDITION$VERSION_SUFFIX.zip > couchbase-lite-objc_$EDITION$VERSION_SUFFIX.zip.md5
md5 couchbase-lite-swift_$EDITION$VERSION_SUFFIX.zip > couchbase-lite-swift_$EDITION$VERSION_SUFFIX.zip.md5
popd

# Generate API docs:
echo "Generate API docs ..."
OBJC_UMBRELLA_HEADER=`find $OUTPUT_OBJC_DIR -name "CouchbaseLite.h"`
sh Scripts/generate_api_docs.sh -o "$OUTPUT_DOCS_DIR" -h "$OBJC_UMBRELLA_HEADER" $EXTRA_CMD_OPTIONS
# >> Objective-C API
pushd "$OUTPUT_OBJC_DOCS_DIR"
zip -ry "$OUTPUT_OBJC_DOCS_ZIP" *
popd
# >> Swift API docs
pushd "$OUTPUT_SWIFT_DOCS_DIR"
zip -ry "$OUTPUT_SWIFT_DOCS_ZIP" *
popd

# Cleanup
rm -rf "$BUILD_DIR"
rm -rf "$OUTPUT_OBJC_DIR"
rm -rf "$OUTPUT_SWIFT_DIR"
rm -rf "$OUTPUT_DOCS_DIR"
