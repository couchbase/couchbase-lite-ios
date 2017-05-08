#! /bin/bash -e
# This script runs Xcode tests and generates a report of every function/method's code coverage.
# Invoke it from the project directory.
# Author: Jens Alfke, 1 March 2017

# These variables are project and target specific:
SCHEME='CBL ObjC'
#SOURCES="Objective-C/*.mm Objective-C/*.m Objective-C/Internal/*.mm Objective-C/Internal/*.m"
EXECUTABLE="build/CouchbaseLite/Build/Intermediates/CodeCoverage/Products/Debug/CouchbaseLite.framework/CouchbaseLite"

# These variables just determine where the profile data and HTML file go:
PROFILE_FILE="$SCHEME.profdata"
OUTPUT_HTML="$SCHEME Test Coverage.html"
OUTPUT_TXT="$SCHEME Test Coverage.txt"

# OK, let's do it. First run the tests:
xcodebuild -scheme "$SCHEME" -enableCodeCoverage YES CLANG_COVERAGE_PROFILE_FILE="$PROFILE_FILE" test

# Generate the report. There are a lot of possibilities here;
# see https://clang.llvm.org/docs/SourceBasedCodeCoverage.html
# and http://llvm.org/docs/CommandGuide/llvm-cov.html
echo "Generating code coverage report '`pwd`/$OUTPUT_TXT' ..."
xcrun llvm-cov report -instr-profile="$PROFILE_FILE" $EXECUTABLE $SOURCES > "$OUTPUT_TXT"
