#!/bin/bash -e
#
# This script is invoked by the "Documentation" target of the XCode project.
# It uses these XCode build variables:
# 
#    DERIVED_FILE_DIR  --  where the doc files are generated
#    TARGET_BUILD_DIR  --  where the doc set ends up
# 
# so it won't work if run standalone unless you define those environment variables first.

export DOCSET_BUNDLE_ID="com.couchbase.CouchbaseLite"             # Used by the Doxyfile
DOCSET_FILENAME="$DOCSET_BUNDLE_ID.docset"

# First remove the old docs
rm -rf "$TARGET_BUILD_DIR/Documentation"
rm -rf "$TARGET_BUILD_DIR/$DOCSET_FILENAME"

if [ "$ACTION" == 'clean' ]
then
    # Just cleaning? Then we're done
    exit 0
fi

# doxygen is a 3rd party tool and often installed in /usr/local/bin
# You can install it via HomeBrew with "brew install doxygen"
# or download it from http://www.stack.nl/~dimitri/doxygen/download.html

PATH=$PATH:/usr/local/bin
if ! /usr/bin/which -s doxygen
then
    echo "$0:29 Error: doxygen is not installed" >&2
    exit 1
fi

# Generate regular HTML docs:

export DOXY_OUTPUT_DIRECTORY="$DERIVED_FILE_DIR/Documentation"    # Used by the Doxyfile
mkdir -p "$DOXY_OUTPUT_DIRECTORY"
doxygen "Documentation/Doxyfile"
mkdir -p "$TARGET_BUILD_DIR"
mv -f "$DOXY_OUTPUT_DIRECTORY/html" "$TARGET_BUILD_DIR/Documentation"


# Generate XCode- and Dash-compatible DocSet bundle:
if [[ -e "/Applications/Xcode.app/Contents/Developer/usr/bin/docsetutil" ]]; then
    export DOXY_OUTPUT_DIRECTORY="$DERIVED_FILE_DIR/DocSet"
    mkdir -p "$DOXY_OUTPUT_DIRECTORY"
    doxygen "Documentation/Doxyfile-DocSet"
    (cd "$DOXY_OUTPUT_DIRECTORY/html" && make)                     # postprocess Doxygen output to create docset
    DOCSET="$DOXY_OUTPUT_DIRECTORY/html/$DOCSET_FILENAME"
    cp "Documentation/logo-small.png" "$DOCSET/icon.png"
    mv -f "$DOCSET" "$TARGET_BUILD_DIR/$DOCSET_FILENAME"
fi
