#!/bin/sh

set -e

function usage
{
  echo "Usage: ${0} -s <Scheme: \"CBL_ObjC\" or \"CBL_Swift\"> [-c <Configuration Name, default is 'Release'>] -o <Output Directory> [-v <Version (<Version Number>[-<Build Number>])>] [--quiet]"
}

while [[ $# -gt 0 ]]
do
  key=${1}
  case $key in
    -s)
    SCHEME=${2}
    shift
    ;;
    -c)
    CONFIGURATION=${2}
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

if [ -z "$CONFIGURATION" ]
then
  CONFIGURATION="Release"
fi

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

# clean the output directory
OUTPUT_BASE_DIR=${OUTPUT_DIR}/xc/${SCHEME}

# Get binary and framework name:
BIN_NAME=`xcodebuild -scheme "${SCHEME}" -showBuildSettings|grep -w PRODUCT_NAME|head -n 1|awk '{ print $3 }'`
FRAMEWORK_FILE_NAME=${BIN_NAME}.framework

# build version and number
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
BUILD_DIR=$OUTPUT_DIR/build/$(echo ${SCHEME} | sed 's/ /_/g')
FRAMEWORK_LOC=${BIN_NAME}.xcarchive/Products/Library/Frameworks/${BIN_NAME}.framework

# this will be used to collect all destination framework path with `-framework`
# to include them in `-create-xcframework`
FRAMEWORK_PATH_ARGS=()

# arg1 = target destination for which the archive is built for. E.g., "generic/platform=iOS"
function xcarchive
{
  DESTINATION=${1}
  echo "Archiving for ${DESTINATION}..."
  ARCHIVE_PATH=${BUILD_DIR}/$(echo ${DESTINATION} | sed 's/ /_/g')
  xcodebuild archive \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -destination "${DESTINATION}" \
    ${BUILD_VERSION} ${BUILD_NUMBER} \
    -archivePath "${ARCHIVE_PATH}/${BIN_NAME}.xcarchive" \
    "ONLY_ACTIVE_ARCH=NO" "BITCODE_GENERATION_MODE=bitcode" \
    "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" \
    "SKIP_INSTALL=NO" ${QUIET}
  
  FRAMEWORK_PATH_ARGS+=("-framework "${ARCHIVE_PATH}/${FRAMEWORK_LOC}" \
    -debug-symbols "${ARCHIVE_PATH}/${BIN_NAME}.xcarchive/dSYMs/${BIN_NAME}.framework.dSYM"")
  echo "Finished archiving ${DESTINATION}."
}

xcarchive "generic/platform=iOS Simulator"
xcarchive "generic/platform=iOS"
xcarchive "generic/platform=macOS"

# create xcframework
echo "Creating XCFramework...: ${FRAMEWORK_PATH_ARGS}"
mkdir -p "${OUTPUT_BASE_DIR}"
xcodebuild -create-xcframework \
    -output "${OUTPUT_BASE_DIR}/${BIN_NAME}.xcframework" \
    ${FRAMEWORK_PATH_ARGS[*]}

# remove build directory
rm -rf ${BUILD_DIR}
echo "Finished creating XCFramework. Output at "${OUTPUT_BASE_DIR}/${BIN_NAME}.xcframework""
