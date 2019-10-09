#!/bin/bash -xe

cd couchbase-lite-ios-ee/couchbase-lite-ios
EDITIONS=("EE" "CE")
for EDITION in "${EDITIONS[@]}"
do
  if [ ${EDITION} = "EE" ]
  then
    EE="-EE"
  else 
    EE=""
  fi
  
  SCHEMES=("CBL${EE} ObjC" "CBL${EE} Swift")
  for SCHEME in "${SCHEMES[@]}"
  do
    xcodebuild test -project CouchbaseLite.xcodeproj -scheme "$SCHEME" -sdk iphonesimulator -destination "platform=iOS Simulator,name=iPhone 11"
  done
done
