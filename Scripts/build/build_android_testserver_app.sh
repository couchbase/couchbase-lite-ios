#!/bin/bash

EDITION=$1
VERSION=$2
BLD_NUM=$3

cd ${WORKSPACE}/mobile-testkit/CBLClient/Apps/CBLTestServer-iOS
if [[ ! -d Frameworks ]]; then mkdir Frameworks; fi

# Prepare framework
SCHEME=CBLTestServer-iOS
SDK=iphonesimulator
SDK_DEVICE=iphoneos
FRAMEWORK_DIR=${WORKSPACE}/mobile-testkit/CBLClient/Apps/CBLTestServer-iOS/Frameworks

if [[ -d build ]]; then rm -rf build/*; fi
if [[ -d ${FRAMEWORK_DIR} ]]; then rm -rf ${FRAMEWORK_DIR}/*; fi

pushd ${FRAMEWORK_DIR}
pwd
IOS_ZIP=${WORKSPACE}/artifacts/couchbase-lite-swift_${EDITION}_${VERSION}-${BLD_NUM}.zip
if [[ -f ${IOS_ZIP} ]]; then
    unzip ${IOS_ZIP}
    cp -r iOS/CouchbaseLiteSwift.framework .
    cp -r iOS/CouchbaseLiteSwift.framework.dSYM .
else
    echo "Required file ${IOS_ZIP} not found!"
    exit 1
fi
popd

# Build LiteServ

TESTSERVER_APP=${SCHEME}.app
TESTSERVER_APP_DEVICE=${SCHEME}-Device.app
TESTSERVER_ZIP=${SCHEME}-${EDITION}.zip
xcodebuild CURRENT_PROJECT_VERSION=${BLD_NUM} CBL_VERSION_STRING=${VERSION} -scheme ${SCHEME} -sdk ${SDK} -configuration Release -derivedDataPath build
xcodebuild CURRENT_PROJECT_VERSION=${BLD_NUM} CBL_VERSION_STRING=${VERSION} -scheme ${SCHEME} -sdk ${SDK_DEVICE} -configuration Release -derivedDataPath build-device -allowProvisioningUpdates

rm -f *.zip
cp -rf build/Build/Products/Release-${SDK}/${TESTSERVER_APP} .
cp -rf build-device/Build/Products/Release-${SDK_DEVICE}/${TESTSERVER_APP} ./${TESTSERVER_APP_DEVICE}
zip -ry ${WORKSPACE}/artifacts/${TESTSERVER_ZIP} *.app

echo "Done!"
