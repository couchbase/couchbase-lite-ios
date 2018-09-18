source ~jenkins/.bash_profile
set -e

LOG_TAIL=-24

function usage
{
    echo -e "\nuse:  ${0}   branch_name<1.x>  release_number  build_number  edition<community|enterprise>  target<ios|macosx|tvos>  sqlcipher_branch<release/1.3.2>\n\n"
}
if [[ ! ${1} ]] ; then usage ; exit 99 ; fi
GITSPEC=${1}

# master branch maps to "0.0.0" for backward compatibility with pre-existing jobs
if [[ ${GITSPEC} =~ "master" ]] ; then GITSPEC=0.0.0 ; fi

if [[ ! ${2} ]] ; then usage ; exit 88 ; fi
VERSION=${2}

if [[ ! ${3} ]] ; then usage ; exit 77 ; fi
BLD_NUM=${3}
REVISION=${VERSION}-${BLD_NUM}

if [[ ! ${4} ]] ; then usage ; exit 66 ; fi
EDITION=${4}
EDN_PRFX=`echo ${EDITION} | tr '[a-z]' '[A-Z]'`

if [[ ! ${5} ]] ; then usage ; exit 55 ; fi
OS=${5}
EDN_PRFX=`echo ${OS} | tr '[a-z]' '[A-Z]'`

if [[ ${6} ]] ; then LIBSQLCIPHER_BRANCH=${6} ; else LIBSQLCIPHER_BRANCH=${GITSPEC} ; fi

if [[ ${7} ]] ; then REL_STAGE=${7} ; fi
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

BASE_DIRNAME=couchbase-lite-${OS}-${EDITION}
BASE_DIR=${WORKSPACE}/${BASE_DIRNAME}
SQLCIPHER="libsqlcipher"
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
    echo -e "\nUnsupported OS:  ${OS}\n"
    exit 555
fi

LOG_FILE=${WORKSPACE}/${OS}_${EDITION}_build_results.log
if [[ -e ${LOG_FILE} ]] ; then rm -f ${LOG_FILE} ; fi

LOG_FILE=${WORKSPACE}/${OS}_${EDITION}_build_results.log
if [[ -e ${LOG_FILE} ]] ; then rm -f ${LOG_FILE} ; fi

rm -f ${BASE_DIR}/*.zip

DOC_ZIP_FILE=couchbase-lite-${OS}-${EDITION}_${REVISION}_Documentation.zip
DOC_ZIP_PATH=${BASE_DIR}/${DOC_ZIP_FILE}
DOC_ZIP_ROOT=${BASE_DIR}/build/Release
DOC_ZIP_ROOT_DIR=${DOC_ZIP_ROOT}/${REVISION}

LICENSED=${WORKSPACE}/build/license/couchbase-lite
LICENSEF=${LICENSED}/LICENSE_${EDITION}.txt
LIC_DEST=${ZIP_SRCD}/LICENSE.txt

README_D=${BASE_DIR}
README_F=${README_D}/README.md
RME_DEST=${ZIP_SRCD}

export TAP_TIMEOUT=120

echo ============================================ `date`
cd ${WORKSPACE}
echo ============================================  sync couchbase-lite-ios
echo ============================================  to ${GITSPEC} into ${BASE_DIR}

if [[ ! -d ${BASE_DIRNAME} ]]
then
    git clone https://github.com/couchbase/couchbase-lite-ios.git ${BASE_DIRNAME}
fi

if [[ ${GITSPEC} =~ "0.0.0" ]]
then
    BRANCH=master
else
    BRANCH=${GITSPEC}
fi

cd  ${BASE_DIRNAME}
git fetch --all
git checkout -B ${BRANCH} --track origin/${BRANCH}
git submodule update --init --recursive
git show --stat
REPO_SHA=`git log --oneline --pretty="format:%H" -1`

echo  ============================================ prepare ${ZIP_FILE}
if [[ -e ${ZIP_SRCD} ]] ; then rm -rf ${ZIP_SRCD} ; fi
mkdir -p ${ZIP_SRCD}

cd ${BASE_DIR}

# Temporary solution to download prebuilt sqlcipher from couchbaselab
if [[ -e ${SQLCIPHER} ]] ; then rm -rf ${SQLCIPHER} ; fi
git clone https://github.com/couchbaselabs/couchbase-lite-libsqlcipher.git ${SQLCIPHER}
cd ${SQLCIPHER}
git checkout ${LIBSQLCIPHER_BRANCH}
git pull origin ${LIBSQLCIPHER_BRANCH}
cd ${BASE_DIR}
if [[ ! -e ${LIB_SQLCIPHER_DEST} ]] ; then mkdir -p ${LIB_SQLCIPHER_DEST} ; fi
cp ${LIB_SQLCIPHER} ${LIB_SQLCIPHER_DEST}

echo "Building target=${OS} ${SDK}"
XCODE_CMD="xcodebuild CURRENT_PROJECT_VERSION=${BLD_NUM} CBL_VERSION_STRING=${CBL_VERSION} CBL_SOURCE_REVISION=${REPO_SHA}"
echo "using command: ${XCODE_CMD}"
echo "using command: ${XCODE_CMD}"                                          >>  ${LOG_FILE}
echo ============================================  ${OS} target: ${TARGET}
echo ============================================  ${OS} target: ${TARGET}	>>  ${LOG_FILE}

${XCODE_CMD} -scheme "${SCHEME}" -configuration "Release" -sdk "${SDK}" "RUN_CLANG_STATIC_ANALYZER=NO" "ONLY_ACTIVE_ARCH=NO" "BITCODE_GENERATION_MODE=bitcode" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" clean build 2>&1 >> ${LOG_FILE}

BUILD_DIR=`${XCODE_CMD} -scheme "${SCHEME}" -configuration "Release" -sdk "${SDK}" -showBuildSettings|grep -w BUILD_DIR|head -n 1|awk '{ print $3 }'`
BUILT_PRODUCTS_DIR=`${XCODE_CMD} -scheme "${SCHEME}" -configuration "Release" -sdk "${SDK}" -showBuildSettings|grep -w BUILT_PRODUCTS_DIR|head -n 1|awk '{ print $3 }'`
if [[ $OS =~ ios ]] || [[ $OS =~ tvos ]]
then
    BUILT_DOC_DIR="${BUILD_DIR}/Release-${SDK}/Documentation"
else
    BUILT_DOC_DIR="${BUILT_PRODUCTS_DIR}/Documentation"
fi

echo "Built Product Directory: ${BUILT_PRODUCTS_DIR}"
echo "Built Documentation Directory: ${BUILT_DOC_DIR}"

if  [[ -e ${LOGFILE} ]]
then
    echo
    echo "======================================= ${LOGFILE}"
    echo ". . ."
    tail  ${LOG_TAIL}                             ${LOGFILE} 
fi

# Documentation:
echo  ============================================ package ${DOC_ZIP_FILE}
DOC_LOG=${WORKSPACE}/doc_zip.log
if [[ -e ${DOC_LOG} ]] ; then rm -f ${DOC_LOG} ; fi
rm -rf "${DOC_ZIP_ROOT_DIR}"
mkdir -p "${DOC_ZIP_ROOT_DIR}"
mv "${BUILT_DOC_DIR}" "${DOC_ZIP_ROOT_DIR}"
pushd  "${DOC_ZIP_ROOT}"         2>&1 > /dev/null

echo  ============================================ creating ${DOC_ZIP_PATH}
( zip -ry ${DOC_ZIP_PATH} ${REVISION}  2>&1 )                                  >>  ${DOC_LOG}
if  [[ -e ${DOC_LOG} ]]
then
    echo
    echo "============================================ ${DOC_LOG}"
    echo ". . ."
    tail  ${LOG_TAIL}                             ${DOC_LOG}
fi
popd                        2>&1 > /dev/null

# Built Artifacts:
echo  ============================================== update ${ZIP_FILE}
cp  -R  "${BUILT_PRODUCTS_DIR}"/*        ${ZIP_SRCD}
cp       ${README_F}               ${RME_DEST}
cp       ${LICENSEF}               ${LIC_DEST}

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

# Stage OpenIDConnectUI for ios and macos
if [[ ${VERSION} == 0.0.0 ]] || [[ ${VERSION} > 1.2.0 ]]
then
    if [[ $OS =~ ios ]] || [[ $OS =~ macosx ]]
    then
        if [[ ! -e ${EXTRAS_DIR} ]] ; then mkdir -p ${EXTRAS_DIR} ; fi
        cp -rf ${OPENID_SRC} ${EXTRAS_DIR}
    elif [[ $OS =~ tvos ]]
    then
        if [[ -e ${EXTRAS_DIR}/OpenIDConnectUI ]] ; then rm -rf ${EXTRAS_DIR}/OpenIDConnectUI  ; fi
    fi
fi

# Postprocessing:
cd ${ZIP_SRCD}
rm -rf ${ZIP_SRCD}/*.a
rm -rf ${ZIP_SRCD}/*.bcsymbolmap
rm -rf *.dSYM
rm -rf ${ZIP_SRCD}/*LinkMap*
rm -rf CouchbaseLite.framework/PrivateHeaders

# Zip:
echo  ============================================== package ${ZIP_PATH}
ZIP_LOG=${WORKSPACE}/doc_zip.log
if [[ -e ${ZIP_LOG} ]] ; then rm -f ${ZIP_LOG} ; fi

cd         ${ZIP_SRCD}
( zip -ry   ${ZIP_PATH} *  2>&1 )                                              >>  ${ZIP_LOG}
if  [[ -e ${ZIP_LOG} ]]
    then
    echo
    echo "============================================ ${ZIP_LOG}"
    echo ". . ."
    tail  ${LOG_TAIL}                             ${ZIP_LOG}
fi

LATESTBUILDS_CBL=http://latestbuilds.hq.couchbase.com/couchbase-lite-ios/${VERSION}${REL_STAGE}/${OS}/${REVISION}
echo        ........................... uploading internally to ${LATESTBUILDS_CBL}
echo ============================================== `date`
