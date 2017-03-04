#!/bin/bash

set -e

function usage 
{
  echo "\nUsage: ${0} -o <Output Directory> [-v <Version String>]\n" 
}

while [[ $# -gt 1 ]]
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

VERSION_SUFFIX=""
if [ ! -z "$VERSION" ]
then
  VERSION_SUFFIX="_$VERSION"
fi

BUILD_DIR=$OUTPUT_DIR/build

OUTPUT_OBJC_COMMUNITY_DIR=$OUTPUT_DIR/objc_community
OUTPUT_OBJC_ENTERPRISE_DIR=$OUTPUT_DIR/objc_enterprise
OUTPUT_OBJC_COMMUNITY_ZIP=`pwd`/$OUTPUT_DIR/couchbase-lite-objc_community$VERSION_SUFFIX.zip
OUTPUT_OBJC_ENTERPRISE_ZIP=`pwd`/$OUTPUT_DIR/couchbase-lite-objc_enterprise$VERSION_SUFFIX.zip

OUTPUT_SWIFT_COMMUNITY_DIR=$OUTPUT_DIR/swift_community
OUTPUT_SWIFT_ENTERPRISE_DIR=$OUTPUT_DIR/swift_enterprise
OUTPUT_SWIFT_COMMUNITY_ZIP=`pwd`/$OUTPUT_DIR/couchbase-lite-swift_community$VERSION_SUFFIX.zip
OUTPUT_SWIFT_ENTERPRISE_ZIP=`pwd`/$OUTPUT_DIR/couchbase-lite-swift_enterprise$VERSION_SUFFIX.zip

rm -rf "$OUTPUT_DIR"

sh Scripts/build_framework.sh -s "CBL ObjC" -p iOS -o "$BUILD_DIR" -v "$VERSION"
sh Scripts/build_framework.sh -s "CBL ObjC" -p tvOS -o "$BUILD_DIR" -v "$VERSION"
sh Scripts/build_framework.sh -s "CBL ObjC" -p macOS -o "$BUILD_DIR" -v "$VERSION"

sh Scripts/build_framework.sh -s "CBL Swift" -p iOS -o "$BUILD_DIR" -v "$VERSION"
sh Scripts/build_framework.sh -s "CBL Swift" -p tvOS -o "$BUILD_DIR" -v "$VERSION"
sh Scripts/build_framework.sh -s "CBL Swift" -p macOS -o "$BUILD_DIR" -v "$VERSION"

# Objective-C Community
mkdir -p "$OUTPUT_OBJC_COMMUNITY_DIR"
cp -R "$BUILD_DIR/CBL ObjC"/* "$OUTPUT_OBJC_COMMUNITY_DIR"
cp Scripts/Support/License/LICENSE_community.txt "$OUTPUT_OBJC_COMMUNITY_DIR"/LICENSE.txt
pushd "$OUTPUT_OBJC_COMMUNITY_DIR"
zip -ry "$OUTPUT_OBJC_COMMUNITY_ZIP" *
popd

# Objective-C Enterprise
mkdir -p "$OUTPUT_OBJC_ENTERPRISE_DIR"
cp -R "$BUILD_DIR/CBL ObjC"/* "$OUTPUT_OBJC_ENTERPRISE_DIR"
cp Scripts/Support/License/LICENSE_enterprise.txt "$OUTPUT_OBJC_ENTERPRISE_DIR/LICENSE.txt"
pushd "$OUTPUT_OBJC_ENTERPRISE_DIR"
zip -ry "$OUTPUT_OBJC_ENTERPRISE_ZIP" *
popd

# Swift Community
mkdir -p "$OUTPUT_SWIFT_COMMUNITY_DIR"
cp -R "$BUILD_DIR/CBL Swift"/* "$OUTPUT_SWIFT_COMMUNITY_DIR"
cp Scripts/Support/License/LICENSE_community.txt "$OUTPUT_SWIFT_COMMUNITY_DIR"/LICENSE.txt
pushd "$OUTPUT_SWIFT_COMMUNITY_DIR"
zip -ry "$OUTPUT_SWIFT_COMMUNITY_ZIP" *
popd

# Swift Enterprise
mkdir -p "$OUTPUT_SWIFT_ENTERPRISE_DIR"
cp -R "$BUILD_DIR/CBL Swift"/* "$OUTPUT_SWIFT_ENTERPRISE_DIR"
cp Scripts/Support/License/LICENSE_enterprise.txt "$OUTPUT_SWIFT_ENTERPRISE_DIR/LICENSE.txt"
pushd "$OUTPUT_SWIFT_ENTERPRISE_DIR"
zip -ry "$OUTPUT_SWIFT_ENTERPRISE_ZIP" *
popd

# Generate MD5 file:
pushd "$OUTPUT_DIR"
md5 *.zip > MD5.txt
popd

# Cleanup
rm -rf "$BUILD_DIR"
rm -rf "$OUTPUT_OBJC_COMMUNITY_DIR"
rm -rf "$OUTPUT_OBJC_ENTERPRISE_DIR"
rm -rf "$OUTPUT_SWIFT_COMMUNITY_DIR"
rm -rf "$OUTPUT_SWIFT_ENTERPRISE_DIR"
