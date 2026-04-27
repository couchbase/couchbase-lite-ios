#!/bin/bash -xe
if [ "$1" = "-enterprise" ]
  then
    cd couchbase-lite-ios-ee/couchbase-lite-ios
  else 
    cd couchbase-lite-ios
fi

# Minimum Matrix: 
# - Run objective-C tests on macOS platform
# - Run swift tests on iOS platform
xcodebuild test -project CouchbaseLite.xcodeproj -scheme "CBL_EE_ObjC_Tests" -destination "platform=macOS"

TEST_SIMULATOR=$(xcrun xctrace list devices 2>&1 | grep -oE 'iPhone.*?[^\(]+' | head -1 | sed 's/Simulator//g' | awk '{$1=$1;print}')
xcodebuild test -project CouchbaseLite.xcodeproj -scheme "CBL_EE_Swift_Tests_iOS_App" -sdk iphonesimulator -destination "platform=iOS Simulator,name=${TEST_SIMULATOR}"
