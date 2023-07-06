#!/bin/bash -xe
if [ "$1" = "-enterprise" ]
  then
    cd couchbase-lite-ios-ee/couchbase-lite-ios
  else 
    cd couchbase-lite-ios
fi

TEST_SIMULATOR=$(xcrun xctrace list devices 2>&1 | grep -oE 'iPhone.*?[^\(]+' | head -1 | sed 's/Simulator//g' | awk '{$1=$1;print}')
SCHEMES=("CBL_EE_ObjC_Tests_iOS_App" "CBL_EE_Swift_Tests_iOS_App")

for SCHEME in "${SCHEMES[@]}"
do
  xcodebuild test -project CouchbaseLite.xcodeproj -scheme "$SCHEME" -sdk iphonesimulator -destination "platform=iOS Simulator,name=${TEST_SIMULATOR}"
done
