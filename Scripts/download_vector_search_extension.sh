#!/bin/bash -e

#
# Downloads the vector search extension for tests based on the version specified
# in Tests/Extensions/version.txt. The extension will be stored in the
# Tests/Extensions folder. The script will not download the extension if the
# extension of the specified version has already been downloaded.
#
# Note : Downloading a non-release build requires Couchbase VPN.

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
EXTENSIONS_DIR="${SCRIPT_DIR}/../Tests/Extensions"

pushd "${EXTENSIONS_DIR}" > /dev/null
EXTENSIONS_DIR=`pwd`

VS_VERSION_FILE="${EXTENSIONS_DIR}/version.txt"
VERSION_NUMBER=$(cat ${VS_VERSION_FILE})
VS_XCFRAMEWORK_FILE="${EXTENSIONS_DIR}/CouchbaseLiteVectorSearch.xcframework"
VS_DOWNLOADED_VERSION_FILE="${EXTENSIONS_DIR}/.downloaded-version"

# Skip when the specified version has already been downloaded:
if [ -d "${VS_XCFRAMEWORK_FILE}" ] && [ -f "${VS_DOWNLOADED_VERSION_FILE}" ] && \
   [ "$(cat ${VS_DOWNLOADED_VERSION_FILE})" == "${VERSION_NUMBER}" ]; then
  echo "Vector Search Framework ${VERSION_NUMBER} is up to date."
  popd > /dev/null
  exit 0
fi

if [[ "$VERSION_NUMBER" == *"-"* ]]; then
  VERSION="${VERSION_NUMBER%-*}"
  BLD_NUM="${VERSION_NUMBER##*-}"
  ZIP_FILENAME="couchbase-lite-vector-search-${VERSION}-${BLD_NUM}-apple.zip"
  URL="https://latestbuilds.service.couchbase.com/builds/latestbuilds/couchbase-lite-vector-search/${VERSION}/${BLD_NUM}/${ZIP_FILENAME}"
else
  VERSION="$VERSION_NUMBER"
  ZIP_FILENAME="couchbase-lite-vector-search_xcframework_${VERSION}.zip"
  URL="https://packages.couchbase.com/releases/couchbase-lite-vector-search/${VERSION}/${ZIP_FILENAME}"
fi

echo "Download Vector Search Framework from ${URL} ..."
curl -f -O ${URL}

# Extract the CouchbaseLiteVectorSearch.xcframework:
rm -rf CouchbaseLiteVectorSearch.xcframework
unzip -o ${ZIP_FILENAME}
echo "${VERSION_NUMBER}" > "${VS_DOWNLOADED_VERSION_FILE}"

rm -rf "${ZIP_FILENAME}" 2> /dev/null

popd > /dev/null
