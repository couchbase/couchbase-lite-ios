#!/bin/bash -xe

cd couchbase-lite-ios
SCHEMES=("CBL ObjC" "CBL Swift")

for SCHEME in "${SCHEMES[@]}"

do
  xcodebuild test -project CouchbaseLite.xcodeproj -scheme "$SCHEME" -sdk iphonesimulator -destination "platform=iOS Simulator,name=iPhone 11"

done
