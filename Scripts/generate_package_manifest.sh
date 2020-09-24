#!/bin/sh

set -e

function usage
{
  echo "Usage: ${0} -zip-path <path to xcframework zip> -o <output file path> --EE"
}

while [[ $# -gt 0 ]]
do
  key=${1}
  case $key in
      -v)
      VERSION=${2}
      shift
      ;;
      -zip-path)
      ZIP_PATH=${2}
      shift
      ;;
      --EE)
      EE=YES
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

PRODUCT_NAME="CouchbaseLiteSwift"
SWIFT_VERSION=`swift -version |  awk '{ print $4 }'`
CHECKSUM="dummy"

#creates the manifest file with filename as the first arg
function createManifest
{
  eval "echo \"$(cat  << EOF
// swift-tools-version:$SWIFT_VERSION
import PackageDescription
 
let package = Package(
    name: \"$PRODUCT_NAME\",
    products: [\"$PRODUCT_NAME\"],
    targets: [
        .binaryTarget(
            name: \"$PRODUCT_NAME\",
            checksum: \"$CHECKSUM\"
        )
    ]
))\"" > ${1}
}

# create & removes a dummy package to generate checksum
createManifest "Package.swift"
CHECKSUM=`swift package compute-checksum ${ZIP_PATH}`
rm "Package.swift"

# generates the package manifest
if [ -z "$EE" ]
then
  createManifest $OUTPUT_DIR/"Package_CE.swift"
else
  createManifest $OUTPUT_DIR/"Package_EE.swift"
fi
