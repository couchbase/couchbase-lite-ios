#!/bin/bash -xe

cd couchbase-lite-ios

TEST_SIMULATOR=$(xcrun xctrace list devices 2>&1 | grep -oE 'iPhone.*?[^\(]+' | head -1 | sed 's/Simulator//g' | awk '{$1=$1;print}')

SCHEMES=("CBL_EE_ObjC" "CBL_EE_Swift")
for SCHEME in "${SCHEMES[@]}"
do
  xcodebuild test -project CouchbaseLite.xcodeproj -scheme "$SCHEME" -sdk iphonesimulator -destination "platform=iOS Simulator,name=${TEST_SIMULATOR}"
done
