#!/bin/sh

set -e

function usage
{
  echo "Usage: ${0} -s <Scheme: \"CBL ObjC\" or \"CBL Swift\"> -o <Output Directory> [-v <Version (<Version Number>[-<Build Number>])>] [--quiet]"
}

while [[ $# -gt 0 ]]
do
  key=${1}
  case $key in
    -s)
    SCHEME=${2}
    shift
    ;;
    -o)
    OUTPUT_DIR=${2}
    shift
    ;;
    -v)
    VERSION=${2}
    shift
    ;;
    --quiet)
    QUIET="Y"
    ;;
    *)
    usage
    exit 3
    ;;
  esac
  shift
done

if [ -z "$SCHEME" ] || [ -z "$OUTPUT_DIR" ]
then
  usage
  exit 4
fi

CONFIGURATION="Release"
echo "Scheme: ${SCHEME}"
echo "Configuration : ${CONFIGURATION}"
echo "Output Directory: ${OUTPUT_DIR}"
echo "Version: ${VERSION}"

if [ -z "$QUIET" ]
then
  echo "QUIET: NO"
  QUIET=""
else
  echo "QUIET: YES"
  QUIET="-quiet"
fi

OUTPUT_BASE_DIR=${OUTPUT_DIR}/${SCHEME}
rm -rf "${OUTPUT_BASE_DIR}"

# Get binary and framework name:
BIN_NAME=`xcodebuild -scheme "${SCHEME}" -showBuildSettings|grep -w PRODUCT_NAME|head -n 1|awk '{ print $3 }'`
FRAMEWORK_FILE_NAME=${BIN_NAME}.framework

BUILD_VERSION=""
BUILD_NUMBER=""
if [ ! -z "$VERSION" ]
then
  IFS='-' read -a VERSION_ITEMS <<< "${VERSION}"
  if [[ ${#VERSION_ITEMS[@]} > 1 ]]
  then
    BUILD_VERSION="CBL_VERSION_STRING=${VERSION_ITEMS[0]}"
    BUILD_NUMBER="CBL_BUILD_NUMBER=${VERSION_ITEMS[1]}"
  else
    BUILD_VERSION="CBL_VERSION_STRING=${VERSION}"
  fi
fi

# archive
DESTINATIONS=("iOS" "macOS")
INDEX=1
for DESTINATION in "${DESTINATIONS[@]}"
do
  echo "Exporting ${DESTINATION}!!"
  ARCHIVE_PATH=${OUTPUT_DIR}/${DESTINATION}/${BIN_NAME}.xcarchive
  echo $ARCHIVE_PATH
  xcodebuild archive -scheme "${SCHEME}" -configuration "${CONFIGURATION}" -destination "generic/platform=${DESTINATION}" ${BUILD_VERSION} ${BUILD_NUMBER}   -archivePath ${ARCHIVE_PATH} "ONLY_ACTIVE_ARCH=NO" "BITCODE_GENERATION_MODE=bitcode" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" "clean"  ${QUIET} "SKIP_INSTALL=NO"
  echo "Exported ${DESTINATION}!!"
  ((INDEX+=1))
done

FRAMEWORK_LOCATION=${BIN_NAME}.xcarchive/Products/Library/Frameworks/${BIN_NAME}.framework

# create xcframework
xcodebuild -create-xcframework -output ${OUTPUT_DIR}/${BIN_NAME}.xcframework -framework ${OUTPUT_DIR}/iOS/${FRAMEWORK_LOCATION} -framework ${OUTPUT_DIR}/macOS/${FRAMEWORK_LOCATION}

# remove all related files
rm -rf ${OUTPUT_DIR}/iOS
rm -rf ${OUTPUT_DIR}/macOS
