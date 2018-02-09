#!/bin/bash

set -e

function usage
{
  echo "Usage: ${0} -o <Output Directory> [-v <Version (<Version Number>[-<Build Number>])>] [--notest]"
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
      --notest)
      NO_TEST=YES
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

#Clean output directory:
rm -rf "$OUTPUT_DIR"

# Check xcodebuild version:
echo "Check xcodebuild version ..."
xcodebuild -version

if [ -z "$NO_TEST" ]
then
  echo "Check devices ..."
  instruments -s devices

  echo "Run ObjC macOS Test ..."
  xcodebuild test -project CouchbaseLite.xcodeproj -scheme "CBL ObjC" -sdk macosx

  echo "Run ObjC iOS Test ..."
  xcodebuild test -project CouchbaseLite.xcodeproj -scheme "CBL ObjC" -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 6'

  echo "Run Swift macOS Test ..."
  xcodebuild test -project CouchbaseLite.xcodeproj -scheme "CBL Swift" -sdk macosx

  echo "Run Swift iOS Test ..."
  xcodebuild test -project CouchbaseLite.xcodeproj -scheme "CBL Swift" -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 6'

  echo "Generate Test Coverage Reports ..."
  OUTPUT_COVERAGE_DIR=$OUTPUT_DIR/test_coverage
  sh Scripts/generate_coverage.sh -o "$OUTPUT_COVERAGE_DIR"
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

OUTPUT_OBJC_COMMUNITY_DIR=$OUTPUT_DIR/objc_community
OUTPUT_OBJC_ENTERPRISE_DIR=$OUTPUT_DIR/objc_enterprise
OUTPUT_OBJC_COMMUNITY_ZIP=../couchbase-lite-objc_community$VERSION_SUFFIX.zip
OUTPUT_OBJC_ENTERPRISE_ZIP=../couchbase-lite-objc_enterprise$VERSION_SUFFIX.zip

OUTPUT_SWIFT_COMMUNITY_DIR=$OUTPUT_DIR/swift_community
OUTPUT_SWIFT_ENTERPRISE_DIR=$OUTPUT_DIR/swift_enterprise
OUTPUT_SWIFT_COMMUNITY_ZIP=../couchbase-lite-swift_community$VERSION_SUFFIX.zip
OUTPUT_SWIFT_ENTERPRISE_ZIP=../couchbase-lite-swift_enterprise$VERSION_SUFFIX.zip

OUTPUT_DOCS_DIR=$OUTPUT_DIR/docs
OUTPUT_OBJC_DOCS_DIR=$OUTPUT_DOCS_DIR/CouchbaseLite
OUTPUT_OBJC_DOCS_ZIP=../../couchbase-lite-objc-documentation$VERSION_SUFFIX.zip
OUTPUT_SWIFT_DOCS_DIR=$OUTPUT_DOCS_DIR/CouchbaseLiteSwift
OUTPUT_SWIFT_DOCS_ZIP=../../couchbase-lite-swift-documentation$VERSION_SUFFIX.zip

sh Scripts/build_framework.sh -s "CBL ObjC" -p iOS -o "$BUILD_DIR" -v "$VERSION"
sh Scripts/build_framework.sh -s "CBL ObjC" -p tvOS -o "$BUILD_DIR" -v "$VERSION"
sh Scripts/build_framework.sh -s "CBL ObjC" -p macOS -o "$BUILD_DIR" -v "$VERSION"

sh Scripts/build_framework.sh -s "CBL Swift" -p iOS -o "$BUILD_DIR" -v "$VERSION"
sh Scripts/build_framework.sh -s "CBL Swift" -p tvOS -o "$BUILD_DIR" -v "$VERSION"
sh Scripts/build_framework.sh -s "CBL Swift" -p macOS -o "$BUILD_DIR" -v "$VERSION"

# Build tools:
echo "Build Development Tools ..."
TOOLS_DIR="$BUILD_DIR/Tools"
mkdir "$TOOLS_DIR"
cp vendor/couchbase-lite-core/tools/README.md "$TOOLS_DIR"
vendor/couchbase-lite-core/Xcode/build_tool.sh -t 'cblite' -o "$TOOLS_DIR" -v "$VERSION"
vendor/couchbase-lite-core/Xcode/build_tool.sh -t 'litecorelog' -o "$TOOLS_DIR" -v "$VERSION"

# Objective-C Community
mkdir -p "$OUTPUT_OBJC_COMMUNITY_DIR"
cp -R "$BUILD_DIR/CBL ObjC"/* "$OUTPUT_OBJC_COMMUNITY_DIR"
cp Scripts/Support/License/LICENSE_community.txt "$OUTPUT_OBJC_COMMUNITY_DIR"/LICENSE.txt
cp -R "$TOOLS_DIR" "$OUTPUT_OBJC_COMMUNITY_DIR"
pushd "$OUTPUT_OBJC_COMMUNITY_DIR"
zip -ry "$OUTPUT_OBJC_COMMUNITY_ZIP" *
popd

# Objective-C Enterprise
mkdir -p "$OUTPUT_OBJC_ENTERPRISE_DIR"
cp -R "$BUILD_DIR/CBL ObjC"/* "$OUTPUT_OBJC_ENTERPRISE_DIR"
cp Scripts/Support/License/LICENSE_enterprise.txt "$OUTPUT_OBJC_ENTERPRISE_DIR/LICENSE.txt"
cp -R "$TOOLS_DIR" "$OUTPUT_OBJC_ENTERPRISE_DIR"
pushd "$OUTPUT_OBJC_ENTERPRISE_DIR"
zip -ry "$OUTPUT_OBJC_ENTERPRISE_ZIP" *
popd

# Swift Community
mkdir -p "$OUTPUT_SWIFT_COMMUNITY_DIR"
cp -R "$BUILD_DIR/CBL Swift"/* "$OUTPUT_SWIFT_COMMUNITY_DIR"
cp Scripts/Support/License/LICENSE_community.txt "$OUTPUT_SWIFT_COMMUNITY_DIR"/LICENSE.txt
cp -R "$TOOLS_DIR" "$OUTPUT_SWIFT_COMMUNITY_DIR"
pushd "$OUTPUT_SWIFT_COMMUNITY_DIR"
zip -ry "$OUTPUT_SWIFT_COMMUNITY_ZIP" *
popd

# Swift Enterprise
mkdir -p "$OUTPUT_SWIFT_ENTERPRISE_DIR"
cp -R "$BUILD_DIR/CBL Swift"/* "$OUTPUT_SWIFT_ENTERPRISE_DIR"
cp Scripts/Support/License/LICENSE_enterprise.txt "$OUTPUT_SWIFT_ENTERPRISE_DIR/LICENSE.txt"
cp -R "$TOOLS_DIR" "$OUTPUT_SWIFT_ENTERPRISE_DIR"
pushd "$OUTPUT_SWIFT_ENTERPRISE_DIR"
zip -ry "$OUTPUT_SWIFT_ENTERPRISE_ZIP" *
popd

# Generate MD5 file:
echo "Generate MD5 files ..."
pushd "$OUTPUT_DIR"
md5 couchbase-lite-objc_community$VERSION_SUFFIX.zip > couchbase-lite-objc_community$VERSION_SUFFIX.zip.md5
md5 couchbase-lite-objc_enterprise$VERSION_SUFFIX.zip > couchbase-lite-objc_enterprise$VERSION_SUFFIX.zip.md5
md5 couchbase-lite-swift_community$VERSION_SUFFIX.zip > couchbase-lite-swift_community$VERSION_SUFFIX.zip.md5
md5 couchbase-lite-swift_enterprise$VERSION_SUFFIX.zip > couchbase-lite-swift_enterprise$VERSION_SUFFIX.zip.md5
popd

# Generate API docs:
echo "Generate API docs ..."
sh Scripts/generate_api_docs.sh -o "$OUTPUT_DOCS_DIR"
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
rm -rf "$OUTPUT_OBJC_COMMUNITY_DIR"
rm -rf "$OUTPUT_OBJC_ENTERPRISE_DIR"
rm -rf "$OUTPUT_SWIFT_COMMUNITY_DIR"
rm -rf "$OUTPUT_SWIFT_ENTERPRISE_DIR"
rm -rf "$OUTPUT_DOCS_DIR"
