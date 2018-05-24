#!/bin/bash

set -e

function usage 
{
  echo "Usage: ${0} -s <Scheme: \"CBL ObjC\" or \"CBL Swift\"> -p <Platform: iOS, tvOS, or macOS> [-c <Configuration Name, default is 'Release'>] -o <Output Directory> [-v <Version (<Version Number>[-<Build Number>])>] [--verbose]" 
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
      -p)
      PLATFORM_NAME=${2}
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
      --verbose)
      VERBOSE="Y"
      ;;
      *)
      usage
      exit 3
      ;;
  esac
  shift
done

if [ -z "$SCHEME" ] || [ -z "$PLATFORM_NAME" ] || [ -z "$OUTPUT_DIR" ]
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
echo "Platform: ${PLATFORM_NAME}"
echo "Output Directory: ${OUTPUT_DIR}"
echo "Version: ${VERSION}"

SDKS=()
PLATFORM_NAME=`echo $PLATFORM_NAME | tr '[:upper:]' '[:lower:]'`
if [ ${PLATFORM_NAME} = "ios" ]
then
  SDKS=("iphoneos" "iphonesimulator")
  PLATFORM_NAME="iOS"
elif [ ${PLATFORM_NAME} = "tvos" ]
then
  SDKS=("appletvos" "appletvsimulator")
  PLATFORM_NAME="tvOS"
elif [ ${PLATFORM_NAME} = "macos" ]
then
  SDKS=("macosx")
  PLATFORM_NAME="macOS"
fi

if [ -z "$VERBOSE" ]
then
  echo "Verbose: NO"
  VERBOSE="-quiet"
else
  echo "Verbose: YES"
  VERBOSE=""
fi

OUTPUT_BASE_DIR=${OUTPUT_DIR}/${SCHEME}/${PLATFORM_NAME}
rm -rf "${OUTPUT_BASE_DIR}"

ROUND=0
OUTPUT_BINS=()
OUTPUT_DSYM=()
OUTPUT_SWIFT_MODULES=()

# Get binary and framework name:
BIN_NAME=`xcodebuild -scheme "${SCHEME}" -showBuildSettings|grep -w PRODUCT_NAME|head -n 1|awk '{ print $3 }'`
FRAMEWORK_FILE_NAME=${BIN_NAME}.framework
OUTPUT_FRAMEWORK_BUNDLE_DIR=${OUTPUT_BASE_DIR}/${FRAMEWORK_FILE_NAME}

# Building all frameworks based on the SDK list:
for SDK in "${SDKS[@]}"
  do
    echo "Running xcodebuild on scheme=${SCHEME} configuration=${CONFIGURATION} and sdk=${SDK} ..."
    ACTION="build"
    if [[ ${ROUND} == 0 ]]
    then
      ACTION="clean build"
    fi

    #Run xcodebuild:
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

    xcodebuild -scheme "${SCHEME}" -configuration "${CONFIGURATION}" -sdk ${SDK} ${BUILD_VERSION} ${BUILD_NUMBER} "ONLY_ACTIVE_ARCH=NO" "BITCODE_GENERATION_MODE=bitcode" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" ${ACTION} ${VERBOSE}

    # Get the XCode built framework and dsym file path:
    PRODUCTS_DIR=`xcodebuild -scheme "${SCHEME}" -configuration "${CONFIGURATION}" -sdk "${SDK}" -showBuildSettings|grep -w BUILT_PRODUCTS_DIR|head -n 1|awk '{ print $3 }'`
    FRAMEWORK_FILE_PATH=${PRODUCTS_DIR}/${FRAMEWORK_FILE_NAME}
    DSYM_FILE_PATH=${FRAMEWORK_FILE_PATH}.dSYM

    # Create output dir to copy the built framework to:
    OUTPUT_SDK_DIR=${OUTPUT_BASE_DIR}/${SDK}
    mkdir -p "${OUTPUT_SDK_DIR}"

    # Copy the framework and dSYM files:
    if [ ${ROUND} == 0 ]
    then
      cp -a "${FRAMEWORK_FILE_PATH}" "${OUTPUT_BASE_DIR}"
      cp -a "${DSYM_FILE_PATH}" "${OUTPUT_BASE_DIR}"
    fi

    cp -a "${FRAMEWORK_FILE_PATH}" "${OUTPUT_SDK_DIR}"
    cp -a "${DSYM_FILE_PATH}" "${OUTPUT_SDK_DIR}"

    # Collect output paths to use for making the FAT framework:
    OUTPUT_BINS+=("\"${OUTPUT_SDK_DIR}/${FRAMEWORK_FILE_NAME}/${BIN_NAME}\"")
    OUTPUT_DSYM+=("\"${OUTPUT_SDK_DIR}/${FRAMEWORK_FILE_NAME}.dSYM/Contents/Resources/DWARF/${BIN_NAME}\"")
    SWIFT_MODULE_DIR=${OUTPUT_SDK_DIR}/${FRAMEWORK_FILE_NAME}/Modules/${BIN_NAME}.swiftmodule
    if [ -d "${SWIFT_MODULE_DIR}" ]
    then
      OUTPUT_SWIFT_MODULES+=("${SWIFT_MODULE_DIR}")
    fi

    ROUND=$((ROUND + 1))
done

# Make FAT framework:
if [[ ${#SDKS[@]} > 1 ]]
then
  # Binary:
  LIPO_BIN_INPUTS=$(IFS=" " ; echo "${OUTPUT_BINS[*]}")
  echo "Generate FAT binary: ${LIPO_BIN_INPUTS}"
  LIPO_CMD="lipo ${LIPO_BIN_INPUTS} -create -output \"${OUTPUT_FRAMEWORK_BUNDLE_DIR}/${BIN_NAME}\""
  eval "${LIPO_CMD}"

  # dSYM file:
  LIPO_DSYM_INPUTS=$(IFS=" " ; echo "${OUTPUT_DSYM[*]}")
  echo "Generate FAT dSYM: ${LIPO_DSYM_INPUTS}"
  LIPO_CMD="lipo ${LIPO_DSYM_INPUTS} -create -output \"${OUTPUT_FRAMEWORK_BUNDLE_DIR}.dSYM/Contents/Resources/DWARF/${BIN_NAME}\""
  eval "${LIPO_CMD}"
  
  # Swift modules:
  for SWIFT_MODULE in "${OUTPUT_SWIFT_MODULES[@]}"
    do
      cp -a "${SWIFT_MODULE}/" "${OUTPUT_FRAMEWORK_BUNDLE_DIR}/Modules/${BIN_NAME}.swiftmodule/"
  done
fi

# Cleanup:
for SDK in "${SDKS[@]}"
  do
    rm -rf "${OUTPUT_BASE_DIR}/${SDK}"
done
