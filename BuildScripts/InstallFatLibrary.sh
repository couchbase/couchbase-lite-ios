#!/bin/sh

#  InstallFatLibrary.sh
#  CouchbaseLite
#
#  Created by Jens Alfke on 3/23/16.
#  Copyright © 2016 Couchbase, Inc. All rights reserved.

SRC="${UNIVERSAL_BUILD_DIR}/${EXECUTABLE_PATH}"
DST="${DSTROOT}/${INSTALL_PATH}/${EXECUTABLE_PATH}"

# Install universal build to the target's build directory (important during Archive builds):
if [ -e "${SRC}" ]
then
    echo "Installing universal ${EXECUTABLE_PATH} to ${DST}"
    cp "${SRC}" "${DST}"
fi
