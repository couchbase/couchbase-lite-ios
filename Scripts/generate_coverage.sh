#!/bin/bash

set -e

function usage 
{
  echo "\nUsage: ${0} -o <Output Directory>\n" 
}

while [[ $# -gt 1 ]]
do
  key=${1}
  case $key in
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

# DerivedData Directory
DERIVED_DATA_DIR="Coverage_DerivedData"

# Objective-C
SCHEME="CBL ObjC"
BINARY_FILE="$DERIVED_DATA_DIR/Build/Products/Debug/CouchbaseLite.framework/CouchbaseLite"
OUTPUT_COVERAGE_DIR="$OUTPUT_DIR/CouchbaseLite"

mkdir -p "$OUTPUT_COVERAGE_DIR"
xcodebuild -scheme "$SCHEME" -enableCodeCoverage YES clean test -derivedDataPath "$DERIVED_DATA_DIR"
PROFILE_DATA_FILE=$(find ${DERIVED_DATA_DIR} -name "Coverage.profdata")
xcrun llvm-cov report -instr-profile="$PROFILE_DATA_FILE" "$BINARY_FILE" | grep -v "vendor/*" | grep -v "TOTAL" > "$OUTPUT_COVERAGE_DIR"/summary.txt
xcrun llvm-cov report -instr-profile="$PROFILE_DATA_FILE" "$BINARY_FILE" Objective-C/*.{m,mm} Objective-C/Internal/*.{m,mm} > "$OUTPUT_COVERAGE_DIR"/summary-detail.txt
xcrun llvm-cov show -format=html -instr-profile="$PROFILE_DATA_FILE" "$BINARY_FILE" Objective-C/*.{m,mm} Objective-C/Internal/*.{m,mm} > "$OUTPUT_COVERAGE_DIR"/coverage.html
rm -rf "$DERIVED_DATA_DIR"

# Swift
SCHEME="CBL Swift"
BINARY_FILE="$DERIVED_DATA_DIR/Build/Products/Debug/CouchbaseLiteSwift.framework/CouchbaseLiteSwift"
OUTPUT_COVERAGE_DIR="$OUTPUT_DIR/CouchbaseLiteSwift"

mkdir -p "$OUTPUT_COVERAGE_DIR"
xcodebuild -scheme "$SCHEME" -enableCodeCoverage YES clean test -derivedDataPath "$DERIVED_DATA_DIR"
PROFILE_DATA_FILE=$(find ${DERIVED_DATA_DIR} -name "Coverage.profdata")
xcrun llvm-cov report -instr-profile="$PROFILE_DATA_FILE" "$BINARY_FILE" | grep -v "Objective-C" | grep -v "vendor/*" | grep -v "TOTAL" > "$OUTPUT_COVERAGE_DIR"/summary.txt
xcrun llvm-cov report -instr-profile="$PROFILE_DATA_FILE" "$BINARY_FILE" Swift/*.swift > "$OUTPUT_COVERAGE_DIR"/summary-detail.txt
xcrun llvm-cov show -format=html -instr-profile="$PROFILE_DATA_FILE" "$BINARY_FILE" Swift/*.swift > "$OUTPUT_COVERAGE_DIR"/coverage.html
rm -rf "$DERIVED_DATA_DIR"
