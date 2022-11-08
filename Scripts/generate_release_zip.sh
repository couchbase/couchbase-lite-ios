#!/bin/bash

set -e

function usage
{
  echo "Usage: ${0} -o <Output Directory> [-v <Version (<Version Number>[-<Build Number>])>]"
  echo "\nOptions:"
  echo "  --xcframework\t [Not used, will be XCFramework by default] create a release package with .xcframework"
  echo "  --combined\t\t [Not used, will be XCFramework by default] create a release package with .xcframework and .framework"
  echo "  --notest\t create a release package but no tests needs to be run"
  echo "  --nocov\t create a release package, run tests but no code coverage zip"
  echo "  --testonly\t run tests but no release package"
}

function checkCrashLogs
{
  echo "Check for xctest crash logs ..."
  sh Scripts/xctest_crash_log.sh
  exit 1
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
      --combined)
      COMBINED=YES
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
      --testonly)
      TEST_ONLY=YES
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

if [ -n "$NO_TEST" ]
then
  OPTS="--notest"
fi

if [ -n "$NO_COV" ]
then
  OPTS="$OPTS --nocov"
fi

if [ -n "$TEST_ONLY" ]
then
  OPTS="$OPTS --testonly"
fi

if [ -n "$EE" ]
then
  OPTS="$OPTS --EE"
fi

if [ -n "$VERSION" ]
then
  OPTS="$OPTS -v ${VERSION}"
fi

if [ -n "$PRETTY" ]
then
  OPTS="$OPTS --pretty"
fi

echo "Building xcframework for ObjC..."
sh Scripts/generate_objc_release_zip.sh -o "${OUTPUT_DIR}/ObjC"  ${OPTS}

echo "Building xcframework for Swift..."
sh Scripts/generate_swift_release_zip.sh -o "${OUTPUT_DIR}/Swift"  ${OPTS}

# copy everything to single folder
mv ${OUTPUT_DIR}/ObjC/* ${OUTPUT_DIR}/
mv ${OUTPUT_DIR}/Swift/* ${OUTPUT_DIR}/

# remove the empty folders!
rm -rf ${OUTPUT_DIR}/ObjC
rm -rf ${OUTPUT_DIR}/Swift
