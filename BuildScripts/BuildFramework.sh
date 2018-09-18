if [[ -e ~jenkins/.bash_profile ]] ; then source ~jenkins/.bash_profile ; fi

function usage
{
    echo -e "\nuse:  ${0} release_number  build_number  edition<community|enterprise>  platform<ios|macosx|tvos> [rel-stage]\n\n"
}

if [[ ! ${1} ]] ; then usage ; exit 88 ; fi
VERSION=${1}

if [[ ! ${2} ]] ; then usage ; exit 77 ; fi
BLD_NUM=${2}
REVISION=${VERSION}-${BLD_NUM}

if [[ ! ${3} ]] ; then usage ; exit 66 ; fi
EDITION=${3}
EDN_PRFX=`echo ${EDITION} | tr '[a-z]' '[A-Z]'`

if [[ ! ${4} ]] ; then usage ; exit 55 ; fi
OS=${4}
EDN_PRFX=`echo ${OS} | tr '[a-z]' '[A-Z]'`

if [[ ${5} ]] ; then REL_STAGE=${5} ; fi
if [ -z $REL_STAGE ]
then
    CBL_VERSION=${VERSION}
else
    REVISION=${VERSION}${REL_STAGE}-${BLD_NUM}
    CBL_VERSION=${VERSION}${REL_STAGE}
fi

if [ -z "$WORKSPACE" ]
then
  WORKSPACE=`pwd`
fi

BASE_DIR=`pwd`
SQLCIPHER="libsqlcipher"
LIBSQLCIPHER_BRANCH="release/1.3.2"
ZIPFILE_STAGING="zipfile_staging"
ZIP_FILE=couchbase-lite-${OS}-${EDITION}_${REVISION}.zip
ZIP_PATH=${BASE_DIR}/${ZIP_FILE}
ZIP_SRCD=${BASE_DIR}/${ZIPFILE_STAGING}
EXTRAS_DIR=${ZIP_SRCD}/Extras

if [[ $OS =~ ios ]]
then
    SCHEME="CI iOS" 
    SDK="iphoneos"
    OPENID_SRC=${BASE_DIR}/Source/API/Extras/OpenIDConnectUI
    LIB_SQLCIPHER=${BASE_DIR}/${SQLCIPHER}/libs/ios/libsqlcipher.a
    LIB_SQLCIPHER_DEST=${EXTRAS_DIR}
elif [[ $OS =~ tvos ]]
then
    SCHEME="CI iOS"
    SDK="appletvos"
    LIB_SQLCIPHER=${BASE_DIR}/${SQLCIPHER}/libs/tvos/libsqlcipher.a
    LIB_SQLCIPHER_DEST=${BASE_DIR}/${ZIPFILE_STAGING}/Extras
elif [[ $OS =~ macosx ]]
then
    SCHEME="CI MacOS"
    SDK="macosx"
    OPENID_SRC=${BASE_DIR}/Source/API/Extras/OpenIDConnectUI
    LIB_SQLCIPHER=${BASE_DIR}/${SQLCIPHER}/libs/osx/libsqlcipher.a
    LIB_SQLCIPHER_DEST=${BASE_DIR}/vendor/SQLCipher/libs/osx
else
    echo -e "\nUnsupported OS: ${OS}\n"
    exit 555
fi

LOG_FILE=${WORKSPACE}/${OS}_${EDITION}_build_results.log
if [[ -e ${LOG_FILE} ]] ; then rm -f ${LOG_FILE} ; fi

LOG_FILE=${WORKSPACE}/${OS}_${EDITION}_build_results.log
if [[ -e ${LOG_FILE} ]] ; then rm -f ${LOG_FILE} ; fi

rm -f ${BASE_DIR}/*.zip

DOC_ZIP_FILE=couchbase-lite-${OS}-${EDITION}_${REVISION}_Documentation.zip
DOC_ZIP_PATH=${BASE_DIR}/${DOC_ZIP_FILE}
DOC_ZIP_ROOT=${BASE_DIR}/apidoc/Release
DOC_ZIP_ROOT_DIR=${DOC_ZIP_ROOT}/${REVISION}

BUILD_REPO_DIR=${WORKSPACE}/build
LICENSED=${BUILD_REPO_DIR}/license/couchbase-lite
LICENSEF=${LICENSED}/LICENSE_${EDITION}.txt
LIC_DEST=${ZIP_SRCD}/LICENSE.txt

README_D=${BASE_DIR}
README_F=${README_D}/README.md
RME_DEST=${ZIP_SRCD}

git show --stat
REPO_SHA=`git log --oneline --pretty="format:%H" -1`

echo "> Prepare ${ZIP_FILE}"
if [[ -e ${ZIP_SRCD} ]] ; then rm -rf ${ZIP_SRCD} ; fi
mkdir -p ${ZIP_SRCD}

# Download build repo:
if [[ ! -e ${BUILD_REPO_DIR} ]]
then
    echo "> Clone https://github.com/couchbase/build.git ..."
    git clone https://github.com/couchbase/build.git ${BUILD_REPO_DIR}
fi

if [[ ! -e ${BUILD_REPO_DIR} ]]
then
    echo -e "\nLicense files not found\n"
    exit 555
fi

Download prebuilt sqlcipher from couchbaselab
if [[ -e ${SQLCIPHER} ]] ; then rm -rf ${SQLCIPHER} ; fi
git clone https://github.com/couchbaselabs/couchbase-lite-libsqlcipher.git ${SQLCIPHER}
cd ${SQLCIPHER}
git checkout ${LIBSQLCIPHER_BRANCH}
git pull origin ${LIBSQLCIPHER_BRANCH}
cd ${BASE_DIR}
if [[ ! -e ${LIB_SQLCIPHER_DEST} ]] ; then mkdir -p ${LIB_SQLCIPHER_DEST} ; fi
cp ${LIB_SQLCIPHER} ${LIB_SQLCIPHER_DEST}

echo "> Building target=${OS} ${SDK}"

BUILD_VERSION="CURRENT_PROJECT_VERSION=${BLD_NUM} CBL_VERSION_STRING=${CBL_VERSION} CBL_SOURCE_REVISION=${REPO_SHA}"
XCODE_CMD="xcodebuild -scheme \"${SCHEME}\" -sdk \"${SDK}\" -configuration Release RUN_CLANG_STATIC_ANALYZER=NO ONLY_ACTIVE_ARCH=NO BITCODE_GENERATION_MODE=bitcode CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= ${BUILD_VERSION}"

echo "> XCode command: ${XCODE_CMD}"
echo "> XCode command: ${XCODE_CMD}" >>  ${LOG_FILE}

# Run xcode build command:
eval "${XCODE_CMD} clean build 2>&1" >> ${LOG_FILE}

BUILD_DIR=`eval "${XCODE_CMD} -showBuildSettings" | grep -w BUILD_DIR | head -n 1 | awk '{ print $3 }'`

BUILT_PRODUCTS_DIR=`eval "${XCODE_CMD} -showBuildSettings" | grep -w BUILT_PRODUCTS_DIR | head -n 1 | awk '{ print $3 }'`

if [[ $OS =~ ios ]] || [[ $OS =~ tvos ]]
then
    BUILT_DOC_DIR="${BUILD_DIR}/Release-${SDK}/Documentation"
else
    BUILT_DOC_DIR="${BUILT_PRODUCTS_DIR}/Documentation"
fi

echo "> Built Product Directory: ${BUILT_PRODUCTS_DIR}"

echo "> Built Documentation Directory: ${BUILT_DOC_DIR}"

if  [[ -e ${LOGFILE} ]]
then
    echo "> Log file: ${LOGFILE} ..."
    tail ${LOG_TAIL} ${LOGFILE}
fi

# Documentation:
echo "> Package : ${DOC_ZIP_FILE}"
DOC_LOG=${WORKSPACE}/doc_zip.log
if [[ -e ${DOC_LOG} ]] ; then rm -f ${DOC_LOG} ; fi
rm -rf "${DOC_ZIP_ROOT_DIR}"
mkdir -p "${DOC_ZIP_ROOT_DIR}"
mv "${BUILT_DOC_DIR}" "${DOC_ZIP_ROOT_DIR}"
pushd  "${DOC_ZIP_ROOT}"         2>&1 > /dev/null
( zip -ry ${DOC_ZIP_PATH} ${REVISION}  2>&1 ) >>  ${DOC_LOG}
if  [[ -e ${DOC_LOG} ]]
then
    echo
    echo "> ${DOC_LOG} ..."
    tail  ${LOG_TAIL} ${DOC_LOG}
fi
popd 2>&1 > /dev/null

# Copy files:
echo "> Prepare ${ZIP_FILE}"
cp -R  "${BUILT_PRODUCTS_DIR}"/* ${ZIP_SRCD}
cp ${README_F} ${RME_DEST}
cp ${LICENSEF} ${LIC_DEST}

if [[ $OS =~ macosx ]]
then
    rm -rf ${ZIP_SRCD}/CouchbaseLite.framework/Versions/A/PrivateHeaders
    rm -rf ${ZIP_SRCD}/LiteServ.app/Contents/Frameworks/CouchbaseLite.framework/PrivateHeaders
    rm -rf ${ZIP_SRCD}/LiteServ.app/Contents/Frameworks/CouchbaseLite.framework/Versions/A/PrivateHeaders
else
    cp ${BASE_DIR}/Source/API/CBLRegisterJSViewCompiler.h "${EXTRAS_DIR}"
    cp ${BASE_DIR}/Source/CBLJSONValidator.h "${EXTRAS_DIR}"
    cp ${BASE_DIR}/Source/CBLJSONValidator.m "${EXTRAS_DIR}"
    cp ${ZIP_SRCD}/libCBLForestDBStorage.a "${EXTRAS_DIR}"
    cp ${ZIP_SRCD}/libCBLJSViewCompiler.a "${EXTRAS_DIR}"
fi

# Copy OpenIDConnectUI for ios and macos
if [[ $OS =~ ios ]] || [[ $OS =~ macosx ]]
then
if [[ ! -e ${EXTRAS_DIR} ]] ; then mkdir -p ${EXTRAS_DIR} ; fi
cp -rf ${OPENID_SRC} ${EXTRAS_DIR}
elif [[ $OS =~ tvos ]]
then
if [[ -e ${EXTRAS_DIR}/OpenIDConnectUI ]] ; then rm -rf ${EXTRAS_DIR}/OpenIDConnectUI  ; fi
fi

# Postprocess & cleanup:
cd ${ZIP_SRCD}
rm -rf ${ZIP_SRCD}/*.a
rm -rf ${ZIP_SRCD}/*.bcsymbolmap
rm -rf *.dSYM
rm -rf ${ZIP_SRCD}/*LinkMap*
rm -rf CouchbaseLite.framework/PrivateHeaders

# Zip:
echo  "> Package ${ZIP_PATH}"
ZIP_LOG=${WORKSPACE}/doc_zip.log
if [[ -e ${ZIP_LOG} ]] ; then rm -f ${ZIP_LOG} ; fi

cd ${ZIP_SRCD}
( zip -ry   ${ZIP_PATH} *  2>&1 ) >>  ${ZIP_LOG}
if  [[ -e ${ZIP_LOG} ]]
    then
    echo
    echo "> ${ZIP_LOG} ..."
    tail ${LOG_TAIL} ${ZIP_LOG}
fi

if [[ -e ~jenkins/.bash_profile ]]
then
LATESTBUILDS_CBL=http://latestbuilds.hq.couchbase.com/couchbase-lite-ios/${VERSION}${REL_STAGE}/${OS}/${REVISION}
echo "> Uploading internally to ${LATESTBUILDS_CBL}"
fi

echo
echo "> Frameworks: ${ZIP_PATH}"
echo "> Documentation: ${DOC_ZIP_PATH}"
echo "> Done: `date`"
