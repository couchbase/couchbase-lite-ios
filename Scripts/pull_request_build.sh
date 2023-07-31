#!/bin/bash -xe
if [ "$1" = "-enterprise" ]
  then
    cd couchbase-lite-ios-ee/couchbase-lite-ios
  else 
    cd couchbase-lite-ios
fi

SCHEMES_MACOS=("CBL_EE_ObjC" "CBL_EE_Swift")

for SCHEMES_MACOS in "${SCHEMES_MACOS[@]}"
do
  xcodebuild build -project CouchbaseLite.xcodeproj -scheme "$SCHEMES_MACOS" -destination "platform=macOS"
done

TEST_SIMULATOR=$(xcrun xctrace list devices 2>&1 | grep -oE 'iPhone.*?[^\(]+' | head -1 | sed 's/Simulator//g' | awk '{$1=$1;print}')
SCHEMES_IOS=("CBL_EE_ObjC_Tests_iOS_App" "CBL_EE_Swift_Tests_iOS_App")

for SCHEMES_IOS in "${SCHEMES_IOS[@]}"
do
  xcodebuild test -project CouchbaseLite.xcodeproj -scheme "$SCHEMES_IOS" -sdk iphonesimulator -destination "platform=iOS Simulator,name=${TEST_SIMULATOR}"
done
