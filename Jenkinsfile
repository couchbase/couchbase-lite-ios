pipeline {
    options {
        disableConcurrentBuilds() 
    }
    environment {
       PRODUCT = 'couchbase-lite-ios'
    }
    agent { label 'mobile-builder-ios-pull-request'  }
    stages {
        stage('Cleanup'){
            steps {
                sh """
                    #clean up DerivedData and tmp directories
                    #shutdown all simulators, in case if any device in "booted" state which doesn't allow data file to be deleted.
                    xcrun simctl shutdown all
                    xcrun simctl erase all
                    rm -rf ~/Library/Developer/Xcode/DerivedData/*
                    rm -rf /tmp/Developer/CoreSimulator
                    rm -rf /tmp/com.apple.mobileassetd
                    rm -rf /tmp/com.apple.launchd*
                    rm -rf /tmp/com.apple.CoreSimulator*
                """
            }
        }
        stage('Checkout'){
            steps {
                sh """
                    #!/bin/bash
                    set -e
                    shopt -s extglob dotglob

                    # move PR related repo to tmp folder
                    mkdir tmp
                    mv !(tmp) tmp

                    # Sometimes the PR depends on a PR in the EE repo as well. It will look for a branch with the same name as the one in CE repo. If not found, use the name of the target branch (master, release/XXX etc) 
                    # clone the EE-repo
                    git clone git@github.com:couchbaselabs/couchbase-lite-ios-ee.git --branch $CHANGE_BRANCH || \
                    git clone git@github.com:couchbaselabs/couchbase-lite-ios-ee.git --branch $CHANGE_TARGET

                    # submodule update for core-EE
                    pushd couchbase-lite-ios-ee
                    git submodule update --init couchbase-lite-core-EE
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
		            ./${env.PRODUCT}/Scripts/pull_request_build.sh
                """
            }
        }
    }
}
