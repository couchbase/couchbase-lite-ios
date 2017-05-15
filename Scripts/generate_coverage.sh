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

# Objective-C
SCHEME="CBL ObjC"
PROFILE_DATA_FILE=CouchbaseLite.profdata
DERIVED_DATA_DIR=DerivedData
BINARY_FILE=DerivedData/Build/Intermediates/CodeCoverage/Products/Debug/CouchbaseLite.framework/CouchbaseLite
OUTPUT_COVERAGE_DIR=$OUTPUT_DIR/CouchbaseLite

mkdir -p "$OUTPUT_COVERAGE_DIR"
xcodebuild -scheme "$SCHEME" -enableCodeCoverage YES CLANG_COVERAGE_PROFILE_FILE="$PROFILE_DATA_FILE" clean test -derivedDataPath "$DERIVED_DATA_DIR"
xcrun llvm-cov report -instr-profile="$PROFILE_DATA_FILE" "$BINARY_FILE" | grep -v "vendor/*" | grep -v "TOTAL" > "$OUTPUT_COVERAGE_DIR"/summary.txt
xcrun llvm-cov report -instr-profile="$PROFILE_DATA_FILE" "$BINARY_FILE" Objective-C/*.{m,mm} Objective-C/Internal/*.{m,mm} > "$OUTPUT_COVERAGE_DIR"/summary-detail.txt
xcrun llvm-cov show -format=html -instr-profile="$PROFILE_DATA_FILE" "$BINARY_FILE" Objective-C/*.{m,mm} Objective-C/Internal/*.{m,mm} > "$OUTPUT_COVERAGE_DIR"/coverage.html
rm -rf "$PROFILE_DATA_FILE"
rm -rf "$DERIVED_DATA_DIR"

# Swift
SCHEME="CBL Swift"
PROFILE_DATA_FILE=CouchbaseLiteSwift.profdata
DERIVED_DATA_DIR=DerivedData
OUTPUT_COVERAGE_DIR=$OUTPUT_DIR/CouchbaseLiteSwift
BINARY_FILE=DerivedData/Build/Intermediates/CodeCoverage/Products/Debug/CouchbaseLiteSwift.framework/CouchbaseLiteSwift

mkdir -p "$OUTPUT_COVERAGE_DIR"
xcodebuild -scheme "$SCHEME" -enableCodeCoverage YES CLANG_COVERAGE_PROFILE_FILE="$PROFILE_DATA_FILE" clean test -derivedDataPath "$DERIVED_DATA_DIR"
xcrun llvm-cov report -instr-profile="$PROFILE_DATA_FILE" "$BINARY_FILE" | grep -v "Objective-C" | grep -v "vendor/*" | grep -v "TOTAL" > "$OUTPUT_COVERAGE_DIR"/summary.txt
xcrun llvm-cov report -instr-profile="$PROFILE_DATA_FILE" "$BINARY_FILE" Swift/*.swift > "$OUTPUT_COVERAGE_DIR"/summary-detail.txt
xcrun llvm-cov show -format=html -instr-profile="$PROFILE_DATA_FILE" "$BINARY_FILE" Swift/*.swift > "$OUTPUT_COVERAGE_DIR"/coverage.html
rm -rf "$PROFILE_DATA_FILE"
rm -rf "$DERIVED_DATA_DIR"
