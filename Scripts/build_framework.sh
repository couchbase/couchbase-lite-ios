#!/bin/bash

set -e

function usage 
{
  echo "\nUsage: ${0} -s <Scheme Name: \"CBL ObjC\" or \"CBL Swift\"> -p <Platform Name: iOS, tvOS, or macOS> -o <Output Directory>\n\n" 
}

while [[ $# -gt 1 ]]
do
  key=${1}
  case $key in
      -s)
      SCHEME=${2}
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
      *)
      usage
      exit 3
      ;;
  esac
  shift
done

if [ -z "$SCHEME" ] || [ -z "$PLATFORM_NAME" ]
then
  usage
  exit 4
fi

echo "Scheme: ${SCHEME}"
echo "Platform: ${PLATFORM_NAME}"
echo "Output Directory: ${OUTPUT_DIR}"

SDKS=()
PLATFORM_NAME=`echo $PLATFORM_NAME | tr '[:upper:]' '[:lower:]'`
if [ ${PLATFORM_NAME} = "ios" ]
then
  SDKS=("iphoneos" "iphonesimulator")
elif [ ${PLATFORM_NAME} = "tvos" ]
then
  SDKS=("appletvos" "appletvsimulator")
elif [ ${PLATFORM_NAME} = "macos" ]
then
  SDKS=("macosx")
fi

OUTPUT_BASE_DIR=${OUTPUT_DIR}/${SCHEME}/${PLATFORM_NAME}
rm -rf "${OUTPUT_BASE_DIR}"

ROUND=0
OUTPUT_BINS=()
OUTPUT_DSYM=()
for SDK in "${SDKS[@]}"
  do
    echo "Running xcodebuild on scheme=${SCHEME} and sdk=${SDK} ..."
    CLEAN_CMD=""
    if [[ ${ROUND} == 0 ]]
    then
      CLEAN_CMD="clean "
    fi

    xcodebuild -scheme "${SCHEME}" -configuration Release -sdk ${SDK} OHTER_CFLAGS="-fembed-bitcode" ${CLEAN_CMD}build
    PRODUCTS_DIR=`xcodebuild -scheme "${SCHEME}" -configuration Release -sdk ${SDK} -showBuildSettings|grep -w BUILT_PRODUCTS_DIR|head -n 1|awk '{ print $3 }'`
    BIN_NAME=`xcodebuild -scheme "${SCHEME}" -configuration Release -sdk ${SDK} -showBuildSettings|grep -w PRODUCT_NAME|head -n 1|awk '{ print $3 }'`
    FRAMEWORK_FILE_NAME=${BIN_NAME}.framework
    FRAMEWORK_FILE_PATH=${PRODUCTS_DIR}/${FRAMEWORK_FILE_NAME}
    DSYM_FILE_PATH=${FRAMEWORK_FILE_PATH}.dSYM

    OUTPUT_SDK_DIR=${OUTPUT_BASE_DIR}/${SDK}
    mkdir -p "${OUTPUT_SDK_DIR}"

    if [ ${ROUND} == 0 ]
    then
      cp -a "${FRAMEWORK_FILE_PATH}" "${OUTPUT_BASE_DIR}"
      cp -a "${DSYM_FILE_PATH}" "${OUTPUT_BASE_DIR}"
    fi

    cp -a "${FRAMEWORK_FILE_PATH}" "${OUTPUT_SDK_DIR}"
    cp -a "${DSYM_FILE_PATH}" "${OUTPUT_SDK_DIR}"

    OUTPUT_BINS+=("\"${OUTPUT_SDK_DIR}/${FRAMEWORK_FILE_NAME}/${BIN_NAME}\"")
    OUTPUT_DSYM+=("\"${OUTPUT_SDK_DIR}/${FRAMEWORK_FILE_NAME}.dSYM/Contents/Resources/DWARF/${BIN_NAME}\"")
    ROUND=$((ROUND + 1))
done

if [[ ${#SDKS[@]} > 1 ]]
then
  LIPO_BIN_INPUTS=$(IFS=" " ; echo "${OUTPUT_BINS[*]}")
  echo "Generate FAT binary: ${LIPO_BIN_INPUTS}"
  LIPO_CMD="lipo ${LIPO_BIN_INPUTS} -create -output \"${OUTPUT_BASE_DIR}/${FRAMEWORK_FILE_NAME}/${BIN_NAME}\""
  eval "${LIPO_CMD}"

  LIPO_DSYM_INPUTS=$(IFS=" " ; echo "${OUTPUT_DSYM[*]}")
  echo "Generate FAT dSYM: ${LIPO_DSYM_INPUTS}"
  LIPO_CMD="lipo ${LIPO_DSYM_INPUTS} -create -output \"${OUTPUT_BASE_DIR}/${FRAMEWORK_FILE_NAME}.dSYM/Contents/Resources/DWARF/${BIN_NAME}\""
fi

# Cleanup:
for SDK in "${SDKS[@]}"
  do
    rm -rf "${OUTPUT_BASE_DIR}/${SDK}"
done
