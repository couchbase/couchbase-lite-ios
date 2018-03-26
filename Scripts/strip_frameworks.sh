#
#  strip_frameworks.sh
#  CouchbaseLite
#
#  Copyright (c) 2017 Couchbase, Inc All rights reserved.
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#
#
# Run this script in the app target's Run Script Phase to strip non-valid
# architecture types from dynamic frameworks and dSYM files.
#
# If the app project installs Couchbase Lite framework manually,
# this is required for archiving the app for submitting to the app store.
# See http://www.openradar.me/radar?id=6409498411401216 for more detail.
#

# Strip non-valid archecture types from the given universal binary file.
strip() {
    i=0
    archs="$(lipo -info "$1" | cut -d ':' -f3)"
    for arch in $archs; do
        if ! [[ "${VALID_ARCHS}" == *"${arch}"* ]]; then
            lipo -remove "${arch}" -output "$1" "$1" || exit 1
            i=$((i + 1))
        fi
    done
    
    if [[ ${i} > 0 ]]; then
        archs="$(lipo -info "$1" | cut -d ':' -f3)"
        echo "Stripped $1 : ${archs}"
        return 0
    else
        return 1
    fi
}

# Go to frameworks folder:
cd "${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}"

# Strip frameworks:
dsyms_files=()
for file in $(find . -type f -perm +111 | grep ".framework"); do
    if ! [[ "$(file "${file}")" == *"dynamically linked shared library"* ]]; then
        continue
    fi

    strip "${file}"
    if [[ $? == 0 ]]; then
        # Code sign the stripped framework:
        if [ "${CODE_SIGNING_REQUIRED}" == "YES" ]; then
            echo "Sign ${file}"
            codesign --force --sign ${EXPANDED_CODE_SIGN_IDENTITY} --preserve-metadata=identifier,entitlements "${file}"
        fi

        bin_name="$(basename "${file}")"
        dsyms_files+=(${BUILT_PRODUCTS_DIR}/${bin_name}.framework.dSYM/Contents/Resources/DWARF/${bin_name})
    fi
done

# Strip dSYM files:
for file in $dsyms_files; do
    if [[ -e "${file}" ]]; then
        strip "${file}" || true
    fi
done
