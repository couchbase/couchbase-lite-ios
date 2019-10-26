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

		    mkdir tmp
                    mv !(tmp) tmp
                    git clone https://github.com/couchbaselabs/${env.PRODUCT}.git --branch $CHANGE_TARGET
		    mv couchbase-lite-ios-ee/* .
		    mv tmp/* couchbase-lite-ios
		    
		    pushd couchbase-lite-ios
                    git submodule update --init --recursive
		    popd
		    rmdir tmp
		    rmdir couchbase-lite-ios-ee
		    
		    ./Scripts/prepare_project.sh
                """
            }
        }
        stage('Build'){
            steps {
                sh """ ./${env.PRODUCT}/couchbase-lite-ios/Scripts/pull_request_build.sh
                """
            }
        }
    }
}
