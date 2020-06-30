pipeline {
    agent { label 'mobile-builder-ios-pull-request'  }
    stages {
        stage('Checkout'){
            steps {
                sh """
                    #!/bin/bash
                    set -e
                    shopt -s extglob dotglob

		    # move PR related repo to tmp folder
		    mkdir tmp
                    mv !(tmp) tmp

		    # Sometimes the PR depends on a PR in the EE repo as well. This needs to be convention based, so if there is a branch with the name PR-###
                    # (with the GH PR number) in the EE repo then use that, otherwise use the name of the target branch (master, release/XXX etc) 
		    # clone the EE-repo
                    git clone git@github.com:couchbaselabs/couchbase-lite-ios-ee.git --branch $BRANCH_NAME || \
		      git clone git@github.com:couchbaselabs/couchbase-lite-ios-ee.git --branch $CHANGE_TARGET

		    # clone the core-EE
		    pushd couchbase-lite-ios-ee
		    git clone git@github.com:couchbase/couchbase-lite-core-EE.git --branch $BRANCH_NAME || \
		      git clone git@github.com:couchbase/couchbase-lite-core-EE.git --branch $CHANGE_TARGET
		    popd

		    # restructure folders
		    mv couchbase-lite-ios-ee/* .
		    rm -rf couchbase-lite-ios && mv tmp couchbase-lite-ios
		    
		    # submodule update inside lite-ios
		    pushd couchbase-lite-ios
                    git submodule update --init --recursive
		    popd

		    # remove tmp folders
		    rmdir couchbase-lite-ios-ee
		    
		    ./Scripts/prepare_project.sh
                """
            }
        }
        stage('Build'){
            steps {
                sh """ 
		    ./couchbase-lite-ios/Scripts/pull_request_build.sh
                """
            }
        }
    }
}
