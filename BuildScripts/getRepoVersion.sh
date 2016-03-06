#!/bin/bash -e

# This script creates a C header "repo_version.h" with string constants that
# contain the current Git status of the repo.

OUTPUT_FILE="$DERIVED_FILE_DIR/repo_version.h"

GIT_BRANCH=`git rev-parse --symbolic-full-name HEAD | sed -e 's/refs\/heads\///'`
GIT_COMMIT=`git rev-parse HEAD`
GIT_DIRTY=$(test -n "`git status --porcelain`" && echo "+CHANGES" || true)

echo "static const char* const GitCommit = \"$GIT_COMMIT\"; " \
     "static const char* const GitBranch = \"$GIT_BRANCH\"; " \
     "static const char* const GitDirty  = \"$GIT_DIRTY\";" \
     >"$OUTPUT_FILE".tmp

if cmp --quiet "$OUTPUT_FILE" "$OUTPUT_FILE".tmp
then
	rm "$OUTPUT_FILE".tmp
#echo "getGitVersion.sh: Leaving $OUTPUT_FILE unchanged"
else
	mv "$OUTPUT_FILE".tmp "$OUTPUT_FILE"
	echo "getGitVersion.sh: Updated $OUTPUT_FILE"
fi
