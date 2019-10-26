pipeline {
    agent { label 'mobile-builder-ios-pull-request'  }
    environment {
       PRODUCT = 'couchbase-lite-ios-ee'
   }
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
                    git clone https://github.com/couchbaselabs/${env.PRODUCT}.git --branch $CHANGE_TARGET

		    # restructure folders
		    mv couchbase-lite-ios-ee/* .
		    mv tmp/* couchbase-lite-ios
		    
		    # submodule update inside lite-ios
		    pushd couchbase-lite-ios
                    git submodule update --init --recursive
		    popd

		    # update the lite-core-EE
		    pushd couchbase-lite-core-EE
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
		    pwd
		    ls
		    git rev-parse HEAD

		    pushd couchbase-lite-ios
		    ls
		    git rev-parse HEAD
		    git log --graph --full-history --all --pretty=format:"%h%x09%d%x20%s"
		    popd

		    cat couchbase-lite-ios/Scripts/pull_request_build.sh
		    ./couchbase-lite-ios/Scripts/pull_request_build.sh
                """
            }
        }
    }
}
