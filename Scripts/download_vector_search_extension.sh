#!/bin/bash -e

#
# Download vector search extension for tests based on the vector specified in Tests/Extensions/version.txt".
# The extension will be stored in the Tests/Extensions folder.
# The script will not download the extensions if the extension of the specified version already exists.
#
# Note : Require Couchbase VPN in order download the extension.

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
EXTENSIONS_DIR="${SCRIPT_DIR}/../Tests/Extensions"

pushd "${EXTENSIONS_DIR}" > /dev/null
EXTENSIONS_DIR=`pwd`

VS_VERSION_FILE="${EXTENSIONS_DIR}/version.txt"
VS_XCFRAMEWORK_FILE="${EXTENSIONS_DIR}/CouchbaseLiteVectorSearch.xcframework"

VERSION=$(cat ${VS_VERSION_FILE} | cut -f1 -d-)
BLD_NUM=$(cat ${VS_VERSION_FILE} | cut -f2 -d-)

echo "Download Vector Search Framework ${VERSION}-${BLD_NUM} ..."

if [ -d "${VS_XCFRAMEWORK_FILE}" ]; then
    VS_INFO_PLIST_FILE="${VS_XCFRAMEWORK_FILE}/ios-arm64/CouchbaseLiteVectorSearch.framework/Info.plist"
    VS_VERSION=`defaults read ${VS_INFO_PLIST_FILE} CFBundleShortVersionString`
    VS_BUILD=`defaults read ${VS_INFO_PLIST_FILE} CFBundleVersion`
    if [ "${VS_VERSION}" == "${VERSION}" ] && [ "${VS_BUILD}" == "${BLD_NUM}" ] ; then
        echo "The Vector Search Framework ${VERSION}-${BLD_NUM} already exists."
        exit 0
    elif [ "${VS_VERSION}" == "" ] && [ "${VS_BUILD}" == "" ] ; then
        echo "<Error> Unknown version of the Vector Search Framework exists."
        exit 0
    fi
fi

ZIP_FILENAME=couchbase-lite-vector-search-${VERSION}-${BLD_NUM}-apple.zip
curl -O http://latestbuilds.service.couchbase.com/builds/latestbuilds/couchbase-lite-vector-search/${VERSION}/${BLD_NUM}/${ZIP_FILENAME}

# Extract the CouchbaseLiteSwift.xcframework:
rm -rf "${VS_XCFRAMEWORK_FILE}"
unzip ${ZIP_FILENAME}

rm -rf "${ZIP_FILENAME}" 2> /dev/null

popd > /dev/null
