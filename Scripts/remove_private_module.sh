#!/bin/bash

set -e

FRAMEWORK_DIR=${TARGET_BUILD_DIR}/${PRODUCT_NAME}${WRAPPER_SUFFIX}

# Remove private headers from module.private.modulemap:
echo "framework module CouchbaseLiteSwift_Private { }" > "${FRAMEWORK_DIR}/Modules/module.private.modulemap"

# Remove PrivateHeaders folder:
rm -rf "${FRAMEWORK_DIR}/PrivateHeaders"
