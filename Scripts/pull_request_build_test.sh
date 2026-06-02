#!/bin/bash -xe

print_result_summary() {
  local title="$1"
  local result_bundle="$2"

  set +x
  echo ""
  echo "===== ${title} result summary ====="

  if [ ! -d "$result_bundle" ]; then
    echo "Result bundle was not created: $result_bundle"
    echo "===== End ${title} result summary ====="
    echo ""
    set -x
    return
  fi

  if command -v jq >/dev/null 2>&1; then
    xcrun xcresulttool get test-results summary \
      --path "$result_bundle" \
      --compact |
    jq -r '
      def test_failures:
        (.testFailures // [])
        | if type == "array" then .[]
          elif type == "object" and has("testName") then .
          else empty
          end;

      "Result: \(.result // "unknown")",
      "Tests: \(.totalTestCount // 0), failed: \(.failedTests // 0), skipped: \(.skippedTests // 0)",
      "",
      (
        if ((.failedTests // 0) == 0) then
          "No XCTest failures recorded."
        else
          "XCTest failures:",
          (
            test_failures
            | "- \(.targetName // "UnknownTarget").\(.testName // "UnknownTest")\n  \(.failureText // "No failure text recorded.")"
          )
        end
      )
    ' || true

  else
    echo "jq is not available; printing raw xcresult summaries."
    xcrun xcresulttool get test-results summary --path "$result_bundle" --compact || true
  fi

  echo "===== End ${title} result summary ====="
  echo ""
  set -x
}

run_xcodebuild_test() {
  local title="$1"
  local result_bundle="$2"
  shift 2

  rm -rf "$result_bundle"

  set +e
  xcodebuild test \
    -project CouchbaseLite.xcodeproj \
    -resultBundlePath "$result_bundle" \
    "$@"
  local status=$?
  set -e

  if [ "$status" -ne 0 ]; then
    print_result_summary "$title" "$result_bundle"
    exit "$status"
  fi
}

if [ "$1" = "-enterprise" ]; then
  cd couchbase-lite-ios-ee/couchbase-lite-ios
else
  cd couchbase-lite-ios
fi

# Minimum Matrix:
# - Run swift tests on iOS platform
# - Run objective-C tests on macOS platform
TEST_SIMULATOR=$(xcrun xctrace list devices 2>&1 | grep -oE 'iPhone.*?[^\(]+' | head -1 | sed 's/Simulator//g' | awk '{$1=$1;print}')

run_xcodebuild_test \
  "Swift iOS XCTest" \
  "$PWD/CBL_EE_Swift_Tests_iOS_App.xcresult" \
  -scheme "CBL_EE_Swift_Tests_iOS_App" \
  -sdk iphonesimulator \
  -destination "platform=iOS Simulator,name=${TEST_SIMULATOR}"

run_xcodebuild_test \
  "ObjC macOS XCTest" \
  "$PWD/CBL_EE_ObjC_Tests.xcresult" \
  -scheme "CBL_EE_ObjC_Tests" \
  -destination "platform=macOS"
