#!/bin/bash

set -e

# Only strip the private module from Release builds used for packaging.
# Development (Debug) builds must keep the full private modulemap in the built
# framework; the Xcode indexer resolves CouchbaseLiteSwift_Private from the
# built products, and stripping it there makes all private Obj-C classes
# unresolvable in the editor.
case "${CONFIGURATION}" in
    Release*) ;;
    *)
        echo "Skipping private module removal for configuration '${CONFIGURATION}'"
        exit 0
        ;;
esac

FRAMEWORK_DIR=${TARGET_BUILD_DIR}/${PRODUCT_NAME}${WRAPPER_SUFFIX}

# Remove private headers from module.private.modulemap:
echo "framework module CouchbaseLiteSwift_Private { }" > "${FRAMEWORK_DIR}/Modules/module.private.modulemap"

# Remove PrivateHeaders folder:
rm -rf "${FRAMEWORK_DIR}/PrivateHeaders"
