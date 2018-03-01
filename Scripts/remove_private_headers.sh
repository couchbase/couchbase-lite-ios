#!/bin/bash

set -e

MODULE_MAP_FILE=${TARGET_TEMP_DIR}/module.modulemap
FRAMEWORK_DIR=${TARGET_BUILD_DIR}/${PRODUCT_NAME}${WRAPPER_SUFFIX}

# Remove private headers from module.modulemap file:
perl -i -0pe "s/module Private {[\s\S]*?}/module Private { }/" "${MODULE_MAP_FILE}"

# Remove PrivateHeaders folder:
rm -rf "${FRAMEWORK_DIR}/PrivateHeaders"
