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
                    git clone https://github.com/couchbaselabs/couchbase-lite-ios-ee.git --branch $CHANGE_TARGET
		    # submodule update inside lite-ios
		    pushd couchbase-lite-ios-ee
                    git submodule update --init --recursive
		    popd

		    # restructure folders
		    mv -v couchbase-lite-ios-ee/* .
		    mv -vf tmp/* couchbase-lite-ios/
		    
		    # submodule update inside lite-ios
		    pushd couchbase-lite-ios
                    git submodule update --init --recursive
		    popd

		    # remove unnecessary folders
		    rmdir tmp
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
