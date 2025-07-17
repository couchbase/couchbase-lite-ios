#!/bin/bash -e

# This script creates a C header "repo_version.h" with string constants that
# contain the current Git status of the repo.

OUTPUT_FILE="$DERIVED_FILE_DIR/repo_version.h"

GIT_BRANCH=`git rev-parse --symbolic-full-name HEAD | sed -e 's/refs\/heads\///'`
GIT_COMMIT=`git rev-parse HEAD || true`
GIT_DIRTY=$(test -n "`git status --porcelain`" && echo "+CHANGES" || true)

# EE repo info (if exists)
TOP=`git rev-parse --show-toplevel`
EE_DIR="$TOP/../couchbase-lite-ios-ee"
if [[ -d "$EE_DIR" ]]; then
  pushd "$EE_DIR" > /dev/null
  GIT_BRANCH_EE=`git rev-parse --symbolic-full-name HEAD | sed -e 's/refs\/heads\///'`
  GIT_COMMIT_EE=`git rev-parse HEAD || true`
  GIT_DIRTY_EE=$(test -n "`git status --porcelain`" && echo "+CHANGES" || true)
  popd > /dev/null
else
  GIT_BRANCH_EE=""
  GIT_COMMIT_EE=""
  GIT_DIRTY_EE=""
fi

echo "static const char* const GitCommit = \"$GIT_COMMIT\"; " \
     "static const char* const GitBranch = \"$GIT_BRANCH\"; " \
     "static const char* const GitCommitEE = \"$GIT_COMMIT_EE\"; " \
     "static const char* const GitBranchEE = \"$GIT_BRANCH_EE\"; " \
     >"$OUTPUT_FILE".tmp

if cmp --quiet "$OUTPUT_FILE" "$OUTPUT_FILE".tmp
then
	rm "$OUTPUT_FILE".tmp
#echo "get_repo_version.sh: Leaving $OUTPUT_FILE unchanged"
else
	mv "$OUTPUT_FILE".tmp "$OUTPUT_FILE"
	echo "get_repo_version.sh: Updated $OUTPUT_FILE"
fi
