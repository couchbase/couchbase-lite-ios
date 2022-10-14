#!/bin/bash -xe

cd couchbase-lite-ios

TEST_SIMULATOR=$(xcrun simctl list devicetypes | grep \.iPhone- | tail -1 |  sed  "s/ (com.apple.*//g")
SCHEMES=("CBL_EE_ObjC" "CBL_EE_Swift")
for SCHEME in "${SCHEMES[@]}"
do
  xcodebuild test -project CouchbaseLite.xcodeproj -scheme "$SCHEME" -sdk iphonesimulator -destination "platform=iOS Simulator,name=$TEST_SIMULATOR"
done
