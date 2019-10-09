pipeline {
    agent { label 'mobile-builder-ios-pull-request'  }
    environment {
       PRODUCT = 'couchbase-lite-ios-ee'
   }
    stages {
        stage('Checkout'){
            steps {
                sh """
                    git clone https://github.com/couchbaselabs/${env.PRODUCT}.git
                    pushd ${env.PRODUCT}
                    git submodule update --init --recursive
                    ./Scripts/prepare_project.sh
                    cd couchbase-lite-ios
		    git checkout master
		    git pull origin master
                    popd
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
